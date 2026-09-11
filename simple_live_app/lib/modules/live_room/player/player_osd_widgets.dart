import 'package:material_ui/material_ui.dart';

/// M3 shape scale：extraSmall 4 / small 8 / medium 12 / large 16。
///
/// OSD 只用这四档，与 Material 3 的形状规范对齐，
/// 不再各处硬写 `BorderRadius.circular(n)`。
abstract final class OsdShape {
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;

  /// M3 底部表单的顶部圆角：比 large 再大一档，是移动端的标准形态。
  static const double sheet = 28;

  static const BorderRadius extraSmallRadius =
      BorderRadius.all(Radius.circular(extraSmall));
  static const BorderRadius smallRadius =
      BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumRadius =
      BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeRadius =
      BorderRadius.all(Radius.circular(large));

  /// 底部表单只圆上面两个角 —— 下边缘贴着屏幕，圆角会露出缝隙。
  static const BorderRadius sheetTopRadius =
      BorderRadius.vertical(top: Radius.circular(sheet));
}

/// 布局断点：按**可用宽度**划分，而不是按平台划分（同一套组件，只换尺寸表）。
enum OsdBreakpoint { desktop, tablet, mobile }

/// 呈现形态：浮层 vs 底部表单。
///
/// 窄屏（<600dp，典型安卓竖屏）上 OSD 只能落在 16:9 的视频区里，
/// 高度往往只有 ~220dp。此时再做成「左上角一张 420dp 宽的浮层」，
/// 既浪费两侧各 12dp 的边距，又让滚动区窄到没意义；
/// 改成**贴底、通栏、顶部大圆角**的 M3 底部表单形态更合理：
/// 宽度吃满、高度吃满、且在拇指可达范围内。
enum OsdPresentment { overlay, sheet }

/// Chip 的语义色调，对应 M3 的容器 / 容器上文字色角色。
enum OsdChipTone { neutral, primary, ok, warn, error }

/// OSD 视觉令牌：全部从当前 [ColorScheme] 派生。
///
/// 这样深浅色主题、以及 App 设置里的「动态取色 / 主题色」都会自动跟随，
/// OSD 不再是写死的一套暗色常量。
///
/// 层级约定（M3 的 tonal elevation，靠色阶而非描边表达）：
/// 面板 `surfaceContainerHigh` → 指标卡 `surfaceContainerHighest` →
/// 内嵌代码块反向用 `surfaceContainerLowest` 形成凹陷。
@immutable
class OsdColors {
  const OsdColors({
    required this.panel,
    required this.tile,
    required this.field,
    required this.divider,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textLabel,
    required this.ok,
    required this.warn,
    required this.okContainer,
    required this.onOkContainer,
    required this.warnContainer,
    required this.onWarnContainer,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.primaryContainer,
    required this.onPrimaryContainer,
  });

  /// 面板底：接近不透明。
  ///
  /// OSD 浮在逐帧变化的视频画面上，半透明会让文字对比度与描边边缘随画面抖动，
  /// 观感发糊 —— M3 对浮层的推荐做法也是给足不透明度，这里留 ~4% 只作过渡。
  final Color panel;

  /// 指标卡底：比面板高一档的 tonal elevation（纯色差，不描边）。
  final Color tile;

  /// 代码块 / URL 块底：比面板低两档，形成凹陷对比。
  final Color field;

  final Color divider;
  final Color shadow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textLabel;

  /// 语义状态色（M3 的 success / warning 属于扩展角色，ColorScheme 未提供）。
  final Color ok;
  final Color warn;

