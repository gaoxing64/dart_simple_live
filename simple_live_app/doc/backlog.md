# simple_live_app 待办与优化清单（backlog）

> 版本锚点：`simple_live_app` v1.8.15+10815 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)

## 0. 使用说明

- 每条含：**现象 → 证据（file:line / commit / 已内联的事实）→ 建议动作 → 影响面**。
- 优先级：`P0` 用户可见的正确性风险；`P1` 平台/设备侧随时可能爆的脆弱点；`P2` 结构/技术债/功能缺口。
- 「证据」行号基于锚点提交 `5ae375f1`；若与当前代码不符，先 `git log -L` 核对再动手。
- 来源标记只表示**来源类别**，不再指向可点开的文件：
  - `[注释]` —— `lib/**` 里的 TODO / FIXME / ⚠️ / 已知限制 注释（路径可直接查证）；
  - `[notes]` —— 原「后台播放」「音量均衡」两份取证笔记的结论，**已内联进条目正文**；
  - `[review]` —— 历史代码评审（OCR / Open Code Review）的结论，**已内联**；
  - `[spec]` —— 2026-10-03「播放 OSD 统一 + 每路独立音量」设计稿的结论，**已内联**。
- **来源文件现状（2026-10-14）**：上述 `[notes]` / `[review]` / `[spec]` 所依据的原件**都已不在工作区**——
  `background-playback-notes.md` 与 `specs/2026-10-03-osd-unify-and-independent-volume-{design,plan}.md`
  曾在 HEAD 里（需要考古时可用 `git show <HEAD>:<路径>` 取回），而 `volume-normalize-notes.md`、
  `ocr-review-future.md` 从未入库、已不可得。故本文**一律不以文件路径作为证据**：原先只写
  「见某笔记第 N 条」的地方，事实都已写进条目正文；标记仅留作来源线索。
- 第 5 节记录**已决策不修**的取舍，避免反复讨论。

## 1. P0 — 用户可见的正确性风险

### P0-1 音量均衡（loudnorm）依赖定制 libmpv，滤镜缺失即整条音轨被禁用（无声）

- 现象：`af=lavfi=[loudnorm=...]` 挂在 mpv 属性上。若宿主 libmpv 未编译 `loudnorm`，mpv 的 `recreate_audio_filters()` 失败走 `init_error` → `uninit_audio_chain` + `error_on_track`，**音频轨被直接禁用**（mpv 没有「跳过滤镜继续播」的回退），表现就是「开启音量均衡后直播静音」。
- 证据：`lib/modules/live_room/player/player_controller.dart:47`（⚠️ 依赖内核编译 loudnorm）、`:51` `volumeNormalizeAF()`、`:252` `_volumeNormalizeUnsupported`、`:284` 起自愈检测。供应链取证（已内联）：对 Predidit 官方「仅视频」构建的 libmpv 产物做符号/字符串扫描，`loudnorm` 相关符号**0 命中**（同法可命中阳性对照），遂改用 gaoxing64 fork 构建（其 ffmpeg 未 `--disable-filters`）。`[notes]`
- 建议：保留现有运行时自愈（监听 `Audio filter initialized failed!` → 清 `af` → 提示并重连本线路）为兜底；**发版前**对四个 ABI（android / windows / linux / macos）的 libmpv 产物各跑一次上述符号扫描（带阳性对照），确认都编入了 `loudnorm`。
- **供应链分叉（2026-10-12 新增）**：同步上游 dev(v1.8.15) 时上游把 media_kit 指向 `SlotSun/media-kit@b2bb9ff0…`；本 fork **保留** `github.com/gaoxing64/media-kit@23ec6b9c…` 钉版（`pubspec.yaml:99-160` 六处 + `dependency_overrides` 五个 libs）。于是 fork 与上游在此分叉：上游那份**是否编译了 `loudnorm`/`dynaudnorm` 未核实**，一旦有人把钉版改回上游即可能整条音轨被禁。升级 media_kit 只能二者取一，且必须连带核对本项。`[notes]`
- 影响：所有开启「音量均衡」的用户，跨平台。

### P0-2 Android 12+ 后台播放：暂停后从通知/锁屏按播放＝一次「后台重启前台服务」

