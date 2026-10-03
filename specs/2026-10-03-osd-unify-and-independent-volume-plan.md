# 播放 OSD 统一 + 每路独立音量 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让直播播放覆盖层在窗口化／全屏／小窗／多开格四种形态下提供同一套动作，并把多开的音频从「聚焦自动压低」改成「每路独立控制、压低变成可选」。

**Architecture:** 一个纯函数 resolver（`player_actions.dart`）按宿主与可用宽度产出「平铺 + ⋮」两份动作清单，三个宿主共用一个 renderer（`player_action_bar.dart`）与一套弹层（`player_action_views.dart`）；音量与选台是锚定控件，其余清单类走右侧抽屉。容器视觉形态不变。

**Tech Stack:** Flutter 3.47.5（fvm）、Dart、GetX、media_kit fork（libmpv）、flutter_smart_dialog、window_manager。

**Spec:** `specs/2026-10-03-osd-unify-and-independent-volume-design.md`（执行时两份一起读，计划里的每条决定都指回那份）

## Global Constraints

每个任务的验收都隐含这一节的内容。

- Flutter 命令一律用仓库内的 SDK，从 `simple_live_app/` 目录跑：`../.fvm/flutter_sdk/bin/flutter.bat`
- **禁止跑 `dart format` / `flutter format`**。仓库按 80 列手工折行，`analysis_options.yaml` 的 `formatter.page_width: 120` 是另一回事，格式化会产生几百行无关 diff。
- 注释写「为什么」，不写「做了什么」；已有中文注释是决策记录，不要顺手删。
- 用户可见文案：同一功能各处同一个名字，多开的功能统一叫**「多开播放」**；不加讲解性提示句；空集合不显示，`0/0` 是噪音。
- 移动端（Android/iOS）**不进这套模型**：`playerControls` 与页级「更多」保留平台门短路，安卓分支一行不改其行为。
- 覆盖层的显隐容器必须**常挂 + `IgnorePointer` + 淡出**，不能条件移除：`PopupMenuButton` 在菜单打开期间被 unmount 会静默丢弃选中结果（`popup_menu.dart` 的 `showButtonMenu().then` 里有 `if (!mounted) return null`）。
- `Text`/`RenderParagraph` 参与命中测试：纯展示的昵称要包 `IgnorePointer`，否则点不到正下方的手势层。
- 条带/胶囊里的**文字按钮**必须带 `live_room_page.dart` 的 `_toolbarTextStyle`（携带 `AppFontName`）——`ButtonStyle.textStyle` 与主题样式是覆盖关系、不是合并关系，漏了会掉字族。
- 音量只走 mpv 的 `volume` 属性，不碰 `af` 链（`af` 是响度均衡 loudnorm 的地盘）。
- 只改 Dart 时构建产物看 `build/windows/x64/runner/Release/data/app.so` 的时间戳，不看 `slive.exe`；构建前**必须关掉正在运行的 app**（`slive.exe` 锁 `WebView2Loader.dll` → MSB3027）。
- 不建 UI 自动化验收，界面行为由作者手测；纯逻辑层必须有单测。
- 分多次提交，一个任务一次提交；提交信息＝标题 + 3~5 条要点，每条一行。

## 文件结构

| 文件 | 责任 | 动作 |
|---|---|---|
| `lib/modules/live_room/multi_play/multi_play_volume.dart` | 纯函数：这一路此刻该给多大音量 | 新建 |
| `lib/modules/live_room/player/player_actions.dart` | 纯函数：这个宿主该有哪些动作、哪些平铺哪些进 ⋮ | 新建 |
| `lib/modules/live_room/player/player_action_views.dart` | 动作 id → 真实调用 + 弹层形态（抽屉／⋮／选台浮层） | 新建 |
| `lib/modules/live_room/player/player_action_bar.dart` | renderer：把 resolver 的产物画成条带/胶囊 | 新建 |
| `lib/modules/live_room/player/player_volume_action.dart` | 音量三态控件（点击静音／悬停滑条／滚轮） | 新建 |
| `lib/modules/live_room/player/player_fit.dart` | `scaleMode → fit/aspectRatio`，接收按格覆盖值 | 修改 |
| `lib/modules/live_room/player/player_controller.dart` | 音量下发、小窗几何链、按格画面尺寸 | 修改 |
| `lib/modules/live_room/live_room_controller.dart` | `resolveTargetVolume` 改调纯函数、`scaleModeOverride` | 修改 |
| `lib/modules/live_room/player/player_controls.dart` | 桌面分支换成 resolver 驱动的条带；移动分支不动 | 修改 |
| `lib/modules/live_room/multi_play/multi_play_tile.dart` | 两个胶囊接 resolver；选台/音量换共用控件 | 修改 |
| `lib/modules/live_room/live_room_page.dart` | 设置卡片加压低开关；页级「更多」合流 | 修改 |
| `lib/app/controller/app_settings_controller.dart`、`lib/services/local_storage_service.dart` | `multiPlayDuckEnabled` | 修改 |
| `test/multi_play_volume_test.dart`、`test/player_action_set_test.dart` | 上面两个纯函数 | 新建 |

---

## Task 1: 音量决策抽成纯函数

**Files:**
- Create: `simple_live_app/lib/modules/live_room/multi_play/multi_play_volume.dart`
- Test: `simple_live_app/test/multi_play_volume_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `double resolveTileVolume({required double master, required bool duckEnabled, required double duckRatio, required double factor, required bool focused})` — Task 3 的 `LiveRoomController.resolveTargetVolume()` 调它

- [ ] **Step 1: 写失败的测试**

`simple_live_app/test/multi_play_volume_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_volume.dart';

void main() {
  group('resolveTileVolume', () {
    test('压低关闭时，聚焦与否同一音量', () {
      final unfocused = resolveTileVolume(
        master: 80, duckEnabled: false, duckRatio: 0.3, factor: 1, focused: false,
      );
      final focused = resolveTileVolume(
        master: 80, duckEnabled: false, duckRatio: 0.3, factor: 1, focused: true,
      );
      expect(unfocused, 80);
      expect(focused, 80);
    });

    test('压低开启时，非聚焦按 ratio 乘上去', () {
      expect(
        resolveTileVolume(
          master: 80, duckEnabled: true, duckRatio: 0.3, factor: 1, focused: false,
        ),
        closeTo(24, 1e-9),
      );
      expect(
        resolveTileVolume(
          master: 80, duckEnabled: true, duckRatio: 0.3, factor: 1, focused: true,
        ),
        80,
      );
    });

    test('该格系数与压低叠乘', () {
      expect(
        resolveTileVolume(
          master: 100, duckEnabled: true, duckRatio: 0.5, factor: 0.4, focused: false,
        ),
        closeTo(20, 1e-9),
      );
    });

    test('系数为 0 即静音，与压低和焦点无关', () {
      for (final duck in [true, false]) {
        for (final focused in [true, false]) {
          expect(
            resolveTileVolume(
              master: 100, duckEnabled: duck, duckRatio: 0.3, factor: 0, focused: focused,
            ),
            0,
          );
        }
      }
    });

    test('结果恒不超过总音量（压低只向下乘，永不越 volume-max）', () {
      for (final duckRatio in [0.0, 0.3, 1.0]) {
        for (final factor in [0.0, 0.25, 1.0]) {
          final v = resolveTileVolume(
            master: 90, duckEnabled: true, duckRatio: duckRatio, factor: factor, focused: false,
          );
          expect(v, lessThanOrEqualTo(90));
        }
      }
    });

    test('ratio 取 1 时等于不压低', () {
      expect(
        resolveTileVolume(
          master: 70, duckEnabled: true, duckRatio: 1, factor: 1, focused: false,
        ),
        70,
      );
    });
  });
}
```

- [ ] **Step 2: 跑到失败**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test test/multi_play_volume_test.dart
```
Expected：编译失败，`multi_play_volume.dart` 不存在（`Target of URI doesn't exist`）。

- [ ] **Step 3: 写实现**

`simple_live_app/lib/modules/live_room/multi_play/multi_play_volume.dart`：

```dart
/// 这一路此刻该给多大 mpv 音量（百分比）。
///
/// 单独抽成纯函数是因为这条规则被四种入口改：焦点变、总音量滑条、该格滚轮、
/// 设置里的压低开关。原来它内联在 `LiveRoomController.resolveTargetVolume` 里，
/// 每次都要连着 `AppSettingsController` 与 `MultiPlaySession` 才能推，真值没法测。
///
/// 「压低」现在是可选行为（设置默认关）：关掉后每路只由自己的系数决定，
/// 焦点不再影响音量——这是「每路独立控制」那半边需求。
library;

double resolveTileVolume({
  required double master,
  required bool duckEnabled,
  required double duckRatio,
  required double factor,
  required bool focused,
}) {
  if (factor <= 0.001) {
    return 0;
  }
  final duck = duckEnabled && !focused ? duckRatio : 1.0;
  return master * duck * factor;
}
```

注意：`library;` 必须在 import 之前（本文件没有 import，但要放在文档注释之后、任何声明之前，与 `multi_play_layout.dart` 一致）。

- [ ] **Step 4: 跑到通过**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test test/multi_play_volume_test.dart
```
Expected：`All tests passed!`（6 个）。

- [ ] **Step 5: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/multi_play/multi_play_volume.dart simple_live_app/test/multi_play_volume_test.dart
git commit -m "feat(multiplay): 音量决策抽成纯函数，压低改为可叠乘因子

- resolveTileVolume 收 master/duckEnabled/duckRatio/factor/focused
- 焦点不再直接决定音量，压低只在开启时乘进去
- 真值表进单测（含「恒不超过总音量」与静音四态）"
```

---

## Task 2: 动作清单 resolver

**Files:**
- Create: `simple_live_app/lib/modules/live_room/player/player_actions.dart`
- Test: `simple_live_app/test/player_action_set_test.dart`

**Interfaces:**
- Consumes: 无（纯 Dart + `IconData` 不用到，模型不持有图标）
- Produces:
  - `enum PlayerHost { windowed, fullscreen, smallWindow, tile }`
  - `enum PlayerActionId { refresh, danmakuToggle, danmakuSettings, volume, quality, line, screenshot, pick, scale, smallWindow, fullscreenToggle, closeTile, share, copyUrl, openApp, debugInfo, autoExit }`
  - `enum PlayerActionTier { core, whenFits, menuOnly }`
  - `class PlayerAction { PlayerActionId id; String title; double slotWidth; bool placeInTopBar; bool rightSide; }`
    ——**评审后修正（见 ledger `Task 2: Ruling(Important-1)`）**：`tier` 不再是 `PlayerAction` 的字段。
    声明表里的 tier 会被 `_tierFor` 覆写、无人读，两个真相源；tier 只作为 resolver 的内部判断。
    同一轮修正还把 `closeTile` 移到 `fullscreenToggle` 之后并置 `rightSide: true`（声明顺序＝输出顺序，
    原顺序会把「关闭这一路」插到音量左边），并清掉 `pick`/`scale` 上多余的 `placeInTopBar`。
  - `class PlayerActionLayout { List<PlayerAction> bar; List<PlayerAction> overflow; bool hasOverflow; }`
  - `PlayerActionLayout resolvePlayerActions({required PlayerHost host, required double availableWidth, bool isVertical = false, bool canCloseTile = false, bool hasQuality = true, bool hasLine = true})`
  - `const double kOverflowButtonWidth = 40;`

  Task 5/6/8/9/10 都靠这些名字。

- [ ] **Step 1: 写失败的测试**

