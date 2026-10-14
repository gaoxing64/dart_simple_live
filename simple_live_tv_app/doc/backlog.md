# simple_live_tv_app 待办与优化清单（backlog）

> 版本锚点：`simple_live_tv_app` v1.5.1+10501 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/backlog.md)

## 0. 使用说明

- 每条含：**现象 → 证据（file:line / commit）→ 建议动作 → 影响面**。
- 优先级：`P0` 用户可见的正确性风险；`P1` 契约/平台脆弱点；`P2` 结构/技术债/功能缺口。
- 证据行号基于锚点提交；若与当前代码不符，先 `git log -L` 核对再动手。
- **代码注释扫描结果**：全 `lib/` 下无 `TODO/FIXME`；唯一命中是 `modules/account/qr_login/qr_login_controller.dart:30` 的「已扫描，待确认」，属二维码状态说明而非待办（旧的 `modules/account/bilibili/qr_login_controller.dart` 已随上游 `6da36e04` 删除）。因此本清单以**行为/结构证据**为主，而非注释。
- 第 5 节记录**已决策不修**的取舍。

## 1. P0 — 正确性风险

### P0-1 焦点节点在 `build` 内联创建（遥控器可用性）

- 现象：多处把 `focusNode: AppFocusNode()` **直接写在 `build()`/`itemBuilder` 内**，每次重建都会 new 一个新 `FocusNode`（旧实例被替换/释放），在焦点控件因 `Obx` 刷新或列表滚动重建时，可能造成**焦点丢失/跳回**（大屏交互最关键的失败模式）。
- 证据：`modules/home/home_page.dart:47,69,79,88,108,115,175,179,234`；`modules/home/home_page.dart:295`（`itemBuilder` 内 `var foucsNode = AppFocusNode();`）；`modules/category/category_page.dart:28,86`；**2026-10-14 上游又加了两处**：`modules/settings/settings_page.dart:453`、`:467`（虎牙/抖音账号项 `focusNode: AppFocusNode()` 直接写在 `buildAccountSettings` 里）。
- 建议：把焦点节点提升到页面 State / Controller 或列表项模型（如 `LiveRoomItemExt.focusNode` 已是正确做法，见 `hot_live_controller.dart:64`），构建期只复用、不新建。
- 影响：查看/搜索/设置页的方向键导航稳定性。
- 备注：是否**必然**丢焦点需真机复现（`AppFocusNode` 重建后 Flutter 是否自动恢复 focus 取决于控件树差异）——**待确认**，但裸建节点属明确的坏味道。

## 2. P1 — 契约 / 平台脆弱点

### P1-1 分页未采信 core 的 `hasMore`（与 core v1.1.0 契约脱节）

- 现象：core v1.1.0 起 `getRecommendRooms/getCategoryRooms` 返回带 `hasMore` 的结果，且抖音推荐首屏 `hasMore` 恒 true 依赖消费方续接（core 知识库 §4）。TV 端 `BasePageController` 完全**忽略该字段**，只用「本页是否非空」判是否继续。
- 证据：`app/controller/base_controller.dart:84-95`（`if (result.isNotEmpty) { canLoadMore = true } else { canLoadMore = false }`）；各控制器只取 `result.items`（`hot_live_controller.dart:35-45`、`search_room_controller.dart:36-46`、`search_anchor_controller.dart:37-47`）。
- 建议：让 `getData` 返回 `(items, hasMore)` 或改用 core 的 `LiveCategoryResult`，`canLoadMore` 采信 `hasMore`——否则抖音等平台在 TV 端可能出现「提前到底、无法续接」。
- 影响：所有列表页的无限滚动能力；与手机端行为不一致。

### P1-2 Hive box 名拼写错误且遗留旧版 Hive