- 现象：`AudioService.enterPlayingState()` 里那句 `startForegroundService` **没有** try/catch；`androidStopForegroundOnPause: true`（暂停时前台服务降级）意味着之后从通知/锁屏按播放是一次「后台重启前台服务」，插件 README 明确点出该组合会中招 `ForegroundServiceStartNotAllowedException`。
- 证据：实现见 `lib/services/playback/live_playback_audio_handler.dart`、`live_audio_session.dart`。原笔记结论（已内联）：该组合的成因就是「暂停时前台服务降级 → 之后按播放＝后台重启前台服务」；本轮没改，是因为改正会牵动唤醒锁的持有期（见下条建议的代价说明）。`[notes]`
- 建议：真机复现则把 `androidStopForegroundOnPause` 改成 `false`（并**连带**把 `androidNotificationOngoing` 也改成 `false`，否则触发插件硬 assert），作为**单变量 A/B** 跑，别和别的改动混一轮；接受「暂停后持续持有 `PARTIAL_WAKE_LOCK`」的耗电代价。
- 影响：Android 13+ 的后台/锁屏播放。

### P0-3 Android 后台按「停止」可能连带回收 Flutter 引擎（长后台后表现为冷启动，需确认真机不黑屏）

- 现象：发出 idle → `AudioService._stop()` → Java `stopSelf()` → `onDestroy()` → `disposeFlutterEngine()`；该方法开头有 `if (clientInterface.activity != null) return;` 守卫。常见「切后台→通知里按停止」时 Activity 仍存活，引擎不销毁；只有「系统已回收 Activity、仅剩进程」时才连带销毁引擎。
- 证据：`AudioServicePlugin.disposeFlutterEngine()` 开头有 `if (clientInterface.activity != null) return;` 守卫——只有系统已回收 Activity、仅剩进程时，这一次 stop 才会连带销毁引擎（原笔记结论，已内联）。`[notes]`
- 建议：真机专项——挂后台足够久（系统可能已销毁 Activity）后从通知按停止，重开 app 确认非黑屏、能正常进直播间。
- 影响：Android 后台播放的退出路径。

### P0-4 后台通知封面取不到（audio_service 的 cache manager 不带 referer/UA）

- 现象：`MediaItem.artUri` 由 audio_service 自己的 cache manager 下载，**不带**页面上那些 referer/UA 请求头；B站/抖音等 CDN 有防盗链时通知退化成纯文字。
- 证据：`lib/services/playback/live_playback_audio_handler.dart:213` `_buildMediaItem` 只交出 `artUri`，取图由 audio_service 自带的 cache manager 完成，不经过页面的 headers（原笔记结论，已内联）。`[notes]`
- 建议：二期改成先落本地文件，再把 `Uri.file(...)` 交给 `MediaItem.artUri`。
- 影响：后台播放通知观感（B站/抖音）。

### P0-5 弹幕表情渲染无开关；旧存储键 `kDanmuEmoticonEnable` 保留但无读取方

- 现象：表情渲染改为**无条件开启**（有表情就渲染）。用户从此没有入口关闭表情图片的下载/解码；老用户此前「关闭表情」的偏好既不会被迁移也不会被清理。
- 证据：`lib/modules/live_room/live_room_page.dart:850`（注释「本项目未提供『表情包』开关（表情始终渲染）」）、`lib/services/local_storage_service.dart:97`（键 `kDanmuEmoticonEnable` 仍在）、`lib/modules/live_room/player/player_controller.dart:541/558`（`_applyDanmakuEmoticon` 无条件渲染）。该项原为历史 OCR 评审的一条，人工复核确认为真（评审记录本身已不在仓库，结论即上条现象）。`[review]`
- **上游对照（2026-10-12 新增）**：上游 dev(v1.8.15) 引入了 `danmuEmoticonEnable` 开关（`AppSettingsController` 上的 getter）；本次同步时本 fork **未采用**该开关（`git grep danmuEmoticonEnable -- simple_live_app/lib` 无命中），仍走「始终渲染」。故此项已从「上游也没有」变成**明确的 fork 决策项**：要么采纳上游开关、要么在 §5 正式登记为有意取舍。
- 建议：确认是否为有意取舍（若是，见 §5）；否则在设置层保留开关、由调用方决定是否传入 `emoticons`，并迁移/清理旧存储键（可直接复用上游 `danmuEmoticonEnable` 的实现）。
- 影响：低端机/流量敏感用户失去退路；老用户偏好静默丢失。**待确认**（是否有意为之，现已有上游实现可对照）。