  final Color okContainer;
  final Color onOkContainer;
  final Color warnContainer;
  final Color onWarnContainer;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  factory OsdColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return OsdColors(
      panel: scheme.surfaceContainerHigh.withAlpha(dark ? 0xF5 : 0xFA),
      tile: scheme.surfaceContainerHighest,
      field: scheme.surfaceContainerLowest,
      divider: scheme.outlineVariant.withAlpha(0x80),
      shadow: scheme.shadow,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textLabel: scheme.onSurfaceVariant,
      // M3 扩展角色：深色主题取 tone 80，浅色主题取 tone 30，两边都能读。
      ok: dark ? const Color(0xFF74DDAF) : const Color(0xFF0F6B4A),
      warn: dark ? const Color(0xFFEFC46D) : const Color(0xFF8A5800),
      okContainer: dark ? const Color(0xFF1F4A38) : const Color(0xFFC7EBD7),
      onOkContainer: dark ? const Color(0xFF8FE7BE) : const Color(0xFF0B5238),
      warnContainer: dark ? const Color(0xFF4A3608) : const Color(0xFFFCE3B8),
      onWarnContainer: dark ? const Color(0xFFF3CE85) : const Color(0xFF6B4400),
      errorContainer: scheme.errorContainer,
      onErrorContainer: scheme.onErrorContainer,
      primaryContainer: scheme.primaryContainer,
      onPrimaryContainer: scheme.onPrimaryContainer,
    );
  }

  Color chipBackground(OsdChipTone tone) {
    switch (tone) {
      case OsdChipTone.primary:
        return primaryContainer;
      case OsdChipTone.ok:
        return okContainer;
      case OsdChipTone.warn:
        return warnContainer;
      case OsdChipTone.error:
        return errorContainer;
      case OsdChipTone.neutral:
        return tile;
    }
  }

  Color chipForeground(OsdChipTone tone) {
    switch (tone) {
      case OsdChipTone.primary:
        return onPrimaryContainer;
      case OsdChipTone.ok:
        return onOkContainer;
      case OsdChipTone.warn:
        return onWarnContainer;
      case OsdChipTone.error:
        return onErrorContainer;
      case OsdChipTone.neutral:
        return textSecondary;
    }
  }
}

/// 文字样式：字形取自 M3 type scale（[TextTheme]），字号由 [OsdMetrics] 的响应式尺寸表覆盖。
///
/// 这样既保留「按可用空间缩放」的能力，又不会绕过 App 的字体与 M3 排版规范。
@immutable
class OsdType {
  const OsdType({
    required this.title,
    required this.groupTitle,
    required this.label,
    required this.value,
    required this.secondaryValue,
    required this.tileLabel,
    required this.tileValue,
    required this.tileUnit,
    required this.chip,
    required this.url,
  });

  final TextStyle title;
  final TextStyle groupTitle;
  final TextStyle label;
  final TextStyle value;
  final TextStyle secondaryValue;
  final TextStyle tileLabel;
  final TextStyle tileValue;
  final TextStyle tileUnit;
  final TextStyle chip;
  final TextStyle url;

  factory OsdType.of(BuildContext context, OsdMetrics m, OsdColors c) {
    final t = Theme.of(context).textTheme;
    TextStyle base(TextStyle? s) => s ?? const TextStyle();
    return OsdType(
      title: base(t.titleMedium).copyWith(
        fontSize: m.titleSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: c.textPrimary,
      ),
      groupTitle: base(t.labelMedium).copyWith(
        fontSize: m.groupTitleSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: c.textLabel,
      ),
      label: base(t.bodyMedium).copyWith(
        fontSize: m.labelSize,
        fontWeight: FontWeight.w400,
        color: c.textLabel,
      ),
      value: base(t.bodyMedium).copyWith(
        fontSize: m.valueSize,
        fontWeight: FontWeight.w500,
        color: c.textPrimary,
      ),
      secondaryValue: base(t.bodySmall).copyWith(
        fontSize: m.secondarySize,
        fontWeight: FontWeight.w400,
        color: c.textSecondary,
      ),
      tileLabel: base(t.labelSmall).copyWith(
        fontSize: m.tileLabelSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: c.textLabel,
      ),
      tileValue: base(t.headlineSmall).copyWith(
        fontSize: m.tileValueSize,
        fontWeight: FontWeight.w500,
        height: 1.15,
        color: c.textPrimary,
      ),
      tileUnit: base(t.labelSmall).copyWith(
        fontSize: m.tileLabelSize,
        fontWeight: FontWeight.w500,
        color: c.textLabel,
      ),
      chip: base(t.labelSmall).copyWith(
        fontSize: m.chipFontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      url: base(t.bodySmall).copyWith(
        fontSize: m.secondarySize,
        height: 1.45,
        color: c.textSecondary,
      ),
    );
  }
}

/// 尺寸表 + 配色 + 字体的打包，避免每个组件都重复三次查表。
@immutable
class OsdSkin {
  const OsdSkin({
    required this.metrics,
    required this.colors,
    required this.type,
  });

  final OsdMetrics metrics;
  final OsdColors colors;
  final OsdType type;

