# simple_live_app 架构与选型对照

> 锚点：future `c1dd7769`（2026-10-26）｜App v1.8.15+10815｜Flutter 3.47.8
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/architecture.md)｜播放：[media-kit](../../media-kit/doc/architecture.md)

## 1. 模块全景

```
lib/
├── main.dart                 # 启动队列、主题/路由、全局手势
├── app/                      # 设置、基类、EventBus、工具、站点表
├── modules/                  # indexed/home/category/search/live_room(+player,multi_play)
│                             # follow_user/mine/settings/sync
├── services/                 # 存储/DB/账号/关注/同步/窗口/后台播放/续流
├── widgets/ routes/ models/ requests/
├── spike/                    # 多开性能探针（一次性）
└── test/                     # 70 个 *_test.dart
```

## 2. 分层

| 层 | 职责 | 依赖 |
| --- | --- | --- |
| 宿主 | `main.dart` 初始化、主题、路由、全局手势 | → app/services |
| 模块 | `modules/*` 页面 + 控制器 | → app/services/widgets/core |
| 服务 | 全局单例（存储/DB/账号/同步/窗口/播放） | → app/models/core |
| 基础 | `app/`、`requests/`、`models/`、`widgets/` | → Dart/Flutter |
| 桥接 | core 的 FRB 绑定层 + `services/playback` | → 原生/系统 |

铁律：`services/` 不 import `modules/`；后台播放用 `LivePlaybackTarget` 抽象解耦。

## 3. 关键选型

| 选择 | 现状 | 理由/代价 |
| --- | --- | --- |
| 状态/DI/路由 | GetX `^4.7.3`，override 到 `SlotSun/get` | 一包三用；fork 的 `Get.put` **不覆盖存活实例**，多开副格必须带 tag |
| 依赖注入 | 启动期 `Get.put` + `Get.find` | 路径短；测试需 `Get.reset` |
| 跨模块信号 | 自研 `EventBus`（字符串事件） | 简单；无编译期校验，必须 cancel |
| 平台能力 | 纯函数 + 薄平台层 | `PipAspectCalculator`、`resolveMultiPlayLayout`、`resolveTileVolume`、`RoomWatchClock` 可单测 |
| 播放 | media-kit fork（`gaoxing64`，锁 `23ec6b9c`） | 需要自建 libmpv 的 loudnorm 等滤镜 |
| 协议 | `simple_live_core` Rust + FRB | 五平台统一；见 core KB |
| 持久化 | `hive_ce` 五箱 | 关注/历史/分组/屏蔽/账号 |
| 关注分组 | 真源 = `FollowUserTag.userId` 成员表 | 一个关注可属多组；`FollowUser.tag` 已删 |
| 搜索 | 按平台 Tab（默认）＋「聚合搜索」开关（默认关、持久化） | 聚合模式一个控制器并发打全平台：逐站分页、跨站去重、单站失败隔离、旧查询提前作废；「房间/主播」模式**只存 `AggregateSearchController` 一份**，页面 Rx 仅服务按平台路径 |

## 4. 服务层（要点）

| 服务 | 职责 |
| --- | --- |
| `local_storage_service` | Hive 设置/弹幕屏蔽键 |
| `db_service` | History/FollowUser/FollowUserTag/FollowUserBlock/account，墓碑清理 |
| `platform_service` | 账号校验、`setSiteAttrs`、UA/hlsFirst 下发 |
| `follow_service` | 关注轮询、快照、成员表读写、导入导出 |
| `smart_group_service` | 按平台一键分组（preview/execute，幂等） |
| `history_service` | 按房间计时，2 分钟落盘 |
| `sync_service` | UDP 发现 + HTTP 接收 |
| `window_service` | 窗口几何/置顶/标题栏（桌面） |
| `playback/*` | audio_service handler + 音频会话 + target 抽象 |
| `screen_awake_service` | 常亮按路引用计数，最后一个释放才熄屏 |
| `stream_relay/*` | 斗鱼直链续流（FLV tag 接续） |

