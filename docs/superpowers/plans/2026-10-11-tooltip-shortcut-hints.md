# Tooltip 内联快捷键提示 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在播放器按钮的 Tooltip 文案右侧内联一个键帽（如「进入全屏 [F]」），键帽显示该动作**当前实际绑定**的键，让用户不必进设置翻找快捷键。

**Architecture:** 新增一个叶子文件 `player_tooltip.dart`，提供 `shortcutForAction(PlayerActionId)`（动作 id → 快捷键枚举，纯表）、`shortcutTooltip({label, shortcut, child})`（读 `AppSettingsController.bindingFor` 决定画「文案+键帽」还是纯「文案」）与一个私有 `_ShortcutKeyCap`。所有需要提示的按钮从「`IconButton(tooltip: 字符串)`」改成「`shortcutTooltip(..., child: IconButton(tooltip: null))`」——因为 `IconButton.tooltip` 是 `String?`，渲染不了键帽，只能用外部 `Tooltip.richMessage`。

**Tech Stack:** Flutter / `material_ui`（Material 分叉，`Tooltip.richMessage: TextSpan` 已支持）、GetX（`AppSettingsController`）、`flutter_test`。

---

## 背景：为什么必须用外部 Tooltip 包装

- `IconButton.tooltip` 是 `String?`（`material_ui` 与上游一致），只能纯文本。
- `Tooltip.richMessage` 是 `InlineSpan`，可放 `WidgetSpan` → 键帽。`_TooltipBox.build` 用 `Text.rich(richMessage, style: textStyle)` 渲染，**纯文字部分继承 Tooltip 的浅色**（黑底白字），`WidgetSpan` 里的键帽自带底色，二者不冲突。
- 一个按钮**不能同时**有 `IconButton.tooltip` 和外层 `Tooltip`（会叠两层）。所以约定：**凡走 `shortcutTooltip` 的按钮，内层 `tooltip:` 一律传 `null`**，提示由外层唯一提供。`shortcutTooltip` 内部永远返回一个 `Tooltip`（有键帽→`richMessage`，无键帽→`message`），保证移动端/未绑定动作的行为与改前逐字一致。

## 键帽显示的是「当前绑定」而非默认值

`shortcutTooltip` 读 `AppSettingsController.instance.bindingFor(shortcut)`：
- 用户把全屏改到 `J` → 键帽显示 `J`；
- 用户把某动作「不设置」（禁用）→ `bindingFor` 返回 `null` → 退回纯文案（无键帽）。

这正是需求「看 tooltip 就知道对应哪个键」的落点：它跟着用户的自定义配置走。

## 范围边界（明确不做）

- **移动端两个旧 builder**（`player_controls.dart` 的 `buildFullControls` / `buildControls`，平台门在 `playerControls:26`）**不动**——它们恒为 `Platform.isAndroid||isIOS`，无键盘场景，保持原样。
- **清晰度/线路那颗 `TextButton`**（`buildPlayerActionItem` 的 quality/line 臂，339-381）**当前根本没有 tooltip**，本次不新增（列为可选 Task 6）。
- **全屏顶栏那颗「← 退出全屏」返回键**（`player_controls.dart:334`）不挂键帽：它的语义与 `F`/`Esc` 有重叠，挂哪个都易误导，跳过。
- **音量颗的键帽只在非触屏出现**：桌面点音量=静音（对应 `M`），触屏点音量=弹滑条（静音走 `⋮` 的 `muteTile`）。所以音量臂传 `shortcut: isTouch ? null : mute`——否则触屏会显示一个「点它并不会触发」的 `M`。

## 文件结构

- 新建 `simple_live_app/lib/modules/live_room/player/player_tooltip.dart` — 映射表 + `shortcutTooltip` + `_ShortcutKeyCap`。唯一职责：把「动作」渲染成「带键帽的 Tooltip」。
- 改 `simple_live_app/lib/modules/live_room/player/player_action_bar.dart` — `buildPlayerActionItem` 的 4 个臂（danmakuToggle / smallWindow / fullscreenToggle / default）接 `shortcutTooltip`。
- 改 `simple_live_app/lib/modules/live_room/player/player_volume_action.dart` — 音量 `IconButton` 接 `shortcutTooltip`（触屏不挂）。
- 改 `simple_live_app/lib/modules/live_room/player/player_controls.dart` — `buildLockButton` 的 `Tooltip(message:)` 换成 `shortcutTooltip`。
- 新建 `simple_live_app/test/player_tooltip_test.dart` — 映射表 + `shortcutTooltip` 渲染。
- 改 `simple_live_app/test/player_action_bar_test.dart` — 追加「fullscreen 臂产出带 F 键帽的 Tooltip」。
- 改 `docs/user.md` — 记一句「按钮 tooltip 会显示当前绑定的键」。

依赖方向（不成环）：`player_tooltip` → `player_actions`（`PlayerActionId`）+ `shortcut_binding`（`PlayerShortcut`/`shortcutBindingLabel`）+ `app_settings_controller`。这三个都不 import `player_tooltip`。`player_action_bar` / `player_volume_action` / `player_controls` → `player_tooltip`。

---