## 2. P1 — 平台与设备脆弱点

### P1-1 iOS 后台/音频会话未在本机验证（开发机为 Windows，无法构建/运行）

- 现象：iOS 侧改动全部落在 `LiveAudioSession` 的类别与激活上；`Info.plist` 早已声明 `UIBackgroundModes: [audio]`，`AppDelegate.swift` 未改。上 Mac 之前，iOS 视为未验证。
- 证据：`lib/services/playback/live_audio_session.dart`、`ios/Runner/Info.plist`；原笔记结论（已内联）：iOS 侧全部改动集中在 `LiveAudioSession` 的类别与激活，plist 早已就位、`AppDelegate.swift` 未改。`[notes]`
- 建议：上 Mac 后补跑 iOS 手测（原笔记的验收清单已内联在此）：切后台/锁屏出声、耳机键、来电中断、拔耳机暂停、类别切换。
- 影响：iOS 后台播放整体可用性。

### P1-2 多开时后台通知只代表页面主格那一路，四路继续各自出声

- 现象：副格永不挂载后台播放（多开时四路争同一条通知只会互相顶掉）；通知跟随聚焦格属二期。
- 证据：`lib/services/playback/live_playback_target.dart:11`（只有 `isSecondaryTile == false` 的主格实现）、`lib/modules/live_room/live_room_controller.dart:1589`（副格不挂通知）；原笔记结论（已内联）：要让通知跟随聚焦格走，需在聚焦切换处 attach/detach，属二期。`[notes]`
- 建议：二期在聚焦切换处 attach/detach；短期在文档中明示。
- 影响：多开 + 后台播放组合的行为预期。

### P1-3 Android 端跳过 mpv 前向缓存配置（`temporary fix of android platform`）

- 现象：非 Android 才设 `cache=yes` / `cache-secs=1` / `cache-on-disk=no` / `demuxer-max-back-bytes=0`；Android 上这些全跳过，弱网只靠默认预读，抖动时更容易硬卡。
- 证据：`lib/modules/live_room/player/player_controller.dart:193`（注释）、`:194`（`if (!Platform.isAndroid)`）。`[注释]`
- 建议：跟踪上游（hls/令牌流内存问题）修复后再放开；短期记录为已知边界。
- 影响：Android 弱网播放流畅度。

### P1-4 依赖 `media-kit` 上游 issue #1443（播放器释放时序）

- 现象：`onClose` 里对 `player.dispose()` 留有 TODO，指向 `media-kit` 的具体 issue。
- 证据：`lib/modules/live_room/player/player_controller.dart:1526`。`[注释]`
- 建议：跟踪上游修复；升级 media-kit 时**连同 libs 分支的滤镜钉版一起核对**（本 fork 的 libs 是编入 `loudnorm` 的自建产物，见 P0-1），别只 bump 主包。
- 影响：播放器退出时的资源释放。

### P1-5 Wayland 下窗口置顶/几何提示为 no-op（自然降级）

- 现象：相关提示在 Wayland 下不生效，代码注释标注为自然降级、不劣于现状。
- 证据：`lib/services/window_service.dart:542`、`:687`。`[注释]`
- 建议：记录为平台边界；若需 Wayland 支持需换协议路径（本仓库不做）。
- 影响：Linux/Wayland 的 PiP / 置顶行为。

### P1-6 多开路数上限 4 与每路缓冲内存是弱机压力点；「四路到底跑不跑得动」的性能 spike 仍未跑

- 现象：上限 `kMultiPlayMaxTiles = 4`；每路缓冲默认 32MiB 起，四路即 128MiB 起（有 `kMultiPlayTileBufferSize` 可调低）；`lib/spike/multi_player_spike.dart` 需要 4 条直播直链才能跑。
- 证据：`lib/modules/live_room/multi_play/multi_play_layout.dart:14`、`lib/app/controller/app_settings_controller.dart:890`（buffer 注释）、`lib/spike/multi_player_spike.dart`。`[注释]`
- 建议：补 spike 记录（丢帧/缓存/硬解属性）；评估移动端默认路数（`kMultiPlayDefaultTiles`）。属已知边界，先记录。
- 影响：弱机多开稳定性与内存占用。