`simple_live_app/test/player_action_set_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';

Set<PlayerActionId> _all(PlayerActionLayout l) => {
      ...l.bar.map((e) => e.id),
      ...l.overflow.map((e) => e.id),
    };

void main() {
  group('跨宿主一致性', () {
    test('桌面窗口化与全屏的动作全集相同（顶栏/底栏归 renderer 管）', () {
      final w = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 1200);
      final f = resolvePlayerActions(host: PlayerHost.fullscreen, availableWidth: 1200);
      expect(_all(w), _all(f));
    });

    test('截图／选台／画面尺寸／小窗在窗口化与全屏都必须在场', () {
      for (final host in [PlayerHost.windowed, PlayerHost.fullscreen]) {
        final ids = _all(resolvePlayerActions(host: host, availableWidth: 1200));
        expect(ids, containsAll(<PlayerActionId>{
          PlayerActionId.screenshot,
          PlayerActionId.pick,
          PlayerActionId.scale,
          PlayerActionId.smallWindow,
        }), reason: '$host 少动作');
      }
    });

    test('窄窗口不会把动作吃掉，只会沉进 ⋮', () {
      final wide = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 1200);
      final narrow = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 320);
      expect(_all(narrow), _all(wide));
      expect(narrow.bar.length, lessThan(wide.bar.length));
    });
  });

  group('格子', () {
    test('格子永不给窗口级动作', () {
      final ids = _all(resolvePlayerActions(host: PlayerHost.tile, availableWidth: 240));
      expect(ids.contains(PlayerActionId.smallWindow), isFalse);
      expect(ids.contains(PlayerActionId.fullscreenToggle), isTrue);
      // 返回键／标题／锁定是容器结构，不建模为动作（spec §8 的建模口径修订）
      expect(PlayerActionId.values.map((e) => e.name), isNot(contains('exit')));
      expect(PlayerActionId.values.map((e) => e.name), isNot(contains('lock')));
    });

    test('关闭这一路只在可关时出现', () {
      expect(
        _all(resolvePlayerActions(host: PlayerHost.tile, availableWidth: 400, canCloseTile: true))
            .contains(PlayerActionId.closeTile),
        isTrue,
      );
      expect(
        _all(resolvePlayerActions(host: PlayerHost.tile, availableWidth: 400))
            .contains(PlayerActionId.closeTile),
        isFalse,
      );
    });

    test('格子平铺 core 五件（含 ▾ 选台），低频动作全在 ⋮ 里', () {
      final l = resolvePlayerActions(host: PlayerHost.tile, availableWidth: 240, canCloseTile: true);
      expect(l.bar.map((e) => e.id).toSet(), {
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
        PlayerActionId.pick,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.closeTile,
      });
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.refresh));
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.quality));
    });
  });

  group('小窗（PiP）', () {
    test('小窗态平铺恰好四件，其余进 ⋮', () {
      final l = resolvePlayerActions(host: PlayerHost.smallWindow, availableWidth: 360);
      expect(l.bar.map((e) => e.id).toSet(), {
        PlayerActionId.smallWindow,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
      });
      expect(l.hasOverflow, isTrue);
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.screenshot));
    });
  });

  group('常驻兜底与收纳', () {
    test('core 动作任何宽度下都留在条带里', () {
      const core = {
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.refresh,
      };
      for (final width in [0.0, 120.0, 400.0, 1200.0, 4000.0]) {
        final ids = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: width).bar
            .map((e) => e.id)
            .toSet();
        expect(ids, containsAll(core), reason: '宽 $width 时常驻件被收进了 ⋮');
      }
    });

    test('竖屏主播时清晰度/线路降到 ⋮ 而不是消失', () {
      final l = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 1200, isVertical: true);
      for (final id in [PlayerActionId.quality, PlayerActionId.line]) {
        expect(l.bar.map((e) => e.id), isNot(contains(id)));
        expect(l.overflow.map((e) => e.id), contains(id));
      }
    });

    test('没有清晰度/线路数据时该动作不提供', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed, availableWidth: 1200, hasQuality: false, hasLine: false,
      );
      expect(l.overflow.map((e) => e.id), isNot(contains(PlayerActionId.quality)));
      expect(l.bar.map((e) => e.id), isNot(contains(PlayerActionId.line)));
    });

    test('装得下时不给 ⋮', () {
      final l = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 4000);
      expect(l.hasOverflow, isFalse);
    });

    test('条带顺序与 _kAllActions 声明顺序一致（左簇在前、右簇在后）', () {
      final bar = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 1200).bar;
      final right = bar.where((e) => e.rightSide).map((e) => e.id).toList();
      expect(bar.last.id, right.last);
      expect(bar.first.rightSide, isFalse);
    });
  });

  test('动作标题与 id 一一对应，没有重复 id', () {
    final l = resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 4000);
    final ids = [...l.bar, ...l.overflow].map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final a in [...l.bar, ...l.overflow]) {
      expect(a.title, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: 跑到失败**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test test/player_action_set_test.dart
```
Expected：编译失败，`player_actions.dart` 不存在。

- [ ] **Step 3: 写实现**

`simple_live_app/lib/modules/live_room/player/player_actions.dart`：

```dart
/// 播放覆盖层的动作清单：这个宿主此刻该有哪些动作、哪些平铺、哪些收进 `⋮`。
///
/// 之所以抽成纯函数：窗口化／全屏／小窗／多开格原先是三套各自硬编码的 `Row`
/// （`player_controls.dart` 的 `buildFullControls` / `buildControls` 与
/// `multi_play_tile.dart` 的两个胶囊），同一个动作在四处有有无、语义还打架。
/// 清单同源之后，「一致」变成可以断言的性质（见 `test/player_action_set_test.dart`）。
///
/// 模型只决定「哪些、在哪」：图标与按下行为归 renderer——弹幕开关用的是 asset
/// `ImageIcon`、清晰度用的是文字按钮，形态本来就不一律，硬塞进数据类只会更难懂。
/// 移动端不进这套模型（`playerControls` 与页级「更多」按平台门短路走现有代码）。
library;

enum PlayerHost { windowed, fullscreen, smallWindow, tile }

enum PlayerActionId {
  refresh,
  danmakuToggle,
  danmakuSettings,
  volume,
  quality,
  line,
  screenshot,
  pick,
  scale,
  smallWindow,
  fullscreenToggle,
  closeTile,
  share,
  copyUrl,
  openApp,
  debugInfo,
  autoExit,
}

enum PlayerActionTier {
  /// 宽度再窄也留在条带里（音量／弹幕／全屏／刷新这几个是「这条带还在」的底线）
  core,

  /// 宽度够才平铺，否则沉进 `⋮`
  whenFits,

  /// 恒在 `⋮` 里
  menuOnly,
}

class PlayerAction {
  const PlayerAction({
    required this.id,
    required this.title,
    required this.tier,
    this.slotWidth = 40,
    this.placeInTopBar = false,
    this.rightSide = false,
  });

  final PlayerActionId id;
  final String title;
  final PlayerActionTier tier;

  /// 平铺时占的宽度预算：图标按钮 40，文字按钮（清晰度／线路）56。
  final double slotWidth;

  /// 全屏宿主里放顶栏还是底栏（窗口化没有顶栏，这个字段被忽略）。
  final bool placeInTopBar;

  /// 条带内的左右簇：false 跟「刷新／弹幕」同侧，true 跟「音量／全屏」同侧。
  final bool rightSide;
}

class PlayerActionLayout {
  const PlayerActionLayout({required this.bar, required this.overflow});

  final List<PlayerAction> bar;
  final List<PlayerAction> overflow;

  bool get hasOverflow => overflow.isNotEmpty;
}

const double kOverflowButtonWidth = 40;

/// 声明顺序＝条带里的显示顺序（左簇 → 右簇，`⋮` 恒在最右）。
const List<PlayerAction> _kAllActions = [
  PlayerAction(id: PlayerActionId.refresh, title: "刷新", tier: PlayerActionTier.core),
  PlayerAction(id: PlayerActionId.danmakuToggle, title: "弹幕", tier: PlayerActionTier.core),
  PlayerAction(id: PlayerActionId.danmakuSettings, title: "弹幕设置", tier: PlayerActionTier.whenFits),
  PlayerAction(id: PlayerActionId.screenshot, title: "截图", tier: PlayerActionTier.whenFits, placeInTopBar: true),
  PlayerAction(id: PlayerActionId.pick, title: "选台", tier: PlayerActionTier.whenFits, placeInTopBar: true),
  PlayerAction(id: PlayerActionId.closeTile, title: "关闭这一路", tier: PlayerActionTier.core),
  PlayerAction(id: PlayerActionId.volume, title: "音量", tier: PlayerActionTier.core, rightSide: true),
  PlayerAction(id: PlayerActionId.quality, title: "清晰度", tier: PlayerActionTier.whenFits, slotWidth: 56, rightSide: true),
  PlayerAction(id: PlayerActionId.line, title: "线路", tier: PlayerActionTier.whenFits, slotWidth: 56, rightSide: true),
  PlayerAction(id: PlayerActionId.scale, title: "画面尺寸", tier: PlayerActionTier.menuOnly, placeInTopBar: true),
  PlayerAction(id: PlayerActionId.smallWindow, title: "小窗播放", tier: PlayerActionTier.whenFits, rightSide: true),
  PlayerAction(id: PlayerActionId.fullscreenToggle, title: "全屏", tier: PlayerActionTier.core, rightSide: true),
  PlayerAction(id: PlayerActionId.debugInfo, title: "播放信息", tier: PlayerActionTier.menuOnly),
  PlayerAction(id: PlayerActionId.autoExit, title: "定时关闭", tier: PlayerActionTier.menuOnly),
  PlayerAction(id: PlayerActionId.share, title: "分享直播间", tier: PlayerActionTier.menuOnly),
  PlayerAction(id: PlayerActionId.copyUrl, title: "复制链接", tier: PlayerActionTier.menuOnly),
  PlayerAction(id: PlayerActionId.openApp, title: "APP 中打开", tier: PlayerActionTier.menuOnly),
];

/// 该动作在这个宿主是否存在（不是「是否平铺」，那由 tier 决定）。
bool _available(
  PlayerActionId id,
  PlayerHost host, {
  required bool canCloseTile,
  required bool hasQuality,
  required bool hasLine,
}) {
  switch (id) {
    case PlayerActionId.closeTile:
      return host == PlayerHost.tile && canCloseTile;
    case PlayerActionId.quality:
      return hasQuality;
    case PlayerActionId.line:
      return hasLine;
    case PlayerActionId.smallWindow:
      // 小窗是窗口级动作：格子碰不得（`enterSmallWindow` 在多开下直接 toast 拒绝）。
      // smallWindow 宿主时它表示「退出小窗」，仍然在场。
      return host != PlayerHost.tile;
    default:
      return true;
  }
}

PlayerActionTier _tierFor(PlayerActionId id, PlayerHost host, {required bool isVertical}) {
  switch (host) {
    case PlayerHost.tile:
      return switch (id) {
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume ||
        PlayerActionId.pick ||
        PlayerActionId.fullscreenToggle ||
        PlayerActionId.closeTile => PlayerActionTier.core,
        _ => PlayerActionTier.menuOnly,
      };
    case PlayerHost.smallWindow:
      // 小窗只有几百 px，右侧抽屉会盖住画面：平铺四件，其余一律进 ⋮（作者选定）。
      return switch (id) {
        PlayerActionId.smallWindow ||
        PlayerActionId.fullscreenToggle ||
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume => PlayerActionTier.core,
        _ => PlayerActionTier.menuOnly,
      };
    case PlayerHost.windowed:
    case PlayerHost.fullscreen:
      // 竖屏主播原先是直接 Offstage 掉清晰度/线路，现在降级进 ⋮（spec §9）。
      if (isVertical && (id == PlayerActionId.quality || id == PlayerActionId.line)) {
        return PlayerActionTier.menuOnly;
      }
      return switch (id) {
        PlayerActionId.refresh ||
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume ||
        PlayerActionId.fullscreenToggle => PlayerActionTier.core,
        PlayerActionId.danmakuSettings ||
        PlayerActionId.screenshot ||
        PlayerActionId.pick ||
        PlayerActionId.quality ||
        PlayerActionId.line ||
        PlayerActionId.smallWindow => PlayerActionTier.whenFits,
        _ => PlayerActionTier.menuOnly,
      };
  }
}

PlayerActionLayout resolvePlayerActions({
  required PlayerHost host,
  required double availableWidth,
  bool isVertical = false,
  bool canCloseTile = false,
  bool hasQuality = true,
  bool hasLine = true,
}) {
  final candidates = [
    for (final action in _kAllActions)
      if (_available(
        action.id,
        host,
        canCloseTile: canCloseTile,
        hasQuality: hasQuality,
        hasLine: hasLine,
      ))
        PlayerAction(
          id: action.id,
          title: action.title,
          tier: _tierFor(action.id, host, isVertical: isVertical),
          slotWidth: action.slotWidth,
          placeInTopBar: action.placeInTopBar,
          rightSide: action.rightSide,
        ),
  ];

  // 要不要给 `⋮` 留位：有 menuOnly 的候选，或者非 menuOnly 的候选本身已经超宽。
  final flexibleTotal = candidates
      .where((e) => e.tier != PlayerActionTier.menuOnly)
      .fold<double>(0, (sum, e) => sum + e.slotWidth);
  final needsMenu = candidates.any((e) => e.tier == PlayerActionTier.menuOnly) ||
      flexibleTotal > availableWidth;

  final bar = <PlayerAction>[];
  final overflow = <PlayerAction>[];
  var budget = availableWidth - (needsMenu ? kOverflowButtonWidth : 0);
  for (final action in candidates) {
    if (action.tier == PlayerActionTier.menuOnly) {
      overflow.add(action);
      continue;
    }
    // core 无条件在场：宽度不够也要留住，这是「常驻至少三件」的底线。
    if (action.tier == PlayerActionTier.core || budget >= action.slotWidth) {
      bar.add(action);
      budget -= action.slotWidth;
      continue;
    }
    overflow.add(action);
  }
  return PlayerActionLayout(bar: bar, overflow: overflow);
}
```