- 现象：历史记录 box 名为 `"TVHostiry"`（拼写错误，History 应为 History），一旦发布即成为持久化契约，日后改名会**丢历史**；且 TV 端用 `hive` 2.2.3，app 已迁 `hive_ce`。
- 证据：`services/db_service.dart:15`（`Hive.openBox("TVHostiry")`）、`:16`（`"TVFollowUser"`）；`pubspec.yaml:21-22`。
- 新增（2026-10-14，`6da36e04`）：第三个箱 `Hive.openBox("account")`（`db_service.dart:17`）与手机端同名同 key 方案（`simple_live_app/lib/services/db_service.dart:26,30`），但两端 `Account` 模型的 Hive `typeId` 不同（TV 3 / app 8），且箱内 `key = account.id`（`db_service.dart:21`）由迁移脚本写死 `'0'/'1'`（`migration_service.dart:21,28`）——手机端同步来的账号只要 id 相同就会**覆盖**本地槽位。
- 建议：`TVHostiry` 加迁移逻辑后再改名（或永久保留 + 注释）；评估随 app 迁移到 `hive_ce`；账号同步按 `siteId` 归并而非按 `id` 直接 put。
- 影响：观看记录持久化；跨端数据迁移。

### P1-3 TV 端不含 twitch（4 平台）

- 现象：TV 只注册 bilibili / douyu / huya / douyin，缺 twitch；core 已支持 5 平台。
- 证据：`app/sites.dart:5-34`。
- 建议：若要补齐，只需在 `Sites.allSites` 增一项并使用 core 的 `TwitchSite`（core 侧 twitch 搜房间/推荐为「尚不支持」，UI 需相应收敛）。
- 影响：平台覆盖（**倾向按设计记载**，见第 5 节）。

### P1-4 media_kit 用 pub 版而非手机端 fork 版

- 现象：TV 用 `media_kit ^1.2.1 / media_kit_video ^1.3.1`（pub 源），跨端行为/后端（如 hvc1 真原画、安卓兼容模式）可能与手机端（自定义 git fork）不一致。
- 证据：`pubspec.yaml:52-54` 对比 `simple_live_app/pubspec.yaml:99-160`。
- 建议：确认 TV 端是否需要与手机端同步某些取流格式支持；如无需求保持现状并注明。
- 影响：个别平台/编码的播放兼容性（**待确认**）。

### P1-5 同步来的账号不会即时生效（要到下次启动才刷新）

- 现象：HTTP 推送与 SignalR 房间两条账号同步路径收到整包 `Account` 后只调 `PlatformService.updateAccount`（仅改内存列表 + 落盘），**不调 `accountLogin`**，因此 `isActive/userName/avatar/uid` 全空；而 `Account.fromJson` 又明确丢弃这四个字段（只取 id/siteId/credential/createdAt/updatedAt），所以设置页立刻显示「暂未登录」，要到下次启动 `initAccount()` 才变绿。
- 证据：`services/sync_service.dart:299-301`；`modules/sync/sync_controller.dart:167-169`；`services/platform_service.dart:24-30`（updateAccount）对比 `:43-60`（accountLogin 才会 `getAccountInfo`）；丢弃字段见 `models/db/account.dart:49-57`（`toJson` 却会写出这些键，`:83-93`），并且 `userName/avatar/uid/isActive` 根本没有 `@HiveField`，适配器只落 5 个字段（`models/db/account.g.dart:19-25,31-41`）；刷新只发生在 `platform_service.dart:15-21,62-66`。
- 建议：`updateAccount` 之后补一次 `accountLogin`（或在 fromJson 里保留 profile 字段）。
- 影响：手机端「同步账号到 TV」的用户感知——TV 显示未登录，容易被判定为同步失败。

### P1-6 账号凭证明文进日志

- 现象：账号同步接口把**请求体原文**（含 `credential`，即 B 站/斗鱼 cookie）写进 `Log.d`；`Account.toString()` 同样整串输出 `credential`。TV 的 `Log.d` 没有 release/debug 短路（`app/log.dart:20-22` 直接 `logger.d`）。
- 证据：`services/sync_service.dart:297`（`Log.d('_syncBiliAccountRequest: $body');`，顺带说一句该 tag 还是改名前的旧名）；`models/db/account.dart:95-108`（toString 含 `credential`）；Hive 明文箱存凭证（`services/db_service.dart:17`）。
- 建议：日志里脱敏（只打 siteId + 长度），`toString` 去掉 `credential`。
- 影响：凭证泄露面（局域网日志、adb logcat）。

### P1-7 设置页对 `siteId` 直接强制解包