### P1-7 本机 `flutter test` 有 15 个存量失败（6 个文件）

- 现象：`fvm flutter test --no-pub` 报 **507 通过 / 15 失败**（共 522 条执行，2026-10-14 同机实测）。失败全部落在 6 个文件：
  `search_initial_site_test.dart`(9)、`theme_mode_test.dart`(2)、`follow_grouped_view_test.dart`(1)、
  `page_view_auto_load_test.dart`(1)、`viewpager_drag_test.dart`(1)、`widget_test.dart`(1)。
- 诊断：① 这些文件在 2026-10-12 同步前的 HEAD（`3714eec1`）上因 `AppSettingsController.onInit`
  早于它们变为 async（`app_settings_controller.dart:76`）而**根本无法编译**（用 worktree 在 HEAD
  复现到 `loading [E]` 编译错误）；本次把 6 个测试假件的 `onInit` 签名改成 `Future<void>`（见
  update-history.md §2.3）后编译器放过，暴露为运行期失败。② 可复现的失败原因：真实
  `AppSettingsController.onInit` → `initDataPath()` → `getApplicationSupportDirectory()` 在 widget
  test 环境抛 `MissingPluginException`（无 path_provider 插件宿主）；`live_room_card.dart` 1px
  overflow；关注页部分断言找不到控件。③ 这些失败涉及的 app 代码**合并没有改过**，属存量问题。
  ④ 2026-10-14 相对 10-12 少了 3 条（`follow_grouped_view_test.dart` 4→1）是关注多归属功能线
  顺手修好的旧文案断言，不是环境变化；同机合并前（`8fd14a9f`）/合并后（`5ae375f1`）两次测量
  **条数与名单逐条一致**，本次同步未引入红灯。
- 证据：`test/search_initial_site_test.dart`、`test/follow_grouped_view_test.dart`、
  `test/theme_mode_test.dart`、`test/page_view_auto_load_test.dart`、`test/viewpager_drag_test.dart`、
  `test/widget_test.dart`；`app_settings_controller.dart:76`；`test/follow_test_harness.dart:45,96`。
- 建议：先在本机改用**真机/桌面**跑 `flutter test -d windows`（有插件宿主，可消掉
  `MissingPluginException` 一类），分流「环境缺插件」与「真断言坏」；对确需真控制器的一类，
  给 `path_provider` 注入 mock（或在 harness 里 stub `getApplicationSupportDirectory`）。
  `widget_test.dart` 是脚手架残留 Counter smoke，历来失败，可直接删。
- 影响：本机测试红灯掩盖真实回归；CI 若跑 `flutter test` 会红。

## 3. P2 — 结构 / 技术债 / 功能缺口

### P2-1 设置项未抽象成 struct（批量生成 UI / 配置）

- 证据：`lib/app/controller/app_settings_controller.dart:665`（`// todo: 构造一个settings struct,用于批量生成ui和配置参数`）。`[注释]`
- 影响：设置页新增/改动的高重复度。

### P2-2 WebDAV 远程同步遗留 TODO

- 现象：启动时自动同步未做、`version.json` 未实现（注释称计划 v1.8.10）、「需一次数据同步后再限制用户完全删除 history」未做。
- 证据：`lib/modules/sync/remote_sync/webdav/remote_sync_webdav_page.dart:172`、`.../remote_sync_webdav_controller.dart:212`、`.../executor/sync_executor.dart:48`。`[注释]`
- 影响：同步功能完整性。

### P2-3 直播间 uid 匹配遗留 TODO 与临时实现

- 证据：`lib/modules/live_room/live_room_controller.dart:542`（`// todo: 更精细化的uid匹配`）、`:619`（`//todo: temp use uid == 0`）。`[注释]`
- 影响：弹幕去重 / 身份匹配精度。

### P2-4 `player_controller` 遗留 TODO

- 现象：动画不流畅、`// todo: 还应该关闭所有的dialog`、`lockControls` 临时解锁未做。
- 证据：`lib/modules/live_room/player/player_controller.dart:631`、`:656`、`:1119`。`[注释]`
- 影响：播放器交互细节。

