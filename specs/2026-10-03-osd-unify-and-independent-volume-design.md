# 播放 OSD 统一 + 每路独立音量 · 设计

日期：2026-10-03
范围：`simple_live_app` 直播间播放覆盖层（窗口化 / 全屏 / 小窗 / 多开格）与多开音频模型
不在范围：容器视觉形态统一、移动端重做、4 路上限调整（见 §11）

## 1. 背景

多开播放的基础设施已落地（见 `plans/ardent-vent-stickleback.md`、`plans/inner-moor-skua.md`），
暴露出两个问题：

1. **音频只有「焦点」一种模型**。聚焦一格就把其余几路按固定比例压低，部分人用不习惯：
   他要的是「每一路都能独立控制」，而不是「焦点自动决定谁响」。
2. **播放 OSD 有三套并存实现，控件集合互有缺口**。同一个动作在不同模式下有的有、有的没有，
   连「音量」这颗图标在单播放与多开下绑的都是两个不同的量。

三套实现分别是：`player_controls.dart:50` `buildFullControls`（全屏）、
`player_controls.dart:471` `buildControls`（窗口化）、`multi_play_tile.dart:25` `MultiPlayTile`（格子）。

## 2. 已确认的不一致（逐条对着代码）

| 动作 | 窗口化 | 全屏 | 小窗 | 格子 | 依据 |
|---|---|---|---|---|---|
| 截图 | ✗ | ✓ 顶栏 | ✓ 顶栏 | ✗ | `player_controls.dart:164` |
| 关注列表／换台 | ✗（要绕页级菜单） | ✓ 顶栏 | ✓ 顶栏 | ✓ `▾` | `player_controls.dart:175` / `multi_play_tile.dart:220` |
| 画面尺寸 | ✗（要绕页级菜单） | ✓「更多设置」 | ✓ | ✗ | `player_controls.dart:200` |
| 小窗播放（桌面） | ✓ | **✗** | ✓ | 拒绝并 toast | `player_controls.dart:631` / `:186` 只有安卓 PIP |
| 清晰度／线路 | 竖屏时 `Offstage` | ✓ | ✓ | 收在 `⋮` | `player_controls.dart:595`、`:615` |
| 音量 | ✓ 弹**总音量**滑条 | ✓ 弹**总音量**滑条 | ✓ | ✓ 改**该格系数** | `live_room_controller.dart:947` / `multi_play_tile.dart:415` |
| 页级动作（分享/复制/APP 打开/播放信息/定时关闭） | 底部抽屉 | ✗ | ✗ | ✗ | `live_room_page.dart:1015`、`:998` |

「全屏进不了小窗」不完全是漏放按钮，后面还压着一个真实缺陷：见 §7。

## 3. 决定记录（他逐项拍的，勿擅自改向）

- **压低保留、但默认关**。新增设置开关「非聚焦自动压低」，默认关闭；原有的比例旋钮保留。
- **每格独立控制**：音量三处同形——**点击＝静音本格**（保住现在的手感）、**悬停＝出滑条**、
  **滚轮＝±5%**，百分比浮层照旧。
- **一致性口径＝动作集合一致，不是容器统一**。窗口化仍是一条通栏、全屏仍是上下两条带、
  格子仍是两个 hug 控件的胶囊；同一份清单按可用宽度决定平铺还是收进 `⋮`。
- **只管桌面**。移动端继续跑现在这套，靠平台判定隔离，要求是「不回归」。
  **修订（2026-10-03 写计划时定）：移动端完全不进这套模型**——`playerControls` 与页级「更多」
  都以平台门短路，安卓/iOS 走现有代码路径；resolver 只为桌面产出，不产出移动端清单。