- 现象：账号 Tab 用 `Sites.allSites[item.siteId]!` 取站点，TV 只注册 4 个站点（`app/sites.dart:5-34`，无 twitch），而手机端注册了 5 个（`simple_live_app/lib/app/sites.dart:38-39` 含 twitch），同步过来的 `Account.siteId` 可以是 TV 不认识的键。一旦取不到，整个 `buildAccountSettings` 抛异常、设置页打不开。
- 证据：`modules/settings/settings_page.dart:422-425`；TV 站点表 `app/sites.dart:5-34`；写入点未校验 siteId（`services/platform_service.dart:24-30`、`services/sync_service.dart:299`）。
- 建议：`allSites[siteId]` 取不到时跳过该条并提示，别用 `!`。
- 影响：跨端同步一次异常数据即让设置页不可用。

## 3. P2 — 结构 / 技术债 / 功能缺口

### P2-1 大量手机端设置项在 TV 端无消费点

- 现象：`AppSettingsController` 定义了聊天区/PIP/动态取色/定时关闭/主页排序等设置，但全 `lib/` 除定义处外**无任何读取或 UI**（grep 命中仅集中在 `app_settings_controller.dart`）。属从手机端沿用未裁剪的「僵尸设置」。
- 证据：`app/controller/app_settings_controller.dart:37-46`（chatTextSize/Gap/BubbleStyle）、`:50-51`（qualityLevelCellular）、`:53-60`（autoExitEnable/Duration/roomAutoExitDuration）、`:68`（autoFullScreen）、`:79`（pipHideDanmu）、`:82`（styleColor）、`:85`（isDynamic）、`:91`（playerBufferSize，仅在 `player_controller.dart:25` 被注释引用）、`:260-276`（siteSort/homeSort）、`:166-171`（danmuStrokeWidth，弹幕渲染 `DanmakuOption` 未用）。
- **2026-10-14 新增一条**：`bilibiliLoginTip`（`:88` 读取、`:310-312` 声明与 setter）自此**彻底无消费点**——`6da36e04` 删掉了 `app_navigation.dart` 里的进房登录拦截，设置页也从未给它做过开关（全 `lib/` grep 仅命中定义处）。
- 建议：逐项「删除 or 补 UI or 注释说明保留原因」三选一，避免误导后续维护。
- 影响：可维护性、设置页与真实能力的一致性。

### P2-2 `playerCompatMode` 默认值自相矛盾

- 现象：`onInit` 从存储读取默认 `true`（`:62-63`），但字段本身声明默认 `false`（`:208`）；若未初始化完成即读取字段会得到 `false`。
- 证据：`app/controller/app_settings_controller.dart:62-63` 与 `:208`。
- 建议：统一为一个默认值常量。
- 影响：播放器兼容模式的初始行为（低风险）。

### P2-3 无弹幕发送 / 聊天输入

- 现象：房间页只接收并展示弹幕，无输入框与发送路径。
- 证据：`modules/live_room/live_room_page.dart`（无 TextField）；`player_controls.dart:216-247` 仅渲染 `DanmakuScreen`。
- 建议：按设计保留（遥控器打字体验差）；如要做，需引入屏上搜索/软键盘逻辑。
- 影响：交互完整性（**倾向设计取舍**，见第 5 节）。

### P2-4 无多路同播（multi_play）

- 现象：手机端已有 `modules/live_room/multi_play/`（多路网格同播），TV 端无对应实现。
- 证据：`simple_live_app/lib/modules/live_room/multi_play/` 存在，TV `lib/modules/live_room/` 无此目录。
- 建议：确认为产品缺口还是有意不跟；TV 大屏其实适合多路，值得评估。
- 影响：功能对齐（**待确认**）。

### P2-5 测试资产为空（默认模板）

- 现象：`test/` 下仅 `widget_test.dart`，仍是 `flutter create` 默认计数器模板（断言 `'0'/'1'/Icons.add`），与真实 App 不符，实际不可用。
- 证据：`test/widget_test.dart:14-28`。
- 建议：见 [test-suite.md](./test-suite.md) 的最小可做清单（从纯函数/DTO 切入）。
- 影响：回归护栏为零。

### P2-6 Windows 目标存在但未登记/未验证

