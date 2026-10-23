# simple_live_tv_app 架构与选型对照

> 锚点：future `52466f96`（2026-10-21）｜TV v1.5.1+10501
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/architecture.md)｜对照：[simple_live_app](../../simple_live_app/doc/architecture.md)

## 1. 分层

| 层 | 位置 | 职责 |
| --- | --- | --- |
| 宿主 | `lib/main.dart` | RustLib 初始化、横屏/全屏、服务注册 |
| 路由 | `lib/routes/` | GetX 路由、导航封装 |
| 模块 | `lib/modules/` | home/hot_live/category/search/follow/history/live_room/settings/sync/qr_login |
| 组件 | `lib/widgets/` | `HighlightWidget`（焦点/按键）、卡片、空错加载态 |
| 服务 | `lib/services/` | LocalStorage/DB/Sync/SignalR/Platform/Migration/FollowUser |
| 模型 | `lib/models/` | Hive `follow_user`/`history`/`account` |
| 数据源 | `lib/app/sites.dart` | 4 个 `Rust*Site`（无 twitch） |

依赖方向：`modules → widgets/services → app/sites → simple_live_core`；core 不反向依赖。

## 2. 模块清单

| 模块 | 控制器 | 职责 |
| --- | --- | --- |
| home | `home_controller` | 大按钮导航 + 关注区 |
| hot_live | `hot_live_controller` | 各平台推荐瀑布流 |
| category(+detail) | `category_controller` | 平台类目/子类房间 |
| search/{room,anchor} | 各自 controller | 搜房间/主播 |
| follow_user | `FollowUserService` | 关注卡片、开播状态 |
| history | `history_controller` | 本地观看记录 |
| live_room | `live_room_controller` + `player/` | 取流/播放/弹幕/切台 |
| settings | `settings_controller` | 播放/弹幕/关注/账号/关于 |
| sync | `sync_controller` | HTTP + UDP + SignalR 接收端 |
| qr_login | `qr_login_controller` | B站/斗鱼通用扫码 |

## 3. 状态与依赖注入

- GetX：`GetxController` + `.obs`/`Obx`；`Get.put` 注册全局服务，路由 `BindingsBuilder` 注册页面控制器。
- 基类：`BaseController`（加载/空/错误/未登录）、`BasePageController<T>`（分页、EasyRefresh、滚动）。
- 跨页信号：自研 `EventBus`（`kUpdateFollow`/`kUpdateHistory`）。
- 非 Provider/Riverpod/Bloc（`pubspec.yaml` 无这些依赖）。

## 4. 关键技术选型

| 选择 | 现状 | 对照/理由 |
| --- | --- | --- |
| 状态/路由/DI | GetX `^4.7.2` | 与手机端同构，启动期注册简单 |
| 协议/取流 | `simple_live_core`（path）+ **Rust FFI** | `main.dart:29` `RustLib.init()`；`sites.dart` 直连 `Rust*Site`；TV 不再有 Dart 协议实现 |
| 播放 | `media_kit ^1.2.1` + `media_kit_video ^1.3.1`（pub 版） | 手机端用自建 fork；TV 未跟（见 backlog P1-3） |
| 存储 | `hive 2.2.3`（非 hive_ce） | 手机端已迁 hive_ce；TV 保持旧版 |
| 弹幕 | `canvas_danmaku ^0.3.3` | 只读展示，无发送 |
| 大屏适配 | `flutter_screenutil` 1920×1080 | 全部 `.w` 缩放 |
| 焦点 | `AppFocusNode` + `HighlightWidget` | 方向键默认空间导航，确认键即点击 |
| 同步 | shelf + udp + signalr_netcore | TV 只做接收端 |

## 5. 与手机端的关系

| 维度 | TV | App |
| --- | --- | --- |
| 共享代码 | 只共享 `simple_live_core` | 同左 |
| 协议路径 | Rust FFI（`RustLib.init`） | Rust FFI |
| media_kit | pub 版 | 自建 fork（git 锁 ref） |
| Hive | `hive` 2.2.3 | `hive_ce` |
| 功能 | 无多开/后台播放/PIP/WebDAV/弹幕发送/twitch | 全有 |
| Flutter | 3.35.7 | 3.47.6 |

## 6. 设计取舍与风险

- **无触屏**：只做焦点导航；弹幕只读；不做软键盘输入。
- **无后台播放/小窗**：TV 常亮横屏。
- **同步只做接收端**：由手机推送。
- **风险**：焦点节点在 `build` 内新建（backlog P0-1）；分页不采信 `hasMore`（P1-1）；账号同步后不即时刷新（P1-2）；测试资产为空。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| 直连 Rust 绑定层 | `2465f9a3` |
| Hive Account + PlatformService | `6da36e04` |
| 账号校验不抹凭证 | `63197f69` |
