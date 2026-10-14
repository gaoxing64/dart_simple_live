# simple_live_tv_app 架构与选型对照

> 版本锚点：`simple_live_tv_app` v1.5.1+10501 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/architecture.md)

## 1. 目录分层

```
simple_live_tv_app/
├── lib/main.dart                  # 启动、强制横屏/全屏、服务注册
├── lib/app/                       # 应用层基座
│   ├── sites.dart                 # 4 个 LiveSite 单例（无 twitch）
│   ├── app_focus_node.dart        # 遥控器焦点状态（isFoucsed）
│   ├── base_focus_model.dart      # 焦点模型基类
│   ├── constant.dart / app_style.dart / utils.dart / log.dart / event_bus.dart
│   ├── app_error.dart / app_style.dart
│   ├── common/asT.dart            # 泛型安全转换（上游新增；TV 内暂无 import，见 backlog P2-7）
│   └── controller/
│       ├── base_controller.dart   # BaseController + BasePageController<T>
│       └── app_settings_controller.dart  # 全部设置项（GetxController）
├── lib/routes/                    # GetX 路由（app_pages / route_path / app_navigation）
├── lib/modules/                   # 页面 + 控制器（按功能分包）
│   ├── home / hot_live / category / search / follow_user / history
│   ├── live_room/                 # 房间页 + player/（播放器控制）
│   ├── settings / sync / account/qr_login / agreement
├── lib/widgets/                   # 可复用组件
│   ├── highlight_widget.dart      # 焦点高亮 + 按键映射（核心）
│   ├── button/ card/ status/      # 按钮、卡片、空/错/加载态
│   ├── page_grid_view.dart / settings_item_widget.dart / net_image.dart ...
├── lib/services/                  # LocalStorage / DB / Sync / SignalR / Platform(账号) / Migration / FollowUser
├── lib/models/                    # db（Hive：follow_user / history / account）、version、account、follow_user_item
├── test/widget_test.dart          # 仅 flutter create 默认模板（见 test-suite.md）
├── android/  windows/             # 打包目标（android 为 TV 主目标）
└── pubspec.yaml
```

依赖方向：`modules → widgets/services/app`，所有数据访问经 `app/sites.dart` → `simple_live_core`。**无任何反向依赖**（core 不依赖本工程）。

## 2. 模块清单

| 模块 | 入口 | 控制器 | 职责 |
| --- | --- | --- | --- |
| 首页 | `modules/home/home_page.dart` | `home_controller.dart` | 大按钮导航 + 关注列表卡片 |
| 热门直播 | `modules/hot_live/` | `hot_live_controller.dart` | 各平台推荐流瀑布流 |
| 直播类目 | `modules/category/` | `category_controller.dart` | 平台类目 + 子类入口 |
| 类目详情 | `category/detail/` | `category_detail_controller.dart` | 子类房间列表 |
| 搜索 | `modules/search/{room,anchor}/` | 各自 controller | 搜房间 / 搜主播 |
| 关注 | `modules/follow_user/` | `FollowUserService`（全局） | 关注主播卡片、开播状态 |
| 观看记录 | `modules/history/` | `history_controller.dart` | 本地 Hive 记录 |
| 直播间 | `modules/live_room/` | `live_room_controller.dart` + `player/` | 取流/播放/弹幕/切台 |
| 数据同步 | `modules/sync/` | `sync_controller.dart` | 本机 HTTP 服务 + 二维码 / SignalR 房间 |
| 设置 | `modules/settings/` | `settings_controller.dart` | 播放/弹幕/关注/账号/关于 5 个 Tab |
| 账号 | `modules/account/qr_login/` | `qr_login_controller.dart` | 通用扫码登录：按传入 `Account.siteId` 取站点（B 站/斗鱼共用此页） |
| 平台账号（服务） | `services/platform_service.dart` | `PlatformService`（GetxService，全局） | 账号列表（Hive `account` 箱）、启动期逐个刷新、登录/登出/同步写入 |

## 3. 状态管理方案（实测）

