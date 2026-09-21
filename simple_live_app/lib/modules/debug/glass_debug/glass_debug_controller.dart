import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:get/get.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as glass;
import 'package:simple_live_app/widgets/liquid_glass_nav_defaults.dart';

/// 一个可调参数的完整描述：标签、当前值、默认值、范围。
///
/// 把这四样收在一处，是为了让「单项重置」成为参数自己的行为：
/// 页面只把它渲染成「滑杆 + 重置按钮」，
/// [GlassDebugController.reset] 也只遍历它们 ——
/// 于是默认值只有一份，不会出现「加了参数却漏掉重置」。
@immutable
class GlassParam {
  const GlassParam({
    required this.label,
    required this.value,
    required this.initial,
    required this.min,
    required this.max,
    this.precision = 2,
  });

  /// 滑杆标题（带参数名，方便对照导出的代码）
  final String label;

  /// 当前值（会话级）
  final Rx<double> value;

  /// 默认值，也就是「重置该项」打回的目标
  final double initial;

  final double min;
  final double max;

  /// 显示与导出的小数位
  final int precision;

  /// 滑杆的档位数 —— 与页面上的 `Slider` 共用这一处，避免两边算得不一样。
  int get divisions => ((max - min) / 0.01).round().clamp(10, 600);

  /// 滑杆一格的大小。
  double get step => (max - min) / divisions;

  /// 是否已偏离默认值 —— 决定重置按钮是否可点。
  ///
  /// 容差取**半格**而不是精确相等：滑杆的取值是 `min + (max-min)*i/divisions`
  /// 离散化出来的，默认值往往不落在刻度上（tint 0-255 被 clamp 到 600 档，
  /// 步长 0.425，最近的刻度是 65.025 而不是 65）。精确比较会让用户把滑杆拖回
  /// 默认位置后按钮仍然亮着，而显示（precision 抹掉小数后）看起来就是 65 ——
  /// 正是那种「看着没改、按钮却可点」的困惑。半格既盖住这种量化误差，
  /// 又不会把「真调了一格」误判成没改。
  bool get isModified => (value.value - initial).abs() > step / 2 + 1e-9;

  /// 只重置这一项
  void reset() => value.value = initial;

  String get display => value.value.toStringAsFixed(precision);
}

/// Liquid Glass 调试参数（仅 Debug 模式使用）。
///
/// 对应 liquid_glass_easy 的 `LiquidGlassTabBar` 三个样式组：
///   * 胶囊本体 → [glass.LiquidGlassStyle]（形状 + 填充/模糊 + 折射）
///   * 选中药丸 → [glass.LiquidGlassTabPillStyle]
///   * 图标文字 → [glass.LiquidGlassTabItemStyle]
///
/// 默认值就是线上固化下来的那一套（[LiquidGlassNavDefaults]），不是包的出厂默认：
/// 相对包默认，这里更重地染色与磨砂、加了接触阴影、折射更强、并打开了药丸滑动。
/// 本控制器与 [FloatingNavigationBar] 读同一份常量、走同一段 `build*` 代码构造样式，
/// 所以「调试页预览」与「线上渲染」在默认值下必然一致。
///
/// 所有参数均为会话级，不持久化；调好后可用页面里的「复制参数」导出代码。
class GlassDebugController extends GetxController {
  static GlassDebugController get instance {
    if (!Get.isRegistered<GlassDebugController>()) {
      Get.put(GlassDebugController(), permanent: true);
    }
    return Get.find<GlassDebugController>();
  }

  static const bool enabled = kDebugMode;

  // ── 胶囊本体（LiquidGlassStyle）──

  /// 胶囊染色：白色，alpha 0-255
  final barTintAlpha = LiquidGlassNavDefaults.barTintAlpha.obs;

  /// 胶囊背后内容的模糊 sigma
  final barBlur = LiquidGlassNavDefaults.barBlur.obs;

  /// 环境饱和度（1.0 = 不变）
  final barSaturation = LiquidGlassNavDefaults.barSaturation.obs;