- ~~**清单类弹层统一成右侧抽屉**~~ → **修订（2026-10-04 手测后）：容器按宿主分，回到改造前口径。**
  右侧面板**只**用于全屏（外加小窗与格子）；桌面窗口化（含页级 AppBar 那颗「更多」）落回**底部抽屉**——
  改造前窗口化条带的清晰度／线路／弹幕设置本来就是 `showQualitySheet`/`showPlayUrlsSheet`/`showDanmuSettingsSheet`，
  页级「更多」本来就是 `showModalBottomSheet`；窗口化右侧站着聊天／SC／关注那一栏，再来一块 400 宽的面板会把它整个盖掉。
  判据一处定义：`usesRightPanelSurface(host) => host != PlayerHost.windowed`，**由调用方（宿主）传给弹层本体**，
  本体不猜平台——移动端两条老 builder 从不传这个参数，行为逐字不变。
- **`▾` 换台与音量滑条是例外，保留贴着按钮的锚定浮层**；~~全屏顶栏那颗「关注列表」因此也改成锚定浮层~~
  （这条 2026-10-03 已被推翻，见 §8：换台按宿主分形态）。
- **画面尺寸做按格独立**。
- **小窗（PiP）态平铺收敛成四件**：退出小窗／全屏播放／弹幕开关／音量，其余全收进 `⋮`；
  小窗态不出顶栏。
- **页级 AppBar「更多」与 OSD 共用同一份清单**：清单同源；容器两支都是底部抽屉
  （这页此刻就是窗口化），只是桌面那份来自 resolver、移动那份是原有硬编码清单。

一处显式取舍，要反对就说：滑条绑的量按宿主不同——单播放绑**总音量**（`playerVolume`，OSD 里
唯一入口，丢了就没地方调了），格子绑**该格系数**（`volumeFactor`）。形态一致、语义按宿主标注
（浮层标题写 `总音量` / `第 2 路`）。

## 4. 架构

```
PlayerHostContext ──▶ resolvePlayerActions()  ──▶ List<PlayerAction>
   (纯输入)              player_actions.dart         (纯输出，可单测)
                                                          │
                        player_action_views.dart ◀────────┘
                     (id → 真实调用 + 弹层形态)
                          │
        ┌─────────────────┼──────────────────┐
   windowed/fullscreen  tile              AppBar 更多
   (player_controls)  (multi_play_tile)  (live_room_page)
```

新增文件：

- **`lib/modules/live_room/player/player_actions.dart`**（纯逻辑：只有数据、判断与收纳规则，
  不出现 `StatelessWidget`/`build`，可以像 `multi_play_layout.dart` 那样直接单测）
  - `enum PlayerHost { windowed, fullscreen, smallWindow, tile }`
  - `enum PlayerActionId { exit, title, refresh, danmakuToggle, danmakuSettings, volume, quality,
    line, screenshot, pick, scale, smallWindow, fullscreenToggle, lock, closeTile, share, copyUrl,
    openApp, debugInfo, autoExit }`
  - `class PlayerAction { id; 标题; tier(core 恒平铺 / whenFits 宽度够才平铺 / menuOnly 只进 ⋮);
    slotWidth(平铺占位预算); placeInTopBar(全屏顶栏还是底栏); rightSide(条带左簇还是右簇) }`
    ——**不持有图标**：弹幕开关用的是 asset `ImageIcon`，清晰度用的是文字按钮，形态本来就不一律；
    模型只决定「哪些、在哪」，图标与按下行为归 renderer。
  - `({List<PlayerAction> bar, List<PlayerAction> overflow}) resolvePlayerActions({
    required PlayerHost host, required double availableWidth, required bool isVertical,
    required bool canCloseTile, required bool hasQuality, required bool hasLine})`
    （移动端不进模型，所以没有 `isMobile`；`multiPlayActive` 也不需要——宿主枚举已经说明了它）
  - 收纳规则：`tier 3` 恒进 `overflow`；`tier 1/2` 按清单顺序累加 `slotWidth`，装不下的进
    `overflow`；`⋮` 自身预留 40；**常驻至少 3 件**（音量／弹幕开关／全屏切换），
    即使宽度不够也不进 `⋮`。

