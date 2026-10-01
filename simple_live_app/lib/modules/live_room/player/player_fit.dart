import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';

/// 「画面尺寸」设置（scaleMode）→ `Video` 的 fit 与锁定比例。
///
/// 原来内联在 `LiveRoomPage.buildMediaPlayer` 里；多开的格子必须用同一套语义，
/// 否则同一个设置在单画面与多画面下会给出不同结果。
///
/// scaleMode：0 适应 / 1 拉伸 / 2 铺满 / 3 16:9 / 4 4:3 / 5 自定义比例。
({BoxFit fit, double? aspectRatio}) resolvePlayerFit() {
  final settings = AppSettingsController.instance;
  switch (settings.scaleMode.value) {
    case 1:
      return (fit: BoxFit.fill, aspectRatio: null);
    case 2:
      return (fit: BoxFit.cover, aspectRatio: null);
    case 3:
      return (fit: BoxFit.contain, aspectRatio: 16 / 9);
    case 4:
      return (fit: BoxFit.contain, aspectRatio: 4 / 3);
    case 5:
      return (fit: BoxFit.contain, aspectRatio: settings.aspectByUser.value);
    default:
      return (fit: BoxFit.contain, aspectRatio: null);
  }
}