## Task 1: `player_tooltip.dart`（映射表 + 渲染器 + 键帽）

**Files:**
- Create: `simple_live_app/lib/modules/live_room/player/player_tooltip.dart`
- Test: `simple_live_app/test/player_tooltip_test.dart`

- [x] **Step 1: 写失败的测试**

新建 `simple_live_app/test/player_tooltip_test.dart`：

```dart
// 播放器按钮 Tooltip 内联键帽的回归。
//
// 钉两件事：(1) 动作 id → 快捷键枚举的映射表；(2) shortcutTooltip 是否按
// 「当前绑定」画出键帽、未绑定/禁用时退回纯文案。这里只测**构造产物**（把
// shortcutTooltip 的返回值当 Tooltip 读它的 richMessage/message），不 pump、
// 不拉起整条播放器链——构造 Tooltip 对象不需要 Directionality/Material 祖先。
//
// 注意 LogicalKeyboardKey 要显式从 services 引：material_ui 只 re-export
// flutter/widgets，而 widgets 不 re-export services（本仓库 shortcut_binding_test
// 同样显式 import services 拿它）。
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_tooltip.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

void main() {
  late _FakeSettings settings;
  setUp(() {
    Get.testMode = true;
    settings = _FakeSettings();
    Get.put<AppSettingsController>(settings);
  });
  tearDown(Get.reset);

  group('shortcutForAction 映射表', () {
    test('有默认快捷键的动作各归其位', () {
      expect(shortcutForAction(PlayerActionId.refresh), PlayerShortcut.refresh);
      expect(shortcutForAction(PlayerActionId.danmakuToggle),
          PlayerShortcut.danmakuToggle);
      expect(shortcutForAction(PlayerActionId.smallWindow),
          PlayerShortcut.smallWindow);
      expect(shortcutForAction(PlayerActionId.screenshot),
          PlayerShortcut.screenshot);
      expect(shortcutForAction(PlayerActionId.pick), PlayerShortcut.pick);
      expect(shortcutForAction(PlayerActionId.fullscreenToggle),
          PlayerShortcut.fullscreen);
      expect(shortcutForAction(PlayerActionId.quality), PlayerShortcut.quality);
      // 音量颗点击=静音（桌面），故映射到 mute
      expect(shortcutForAction(PlayerActionId.volume), PlayerShortcut.mute);
    });

    test('没有快捷键的动作返回 null（弹幕设置/线路/画面尺寸/关闭格…）', () {
      for (final id in [
        PlayerActionId.danmakuSettings,
        PlayerActionId.line,
        PlayerActionId.scale,
        PlayerActionId.closeTile,
        PlayerActionId.share,
        PlayerActionId.copyUrl,
        PlayerActionId.openApp,
        PlayerActionId.debugInfo,
        PlayerActionId.autoExit,
        PlayerActionId.muteTile,
      ]) {
        expect(shortcutForAction(id), isNull, reason: '$id 不该有键帽');
      }
    });
  });

  group('shortcutTooltip 渲染', () {
    test('动作有默认绑定 → richMessage，且纯文本含键帽字母', () {
      // 默认 fullscreen=F（onInit 被跳过，overrides 为空 → 生效表回落默认）
      final tip = shortcutTooltip(
        label: '全屏播放',
        shortcut: PlayerShortcut.fullscreen,
        child: const Icon(Icons.fullscreen),
      );
      final tooltip = tip as Tooltip;
      expect(tooltip.richMessage, isNotNull);
      expect(tooltip.message, isNull);
      expect(tooltip.richMessage!.toPlainText(), contains('全屏播放'));
      expect(tooltip.richMessage!.toPlainText(), contains('F'));
    });

    test('键帽跟随用户改键：改成 J 后显示 J、不显示 F', () {
      settings.shortcutOverrides.value = {
        PlayerShortcut.fullscreen:
            const ShortcutBinding(LogicalKeyboardKey.keyJ),
      };
      final tooltip = shortcutTooltip(
        label: '全屏播放',
        shortcut: PlayerShortcut.fullscreen,
        child: const Icon(Icons.fullscreen),
      ) as Tooltip;
      expect(tooltip.richMessage!.toPlainText(), contains('J'));
      expect(tooltip.richMessage!.toPlainText(), isNot(contains('F')));
    });

    test('动作被「不设置」禁用 → 退回纯 message（无键帽）', () {
      settings.shortcutOverrides.value = {
        PlayerShortcut.fullscreen: null,
      };
      final tooltip = shortcutTooltip(
        label: '全屏播放',
        shortcut: PlayerShortcut.fullscreen,
        child: const Icon(Icons.fullscreen),
      ) as Tooltip;
      expect(tooltip.richMessage, isNull);
      expect(tooltip.message, '全屏播放');
    });

    test('shortcut 为 null → 纯 message（与改前 IconButton.tooltip 等价）', () {
      final tooltip = shortcutTooltip(
        label: '弹幕设置',
        shortcut: null,
        child: const Icon(Icons.tune),
      ) as Tooltip;
      expect(tooltip.richMessage, isNull);
      expect(tooltip.message, '弹幕设置');
    });

    test('带修饰键的绑定，键帽显示完整组合', () {
      settings.shortcutOverrides.value = {
        PlayerShortcut.fullscreen: const ShortcutBinding(
          LogicalKeyboardKey.keyF,
          ctrl: true,
        ),
      };
      final tooltip = shortcutTooltip(
        label: '全屏播放',
        shortcut: PlayerShortcut.fullscreen,
        child: const Icon(Icons.fullscreen),
      ) as Tooltip;
      expect(tooltip.richMessage!.toPlainText(), contains('Ctrl + F'));
    });
  });
}
```

