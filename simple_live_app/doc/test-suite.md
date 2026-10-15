# simple_live_app 测试案例库（面向 AI 的文字版）

> 版本锚点：`simple_live_app` v1.8.15+10815 · future 分支 `9697ab61`（2026-10-15）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)

## 1. 怎么跑

```bash
cd simple_live_app
fvm flutter test                                  # 全部离线用例（不需要网络）
fvm flutter test test/multi_play_layout_test.dart # 单个文件
fvm flutter test --plain-name "排布选择"           # 按用例名过滤
fvm flutter test integration_test/simple_test.dart -d windows   # 集成测试需指定设备（真机/桌面）
```

- 工程用 FVM 管理 Flutter（本目录 `.fvmrc` 锁 **3.47.6**；注意与 `simple_live_core` 的 3.38.4 不同）。
- `test/` 下的用例**全部为离线**（纯函数或 fake 注入），不依赖网络、不拉起真实播放器；这是与 core 目录最大的差别（core 混有联网冒烟）。
- widget test 跑在 fake-async 环境，**Hive 不可用**：凡涉及本地存储 / DBService / FollowService 的地方都用 `test/follow_test_harness.dart` 里的内存假实现（见 §5）。
- **测试假件契约（2026-10-12 补）**：任何覆写 `AppSettingsController.onInit` 的假设置**必须**写成 `Future<void> onInit() async {}`——真实 `onInit` 已是 async（`app_settings_controller.dart:76`），写成 `void onInit()` 会因签名不匹配**编译失败**（同步前 HEAD 上 6 个测试文件即如此，见 update-history.md §2.3）。另：真实 `AppSettingsController` 在 widget test 里会撞 `path_provider` 的 `MissingPluginException`（`onInit → initDataPath → getApplicationSupportDirectory`），故测试一律用假设置跳过 `onInit`，不要构造真控制器。

## 2. 现有测试资产

`simple_live_app/test/` 共 **54 个 `.dart`**（`find simple_live_app/test -name '*.dart' | wc -l`）：**53 个含用例文件**（静态声明 **523** 个 `test`/`testWidgets`）+ 1 个共享 harness（`follow_test_harness.dart`）。`fvm flutter test --no-pub` 本次**执行 549 条**（数据驱动循环用例使运行条数多于静态声明数）：**534 通过 / 15 失败**（2026-10-15 同机实测；红灯清单见 §7）。另有 `integration_test/simple_test.dart`（1 个用例，需设备）。

> 相对旧锚点 `abca65f8`（48 个 `.dart` / 465 声明 / 491 执行 / 473 通过 18 失败）的增量全部来自
> 关注多归属功能线（update-history.md §2.4）：新增 `follow_membership_test.dart`、
> `smart_group_service_test.dart`、`follow_smart_group_ui_test.dart` 三个文件，
> `follow_grouped_view_test.dart` 由 14 条增至 17 条；失败数 18→15 是其中 3 条旧文案断言被顺手修好，
> 不是外部变化。

按主题分组（用例数＝`^\s*(test|testWidgets)\(` 命中数）：