- **`lib/modules/live_room/player/player_action_views.dart`**
  - `PlayerAction` → 调用的映射表，全部走 controller 上**已存在**的方法（`refreshRoom`、
    `saveScreenshot`、`showQualitySheet`、`showPlayUrlsSheet`/`changePlayLine`、
    `showPlayerSettingsSheet`、`showDanmuSettingsSheet`、`showDebugInfo`、`showAutoExitSheet`、
    `share`/`copyUrl`/`openNaviteAPP`、`toggleMute`/`nudgeVolumeFactor`、`multiPlay.replaceTileRoom`）；
    只有 `pick`（合并原「关注列表」与格子 `▾`）与音量三态是新增的封装。
  - 弹层形态：清单类 → 容器按宿主（全屏／小窗／格子＝`Utils.showRightDialog`，窗口化＝`Utils.showBottomSheet`）；
    `pick`（格子的 `▾`）与音量 → 锚定浮层
  - `⋮` 的渲染：`overflow` 非空时在条带／胶囊右端给一颗 `⋮`，点开的是同一判据选出的容器
    （右侧面板或底部抽屉），按清单顺序把 `overflow` 各项列成 `图标 + 标题` 的 `ListTile`
    （与今天页级「更多」同形，只是清单换成 resolver 产的）；`overflow` 为空时不给这颗 `⋮`。
  - 目标格规则：动作恒作用于**该宿主自己的 controller**；窗口化／全屏＝页面主格（多开时＝聚焦格，
    沿用 `live_room_page.dart:139` 的 `room => controller.focused`），格子＝本格 `tile`；
    窗口级动作（`smallWindow`、`autoExit`、`lock`）恒走页面主格。

- **`lib/modules/live_room/player/player_action_bar.dart`**（renderer：把 resolver 的产物画成
  条带／胶囊，含 `⋮` 那颗；三个宿主共用）
- **`lib/modules/live_room/player/player_volume_action.dart`**（音量三态控件：点击静音／悬停滑条／
  滚轮微调；`VolumeTarget` 区分「总音量」与「该格系数」两种绑定）
- **`lib/modules/live_room/multi_play/multi_play_volume.dart`**（纯函数 `resolveTileVolume`，见 §5）

改动文件：

- `player_controls.dart`：`buildFullControls`/`buildControls` 的两条 `Row` 改为渲染 resolver 的产物；
  顶栏、渐变带、锁定、`DragToMoveArea`、安卓分支的清单原样保留。
- `multi_play_tile.dart`：`_buildControlsPill`(`:165`) 改为渲染 tile 切片；`_buildMoreButton`(`:303`)
  的三项并进 `overflow`；`_buildSwitchButton`(`:220`) 保留 `PopupMenuButton`（锚定浮层），
  但**必须维持常挂 + `IgnorePointer` + 淡出**（`PopupMenuButton` 在菜单打开期间被 unmount 会
  静默丢弃选中结果，`popup_menu.dart` 的 `.then` 里有 `if (!mounted) return null`）。
- `live_room_page.dart`：`showMore()`(`:1015`) 改为由同一份清单渲染；设置卡片(`:800-859`) 加压低开关。
- `player_controller.dart`：小窗几何链（§7）、`scaleModeOverride`（§6）、全屏态补小窗入口。
- `live_room_controller.dart`：`resolveTargetVolume()`(`:141`) 改调纯函数（§5）。
- `app_settings_controller.dart` + `local_storage_service.dart`：`multiPlayDuckEnabled`。

## 5. 音频模型

抽出纯函数（新文件 `multi_play/multi_play_volume.dart`，便于真值表单测）：