- [ ] **Step 4: 跑到通过**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test test/player_action_set_test.dart
```
Expected：`All tests passed!`。若「窄窗口不会把动作吃掉」失败，检查 `needsMenu` 的预留是否让 whenFits 被过早挤出——断言只要求全集不变、bar 变短，不要求具体件数。

- [ ] **Step 5: 全量测试 + 分析**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test && ../.fvm/flutter_sdk/bin/flutter.bat analyze
```
Expected：现有用例（含多开那几组）全绿；analyze 无 issue。

- [ ] **Step 6: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_actions.dart simple_live_app/test/player_action_set_test.dart
git commit -m "feat(player): 播放覆盖层动作清单抽成纯 resolver

- 四个宿主（窗口化/全屏/小窗/格子）共用一份声明顺序
- tier 决定平铺还是进 ⋮，core 件无视宽度兜住
- 跨宿主一致性写成断言（窗口化与全屏全集相等）
- 竖屏主播的清晰度/线路由隐藏改为降级进 ⋮"
```

---

## Task 3: 压低开关落设置、接进音量链

**Files:**
- Modify: `simple_live_app/lib/services/local_storage_service.dart:178`（键定义附近）
- Modify: `simple_live_app/lib/app/controller/app_settings_controller.dart:732`（字段附近）与 `:254`（load 附近）
- Modify: `simple_live_app/lib/modules/live_room/live_room_controller.dart:141`（`resolveTargetVolume`）
- Modify: `simple_live_app/lib/modules/live_room/live_room_page.dart:817-832`（设置卡片）

**Interfaces:**
- Consumes: Task 1 的 `resolveTileVolume(...)`
- Produces: `AppSettingsController.multiPlayDuckEnabled`（`RxBool`，默认 `false`）、`setMultiPlayDuckEnabled(bool)`、`LocalStorageService.kMultiPlayDuckEnable`

- [ ] **Step 1: 加存储键**

`local_storage_service.dart`，紧跟 `kMultiPlayDuckVolume`（`:178`）之后：

```dart
  /// 多开播放：是否自动压低非聚焦格（关掉时 [kMultiPlayDuckVolume] 不参与计算）
  static const String kMultiPlayDuckEnable = "MultiPlayDuckEnable";
```

- [ ] **Step 2: 加设置字段**

`app_settings_controller.dart`，紧跟 `setMultiPlayDuckVolume`（`:740`）之后：

```dart
  /// 多开播放：非聚焦格是否自动压低。
  ///
  /// 默认关：主模型是「每一路自己说了算」，压低只是给习惯「聚焦即安静」的人的可选行为。
  /// 关掉时 [multiPlayDuckVolume] 原样留着，重新打开不用再调一遍。
  var multiPlayDuckEnabled = false.obs;

  void setMultiPlayDuckEnabled(bool e) {
    multiPlayDuckEnabled.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayDuckEnable,
      e,
    );
  }
```

同文件 load 段落（`:254` 的 `multiPlayDuckVolume.value = ...` 之后）：

```dart
    multiPlayDuckEnabled.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayDuckEnable,
      false,
    );
```

- [ ] **Step 3: 不引入新事件**

不要为这个开关加 `EventBus` 事件：设置卡片就在 `live_room_page.dart` 里、当场拿得到
`controller.multiPlay`，与相邻的「非聚焦音量」行用同一个办法（改完直接 `applyVolumes()`，见 Step 5）。
多开会话里既有的订阅（总音量、最大音量变化）一律不动——多一条事件就等于多一个
「谁负责重算音量」的入口，而音量权威只能有一个。

- [ ] **Step 4: `resolveTargetVolume` 改调纯函数**

`live_room_controller.dart:141` 整个方法替换为：

```dart
  /// 本路此刻该给多大音量：见 `resolveTileVolume`。
  @override
  double resolveTargetVolume() {
    final settings = AppSettingsController.instance;
    return resolveTileVolume(
      master: settings.playerVolume.value,
      duckEnabled: settings.multiPlayDuckEnabled.value,
      duckRatio: settings.multiPlayDuckVolume.value,
      factor: volumeFactor.value,
      focused: !multiPlay.isActive || multiPlay.focused == this,
    );
  }
```

并在文件顶部 import 区加：

```dart
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_volume.dart';
```

原方法上面那行文档注释（`/// 副格的目标音量：多开时非聚焦格按设置压低，详见 [resolveTargetVolume]。`）改成上面这句，别留下与新行为矛盾的旧说明。

- [ ] **Step 5: 设置卡片加压低开关**

`live_room_page.dart`，把 `:817` 那个 `Obx(() => SettingsNumber(...))` 换成「开关 + 数字」两行（沿用文件里既有的 `SettingsSwitch` 写法，见同卡片 `:835`）：

```dart
                    Obx(
                      () => SettingsSwitch(
                        title: "非聚焦自动压低",
                        value: AppSettingsController.instance.multiPlayDuckEnabled.value,
                        onChanged: (e) {
                          AppSettingsController.instance.setMultiPlayDuckEnabled(e);
                          // 设置只落盘，正在跑的几路要重下一次音量
                          controller.multiPlay.applyVolumes();
                        },
                      ),
                    ),
                    AppStyle.divider,
                    Obx(
                      () => SettingsNumber(
                        title: "非聚焦音量",
                        value: (AppSettingsController.instance.multiPlayDuckVolume.value * 100).round(),
                        min: 0,
                        max: 100,
                        step: 5,
                        unit: "%",
                        onChanged: (e) {
                          AppSettingsController.instance.setMultiPlayDuckVolume(e / 100);
                          // 设置只落盘，正在跑的四路要重下一次音量
                          controller.multiPlay.applyVolumes();
                        },
                      ),
                    ),
```

`subtitle` 那句「聚焦的一路保持总音量，其余按这个比例压低（不是静音）」删掉——开关一眼能懂，不要讲解句。开关关掉时不要把比例行灰掉或隐藏：灰态需要额外的 disabled 支持，而这两行本来就只在多开启用时渲染。

- [ ] **Step 6: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze && ../.fvm/flutter_sdk/bin/flutter.bat test
```
Expected：analyze 无 issue；测试全绿（本任务没有新增断言，Task 1 的真值表已经覆盖计算）。

- [ ] **Step 7: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/services/local_storage_service.dart simple_live_app/lib/app/controller/app_settings_controller.dart simple_live_app/lib/modules/live_room/live_room_controller.dart simple_live_app/lib/modules/live_room/live_room_page.dart
git commit -m "feat(multiplay): 非聚焦压低改为默认关的可选行为

- 新增设置项 multiPlayDuckEnabled，比例值原样保留
- resolveTargetVolume 改调 resolveTileVolume，注释同步
- 开关在设置卡片当场 applyVolumes，与比例行同一办法
- 设置卡片删掉讲解句副标题"
```

---

## Task 4: 小窗几何链修正 + 全屏进小窗的控制器侧

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_controller.dart:614`（`enterFullScreen`）、`:648`（`exitFull`）、`:724`（`enterSmallWindow`）、`:774`（`exitSmallWindow`）

**Interfaces:**
- Consumes: `WindowService.instance`（`setMultiPlayMinimumSize` / `restoreNormalMinimumSize` / `applyPipAspect` / `releasePipAspect` / `pipAspectWanted` / `pipAspectLocked`）、`window_manager`
- Produces: 修正后的语义——「谁先离开窗口态谁捕获几何、退出时消费」；`enterSmallWindow` 在 `fullScreenState && !smallWindowState` 时可用（Task 8 的全屏底栏小窗入口靠它）

- [ ] **Step 1: 读现有四个方法，确认几何字段的使用面**

```bash
cd /c/dart_simple_live && grep -n "_lastWindowSize\|_lastWindowPosition\|windowMaxState" simple_live_app/lib/modules/live_room/player/player_controller.dart
```
Expected：赋值只出现在 `enterSmallWindow`（`:736-737`），读取在 `exitFull`（`:667-671`）与 `exitSmallWindow`（`:786-790`）。这一步是确认没有别处也在写这两个字段。

- [ ] **Step 2: 加捕获入口**

`player_controller.dart` 的 `Size? _lastWindowSize;` / `Offset? _lastWindowPosition;`（`:683-684`）附近加：

```dart
  /// 窗口态（非全屏、非小窗）的几何，用于退出全屏/小窗时还原。
  ///
  /// 「谁先离开窗口态谁捕获」：原先只有 `enterSmallWindow` 写这两个字段，
  /// 于是从全屏进小窗时记下来的是满屏几何，退出小窗后窗口停在满屏大小——
  /// 这就是全屏里那颗「小窗播放」按钮原来不敢放的原因。
  bool _normalGeometryCaptured = false;

  Future<void> _captureNormalGeometry() async {
    if (_normalGeometryCaptured) {
      return;
    }
    _lastWindowSize = await windowManager.getSize();
    _lastWindowPosition = await windowManager.getPosition();
    windowMaxState.value = await windowManager.isMaximized();
    _normalGeometryCaptured = true;
  }

  /// 退出到窗口态时消费还原点，下一次进全屏重新采。
  void _consumeNormalGeometry() {
    _normalGeometryCaptured = false;
  }