| 主题 | 文件 | 用例数 | 守护的行为 |
| --- | --- | --- | --- |
| **多开** | `multi_play_layout_test.dart` | 26 | 排布选择、位置稳定性、窗口过小折叠、最小窗口尺寸、不折叠不变量、竖屏视频区高度、默认路数 |
| | `multi_play_selection_test.dart` | 15 | 勾选→选路（剔除未开播、上限、顺序）、删格后焦点归属、关注行「加入多开」置灰判据 |
| | `multi_play_volume_test.dart` | 6 | `resolveTileVolume` 真值表（压低开关/系数/焦点） |
| | `multi_play_identity_test.dart` | 1 | 每格身份（`isSecondaryTile`/槽位） |
| | `multi_play_window_floor_test.dart` | 3 | 多开窗口收口：全屏态关格零摆窗、不采还原点；窗口态关格照旧还原 |
| **播放器动作 / 快捷键 / 音量 / OSD / 窗口几何** | `player_action_set_test.dart` | 22 | resolver：跨宿主全集一致、格子/小窗切片、常驻兜底、竖屏降级、页级「更多」、容器判据 |
| | `player_action_bar_test.dart` | 3 | 条带 renderer 渲染 |
| | `player_volume_action_test.dart` | 7 | 音量三态控件（点击静音 / 悬停滑条 / 滚轮） |
| | `player_shortcuts_test.dart` | 9 | 默认键位逐键映射、不吞不属于自己的键、改键后生效 |
| | `shortcut_binding_test.dart` | 27 | 快捷键模型结构性质（默认表覆盖全集、编解码往返、坏数据回落、冲突判定、显示名） |
| | `player_osd_metrics_test.dart` | 31 | OSD 度量：桌面断点、宽/高断点、小屏落底部表单、触控放大点击区、安全区、M3 可渲染 |
| | `player_window_geometry_test.dart` | 3 | 窗口几何纯函数（全屏↔小窗还原点） |
| | `resolve_player_fit_test.dart` | 3 | `scaleMode → fit/aspectRatio`（含按格覆盖值） |
| | `pip_aspect_test.dart` | 44 | PiP 纵横比：FrameInsets 语义、client/outer 换算、残差对照、`minLongSide` 抬升 |
| | `pip_aspect_qa_test.dart` | 44 | PiP 纵横比独立复核（零残差、幂等、非法输入、物理像素判据） |
| | `danmaku_settings_surface_test.dart` | 2 | 弹幕设置弹层形态 |
| **分页与列表** | `base_page_controller_paging_test.dart` | 11 | 采信服务端 `hasMore`、`itemKey` 去重、连续两页零新增才停、失败重试标记、别名回归 |
| | `page_view_auto_load_test.dart` | 12 | 触底自动补页、空列表不加载、失败门闩与重试条（真 `IndexedPage`/`PageGridView`） |
| | `page_view_skeleton_test.dart` | 6 | 加载骨架 |
| | `page_grid_view_sections_test.dart` | 3 | 分段渲染（关注页上段网格 + 下段行） |
| | `page_end_bar_test.dart` | 12 | 「已到底」条、首页列数 `resolveHomeColumns` |
| | `viewpager_drag_test.dart` | 2 | 鼠标左键横拖切页 |
| | `smooth_wheel_scroll_test.dart` | 4 | `SmoothWheelScrollController` 滚轮动画 |
| | `desktop_scroll_behavior_test.dart` | 7 | 桌面 `dragDevices` 放开 |
| | `ticker_offstage_test.dart` | 4 | `TickerOffstage`（常驻 Offstage 时停动画） |
| **弹幕 / 表情渲染** | `danmaku_emoticon_test.dart` | 18 | 弹幕表情分段、`canRender`、图源句柄生命周期、`apply`、大表情位图高度 |
| | `chat_emoticon_span_test.dart` | 14 | 聊天区消息 span 构建、上下文菜单判据 |
| **关注页** | `follow_search_test.dart` | 5 | 搜索过滤 |
| | `follow_grouped_view_test.dart` | 17 | 分组卡片/计数 pill/折叠、拖头像换组、拖把手调序、视图切换；**多归属**：拖进别组=加入且原组仍可见、已在组内的成员拖回本组不高亮、空分组+选择态计数 Obx 不抛「没有可观察变量」 |
| | `follow_group_filter_test.dart` | 8 | **分组胶囊筛选 + 模式切换**（2026-10-15 新增）：无自定义分组不出胶囊行、点胶囊=平铺该组成员（别的组/未分组不可见）、多归属筛选态去重、筛选态隐藏折叠全部按钮、筛选态搜索无匹配浮层、幽灵 id 回落总览、「模式切换」仅筛选态出现且紧凑/卡片切换生效、跨 tab 保持、卡片模式落存储 |
| | `follow_membership_test.dart` | 16 | **归属唯一真源 = 成员表**（2026-10-12 新增）：`FollowService` 归属 API 5 条（多归属加入/重复加入不产生重复成员/只移出该组/未知组名不抛异常/清空全部归属）、`groupedView` 按 userId 分桶 4 条（出现在每个所属组/无归属落未分组/组内顺序继承 list 而非 userId/忽略幽灵 id）、JSON 导出导入 2 条（`generateJson` 带 `tags`、`inputJson` 认 `tags` 也认旧版单 `tag`）、备份向后兼容 3 条（旧→新、新→旧、往返）、WebDAV 合并 2 条（按分组名并集保住多归属、剔除幽灵与墓碑） |
| | `smart_group_service_test.dart` | 9 | **`SmartGroupService` 纯逻辑**（2026-10-12 新增）：preview 按平台汇总人数/标记同名组已存在、execute 建组填人/多归属不冲掉手工组/幂等（第二次 0 新增）/未知平台跳过不建空组/无关注不建组、派生统计字段（`pendingTotal`/`newTagCount`/`skippedUnknownSite`）、`siteSort` 不全时缺掉的已知平台照常归组且不算「未知平台」 |
| | `follow_smart_group_ui_test.dart` | 3 | **智能分组两处 UI 入口**（2026-10-12 新增）：顶栏 ⋮ 菜单点开预览→确认→完成归组、无可归组内容时只 toast 不弹空表、关注设置页入口同行为（并钉住「设置页不碰 `FollowUserController`」） |
| | `follow_user_sections_test.dart` | 6 | 上段直播中 / 下段未开播分段 |
| | `follow_tag_reorder_test.dart` | 3 | 标签重排 |
| | `follow_user_item_trailing_test.dart` | 2 | 行尾尾部控件（宿主**未注册** `FollowService`，钉住行组件的 `isRegistered` 兜底不崩） |
| | `collapsible_top_bar_follow_test.dart` | 4 | 关注页顶栏收起 |
| **导航 / 主题 / 系统 UI** | `navigation_dock_test.dart` | 24 | 胶囊导航：尺寸布局、点击切换、拖动透镜、参数校验、几何纯函数、桌面悬停 |
| | `theme_mode_test.dart` | 6 | 主题模式索引 |
| | `system_ui_inset_test.dart` | 8 | 系统安全区 inset |
| | `indexed_jump_transition_test.dart` | 4 | 跨 Tab 跳切过渡 |
| | `search_initial_site_test.dart` | 9 | 首页 tab→平台 id 映射、搜索页初始平台 |
| | `home_site_id_test.dart` | 3 | 首页平台 id |
| **设置 / 通用控件** | `settings_switch_locked_test.dart` | 4 | `SettingsSwitch` locked/lockedHint 行为 |
| | `m3e_loading_indicator_test.dart` | 9 | M3E 加载指示器（禁用不出帧、默认多边形） |
| | `app_popup_menu_item_test.dart` | 3 | 自定义菜单项内缩/圆角 |
| | `net_image_size_test.dart` | 1 | 网络图尺寸参数 |
| | `desktop_secondary_tap_test.dart` | 3 | 桌面右键（副键）点击 |
| **工具函数** | `tool_test.dart` | 8 | 拼音/路径正则、抖音 URL 解析 |
| | `duration_2_str_utils_test.dart` | 6 | 「累计观看 N」文案三档 + 无记录 |
| | `room_watch_clock_test.dart` | 6 | 观看计时 |
| | `widget_test.dart` | 1 | 脚手架残留 smoke（`Counter increments smoke test`），**历来失败**，与业务无关 |
| **harness（无用例）** | `follow_test_harness.dart` | 0 | 关注页 widget 测试的共享 fake + 泵取工具 |
| **集成测试** | `integration_test/simple_test.dart` | 1 | Rust 桥（`RustLib.init` + `MyApp`），需设备 |