- [x] **Step 2: 跑测试，确认它失败**

Run: `cd simple_live_app && ../.fvm/flutter_sdk/bin/flutter.bat test test/player_tooltip_test.dart`
（若 `.fvm` 未链到 3.47.6，用 `C:\Users\admin\scoop\persist\fvm\versions\3.47.6\bin\flutter.bat`）
Expected: 编译失败 —— `Target of URI doesn't exist: '.../player_tooltip.dart'` 与 `Undefined name 'shortcutForAction'` / `'shortcutTooltip'`。

- [x] **Step 3: 写最小实现**

新建 `simple_live_app/lib/modules/live_room/player/player_tooltip.dart`：

```dart
/// 播放器按钮 Tooltip 的「内联键帽」渲染器。
///
/// 目的：把「这个按钮对应哪个快捷键」直接印在 tooltip 上（参考三方播放器
/// 「进入全屏 [H]」那种），用户不必进设置翻快捷键表。键帽显示的是**当前生效
/// 绑定**（跟着用户改键 / 禁用走），不是写死的默认值。
///
/// 为什么用外部 Tooltip 而不是 `IconButton.tooltip`：后者是 `String?`，画不了
/// 键帽。`material_ui` 的 `Tooltip.richMessage`（`InlineSpan`）可以塞 `WidgetSpan`，
/// 且 `_TooltipBox` 用 `Text.rich(richMessage, style: textStyle)` 渲染——纯文字
/// 继承 tooltip 的浅色，键帽自带底色，互不干扰。
///
/// 约定：**凡经 [shortcutTooltip] 的按钮，内层 `tooltip:` 必须传 null**，否则
/// 会叠两层 tooltip。本函数永远返回一个 `Tooltip`（有键帽走 `richMessage`，
/// 无键帽走 `message`），所以未绑定动作的观感与改前逐字一致。
library;

import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 播放器动作 → 它对应的快捷键枚举；没有快捷键的动作返回 null。
///
/// 这是「按钮」与「快捷键」两套枚举之间**唯一**的桥。之所以放这儿而不是塞进
/// `PlayerActionId` 或 `PlayerShortcut`：两边各自独立演化（动作清单按宿主裁剪、
/// 快捷键按用户可配），硬把映射写进任一枚举都会让另一侧的改动波及自己。
///
/// 音量颗映射到 [PlayerShortcut.mute]：桌面点音量＝静音（见
/// `player_action_bar.dart` 的 volume 臂 → `VolumeActionWidget` 的 `toggleMute`）。
/// 触屏点音量是弹滑条、静音另有 `muteTile`，所以**调用方**在触屏下不传这个映射
/// （见 `player_volume_action.dart`），不在表里判平台。
PlayerShortcut? shortcutForAction(PlayerActionId id) => switch (id) {
      PlayerActionId.refresh => PlayerShortcut.refresh,
      PlayerActionId.danmakuToggle => PlayerShortcut.danmakuToggle,
      PlayerActionId.smallWindow => PlayerShortcut.smallWindow,
      PlayerActionId.screenshot => PlayerShortcut.screenshot,
      PlayerActionId.pick => PlayerShortcut.pick,
      PlayerActionId.fullscreenToggle => PlayerShortcut.fullscreen,
      PlayerActionId.quality => PlayerShortcut.quality,
      PlayerActionId.volume => PlayerShortcut.mute,
      _ => null,
    };

/// 把 [child] 包成一个带（或不带）键帽的 Tooltip。
///
/// - [shortcut] 为 null，或该动作被「不设置」禁用（`bindingFor` 返回 null）→
///   纯 [label] 文案，等价于改前的 `tooltip: label`。
/// - 否则 → 「label + 键帽」，键帽文字是 [shortcutBindingLabel]（如 `F`、`Ctrl + F`）。
///
/// [child] 必须是**没有自带 tooltip** 的按钮（内层 `tooltip:` 传 null）。
Widget shortcutTooltip({
  required String label,
  required PlayerShortcut? shortcut,
  required Widget child,
}) {
  final binding =
      shortcut == null ? null : AppSettingsController.instance.bindingFor(shortcut);
  if (binding == null) {
    return Tooltip(message: label, child: child);
  }
  return Tooltip(
    richMessage: TextSpan(
      children: [
        TextSpan(text: label),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ShortcutKeyCap(shortcutBindingLabel(binding)),
        ),
      ],
    ),
    child: child,
  );
}

/// 键帽：白底黑字的小圆角块，压在深色 tooltip 上（对齐参考图）。
///
/// 自带左边距，所以调用方不必再排间隔。颜色写死而非取主题：tooltip 的
/// `DefaultTextStyle` 是浅色（黑底白字），键帽要的是反过来的「浅底深字」才像
/// 一颗物理按键；跟随主题会让键帽和它所在的 tooltip 同色系而糊掉。
class _ShortcutKeyCap extends StatelessWidget {
  const _ShortcutKeyCap(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `flutter test test/player_tooltip_test.dart`
Expected: `All tests passed!`（映射表 2 组 + 渲染 5 条，共约 7 例）。

`Tooltip`/`TextSpan`/`WidgetSpan`/`PlaceholderAlignment` 都经 `material_ui`（re-export `flutter/widgets`）可见；`LogicalKeyboardKey` 走测试文件顶部那句 `import 'package:flutter/services.dart' show LogicalKeyboardKey;`（widgets 不 re-export services）。若报 `bindingFor`/`shortcutOverrides` 相关 undefined：确认 `AppSettingsController.instance` 已在 setUp 里 `Get.put`，且 `shortcutOverrides` 是 `Rx<Map<...>>`（用 `.value = {...}` 整体替换，不是原地改）。

- [x] **Step 5: 提交**

```bash
git add simple_live_app/lib/modules/live_room/player/player_tooltip.dart simple_live_app/test/player_tooltip_test.dart
git commit -m "feat(live_room): player_tooltip —— 动作→快捷键映射与带键帽的 Tooltip 渲染器"
```

---

## Task 2: `buildPlayerActionItem` 桌面条带 4 个臂接键帽

桌面窗口化与全屏的底栏/顶簇都流经这个函数（`playerTopClusterItems` 与 `PlayerActionBar` 都调它），改这一处即覆盖桌面全部条带按钮。

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_action_bar.dart`（import + danmakuToggle 臂 ~315-338、smallWindow 臂 ~401-415、fullscreenToggle 臂 ~416-454、default 臂 ~478-506）
- Test: `simple_live_app/test/player_action_bar_test.dart`