```

- [ ] **Step 3: 在两个入口调用**

`enterFullScreen`（`:614`）的桌面分支开头，`windowMaxState.value = await windowManager.isMaximized();` 那一行**替换**为：

```dart
      await _captureNormalGeometry();
```

（原来这行就是 `enterFullScreen` 里的 `windowMaxState` 赋值，语义并入 `_captureNormalGeometry`；小窗→全屏这条路径上已经捕获过，不重复采，符合「谁先离开窗口态谁捕获」。）

`enterSmallWindow`（`:724`）桌面分支开头，`_lastWindowSize = await windowManager.getSize();` 与 `_lastWindowPosition = await windowManager.getPosition();` 两行**替换**为：

```dart
      await _captureNormalGeometry();
```

并把 `enterSmallWindow` 里紧接其后的 `await windowManager.setTitleBarStyle(TitleBarStyle.hidden);` 之前插入退 OS 全屏的两步（次序：先退全屏/取消最大化，再隐标题栏，最后落 PiP 尺寸）：

```dart
      // 从 OS 全屏进小窗必须先退全屏：`setFullScreen(true)` 期间 setSize 会被
      // 全屏的窗口样式吃掉，收不成小窗；最大化态同理会顶住目标尺寸。
      if (fullScreenState.value) {
        await windowManager.setFullScreen(false);
        if (windowMaxState.value) {
          await windowManager.unmaximize();
        }
      }
```

同方法里 `fullScreenState.value = true;`（`:731`）必须留在这段之后——上面判断读的还是「进小窗前」的状态。把 `:731` 那一行挪到 `await _captureNormalGeometry();` 之后、上面这段之前，并把判断条件保持为读旧值：为可读性，直接在方法开头记下 `final wasFullScreen = fullScreenState.value;`，上面的分支用 `if (wasFullScreen)`，再写 `fullScreenState.value = true;`。最终顺序：

```dart
    if (!(Platform.isAndroid || Platform.isIOS)) {
      final wasFullScreen = fullScreenState.value;
      // 还原点在离开窗口态那一刻采（全屏或小窗），退出时消费。
      await _captureNormalGeometry();
      fullScreenState.value = true;
      smallWindowState.value = true;
      WindowService.instance.isPIP = smallWindowState.value;
      if (wasFullScreen) {
        await windowManager.setFullScreen(false);
        if (windowMaxState.value) {
          await windowManager.unmaximize();
        }
      }
      // 翻转 Q5：必须先 await 让平台侧「隐藏标题栏」样式就绪，随后 measureFrameInsets
      // 才能采到隐藏态的真实客户区（win32 读平台实时状态，与视图 metrics 解耦）。
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
```

`Log.d` 那两行保留原位（在读完 `_lastWindowSize` 之后、`setTitleBarStyle` 之前）。

- [ ] **Step 4: 两条退出路径消费还原点**

`exitSmallWindow`（`:774`）桌面分支末尾 `windowManager.setAlwaysOnTop(false);` 之后加：

```dart
      _consumeNormalGeometry();
```

`exitFull`（`:648`）桌面分支里 `windowManager.setTitleBarStyle(TitleBarStyle.normal);` 之后加：

```dart
      _consumeNormalGeometry();
```

`exitFull` 开头把小窗整单转交 `exitSmallWindow` 那段（`:654-657`）不动——它保证了 PiP 清理只有一个出口。

- [ ] **Step 5: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze
```
Expected：无 issue。本任务没有可单测的纯逻辑（全是窗口调用），行为由 Task 11 的手测矩阵验收：窗口→小窗→退出／窗口→全屏→退出／窗口→全屏→小窗→退出／窗口→小窗→全屏→退出，四条都要落回窗口态且尺寸是进全屏前那个。

- [ ] **Step 6: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_controller.dart
git commit -m "fix(player): 小窗还原点改为离开窗口态时采集，支持从全屏直接进小窗

- 原先只有 enterSmallWindow 写几何，从全屏进小窗会把满屏当还原目标
- 进小窗前先退 OS 全屏、必要时取消最大化，setSize 才收得住
- 谁先离开窗口态谁捕获、退出时消费，两条路径共用一个还原点"
```

---

## Task 5: 动作执行层与弹层

**Files:**
- Create: `simple_live_app/lib/modules/live_room/player/player_action_views.dart`
- Modify: `simple_live_app/lib/modules/live_room/live_room_controller.dart`（本任务不动它；`showVolumeSlider` 在 Task 8 之后已无调用点，随死代码清理删除）

**Interfaces:**
- Consumes: Task 2 的 `PlayerAction` / `PlayerActionId` / `PlayerActionLayout`；`LiveRoomController` 上既有方法 `refreshRoom` `saveScreenshot` `showQualitySheet` `showPlayUrlsSheet` `showPlayerSettingsSheet` `showDanmuSettingsSheet` `showDebugInfo` `showAutoExitSheet` `share` `copyUrl` `openNaviteAPP` `enterSmallWindow` `exitSmallWindow` `enterFullScreen` `exitFull`，以及 `multiPlay.replaceTileRoom` / `buildSwitchEntries`；`Utils.showRightDialog`（`app/utils.dart:112`）
- Produces:
  - `void invokePlayerAction({required LiveRoomController target, required LiveRoomController page, required PlayerActionId id, required BuildContext context})`
  - `void showActionMenu({required String title, required List<PlayerAction> items, required void Function(PlayerActionId) onSelect})`
  - `IconData playerActionIcon(PlayerActionId id)`
  - `class FollowPickButton` —— 选台锚定浮层（Step 4）

- [ ] **Step 1: 建文件与动作分发**

`simple_live_app/lib/modules/live_room/player/player_action_views.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';

/// 动作 id → 真实调用。
///
/// [target] 是这一路（窗口化/全屏＝页面主格，多开时＝聚焦格；格子＝本格），
/// [page] 恒是页面主格：窗口级动作（小窗、定时关闭）只能由它执行，
/// 四路各跑一份倒计时或直接 `exit(0)` 是不能接受的。
void invokePlayerAction({
  required LiveRoomController target,
  required LiveRoomController page,
  required PlayerActionId id,
  required BuildContext context,
}) {
  switch (id) {
    case PlayerActionId.refresh:
      target.refreshRoom();
    case PlayerActionId.danmakuToggle:
      target.showDanmakuState.value = !target.showDanmakuState.value;
    case PlayerActionId.danmakuSettings:
      target.showDanmuSettingsSheet();
    case PlayerActionId.screenshot:
      target.saveScreenshot();
    case PlayerActionId.quality:
      target.showQualitySheet();
    case PlayerActionId.line:
      target.showPlayUrlsSheet();
    case PlayerActionId.scale:
      target.showPlayerSettingsSheet();
    case PlayerActionId.smallWindow:
      // 小窗态下同一个位置的动作是「退出小窗」，由 renderer 换 title，这里只看状态。
      if (target.smallWindowState.value) {
        page.exitSmallWindow();
      } else {
        page.enterSmallWindow();
      }
    case PlayerActionId.fullscreenToggle:
      if (target.fullScreenState.value) {
        page.exitFull();
      } else {
        page.enterFullScreen();
      }
    case PlayerActionId.debugInfo:
      target.showDebugInfo();
    case PlayerActionId.autoExit:
      page.showAutoExitSheet();
    case PlayerActionId.share:
      target.share();
    case PlayerActionId.copyUrl:
      target.copyUrl();
    case PlayerActionId.openApp:
      target.openNaviteAPP();
    case PlayerActionId.pick:
    case PlayerActionId.volume:
    case PlayerActionId.closeTile:
      // pick 与 volume 是锚定控件，renderer 直接画对应 widget，不走这里；
      // closeTile 需要格子的 index，由 renderer 闭包带走。
      break;
  }
}
```

- [ ] **Step 2: `⋮` 的抽屉渲染**

同文件继续加：

```dart
/// `⋮` 的内容：桌面右侧抽屉，按清单顺序列出「图标 + 标题」。
///
/// 抽屉自带返回按钮（`Utils.showRightDialog` 的头），点外部是否关闭沿用现有行为，
/// 本次不改。移动端不会走到这里（平台门短路）。
void showActionMenu({
  required String title,
  required List<PlayerAction> items,
  required void Function(PlayerActionId) onSelect,
}) {
  Utils.showRightDialog(
    title: title,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final item in items)
          ListTile(
            leading: Icon(playerActionIcon(item.id)),
            title: Text(item.title),
            onTap: () {
              Utils.hideRightDialog();
              onSelect(item.id);
            },
          ),
      ],
    ),
  );
}
```

`playerActionIcon` 与图标表放同文件（renderer 也要用）：

```dart
/// 条带里的图标。弹幕开关的两个 asset 图标是 `ImageIcon`，由 renderer 自己处理，
/// 这里只给 `⋮` 抽屉里的行用（抽屉里用普通图标即可）。
IconData playerActionIcon(PlayerActionId id) {
  return switch (id) {
    PlayerActionId.refresh => Icons.refresh,
    PlayerActionId.danmakuToggle => Icons.chat_bubble_outline,
    PlayerActionId.danmakuSettings => Icons.tune,
    PlayerActionId.screenshot => Icons.camera_alt_outlined,
    PlayerActionId.pick => Icons.play_list,
    PlayerActionId.quality => Icons.high_quality,
    PlayerActionId.line => Icons.switch_video_outlined,
    PlayerActionId.scale => Icons.aspect_ratio_outlined,
    PlayerActionId.smallWindow => Icons.picture_in_picture,
    PlayerActionId.fullscreenToggle => Icons.fullscreen,
    PlayerActionId.closeTile => Icons.close,
    PlayerActionId.debugInfo => Icons.info_outline_rounded,
    PlayerActionId.autoExit => Icons.timer_outlined,
    PlayerActionId.share => Icons.share,
    PlayerActionId.copyUrl => Icons.copy,
    PlayerActionId.openApp => Icons.open_in_new,
    PlayerActionId.volume => Icons.volume_up,
  };
}
```

补 import：`import 'package:simple_live_app/app/utils.dart';`

- [ ] **Step 3: 确认这些方法名真的存在**

```bash
cd /c/dart_simple_live/simple_live_app && grep -rn "void showAutoExitSheet\|void share(\|void copyUrl(\|void openNaviteAPP(\|void showDebugInfo(\|void showQualitySheet(\|void showPlayUrlsSheet(\|void showPlayerSettingsSheet(\|void showDanmuSettingsSheet(" lib/modules/live_room/live_room_controller.dart lib/modules/live_room/player/player_controller.dart
```
Expected：每个都在 `LiveRoomController` 上找得到定义。若 `share`/`copyUrl`/`openNaviteAPP` 名字不同（页级菜单里是 `room.share()`，见 `live_room_page.dart:1099`），以文件里实际的名字为准改 Step 1 的分发表，**不要**新加一层转发。

- [ ] **Step 4: 选台锚定浮层组件**

`pick` 用 `PopupMenuButton`（锚定、常挂，不弹抽屉）。把 `multi_play_tile.dart:220` 的 `_buildSwitchButton` 提成公共 widget，放本文件：

```dart
/// 选台：把这一格／这一路换成关注列表里另一个正在直播的直播间。
///
/// 数据源就是 `MultiPlaySession.buildSwitchEntries()`——非多开时它的 slots 只有页面主格
/// 自己，所以单画面也能直接用同一个列表，`playingSlot >= 0` 即「已在本会话里播」。
/// 换台走 `replaceTileRoom`：它在单画面下等价于 `resetRoom`（主格也在自己的 slots 里），
/// 命中别的格子时只把焦点移过去，不建第二个实例。
///
/// 菜单开着时 [onOpened] 要把网格的自动隐藏倒计时续上；宿主侧必须常挂这个按钮
/// （`IgnorePointer` + 淡出），否则 `showButtonMenu` 的 `.then` 会因 unmount 丢掉选中结果。
class FollowPickButton extends StatelessWidget {
  const FollowPickButton({
    super.key,
    required this.target,
    required this.icon,
    this.style,
    this.iconSize,
    this.tooltip = "选台",
    this.onOpened,
  });