  factory OsdSkin.of(BuildContext context) {
    final metrics = OsdMetricsScope.of(context);
    final colors = OsdColors.of(context);
    return OsdSkin(
      metrics: metrics,
      colors: colors,
      type: OsdType.of(context, metrics, colors),
    );
  }
}

/// 响应式尺寸表：一套组件 + 四组尺寸（desktop / tablet / mobile / dense）。
///
/// 只改「尺寸与间距」，不改组件结构；触控尺寸（按钮）按平台而非宽度决定，
/// 避免为了塞进小屏把点击区域压到点不中。
@immutable
class OsdMetrics {
  const OsdMetrics({
    required this.breakpoint,
    required this.presentment,
    required this.touch,
    required this.dense,
    required this.minimal,
    required this.horizontalMargin,
    required this.verticalMargin,
    required this.panelMaxWidth,
    required this.panelMaxHeight,
    required this.bodyMaxHeight,
    required this.panelRadius,
    required this.contentPadding,
    required this.contentGap,
    required this.sectionGap,
    required this.insetPaddingH,
    required this.insetPaddingV,
    required this.tileColumns,
    required this.tileGap,
    required this.tilePaddingH,
    required this.tilePaddingV,
    required this.rowSpacing,
    required this.rowGap,
    required this.chipGap,
    required this.chipPaddingH,
    required this.chipVPadding,
    required this.titleSize,
    required this.groupTitleSize,
    required this.labelSize,
    required this.valueSize,
    required this.secondarySize,
    required this.tileLabelSize,
    required this.tileValueSize,
    required this.chipFontSize,
    required this.iconButtonSize,
    required this.advancedVPadding,
    required this.urlMaxLines,
    required this.headerTopPadding,
  });

  final OsdBreakpoint breakpoint;

  /// 浮层（宽屏，左上角 420dp 卡片）还是底部表单（窄屏，通栏贴底）。
  final OsdPresentment presentment;

  final bool touch;

  /// 可用高度很小（例如手机竖屏时 OSD 落在 16:9 视频区里）。
  final bool dense;

  /// 可用高度小到放不下内容时，只保留标题栏，绝不溢出。
  final bool minimal;

  final double horizontalMargin;
  final double verticalMargin;
  final double panelMaxWidth;
  final double panelMaxHeight;

  /// 滚动区上限 = 面板高度 - 头部占位（已保证不会溢出）。
  final double bodyMaxHeight;

  /// 面板圆角：浮层四角 16，底部表单只圆顶部两角 28。
  final BorderRadiusGeometry panelRadius;

  final double contentPadding;
  final double contentGap;
  final double sectionGap;

  /// 内嵌块（折叠头 / URL 块）的横向内缩。
  final double insetPaddingH;
  final double insetPaddingV;

  final int tileColumns;
  final double tileGap;
  final double tilePaddingH;
  final double tilePaddingV;

  /// 行的上下留白（半值分别加在行首行尾）。
  final double rowSpacing;

  /// 行内 Label 与 Value 之间的横向间隙。
  ///
  /// 窄屏上把这 12dp 收窄一点，能给长数值多留几个字符，少出现省略号。
  final double rowGap;

  final double chipGap;
  final double chipPaddingH;
  final double chipVPadding;

  final double titleSize;
  final double groupTitleSize;
  final double labelSize;
  final double valueSize;
  final double secondarySize;
  final double tileLabelSize;
  final double tileValueSize;
  final double chipFontSize;

  final double iconButtonSize;
  final double advancedVPadding;
  final int urlMaxLines;
  final double headerTopPadding;

  /// 是否走底部表单形态（窄屏）。
  bool get isSheet => presentment == OsdPresentment.sheet;

  /// 高度紧张时是否保留次要行（Pixel Format / Color Matrix / Layout 这类）。
  ///
  /// 竖屏手机上 OSD 只有 ~160dp 的滚动区，次要行会把真正要看的
  /// 分辨率 / 码率 / 缓冲挤出首屏，因此 dense 下直接不渲染。
  bool get showSecondaryRows => !dense;

  /// 指标卡的最小高度：由「label + 间距 + 数值」三段的字号推导，
  /// 保证同一行的卡片等高（不能用 `CrossAxisAlignment.stretch` ——
  /// 面板里高度约束无界，stretch 会把 `tight(infinity)` 传给 child 直接崩）。
  double get tileMinHeight {
    final double label = tileLabelSize * 1.3;
    final double gap = tilePaddingV * 0.3;
    final double value = tileValueSize * 1.15;
    return tilePaddingV * 2 + label + gap + value;
  }