## 3. 覆盖矩阵

| 子系统 | 离线测试 | 说明 |
| --- | --- | --- |
| 多开（布局/选中/音量/身份） | ✅ | 纯函数 + 布局，覆盖充分 |
| 播放器动作 resolver / 条带 renderer | ✅ | 含跨宿主一致性断言 |
| 快捷键模型（默认表/编解码/冲突） | ✅ | 结构性质全覆盖 |
| 音量三态控件 | ✅ | 控件级 |
| OSD 度量 | ✅ | 断点与安全区 |
| PiP 纵横比 / 窗口几何 | ✅ | 纯函数；**真实 `window_manager` 调用无自动化** |
| 分页与列表（含别名/门闩/去重） | ✅ | 含 `IndexedPage` 级用例 |
| 弹幕/表情渲染（分段、图源） | ✅ | 渲染层 |
| 关注页（搜索/分组/分段/标签） | ✅ | 已补齐（此前无） |
| 关注**多分组归属**（成员表读写/分桶/备份双字段/WebDAV 并集） | ✅ | `follow_membership_test.dart` 16 条（2026-10-12 新增）；**降级到旧版本 app 的归属丢失无自动化**，靠 PR 手工验收清单 |
| **一键按平台智能分组** | ✅ | 纯逻辑 `smart_group_service_test.dart` 9 条 + 两处入口 `follow_smart_group_ui_test.dart` 3 条；真机首次体验仍属手测 |
| 导航/主题/系统 UI/设置控件 | ✅ | |
| **音频焦点 / 后台播放状态机** | ❌ | `live_audio_session.dart`、`live_playback_audio_handler.dart` 无离线用例（依赖平台插件） |
| **Android 前台服务 / MediaSession / 唤醒锁** | ❌ | 天然缺口，只能真机验收 |
| **iOS 后台音频会话** | ❌ | 天然缺口，开发机为 Windows |
| **真实窗口行为（PiP 收放、置顶、标题栏）** | ❌ | `window_manager` 需真实窗口，纯函数外的部分无自动化 |
| **弹幕解码（4 平台协议）** | ❌ | 归属 `simple_live_core`，见 core 的 test-suite.md |
| **网络层（下载/断点续传/请求）** | ❌ | `requests/http_client.dart` 无离线用例 |
| **WebDAV 同步 / Rust builder** | ❌ | 集成面，仅 `integration_test` 触及 Rust 桥 |

## 4. 文字版测试案例库

