# simple_live_app 架构与选型对照

> 版本锚点：`simple_live_app` v1.8.15+10815 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/workflow-diagram.md)

## 1. 模块全景

```
simple_live_app/
├── lib/main.dart                 # 启动：初始化队列 → runApp（见 workflow-diagram.md §1）
├── lib/app/                      # 应用地基：日志 / 风格 / 常量 / 站点表 / 事件总线 / 控制器基类
│   ├── controller/app_settings_controller.dart   # 全局设置（GetxController 单例，~1231 行）
│   ├── controller/base_controller.dart           # BaseController / BasePageController（分页收口）
│   ├── event_bus.dart  log.dart  utils.dart  sites.dart  constant.dart  app_style.dart
│   └── utils/                    # 扩展与纯工具（duration/hangdle/sandbox/dynamic_sort…）
├── lib/modules/                  # 页面模块（每个 = Controller + Page/View）
│   ├── indexed/                  # 首页壳（PageView 装 4 个 Tab）
│   ├── home/  category/  search/ # 列表三件套
│   ├── live_room/                # 直播间：controller + page + player/ + multi_play/
│   ├── follow_user/  mine/       # 关注 / 我的
│   ├── settings/                 # 设置页群（外观/播放/弹幕/屏蔽/快捷键/其他）
│   └── sync/                     # 同步页群（local_sync + remote_sync/webdav）
├── lib/services/                 # 全局服务（GetxService / 纯类），见 §4.3
├── lib/widgets/                  # 复用组件（35 个 dart：列表/网格/骨架/设置项/导航栏…）
├── lib/routes/                   # 路由表 + 导航封装 + 参数对象
├── lib/models/                   # Hive 模型（follow_user/history/follow_snapshot…）+ 枚举/账号模型
├── lib/requests/                 # App 自身 HTTP（dio 封装 + CustomLogInterceptor + HttpError）
├── lib/spike/                    # 多开性能探针（一次性脚本，见 §7）
├── android/ windows/ linux/ macos/ ios/   # 原生宿主
└── test/                         # 51 个测试文件（纯函数与 widget 为主）
```

## 2. 分层

| 层 | 职责 | 依赖方向 | 变更频率 |
| --- | --- | --- | --- |
| 宿主层 | `main.dart` 初始化队列、`MyApp`（主题/路由/全局手势） | → app/services | 低 |
| 模块层 | `modules/*` 页面与页面级 Controller | → app、services、widgets、core | 高（功能驱动） |
| 服务层 | `services/*` 全局单例（存储 / DB / 账号 / 同步 / 窗口 / 播放） | → app、models、core | 中 |
| 基础层 | `app/`（设置、事件总线、基类、工具）、`requests/`、`models/`、`widgets/` | → 仅 Dart/Flutter | 中 |
| 桥接层 | `simple_live_core/lib/src/{rust,bridge}`（FRB 生成物 + Dart 绑定层，随 core 包引入）、`services/playback`（audio_service 投影面） | → 原生/系统 | 低 |

**铁律**：`services/` 绝不 import `modules/`（会成环）。后台播放为此专门抽出 `LivePlaybackTarget` 抽象（`services/playback/live_playback_target.dart:1-13`），由 `modules/live_room` 侧实现。

## 3. 关键设计决策与对照

### 3.1 状态管理 = GetX（实测确认，非猜测）

- **证据**：`pubspec.yaml:23` `get: ^4.7.3`，且 `pubspec.yaml:130-134` 把 `get` 通过 `dependency_overrides` 指向 **`SlotSun/get` master**（上游自维护分支）。所有控制器 `extends GetxController`（`app/controller/base_controller.dart:9`；`app_settings_controller.dart:16`），状态用 `Rx* / .obs` + `Obx`。
- **选型理由**：一个包同时覆盖状态、依赖注入（`Get.put/Get.find`）与路由（`GetMaterialApp/getPages`），启动期一次性注册单例很自然。
- **代价**：fork 过的 `get` 行为与 pub.dev 版本有差异——`Get.put` **不覆盖已存活实例**，多开副格必须带 tag 注册（`live_room_controller.dart:97-102`），这是本仓库独有的坑。

### 3.2 依赖注入用 `Get.put/Get.find` 单例，不用 Provider/riverpod