```dart
double resolveTileVolume({
  required double master,      // AppSettingsController.playerVolume
  required bool duckEnabled,   // 新：multiPlayDuckEnabled，默认 false
  required double duckRatio,   // 现有：multiPlayDuckVolume（0~1）
  required double factor,      // 现有：该格 volumeFactor（0~1）
  required bool focused,
})
```

真值表（写进测试）：

| duckEnabled | focused | 结果 |
|---|---|---|
| false | 任意 | `master * factor`（聚焦与否同值——这就是「独立控制」） |
| true | true | `master * factor` |
| true | false | `master * duckRatio * factor` |
| 任意 | 任意 | `factor <= 0.001` → `0`；结果恒 `<= master * factor`（duck 只向下乘，永不超 `volume-max`） |

- 触发点不动：`MultiPlaySession.applyVolumes()`(`multi_play_session.dart:254`) 仍是唯一权威，
  `focusSlot`／`addRoom`／`_dropTile`／`toggleTileMute`／`nudgeTileVolume`／总音量滑条各自照调。
  duck 关掉后焦点只剩三件事：描边、侧栏跟随、折叠时先保谁。
- 设置卡片：在「非聚焦音量」(`live_room_page.dart:817`) 上面加 `SettingsSwitch`「非聚焦自动压低」。
  **修订（实现期定）：开关关掉时不渲染比例那行**——`SettingsNumber` 没有 disabled 态，灰它要新加一层支持；
  而「一行现在不起作用」这种状态本来就该用不显示来表达（项目自己的口径：空集合不显示）。
  文案里「不是静音」这类讲解句去掉，只留功能名。
- 每格音量控件的三态：点击 `toggleMute()`（`live_room_controller.dart:116`，系数 0↔上次值，
  **不落盘**，退出直播间即失效）、悬停出滑条、滚轮 `nudgeVolumeFactor(±0.05)`（`:127`）。
  滑条在单播放宿主绑 `playerVolume`/`playerMaxVolume`，在格子宿主绑 `volumeFactor`。
  **修订（实现期定）：静音在两种宿主下都问同一件事——「这一路被我静音了吗」，一律读/写 `volumeFactor`**；
  滑条才各自绑总音量与该格系数。所以把总音量拖到 0 时图标仍是 `volume_up`，这是对的。
- 悬停滑条与 chrome 自动隐藏的打架，**按宿主分两种解法（实现期推翻了我原来「都不能用 overlay」的判断）**：
  条带（窗口化／全屏／小窗）里滑条**行内展开在同一个 `MouseRegion` 内**，向左长、右侧那一簇不动，零位移；
  格子里必须走 `Overlay`（`OverlayPortal.overlayChildLayoutBuilder`，即 `RawTooltip` 那套）——
  `Positioned` 画出盒子之外的东西不参与命中测试（`RenderBox.hitTest` 先按自身尺寸筛，`clipBehavior: none` 只管绘制），
  指针一移到滑条上就 `onExit`、滑条既会消失也拖不动。格子那条用 150ms 宽限期 + 滑条自带 `MouseRegion` 续命。

## 6. 按格独立画面尺寸

- `LiveRoomController.scaleModeOverride`：`int?`，`null` ＝跟随全局；**会话级，不落盘**
  （格子是临时身份，换台会换房间；新格继承全局）。
- `player_fit.dart:10` 的 `resolvePlayerFit()` 改为接收可选 `scaleMode`，
  新增 `int get effectiveScaleMode => scaleModeOverride ?? settings.scaleMode.value`；
  `updateScaleMode()`（`player_controller.dart:442`）按本格有效值下发。
- 可行性已核实：`globalPlayerKey` 是每个 controller 一份（`player_controller.dart:96`），
  格子早就在用 `tile.globalPlayerKey`（`multi_play_tile.dart:346`），所以按格下发只影响那一格。
- 不碰布局引擎：格子外框仍由「各路中最宽比例」定（`MultiPlaySession.tileAspect()`），
  覆盖值只改格内的信箱方式。