约定：`[已有]` ＝ 现有用例已覆盖（给出来源文件）；`[待补]` ＝ 建议新增（给出实现要点）。用例描述已足够 AI 直接转写为 `test()`/`testWidgets()`。

### 4.1 多开（TC-A-1xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-101 | 1/2/3/4 路时的网格排布 | 按路数选出正确 `rows×cols` | 【已有：multi_play_layout_test.dart】 |
| TC-A-102 | 增删一路后既有格位置不跳变 | 位置稳定性不变量 | 【已有：同上】 |
| TC-A-103 | 窗口缩到默认路数放不下 | 折叠策略（保聚焦、先丢谁） | 【已有：同上】 |
| TC-A-104 | 窗口小于最小尺寸 | 最小窗口尺寸约束 | 【已有：同上】 |
| TC-A-105 | 竖屏多开的视频区高度 | 与设定一致 | 【已有：同上】 |
| TC-A-106 | 勾选含未开播用户 | 先剔除未开播再判上限，未被开播项不占位 | 【已有：multi_play_selection_test.dart】 |
| TC-A-107 | 勾选 > 4 位在播 | `tooMany` 且**不偷偷截断** | 【已有：同上】 |
| TC-A-108 | 删格后焦点归属 | 删聚焦前→前移；删后→不动；删自己→夹到末格；越界夹回 | 【已有：同上】 |
| TC-A-109 | 关注行「加入多开」图标判据 | 不在多开→显示；已在（主格/副格一律）→不显示 | 【已有：同上】 |
| TC-A-110 | `resolveTileVolume` 真值表 | 压低关＝聚焦与否同值；开＝非聚焦乘 ratio；系数 0＝静音；结果恒 ≤ 总音量 | 【已有：multi_play_volume_test.dart】 |
| TC-A-111 | 每格身份 | `isSecondaryTile` / 槽位正确 | 【已有：multi_play_identity_test.dart】 |
| TC-A-112 | 多开达到 4 路上限再加 | toast「已满 4 路」且不新增 | 【待补】需 fake `MultiPlaySession`，断言 `slots.length` 与提示 |
| TC-A-113 | 副格不挂后台播放通知 | `isSecondaryTile==true` 时 handler 不 attach | 【待补】对应 backlog P1-2 |
| TC-A-114 | 多开中进全屏后关掉副格 | 窗口保持全屏、主格单画面铺满；不得出现「全屏态 + 窗口化尺寸」半态 | 【已有：multi_play_window_floor_test.dart】 |

### 4.2 播放器动作与 OSD（TC-A-2xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-201 | 桌面 `windowed` 与 `fullscreen` 动作全集相等 | `bar ∪ overflow` 的 id 集合相同 | 【已有：player_action_set_test.dart】 |
| TC-A-202 | 截图/选台/画面尺寸/小窗在窗口化与全屏都在场 | 四项 `containsAll` | 【已有：同上】 |
| TC-A-203 | 窄窗口 | 动作**不消失**，只沉进 `⋮`；`bar` 变短 | 【已有：同上】 |
| TC-A-204 | 格子宿主 | 永不含 `smallWindow`；`closeTile` 只在可关时出现 | 【已有：同上】 |
| TC-A-205 | 小窗宿主 | 平铺恰好四件（退出小窗/全屏/弹幕/音量）+ `⋮` | 【已有：同上】 |
| TC-A-206 | 常驻件在任何宽度都留在条带 | `core` 件不被收进 `⋮` | 【已有：同上】 |
| TC-A-207 | 竖屏主播的清晰度/线路 | 从 `Offstage` 改为降级进 `⋮`（不消失） | 【已有：同上】 |
| TC-A-208 | 页级「更多」与视频区「⋮」同源 | 内容来自同一 resolver，页级列全集 | 【已有：同上】 |
| TC-A-209 | 条带 renderer 渲染 | 动作按 `rightSide` 分簇、`⋮` 在右 | 【已有：player_action_bar_test.dart】 |
| TC-A-210 | OSD 断点（宽/高、安全区、触控放大） | 与约定参数一致 | 【已有：player_osd_metrics_test.dart】 |
| TC-A-211 | 小屏 OSD | 落到底部表单形态 | 【已有：同上】 |
| TC-A-212 | 弹幕设置弹层形态 | 按宿主选容器 | 【已有：danmaku_settings_surface_test.dart】 |
| TC-A-213 | `⋮` 打开后的容器判据 | 全屏/小窗/格子＝右侧面板；窗口化＝底部抽屉 | 【已有：player_action_set_test.dart「容器判据」】 |
| TC-A-214 | 触屏静音入口 | 触屏平台提供静音入口 | 【已有：同上「触屏静音入口」】 |