- **现状**：全局服务在 `main.dart:109-149` 一次性 `Get.put`；各服务暴露 `static X get instance => Get.find<X>()`（如 `db_service.dart:13`）。页面级控制器走路由 `bindings` 的 `BindingsBuilder.put`（`routes/app_pages.dart:57-283`）或 `IndexedController.setIndex` 里惰性 `Get.put`（`indexed_controller.dart:257-287`）。
- **对照**：Provider/riverpod 的 `ProviderScope` 需要在 widget 树里重建依赖；本 App 用「启动期注册 + 全局 `Get.find`」，读写路径短，但测试隔离要手动 `Get.reset`。

### 3.3 跨模块信号用自研 `EventBus`（不是 GetX 的 `Get.snackbar` 类机制）

- **现状**：`EventBus`（`app/event_bus.dart:6-49`）是「名字 → 广播 StreamController」的字典，`emit/listen` 按字符串事件名。
- **用途**：底部导航点击、`kEscapePressed`、`kBackgroundPlayChanged`、`kVolumeNormalizeChanged`、`kPlayerMaxVolumeChanged`、`kOSDBackendChanged`。
- **代价**：字符串事件名无编译期校验；订阅者必须在 `onClose` 里 `cancel`（`live_room_controller.dart:1744-1746` 修过一次监听泄漏）。

### 3.4 平台能力按「纯函数 + 薄平台层」切分

`PipAspectCalculator`（小窗纵横比）、`resolveMultiPlayLayout`（多开排布）、`resolveTileVolume`（音量）、`RoomWatchClock`（观看计时）都是**无 IO/无平台**的纯算术或状态，可在 Dart VM 单测里扫边界；真正碰 `window_manager`/`MediaQuery` 的部分留在 `WindowService`/`PlayerController` 薄层。对应测试：`test/{pip_aspect,multi_play_layout,multi_play_volume,room_watch_clock}_test.dart`。

### 3.5 `AppSettingsController.onInit` 是 async（测试假件契约）

- **现状**：`AppSettingsController.onInit()` 返回 `Future<void>`（`app_settings_controller.dart:76`，`main.dart:117` 用 `await` 调），因为它要在 `initDataPath()` 里 `await getApplicationSupportDirectory()`。
- **契约**：任何覆写 `onInit` 的测试假设置（`FakeSettings` 等）**必须**声明为 `Future<void> onInit() async {}`；写成 `void onInit()` 会因签名不匹配**编译失败**（2026-10-12 同步时 6 个测试文件即栽在这里，见 update-history.md §2.3、test-suite.md §1）。
- **代价**：真实 `AppSettingsController` 在 widget test 里会撞 `path_provider` 的 `MissingPluginException`（无插件宿主）——测试必须用假设置跳过 `onInit`，不要构造真控制器（见 backlog P1）。

### 3.6 关注分组归属的唯一真源 = `FollowUserTag.userId` 成员表（2026-10-12 定稿）

- **现状**：一个关注可**同时属于多个分组**。真源只有一处——`FollowUserTag.userId`
  （`follow_user_tag.dart:16`）；读口 `FollowService.userTagNamesOf/userTagsOf`
  （`follow_service.dart:127-136`），写口 `addUserToTag`/`removeUserFromTag`/`removeAllTagsFromUser`
  （`:148-181`，哨兵 `'全部'` = 移出所有分组）。旧的 `FollowUser.tag` 字段（曾兼职「主分组」）
  已整条删除（`3267a04e`，breaking）。
- **代价与对策**：`groupedView` 每次重建都要遍历所有成员表建 `userId → 分组 id[]` 桶
  （`follow_user_controller.dart:147-180`）——几百关注 × 几十分组时未做缓存，
  计划文档「已知风险」第 3 条明确记为「本计划不做」。
- **写侧约定**：`addUserToTag` **刻意不排序**（批量归组每条都重排就是 O(N² log N)），
  排序交调用方在一批操作后做一次（`follow_service.dart:138-147` 注释、
  `follow_user_controller.dart:322`）。新测试若直连 service 批量写，记得补一次 `liveListSort()`。
- **对外兼容**：备份导出同带 `tag`（旧版本只认它，值由真源派生）与 `tags` 数组
  （`follow_service.dart:726-748`）；WebDAV 按**分组名并集**合并成员表而非覆盖
  （`follow_sync_resource.dart:99-133`）。两条承诺分别由
  `test/follow_membership_test.dart` 的「备份向后兼容」与「WebDAV 合并」两组用例钉住。