  /// Advanced 折叠头的最小高度（ListTile 的 minTileHeight）。
  double get advancedTileMinHeight {
    final double text = secondarySize * 1.4;
    final double padded = advancedVPadding * 2 + text;
    // ListTile 在紧凑密度下的实际下限约 40，低于它会自己撑开，这里如实反映。
    return padded < 40 ? 40 : padded;
  }

  /// 依据可用约束 + 安全区 + 是否触控平台解析尺寸表。
  factory OsdMetrics.resolve({
    required BoxConstraints constraints,
    required EdgeInsets safePadding,
    required bool touch,
  }) {
    final double maxW =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 1920.0;
    final double maxH =
        constraints.maxHeight.isFinite ? constraints.maxHeight : 1080.0;

    final OsdBreakpoint breakpoint = maxW >= 900
        ? OsdBreakpoint.desktop
        : (maxW >= 600 ? OsdBreakpoint.tablet : OsdBreakpoint.mobile);

    // 窄屏走底部表单：通栏贴底，不再是一张浮在左上角的卡片。
    final OsdPresentment presentment = breakpoint == OsdBreakpoint.mobile
        ? OsdPresentment.sheet
        : OsdPresentment.overlay;

    // 表单形态贴着视频区边缘，不需要外边距；浮层形态四周各留 12。
    final double horizontalMargin =
        presentment == OsdPresentment.sheet ? 0 : 12;
    final double verticalMargin = presentment == OsdPresentment.sheet ? 0 : 12;
    final double usableHeight =
        maxH - safePadding.top - safePadding.bottom - verticalMargin * 2;
    final bool dense = usableHeight < 300;

    double panelMaxWidth;
    double contentPadding;
    double contentGap;
    double sectionGap;
    double insetPaddingH;
    double insetPaddingV;
    double tileColumns;
    double tileGap;
    double tilePaddingH;
    double tilePaddingV;
    double rowSpacing;
    double rowGap;
    double chipGap;
    double chipPaddingH;
    double chipVPadding;
    double titleSize;
    double groupTitleSize;
    double labelSize;
    double valueSize;
    double secondarySize;
    double tileLabelSize;
    double tileValueSize;
    double chipFontSize;
    double iconButtonSize;
    double advancedVPadding;
    int urlMaxLines;
    double headerTopPadding;

    if (breakpoint == OsdBreakpoint.desktop) {
      panelMaxWidth = 420;
      contentPadding = 16;
      contentGap = 14;
      sectionGap = 16;
      insetPaddingH = 10;
      insetPaddingV = 8;
      tileColumns = 2;
      tileGap = 10;
      tilePaddingH = 12;
      tilePaddingV = 10;
      rowSpacing = 9;
      rowGap = 12;
      chipGap = 6;
      chipPaddingH = 9;
      chipVPadding = 4;
      titleSize = 15.5;
      groupTitleSize = 12;
      labelSize = 12.5;
      valueSize = 13.5;
      secondarySize = 12;
      tileLabelSize = 11;
      tileValueSize = 20;
      chipFontSize = 11.5;
      iconButtonSize = 28;
      advancedVPadding = 9;
      urlMaxLines = 6;
      headerTopPadding = 14;
    } else if (breakpoint == OsdBreakpoint.tablet) {
      panelMaxWidth = 400;
      contentPadding = 14;
      contentGap = 12;
      sectionGap = 15;
      insetPaddingH = 10;
      insetPaddingV = 8;
      tileColumns = 2;
      tileGap = 9;
      tilePaddingH = 11;
      tilePaddingV = 9;
      rowSpacing = 8;
      rowGap = 11;
      chipGap = 6;
      chipPaddingH = 9;
      chipVPadding = 4;
      titleSize = 15;
      groupTitleSize = 11.5;
      labelSize = 12;
      valueSize = 13;
      secondarySize = 11.5;
      tileLabelSize = 10.5;
      tileValueSize = 19;
      chipFontSize = 11;
      iconButtonSize = touch ? 40 : 28;
      advancedVPadding = touch ? 11 : 9;
      urlMaxLines = 5;
      headerTopPadding = 12;
    } else {
      // 底部表单：宽度吃满可用区。竖屏手机上这比固定 420 多出两侧各 12dp。
      panelMaxWidth = maxW;
      contentPadding = 14;
      contentGap = 10;
      sectionGap = 14;
      insetPaddingH = 8;
      insetPaddingV = 7;
      tileColumns = maxW < 320 ? 1 : 2; // 极窄屏退化为单列
      tileGap = 8;
      tilePaddingH = 10;
      tilePaddingV = 8;
      rowSpacing = 9;
      rowGap = 10;
      chipGap = 6;
      chipPaddingH = 9;
      chipVPadding = 4;
      titleSize = 16;
      groupTitleSize = 12;
      labelSize = 12.5;
      valueSize = 13.5;
      secondarySize = 12.5;
      tileLabelSize = 11;
      tileValueSize = 20;
      chipFontSize = 11.5;
      // 触控平台放大到接近 M3 的 48dp 最小点击区（这里是 44，
      // 再大就要吃掉竖屏那点可怜的滚动高度了）。
      iconButtonSize = touch ? 44 : 30;
      advancedVPadding = touch ? 12 : 9;
      urlMaxLines = 4;
      headerTopPadding = 10;
    }

    if (dense) {
      contentPadding = 10;
      contentGap = 10;
      sectionGap = 12;
      insetPaddingH = 8;
      insetPaddingV = 6;
      tileGap = 7;
      tilePaddingH = 9;
      tilePaddingV = 7;
      rowSpacing = 7;
      rowGap = 8;
      chipGap = 5;
      chipPaddingH = 8;
      chipVPadding = 3;
      titleSize = 13;
      groupTitleSize = 11;
      labelSize = 11.5;
      valueSize = 12.5;
      secondarySize = 11;
      tileLabelSize = 10;
      tileValueSize = 17;
      chipFontSize = 11;
      // dense 也不能把触控目标压回 34：小屏恰恰是最需要点得中的场景。
      iconButtonSize = touch ? 40 : 30;
      advancedVPadding = 9;
      urlMaxLines = 3;
      headerTopPadding = 8;
      // 指标卡改「一行四个」。
      //
      // 竖屏手机上滚动区只有 ~160dp，2×2 排列光是指标卡就吃掉 100dp，
      // 下面的分组全被挤没；排成一行（每格 ~85dp 宽）只占 ~48dp。
      // 极窄屏（<340）放不下四格，退回两列。
      //
      // 只对底部表单形态生效：`dense` 只看可用高度，桌面 / 平板在矮窗口里
      // 同样会 dense，但它们的面板宽度是固定的（420 / 400），四格会把每格
      // 压到 ~95dp——既不符合这里「竖屏手机」的出发点，也破坏了宽屏的既有观感。
      if (presentment == OsdPresentment.sheet) {
        tileColumns = maxW >= 340 ? 4 : 2;
      }
    }

    final bool minimal = usableHeight < 140;
    final double panelMaxHeight = usableHeight.clamp(0.0, 620.0);

    final double titleLine = titleSize * 1.35;
    final double topLine =
        titleLine > iconButtonSize ? titleLine : iconButtonSize;
    final double headerHeight = headerTopPadding + topLine;
    final double bodyMaxHeight = minimal
        ? 0.0
        : (panelMaxHeight - headerHeight - contentGap).clamp(0.0, 520.0);

    return OsdMetrics(
      breakpoint: breakpoint,
      presentment: presentment,
      touch: touch,
      dense: dense,
      minimal: minimal,
      horizontalMargin: horizontalMargin,
      verticalMargin: verticalMargin,
      panelMaxWidth: panelMaxWidth,
      panelMaxHeight: panelMaxHeight,
      bodyMaxHeight: bodyMaxHeight,
      panelRadius: presentment == OsdPresentment.sheet
          ? OsdShape.sheetTopRadius
          : OsdShape.largeRadius,
      contentPadding: contentPadding,
      contentGap: contentGap,
      sectionGap: sectionGap,
      insetPaddingH: insetPaddingH,
      insetPaddingV: insetPaddingV,
      tileColumns: tileColumns.round(),
      tileGap: tileGap,
      tilePaddingH: tilePaddingH,
      tilePaddingV: tilePaddingV,
      rowSpacing: rowSpacing,
      rowGap: rowGap,
      chipGap: chipGap,
      chipPaddingH: chipPaddingH,
      chipVPadding: chipVPadding,
      titleSize: titleSize,
      groupTitleSize: groupTitleSize,
      labelSize: labelSize,
      valueSize: valueSize,
      secondarySize: secondarySize,
      tileLabelSize: tileLabelSize,
      tileValueSize: tileValueSize,
      chipFontSize: chipFontSize,
      iconButtonSize: iconButtonSize,
      advancedVPadding: advancedVPadding,
      urlMaxLines: urlMaxLines,
      headerTopPadding: headerTopPadding,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OsdMetrics &&
      other.breakpoint == breakpoint &&
      other.presentment == presentment &&
      other.touch == touch &&
      other.dense == dense &&
      other.panelMaxWidth == panelMaxWidth &&
      other.panelMaxHeight == panelMaxHeight;

  @override
  int get hashCode => Object.hash(
        breakpoint,
        presentment,
        touch,
        dense,
        panelMaxWidth,
        panelMaxHeight,
      );
}

/// 通过 InheritedWidget 下发尺寸表，避免每个组件都手动透传参数。
class OsdMetricsScope extends InheritedWidget {
  const OsdMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  final OsdMetrics metrics;

  static OsdMetrics of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OsdMetricsScope>();
    return scope?.metrics ?? _fallback;
  }

  static final OsdMetrics _fallback = OsdMetrics.resolve(
    constraints: const BoxConstraints(maxWidth: 1920, maxHeight: 1080),
    safePadding: EdgeInsets.zero,
    touch: false,
  );

  @override
  bool updateShouldNotify(OsdMetricsScope oldWidget) =>
      oldWidget.metrics != metrics;
}

/// 面板外壳：M3 surface 容器（tonal surface + level3 阴影 + large 圆角）。
///
/// 面板是**唯一的容器**：内部分组一律用 [OsdDivider] 与间距切分，
/// 不再嵌套同款描边卡片（框套框会让层级失效、视觉发脏）。
class OsdPanel extends StatelessWidget {
  const OsdPanel({
    super.key,
    required this.child,
    required this.maxWidth,
    required this.maxHeight,
    this.radius,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  /// 圆角：不传用 [OsdShape.largeRadius]，底部表单传 [OsdShape.sheetTopRadius]。
  final BorderRadiusGeometry? radius;

  @override
  Widget build(BuildContext context) {
    final c = OsdColors.of(context);
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        // 面板自身吞掉点击：否则点标题栏或分组间隙会穿透到下层全屏手势
        // （切换控制栏 / 双击全屏）。面板外仍可穿透。
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: radius ?? OsdShape.largeRadius,
            // M3 level3 elevation：浮层足够，不再用 M2 式的大扩散阴影。
            boxShadow: [
              BoxShadow(
                color: c.shadow.withAlpha(0x4D),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// 顶部：标题 + 关闭。
class OsdHeader extends StatelessWidget {
  const OsdHeader({super.key, required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        s.metrics.contentPadding,
        s.metrics.headerTopPadding,
        OsdShape.small,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: s.type.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            OsdIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              onTap: onClose!,
            ),
        ],
      ),
    );
  }
}

/// 统一尺寸的图标按钮（M3 [IconButton]，触控平台自动放大到可点击尺寸）。
class OsdIconButton extends StatelessWidget {
  const OsdIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final double size = s.metrics.iconButtonSize;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      // M3 的按钮状态层（悬停 / 按下 / 聚焦）由 IconButton 自己处理，
      // 不再手写 MouseRegion + AnimatedContainer 模拟悬停。
      style: IconButton.styleFrom(
        foregroundColor: s.colors.textSecondary,
        // M3 的状态层是**低透明度**叠加色（约 8%~12%）。这里原来直接给了
        // 不透明的 onSurface：悬停 / 按下会在按钮区域盖出一块实心色块，
        // 既遮图标又丢掉重构前 Colors.white.withAlpha(22) 那种轻量反馈。
        overlayColor: s.colors.textPrimary.withAlpha(0x1F),
        fixedSize: Size.square(size),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(
          borderRadius: OsdShape.smallRadius,
        ),
      ),
      icon: Icon(icon, size: size * 0.6),
    );
  }
}

/// 分组：小标题 + 内容。
///
/// 关键约定：**分组不套卡片**。面板本身就是唯一容器，分组之间靠间距与
/// [OsdDivider] 切分，避免「框套框」把 tonal 层级抹平。
class OsdGroup extends StatelessWidget {
  const OsdGroup({
    super.key,
    required this.title,
    required this.child,
    this.chips = const <OsdChip>[],
  });