- **方案：GetX 全家桶**（`get: ^4.7.2`）。路由用 `GetPage`/`Get.toNamed`（`routes/app_pages.dart`），依赖注入用 `Get.put`/`BindingsBuilder.put`（`main.dart:78-89`、`app_pages.dart:43-140`），响应式状态用 `.obs` / `Obx` / `GetxController`。
- **页面控制器基类**：`BaseController`（加载/空白/错误/未登录态，`base_controller.dart:10-57`）+ `BasePageController<T>`（分页、`EasyRefreshController`、`scrollController`，`:59-124`）。
- **不是 Provider / Riverpod / Bloc**：仓库内无这些依赖（`pubspec.yaml`）。
- **局部状态**：焦点态用 `AppFocusNode` 自带 RxBool；跨页事件用 `EventBus`（`app/event_bus.dart`，事件常量 `Constant.kUpdateFollow/kUpdateHistory`）。
- **账号状态**：`PlatformService.accountList`（`RxList<Account>`，`services/platform_service.dart:13`）为唯一真源，设置页在 `Obx` 里直接遍历它（`settings_page.dart:418-422`）；持久化在 Hive `account` 箱（`db_service.dart:17`，key = `account.id`，`:21`）。
- **注意**：`app_settings_controller.dart` 里定义了**大量手机端沿用而来的设置项**（聊天区、PIP、动态取色、定时关闭等），TV 端 UI 并未消费，见 backlog P2。

## 4. 依赖清单（`pubspec.yaml`）与用途

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| `simple_live_core` | path `../simple_live_core` | 平台数据/取流/弹幕（唯一共享代码） |
| `get` | ^4.7.2 | 状态管理 + 路由 + 依赖注入 |
| `dio` | ^5.9.0 | HTTP（更新检查/同步等） |
| `hive` + `hive_flutter` | 2.2.3 / 1.1.0 | 本地持久化（关注、历史、设置、屏蔽词、账号）（`pubspec.yaml:21-22`） |
| `media_kit` + `media_kit_video` + `media_kit_libs_video` | ^1.2.1 / ^1.3.1 / ^1.0.7 | 播放内核 |
| `canvas_danmaku` | ^0.3.3 | 弹幕渲染（`pubspec.yaml:39`，本次由 ^0.2.7 升上来） |
| `flutter_easyrefresh` | 2.2.2 | 下拉刷新/上拉加载 |
| `flutter_staggered_grid_view` | ^0.7.0 | 瀑布流卡片 |
| `flutter_screenutil` | ^5.9.3 | 大屏尺寸适配（设计基准 1920×1080） |
| `flutter_smart_dialog` | ^4.9.8+9 | Toast/Dialog/Loading |
| `qr_flutter` | ^4.1.0 | 登录二维码 / 同步二维码 |
| `signalr_netcore` | ^1.4.4 | 房间远程同步 |
| `shelf` + `shelf_router` + `udp` | — | 本机同步 HTTP 服务 + UDP 发现 |
| `device_info_plus` / `network_info_plus` / `package_info_plus` | — | 设备名、局域网 IP、版本 |
| `wakelock_plus` | ^1.4.0 | 播放时屏幕常亮 |
| `marquee` / `lottie` / `extended_image` / `remixicon` | — | 跑马灯标题、Lottie 空态、图片缓存、图标 |
| `dev`: `flutter_test` / `flutter_lints` | ^5.0.0 | 测试与静态检查 |

## 5. 与 `simple_live_app` 的关系对照（按证据）

| 维度 | TV 端 | 手机端（`simple_live_app/pubspec.yaml`） | 依据 |
| --- | --- | --- | --- |
| 代码共享 | **只共享 `simple_live_core`** | 同左 | 两边 `lib/` 各自独立；`widgets/live_room_card.dart` 等同名文件内容不同 |
| Flutter | `3.35.7`（`.fvmrc`） | `3.47.6` | TV `pubspec.yaml:8`；app `pubspec.yaml:7` |
| SDK 下限 | `>=3.1.2` | `>=3.0.5` | 各自 `environment` |
| media_kit 来源 | pub 版（^1.2.1） | fork 版 `gaoxing64/media-kit`（git 锁定 ref） | app `pubspec.yaml:99-160` |
| Rust/FFI | **无** | 有 `rust_lib_simple_live_app` + `flutter_rust_bridge` | app `pubspec.yaml:46-48` |
| Hive | `hive` 2.2.3 | `hive_ce` 2.19.3 | 各自依赖段 |
| 弹幕库 | `canvas_danmaku` ^0.3.3 | ^0.3.1 | TV `pubspec.yaml:39` / app `pubspec.yaml:57` |
| 刷新库 | `flutter_easyrefresh` 2.2.2 | `easy_refresh` ^3.5.1 | 同上 |
| Firebase | 无 | analytics/crashlytics/core | app `pubspec.yaml:28-30` |
| 后台播放 | 无 | `audio_service` + `audio_session`（钉版本 0.18.19） | app `pubspec.yaml:124-128` |
| 其他 | — | webdav、floating(PIP)、inappwebview、window_manager、share_plus、file_picker、pinyin | app 依赖段 |
| 账号模型 | 自有精简版 `models/db/account.dart`（Hive `typeId: 3`，字段可变，无 `support*Login`） | `models/db/account.dart`（`typeId: 8`，全 `final` + `supportQRLogin/supportCookieLogin/supportWebLogin`，`:41-48`） | TV `models/db/account.dart:5` / app `models/db/account.dart:5` |
| 版本/规模 | v1.5.1+10501 | v1.8.15+10815 | 各自 `pubspec.yaml:4` / `:2` |