## 5. 播放栈

```
media_kit_video（Video widget）→ media_kit（FFI）→ libmpv（fork 构建）
```

- 8 处引用钉到 `github.com/gaoxing64/media-kit@23ec6b9c`（含 libs override）。
- 官方 libmpv 不含 loudnorm；挂 `af` 会导致音频轨被禁（静音），故必须用 fork 二进制。
- 斗鱼直链经本地 `127.0.0.1` 中转，播放器无感。
- 直播缓存属性由顶层纯函数 `buildLiveCacheProperties({isAndroid, doubleBuffering, cacheSecs})` **一次性组表**，
  `initializePlayer` 只按表逐条 `setProperty`；绕过它的写入不会被测试覆盖。平台门闩是刻意的：
  **Android 且关双重缓冲时整表为空**（`cache-secs` 留在 mpv 默认值上，补写会静默改变手机端实际延迟）。
  预读秒数由 `PlayerMixin.resolvePlayerCacheSecs` 按站点解析，直播间覆写 Twitch＝`kTwitchPlayerCacheSecs`(10)。

## 6. Rust 桥

- `RustLib.init()` 在 `main.dart` 最早；`sites.dart` 五平台直连 `Rust*Site`。
- `DanmakuMask`（滑动窗口 + 分桶 + xxh3）做弹幕去重，每 500ms 批量判定，两种模式按批二选一：
  - 屏蔽模式 `allowListBatch`：受频控上限约束，超限的重复直接丢弃；
  - 合并模式 `mergeListBatch`：重复聚成一条并返回窗口计数（不看频控上限），聊天区原地更新「×N」，
    飘屏只在发射那一刻定稿计数（`canvas_danmaku` 不支持更新已发射项），后续重复只增长聊天区计数。
- FRB 2.13.0 两侧精确钉版；生成物入库。

## 7. 原生接线

| 平台 | 接线 |
| --- | --- |
| Android | `AudioService` 前台服务 + `MediaButtonReceiver`；`AudioServiceActivity`；PiP；Impeller 关 |
| Windows | `window_manager` + `win32`（几何/标题栏深浅） |
| Linux | 窗口关闭即退出；Wayland 下部分提示 no-op |
| macOS | 小窗用 Dart 拉回比例 |
| iOS | `UIBackgroundModes: audio` + `audio_session` playback；PiP 用 floating |

## 8. 已删除/迁出

- Dart 协议实现（34 文件/15k 行）、`simple_live_console` → `slive-cli`（2026-10-18）。
- FRB 资产/绑定层/`rust_builder` → `simple_live_core`（ADR-014）。
- `BiliBiliAccountService` → core 账号契约 + `PlatformService`。

## 9. 风险

1. **播放供应链单点**：音量均衡依赖 fork libmpv；换回上游即静音。
2. **GetX fork 行为**：多开副格 tag 是硬约束。
3. **续流是条件兜底**：直链寿命按 300s 假设，非所有线路成立。
4. **同步三套并存**：局域网/WebDAV/SignalR 语义未统一。
5. **测试基线**：存在历史红灯（见 test-suite）。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| Rust 全面接管、去掉运行时开关 | `73e80b1e`、`f72bb417` |
| 多开从「模式」改「动作」 | `afd18194` |
| 后台播放/系统媒体控制 | `e374b4df`、`5692db16`、`cd89ecdc`、`cbb474ee` |
| 关注多分组归属 | `3267a04e`、`a225e3b4`、`0442f4ac` |
| 屏幕常亮按路引用计数 | `900f8d50` |
| 关注页三栏 + 分组胶囊 | `1c0d02f5`、`55928d21` |
| 播放二进制指向自建 libmpv | `c3c6afc4` … `23ec6b9c`（media-kit 8 条） |
| 聚合搜索（默认关的开关 + 单一真值 + 失败隔离） | `446d613f`、`3624927b`、`8947bcdc` |
| Twitch 预读与缓存键值表可测化 | `0e99306a`、`c1dd7769` |