### 4.3 快捷键（TC-A-3xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-301 | 默认键位逐键映射 | space/F/ESC/D/P/M/S/L/R、方向键、Q/G、Enter、1–4 各自命中约定动作 | 【已有：player_shortcuts_test.dart】 |
| TC-A-302 | 不吞不属于自己的键 | W/E/T/V、Tab、修饰键、Home/End/PgUp/PgDn、digit0/5 均未映射 | 【已有：同上】 |
| TC-A-303 | 字母键默认只占约定 9 个 | 反向遍历 a–z 命中集合与白名单完全相等 | 【已有：同上】 |
| TC-A-304 | 默认表覆盖每一个动作 | 新增动作忘配键则会红 | 【已有：同上】 |
| TC-A-305 | 快捷键模型结构性质 | 编解码往返、坏数据回落默认、修饰键严格相等、冲突判定 | 【已有：shortcut_binding_test.dart】 |
| TC-A-306 | 改键后旧键失效、新键接管 | 断言新键命中、旧键为 null | 【已有：player_shortcuts_test.dart】 |
| TC-A-307 | 冲突检测覆盖自定义键与另一动作冲突 | `findConflict` 返回被顶掉的动作 | 【已有：shortcut_binding_test.dart「冲突判定」】 |

### 4.4 音量（TC-A-4xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-401 | 点击音量图标 | 静音本路（`volumeFactor` 0↔上次值），不落盘 | 【已有：player_volume_action_test.dart】 |
| TC-A-402 | 悬停出滑条 | 单播放绑总音量、格子绑该格系数 | 【已有：同上】 |
| TC-A-403 | 滚轮 ±5% | 百分比浮层出现并在 1.2s 后消失 | 【已有：同上】 |
| TC-A-404 | 总音量写 0 时图标仍为 `volume_up` | 静音语义只读 `volumeFactor` | 【已有：同上】 |

### 4.5 窗口 / PiP 几何（TC-A-5xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-501 | PiP 纵横比换算（client/outer/insets） | 各分支公式与固定样例一致 | 【已有：pip_aspect_test.dart、pip_aspect_qa_test.dart】 |
| TC-A-502 | 非法/边界输入 | 负值归零、`minLongSide` 抬升、容差边界 | 【已有：同上】 |
| TC-A-503 | 幂等性 | 复合映射 `F(F(x))==F(x)` | 【已有：pip_aspect_qa_test.dart】 |
| TC-A-504 | 窗口几何还原点纯函数 | 全屏↔小窗的还原尺寸/位置 | 【已有：player_window_geometry_test.dart】 |
| TC-A-505 | `resolvePlayerFit` | scaleMode→fit/aspectRatio，按格覆盖优先于全局 | 【已有：resolve_player_fit_test.dart】 |
| TC-A-506 | 真实窗口四条 PiP 路径 | 窗口→小窗→退出／窗口→全屏→退出／窗口→全屏→小窗→退出／窗口→小窗→全屏→退出，均落回进全屏前尺寸 | 【待补】`window_manager` 需真实窗口，属手测矩阵；对应 backlog P1 平台脆弱点（见 spec §7） |
| TC-A-507 | `SmoothWheelScrollController` 边界 | `initialScrollOffset`/`keepScrollOffset` 透传、连续滚轮目标累加、贴边行为、`delta==0` 停惯性、方向上报 | 【已有：smooth_wheel_scroll_test.dart（部分）】；完整 5 条待补（见 review low#31） |

### 4.6 分页与列表（TC-A-6xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-601 | 服务端 `hasMore=false` | 第一页后即停、`canLoadMore==false`、非空 | 【已有：base_page_controller_paging_test.dart】 |
| TC-A-602 | 服务端 `hasMore=true` | 可续加载、跨页无重复 | 【已有：同上】 |
| TC-A-603 | 接口忽略翻页参数 | **连续两页**零新增才停（单页零新增不判死） | 【已有：同上】 |
| TC-A-604 | 未实现 `itemKey` 的子类 | 保持旧行为（不去重、非空即可加载） | 【已有：同上】 |
| TC-A-605 | 空页 | `pageEmpty==true`、停止加载 | 【已有：同上】 |
| TC-A-606 | 非首页失败 | 置起 `loadMoreFailed`（可观察），失败页**不自增** | 【已有：同上】 |
| TC-A-607 | `retryLoadMore()` | 先解闩再加载，重试的是同一页（`[1,2,2]`），成功后重试条消失 | 【已有：同上】 |
| TC-A-608 | 别名回归 | `getData` 返回外部 List 时页面列表不共享引用；自赋值/`retainWhere` 不清空、不改数据源 | 【已有：同上 `_aliasingRegressionTests`】 |
| TC-A-609 | 触底自动补页 | 真 `IndexedPage`/`PageGridView` 走 `AutoLoadOnScroll` | 【已有：page_view_auto_load_test.dart】 |
| TC-A-610 | 空列表 | 不触发自动加载 | 【已有：同上】 |
| TC-A-611 | 短列表补页失败 | 展示「加载失败，点击重试」→ tap → 重新发起请求 | 【已有：page_view_auto_load_test.dart（P2 端到端）】 |
| TC-A-612 | 分段渲染（关注页） | 上段网格 + 下段行；空段整段跳过；末段补 `gridPadding.bottom` | 【已有：page_grid_view_sections_test.dart（部分）】；空段/底部留白待补（见 review low#14） |
| TC-A-613 | 「已到底」条 | 判据是 `showEndBar`（无下一页），与平台无关 | 【已有：page_end_bar_test.dart】 |
| TC-A-614 | 鼠标左键横拖切页 | 桌面放开 `dragDevices` | 【已有：viewpager_drag_test.dart、desktop_scroll_behavior_test.dart】 |