  final LiveRoomController target;
  final Widget icon;
  final ButtonStyle? style;
  final double? iconSize;
  final String tooltip;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FollowUser>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      iconSize: iconSize,
      style: style,
      icon: icon,
      onOpened: onOpened,
      itemBuilder: (context) {
        // 在菜单打开时才扫关注列表：放在 build 里，四格每帧都要扫一遍
        final entries = target.multiPlay.buildSwitchEntries();
        if (entries.isEmpty) {
          return const [
            AppPopupMenuItem<FollowUser>(
              enabled: false,
              child: SizedBox(width: 220, child: Text("关注列表里没有正在直播的主播")),
            ),
          ];
        }
        return [
          for (final entry in entries)
            AppPopupMenuItem<FollowUser>(
              value: entry.user,
              // 定宽：菜单容器宽度可能是无界的，Expanded 撞上无界约束会直接报错
              child: SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.user.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(entry.platform, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (entry.isPlaying) ...[
                      const SizedBox(width: 6),
                      const Text("在播", style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
        ];
      },
      onSelected: (user) {
        final site = Sites.allSites[user.siteId];
        if (site == null) {
          return;
        }
        target.multiPlay.replaceTileRoom(target, site, user.roomId);
      },
    );
  }
}
```

补 import：`package:simple_live_app/widgets/app_popup_menu_item.dart`。

- [ ] **Step 5: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze
```
Expected：无 issue（此时还没有调用方，`player_action_views.dart` 的公开函数会被 analyze 认作已使用——它们是 `library` 级 public，不会报 unused）。

- [ ] **Step 6: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_action_views.dart
git commit -m "feat(player): 动作执行层与 ⋮ 抽屉、选台锚定浮层

- invokePlayerAction 收一处：窗口级动作恒走页面主格
- showActionMenu 桌面统一渲染成右侧抽屉
- FollowPickButton 从格子 ▾ 提出来，单画面与每格同源
- 图标表单独一处，抽屉与条带共用"
```

---

## Task 6: 音量三态控件

**Files:**
- Create: `simple_live_app/lib/modules/live_room/player/player_volume_action.dart`
- Modify: `simple_live_app/lib/modules/live_room/multi_play/multi_play_tile.dart`（删掉 `_TileVolumeButton`，改调用新 widget；Task 9 完成接线）

**Interfaces:**
- Consumes: `LiveRoomController.volumeFactor` / `muted` / `toggleMute()` / `nudgeVolumeFactor(double)`（`live_room_controller.dart:109-137`）、`AppSettingsController.playerVolume` / `playerMaxVolume` / `setPlayerVolume(double)`、`MultiPlaySession.applyVolumes()`
- Produces:
  - `class VolumeTarget { VolumeTarget.master(LiveRoomController page) / VolumeTarget.tile(LiveRoomController tile); double get value; double get maxValue; String get label; void setValue(double); void nudge(double); void toggleMute(); }`
  - `class VolumeActionWidget extends StatelessWidget { VolumeActionWidget({required VolumeTarget target, required ButtonStyle style, double iconSize = 24, bool overlayPopover = false, VoidCallback? onInteract}) }`

- [ ] **Step 1: 写 `VolumeTarget`**

```dart
import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 音量按钮此刻绑的是哪个量。
///
/// 形态一致、绑的量按宿主不同是刻意决定（spec §3）：单播放的滑条必须是**总音量**
/// （那是 OSD 里唯一的总音量入口，换成按路系数就等于把它藏了），格子绑**该格系数**。
/// 浮层标题把区别写出来（`总音量` / `第 2 路`），免得用户在格子上拖了一下发现四路都变了。
class VolumeTarget {
  VolumeTarget.master(LiveRoomController page)
      : label = "总音量",
        _page = page,
        _tile = null;

  VolumeTarget.tile(LiveRoomController tile)
      : label = "第${tile.tileSlot + 1}路",
        _page = null,
        _tile = tile;

  final String label;
  final LiveRoomController? _page;
  final LiveRoomController? _tile;

  /// 是否绑总音量（true＝单播放宿主，false＝格子宿主）。
  bool get isMaster => _tile == null;

  LiveRoomController get _owner => _tile ?? _page!;

  /// 归一化到 0~1，用于显示百分比与滚轮步进。
  double get ratio {
    if (isMaster) {
      final max = AppSettingsController.instance.playerMaxVolume.value;
      return max <= 0 ? 0 : AppSettingsController.instance.playerVolume.value / max;
    }
    return _tile!.volumeFactor.value;
  }

  bool get muted => ratio <= 0.001;

  void setValueRatio(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    if (isMaster) {
      final max = AppSettingsController.instance.playerMaxVolume.value;
      AppSettingsController.instance.setPlayerVolume(max * clamped);
      // 总音量是唯一的音量权威：压低开启时非聚焦格按 ratio 跟着走
      _owner.multiPlay.applyVolumes();
      return;
    }
    _tile!.nudgeVolumeFactor(clamped - _tile!.volumeFactor.value);
  }

  void nudge(double deltaRatio) => setValueRatio(ratio + deltaRatio);

  void toggleMute() => _owner.toggleMute();
}
```

`LiveRoomController` 上要用到的成员实际名字以文件为准：`tileSlot`（`live_room_controller.dart` 里给格子标槽位的 getter）、`volumeFactor`、`toggleMute`、`nudgeVolumeFactor`、`multiPlay`。若 `tileSlot` 在非多开时不可用（返回 -1），label 走 `isMaster` 分支，不需要它。

- [ ] **Step 2: 写 widget：点击静音、悬停滑条、滚轮微调**

同文件继续：

```dart
/// 音量按钮的三态：点击＝静音这一路，悬停＝出滑条，滚轮＝±5%。
///
/// 点击静音要保住：原先格子上「点一下静音」是快按，滑条做成悬停弹出之后仍然不改它，
/// 否则「静音这路」从一次点击变成两次操作。
///
/// 滑条是**同一个 `MouseRegion` 的孩子**，不能飘出去用 `SmartDialog`：飘出去就不在
/// hover 区内，指针移到滑条上会触发 `onExit`，滑条立刻消失、根本拖不动。
/// [overlayPopover] 为 true 时（格子宿主）滑条浮在按钮上方、向左上展开，
/// 因为格子胶囊只有 240px 宽，行内展开会把旁边的昵称挤成省略号；
/// 条带宿主用行内展开（向左长，右侧那簇不动，Expanded 吃掉宽度），零位移。
class VolumeActionWidget extends StatefulWidget {
  const VolumeActionWidget({
    super.key,
    required this.target,
    required this.style,
    this.iconSize = 24,
    this.overlayPopover = false,
    this.onInteract,
  });

  final VolumeTarget target;
  final ButtonStyle style;
  final double iconSize;
  final bool overlayPopover;
  final VoidCallback? onInteract;

  static const double _step = 0.05;
  static const double _sliderWidth = 88;

  @override
  State<VolumeActionWidget> createState() => _VolumeActionWidgetState();
}

class _VolumeActionWidgetState extends State<VolumeActionWidget> {
  bool _hovering = false;
  bool _showingTip = false;
  Timer? _tipTimer;

  void _showTip() {
    _tipTimer?.cancel();
    if (!_showingTip) {
      setState(() => _showingTip = true);
    }
    _tipTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showingTip = false);
      }
    });
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  void _onPointerSignal(PointerScrollEvent event) {
    widget.onInteract?.call();
    widget.target.nudge(event.scrollDelta.dy > 0 ? -VolumeActionWidget._step : VolumeActionWidget._step);
    _showTip();
  }

  Widget _buildSlider(BuildContext context) {
    return Obx(() {
      final ratio = widget.target.ratio;
      return SizedBox(
        width: VolumeActionWidget._sliderWidth,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            isTrackVertical: false,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: ratio,
            onChanged: (value) {
              widget.onInteract?.call();
              widget.target.setValueRatio(value);
            },
          ),
        ),
      );
    });
  }

  Widget _buildTip() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: AppStyle.radius8),
        child: Obx(
          () => Text(
            "${(widget.target.ratio * 100).round()}%",
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _onPointerSignal(event);
          }
        },
        child: Obx(() {
          final button = IconButton(
            tooltip: widget.target.muted ? "取消静音（悬停可调音量）" : "静音（悬停可调音量）",
            style: widget.style,
            iconSize: widget.iconSize,
            icon: Icon(widget.target.muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () {
              widget.onInteract?.call();
              widget.target.toggleMute();
            },
          );
          if (widget.overlayPopover) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                button,
                if (_hovering)
                  Positioned(
                    right: 0,
                    bottom: 30,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: AppStyle.radius8,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.target.label,
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                            _buildSlider(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_showingTip) Positioned(right: 0, bottom: 34, child: _buildTip()),
              ],
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hovering) _buildSlider(context),
              button,
              if (_showingTip)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const SizedBox(width: 0, height: 24),
                    Positioned(right: 0, bottom: 26, child: _buildTip()),
                  ],
                ),
            ],
          );
        }),
      ),
    );
  }
}
```

补 import：`package:get/get.dart`（`Obx` 走 GetX；文件里已有 `RxDouble`，这里订阅它）。

- [ ] **Step 3: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze lib/modules/live_room/player/player_volume_action.dart
```
Expected：无 issue。此 widget 还没有调用方，Task 8/9 接上后由手测验收（悬停出滑条可拖、滚动 ±5% 有百分比浮层、点击静音与取消静音还原上次的值）。

- [ ] **Step 4: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_volume_action.dart
git commit -m "feat(player): 音量三态控件（点击静音/悬停滑条/滚轮微调）

- VolumeTarget 区分总音量与该格系数，形态一致语义按宿主标注
- 滑条必须是同一 MouseRegion 的孩子，飘出去会被 onExit 关掉
- 条带行内向左展开、格子浮在按钮上方，都不挤动旁边控件"
```

---

## Task 7: 按格独立画面尺寸

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_fit.dart:10`
- Modify: `simple_live_app/lib/modules/live_room/live_room_controller.dart`（加 `scaleModeOverride`）
- Modify: `simple_live_app/lib/modules/live_room/player/player_controller.dart:442`（`updateScaleMode`）
- Modify: `simple_live_app/lib/modules/live_room/live_room_controller.dart:1060`（`showPlayerSettingsSheet`）
- Modify: `simple_live_app/lib/modules/live_room/multi_play/multi_play_tile.dart:342`（`_buildVideo`）

**Interfaces:**
- Consumes: `AppSettingsController.scaleMode` / `aspectByUser` / `setScaleMode`
- Produces: `LiveRoomController.scaleModeOverride`（`int?`，`null`＝跟随全局）、`int get effectiveScaleMode`、`resolvePlayerFit([int? scaleMode])`

- [ ] **Step 1: `resolvePlayerFit` 接收覆盖值**

`player_fit.dart`：把函数签名从 `resolvePlayerFit()` 改为下面这版，其余分支不动：