  /// 接触阴影的模糊半径与不透明度
  final shadowBlur = LiquidGlassNavDefaults.shadowBlur.obs;
  final shadowOpacity = LiquidGlassNavDefaults.shadowOpacity.obs;

  // ── 折射（LiquidGlassRefraction）──

  /// 折射强度
  final distortion = LiquidGlassNavDefaults.distortion.obs;

  /// 折射带宽，逻辑像素
  final distortionWidth = LiquidGlassNavDefaults.distortionWidth.obs;

  /// 色差
  final chromaticAberration = LiquidGlassNavDefaults.chromaticAberration.obs;

  // ── 选中药丸（LiquidGlassTabPillStyle）──

  /// 药丸填充色 alpha 0-255。基底色 #AEAEB2（深色模式取白）——
  /// 调 alpha 就能压深/放淡。
  final pillAlpha = LiquidGlassNavDefaults.pillAlpha.obs;

  /// 药丸圆角。0 = 交给包按高度自适应；>0 时显式指定圆角半径。
  final pillCornerRadius = LiquidGlassNavDefaults.pillCornerRadius.obs;

  /// 药丸是否在标签之间滑动（关掉=瞬间跳）
  final pillAnimated = LiquidGlassNavDefaults.pillAnimated.obs;

  /// 药丸滑动的时长（毫秒）。
  ///
  /// 包默认 320ms / `easeOutCubic`。本项目页面侧是
  /// 相邻切换 300ms、跨 Tab 跳切 220ms（`IndexedController`），
  /// 两者不同步时会看到"页面先到位、指示器还在走"。
  final pillDuration = LiquidGlassNavDefaults.pillDurationMs.obs;

  // ── 图标与文字（LiquidGlassTabItemStyle）──

  final iconSize = LiquidGlassNavDefaults.iconSize.obs;
  final labelFontSize = LiquidGlassNavDefaults.labelFontSize.obs;
  final iconLabelGap = LiquidGlassNavDefaults.iconLabelGap.obs;

  /// 胶囊内边距（药丸高度 / 胶囊高度 的主控）
  final itemPadding = LiquidGlassNavDefaults.itemPadding.obs;

  // ── 参数表 ──────────────────────────────────────────────
  //
  // 每组顺序 == 页面上的分组顺序。
  //
  // `initial` 与上面各 Rx 字段的初值都取自 [LiquidGlassNavDefaults]，
  // 也就是线上渲染用的那一份 —— 单一来源，不存在「调试页打回一个线上不用的值」。

  /// 胶囊本体（LiquidGlassStyle）
  late final List<GlassParam> capsuleParams = [
    // 参数字段名，便于对照导出的代码          当前值          默认值   最小  最大  小数位
    GlassParam(label: "itemPadding 内边距", value: itemPadding, initial: LiquidGlassNavDefaults.itemPadding, min: 0, max: 20, precision: 0),
    GlassParam(label: "tint 白色不透明度", value: barTintAlpha, initial: LiquidGlassNavDefaults.barTintAlpha, min: 0, max: 255, precision: 0),
    GlassParam(label: "blur 背后模糊", value: barBlur, initial: LiquidGlassNavDefaults.barBlur, min: 0, max: 20),
    GlassParam(label: "saturation 饱和度", value: barSaturation, initial: LiquidGlassNavDefaults.barSaturation, min: 0, max: 3),
    GlassParam(label: "shadowBlur 阴影模糊", value: shadowBlur, initial: LiquidGlassNavDefaults.shadowBlur, min: 0, max: 40),
    GlassParam(label: "shadowOpacity 阴影浓度", value: shadowOpacity, initial: LiquidGlassNavDefaults.shadowOpacity, min: 0, max: 1),
  ];