### 4.7 弹幕与表情（TC-A-7xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-701 | 弹幕表情分段 | 有 `name` 定位、无 `name` 追加末尾；占位符匹配 | 【已有：danmaku_emoticon_test.dart】 |
| TC-A-702 | `DanmakuEmoticonRenderer.canRender` | 门禁判据 | 【已有：同上】 |
| TC-A-703 | 图源句柄生命周期 | 引用计数/回收 | 【已有：同上】 |
| TC-A-704 | 大表情位图高度 | 与库等高网格约束一致（已知限制见 backlog P2-7） | 【已有：同上】 |
| TC-A-705 | 聊天区 span 构建 | `buildChatMessageSpans` 分段正确 | 【已有：chat_emoticon_span_test.dart】 |
| TC-A-706 | 上下文菜单判据 | `shouldShowContextMenu` | 【已有：同上】 |
| TC-A-707 | 弹幕消息上限/节流 | 大房间刷屏时的 UI 上限 | 【待补】 |

### 4.8 关注页（TC-A-8xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-801 | 搜索过滤 | 命中 remark/userName/title | 【已有：follow_search_test.dart】 |
| TC-A-802 | 上段「直播中」/ 下段「未开播」分段 | `liveStatus==2` 归上段、`0/1` 归下段 | 【已有：follow_user_sections_test.dart】 |
| TC-A-803 | 分组视图 | 分组卡片/计数 pill/折叠、拖头像换组、拖把手调序、视图切换 | 【已有：follow_grouped_view_test.dart】 |
| TC-A-804 | 标签重排 | `reorderFollowTag` 的索引语义（已删旧位的 newIndex） | 【已有：follow_tag_reorder_test.dart】 |
| TC-A-805 | 行尾尾部控件 | trailing 按状态显示 | 【已有：follow_user_item_trailing_test.dart】 |
| TC-A-806 | 关注页顶栏收起 | `BarCollapse` 平移量 | 【已有：collapsible_top_bar_follow_test.dart】 |
| TC-A-807 | 内置标签保留字 | 自定义标签不得占用「全部/直播中/未开播」 | 【待补】对应 review medium#25 的残留（`isReservedTagName`） |
| TC-A-808 | 加载中不误显「没有匹配的关注」浮层 | 搜索词非空 + 正在加载时不显示 | 【已有：follow_user_page.dart 逻辑，测试待补】 |
| TC-A-809 | `hideRemoveFollowButton` 透传到下段紧凑行 | 上/下两段取关按钮一致 | 【待补】对应 review medium#10 |
| TC-A-810 | 归属唯一真源 = `FollowUserTag.userId` 成员表 | 加入某组不动它已在的其他组；移出只动该组；`removeAllTagsFromUser` 清空回未分组；未知组名静默返回不抛异常 | 【已有：follow_membership_test.dart】 |
| TC-A-811 | `groupedView` 按 `userId` 分桶 | 一个关注出现在它的**每个**所属分组；不在任何成员表里的落未分组；组内顺序继承 `list` 顺序而非 `userId` 顺序；成员表里指向已取关的幽灵 id 被忽略 | 【已有：follow_membership_test.dart】 |
| TC-A-812 | 备份向后兼容（双字段） | 导出同带 `tag`（主分组，旧版本只认它）与 `tags`（全量归属）；导入优先 `tags`、无则回退旧版单 `tag`；导出→清空→导入归属不丢 | 【已有：follow_membership_test.dart】 |
| TC-A-813 | WebDAV 关注合并 | 同名分组按**分组名取成员并集**（非覆盖），并按存活关注 id 过滤幽灵与墓碑 | 【已有：follow_membership_test.dart】 |
| TC-A-814 | 拖拽的「同组」判据看成员表 | 已在组内的成员拖回本组**不高亮**（不该假装发生了移动）；拖进别组＝加入、原分组里仍然可见 | 【已有：follow_grouped_view_test.dart】 |
| TC-A-815 | 智能分组纯逻辑 | `preview` 只算不改并标记同名组是否已存在；`execute` 建组填人、复用同名组、**幂等**（第二次 0 新增）、未知平台跳过不建空组、无关注不建组；`siteSort` 不全时缺掉的已知平台照常归组且不算「未知平台」 | 【已有：smart_group_service_test.dart】 |
| TC-A-816 | 智能分组两处 UI 入口 | 关注页顶栏 ⋮ 与关注设置页都走同一份 `startSmartGrouping`；无可归组内容时只 toast 不弹空表；设置页入口**不得**拉起 `FollowUserController` | 【已有：follow_smart_group_ui_test.dart】 |
| TC-A-817 | 空分组 + 选择态的计数 `Obx` | `Obx` 内无条件读一次 `selectedIds.length` 登记订阅，不再抛「没有可观察变量」/ `[Get] the improper use of a GetX` | 【已有：follow_grouped_view_test.dart】 |