- [x] **Step 1: 写失败的测试**

在 `player_action_bar_test.dart` 的 `void main()` 内、现有 `setUp` 之后追加（复用文件已有的 `_FakeTile`/`_FakeSettings`）：

```dart
  testWidgets('fullscreen 臂产出的 Tooltip 带当前绑定键帽 F', (tester) async {
    final tile = _FakeTile();
    final w = buildPlayerActionItem(
      action: PlayerAction(
        id: PlayerActionId.fullscreenToggle,
        title: '全屏播放',
      ),
      host: PlayerHost.windowed,
      target: tile,
      page: tile,
      textStyle: null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNotNull,
        reason: '有默认绑定的动作应走 richMessage');
    expect(tooltip.richMessage!.toPlainText(), contains('全屏播放'));
    expect(tooltip.richMessage!.toPlainText(), contains('F'));
  });

  testWidgets('danmakuSettings 臂（无快捷键）仍是纯 message', (tester) async {
    final tile = _FakeTile();
    final w = buildPlayerActionItem(
      action: PlayerAction(
        id: PlayerActionId.danmakuSettings,
        title: '弹幕设置',
      ),
      host: PlayerHost.windowed,
      target: tile,
      page: tile,
      textStyle: null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNull);
    expect(tooltip.message, '弹幕设置');
  });
```

- [x] **Step 2: 跑测试，确认失败**

Run: `flutter test test/player_action_bar_test.dart`
Expected: FAIL —— fullscreen 臂那条 `expected tooltip.richMessage to not be null`（当前它用 `IconButton(tooltip: String)`，产出的 Tooltip 只有 `message`）。danmakuSettings 那条应已 PASS（它本就用纯 message）。

- [x] **Step 2b: 先修既有几何用例被键帽打破的 `byTooltip` 断言**

⚠️ **这是计划初稿漏掉的一步，已用探针实测确认（非推测）。**

`flutter_test` 的 `find.byTooltip(String)` 走**精确相等**比较，比的是
`RawTooltip.semanticsTooltip`，而 material_ui 把它填成
`message ?? richMessage!.toPlainText()`。关键在于 **`WidgetSpan.toPlainText()` 返回
U+FFFC（object replacement char），不是它孩子的文字**——所以一旦 fullscreen 臂改走
`richMessage`，那个字符串就变成 `'全屏播放￼'`，`byTooltip('全屏播放')` 命中数归零。

实测结果（探针跑完已删）：
```
PROBE byTooltip(plain U+FFFC) count = 1     // '全屏播放￼' 能匹配
PROBE byTooltip(exact 全屏播放) count = 0   // 精确串匹配不到 ← 会炸
PROBE byTooltip(RegExp) count = 1           // 正则能匹配
```

受影响的既有断言在 `player_action_bar_test.dart` 的「宽窗口化条带」用例里，共两处
（`弹幕设置` 那颗走 `danmakuSettings` 臂、无快捷键、仍是纯 `message`，**不受影响**）：

把这两行的 `find.byTooltip("...")` 换成正则：

