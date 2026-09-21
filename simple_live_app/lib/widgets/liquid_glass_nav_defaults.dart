// Liquid Glass 底栏的默认观感 —— **单一来源**。
//
// 这里的每个数字都同时喂给两处：
//   * floating_navigation_bar.dart —— 线上（release）实际渲染的默认样式；
//   * glass_debug_controller.dart  —— 调试页参数表的 `initial`（「重置该项」的目标）。
// 两边读同一份常量、且用同一段 build* 代码构造样式，所以「调试页预览」与
// 「线上渲染」不可能再各存一份而静默漂移 —— 想改观感就改这里，调试页自动跟上。
//
// 这些值是对着参考图在调试页（设置 → 开发者选项 → Liquid Glass 调试）里拖出来
// 固化的：比包默认更明显的磨砂 + 更读得出的选中药丸 + 一层接触阴影。

import 'package:flutter/material.dart' show Brightness, Color;
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as glass;

/// 底栏玻璃的数值默认值 + 由数值构造样式的唯一入口。
///
/// 只装数字和纯函数，不依赖任何本项目的 widget，方便调试页独立引用。
abstract final class LiquidGlassNavDefaults {
  // ── 布局 ──

  /// 胶囊内边距（药丸高度 / 胶囊高度 的主控）。
  static const double itemPadding = 6;

  // ── 胶囊本体（LiquidGlassStyle）──

  /// 胶囊染色 alpha（0-255），基底白色；包默认只有 22（0.086）。
  static const double barTintAlpha = 65;

  /// 胶囊背后内容的模糊 sigma；包默认 2。
  static const double barBlur = 9;

  /// 环境饱和度（1.0 = 不变，与包默认一致）。
  static const double barSaturation = 1;

  /// 接触阴影：模糊半径 + 浓度。包默认不画阴影。
  static const double shadowBlur = 16;
  static const double shadowOpacity = 0.16;

  // ── 折射（LiquidGlassRefraction）──

  /// 包默认 0.07 / 28 / 0.002。
  static const double distortion = 0.14;
  static const double distortionWidth = 28;
  static const double chromaticAberration = 0.005;

  // ── 选中药丸（LiquidGlassTabPillStyle）──

  /// 药丸填充色 alpha（0-255），基底色见 [pillBaseLight] / [pillBaseDark]。
  static const double pillAlpha = 110;

  /// 药丸圆角；0 = 交给包按高度自适应。
  static const double pillCornerRadius = 0;

  /// 药丸是否在标签之间滑动（关掉 = 瞬间跳）；包默认 false。
  static const bool pillAnimated = true;

  /// 药丸滑动时长（毫秒）；包默认 320 / `easeOutCubic`。
  static const double pillDurationMs = 320;

  /// 药丸基底色：浅色用从参考图取的 #AEAEB2（那枚蓝灰药丸），深色用白 ——
  /// 同一档不透明度，压在深色玻璃上才读得出「选中」。
  static const Color pillBaseLight = Color(0xFFAEAEB2);
  static const Color pillBaseDark = Color(0xFFFFFFFF);

  // ── 图标与文字（LiquidGlassTabItemStyle）──

  /// 与包默认一致（24 / 10.5 / 2）；显式写出来是为了让调试页有明确的重置目标，
  /// 也为了包哪天改默认值时本项目的观感不会跟着漂。
  static const double iconSize = 24;
  static const double labelFontSize = 10.5;
  static const double iconLabelGap = 2;

  // ── 线上渲染用的默认样式 ─────────────────────────────────

  /// 线上固化的胶囊玻璃外观。
  static final glass.LiquidGlassStyle defaultBarStyle = buildBarStyle(
    tintAlpha: barTintAlpha,
    blur: barBlur,
    saturation: barSaturation,
    shadowBlur: shadowBlur,
    shadowOpacity: shadowOpacity,
    distortion: distortion,
    distortionWidth: distortionWidth,
    chromaticAberration: chromaticAberration,
  );