```dart
/// 「画面尺寸」设置（scaleMode）→ `Video` 的 fit 与锁定比例。
///
/// [scaleMode] 传 null 时读全局设置；多开的每格可以传自己的覆盖值（会话级，不落盘），
/// 让一路竖屏主播铺满、另一路横屏主播保持适应。
///
/// scaleMode：0 适应 / 1 拉伸 / 2 铺满 / 3 16:9 / 4 4:3 / 5 自定义比例。
({BoxFit fit, double? aspectRatio}) resolvePlayerFit([int? scaleMode]) {
  final settings = AppSettingsController.instance;
  switch (scaleMode ?? settings.scaleMode.value) {
```

- [ ] **Step 2: controller 上加覆盖字段**

`live_room_controller.dart`，紧跟 `volumeFactor`（`:109`）那一段之后：

```dart
  /// 这一格的画面尺寸覆盖值；null ＝跟随全局设置。
  ///
  /// 会话级、不落盘：格子是临时身份（换台会换房间、关一格就散），存下来下一次
  /// 对不上号反而更困惑。新加入的一路继承全局设置。
  /// 自定义比例的宽:高仍然是全局值，按格只覆盖模式。
  final RxnInt scaleModeOverride = RxnInt();

  int get effectiveScaleMode => scaleModeOverride.value ?? AppSettingsController.instance.scaleMode.value;

  /// 由格子的画面尺寸菜单调用：改完立刻下发到这一格的 `Video`。
  void setTileScaleMode(int mode) {
    scaleModeOverride.value = mode;
    updateScaleMode();
  }
```

`RxnInt` 若 GetX 版本没有，用 `final Rx<int?> scaleModeOverride = Rx<int?>(null);`。

- [ ] **Step 3: `updateScaleMode` 走本格有效值**

`player_controller.dart:442` 的方法体整体替换为（保持它经 `globalPlayerKey` 下发的机制不变）：

```dart
  void updateScaleMode() {
    final resolved = resolvePlayerFit(effectiveScaleModeForFit());
    globalPlayerKey.currentState?.update(
      aspectRatio: resolved.aspectRatio,
      fit: resolved.fit,
    );
  }

  /// 本实例该用哪个 scaleMode 算 fit：`LiveRoomController` 覆写成「按格覆盖优先」。
  /// 基类（非直播间控制器）就读全局。
  int effectiveScaleModeForFit() => AppSettingsController.instance.scaleMode.value;
```

在 `LiveRoomController` 里覆写：

```dart
  @override
  int effectiveScaleModeForFit() => effectiveScaleMode;
```

注意：`resolvePlayerFit` 在 `player_controller.dart`（mixin）里要用，补 import `package:simple_live_app/modules/live_room/player/player_fit.dart`。原方法里那 6 个 `if/else if` 与 `AppSettingsController.instance.scaleMode.value` 的读取全部由 `resolvePlayerFit` 承担，删掉重复实现（文件里那句 `// todo: 代码复用` 正是这一处，可以一并去掉）。

- [ ] **Step 4: 菜单按格读写**

`live_room_controller.dart:1060` 的 `showPlayerSettingsSheet` 改两处：

```dart
  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      // 多开的格子改的是自己那一格，标题要说清楚作用范围，
      // 否则用户会以为在调整窗。
      title: isSecondaryTile ? "画面尺寸 · 第${tileSlot + 1}路（仅这一格）" : "画面尺寸",
      child: Obx(
        () => ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            RadioGroup(
              groupValue: effectiveScaleMode,
              onChanged: (e) {
                final mode = e ?? 0;
                if (multiPlay.isActive) {
                  setTileScaleMode(mode);
                } else {
                  AppSettingsController.instance.setScaleMode(mode);
                  updateScaleMode();
                }
              },
```

其余 `RadioListTile` 项不动；最后一项「自定义」的标题仍读全局 `aspectWidth/aspectHeight`。

- [ ] **Step 5: 格子的 `Video` 订阅覆盖值**

`multi_play_tile.dart:342`：

```dart
  Widget _buildVideo() {
    final settings = AppSettingsController.instance;
    // 订阅本格的覆盖值：它变了这格的外框比例要跟着重建（updateScaleMode 只改 state，
    // 初始参数不变的话、下一次重建又会回到旧值）。
    final fit = resolvePlayerFit(tile.effectiveScaleMode);
    return Video(
```

`Obx(_buildVideo)`（`:77`）已经存在，`effectiveScaleMode` 读的是 `RxnInt`，订阅自动成立。

- [ ] **Step 6: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze && ../.fvm/flutter_sdk/bin/flutter.bat test test/pip_aspect_calculator_test.dart
```
Expected：analyze 无 issue；纵横比相关用例仍绿（小窗锁定比例读的是全局值，本任务不动它）。

- [ ] **Step 7: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_fit.dart simple_live_app/lib/modules/live_room/player/player_controller.dart simple_live_app/lib/modules/live_room/live_room_controller.dart simple_live_app/lib/modules/live_room/multi_play/multi_play_tile.dart
git commit -m "feat(multiplay): 画面尺寸可按格独立（会话级覆盖，不落盘）

- resolvePlayerFit 收可选 scaleMode，controller 用 effectiveScaleMode
- 多开下的画面尺寸菜单只改本格并在标题标明范围
- 格子的 Video 初始参数订阅覆盖值，避免重建后回退"
```

---

## Task 8: 桌面条带接 resolver（窗口化／全屏／小窗）

**Files:**
- Create: `simple_live_app/lib/modules/live_room/player/player_action_bar.dart`
- Modify: `simple_live_app/lib/modules/live_room/player/player_controls.dart:23`（dispatcher 平台门）、`:50`（`buildFullControls`）、`:471`（`buildControls`）

**Interfaces:**
- Consumes: Task 2 `resolvePlayerActions`／Task 5 `invokePlayerAction`/`showActionMenu`/`FollowPickButton`／Task 6 `VolumeActionWidget`/`VolumeTarget`；Task 4 的 `enterSmallWindow` 从全屏可用
- Produces:
  - `class PlayerActionBar extends StatelessWidget { PlayerActionBar({required PlayerHost host, required LiveRoomController target, required LiveRoomController page, required List<PlayerAction> bar, required List<PlayerAction> overflow, TextStyle? textStyle, VoidCallback? onInteract, Widget? trailing}) }`

- [ ] **Step 1: 写 renderer**

`player_action_bar.dart`：

```dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';

/// 播放条带／胶囊的渲染器：把 resolver 的产物画出来，三个宿主共用。
///
/// 图标在这里决定（模型不持有图标）：弹幕开关用 asset `ImageIcon`、清晰度／线路用
/// 文字按钮——它们是「读数」不是「动作」，宽度随内容变。
///
/// 文字按钮必须带 [textStyle]：`ButtonStyle.textStyle` 与主题的 buttonTheme 是覆盖
/// 关系而不是合并关系，只写 fontSize 会把用户设定的字族丢掉。
class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({
    super.key,
    required this.host,
    required this.target,
    required this.page,
    required this.bar,
    required this.overflow,
    this.textStyle,
    this.onInteract,
    this.trailing,
    this.iconSize = 24,
    this.canCloseTile = false,
    this.onCloseTile,
  });

  final PlayerHost host;
  final LiveRoomController target;
  final LiveRoomController page;
  final List<PlayerAction> bar;
  final List<PlayerAction> overflow;
  final TextStyle? textStyle;
  final VoidCallback? onInteract;
  final Widget? trailing;
  final double iconSize;
  final bool canCloseTile;
  final VoidCallback? onCloseTile;

  static final ButtonStyle _iconStyle = IconButton.styleFrom(
    minimumSize: const Size(36, 36),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: Colors.white,
  );

  /// 底栏那一行：左簇 → `Spacer` → 右簇 → `⋮`。
  ///
  /// 顶栏不由这里渲染：它要插返回键与标题（容器结构，不是动作，见 spec §8 的建模口径），
  /// 由 `player_controls.dart` 用同一个 `buildPlayerActionItem` 自己排。
  @override
  Widget build(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (final action in bar) {
      if (host == PlayerHost.fullscreen && action.placeInTopBar) {
        continue;
      }
      final item = buildPlayerActionItem(
        action: action,
        host: host,
        target: target,
        page: page,
        textStyle: textStyle,
        iconSize: iconSize,
        onInteract: onInteract,
        onCloseTile: onCloseTile,
      );
      (action.rightSide ? right : left).add(item);
    }
    return Row(
      children: [
        ...left,
        const Spacer(),
        ...right,
        if (overflow.isNotEmpty)
          IconButton(
            tooltip: "更多",
            iconSize: iconSize,
            style: _iconStyle,
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {
              onInteract?.call();
              showActionMenu(
                title: "更多",
                items: overflow,
                onSelect: (id) => invokePlayerAction(target: target, page: page, id: id, context: Get.context!),
              );
            },
          ),
        if (trailing != null) trailing!,
      ],
    );
  }

  }
}

/// 单个动作的 widget。**文件级函数**：`PlayerActionBar` 负责组装整行，全屏顶栏要自己插
/// 返回键与标题，所以拿这个函数逐个排——两处画同一个动作必须是同一个函数，否则又分叉。
Widget buildPlayerActionItem({
  required PlayerAction action,
  required PlayerHost host,
  required LiveRoomController target,
  required LiveRoomController page,
  required TextStyle? textStyle,
  double iconSize = 24,
  VoidCallback? onInteract,
  VoidCallback? onCloseTile,
}) {
  switch (action.id) {
      case PlayerActionId.danmakuToggle:
        // 开／关两个 asset 图标，是「状态」而不是「动作名」，所以不能收进 ⋮ 用通用图标。
        return Obx(
          () => IconButton(
            tooltip: target.showDanmakuState.value ? "关闭弹幕" : "开启弹幕",
            iconSize: iconSize,
            style: _iconStyle,
            icon: ImageIcon(
              AssetImage(
                target.showDanmakuState.value
                    ? 'assets/icons/icon_danmaku_close.png'
                    : 'assets/icons/icon_danmaku_open.png',
              ),
              size: iconSize,
              color: Colors.white,
            ),
            onPressed: () => invokePlayerAction(target: target, page: page, id: action.id, context: Get.context!),
          ),
        );
      case PlayerActionId.quality:
      case PlayerActionId.line:
        return Obx(
          () => TextButton(
            style: TextButton.styleFrom(
              textStyle: textStyle,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              onInteract?.call();
              invokePlayerAction(target: target, page: page, id: action.id, context: Get.context!);
            },
            child: Text(
              action.id == PlayerActionId.quality
                  ? target.currentQualityInfo.value
                  : target.currentLineInfo.value,
              style: TextStyle(color: Colors.white, fontSize: iconSize > 20 ? 15 : 13),
            ),
          ),
        );
      case PlayerActionId.pick:
        return FollowPickButton(
          target: target,
          style: _iconStyle,
          iconSize: iconSize,
          icon: const Icon(Icons.arrow_drop_down),
          onOpened: onInteract,
        );
      case PlayerActionId.volume:
        return VolumeActionWidget(
          target: host == PlayerHost.tile ? VolumeTarget.tile(target) : VolumeTarget.master(page),
          style: _iconStyle,
          iconSize: iconSize,
          overlayPopover: host == PlayerHost.tile,
          onInteract: onInteract,
        );
      case PlayerActionId.closeTile:
        return IconButton(
          tooltip: action.title,
          iconSize: iconSize,
          style: _iconStyle,
          icon: const Icon(Icons.close),
          onPressed: onCloseTile,
        );
      case PlayerActionId.smallWindow:
        return Obx(
          () => IconButton(
            tooltip: target.smallWindowState.value ? "退出小窗" : action.title,
            iconSize: iconSize,
            style: _iconStyle,
            icon: Icon(Icons.picture_in_picture, color: Colors.white),
            onPressed: () => invokePlayerAction(target: target, page: page, id: action.id, context: Get.context!),
          ),
        );
      case PlayerActionId.fullscreenToggle:
        return Obx(
          () => IconButton(
            tooltip: target.fullScreenState.value ? "退出全屏" : "全屏播放",
            iconSize: iconSize,
            style: _iconStyle,
            icon: Icon(
              target.fullScreenState.value ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: () => invokePlayerAction(target: target, page: page, id: action.id, context: Get.context!),
          ),
        );
      default:
        return IconButton(
          tooltip: action.title,
          iconSize: iconSize,
          style: _iconStyle,
          icon: Icon(playerActionIcon(action.id), color: Colors.white),
          onPressed: () {
            onInteract?.call();
            invokePlayerAction(target: target, page: page, id: action.id, context: Get.context!);
          },
        );
    }
  }
}
```