- 「自定义 宽:高」沿用全局的 `aspectWidth/aspectHeight/aspectByUser`；按格只覆盖模式，不覆盖自定义数值。

## 7. 全屏 ↔ 小窗几何链

现状缺陷：`_lastWindowSize/_lastWindowPosition` **只在 `enterSmallWindow` 里赋值**
（`player_controller.dart:736-737`），`enterFullScreen`(`:614`) 只记 `windowMaxState`。
于是「窗口化 → 全屏 → 小窗 → 退出小窗」会把**满屏几何**当成还原目标，窗口停在满屏大小。
（`exitFull`(`:648`) 已有把小窗整单转交 `exitSmallWindow` 的处理，这条不动。）

改法：

1. `enterFullScreen`：仅在「当前既非全屏也非小窗」时捕获几何与 `windowMaxState`。
2. `enterSmallWindow`：仅在当前是窗口态时捕获；若 `fullScreenState && !smallWindowState`，
   先 `setFullScreen(false)`（需要时 `unmaximize()`），再走既有的 PiP 流程
   （标题栏隐藏 → 先约束后设尺寸 → 记忆位置 → 置顶），次序铁律不变。
3. 谁先离开窗口态谁捕获、只捕获一次，退出时消费并清空。

验收矩阵（手测，四条路径都要落回窗口态且尺寸是进全屏前那个）：
窗口→小窗→退出；窗口→全屏→退出；窗口→全屏→小窗→退出；窗口→小窗→全屏→退出。

## 8. 动作清单（resolver 的期望输出）

`✓`＝平铺在条/胶囊里，`⋮`＝收进 `⋮`，`✗`＝该宿主不提供。

**2026-10-03 手测后修订（位置与形态）**：桌面两种形态都有**右上角那一簇**＝`截图 / 换台 / 小窗播放 / ⋮更多`
（作者原话：「现在基本上所有的 OSD 全部堆砌在下方，顶部完全什么都没有……原本的就挺好的」）；
底栏只留 `刷新 / 弹幕 / 弹幕设置 / 音量 / 切换清晰度 / 切换线路 / 全屏`。
`⋮` 全应用只有**一个**落点：有顶栏的宿主在右上簇，小窗与格子留在各自底栏／胶囊。
下表 `✓ 顶栏` 即右上那一簇，`pick`／`smallWindow` 都归它。

**2026-10-04 手测后再修订（容器与换台的存在性）**：「现在全部采用右侧面板就不太好，在非全屏下不如原版」
→ ① **右侧面板仅在全屏使用**，窗口化（含页级「更多」）的清单类弹层回到改造前的**底部抽屉**
（判据 `usesRightPanelSurface(host)`，小窗与格子的 `⋮` 仍右侧面板）；
② **换台只在全屏与格子在场**——「换台这个回归和原版一致，仅在全屏时出现，那就是右侧面板」，
所以窗口化的右上簇是 `截图 / 小窗播放 / ⋮`，锚定小列表只留给格子，长按画面仍开右侧面板（只在全屏有长按）。

**建模口径修订（写计划时定）**：`exit`、`title`、`lock` **不建模为动作**——它们是全屏容器的结构
部分（顶栏的返回与标题、两侧的锁定按钮），renderer 直接画，resolver 不产出；表里那三行只作
为「全屏容器有什么」的说明保留。`pick` 与 `volume` 是**锚定控件**（`pick` ＝ `PopupMenuButton`
的行内形态，`volume` ＝ 悬停浮层/行内展开），不是点开抽屉的图标按钮。
（`pick` 这句只对**格子**成立：全屏那颗点开的是右侧面板，见上面 2026-10-04 那条。）