  /// 线上固化的图标文字样式。
  static glass.LiquidGlassTabItemStyle defaultItemStyle({
    required Color selectedColor,
    required Color unselectedColor,
  }) =>
      buildItemStyle(
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        iconSize: iconSize,
        labelFontSize: labelFontSize,
        iconLabelGap: iconLabelGap,
      );

  /// 线上固化的选中药丸样式。
  static glass.LiquidGlassTabPillStyle defaultPillStyle(Brightness brightness) =>
      buildPillStyle(
        brightness: brightness,
        alpha: pillAlpha,
        cornerRadius: pillCornerRadius,
        animated: pillAnimated,
        durationMs: pillDurationMs,
      );

  // ── 构造：线上默认值与调试页当前值共用同一段代码 ──────────

  /// 药丸填充色：基底色跟着主题亮度走，[alpha255] 是 0-255 的不透明度。
  static Color pillColor(Brightness brightness, double alpha255) =>
      (brightness == Brightness.dark ? pillBaseDark : pillBaseLight)
          .withValues(alpha: alpha255 / 255);

  /// 胶囊本体：填充 + 模糊 + 饱和度 + 折射 + 接触阴影。
  ///
  /// 以 [glass.LiquidGlassTabBar.defaultStyle] 为底（形状留空 → 由高度自适应成
  /// 完整胶囊）。
  static glass.LiquidGlassStyle buildBarStyle({
    required double tintAlpha,
    required double blur,
    required double saturation,
    required double shadowBlur,
    required double shadowOpacity,
    required double distortion,
    required double distortionWidth,
    required double chromaticAberration,
  }) {
    const base = glass.LiquidGlassTabBar.defaultStyle;
    return base.copyWith(
      appearance: base.appearance.copyWith(
        color: const Color(0xFFFFFFFF).withValues(alpha: tintAlpha / 255),
        blur: glass.LiquidGlassBlur(sigmaX: blur, sigmaY: blur),
        saturation: saturation,
        shadow: glass.LiquidGlassShadow(
          blur: shadowBlur,
          opacity: shadowOpacity,
        ),
      ),
      refraction: glass.LiquidGlassRefraction(
        distortion: distortion,
        distortionWidth: distortionWidth,
        chromaticAberration: chromaticAberration,
      ),
    );
  }

  /// 图标与文字：颜色由调用方给（本项目用的是 `material_ui` 的 ColorScheme，
  /// 与 `flutter/material` 的同名类是**两个不同的类型**，所以这里只收 [Color]），
  /// 尺寸与间距可调。
  static glass.LiquidGlassTabItemStyle buildItemStyle({
    required Color selectedColor,
    required Color unselectedColor,
    required double iconSize,
    required double labelFontSize,
    required double iconLabelGap,
  }) =>
      glass.LiquidGlassTabItemStyle(
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        iconSize: iconSize,
        labelFontSize: labelFontSize,
        iconLabelGap: iconLabelGap,
      );

  /// 选中药丸：填充色 + 可选圆角 + 滑动参数。
  static glass.LiquidGlassTabPillStyle buildPillStyle({
    required Brightness brightness,
    required double alpha,
    required double cornerRadius,
    required bool animated,
    required double durationMs,
  }) {
    final color = pillColor(brightness, alpha);
    return glass.LiquidGlassTabPillStyle(
      animated: animated,
      animationDuration: Duration(milliseconds: durationMs.round()),
      color: color,
      // 圆角为 0 时不传 rest，交回包按高度自适应
      rest: cornerRadius <= 0
          ? null
          : glass.LiquidGlassStyle(
              shape: glass.LiquidGlassShape.roundedRectangle(
                cornerRadius: cornerRadius,
                borderWidth: 0,
              ),
              appearance: glass.LiquidGlassAppearance(color: color),
            ),
    );
  }
}