结论：**两边只共享 core**；UI、服务、模型、播放器封装各自演进，TV 端整体比 app 轻（无 rust、无 firebase、无后台播放/多开/WebDAV）。

## 6. TV 端适配设计

- **横屏布局**：启动强制 `landscapeRight/Left`（`main.dart:35-38`）+ 全屏（`:40`）；`AndroidManifest.xml:22` 再锁 `screenOrientation=landscape`；`ScreenUtilInit designSize: 1920×1080`（`main.dart:97-98`），全部尺寸用 `.w` 缩放。
- **TV 应用身份**：`AndroidManifest.xml:34` 声明 `LEANBACK_LAUNCHER`，并提供 `android:banner`（`:10`、`:21`），可出现在 Android TV 桌面。
- **焦点/按键映射**：见 `workflow-diagram.md` §4。核心是 `HighlightWidget` 把每个可点击项包成 `Focus` + 视觉高亮，方向键交给 Flutter 默认空间导航，`enter/select/space` 当点击。
- **性能取舍**：
  - 图片统一走 `NetImage`（`extended_image` 缓存）并给 `cacheWidth` 降采样（如 `live_room_card.dart:52-55` 用 400）。
  - 弹幕默认开启、可关（`app_settings_controller.dart:26-27` 默认 `danmuEnable=true`）；播放器弹幕由 `DanmakuScreen` 渲染（`player_controls.dart:216-247`）。
  - 硬件解码/兼容模式二选一（`player_controller.dart:30-42`：兼容模式走 `mediacodec_embed`）。
  - 关注开播状态用可配线程数并发刷新（`follow_user_service.dart:80-106`，默认 4 线程）。

## 7. 已知取舍（是设计还是缺口）

| 事项 | 判断 | 依据 |
| --- | --- | --- |
| 无 twitch | **设计**：TV 只列 4 平台 | `sites.dart:5-34`（core 有 5 平台） |
| 无弹幕发送/聊天输入 | **设计**：遥控器打字体验差，只读展示 | 房间页无 TextField；`player_controls.dart` 仅展示 |
| 无后台播放/小窗 | **设计**：TV 常亮横屏 | 无 `audio_service`/PIP 依赖 |
| 无多路同播（multi_play） | **缺口/待确认**：app 作为新特性有，TV 未跟 | app `lib/modules/live_room/multi_play/` 存在 |
| 同步只做「被同步端」 | **设计**：TV 起 HTTP 服务供手机推送 | `sync_service.dart:144-173` |
| 进直播间不再做 B 站登录拦截 | **上游设计变更**（`6da36e04`）：账号从「取流前置条件」改成设置页里的可选登录位，未登录也能进 B 站房间 | `app_navigation.dart:12-16`（原 `bilibiliLoginTip` 分支已删），残留设置项见 backlog P2-1 |
| 账号凭证按站点解析 | **设计**：TV 只存 core 下发的 JSON 凭证串，不解释字段 | `platform_service.dart:45`（`getAccountInfo`）、`:55`（`setSiteAttrs`）；见 workflow-diagram.md §0 |
| 分页未采信 core 的 `hasMore` | **缺口**（与 core v1.1.0 契约脱节） | `base_controller.dart:84-95` 用「本页非空」，见 backlog P1 |
| 大量 app 设置项在 TV 无 UI | **技术债**：沿用设置模型未裁剪 | `app_settings_controller.dart:37-98`，全仓库无消费点 |