  /// 折射（LiquidGlassRefraction）
  late final List<GlassParam> refractionParams = [
    GlassParam(label: "distortion 折射强度", value: distortion, initial: LiquidGlassNavDefaults.distortion, min: 0, max: 0.3),
    GlassParam(label: "distortionWidth 折射带宽", value: distortionWidth, initial: LiquidGlassNavDefaults.distortionWidth, min: 0, max: 80),
    // 默认值 0.005，两位小数会显示成 0.01，所以这一项给三位
    GlassParam(label: "chromaticAberration 色差", value: chromaticAberration, initial: LiquidGlassNavDefaults.chromaticAberration, min: 0, max: 0.05, precision: 3),
  ];

  /// 选中药丸（LiquidGlassTabPillStyle）
  late final List<GlassParam> pillParams = [
    GlassParam(label: "color alpha 药丸不透明度", value: pillAlpha, initial: LiquidGlassNavDefaults.pillAlpha, min: 0, max: 255, precision: 0),
    GlassParam(label: "cornerRadius 圆角（0=自适应）", value: pillCornerRadius, initial: LiquidGlassNavDefaults.pillCornerRadius, min: 0, max: 40),
    GlassParam(label: "animationDuration 滑动时长(ms)", value: pillDuration, initial: LiquidGlassNavDefaults.pillDurationMs, min: 100, max: 600, precision: 0),
  ];

  /// 图标与文字（LiquidGlassTabItemStyle）
  late final List<GlassParam> itemParams = [
    GlassParam(label: "iconSize 图标尺寸", value: iconSize, initial: LiquidGlassNavDefaults.iconSize, min: 16, max: 32),
    GlassParam(label: "labelFontSize 字号", value: labelFontSize, initial: LiquidGlassNavDefaults.labelFontSize, min: 8, max: 16),
    GlassParam(label: "iconLabelGap 图标文字间距", value: iconLabelGap, initial: LiquidGlassNavDefaults.iconLabelGap, min: 0, max: 12),
  ];

  /// 全部可调参数（顺序与页面一致）
  late final List<GlassParam> allParams = [
    ...capsuleParams,
    ...refractionParams,
    ...pillParams,
    ...itemParams,
  ];

  /// 药丸滑动开关的默认值。
  ///
  /// 这是唯一的布尔参数，且不是滑杆，所以不放进 [GlassParam]（那里装的是 double），
  /// 单独给默认值 + 重置 + 「是否改过」三个成员，好让它和滑杆一样能单项重置。
  static const bool pillAnimatedInitial = LiquidGlassNavDefaults.pillAnimated;

  bool get pillAnimatedModified => pillAnimated.value != pillAnimatedInitial;

  void resetPillAnimated() => pillAnimated.value = pillAnimatedInitial;

  /// 预览用的选中项（调试页自身的预览胶囊）
  final previewIndex = 0.obs;

  /// 药丸填充色：基底色跟着主题亮度走（浅色 #AEAEB2 / 深色白）
  Color pillColor(Brightness brightness) =>
      LiquidGlassNavDefaults.pillColor(brightness, pillAlpha.value);

  /// 胶囊本体：填充 + 模糊 + 折射 + 接触阴影。
  ///
  /// 与线上默认样式（[LiquidGlassNavDefaults.defaultBarStyle]）走的是同一段
  /// 构造代码，只是把默认值换成当前值 —— 默认值下两者必然相等。
  glass.LiquidGlassStyle buildBarStyle() => LiquidGlassNavDefaults.buildBarStyle(
        tintAlpha: barTintAlpha.value,
        blur: barBlur.value,
        saturation: barSaturation.value,
        shadowBlur: shadowBlur.value,
        shadowOpacity: shadowOpacity.value,
        distortion: distortion.value,
        distortionWidth: distortionWidth.value,
        chromaticAberration: chromaticAberration.value,
      );

  /// 图标与文字：颜色由调用方给（本项目用的是 `material_ui` 的
  /// [ColorScheme]，与 `flutter/material` 的同名类是**两个不同的类型**，
  /// 所以这里只收 [Color]，不收 ColorScheme），尺寸与间距可调。
  glass.LiquidGlassTabItemStyle buildItemStyle({
    required Color selectedColor,
    required Color unselectedColor,
  }) =>
      LiquidGlassNavDefaults.buildItemStyle(
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        iconSize: iconSize.value,
        labelFontSize: labelFontSize.value,
        iconLabelGap: iconLabelGap.value,
      );