```dart
    // 键帽（WidgetSpan）在 toPlainText 里是一个 U+FFFC，会让 byTooltip 的精确
    // 相等匹配落空，所以这里用正则匹配 label 子串。
    expect(
      tester.getRect(find.byTooltip(RegExp('全屏播放'))).right,
      moreOrLessEquals(barRect.right, epsilon: 0.5),
      reason: '右簇必须贴到条带右端，余量留在左右簇之间',
    );
    expect(
      tester.getRect(find.byTooltip(RegExp('刷新'))).left,
      moreOrLessEquals(barRect.left, epsilon: 0.5),
      reason: '左簇贴左端',
    );
```

> 为什么改测试而不是绕开：tooltip 的文案**确实**变了（多了键帽），断言跟着改用子串匹配
> 是如实反映，不是把测试改松——`RegExp('全屏播放')` 仍不会误匹配「退出全屏」
> （不含「全屏播放」四字）。若嫌 `getRect` 语义更该落在按钮本体上，也可改成
> `find.byType(IconButton)` 配合 `at` 索引，但那会把「哪颗是全屏颗」这个断言意图
> 弄丢，所以默认用正则。
>
> Task 3 的音量颗同理：`player_volume_action_test.dart` 里若有 `byTooltip('音量')`
> 一类精确断言需一并改正则（写 Task 3 时先 grep 确认，桌面臂会挂 M 键帽）。

- [x] **Step 3: 加 import**

在 `player_action_bar.dart` 的 import 区（`player_actions.dart` 那行附近）加两行——`player_tooltip.dart` 提供 `shortcutTooltip`/`shortcutForAction`，`shortcut_binding.dart` 提供下面各臂直接引用的 `PlayerShortcut` 枚举（Dart import 不传递，本文件没引过它，必须补）：

```dart
import 'package:simple_live_app/modules/live_room/player/player_tooltip.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
```

- [x] **Step 4: 改 danmakuToggle 臂**

把 `buildPlayerActionItem` 里 `case PlayerActionId.danmakuToggle:` 分支（当前 315-338）的 `return Obx(() => IconButton(tooltip: ..., onPressed: ...))` 改成用 `shortcutTooltip` 包、内层 `tooltip: null`：

```dart
    case PlayerActionId.danmakuToggle:
      // 开／关两个 asset 图标，是「状态」而不是「动作名」，所以不能收进 ⋮ 用通用图标。
      return Obx(
        () => shortcutTooltip(
          label: target.showDanmakuState.value ? '关闭弹幕' : '开启弹幕',
          shortcut: PlayerShortcut.danmakuToggle,
          child: IconButton(
            tooltip: null,
            iconSize: iconSize,
            style: buttonStyle,
            icon: ImageIcon(
              AssetImage(
                target.showDanmakuState.value
                    ? 'assets/icons/icon_danmaku_close.png'
                    : 'assets/icons/icon_danmaku_open.png',
              ),
              size: iconSize,
              color: Colors.white,
            ),
            onPressed: () => invokePlayerAction(
              host: host,
              target: target,
              page: page,
              id: action.id,
            ),
          ),
        ),
      );
```

（`PlayerShortcut` 枚举由 Step 3 补的 `shortcut_binding.dart` import 提供。）

- [x] **Step 5: 改 smallWindow 臂**

`case PlayerActionId.smallWindow:`（当前 401-415）改为：

```dart
    case PlayerActionId.smallWindow:
      return Obx(
        () => shortcutTooltip(
          label: page.smallWindowState.value ? '退出小窗' : action.title,
          shortcut: PlayerShortcut.smallWindow,
          child: IconButton(
            tooltip: null,
            iconSize: iconSize,
            style: buttonStyle,
            icon: const Icon(Icons.picture_in_picture, color: Colors.white),
            onPressed: () => invokePlayerAction(
              host: host,
              target: target,
              page: page,
              id: action.id,
            ),
          ),
        ),
      );
```

- [x] **Step 6: 改 fullscreenToggle 臂**

`case PlayerActionId.fullscreenToggle:`（当前 416-454）里，最内层那个 `return IconButton(tooltip: showExit ? '退出全屏' : '全屏播放', ...)` 改成外层包 `shortcutTooltip`。保留上面所有注释与 `pip/full/showExit/iconData` 计算，只替换 return：

```dart
          return shortcutTooltip(
            label: showExit ? '退出全屏' : '全屏播放',
            shortcut: PlayerShortcut.fullscreen,
            child: IconButton(
              tooltip: null,
              iconSize: iconSize,
              style: buttonStyle,
              icon: Icon(iconData, color: Colors.white),
              onPressed: () {
                onInteract?.call();
                if (pip) {
                  page.enterFullScreen();
                } else {
                  invokePlayerAction(
                    host: host,
                    target: target,
                    page: page,
                    id: action.id,
                  );
                }
              },
            ),
          );
```

- [x] **Step 7: 改 default 臂**

`default:`（当前 478-506）覆盖 refresh / pick / screenshot / line / scale / share / copyUrl / openApp / debugInfo / autoExit。用 `shortcutForAction(action.id)` 决定有无键帽；无快捷键的动作 `bindingFor` 为 null → 纯 message，与改前一致：