| id | windowed | fullscreen | smallWindow | tile |
|---|---|---|---|---|
| exit | ✗ | ✓ 顶栏 | ✗（顶栏不出，退出由 `smallWindow` 那颗承担） | ✗ |
| title | ✗ | ✓ 顶栏文本 | ✗ | ✗（信息胶囊里的 `① 名字`） |
| refresh | ✓ | ✓ | ⋮ | ⋮ |
| danmakuToggle | ✓ | ✓ | ✓ | ✓ |
| danmakuSettings | ✓ | ✓ | ⋮ | ⋮ |
| volume | ✓ | ✓ | ✓ | ✓ |
| quality | ✓（竖屏 ⋮） | ✓ | ⋮ | ⋮ |
| line | ✓（竖屏 ⋮） | ✓ | ⋮ | ⋮ |
| screenshot | ✓ | ✓ 顶栏 | ⋮ | ⋮ |
| pick（选台/换台） | ✗（2026-10-04：仅全屏） | ✓ 顶栏 | ✗ | ✓ `▾` |
| scale（画面尺寸） | ⋮ | ⋮ | ⋮（全局） | ⋮（本格） |
| smallWindow | ✓ | ✓ **新增** | ✓ 显示为「退出小窗」 | ✗ |
| fullscreenToggle | ✓ | ✓ | ✓ | ✓ |
| lock | ✗ | ✓ 两侧 | ✓ 两侧 | ✗ |
| closeTile | — | — | — | ✓（`index > 0`） |
| share / copyUrl / openApp / debugInfo / autoExit | ⋮ | ⋮ | ⋮ | ⋮ |

小窗态按他选定的口径收敛成**四件平铺 + 一个 `⋮`**：退出小窗／全屏播放／弹幕开关／音量，
其余全在 `⋮` 里；并且**顶栏在小窗态不再出现**（现在 `fullScreenState` 为 true 时顶栏是照给的）。
已知取舍：`⋮` 打开的是右侧面板，在几百 px 的小窗里会盖住画面——作者 2026-10-04 明确选了
「小窗与格子都保持右侧面板」（改造前小窗复用的就是全屏那一套，本来就是右侧面板）。

页级「更多」与视频区 `⋮` **同源但不同范围**（实现期定，2026-10-03）：`⋮` 只列「条带这一刻放不下的那些」，
页级「更多」列**全集**（`layout.all`，锚定件由 `actionableMenuItems` 剔掉）。
两处内容都来自同一份 resolver，不存在第二份清单；差别只在「就近的溢出桶」与「完整菜单」这一层级。
容器同判据：页级这颗挂在窗口化的 AppBar 上，所以它与窗口化条带一样落**底部抽屉**（2026-10-04）。

## 9. 错误处理与边界

- 竖屏主播（`isVertical`）：`quality`/`line` 从平铺降级为 `⋮`，**不再 `Offstage` 掉**（现在
  `player_controls.dart:595`/`:615` 是直接藏）。
- 无清晰度／无线路数据：动作不提供（沿用现有的空列表判断）。
- 多开满 4 路再加：维持现有 toast 文案「已满 4 路，可用格子上的 ▾ 换掉一路」。
- 多开中点「小窗播放」：仍由 `enterSmallWindow` 的门给出 toast（`player_controller.dart:725`）；
  格子的条带里不提供这个动作，所以正常路径点不到。
- 桌面截图在全屏／小窗下会先 `exitFull()`（`player_controller.dart:856`）再开原生保存对话框，
  这条既有行为不动；格子截图＝该格 controller 的 `player.screenshot()`。
- `showRightDialog` 的点外部关闭沿用现状（`maskColor` 透明、面板自带返回按钮），本次不改。
- 文案：同一功能各处必须同一个名字（开关胶囊／设置卡片／tooltip／toast 全部「多开播放」）；
  一眼能看懂的交互不写讲解句。
- 字体：条带里新增的文字按钮必须带 `live_room_page.dart` 的 `_toolbarTextStyle`（携带
  `AppFontName`）——`ButtonStyle.textStyle` 与主题样式是覆盖关系不是合并关系，漏了会掉字族。

## 10. 测试