### P2-5 弹幕字号跟随窗口缩放为临时实现（`danmakuFontResize is temp`）

- 证据：`lib/modules/live_room/player/player_controls.dart:1028`。`[注释]`
- 影响：弹幕渲染一致性。

### P2-6 关注页遗留 TODO：信息编辑占位与筛选条件设置

- 证据：`lib/modules/follow_user/follow_info_setting/follow_info_page.dart:227`（`"other todo ..."`）、`lib/modules/follow_user/follow_app_setting/follow_app_settings_page.dart:59`（`// todo：筛选条件设置`）。`[注释]`
- 影响：关注信息编辑 / 筛选功能。

### P2-7 弹幕库滚动轨道为等高网格，改写尺寸（大表情位图）后同轨/相邻轨会重叠

- 现象：库的滚动轨道是等高网格、排轨只看入轨时的文本宽高，改写尺寸后不重排。
- 证据：`lib/modules/live_room/player/player_controller.dart:551`（已知限制）。`[注释]`
- 影响：大表情弹幕观感。

### P2-8 `migration_service.dart` 迁移逻辑临时物

- 证据：`lib/services/migration_service.dart:88`（`// hive logic temp:`）。`[注释]`
- 影响：历史数据迁移的可维护性。

### P2-9 OSD 设计里明确「不做 / 二期」的部分（记录以免重开）

- 内容：容器视觉形态统一、移动端重做、4 路上限调整、拖拽换位/拖拽换台、讲解性提示条、`kMultiPlayLowQualityUnfocused` 性能降级；多路性能 spike 本设计不依赖。
- 证据：原设计稿的「明确不做」章节已内联为上面这条内容本身（设计稿文件已不在工作区）。`[spec]`
- 影响：功能范围。

### P2-10 `_appendDistinct` 每页重建 `seen` 集合，跨页 O(n²)（留作观察）

- 现象：每次调用重新遍历整个 `list` 建 set；现实规模（斗鱼类目流 120/页 × 10 页 ≈ 72 万次字符串操作）影响可忽略。
- 证据：`code-review-future-branch.md` P8；`code-review-remediation-plan.md` §5「明确不做」。`[review]`
- 建议：若后续出现更长列表或 `itemKey` 变重，把 `Set<String> _seenKeys` 提升为控制器状态。
- 影响：超长列表的滚动成本。

### P2-11 搜索页未接通服务端 `hasMore`

- 现象：四平台语义不一致（douyu 的 `relateShow.isNotEmpty` 与 page 无关），需单独实测，暂不在分页批里做。
- 证据：`code-review-remediation-plan.md` §5「明确不做」。`[review]`
- 影响：搜索翻页判定。

### P2-12 审查报告整体落地情况（仅登记残留，已修复项不再收）

- `code-review-future-branch.md` 的 P1/P2/P3/N1–N6 **已全部落地**（见 `code-review-remediation-applied.md`），未收。
- 历史 OCR 评审（记录已不在仓库）的高/中优先级绝大多数**已修复或已确认为误报**：`app_scroll_behavior.dart` 的 `-delta`（复核为与框架默认一致，误报）、`indexed_controller.dart`（`jumpToPage` + `_instantiated.add` 置后 + release 兜底）、`page_grid_view.dart`（构造函数已补 assert）、`app_style.dart`（`main.dart` 已覆盖 `backgroundColor`）、`live_room_card.dart`（胶囊已始终渲染）、`settings_switch.dart`（`width` 已夹取 + locked 断言）、`duration_2_str_utils.dart`（0 值返回空串）。**仅**表情开关（P0-5）作为残留登记。`[review]`

### P2-13 `analysis_options.yaml` 未排除 `rust_builder/`，`flutter analyze` 带出 43 个存量 error

- 现象：`flutter analyze` 除 app 代码外，还报 `rust_builder/cargokit/build_tool/**` 的 **43 个 error**；这些是 frb 构建 glue 的存量问题，与 2026-10-12 的合并无关，但污染分析输出、抬高信噪比（app 代码本身无 error）。
- 证据：`simple_live_app/analysis_options.yaml` 的 `analyzer.exclude` 仅列 `**/frb_generated.web.dart`、`build/**`、`android/**`、`ios/**`、`web/**`、`windows/**`、`macos/**`、`linux/**`，**未含** `rust_builder/**`。
- 建议：在 `analyzer.exclude` 增补 `"rust_builder/**"`（或至少 `rust_builder/cargokit/**`），并在 PR 说明排除理由；改后重跑 `flutter analyze` 应只剩 app 代码结果。
- 影响：分析器噪音、CI 判定口径。