```dart
    default:
      return shortcutTooltip(
        label: action.title,
        shortcut: shortcutForAction(action.id),
        child: IconButton(
          tooltip: null,
          iconSize: iconSize,
          style: buttonStyle,
          // 刷新颗与全屏颗同理：桌面条带回到项目图标族 Remix.refresh_line（Task 8
          // 接线时漂成 Icons.refresh，作者未认可）；tile 宿主维持 Material 表。
          // 换台颗同理回到改造前顶栏那颗 `Remix.play_list_2_line`——作者要求右上这一簇
          // 与改造前一致，图标也算一致的一部分。
          icon: Icon(
            host == PlayerHost.tile
                ? playerActionIcon(action.id)
                : switch (action.id) {
                    PlayerActionId.refresh => Remix.refresh_line,
                    PlayerActionId.pick => Remix.play_list_2_line,
                    _ => playerActionIcon(action.id),
                  },
            color: Colors.white,
          ),
          onPressed: () {
            onInteract?.call();
            invokePlayerAction(
              host: host,
              target: target,
              page: page,
              id: action.id,
            );
          },
        ),
      );
```

`closeTile`（393-400）与 `danmakuSettings`（455-477）两臂**不动**：它们无快捷键，保留原 `IconButton(tooltip: action.title)` 即可（等价于 `shortcutTooltip(shortcut: null)`）。

- [x] **Step 8: 跑测试，确认通过 + 无溢出回归**

Run: `flutter test test/player_action_bar_test.dart`
Expected: `All tests passed!`——含新加的 2 条，且原有的「格子最小宽度不溢出」两条仍过（`Tooltip` 只包在按钮外、不参与条带 Row 的宽度测量，不会引入溢出）。

- [x] **Step 9: 提交**

```bash
git add simple_live_app/lib/modules/live_room/player/player_action_bar.dart simple_live_app/test/player_action_bar_test.dart
git commit -m "feat(live_room): 桌面播放器条带按钮 tooltip 内联当前快捷键键帽"
```

---

## Task 3: 音量颗接键帽（触屏不挂）

音量颗在 `player_volume_action.dart` 内部，且**桌面/触屏语义不同**：桌面点=静音（`M`），触屏点=弹滑条（静音走 `⋮`）。所以只在非触屏传 `mute` 映射。

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_volume_action.dart`（import + 音量 `IconButton` ~405-425）
- Test: `simple_live_app/test/player_volume_action_test.dart`

- [x] **Step 1: 写失败的测试**

在 `player_volume_action_test.dart` 的 `main()` 内、既有 `setUp`/`tearDown` **之后**追加。该文件顶部的 `setUp` 已经 `Get.put<AppSettingsController>(_FakeSettings())`（其 `onInit` 被空掉，`shortcutOverrides` 保持空 → 生效表回落默认，`mute`＝`M`），所以**不要**在 testWidgets 里再 put 一次；`VolumeActionWidget.style` 是**必填非空** `ButtonStyle`，传 `const ButtonStyle()`：

```dart
  testWidgets('桌面音量颗 tooltip 带静音键帽 M', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
              isTouch: false,
            ),
          ),
        ),
      ),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNotNull);
    // 键帽是 WidgetSpan：toPlainText() 只给 U+FFFC，读不到它的文字，必须把
    // WidgetSpan 的 child 单独 pump 出来断言（同 player_tooltip_test 的 _keycapText）。
    final keycap = (tooltip.richMessage! as TextSpan)
        .children!
        .whereType<WidgetSpan>()
        .single
        .child;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: keycap)));
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('触屏音量颗不挂静音键帽（点它是弹滑条，不是静音）', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
              isTouch: true,
            ),
          ),
        ),
      ),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNull);
    expect(tooltip.message, '音量');
  });
```

> 该文件已 import `Tooltip`（经 `material_ui`）、`VolumeActionWidget`/`VolumeTarget`、`_FakeTile`。若 `Tooltip` 未被 import 到，补 `import 'package:material_ui/material_ui.dart';`（多半已有）。

- [x] **Step 2: 跑测试，确认失败**

Run: `flutter test test/player_volume_action_test.dart`
Expected: 桌面那条 FAIL（当前音量 `IconButton` 用 `tooltip:` 字符串，产出纯 `message`，`richMessage` 为 null）。

- [x] **Step 3: 加 import**

`player_volume_action.dart` import 区加两行（`shortcut_binding.dart` 提供下面 `PlayerShortcut.mute`，本文件此前没引过它）：

```dart
import 'package:simple_live_app/modules/live_room/player/player_tooltip.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
```

- [x] **Step 4: 改音量 IconButton**

把 `build` 里 `child: Obx(() { ... return IconButton(tooltip: ..., onPressed: ...); })`（当前 405-425）改成外层 `shortcutTooltip`、内层 `tooltip: null`，`shortcut` 按 `isTouch` 决定：

```dart
        child: Obx(() {
          final muted = widget.target.muted;
          return shortcutTooltip(
            label: widget.isTouch
                ? '音量'
                : muted
                ? '取消静音（悬停可调音量）'
                : '静音（悬停可调音量）',
            // 触屏点音量颗是弹滑条、不是静音（静音在 ⋮ 的 muteTile），
            // 所以只有非触屏才挂 M 键帽，否则提示的是「点它并不会做」的动作。
            shortcut: widget.isTouch ? null : PlayerShortcut.mute,
            child: IconButton(
              tooltip: null,
              style: widget.style,
              iconSize: widget.iconSize,
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
              onPressed: () {
                widget.onInteract?.call();
                if (widget.isTouch) {
                  _toggleByTouch();
                  return;
                }
                widget.target.toggleMute();
              },
            ),
          );
        }),