- 现象：仓库含完整 `windows/` 运行器，但 `.metadata` 只登记了 `root` 与 `android` 两个平台；`analysis_options.yaml:11-13` 把 `windows/**` 排除出分析。
- 证据：`.metadata:14-20`；`analysis_options.yaml:10-13`。
- 建议：明确 TV 端交付目标（Android TV 为主），Windows 若仅作调试则注明；否则补 CI。
- 影响：构建与发布范围（**待确认**）。

### P2-7 上游账号迁移留下的死代码/死常量

- 现象：`6da36e04` 只删了旧服务本体，没清理它依赖过的东西，TV 里现在有四类零引用符号。
- 证据（`grep` 全 `lib/` 均只有定义处）：`routes/route_path.dart:28`（`kBiliBiliQRLogin`，对应 `GetPage` 已换成 `kAccountQRLogin`，见 `app_pages.dart:72-79`）；`services/local_storage_service.dart:106`（`kBilibiliCookie`，原读写者 `services/bilibili_account_service.dart:23,63,73` 已删）；`models/account/bilibili_user_info_page.dart:10`（`BiliBiliUserInfoModel`，原唯一使用者是被删服务，见 `git show 8fd14a9f:simple_live_tv_app/lib/services/bilibili_account_service.dart` 第 41 行）；`app/common/asT.dart:1`（新增文件无 import，而 `models/account/bilibili_user_info_page.dart:3` 与 `models/version_model.dart:3` 各自还留着同名本地副本）。
- 建议：一并删除或收敛为共享工具；`kBilibiliCookie` 若要清历史数据可留一次清理逻辑。
- 影响：可维护性；不影响运行时行为。

### P2-8 `account.g.dart` 是生成物，但 TV 包没有生成链

- 现象：`models/db/account.dart:3` 用 `part 'account.g.dart';`，`account.g.dart:1` 标着 `GENERATED CODE - DO NOT MODIFY BY HAND`（`TypeAdapterGenerator` 产出，`typeId = 3` 在 `:11`，只落 5 个字段：`read` `:19-25` / `write` `:31-41`）；而 TV 的 `dev_dependencies` 只有 `flutter_test` + `flutter_lints`（`pubspec.yaml:59-63`），**没有 `build_runner` / `hive_generator`**（手机端有 `build_runner`：`simple_live_app/pubspec.yaml:164`）。改 `Account` 字段只能手改 `.g.dart`，且本地无法验证是否一致。
- 建议：要么补 dev_dependency + 一次生成交互（需本机 Flutter，见 test-suite.md §1 的未验证声明），要么在文件头注明「手工维护、与 account.dart 字段序号对齐」。
- 影响：账号模型的可演进性；错序会直接读到脏数据（Hive field 序号即存储布局）。

### P2-9 账号迁移逻辑硬编码，且只建两个槽位

- 现象：`MigrationService.migrateDataByVersion()` 里版本阈值与默认账号都是写死的字面量——`curDBVer` 默认 10500、判断 `curDBVer < 10501`、只给 bilibili/douyu 建 `id='0'/'1'` 的空账号；虎牙/抖音在 TV 设置页是硬编码「无需登录」项而非账号槽。下一版本再加迁移就得再堆一段 `if`。
- 证据：`services/migration_service.dart:12`（默认 10500）、`:14`（`< 10501`）、`:19-34`（两条默认）、`:42`（写回 `curAppVer`）；`modules/settings/settings_page.dart:452-478`（虎牙/抖音硬编码）；`main.dart:83`（唯一调用点）。
- 备注：同批改动还把 `Utils.packageInfo = await PackageInfo.fromPlatform();` 写了两次（`main.dart:47` 与 `:75`）。
- 建议：改成「目标版本 → 迁移函数」表驱动；默认槽位按 `Sites.allSites` 生成。
- 影响：后续版本升级的正确性（漏加 `if` 就等于不迁移）。

## 4. TV 特有问题清单