## 4. 建议的推进批次

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 1 | P0-1（发版前全 ABI 滤镜核对） | 用户可见静音风险，零代码、只做核验 |
| 2 | P0-2 / P0-3（Android 12+ 后台真机 A/B） | 唯一只能在真机上定性的一类，且互相关联，建议成组做 |
| 3 | P1-1（iOS 上 Mac 补验） | iOS 后台整块未验证 |
| 4 | P0-5（表情开关是否恢复） | 先定性（有意/无意），再决定动作 |
| 5 | P1-6（跑 spike、定默认路数） | 弱机多开稳定性 |
| 6 | P2-1 / P2-2 / P2-4 / P2-5 | 结构性整理，配合下一次功能改动一起做 |
| 7 | 其余 P2 | 按产品优先级取舍 |
| 8 | P1-7（真机/桌面复跑 `flutter test`，分流存量红灯） | 本机红灯掩盖回归，先恢复可信基线 |
| 9 | P2-13（`analysis_options.yaml` 排除 `rust_builder/**`） | 零风险、只降噪，可随手做 |

## 5. 已决策的取舍（不修，记录原因）

| 取舍 | 原因 | 来源 |
| --- | --- | --- |
| 弹幕表情始终渲染、设置页不提供「表情包」开关 | 有意统一渲染、简化调用（有表情就渲染，没表情返回纯文本）；存储键保留以兼容将来恢复。**注**：上游 dev(v1.8.15) 已加 `danmuEmoticonEnable` 开关，本 fork 未采用（见 P0-5），此取舍待复核 | `live_room_page.dart:850`；见 P0-5 |
| 通知不绘画进度条、不推 `duration`/`updatePosition`（v1） | 直播无时间轴；发了 duration 两端都会画出拖着没反应的进度条，比没有更糟 | 见 P0-4；`[notes]` |
| 通知里的「停止」＝暂停出声 + 撤通知，不是 `player.stop()` | `player.stop()` 会推 EOS → `completed` → 触发 `mediaEnd()` 自愈重连，把「停止」当成意外断流又拉起来 | `[notes]` |
| 抢音频焦点只挂「真的推出 `playing=true`」的边沿；`refresh()` 去重不用 `PlaybackState ==` | `attach` 跟 mpv 事件率（弱网 buffering 一秒跳多回）；`PlaybackState ==` 含 `updateTime`，两次同内容状态永不相等 | `[notes]` |
| 「后台播放」与「进入后台自动暂停」互斥，由两个 setter 互相顶掉 | 两者同开时切后台即被暂停，后台播放名存实亡 | `[notes]` |
| 副格永不挂载后台播放 | 多开时四路争同一条通知只会互相顶掉 | 见 P1-2 |
| OSD 容器按宿主分：右侧面板只用于全屏/小窗/格子，窗口化（含页级「更多」）回底部抽屉 | 窗口化右侧站着聊天/SC/关注栏，再来一块 400 宽面板会整个盖掉 | 原 OSD 设计稿 §3/§8（已内联）；`[spec]` |
| 4 路上限不变；拖拽换位/换台不做 | 布局引擎与性能未评估，本批不动 | 见 P2-9 |
| 音量滑条绑的量按宿主不同（单播放绑总音量、格子绑该格系数） | 总音量是 OSD 里唯一入口，换成按路系数等于把它藏了（形态一致、语义按宿主标注） | 原 OSD 设计稿 §3/§5（已内联） |
| `followStyleNotGrid` 字段/setter/存储键刻意保留、当前无读取方 | 关注页改成「上段卡片 + 下段紧凑行」后二选一不存在，但老用户取值不丢、恢复便宜 | `app_settings_controller.dart:1197` |
| 重试条出现会扰动滚动几何，故放宽既有测试的精确计数 | 断言过严（原断言 `requestedPages == [1,2]`），非逻辑缺陷；真正要守的是「不出现请求风暴」 | `code-review-remediation-applied.md` §三.2 |