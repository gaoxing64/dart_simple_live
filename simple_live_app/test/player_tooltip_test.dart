// 播放器按钮 Tooltip 内联键帽的回归。
//
// 钉两件事：(1) 动作 id → 快捷键枚举的映射表；(2) shortcutTooltip 是否按
// 「当前绑定」画出键帽、未绑定/禁用时退回纯文案。这里只测**构造产物**（把
// shortcutTooltip 的返回值当 Tooltip 读它的 richMessage/message），不拉起整条
// 播放器链——构造 Tooltip 对象不需要 Directionality/Material 祖先；只有读键帽
// 文字时才把键帽那一小块单独 pump 一下（原因见 [_keycapText]）。
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

/// 从 [tooltip] 的 richMessage 里取出键帽文字。
///
/// **不能**用 `richMessage.toPlainText()` 读它：`WidgetSpan.toPlainText` 返回
/// 的是 U+FFFC（object replacement char），键帽那颗 `Text` 在 inline span 树里
/// 根本不占字符位——纯文本只有「label + ￼」。所以 label 归 label（走
/// `toPlainText()`），键帽单独把那颗 child 塞进最小 MaterialApp 里 pump 一次：
/// 既拿到文字，也顺手证明它是**真能渲染**的 widget，而不是个没接线的对象。
Future<String> _keycapText(Tooltip tooltip, WidgetTester tester) async {
  final cap = (tooltip.richMessage! as TextSpan)
      .children!
      .whereType<WidgetSpan>()
      .single
      .child;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: cap)));
  return tester.widget<Text>(find.byType(Text)).data!;
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
    testWidgets('动作有默认绑定 → richMessage，label + 键帽字母 F', (tester) async {
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
      expect(await _keycapText(tooltip, tester), 'F');
    });

    testWidgets('键帽跟随用户改键：改成 J 后显示 J、不显示 F', (tester) async {
      settings.shortcutOverrides.value = {
        PlayerShortcut.fullscreen:
            const ShortcutBinding(LogicalKeyboardKey.keyJ),
      };
      final tooltip = shortcutTooltip(
        label: '全屏播放',
        shortcut: PlayerShortcut.fullscreen,
        child: const Icon(Icons.fullscreen),
      ) as Tooltip;
      expect(tooltip.richMessage!.toPlainText(), contains('全屏播放'));
      expect(await _keycapText(tooltip, tester), 'J');
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

    testWidgets('带修饰键的绑定，键帽显示完整组合', (tester) async {
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
      expect(await _keycapText(tooltip, tester), 'Ctrl + F');
    });
  });
}