### 4.9 导航 / 主题 / 系统 UI / 设置控件（TC-A-9xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-901 | 胶囊导航几何/点击/拖动透镜 | 尺寸布局、点击切换、拖动透镜、参数校验、几何纯函数、桌面悬停 | 【已有：navigation_dock_test.dart】 |
| TC-A-902 | 主题模式索引 | 与设置项一一对应 | 【已有：theme_mode_test.dart】 |
| TC-A-903 | 系统安全区 inset | `measureFrameInsets` 等 | 【已有：system_ui_inset_test.dart】 |
| TC-A-904 | 跨 Tab 跳切过渡 | 跳切用 `jumpToPage` + `_JumpTransition`（不扫过空白占位） | 【已有：indexed_jump_transition_test.dart】 |
| TC-A-905 | 首页 tab→平台 id 映射 & 搜索页初始平台 | 与 `Sites.supportSites` 一致 | 【已有：search_initial_site_test.dart、home_site_id_test.dart】 |
| TC-A-906 | `SettingsSwitch` locked/lockedHint | locked 时点击不改值、出提示；非 locked 正常回调 | 【已有：settings_switch_locked_test.dart】 |
| TC-A-907 | M3E 加载指示器 | 禁用不出帧；默认多边形不可变 | 【已有：m3e_loading_indicator_test.dart】 |
| TC-A-908 | 桌面右键副键 | 副键点击行为 | 【已有：desktop_secondary_tap_test.dart】 |
| TC-A-909 | 主题切换（改主题色/动态取色） | AppBar 与页面底色不出现色差 | 【待补】对应 backlog 已决策取舍（`main.dart` 覆盖 `backgroundColor`） |

### 4.10 工具函数（TC-A-10xx）

| ID | 用例（契约） | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A-1001 | 「累计观看 N」文案 | 0 值返回空串；≥3600 小时、≥60 分钟、其余秒 | 【已有：duration_2_str_utils_test.dart】 |
| TC-A-1002 | 观看计时 | `RoomWatchClock` | 【已有：room_watch_clock_test.dart】 |
| TC-A-1003 | 拼音/路径正则/抖音 URL 解析 | 数字/字母/带点号 ID 均正确 | 【已有：tool_test.dart】 |

## 5. 写新测试的约定

1. **离线优先**：本目录不写联网用例；任何需要网络的东西注入 fake。
2. **纯函数优先**：`player_actions.dart` / `multi_play_volume.dart` / `multi_play_layout.dart` / `multi_play_selection.dart` / `pip_aspect.dart` / `shortcut_binding.dart` / `resolve_player_fit.dart` 都是**纯逻辑**，直接 import 断言，不要搭 widget。（范式：`multi_play_volume_test.dart`、`player_action_set_test.dart`。）
3. **控制器级**：继承真实控制器、只覆写 `getData`/`handleError`（范式：`base_page_controller_paging_test.dart` 的 `PagedRoomController`、`_FailOnceSecondPageController`）。注意 `handleError` 会走 SmartDialog，测试里必须覆写成空实现。
4. **widget 级 + 关注页 harness**：`follow_test_harness.dart` 提供：
   - `FakeSettings`（`onInit` 置空，不读 Hive；`firstRun=false`）、`FakeLocalStorageService`（内存 `Map`，否则 setter 抛 `GetFindCanceled`）、`FakeFollowService`（内存实现归属 API：`addUserToTag:102`/`removeUserFromTag:113`/`removeAllTagsFromUser:124`/`addFollowUserTag:131`/`reorderFollowTag:142`；真实现要经 Hive 与 `DBService` 故必须覆写。⚠️ 旧的 `setFollowTag` 假件已随字段删除消失，别再照旧名覆写）、`FakeHomeListController`（只给第一页）；
   - `pumpIndexed()`：`Get.reset()` → `Get.put` 各 fake → `pumpWidget(GetMaterialApp(scrollBehavior: AppScrollBehavior, observers/builder: FlutterSmartDialog, home: IndexedPage))`；必须打桩 `Utils.packageInfo`（我的页读版本号，否则 build 抛 `LateInitializationError`）；
   - 多用 `tester.pump(Duration)` 推进，**不要 `pumpAndSettle`**（easy_refresh 有循环动画会挂）；收尾用 `settleEnd()` 跑完 easy_refresh 的 400ms 完成计时器，否则 teardown 报 pending timer。