写完这个函数后有三处收口：① `buildPlayerActionItem` 的函数体整体比原来少两级缩进（它不再在
class 里）；② `_iconStyle` 从类的 `static final` 提到文件级 `final ButtonStyle _iconStyle = …`，
类和这个函数都读它，名字不变；③ 类的 `canCloseTile` 字段删掉——能不能关已经由 resolver 决定
（`closeTile` 在不在 `bar` 里），widget 再拿一份就是两个真相。

`Spacer()` 而不是 `Expanded(child: Center())`：resolver 已经把左右簇分好，`Spacer` 吃掉余量即可，
且不会像 flex 那样先分掉一半宽度。

- [ ] **Step 2: dispatcher 加平台门**

`player_controls.dart:23` 的 `playerControls` 改成：

```dart
Widget playerControls(VideoState videoState, LiveRoomController controller) {
  return Obx(() {
    // 移动端不进这套模型：安卓走下面两个既有 builder 的原样清单，
    // 桌面才用 resolver 驱动的条带（spec §3 的平台门）。
    if (Platform.isAndroid || Platform.isIOS) {
      return controller.fullScreenState.value
          ? buildFullControls(videoState, controller)
          : buildControls(videoState.context.orientation == Orientation.portrait, videoState, controller);
    }
    return controller.fullScreenState.value
        ? _buildDesktopFullControls(videoState, controller)
        : _buildDesktopControls(videoState, controller);
  });
}
```

- [ ] **Step 3: 桌面窗口化条带**

同文件加：

```dart
/// 桌面窗口化的底栏：与全屏用同一份清单、同一个 renderer，只是没有顶栏。
Widget _buildDesktopControls(VideoState videoState, LiveRoomController controller) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final layout = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: constraints.maxWidth - 24,
        isVertical: controller.isVertical.value,
        hasQuality: controller.qualites.length > 1,
        hasLine: controller.playUrls.length > 1,
      );
      return Stack(
        children: [
          Container(),
          buildDanmuView(videoState, controller),
          Center(
            child: StreamBuilder(
              stream: videoState.widget.controller.player.stream.buffering,
              initialData: videoState.widget.controller.player.state.buffering,
              builder: (_, s) => Visibility(
                visible: s.data ?? false,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: controller.onTap,
              onDoubleTapDown: controller.onDoubleTap,
              onVerticalDragStart: controller.onVerticalDragStart,
              onVerticalDragUpdate: controller.onVerticalDragUpdate,
              onVerticalDragEnd: controller.onVerticalDragEnd,
              child: MouseRegion(
                onEnter: controller.onEnter,
                child: Container(width: double.infinity, height: double.infinity, color: Colors.transparent),
              ),
            ),
          ),
          Obx(
            () => AnimatedPositioned(
              left: 0,
              right: 0,
              bottom: controller.showControlsState.value ? 0 : -48,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PlayerActionBar(
                  host: PlayerHost.windowed,
                  target: controller,
                  page: controller,
                  bar: layout.bar,
                  overflow: layout.overflow,
                  textStyle: playerToolbarTextStyle(),
                  onInteract: controller.showControls,
                ),
              ),
            ),
          ),
          Obx(
            () => Offstage(
              offstage: !controller.showGestureTip.value,
              child: Center(child: _gestureTip(controller)),
            ),
          ),
          Positioned.fill(child: buildOsdOverlay(controller)),
        ],
      );
    },
  );
}
```

`_gestureTip(controller)` 就是把现有那坨 `Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(12)), child: Text(controller.gestureTipText.value, ...))`（`player_controls.dart:665-674`）提成一个私有函数，两个桌面 builder 与移动 builder 都调它，不要复制两份。

`playerToolbarTextStyle()` 是 Step 1 的 `player_action_bar.dart` 里那个文件级 helper（Step 4 末尾
给出定义与页面转发的改法）；不要在这里另写一份，也不要直接从 `live_room_page.dart` import 私有的
`_toolbarTextStyle`——那东西跨不了库。

- [ ] **Step 4: 桌面全屏条带**

同文件再加。要点：顶栏仍在（返回＋标题＋顶栏动作），底栏用 renderer；小窗态只画底栏且动作集合换成 `PlayerHost.smallWindow`；锁定按钮与 `DragToMoveArea` 原样保留。

```dart
Widget _buildDesktopFullControls(VideoState videoState, LiveRoomController controller) {
  final padding = MediaQuery.of(videoState.context).padding;
  final host = controller.smallWindowState.value ? PlayerHost.smallWindow : PlayerHost.fullscreen;
  return LayoutBuilder(
    builder: (context, constraints) {
      // 顶栏与底栏各有一套宽度预算：顶栏还要容纳标题，所以给它更小的预算。
      final layout = resolvePlayerActions(
        host: host,
        availableWidth: constraints.maxWidth - 24,
        isVertical: controller.isVertical.value,
        hasQuality: controller.qualites.length > 1,
        hasLine: controller.playUrls.length > 1,
      );
      final visible = controller.showControlsState.value && !controller.lockControlsState.value;
      final showTopBar = host == PlayerHost.fullscreen;
      return buildDragToMoveArea(
        child: Stack(
          children: [
            Container(),
            buildDanmuView(videoState, controller),
            Center(
              child: StreamBuilder(
                stream: videoState.widget.controller.player.stream.buffering,
                initialData: videoState.widget.controller.player.state.buffering,
                builder: (_, s) => Visibility(
                  visible: s.data ?? false,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: controller.onTap,
                onDoubleTapDown: controller.onDoubleTap,
                onLongPress: () {
                  if (controller.lockControlsState.value) {
                    return;
                  }
                  // 长按＝选台，与顶栏那颗同一个动作、同一个浮层。
                  showFollowUser(controller);
                },
                onVerticalDragStart: controller.onVerticalDragStart,
                onVerticalDragUpdate: controller.onVerticalDragUpdate,
                onVerticalDragEnd: controller.onVerticalDragEnd,
                child: MouseRegion(
                  onHover: (event) => controller.onHover(event, videoState.context),
                  child: Container(width: double.infinity, height: double.infinity, color: Colors.transparent),
                ),
              ),
            ),
            if (showTopBar)
              Obx(
                () => AnimatedPositioned(
                  left: 0,
                  right: 0,
                  top: visible ? 0 : -(48 + padding.top),
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 48 + padding.top,
                    padding: EdgeInsets.only(left: padding.left + 12, right: padding.right + 12, top: padding.top),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: PlayerActionBar(
                      host: PlayerHost.fullscreen,
                      target: controller,
                      page: controller,
                      bar: layout.bar,
                      // 顶栏只画 placeInTopBar 的那几颗 + 返回与标题（在 renderer 内部）
                      overflow: const [],
                      textStyle: playerToolbarTextStyle(),
                      onInteract: controller.showControls,
                    ),
                  ),
                ),
              ),
            Obx(
              () => AnimatedPositioned(
                left: 0,
                right: 0,
                bottom: visible ? 0 : -(80 + padding.bottom),
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: padding.left + 12,
                    right: padding.right + 12,
                    bottom: padding.bottom,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: PlayerActionBar(
                    host: host,
                    target: controller,
                    page: controller,
                    bar: layout.bar,
                    overflow: layout.overflow,
                    textStyle: playerToolbarTextStyle(),
                    onInteract: controller.showControls,
                  ),
                ),
              ),
            ),
            Obx(
              () => AnimatedPositioned(
                top: 0,
                bottom: 0,
                right: visible ? padding.right + 12 : -(64 + padding.right),
                duration: const Duration(milliseconds: 200),
                child: buildLockButton(controller),
              ),
            ),
            Obx(
              () => AnimatedPositioned(
                top: 0,
                bottom: 0,
                left: visible ? padding.left + 12 : -(64 + padding.right),
                duration: const Duration(milliseconds: 200),
                child: buildLockButton(controller),
              ),
            ),
            Obx(
              () => Offstage(offstage: !controller.showGestureTip.value, child: Center(child: _gestureTip(controller))),
            ),
            Positioned.fill(child: buildOsdOverlay(controller)),
          ],
        ),
      );
    },
  );
}
```

顶栏不由 `PlayerActionBar` 整行渲染（它要插返回键与标题，标题是容器结构不是动作），
所以顶栏在 `player_controls.dart` 里手排，动作项走 Step 1 那个文件级函数：

```dart
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: controller.smallWindowState.value ? "退出小窗" : "退出全屏",
                          onPressed: () => controller.smallWindowState.value
                              ? controller.exitSmallWindow()
                              : controller.exitFull(),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        AppStyle.hGap12,
                        Expanded(
                          child: Text(
                            "${controller.detail.value?.title} - ${controller.detail.value?.userName}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        AppStyle.hGap12,
                        for (final action in layout.bar.where((e) => e.placeInTopBar))
                          buildPlayerActionItem(
                            action: action,
                            host: PlayerHost.fullscreen,
                            target: controller,
                            page: controller,
                            textStyle: playerToolbarTextStyle(),
                            onInteract: controller.showControls,
                          ),
                      ],
                    ),
```

长按画面那行仍然调 `showFollowUser(controller)`（`player_controls.dart:913` 的既有右侧抽屉，
安卓的长按也在用）：长按没有按钮可以锚，所以它保留抽屉形态；条带/胶囊里的选台是锚定浮层。
两者读的是同一份列表（`FollowService.liveList` / `buildSwitchEntries` 同源），不再新增转发方法。

`playerToolbarTextStyle()` 是本任务在 `player_action_bar.dart` 里加的文件级 helper，把页面里那份
私有 `_toolbarTextStyle`（`live_room_page.dart:48`）搬成公共函数并带原来的 ⚠️ 注释；同任务里把
`live_room_page.dart:48` 改成 `static TextStyle get _toolbarTextStyle => playerToolbarTextStyle();`，
两处共用一个来源，别各写一份。

- [ ] **Step 6: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze && ../.fvm/flutter_sdk/bin/flutter.bat test
```
Expected：analyze 无 issue；测试全绿。然后 `flutter build windows --release`（**先关掉正在运行的 app**），实机走一遍：窗口化出现截图／选台／⋮，全屏底栏多出小窗入口，小窗态只剩四件，竖屏主播的清晰度/线路在 ⋮ 里还在。

- [ ] **Step 7: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/player/player_action_bar.dart simple_live_app/lib/modules/live_room/player/player_controls.dart simple_live_app/lib/modules/live_room/live_room_controller.dart
git commit -m "feat(player): 桌面条带改由动作 resolver 驱动

- 窗口化/全屏/小窗三个宿主共用一个 renderer 与同一份清单
- 全屏补上小窗入口，小窗态平铺收敛成四件、不再出顶栏
- 截图/选台/画面尺寸在窗口化不再缺席，竖屏时清晰度降进 ⋮
- 移动端走平台门短路，仍用原有两套 builder"
```