- 新增 `test/player_action_set_test.dart`（纯 resolver）：
  - 桌面 `windowed` 与 `fullscreen` 的动作集合（bar ∪ overflow，去掉窗口专属的 `exit/title/lock`）
    **必须相等**——这条断言就是本次重构的验收定义；
  - `screenshot/pick/scale/smallWindow` 在 windowed 与 fullscreen 中同时在场；
  - `tile` 永不含 `smallWindow/lock/exit`；`closeTile` 只在 `canCloseTile` 时出现；
  - `smallWindow` 宿主的 `bar` 恰好 {`smallWindow`(文案「退出小窗」), `fullscreenToggle`,
    `danmakuToggle`, `volume`} 再加一个 `⋮`，且 `overflow` 含其余全部清单类动作；
  - 宽度收窄时按 tier 沉进 `⋮`，且常驻三件不被收走；
  - 移动端不进模型（§3 的平台门），因此没有「移动端清单」可断言；护栏是
    `playerControls` 与 `showMore()` 在安卓分支的短路必须存在，改动只发生在桌面分支。
- 新增 `test/multi_play_volume_test.dart`：§5 的真值表。
- 现有 37 个用例保持绿；`flutter analyze` 无告警；不要跑 `dart format`（仓库手工 80 列折行）。
- 构建：`flutter build windows --release`，**须先关掉正在运行的 app**（`slive.exe` 会锁住
  `WebView2Loader.dll` 导致 MSB3027）；只改 Dart 时看 `build/windows/.../data/app.so` 的时间戳。
- UI 行为由他手测，不建自动化验收。

## 11. 明确不做

- 容器视觉统一（全屏的横跨式渐变带不换）；移动端重做；4 路上限调整；拖拽换位／拖拽换台；
  讲解性提示条；`kMultiPlayLowQualityUnfocused` 那套性能降级。
- 多路性能 spike 仍未跑（`lib/spike/multi_player_spike.dart`，需 4 条直播直链），本设计不依赖它。

## 12. 交付顺序

1. 纯模型 + 单测（`player_actions.dart`、`multi_play_volume.dart`、两个测试文件）——不接 UI，零风险。
2. 音频：`multiPlayDuckEnabled` 落设置、`resolveTargetVolume` 改调纯函数、设置卡片加开关。
3. 音量控件三态统一（点击静音／悬停滑条／滚轮），单播放与格子共用一套组件。
4. 按格画面尺寸（`scaleModeOverride` + `resolvePlayerFit`）。
5. OSD 接线：windowed/fullscreen 条带渲染 resolver、补齐截图/选台/画面尺寸、全屏补小窗入口、
   小窗态四件、PiP 几何链修正、页级「更多」合流。
6. `analyze` + 全量测试 + release 构建 + 他手测（PiP 四条路径、四路音量互不干扰、每格画面尺寸）。

## 13. 风险

| 风险 | 影响 | 处置 |
|---|---|---|
| PiP 几何链改动碰到窗口管理时序（先约束后设尺寸） | 退小窗后窗口尺寸/位置不对 | 手测矩阵 4 条路径；不改 `applyPipAspect`/`releasePipAspect` 的次序 |
| 悬停滑条与 chrome 自动隐藏打架 | 滑条刚出现就跟着淡出、拖不动 | 同一 `MouseRegion` 包住按钮+滑条；展开期间 `onInteract()` 续期 |
| 格子条带塞太多 | 240px 窄格溢出 | tier + `LayoutBuilder` 实测宽度收纳，常驻 3 件兜底 |
| 移动端回归 | 安卓的 PIP/竖屏/锁定被动到 | `isMobile` 平台门保持原集合，并用 resolver 测试当护栏 |
| `PopupMenuButton` 常挂约束被破坏 | `▾` 选中结果静默丢失 | 保留常挂 + `IgnorePointer` + 淡出；改动前后各跑一次手测 |
