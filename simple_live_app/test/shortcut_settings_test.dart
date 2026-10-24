// 「键盘控制 / 自定义键位」两个开关在**控制器层**的语义回归。
//
// 与 `player_tooltip_test.dart` 的分工：那边验证的是用户看得见的结果（键帽），
// 这里钉的是背后的规则本身——尤其「关掉自定义不会丢掉用户改过的键」这条，
// 它没有任何 UI 迹象：一旦有人把实现改成「关掉时顺手清空覆盖表」，界面照样
// 正常，用户却会永久失去自己配的键位。
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
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

  /// 关掉自定义之前先摆一份「用户动过」的覆盖表：改一个键 + 禁用一个动作。
  void seedOverrides() {
    settings.shortcutOverrides.value = {
      PlayerShortcut.fullscreen:
          const ShortcutBinding(LogicalKeyboardKey.keyJ),
      PlayerShortcut.danmakuToggle: null,
    };
  }

  group('自定义键位开关', () {
    test('关闭时全部走默认值（改过的键与「不设置」都失效）', () {
      settings.shortcutCustom.value = false;
      seedOverrides();

      final effective = settings.effectiveShortcuts;
      expect(effective[PlayerShortcut.fullscreen]?.key, LogicalKeyboardKey.keyF);
      expect(effective[PlayerShortcut.danmakuToggle]?.key, LogicalKeyboardKey.keyD);
      // 生效表必须是「每个动作都有确定的一项」，不能有关闭后消失的洞。
      expect(effective.length, kShortcutOrder.length);
    });

    test('关闭不清空覆盖表，重新打开原样回来', () {
      seedOverrides();
      final before = settings.shortcutOverrides.value;

      settings.shortcutCustom.value = false;
      settings.shortcutCustom.value = true;

      expect(settings.shortcutOverrides.value, before);
      final effective = settings.effectiveShortcuts;
      expect(effective[PlayerShortcut.fullscreen]?.key, LogicalKeyboardKey.keyJ);
      // 「不设置」也要回来：它和「没配过」是两回事。
      expect(effective[PlayerShortcut.danmakuToggle], isNull);
    });

    test('打开自定义但覆盖表为空 → 与关闭等价（都是默认键位）', () {
      settings.shortcutCustom.value = true;
      expect(settings.shortcutOverrides.value, isEmpty);
      expect(
        settings.effectiveShortcuts[PlayerShortcut.fullscreen]?.key,
        LogicalKeyboardKey.keyF,
      );
    });
  });
}