```

- [x] **Step 5: 跑测试，确认通过**

Run: `flutter test test/player_volume_action_test.dart`
Expected: `All tests passed!`（含新 2 条与原有命中测试回归）。

- [x] **Step 6: 提交**

```bash
git add simple_live_app/lib/modules/live_room/player/player_volume_action.dart simple_live_app/test/player_volume_action_test.dart
git commit -m "feat(live_room): 桌面音量颗 tooltip 内联静音键帽（触屏不挂）"
```

---

## Task 4: 锁定按钮接键帽

`buildLockButton`（`player_controls.dart:825`）当前已是外部 `Tooltip(message: ...)`，直接换成 `shortcutTooltip`。它被桌面全屏（430/442）与移动全屏（783/793）共用——移动全屏同样有键盘场景（外接键盘），显示 `L` 无害且正确，故不额外分平台。

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_controls.dart`（import + `buildLockButton` 825-853）

- [x] **Step 1: 加 import**

`player_controls.dart` import 区加两行（本文件已 import `flutter/services.dart`，但没引 `shortcut_binding.dart`，`PlayerShortcut.lockControls` 需要它）：

```dart
import 'package:simple_live_app/modules/live_room/player/player_tooltip.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
```

- [x] **Step 2: 改 buildLockButton**

把 `buildLockButton`（当前 825-853）里的 `Tooltip(message: ..., child: InkWell(...))` 换成 `shortcutTooltip(...)`：

```dart
Widget buildLockButton(LiveRoomController controller) {
  return Center(
    child: shortcutTooltip(
      label: controller.lockControlsState.value ? '解锁' : '锁定',
      shortcut: PlayerShortcut.lockControls,
      child: InkWell(
        onTap: () {
          controller.setLockState();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: AppStyle.radius8,
          ),
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              controller.lockControlsState.value
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}
```

（`PlayerShortcut` 枚举由 Step 1 补的 `shortcut_binding.dart` import 提供。）

> ⚠️ `buildLockButton` 是**桌面全屏（430/442）与移动全屏（783/793）共用**的函数，
> 改它会让移动端全屏的锁定颗也显示 `L` 键帽。这与「移动端不进这套模型」不冲突：
> 那条规则管的是动作清单 resolver（`resolvePlayerActions`），不是 tooltip；而
> `L` 快捷键在外接键盘的移动端同样生效，提示它是对的。作者若要移动端**不**显示
> 键帽，改法是给 `buildLockButton` 加一个 `bool showKeycap` 参数、移动调用点传
> false——但默认按共用处理（键帽跟着真实可用的快捷键走）。

- [x] **Step 3: 编译校验**

Run: `flutter analyze lib/modules/live_room/player/player_controls.dart`
Expected: `No issues found!`

- [x] **Step 4: 提交**

```bash
git add simple_live_app/lib/modules/live_room/player/player_controls.dart
git commit -m "feat(live_room): 锁定按钮 tooltip 内联 L 键帽"
```

---

## Task 5（可选）: 清晰度那颗补一个带键帽的 tooltip

清晰度/线路那颗 `TextButton`（`buildPlayerActionItem` 的 quality/line 臂，339-381）**当前没有 tooltip**。`Q` 快捷键是绑到清晰度的，补一个「清晰度 [Q]」能提升可发现性；但它是**新增**行为（改前这颗无 tooltip），且那颗按钮的可见文字是当前清晰度名（如「1080P」），加 tooltip 不影响布局。默认**不做**，仅当作者点头时执行。

**Files:**
- Modify: `simple_live_app/lib/modules/live_room/player/player_action_bar.dart`（quality/line 臂 339-381）

- [ ] **Step 1: 只给 quality 补 tooltip**

在 quality/line 臂里，`return Obx(() { ... return TextButton(...); })` 外层，仅当 `action.id == PlayerActionId.quality` 时包 `shortcutTooltip`：

```dart
    case PlayerActionId.quality:
    case PlayerActionId.line:
      return Obx(
        () {
          final labelFontSize = iconSize > 20 ? 15.0 : 13.0;
          final button = TextButton(
            style: TextButton.styleFrom(
              textStyle: textStyle,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            onPressed: () {
              onInteract?.call();
              invokePlayerAction(
                host: host,
                target: target,
                page: page,
                id: action.id,
              );
            },
            child: Text(
              action.id == PlayerActionId.quality
                  ? target.currentQualityInfo.value
                  : target.currentLineInfo.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (textStyle ?? const TextStyle()).copyWith(
                color: Colors.white,
                fontSize: labelFontSize,
              ),
            ),
          );
          // 清晰度有 Q 快捷键，补一个「清晰度 [Q]」tooltip；线路没有单键
          // （←/→ 是切线路不是「打开线路面板」），故 line 保持无 tooltip。
          if (action.id != PlayerActionId.quality) {
            return button;
          }
          return shortcutTooltip(
            label: '清晰度',
            shortcut: PlayerShortcut.quality,
            child: button,
          );
        },
      );
```