---

## Task 9: 格子胶囊接 resolver

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/multi_play/multi_play_tile.dart:25`

**Interfaces:**
- Consumes: Task 2 `resolvePlayerActions(host: tile)`、Task 8 `PlayerActionBar`/`buildPlayerActionItem`、Task 5 `FollowPickButton`
- Produces: `MultiPlayTile` 的新构造参数（去掉 `chromeVisible` 之外的私有控件）

- [ ] **Step 1: 宽度预算与动作**

`_buildControlsPill`（`:165`）改为：

```dart
  /// 右下角的按钮胶囊：resolver 给的 tile 切片 + `⋮`。
  ///
  /// 常挂 + `IgnorePointer` + 淡出这一条不能破：`PopupMenuButton` 在菜单打开期间
  /// 被 unmount 会静默丢弃选中结果（`popup_menu.dart` 的 `showButtonMenu().then`）。
  Widget _buildControlsPill() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = resolvePlayerActions(
          // 信息胶囊（序号+昵称+▾）与「更多」各占一段预算，这里只算按钮这一簇。
          host: PlayerHost.tile,
          availableWidth: constraints.maxWidth,
          canCloseTile: index > 0,
          hasQuality: tile.qualites.length > 1,
          hasLine: tile.playUrls.length > 1,
          isVertical: tile.isVertical.value,
        );
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: AppStyle.radius8),
          child: PlayerActionBar(
            host: PlayerHost.tile,
            target: tile,
            page: page,
            bar: layout.bar,
            overflow: layout.overflow,
            iconSize: 20,
            onInteract: onInteract,
            onCloseTile: () => page.multiPlay.removeTile(tile),
            canCloseTile: index > 0,
          ),
        );
      },
    );
  }
```

- [ ] **Step 2: 信息胶囊的 ▾ 换成共用 widget**

`_buildSwitchButton`（`:220`）整体替换为：

```dart
  Widget _buildSwitchButton() {
    return FollowPickButton(
      target: tile,
      style: _iconStyle,
      iconSize: 20,
      tooltip: "第${index + 1}路 · 选台",
      icon: const Icon(Icons.arrow_drop_down),
      onOpened: onInteract,
    );
  }
```

`pick` 在 tile 的 resolver 输出里是 core，但 renderer 把它画在按钮簇里会与信息胶囊重复——所以 Step 1 之后要把 `layout.bar` 中的 `pick` 过滤掉再交给 `PlayerActionBar`，并把它从信息胶囊那个位置渲染：

```dart
            bar: layout.bar.where((e) => e.id != PlayerActionId.pick).toList(),
```

- [ ] **Step 3: 删掉被替换的私有控件**

删除 `_buildMoreButton`（`:303`）与 `_TileVolumeButton`/`_TileVolumeButtonState`（`:415-510`）、`_buildFullScreenButton`（`:284`）、`_buildCloseButton`（`:329`）——它们的职责已经由 renderer 承担。文件顶部不再需要的 import（`dart:async`、`PointerScrollEvent`、`app_popup_menu_item`、`FollowUser`）一并删掉；`_iconStyle` 若已无引用也删。

- [ ] **Step 4: 音量浮层与 chrome 自动隐藏的关系**

滑条浮层是**格子自己 Stack 的孩子**（`_buildControlsPill` 在 `Positioned(bottom: 8)` 里，滑条
`bottom: 30`），所以它天然落在网格的 `MouseRegion` 内：指针在滑条上＝还在网格里＝`onHover`
继续续期，chrome 不会中途收走（`multi_play_grid.dart:79-81`）。要复核的只有一件事：格子
Container 是 `clipBehavior: Clip.antiAlias`（`:74`），滑条那坨约 54 高、距底 30，而格子最小
高度 135（`kMultiPlayMinTileHeight`），不会越出被裁掉。手测时确认四格滑条都能拖住、贴顶那排
也不被裁。

指针**离开网格**时 chrome 隐藏、`IgnorePointer` 同时生效，滑条变不可交互——这是对的：人已经走了。

- [ ] **Step 5: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze && ../.fvm/flutter_sdk/bin/flutter.bat test test/multi_play_layout_test.dart
```
Expected：无 issue，布局用例仍绿。构建后手测：格子点音量＝静音/取消、悬停＝滑条可拖、滚轮＝±5% 带百分比；`⋮` 里刷新/清晰度/线路/截图/画面尺寸都能用；主格（`index==0`）没有 ✕。

- [ ] **Step 6: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/multi_play/multi_play_tile.dart
git commit -m "feat(multiplay): 格子胶囊改由动作 resolver 驱动

- 按钮簇交给共用 renderer，⋮ 与单播放同形
- ▾ 换台换成 FollowPickButton，与单画面选台同源
- 删掉格子自己的音量/更多/全屏/关闭控件
- 滑条是格子 Stack 的孩子，天然在网格 hover 区内（复核 clip 与 135 最小格高）"
```

---

## Task 10: 页级「更多」合流

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/live_room_page.dart:1015`（`showMore`）与 `:998`（`buildAppbarActions`）

**Interfaces:**
- Consumes: Task 2 `resolvePlayerActions`、Task 5 `showActionMenu`/`invokePlayerAction`
- Produces: 桌面「更多」＝右侧抽屉，内容＝`windowed` 宿主的 `overflow`；移动端保持现有底部抽屉

- [ ] **Step 1: 桌面分支走 resolver**

`showMore()` 改为：

```dart
  void showMore() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // 与视频区条带同一份清单：两处内容同源，不再各写一份 ListTile。
      final layout = resolvePlayerActions(
        host: PlayerHost.windowed,
        // 抽屉不受条带宽度约束：给足宽度让全部动作进 overflow 之外的部分也列出来
        availableWidth: 4000,
        isVertical: room.isVertical.value,
        hasQuality: room.qualites.length > 1,
        hasLine: room.playUrls.length > 1,
      );
      showActionMenu(
        title: "更多",
        // availableWidth 给足时 bar 里只剩 core 件，页级菜单要的是「条带放不下的那些」，
        // 所以这里列全集，让用户从一处就能直达。
        items: [...layout.bar, ...layout.overflow],
        onSelect: (id) => invokePlayerAction(target: room, page: controller, id: id, context: Get.context!),
      );
      return;
    }
    // 移动端：原来的底部抽屉清单原样保留（不进模型）。
    ...现有实现...
  }
```

`...现有实现...` 指的是把现在 `:1016-1132` 那段 `showModalBottomSheet` 整体挪进这个 `else` 分支，**一行不改**——它是安卓的入口。

- [ ] **Step 2: 检查 `Visibility(Platform.isAndroid)` 那一项**

现有清单里的「小窗播放」（`:1072-1083`）包在 `Visibility(visible: Platform.isAndroid)` 里；桌面分支现在由 resolver 给 `smallWindow`，安卓分支保留原样。确认两条路都只有一条入口，不要在桌面弹出两个「小窗播放」。

- [ ] **Step 3: 验证**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze
```
Expected：无 issue。手测：桌面 AppBar「更多」弹右侧抽屉，内容与视频区 `⋮` 一致且含全集；安卓仍是底部抽屉。

- [ ] **Step 4: 提交**

```bash
cd /c/dart_simple_live
git add simple_live_app/lib/modules/live_room/live_room_page.dart
git commit -m "feat(liveroom): 页级「更多」与视频区条带共用同一份动作清单

- 桌面走右侧抽屉，内容来自 resolver，删掉重复的 ListTile 清单
- 安卓保持原底部抽屉，一行不动
- 小窗入口在桌面只有一条路径，不再两处并存"
```

---

## Task 11: 全量验证与手测交接

**Files:**
- Modify: 无（只有验证与可能的修复）

- [ ] **Step 1: 分析 + 全量测试**

```bash
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat analyze && ../.fvm/flutter_sdk/bin/flutter.bat test
```
Expected：analyze 无 issue；含新增两个文件在内的全部用例通过。若失败，改到通过为止——**不许**为了绿而放宽断言。

- [ ] **Step 2: release 构建**

先确认没有实例在跑：

```bash
tasklist //FI "IMAGENAME eq slive.exe" 2>/dev/null | grep -i slive || echo "app 未运行"
cd /c/dart_simple_live/simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat build windows --release
```
Expected：构建成功。若报 `MSB3027`/`MSB3021` 且提到 `WebView2Loader.dll`，是 app 还开着锁住了文件，不是代码问题——请他关掉再构建，不要 `--force` 杀进程。

- [ ] **Step 3: 交他手测的清单（不建自动化）**

1. **音频**：开两路，默认不压低（两路同响）→ 设置里打开「非聚焦自动压低」，当场一路变轻；
   每格点音量静音/取消、悬停拖滑条、滚轮 ±5% 有百分比；总音量拖动时四路按规则跟着走。
2. **画面尺寸**：一格设「铺满」另一格保持「适应」，互不影响；退出直播间再进，恢复全局值（不落盘）。
3. **OSD 一致**：窗口化条带能截图、选台、⋮ 里有画面尺寸；全屏顶栏与底栏的动作与窗口化一一对应。
4. **小窗四条路径**：窗口→小窗→退出／窗口→全屏→退出／窗口→全屏→小窗→退出／窗口→小窗→全屏→退出，
   每条都落回窗口态且尺寸是进全屏前那个。
5. **窄窗收纳**：把窗口拖窄，条带上的控件逐个沉进 `⋮`，音量/弹幕/全屏/刷新始终在场。
6. **小窗态**：只剩退出小窗／全屏／弹幕／音量 + `⋮`，顶栏不再出现。
7. **安卓**：同一份构建装到模拟器上，全屏顶栏、竖屏、锁定、PIP 与改动前一致。

- [ ] **Step 4: 按反馈修复后补提交**

每次修复一个独立提交，标题按 `fix(player): ...` / `fix(multiplay): ...`。

---

## Self-Review（写完后对 spec 逐节核对过）

- spec §2 的六条不一致 → Task 3/4/8/9 各自覆盖：截图·选台·画面尺寸进窗口化（8/10），小窗进全屏（4/8），音量语义标注（6），清晰度/线路竖屏不再隐藏（2/8），页级动作合流（10）。
- spec §5 音频 → Task 1（纯函数）+ Task 3（设置与接线）+ Task 6（三态控件）。
- spec §6 按格画面尺寸 → Task 7。
- spec §7 几何链 → Task 4。
- spec §8 清单 → Task 2 的 `_kAllActions` + `_tierFor`，逐条对应。
- spec §9 边界 → Task 2（竖屏/无数据）、Task 4（多开拒绝小窗保留）、Task 8（`_toolbarTextStyle` 与命中测试）、Task 9（常挂约束与滑条 hover 区）。
- spec §10 测试 → Task 1/2 的测试步骤 + Task 11。
- 无 TBD/占位；每个代码步骤都有真实代码；跨任务引用的名字（`resolveTileVolume`、`PlayerActionLayout`、`VolumeTarget`、`PlayerActionBar`、`FollowPickButton`、`showActionMenu`、`invokePlayerAction`）在定义处与使用处一致。
- 有意偏离 spec 的两处已在正文写明并同步回 spec：`exit`/`title`/`lock` 不建模为动作；移动端不进模型。