  final String title;
  final Widget child;

  /// 挂在标题右侧的状态令牌（格式 / 清晰度 / 直播状态这类短值）。
  final List<OsdChip> chips;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;
    final bool hasChips = chips.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(top: s.metrics.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 标题只占 1 份、Chip 区占 3 份：窄屏上先牺牲标题宽度，
              // Chip 在自己的份额里换行。
              Flexible(
                child: Text(
                  title,
                  style: s.type.groupTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasChips) ...[
                SizedBox(width: m.chipGap),
                // 不能用 Row 平铺 Chip：清晰度名一长就会把标题挤出面板
                // （RenderFlex overflow）。Wrap 会自动折到下一行。
                Flexible(
                  flex: 3,
                  child: Wrap(
                    spacing: m.chipGap,
                    runSpacing: m.chipGap,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: chips,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: hasChips ? 8 : 6),
          child,
        ],
      ),
    );
  }
}

/// 核心指标卡：小号 Label 在上、大号数值在下，可带单位。
///
/// 这是面板里唯一的「卡片」层级，用来给最重要的四个数字做视觉锚点；
/// 底色取 `surfaceContainerHighest`（比面板高一档），不描边。
class OsdStatTile extends StatelessWidget {
  const OsdStatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.tone = OsdChipTone.neutral,
  });