- **对照**：`simple_live_tv_app` 有独立 `FollowUser` 模型、无 tag 字段，本次改动**刻意不触及**
  （PR 说明「改动范围之外的库完全未动」）。

## 4. 目录分层细表

### 4.1 `lib/app`

| 文件 | 职责 |
| --- | --- |
| `controller/app_settings_controller.dart` | 全局设置单例：主题、弹幕、播放、多开、WebDAV、快捷键覆盖表…；`onInit` 从 Hive 回填 |
| `controller/base_controller.dart` | `BaseController`（错误/登录态）+ `BasePageController<T>`（分页、去重、`canLoadMore`） |
| `event_bus.dart` | 全局事件总线（§3.3） |
| `log.dart` | `Log` 静态门面（logger + debug 面板 + 文件写入 `LogFileWriter`） |
| `utils.dart` / `utils/*` | 版本解析、剪贴板、权限、`appBack`、排序/时长/沙箱等纯工具 |
| `sites.dart` | `Sites.allSites`（5 平台 `Site`）与 `Site` 结构 |
| `constant.dart` / `app_style.dart` / `app_scroll_behavior.dart` | 常量、Material3 主题、桌面滚轮平滑 |

### 4.2 `lib/modules`

| 模块 | 组成 |
| --- | --- |
| `indexed` | 首页壳 `IndexedPage` + `IndexedController`（PageView 惰性装页 + 顶/底栏收起） |
| `home` | `HomeController`（各平台 Tab）+ `HomeListController`（推荐流）+ `HomeListView/Page` |
| `category` | `CategoryController`（各平台 Tab）+ `CategoryListController` + `detail/` 分类详情 |
| `search` | `AppSearchController`（各平台 Tab + 关键词）+ `SearchListController` + `douyin/`（WebView 搜索，当前注释停用） |
| `live_room` | `LiveRoomController`（~1763 行，直播间全链路）+ `live_room_page.dart` + `player/` + `multi_play/` |
| `follow_user` | 关注页（**多分组归属**/标签/拖拽排序/选择态多开/一键按平台智能分组）+ 信息设置 + 关注设置 |
| `mine` | 我的 / `history/` / `account/`（平台账号列表 + `qr_login/` 扫码登录 + `bilibili/` Web 登录）/ `parse/`（工具箱） |
| `settings` | 外观 / 播放 / 弹幕 / 弹幕屏蔽 / 快捷键 / 首页 / 自动关闭 / 其他 |
| `sync` | `local_sync/`（设备发现/扫码）+ `remote_sync/webdav/`（资源+执行器） |
| `other` | `debug_log_page.dart`（DEBUG LOG 浮层） |

`live_room/player/` 子域：`player_controller.dart`（PlayerMixin/State/Danmaku/System/Gesture 五段 mixin）、`player_actions.dart`（动作清单）、`player_action_{bar,views,surfaces}.dart`（渲染器）、`player_shortcuts.dart` + `shortcut_binding.dart`（快捷键）、`pip_aspect.dart`、`danmaku_emoticon.dart`、`player_osd_*`。

### 4.3 `lib/services`（逐个）