- [ ] **Step 2: 校验 + 溢出回归**

Run: `flutter test test/player_action_bar_test.dart`
Expected: 全过（`Tooltip` 不参与 Row 宽度测量，最小格宽那条不回归）。

- [ ] **Step 3: 提交**

```bash
git add simple_live_app/lib/modules/live_room/player/player_action_bar.dart
git commit -m "feat(live_room): 清晰度按钮补「清晰度 [Q]」tooltip"
```

---

## Task 6: 文档 + 全量校验

**Files:**
- Modify: `docs/user.md`

- [x] **Step 1: 在「键盘快捷键」小节末尾补一句**

在 `docs/user.md` 的「#### 中文输入法下按不动怎么办」段落**之前**（即「同一页顶部的『启用键盘快捷键』可整体关闭。」之后）加：

```markdown

播放器条带上的按钮，鼠标悬停时的 tooltip 会顺带显示它当前绑定的键（如
「全屏播放 F」）；改了键位后 tooltip 里的键也跟着变。没有对应快捷键的按钮
只显示文字、不显示键帽。
```

- [x] **Step 2: 全量 analyze**

Run: `flutter analyze`
Expected: 与基线**同数量** issue（本仓库基线为既有第三方 `rust_builder` 报错 + 若干 `avoid_print`/test 桩 info；本次新增文件应贡献 0 条）。逐字对比数量，不新增。

- [x] **Step 3: 全量 test**

Run: `flutter test`
Expected: 失败文件集合与基线**逐字节相同**（既有 `MissingPluginException`/`FakeSettings.onInit` 环境性失败）；`player_tooltip_test`、`player_action_bar_test`、`player_volume_action_test`、`shortcut_binding_test`、`player_shortcuts_test` 全过。

- [x] **Step 4: 提交文档**

```bash
git add docs/user.md
git commit -m "docs: 说明按钮 tooltip 内联当前快捷键"
```

- [x] **Step 5: 人工验收（必须，无法自动化）**

`flutter run -d windows`，进直播间：
1. 悬停底栏「全屏」→ tooltip 显示「全屏播放」+ 白底键帽 `F`；
2. 去设置把全屏改到 `J` → 回直播间，悬停那颗 → 键帽变 `J`；
3. 把某动作「不设置」→ 悬停那颗 → 只有文字、无键帽；
4. 弹幕颗悬停 → 「开启弹幕 D」/「关闭弹幕 D」，随开/关切换文字但键帽恒 `D`；
5. 音量颗（桌面）→ 「静音（悬停可调音量） M」；
6. 锁定颗（全屏）→ 「锁定 L」；
7. 触屏/移动包（若有条件）→ 音量颗 tooltip 只有「音量」无 `M`。

---

## Self-Review

**1. Spec coverage：** 需求＝「tooltip 旁边放快捷键、跟着自定义配置走、不影响原使用习惯」。
- 「放键帽」→ Task 1 渲染器 + Task 2/3/4 接线。
- 「跟着配置走」→ `shortcutTooltip` 读 `bindingFor`（Task 1，含改键/禁用测试）。
- 「不影响原习惯」→ 无快捷键动作走纯 `message`（与改前逐字一致，Task 1/2 测试钉住）；移动端旧 builder 不动（范围边界节）；音量触屏不挂（Task 3）。
- 覆盖到的动作：全屏/弹幕/小窗/截图/刷新/换台/清晰度/静音/锁定（Task 2/3/4 + 映射表）。线路/画面尺寸/分享等无快捷键 → 无键帽，符合预期。

**2. Placeholder scan：** 无 TBD/TODO；每个改代码的 step 都给了完整 before/after 代码块；测试给了可运行断言与预期。三处易错点已按真实签名钉死：(a) `VolumeActionWidget.style` 必填非空 → 测试传 `const ButtonStyle()`；(b) `LogicalKeyboardKey` 不能经 `material_ui` 拿到（widgets 不 re-export services）→ 测试文件显式 import services；(c) 各接线文件此前都没 import `shortcut_binding.dart`，而改后的臂直接写 `PlayerShortcut.*` → Task 2/3/4 的 import step 都补了它（Dart import 不传递）。

**3. Type consistency：**
- `shortcutTooltip({required String label, required PlayerShortcut? shortcut, required Widget child})` 在 Task 1 定义，Task 2/3/4/5 调用签名一致（label/shortcut/child）。
- `shortcutForAction(PlayerActionId) → PlayerShortcut?` 定义于 Task 1，Task 2 default 臂与测试引用一致。
- `_ShortcutKeyCap(String)` 私有，仅 Task 1 内部用。
- `PlayerShortcut.{fullscreen,danmakuToggle,smallWindow,screenshot,refresh,pick,quality,mute,lockControls}` 均为 `shortcut_binding.dart` 既有枚举值（已核对），无新造名字。
- `bindingFor`/`shortcutOverrides`/`ShortcutBinding`/`shortcutBindingLabel` 均为既有 API（前几轮已建）。
