import 'package:flutter/rendering.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_fit.dart';

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用）。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(() {
    Get.reset();
  });

  test('不传覆盖值时读全局设置', () {
    final settings = AppSettingsController.instance;
    settings.scaleMode.value = 2;
    final resolved = resolvePlayerFit();
    expect(resolved.fit, BoxFit.cover);
    expect(resolved.aspectRatio, isNull);
  });

  test('覆盖值优先于全局设置', () {
    final settings = AppSettingsController.instance;
    settings.scaleMode.value = 0;
    // 一路竖屏铺满、另一路保持适应：格传 2，全局是 0。
    final tile = resolvePlayerFit(2);
    expect(tile.fit, BoxFit.cover);
    expect(tile.aspectRatio, isNull);
    final main = resolvePlayerFit(null);
    expect(main.fit, BoxFit.contain);
    expect(main.aspectRatio, isNull);
  });

  test('锁定比例的模式给出对应 aspectRatio', () {
    final settings = AppSettingsController.instance;
    settings.scaleMode.value = 3;
    expect(resolvePlayerFit(4).aspectRatio, 4 / 3);
    expect(resolvePlayerFit(3).aspectRatio, 16 / 9);
    settings.aspectByUser.value = 2.0;
    final custom = resolvePlayerFit(5);
    expect(custom.fit, BoxFit.contain);
    expect(custom.aspectRatio, 2.0);
  });
}