| 服务 | 类型 | 职责 | 证据 |
| --- | --- | --- | --- |
| `local_storage_service.dart` | GetxService | Hive 两箱（`LocalStorage`/`DanmuShield`）读写，定义全部设置 key | `local_storage_service.dart:360-406` |
| `db_service.dart` | GetxService | 5 个 Hive 箱：History/FollowUser/FollowUserTag/FollowUserBlock/**account**；分组整表重建、墓碑清理 | `db_service.dart:13-177`（`accountBox:19`、`getAllAccounts:34`、`replaceAllFollowTags:72`、`cleanupTombstones:104`） |
| `platform_service.dart` | GetxService | **账号分流**：`accountList` 遍历 → core 各 `LiveSite.getAccountInfo` 校验 → `setSiteAttrs(jsonEncode(...))` 下发凭证；另下发抖音 hlsFirst / 虎牙 UA。`accountLogout` 同时清 `credential` 与 `userName`（上游 `5ae375f1` 批） | `platform_service.dart:21-138`（`accountLogout:41-50`、`accountLogin:52`、`setSiteAttrs:64`） |
| `follow_service.dart` | GetxService | 关注列表状态轮询（`Pool` 并发）、快照、休眠、**分组归属唯一真源的读写口**、导入导出 | `follow_service.dart:31-847`（归属 API `:127-181`、导出/导入 `:726-775`、数据校对 `:784-829`） |
| `smart_group_service.dart` | GetxService | **一键按平台智能分组**（2026-10-12 新增）：`preview` 只算不改给确认弹窗、`execute` 落库并统计；平台顺序先 `siteSort` 再补 `Sites.allSites`。**纯逻辑、可脱离 UI 单测** | `smart_group_service.dart:16-176`（`preview:20`、`execute:54`、`_orderedSiteIds:104`）；入口 `modules/follow_user/widgets/smart_group_preview_sheet.dart:199` |
| `history_service.dart` | GetxService | 按房间计时（`RoomWatchClock`）、2 分钟落盘、`EventBus` 回写关注 | `history_service.dart:62-198` |
| `follow_block_service.dart` | GetxService | 单直播间屏蔽账户/词的增删与导入导出 | `follow_block_service.dart:7-128` |
| `sync_service.dart` | GetxService | 局域网同步：UDP 23235 发现 + shelf HTTP 23234 收数据 | `sync_service.dart:25-449` |
| `window_service.dart` | GetxService | 窗口尺寸/位置记忆、小窗纵横比锁定、Windows 标题栏深浅色（win32） | `window_service.dart:18-725` |
| `firebase_service.dart` | GetxService | Android 侧 Analytics/Crashlytics 开关 | `firebase_service.dart:10-32` |
| `signalr_service.dart` | 纯类 | 「远程同步-房间」：连 `sync1.nsapps.cn` 建房/加房（QR），同步关注/历史/屏蔽词/账号 | `signalr_service.dart:14-131`；`modules/sync/remote_sync/room/remote_sync_room_controller.dart:21-57` |
| `core_api_service.dart` | 草稿 | `CoreApiBuilder` 命令式解耦 core 的**未完成草案** | `core_api_service.dart:1-123` |
| `migration_service.dart` | 纯类 | 按 DB 版本迁移 Hive 字段（`migrateDataByVersion`）；v1.8.16 的 tag→成员表一次性回填 `migrateTagMembership` 已随字段删除撤销（`:159-160` 留注） | `migration_service.dart:16-164`（`migrateDataByVersion:59`、账号迁移 `:102-157`） |
| `playback/live_playback_audio_handler.dart` | BaseAudioHandler | 投影到系统媒体控制面（通知/锁屏/耳机键） | `live_playback_audio_handler.dart:22-300` |
| `playback/live_audio_session.dart` | 单例类 | 音频会话：iOS `playback` 类别 / Android 焦点与中断 | `live_audio_session.dart:25-119` |
| `playback/live_playback_target.dart` | 抽象接口 | services↔modules 的唯一契约（防依赖环） | `live_playback_target.dart:13-50` |
| `stream_relay/stream_relay_service.dart` | GetxService | **斗鱼直链续流中转**（2026-10-16）：本地 `127.0.0.1` HTTP 服务（惰性启停），把带硬性寿命的直链包成对播放器不中断的一条流——到期前 5s 预取新流、旧流 EOF/超时后按 FLV tag 边界接续（丢文件头与初始化 tag、对齐关键帧、丢重复 GOP）；只有提供 `LivePlayUrl.renewers` 的线路（当前=斗鱼 flv）才走它 | `stream_relay_service.dart:26-106`（`register:71` / `release:83` / `shutdown:97`）、`_RelayPipe._pump:271`、`_schedulePrefetch:330`、`_forwardContinuation:435` |
| `stream_relay/flv_demuxer.dart` | 纯类 | 增量 FLV 解析（tag 类型/时间戳/关键帧/初始化 tag/失同步兜底）+ `FlvTimeline`（音视频分开记 last ts，「未落后于旧位置」才转发；相等时间戳也算未落后，避免丢真实流里同毫秒的帧）；零 IO、可直接单测 | `flv_demuxer.dart:54-215`（`FlvDemuxer:54`、`nextTag:128`、`FlvTimeline:183`、`isNotBehind:204`） |

### 4.4 `lib/widgets` / `lib/routes` / `lib/models` / `lib/requests`

- **widgets**：`page_list_view` / `page_grid_view`（列表基座，接 `AutoLoadOnScroll`）、`skeleton`、`live_room_card`、`keep_alive_wrapper`、`collapsible_top_bar_scaffold`、`settings/*`、`status/*`、`ui/*`。
- **routes**：`app_pages.dart`（GetPage 表）、`route_path.dart`（路径常量）、`app_navigation.dart`（带参导航封装）、`live_room_route_args.dart`（`LiveRoomRouteArgs`）、`app_analytics_observer.dart`。
- **models**：`db/follow_user.dart` + `.g.dart`（`followUserTag/history/follow_snapshot/follow_user_block/**account**` 同理，由 `hive_ce_generator` 生成）、`enum/danmaku_font_size_enum.dart`、`font(s)_model`、`version_model`。（旧的 `models/account/` 目录已随账号迁 core 删除。）
  `FollowUser` 的 `@HiveField(7) String tag` **已删除**（`follow_user.dart:50-53` 留注说明旧记录 field 7 读取时被忽略、旧版本 app 读新记录回退「全部」）；归属的唯一真源是 `FollowUserTag.userId` 成员表（`follow_user_tag.dart:16`，配套 `contains:53`/`addMember:56`）。
- **requests**：App 自身 dio 单例 `HttpClient`（20s 三超时 + `CustomLogInterceptor`，`http_client.dart:7-25`），错误收敛为 `HttpError`；另有 `common_request`/`sync_client_request`/`webdav_client`。
- **FRB 桥（2026-10-17 起位于 core 包）**：`simple_live_core/lib/src/rust/`（`frb_generated.dart` 生成物 + `api/danmaku_mask.dart` 的 `DanmakuMask`）+ `simple_live_core/lib/src/bridge/`（五平台 `Rust*Site` 绑定层，经 `simple_live_core.dart` 出口暴露）。App 侧 `import 'package:simple_live_core/simple_live_core.dart'` 即可用。

## 5. 路由方案

- 用 **GetX 声明式路由**：`GetMaterialApp(initialRoute: RoutePath.kIndex, getPages: AppPages.routes)`（`main.dart:235-236`）。
- `AppPages.routes`（`routes/app_pages.dart:55-283`）：每条 `GetPage` 挂 `bindings`，把 `Get.arguments` 解成控制器构造参数（如 `/room/detail` 读 `LiveRoomRouteArgs`，`:114-122`）。
- 带参跳转一律走 `AppNavigator`（`routes/app_navigation.dart:21-89`），路径常量集中在 `RoutePath`（`route_path.dart`）。
- **多开参数**统一收进 `LiveRoomRouteArgs{site, roomId, together}`（`live_room_route_args.dart:18-29`），`together` 是本 fork 新增。

## 6. 播放栈选型

```
video_player 接口层：video_player_media_kit（fork 内提供，给依赖官方 video_player 的插件用）
        ▲
media_kit_video（Video widget / VideoController）
        ▲
media_kit（Player / Playlist / NativePlayer → libmpv）
        ▲
media_kit_libs_*_video（各平台预编译 libmpv 产物）
```

- **全部走 fork**：`pubspec.yaml:99-160` 把 `media_kit` / `media_kit_video` / `media_kit_libs_video` 及 5 个平台 libs 全部钉到 **`github.com/gaoxing64/media-kit@23ec6b9c`**（`dependency_overrides` 里 6 个 libs 也一并指向它）。
- **为何 fork**：官方（Predidit）的「仅视频」libmpv 构建 ffmpeg `--disable-filters`，**不含 `loudnorm`/`dynaudnorm`**；挂载音量均衡的 `af` 链会导致音频轨被禁（静音）。fork 分支 `feat/audio-filters` 编入了这些滤镜，运行时仍保留「回读 + 自愈 + 重连」（`player_controller.dart:33-60,241-257` 挂载与回读；`live_room_controller.dart:901-908` 不可用时重连当前线路）。取证（已内联）：对官方构建产物做符号/字符串扫描，`loudnorm` 相关符号 0 命中（带阳性对照）。
- **供应链说明**：media-kit 的 fork **不是主仓库的一部分**——`git ls-files media-kit` 为 0、非 submodule（仓库根有一份独立 clone，非跟踪）。锁定的是**远程仓库 + 精确 commit**，bump 需同时改 8 处引用。
- **输入源在斗鱼上多一层本地中转**：mpv 拿到的不是 CDN 直链，而是 `StreamRelayService` 的 `127.0.0.1` 地址（仅对带 `LivePlayUrl.renewers` 的线路生效）。它只搬运字节、不改播放栈：到期前重新取流 + FLV tag 边界接续，见 §4.3 与 §11。

## 7. Rust 桥（flutter_rust_bridge 2.13.0）

- **用途**：弹幕**去重 + 频控** + **五平台站点能力**（bilibili/douyu/huya/douyin/twitch 全量迁移，见 `docs/decisions/ADR-014`）。`DanmakuMask`（`simple_live_core/src/api/danmaku_mask.rs`）用「滑动窗口 + 分桶 + xxh3 哈希」批量判重。
- **调用点**：`LiveRoomController._initDanmakuMask()` 按设置构造；`_processDanmakuBuffer()` 每 500ms 批调 `allowListBatch`，返回 `Vec<u8>`（1 允许 / 0 屏蔽，`simple_live_core/lib/src/rust/api/danmaku_mask.dart`）；换台 `reset()`、退出 `dispose()`。
- **站点分派**：`app/sites.dart` 五平台直连 `Rust*Site()`（`simple_live_core/lib/src/bridge/`）；2026-10-17 前为 `Constant.kUseRust*` 开关 + Dart/Rust 二元分派，回退窗口已关闭（ADR-008）。
- **生成方式**：`main.dart:70` `RustLib.init()`（符号经 core 库出口提供）；`pubspec.yaml` 路径依赖 `rust_lib_simple_live_app`（→ `../simple_live_core/rust_builder`）；`flutter_rust_bridge` / `freezed_annotation` 运行依赖在 core 包 pubspec。
- **来源**：上游提交 `1c4fbce7`/`f709a21c`（`SlotSun`）的 DanmakuMask；五平台迁移为本 fork 自研（决策链 `docs/decisions/`）。

## 8. 原生接线

| 平台 | 接线 | 证据 |
| --- | --- | --- |
| Android | 媒体**前台服务** `AudioService`（`foregroundServiceType=mediaPlayback`）+ `MediaButtonReceiver`（耳机键）+ 权限 `WAKE_LOCK`/`FOREGROUND_SERVICE_MEDIA_PLAYBACK`/`POST_NOTIFICATIONS`；`MainActivity : AudioServiceActivity`（保留同 FlutterEngine）；`supportsPictureInPicture=true`、Impeller 关、`extractNativeLibs=true` | `AndroidManifest.xml:7-71`；`MainActivity.kt:9` |
| Windows | `window_manager` 全窗口操作；`win32` 读 `GetWindowRect/GetClientRect/GetDpiForWindow` 量小窗 insets + `DwmSetWindowAttribute` 设标题栏深浅色；最大化/全屏还原点 `_captureNormalGeometry` | `window_service.dart:189-244,426-468`；`player_controller.dart:729-754` |
| Linux | `WindowService.onWindowClose → exit(0)`；小窗纵横比交 GDK 提示（Wayland 下为 no-op） | `window_service.dart:263-267,540-549,598-608` |
| macOS | 小窗走「纯 Dart 拉回比例（方案 B）」；`window_manager` 不调原生约束 | `window_service.dart:316-362,673-694` |
| iOS | `UIBackgroundModes: audio`（既有）+ `audio_session` 切 `playback` 类别；PiP 走 `floating` | `live_audio_session.dart:17-23` |
| Shorebird | **已配置**：`shorebird.yaml`（app_id 在列）+ `pubspec.yaml:197` 把 `shorebird.yaml` 打进 assets；来源上游 `d0c49269` | `shorebird.yaml:8` |
| Firebase | **仅 Android 启用**：`firebase_analytics/crashlytics/core` + `google-services.json` + `firebase_options.dart`；`main.dart:141-146` 仅 `Platform.isAndroid` 初始化 | `firebase_service.dart:1`（注释 "only for Android"） |

## 9. 依赖清单（`pubspec.yaml`）与用途

| 依赖 | 用途 | 可替代性 |
| --- | --- | --- |
| `get`（override→`SlotSun/get`） | 状态 / DI / 路由 | **低**（fork 行为差异已渗入多开） |
| `hive_ce`(+flutter/generator) | 本地持久化（设置/关注/历史） | 中 |
| `dio` | App 自身 HTTP（非 core 请求） | 中 |
| `media_kit` 系（git fork） | 播放内核 + Video widget + libmpv | **极低**（滤镜依赖 fork 构建） |
| `audio_service` 0.18.19 + `audio_session` 0.2.4 | 后台播放 / 系统媒体控制 / 音频会话 | 低（钉死精确版本；四条源码前提已内联在 backlog P0-2 与 [workflow-diagram.md](./workflow-diagram.md) §5） |
| `rust_lib_simple_live_app`（cargokit 插件，path → `../simple_live_core/rust_builder`） | Rust core 构建入口（弹幕去重 + 五平台站点）；`flutter_rust_bridge` 运行库由 core 包传递依赖 | 低 |
| `canvas_danmaku` | 弹幕渲染轨 | 中 |
| `easy_refresh` | 下拉刷新（footer 已被移除，仅刷新） | 中 |
| `extended_image` / `flutter_staggered_grid_view` | 图片缓存 / 瀑布流 | 中 |
| `window_manager` + `win32` + `ffi` | 桌面窗口与标题栏 | 高（平台专属） |
| `floating` | Android/iOS 画中画 | 中 |
| `flutter_inappwebview`（`guide-inc-org` fork） | B 站 Web 登录 / 抖音搜索（停用） | 中 |
| `webdav_client` + `shelf` + `shelf_router` | 远程 WebDAV 同步 / 局域网 HTTP 服务 | 中 |
| `udp` + `network_info_plus` | 局域网设备发现 | 中 |
| `signalr_netcore` | 房间式远程同步（`/remote_sync/room`：建房/加房，同步关注/历史/屏蔽词/账号） | 高 |
| `dynamic_color` / `material_new_shapes` / `lottie` | 动态取色 / M3 Expressive 形状 / 动画 | 高 |
| `fractional_indexing_dart` + `collection` | 标签 fractional id 排序 | 高 |
| `pinyin` + `pool` + `synchronized` | 关注罗马音排序 / 并发池 / 锁 | 高 |
| `qr_flutter` / `qr_code_scanner_plus` | 二维码（登录/同步） | 高 |
| `wakelock_plus` / `screen_brightness_*` / `volume_controller` / `auto_orientation_v2` | 常亮 / 亮度 / 音量 / 方向 | 高 |
| `permission_handler_android/_apple/_platform_interface`（拆包） | 权限（主包被注释停用） | 中 |

## 10. fork 与上游的差异（future vs fork-parent/dev）

| 差异 | fork 实现 | 上游行为 | 提交 |
| --- | --- | --- | --- |
| **多开从「模式」改「动作」** | 关注行只显示「加入」icon，关格子去网格 ✕；新增批量入口 `together`/`addRooms` | 只有「模式 + 替换当前房间」一条路径 | `afd18194`→`3714eec1` |
| **后台播放 + 系统媒体控制** | `services/playback/` 三件套 + Android 前台服务 + 原生接线 | 无（仅有"进后台不暂停"的默认） | `5692db16`/`cd89ecdc`/`e374b4df`/`cbb474ee` |
| **音量均衡 + 最大音量** | loudnorm `af` 链 + `volume-max`，并 fork media-kit 补滤镜 | 无；官方内核缺滤镜 | `dec20731` |
| **多开性能探针** | `lib/spike/multi_player_spike.dart`（一次性，未合入语义） | 无 | `c08d7914` |
| **播放器快捷键可改键** | `shortcut_binding.dart` + 覆盖表 + `player_shortcuts.dart` 执行层 | 无 | `12ab0c42` |
| **关注多分组归属 + 一键按平台智能分组** | 归属唯一真源 = `FollowUserTag.userId` 成员表（一个关注可同时进多个组，`FollowUser.tag` 已删）；`SmartGroupService` 按平台归组（复用同名组、幂等）；备份带 `tags` 数组、WebDAV 按分组名**并集**合并 | 一个关注只有一个 `FollowUser.tag`（单选），无按平台批量归组；WebDAV 按分组覆盖 | `7c895e6d`…`3b86b496` 共 11 条（见 update-history.md §2.4；权威设计 `specs/2026-10-12-multi-membership-and-smart-grouping-plan.md`） |
| 首页顶/底栏收起、PageView 惰性装页 | `IndexedController` 自研 | 差异实现 | — |

> 说明：`gaoxing64` = 本 fork 作者，`SlotSun`/`Slot` = 上游作者。近期 50 条提交（`git log -50 future`）
> 中 `gaoxing64` **31** 条——其余是 2026-10-12/10-14 两次同步批带进来的上游提交。

## 11. 已知取舍与风险

- **`get` 用 fork**：`Get.put` 不覆盖已存活实例，多开副格靠 tag 规避（`live_room_controller.dart:97-102`）；升级 pub 版会静默改变覆盖语义。
- **播放内核靠 fork 构建**：音量均衡/未来滤镜都绑在 `gaoxing64/media-kit@23ec6b9c` 上，供应链单点；本仓库 `media-kit/` 只是本地 clone（未跟踪）。
- **续流中转是有条件的兜底，不是「无缝」保证**（§4.3 `stream_relay/*`）：直链寿命按 300s 假设——**实测并非所有线路都成立**（`hw1a` 线路 335s 未断，URL 自带 `expire=0`），中继对「不断」的线路只是挂一条预取连接、30s 后放弃，退化为直通。旧流真断时：预取已就绪 → 接续间隔 ~0.2-0.6s；预取没赶上（走到期早于假设）→ 同步补取，实测到达间隔 ~1.6s（重取接口 + 建连 + 等关键帧）。FLV 解析失同步、时间轴重置（主播重开播）都会放弃接续、把响应关掉交回 `mediaEnd/mediaError` 重试。
- **`core_api_service.dart` 是草稿**：`CoreApiBuilder` 自述「暂备份为草稿」（`core_api_service.dart:120-123`），无调用点——待确认是否清理。
- **同步有三套并存**：局域网 `SyncService`（UDP+HTTP，在用）、远程 WebDAV（资源+执行器）、SignalR 房间同步（`/remote_sync/room`，另有 `mine_page.dart:213` 的 `kDebugMode` 测试入口）——三者语义未统一。
- **`permission_handler` 主包被注释**（`pubspec.yaml:67`），改用三拆分包 + 平台判断，权限请求路径需按平台复核。
- **`lib/spike/multi_player_spike.dart` 是实验脚本**，头部注明「一次性脚本，验证完就删（不要合入）」（`:1-3`）。
- 关注用墓碑 + 15 天清理，跨端同步的冲突解决靠 `updateTime` 比较（`sync_service.dart:315-321`）。
- **关注归属只剩成员表**（§3.6）：`FollowUser` 不再带 `tag`，任何新读取路径都得走
  `FollowService.userTagNamesOf`；`follow_user_item.dart:158-160` 因此在未注册 `FollowService`
  的宿主（直播间关注面板、`test/follow_user_item_trailing_test.dart`）里退回哨兵「全部」而不是 `Get.find` 抛错——
  复用该组件时记得这条兜底。
- **降级到旧版本 app 会「看不见」分组归属**：旧版读新记录时 field 7 为空 → 显示「全部」，
  成员表本身仍在 `tagBox` 里，重新升级即自动恢复；**降级期间不要做「清理数据 / 重建分组」**
  （`follow_user.dart:50-53`、PR 说明「老版本 app 读新数据」一节）。
- **WebDAV 合并语义已从「覆盖」变为「按分组名并集」**（`follow_sync_resource.dart:99-133`）：
  同名分组会被并集，**改名 = 新组**，两侧不会互相收敛；分组 id 每次合并都重发
  （`FractionalIndexing`），故按 id 存的折叠态会随同步重置。

## 12. 本组件与 `simple_live_core` 的边界

- **只消费、不反向依赖**：App 通过 `Sites.allSites[siteId].liveSite`（`app/sites.dart:9-45`）调用 core 的 `LiveSite`/`LiveDanmaku`，`pubspec.yaml:15-16` 用 `path: ../simple_live_core` 引入；core 的依赖方向里**没有任何对 `simple_live_app` 的依赖**（见 core 架构文档 §1）。
- **契约面**：列表 `LiveCategoryResult.hasMore`（分页判据权威定义见 [core 工作流程图 §4](../../simple_live_core/doc/workflow-diagram.md)）、`LiveRoomDetail{data,danmakuData}`、`getPlayQualities/getPlayUrls`、`LiveMessage{emoticons?}`、`setSiteAttrs`（cookie/UA 注入；**一律传 `jsonEncode` 后的 map 字符串**，2026-10-14 起 B 站也改成先 `jsonDecode` 再取 `cookie`，与其他平台同口径，`bilibili_site.dart:553-558`）。
- **相关文档**：[simple_live_core 架构与选型对照](../../simple_live_core/doc/architecture.md)｜[simple_live_core 工作流程图](../../simple_live_core/doc/workflow-diagram.md)｜[simple_live_core test-suite](../../simple_live_core/doc/test-suite.md)。