5. **禁止跑 `dart format`**：仓库按 80 列手工折行；`analysis_options.yaml` 的 `formatter.page_width: 120` 是另一回事。
6. **命名**：文件 `<域>_<行为>_test.dart`；用例名用中文描述行为 + 括号给关键条件；`reason:` 写明「为什么这个断言值得守护」。
7. **契约变更时**：先改测试期望值，并在 PR 说明里引用本文件 ID（如「TC-A-603 判据由单页零新增改为连续两页」），让行为变更有据可查。

## 6. 与 backlog 的对应

- §4.1 TC-A-112 / TC-A-113 对应 backlog **P1-6**（多开资源上限）与 **P1-2**（副格不挂通知）；
- §4.5 TC-A-506 / TC-A-507 对应 backlog 已决策取舍（PiP 几何链）与 review low#31（`SmoothWheelScrollController` 补测）；
- §4.2/§4.4 是 backlog「已决策取舍」里「音量滑条按宿主绑定」「OSD 容器按宿主分」的护栏；
- §4.8 TC-A-807 / TC-A-809 对应历史 OCR 评审两条残留（评审记录已不在仓库）：内置标签保留字 `isReservedTagName` 的门禁、`hideRemoveFollowButton` 透传到下段紧凑行——两处代码均已修，缺回归用例；
- §4.9 TC-A-909 对应 `app_style.dart` 的 AppBar 底色取舍（`main.dart` 覆盖）——一旦有人只改一处会在这里先红；
- backlog **P0-2/P0-3/P1-1**（后台播放/Android 前台服务/iOS）在本目录**无离线测试**，只能靠真机手测矩阵（即 backlog 各条建议里列出的验收动作），属 §3 的天然缺口。
- backlog **P1-7**（本机 15 个存量失败）即 §7 的红灯清单。

## 7. 已知红灯清单（2026-10-14 本机，`fvm flutter test --no-pub` 507 通过 / 15 失败）

> 性质：**存量问题**——这些文件在同步前 HEAD（`3714eec1`）因 6 个测试假件 `onInit` 签名不匹配
> 而**无法编译**；本次把签名改成 `Future<void>` 后编译器放过，暴露为运行期失败。涉及的 app 代码
> 合并没有改过。诊断与建议见 backlog P1-7。

| 文件 | 失败数 | 原因（已核实/推定） |
| --- | --- | --- |
| `search_initial_site_test.dart` | 9 | 需真实设置/环境，撞 `AppSettingsController.onInit` → `getApplicationSupportDirectory()` 的 `MissingPluginException`（widget test 无 path_provider 宿主） |
| `theme_mode_test.dart` | 2 | 主题模式读设置值，受真实 `onInit` 影响 |
| `follow_grouped_view_test.dart` | 1 | 「tab 变视图切换：直播中=卡片网格，未开播=紧凑行」——几何依赖真控制器，视图切换断言找不到控件 |
| `page_view_auto_load_test.dart` | 1 | 「鼠标滚轮滚到底部自动加载」——真 `IndexedPage` 路径受环境/几何扰动 |
| `viewpager_drag_test.dart` | 1 | 「关注页：鼠标左键横拖切换视图 Tab（全部→直播中）」——横拖切页断言（几何/环境相关） |
| `widget_test.dart` | 1 | 脚手架残留 Counter smoke，**历来失败**，与业务无关 |

- **2026-10-14 相对 10-12 的变化**：失败 18→15 全部来自关注多归属功能线顺手修好 `follow_grouped_view_test.dart`
  的 3 条旧文案断言（4→1），不是外部/环境问题。
- **同步门证据（merge `5ae375f1`）**：同机跑两次——合并前 `8fd14a9f` 与合并后 `5ae375f1` 都是
  **507 通过 / 15 失败**，且 15 条**失败名单逐条一致**，所以上面这批红灯与本次同步无关。
- **未修复说明**：本批只修「签名编译」这一类（属于同步的连带修复），其余 15 条按「存量」留待专门一轮；**不掩盖**、不外推为业务回归。复跑建议见 backlog P1-7（真机/桌面 `flutter test -d windows`，或给 `path_provider` 注入 mock）。