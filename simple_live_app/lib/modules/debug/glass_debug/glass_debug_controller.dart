import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

/// Liquid Glass 调试参数（仅 Debug 模式使用）。
///
/// 所有参数均为会话级，不持久化；调好后可用页面里的"复制参数"导出代码。
class GlassDebugController extends GetxController {
  static GlassDebugController get instance {
    if (!Get.isRegistered<GlassDebugController>()) {
      Get.put(GlassDebugController(), permanent: true);
    }
    return Get.find<GlassDebugController>();
  }

  static const bool enabled = kDebugMode;

  // ── 玻璃材质（LiquidGlassSettings）──
  final glassColorAlpha = 0.0.obs; // glassColor: 白色，alpha 0-255
  final blur = 5.0.obs;
  final thickness = 20.0.obs;
  final visibility = 1.0.obs;
  final saturation = 1.5.obs;
  final whitenStrength = 0.0.obs;
  final standardOpacityMultiplier = 1.0.obs;

  // ── 光照与折射 ──
  final lightIntensity = 0.5.obs;
  final ambientStrength = 0.0.obs;
  final ambientRim = 0.0.obs;
  final fresnelStrength = 1.0.obs;
  final refractiveIndex = 1.2.obs;
  final glowIntensity = 0.75.obs;

  // 预览用的选中项（调试页自身的预览胶囊）
  final RxInt previewIndex = 0.obs;

  glass.LiquidGlassSettings buildSettings() {
    return glass.LiquidGlassSettings(
      glassColor: Color.fromRGBO(255, 255, 255, glassColorAlpha.value / 255),
      blur: blur.value,
      thickness: thickness.value,
      visibility: visibility.value,
      saturation: saturation.value,
      whitenStrength: whitenStrength.value,
      standardOpacityMultiplier: standardOpacityMultiplier.value,
      lightIntensity: lightIntensity.value,
      ambientStrength: ambientStrength.value,
      ambientRim: ambientRim.value,
      fresnelStrength: fresnelStrength.value,
      refractiveIndex: refractiveIndex.value,
      glowIntensity: glowIntensity.value,
    );
  }

  void reset() {
    glassColorAlpha.value = 0;
    blur.value = 5;
    thickness.value = 20;
    visibility.value = 1;
    saturation.value = 1.5;
    whitenStrength.value = 0;
    standardOpacityMultiplier.value = 1;
    lightIntensity.value = 0.5;
    ambientStrength.value = 0;
    ambientRim.value = 0;
    fresnelStrength.value = 1;
    refractiveIndex.value = 1.2;
    glowIntensity.value = 0.75;
  }

  /// 导出可直接粘贴进悬浮胶囊的参数代码
  String exportCode() {
    String f(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toStringAsFixed(3);
    return '''
// Liquid Glass 调试参数（悬浮胶囊背景，浅色模式可读性调优）
FloatingNavigationBar(
  liquidGlass: true,
  liquidGlassSettings: glass.LiquidGlassSettings(
    glassColor: Color.fromRGBO(255, 255, 255, ${f(glassColorAlpha.value / 255)}),
    blur: ${f(blur.value)},
    thickness: ${f(thickness.value)},
    visibility: ${f(visibility.value)},
    saturation: ${f(saturation.value)},
    whitenStrength: ${f(whitenStrength.value)},
    standardOpacityMultiplier: ${f(standardOpacityMultiplier.value)},
    lightIntensity: ${f(lightIntensity.value)},
    ambientStrength: ${f(ambientStrength.value)},
    ambientRim: ${f(ambientRim.value)},
    fresnelStrength: ${f(fresnelStrength.value)},
    refractiveIndex: ${f(refractiveIndex.value)},
    glowIntensity: ${f(glowIntensity.value)},
  ),
  // ...其余参数
)''';
  }
}