  final String label;
  final String value;

  /// 数值后面的小号单位（如 `FPS` / `Mbps` / `s`）。
  final String? unit;

  /// 决定数值颜色；[OsdChipTone.neutral] 表示默认前景色。
  final OsdChipTone tone;

  Color _valueColor(OsdColors c) {
    switch (tone) {
      case OsdChipTone.ok:
        return c.ok;
      case OsdChipTone.warn:
        return c.warn;
      case OsdChipTone.error:
        return c.onErrorContainer;
      case OsdChipTone.primary:
        return c.onPrimaryContainer;
      case OsdChipTone.neutral:
        return c.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;
    final Color valueColor = _valueColor(s.colors);

    return Container(
      // minHeight 让同一行卡片等高，而不是靠 stretch（会撞上无界高度约束）。
      constraints: BoxConstraints(minHeight: m.tileMinHeight),
      padding: EdgeInsets.symmetric(
        horizontal: m.tilePaddingH,
        vertical: m.tilePaddingV,
      ),
      decoration: BoxDecoration(
        color: s.colors.tile,
        borderRadius: OsdShape.mediumRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: s.type.tileLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: m.tilePaddingV * 0.3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: s.type.tileValue.copyWith(color: valueColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!, style: s.type.tileUnit),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 指标卡网格：列数由尺寸表决定（桌面 2 列，极窄屏 1 列）。
class OsdStatTileGrid extends StatelessWidget {
  const OsdStatTileGrid({super.key, required this.tiles});

  final List<OsdStatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    final int columns = m.tileColumns;
    final rows = <Widget>[];

    for (var i = 0; i < tiles.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: m.tileGap));
        final index = i + j;
        cells.add(
          Expanded(
            child:
                index < tiles.length ? tiles[index] : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        Padding(
          padding: EdgeInsets.only(
              bottom: i + columns < tiles.length ? m.tileGap : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cells,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// 一条行式数据：Label 左、Value 右，共享一条右对齐线。
///
/// M3 表达 key-value 的标准范式（List / ListTile 的行），
/// 优于「label 上 value 下」的堆叠网格：后者行高参差、对齐线全乱。
class OsdRow extends StatelessWidget {
  const OsdRow({
    super.key,
    required this.label,
    required this.value,
    this.tone = OsdChipTone.neutral,
    this.secondary = false,
  });

  final String label;
  final String value;

  /// 数值强调色；[OsdChipTone.neutral] 表示默认前景色。
  final OsdChipTone tone;

  /// 次要信息：更小字号、更低对比度。
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;
    final Color valueColor = switch (tone) {
      OsdChipTone.ok => s.colors.ok,
      OsdChipTone.warn => s.colors.warn,
      OsdChipTone.error => s.colors.onErrorContainer,
      OsdChipTone.primary => s.colors.onPrimaryContainer,
      OsdChipTone.neutral => s.colors.textPrimary,
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.rowSpacing / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: s.type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: m.rowGap),
          // 必须用 Expanded（tight）而不是 Flexible（loose）：loose 只会把 value
          // 撑到自身文字宽度，剩余空间被丢到行尾，短值会停在「行中偏左」的位置，
          // 各行也凑不到同一条右边界；Expanded + Align 才能让 value 的盒子占满
          // 自己的份额、文字内部右对齐，从而共享面板右边缘。
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: secondary
                    ? s.type.secondaryValue
                    : s.type.value.copyWith(color: valueColor),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 行式列表：行之间插 [OsdDivider]（M3 用分隔线而不是嵌套卡片分组）。
///
/// 高度紧张（[OsdMetrics.dense]，典型是安卓竖屏）时直接不渲染次要行 ——
/// 与其让「Pixel Format / Color Matrix」占掉首屏，不如把它们让给
/// 分辨率 / 码率 / 缓冲这些真正要看的数。原本它们就在 Advanced 里有一份。
class OsdRowList extends StatelessWidget {
  const OsdRowList({super.key, required this.rows});

  final List<OsdRow> rows;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    final List<OsdRow> visible =
        m.showSecondaryRows ? rows : rows.where((r) => !r.secondary).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      if (i > 0) children.add(const OsdDivider());
      children.add(visible[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// 分隔线：取自 `outlineVariant`，1px，无缩进（M3 Divider 规范）。
class OsdDivider extends StatelessWidget {
  const OsdDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: OsdColors.of(context).divider,
    );
  }
}

/// 状态令牌：格式 / 清晰度 / 直播状态这类短值的容器（M3 Chip，8dp 圆角）。
class OsdChip extends StatelessWidget {
  const OsdChip({
    super.key,
    required this.label,
    this.tone = OsdChipTone.neutral,
  });

  final String label;
  final OsdChipTone tone;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.chipPaddingH,
        vertical: m.chipVPadding,
      ),
      decoration: BoxDecoration(
        color: s.colors.chipBackground(tone),
        borderRadius: OsdShape.smallRadius,
      ),
      child: Text(
        label,
        style: s.type.chip.copyWith(color: s.colors.chipForeground(tone)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Advanced 折叠区：默认收起，点击展开。
///
/// 用 M3 的 [ExpansionTile]（自带旋转指示箭头、状态层与强调缓动）。
/// 这里**刻意不给它加卡片底与描边** —— 折叠区在视觉上属于面板本身，
/// 只靠一条 [OsdDivider] 与上方内容切分。
class OsdAdvanced extends StatelessWidget {
  const OsdAdvanced({super.key, required this.child, this.title = 'Advanced'});

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;

    return Padding(
      padding: EdgeInsets.only(top: m.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const OsdDivider(),
          ExpansionTile(
            title: Text(
              title,
              style: s.type.groupTitle,
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 2),
            // 折叠区融入面板：透明底 + 无边框，不再制造第二层容器。
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            textColor: s.colors.textPrimary,
            collapsedTextColor: s.colors.textPrimary,
            iconColor: s.colors.textSecondary,
            collapsedIconColor: s.colors.textSecondary,
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            dense: true,
            visualDensity: VisualDensity.compact,
            minTileHeight: m.advancedTileMinHeight,
            // M3 动效 token：展开走强调减速，收起走强调加速（更短）。
            expansionAnimationStyle: const AnimationStyle(
              curve: Easing.emphasizedDecelerate,
              duration: Durations.medium2,
              reverseCurve: Easing.emphasizedAccelerate,
              reverseDuration: Durations.short4,
            ),
            children: [child],
          ),
        ],
      ),
    );
  }
}

/// Advanced 里的单条明细：Label 在上，可换行的值在下。
///
/// 这里刻意不改成行式 —— 明细值可能是「原始属性串」这类长文本，
/// 右对齐会挤成一条省略号，堆叠反而更好读。
class OsdDetailRow extends StatelessWidget {
  const OsdDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: s.type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: s.type.secondaryValue.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 长 URL 展示块：可选中、可复制，行数受尺寸表限制，绝不撑爆面板宽度。
class OsdUrlBlock extends StatelessWidget {
  const OsdUrlBlock({
    super.key,
    required this.url,
    this.label = 'Stream URL',
    this.onCopy,
  });

  final String url;
  final String label;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final s = OsdSkin.of(context);
    final m = s.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: s.type.label)),
            if (onCopy != null)
              OsdIconButton(
                icon: Icons.copy_rounded,
                tooltip: '复制链接',
                onTap: onCopy!,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.insetPaddingH,
            vertical: m.insetPaddingV,
          ),
          decoration: BoxDecoration(
            // 比面板低两档，形成「挖空」的输入框观感。
            color: s.colors.field,
            borderRadius: OsdShape.smallRadius,
          ),
          child: SelectableText(
            url,
            maxLines: m.urlMaxLines,
            style: s.type.url,
          ),
        ),
      ],
    );
  }
}