  /// 选中药丸：填充色 + 可选圆角 + 滑动开关
  glass.LiquidGlassTabPillStyle buildPillStyle(Brightness brightness) =>
      LiquidGlassNavDefaults.buildPillStyle(
        brightness: brightness,
        alpha: pillAlpha.value,
        cornerRadius: pillCornerRadius.value,
        animated: pillAnimated.value,
        durationMs: pillDuration.value,
      );

  /// 全部打回默认值
  void reset() {
    for (final param in allParams) {
      param.reset();
    }
    resetPillAnimated();
  }

  /// 导出可直接粘贴回 `floating_navigation_bar.dart` 的参数代码。
  ///
  /// [brightness] 只影响药丸的**基底色**（浅色 #AEAEB2 / 深色白）。早先这里把基底色
  /// 写死成 #AEAEB2，深色下调出来的 alpha 会被导成浅色的基底色，照着贴回去就和
  /// 预览不是一个东西了。
  String exportCode({required Brightness brightness}) {
    String f(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toStringAsFixed(3);
    final alpha = (pillAlpha.value / 255).toStringAsFixed(3);
    final base = brightness == Brightness.dark
        ? LiquidGlassNavDefaults.pillBaseDark
        : LiquidGlassNavDefaults.pillBaseLight;
    final rgb =
        "${(base.r * 255).round()}, ${(base.g * 255).round()}, ${(base.b * 255).round()}";
    final radius = pillCornerRadius.value;
    // 圆角 > 0 时运行时会给药丸补一层 rest（见 buildPillStyle），导出必须跟上，
    // 否则页面上调出来的圆角一贴回去就丢了。
    final restLine = radius <= 0
        ? ''
        : '    rest: glass.LiquidGlassStyle(\n'
            '      shape: glass.LiquidGlassShape.roundedRectangle('
            'cornerRadius: ${f(radius)}, borderWidth: 0),\n'
            '      appearance: glass.LiquidGlassAppearance('
            'color: Color.fromRGBO($rgb, $alpha)),\n'
            '    ),\n';
    return '''
// Liquid Glass 调试参数（悬浮胶囊底栏，照着参考图对齐观感）
FloatingNavigationBar(
  liquidGlass: true,
  liquidGlassItemPadding: ${f(itemPadding.value)},
  liquidGlassStyle: glass.LiquidGlassTabBar.defaultStyle.copyWith(
    appearance: glass.LiquidGlassTabBar.defaultStyle.appearance.copyWith(
      color: Color.fromRGBO(255, 255, 255, ${f(barTintAlpha.value / 255)}),
      blur: glass.LiquidGlassBlur(
        sigmaX: ${f(barBlur.value)},
        sigmaY: ${f(barBlur.value)},
      ),
      saturation: ${f(barSaturation.value)},
      shadow: glass.LiquidGlassShadow(
        blur: ${f(shadowBlur.value)},
        opacity: ${f(shadowOpacity.value)},
      ),
    ),
    refraction: glass.LiquidGlassRefraction(
      distortion: ${f(distortion.value)},
      distortionWidth: ${f(distortionWidth.value)},
      chromaticAberration: ${f(chromaticAberration.value)},
    ),
  ),
  liquidGlassItemStyle: glass.LiquidGlassTabItemStyle(
    selectedColor: colors.primary,
    unselectedColor: colors.onSurfaceVariant,
    iconSize: ${f(iconSize.value)},
    labelFontSize: ${f(labelFontSize.value)},
    iconLabelGap: ${f(iconLabelGap.value)},
  ),
  liquidGlassPillStyle: glass.LiquidGlassTabPillStyle(
    animated: ${pillAnimated.value},
    animationDuration: const Duration(milliseconds: ${pillDuration.value.round()}),
$restLine    color: Color.fromRGBO($rgb, $alpha),
  ),
  // ...其余参数
)''';
  }
}