| 主题 | 现状/证据 | 备注 |
| --- | --- | --- |
| 遥控器焦点 | `HighlightWidget` 默认不拦截方向键（`widgets/highlight_widget.dart:51-72`），空间导航依赖 Flutter 默认策略 | 瀑布流/网格里方向键落点是否直觉**待真机确认**；见 P0-1 |
| 返回键 | 房间页 `PopScope` 双击退出（`live_room_page.dart:19-36`）；其余页靠 GetX 默认返回 | 个别弹窗返回后需手动还原焦点（`player_controls.dart:594-597`） |
| 横屏 | 启动强制 landscape（`main.dart:35-38`）+ manifest 锁定（`AndroidManifest.xml:22`） | 无竖屏分支 |
| 启动性能 | `main.dart:44-90` 启动期同步 `Get.put` 多个服务 + 多次 `Hive.openBox`，外加 `PlatformService.onInit` 里的逐账号网络请求（`platform_service.dart:15-21`） | 无实测耗时数据，**待确认** |
| 账号能力 | **实测有**：通用扫码页 `modules/account/qr_login/`（B 站 + 斗鱼）+ 全局 `PlatformService`（`services/platform_service.dart`）+ Hive `account` 箱（`db_service.dart:17`）+ 迁移脚本 `services/migration_service.dart`。旧 `services/bilibili_account_service.dart` 与 `modules/account/bilibili/` **已随上游 `6da36e04` 删除** | 仍无多账号并存、无网页登录、虎牙/抖音无扫码（`settings_page.dart:452-478`；core 侧 `huya_site.dart:567-582`、`douyin_site.dart:1290-1299` 直接 `UnimplementedError`） |
| 进房登录门槛 | 已无：`app_navigation.dart:12-16` 不再拦截未登录的 B 站房间（2026-10-14 `6da36e04`） | 未登录看 B 站走的是 core 的匿名路径；受 `57d8f86d`/`03c4493a` 影响的登录态路径未在真机验证 |
| 同步能力 | **实测有**：本机 UDP 发现(23235)+HTTP 服务(23234)（`sync_service.dart:28-29,144-173`）+ SignalR 房间同步（`signalr_service.dart:12-13`）；账号端点已改名 `/sync/account/account`（`sync_service.dart:152`） | 只做「被同步端」，无 WebDAV；`SyncController.onInit` 里的 `connect()`（SignalR 房间）当前是被注释掉的（`sync_controller.dart:37`），**待确认为何关掉** |
| 与 app 功能缺口 | 缺 twitch、多路同播、后台播放、PIP、弹幕发送、WebDAV、网页登录、多账号并存 | 「斗鱼/B 站扫码登录」这一条 **2026-10-14 已解决（`6da36e04`）**；其余多数仍为有意取舍 |

## 5. 已决策的取舍（不修，记录原因）

| 取舍 | 原因 | 来源 |
| --- | --- | --- |
| TV 只支持 4 平台（无 twitch） | 大屏主打国内主流平台；core 的 twitch 搜索/推荐本就「尚不支持」 | `app/sites.dart:5-34`、core 知识库 §5.5 |
| 无弹幕发送/聊天输入 | 遥控器无键盘，输入体验差；只读展示已满足大屏场景 | 房间页无 TextField |
| 无后台播放/小窗（PIP） | TV 常亮横屏，无移动场景 | 无 `audio_service`/PIP 依赖 |
| 同步只做接收端 | TV 作为「数据汇聚显示端」，由手机推送 | `sync_service.dart:144-173` |
| 沿用手机端整套设置模型 | 便于两端共享设置键位/后续对齐，代价是僵尸项（P2-1） | `app_settings_controller.dart` |

## 6. 建议的推进批次

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 1 | P0-1（焦点节点归属修正）+ P1-1（分页采信 hasMore）+ P1-7（`siteId` 解包加判空） | 直接决定大屏交互与列表可用性；P1-7 一行即可挡住设置页崩溃 |
| 2 | P2-5（补最小测试）+ P2-1（清理僵尸设置）+ P1-5/P1-6（账号同步即时生效、日志脱敏） | 低成本高收益，先立护栏；账号链路是本次新落入的代码，趁热修 |
| 3 | P1-2（Hive box 迁移评估）+ P1-4（media_kit 对齐确认）+ P2-9（迁移脚本表驱动） | 涉及持久化/播放，需真机验证 |
| 4 | P1-3 / P2-3 / P2-4（功能取舍拍板）+ P2-7/P2-8（死代码清理、生成链补齐） | 产品决策 + 无风险的清理项 |