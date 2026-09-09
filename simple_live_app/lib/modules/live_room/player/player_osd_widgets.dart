import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// OSD 面板是否启用背景模糊（Acrylic）。
///
/// 默认关闭：面板覆盖在视频上，而视频画面每帧都在变化，BackdropFilter 会逐帧重算模糊，
/// 在 Windows / 高 DPI 下开销明显。需要更强玻璃感时把这里改成 true 即可。
const bool kOsdEnableBlur = false;

/// 布局断点：按**可用宽度**划分，而不是按平台划分（同一套组件，只换尺寸表）。
enum OsdBreakpoint { desktop, tablet, mobile }

/// 颜色 / 圆角等与尺寸无关的视觉常量。
class OsdStyle {
  const OsdStyle._();

  static const Color panelTop = Color(0xF21B1E23);
  static const Color panelBottom = Color(0xF20F1114);
  static const Color border = Color(0x14FFFFFF); // ≈8% 白
  static const Color cardFill = Color(0x0AFFFFFF); // ≈4% 白

  static const Color textPrimary = Color(0xFFF3F5F8);
  static const Color textSecondary = Color(0x8FFFFFFF); // ≈56% 白
  static const Color textLabel = Color(0x73FFFFFF); // ≈45% 白

  static const Color ok = Color(0xFF63D6A5);
  static const Color warn = Color(0xFFE6B45C);

  static const double radius = 12;
}

/// 响应式尺寸表：一套组件 + 四组尺寸（desktop / tablet / mobile / dense）。
///
/// 只改「尺寸与间距」，不改组件结构；触控尺寸（按钮、页签）按平台而非宽度决定，
/// 避免为了塞进小屏把点击区域压到点不中。
@immutable
class OsdMetrics {
  const OsdMetrics({
    required this.breakpoint,
    required this.touch,
    required this.dense,
    required this.minimal,
    required this.inlineHeader,
    required this.horizontalMargin,
    required this.verticalMargin,
    required this.panelMaxWidth,
    required this.panelMaxHeight,
    required this.bodyMaxHeight,
    required this.contentPadding,
    required this.contentGap,
    required this.sectionGap,
    required this.cardPaddingH,
    required this.cardPaddingV,
    required this.gridGap,
    required this.rowSpacing,
    required this.columns,
    required this.titleSize,
    required this.sectionTitleSize,
    required this.labelSize,
    required this.valueSize,
    required this.secondarySize,
    required this.segmentSize,
    required this.iconButtonSize,
    required this.segmentVPadding,
    required this.advancedVPadding,
    required this.urlMaxLines,
    required this.headerTopPadding,
    required this.tabsMarginTop,
  });

  final OsdBreakpoint breakpoint;
  final bool touch;

  /// 可用高度很小（例如手机竖屏时 OSD 落在 16:9 视频区里）。
  final bool dense;

  /// 可用高度小到放不下页签与内容时，只保留标题栏，绝不溢出。
  final bool minimal;

  /// dense 下把关闭按钮并入页签行，省掉一整行标题。
  final bool inlineHeader;

  final double horizontalMargin;
  final double verticalMargin;
  final double panelMaxWidth;
  final double panelMaxHeight;

  /// 滚动区上限 = 面板高度 - 头部/页签占位（已保证不会溢出）。
  final double bodyMaxHeight;

  final double contentPadding;
  final double contentGap;
  final double sectionGap;
  final double cardPaddingH;
  final double cardPaddingV;
  final double gridGap;
  final double rowSpacing;
  final int columns;

  final double titleSize;
  final double sectionTitleSize;
  final double labelSize;
  final double valueSize;
  final double secondarySize;
  final double segmentSize;

  final double iconButtonSize;
  final double segmentVPadding;
  final double advancedVPadding;
  final int urlMaxLines;
  final double headerTopPadding;
  final double tabsMarginTop;

  /// 依据可用约束 + 安全区 + 是否触控平台解析尺寸表。
  factory OsdMetrics.resolve({
    required BoxConstraints constraints,
    required EdgeInsets safePadding,
    required bool touch,
  }) {
    final double maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 1920.0;
    final double maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 1080.0;

    final OsdBreakpoint breakpoint = maxW >= 900
        ? OsdBreakpoint.desktop
        : (maxW >= 600 ? OsdBreakpoint.tablet : OsdBreakpoint.mobile);

    const double horizontalMargin = 12;
    const double verticalMargin = 12;
    final double usableHeight =
        maxH - safePadding.top - safePadding.bottom - verticalMargin * 2;
    final bool dense = usableHeight < 300;

    double panelMaxWidth;
    double contentPadding;
    double contentGap;
    double sectionGap;
    double cardPaddingH;
    double cardPaddingV;
    double gridGap;
    double rowSpacing;
    int columns;
    double titleSize;
    double sectionTitleSize;
    double labelSize;
    double valueSize;
    double secondarySize;
    double segmentSize;
    double iconButtonSize;
    double segmentVPadding;
    double advancedVPadding;
    int urlMaxLines;
    double headerTopPadding;
    double tabsMarginTop;

    if (breakpoint == OsdBreakpoint.desktop) {
      // 与重构前的 Windows 横屏视觉完全一致
      panelMaxWidth = 420;
      contentPadding = 16;
      contentGap = 14;
      sectionGap = 18;
      cardPaddingH = 12;
      cardPaddingV = 10;
      gridGap = 12;
      rowSpacing = 10;
      columns = 2;
      titleSize = 15.5;
      sectionTitleSize = 10.5;
      labelSize = 10.5;
      valueSize = 14;
      secondarySize = 12;
      segmentSize = 11.5;
      iconButtonSize = 28;
      segmentVPadding = 6;
      advancedVPadding = 9;
      urlMaxLines = 6;
      headerTopPadding = 14;
      tabsMarginTop = 12;
    } else if (breakpoint == OsdBreakpoint.tablet) {
      panelMaxWidth = 400;
      contentPadding = 14;
      contentGap = 12;
      sectionGap = 16;
      cardPaddingH = 12;
      cardPaddingV = 9;
      gridGap = 10;
      rowSpacing = 8;
      columns = 2;
      titleSize = 15;
      sectionTitleSize = 10;
      labelSize = 10;
      valueSize = 13.5;
      secondarySize = 11.5;
      segmentSize = 11;
      iconButtonSize = touch ? 38 : 28;
      segmentVPadding = touch ? 8 : 6;
      advancedVPadding = touch ? 11 : 9;
      urlMaxLines = 5;
      headerTopPadding = 12;
      tabsMarginTop = 10;
    } else {
      panelMaxWidth = 420;
      contentPadding = 12;
      contentGap = 10;
      sectionGap = 14;
      cardPaddingH = 10;
      cardPaddingV = 8;
      gridGap = 10;
      rowSpacing = 8;
      columns = maxW < 320 ? 1 : 2; // 极窄屏退化为单列
      titleSize = 16;
      sectionTitleSize = 11;
      labelSize = 11;
      valueSize = 14;
      secondarySize = 12.5;
      segmentSize = 10.5;
      iconButtonSize = touch ? 40 : 30;
      segmentVPadding = touch ? 8 : 6;
      advancedVPadding = touch ? 12 : 9;
      urlMaxLines = 4;
      headerTopPadding = 10;
      tabsMarginTop = 8;
    }

    if (dense) {
      contentPadding = 10;
      contentGap = 10;
      sectionGap = 12;
      cardPaddingH = 10;
      cardPaddingV = 7;
      gridGap = 8;
      rowSpacing = 6;
      titleSize = 13;
      sectionTitleSize = 9.5;
      labelSize = 9.5;
      valueSize = 12.5;
      secondarySize = 11;
      segmentSize = 10;
      iconButtonSize = 34;
      segmentVPadding = 5;
      advancedVPadding = 9;
      urlMaxLines = 3;
      headerTopPadding = 8;
      tabsMarginTop = 8;
    }

    final bool minimal = usableHeight < 140;
    final bool inlineHeader = dense && !minimal;
    final double panelMaxHeight = usableHeight.clamp(0.0, 620.0);

    final double titleLine = titleSize * 1.35;
    final double headerHeight = inlineHeader
        ? 0
        : headerTopPadding +
            (titleLine > iconButtonSize ? titleLine : iconButtonSize);
    final double segmentHeight = segmentVPadding * 2 + segmentSize * 1.4;
    final double tabsContentHeight =
        inlineHeader && iconButtonSize > segmentHeight
            ? iconButtonSize
            : segmentHeight;
    final double tabsHeight = tabsMarginTop + tabsContentHeight + 6;
    final double chrome = minimal
        ? headerTopPadding + iconButtonSize
        : headerHeight + tabsHeight + contentGap;
    final double bodyMaxHeight =
        minimal ? 0.0 : (panelMaxHeight - chrome).clamp(0.0, 520.0);

    return OsdMetrics(
      breakpoint: breakpoint,
      touch: touch,
      dense: dense,
      minimal: minimal,
      inlineHeader: inlineHeader,
      horizontalMargin: horizontalMargin,
      verticalMargin: verticalMargin,
      panelMaxWidth: panelMaxWidth,
      panelMaxHeight: panelMaxHeight,
      bodyMaxHeight: bodyMaxHeight,
      contentPadding: contentPadding,
      contentGap: contentGap,
      sectionGap: sectionGap,
      cardPaddingH: cardPaddingH,
      cardPaddingV: cardPaddingV,
      gridGap: gridGap,
      rowSpacing: rowSpacing,
      columns: columns,
      titleSize: titleSize,
      sectionTitleSize: sectionTitleSize,
      labelSize: labelSize,
      valueSize: valueSize,
      secondarySize: secondarySize,
      segmentSize: segmentSize,
      iconButtonSize: iconButtonSize,
      segmentVPadding: segmentVPadding,
      advancedVPadding: advancedVPadding,
      urlMaxLines: urlMaxLines,
      headerTopPadding: headerTopPadding,
      tabsMarginTop: tabsMarginTop,
    );
  }

  // 由尺寸表派生的文字样式（颜色来自 OsdStyle）。
  TextStyle get titleStyle => TextStyle(
        fontSize: titleSize,
        fontWeight: FontWeight.w600,
        color: OsdStyle.textPrimary,
        letterSpacing: 0.1,
      );
  TextStyle get sectionTitleStyle => TextStyle(
        fontSize: sectionTitleSize,
        fontWeight: FontWeight.w600,
        color: OsdStyle.textLabel,
        letterSpacing: 1.1,
      );
  TextStyle get labelStyle => TextStyle(
        fontSize: labelSize,
        fontWeight: FontWeight.w500,
        color: OsdStyle.textLabel,
        letterSpacing: 0.2,
      );
  TextStyle get valueStyle => TextStyle(
        fontSize: valueSize,
        fontWeight: FontWeight.w500,
        color: OsdStyle.textPrimary,
      );
  TextStyle get secondaryValueStyle => TextStyle(
        fontSize: secondarySize,
        fontWeight: FontWeight.w400,
        color: OsdStyle.textSecondary,
      );
  TextStyle get segmentStyle => TextStyle(
        fontSize: segmentSize,
        fontWeight: FontWeight.w500,
      );
  TextStyle get urlStyle => TextStyle(
        fontSize: secondarySize,
        height: 1.45,
        color: OsdStyle.textSecondary,
      );

  @override
  bool operator ==(Object other) =>
      other is OsdMetrics &&
      other.breakpoint == breakpoint &&
      other.touch == touch &&
      other.dense == dense &&
      other.panelMaxWidth == panelMaxWidth &&
      other.panelMaxHeight == panelMaxHeight;

  @override
  int get hashCode =>
      Object.hash(breakpoint, touch, dense, panelMaxWidth, panelMaxHeight);
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
    final scope =
        context.dependOnInheritedWidgetOfExactType<OsdMetricsScope>();
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

/// 面板外壳：深色玻璃卡片。
class OsdPanel extends StatelessWidget {
  const OsdPanel({
    super.key,
    required this.child,
    required this.maxWidth,
    required this.maxHeight,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OsdStyle.radius);
    Widget panel = Container(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [OsdStyle.panelTop, OsdStyle.panelBottom],
        ),
        borderRadius: radius,
        border: Border.all(color: OsdStyle.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(96),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (kOsdEnableBlur) {
      panel = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: panel,
        ),
      );
    }

    // Material 祖先：SelectableText 等组件需要（不依赖 InkWell 的涟漪）。
    return Material(
      type: MaterialType.transparency,
      // 面板自身吞掉点击：Container 与卡片间隙默认不参与命中测试，否则点标题栏或
      // 间隙会穿透到下层全屏手势（切换控制栏 / 双击全屏）。面板外仍可穿透。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: panel,
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
    final m = OsdMetricsScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.contentPadding, m.headerTopPadding, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: m.titleStyle,
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

/// 统一尺寸的图标按钮（触控平台自动放大到可点击尺寸）。
class OsdIconButton extends StatefulWidget {
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
  State<OsdIconButton> createState() => _OsdIconButtonState();
}

class _OsdIconButtonState extends State<OsdIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: m.iconButtonSize,
          height: m.iconButtonSize,
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withAlpha(22) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            widget.icon,
            size: m.iconButtonSize * 0.6,
            color: _hover ? OsdStyle.textPrimary : OsdStyle.textSecondary,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 分段控件（替代裸数字 1..5 的页签）。dense 模式下可在尾部内联关闭按钮。
class OsdSegmentedTabs extends StatelessWidget {
  const OsdSegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.trailing,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(
        m.contentPadding,
        m.tabsMarginTop,
        m.contentPadding,
        0,
      ),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: _segment(context, i)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, int i) {
    final m = OsdMetricsScope.of(context);
    final selected = index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(vertical: m.segmentVPadding),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withAlpha(26) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              labels[i],
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: m.segmentStyle.copyWith(
                color: selected ? OsdStyle.textPrimary : OsdStyle.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分节：小标题 + 卡片容器。
class OsdSection extends StatelessWidget {
  const OsdSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    return Padding(
      padding: EdgeInsets.only(top: m.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(title.toUpperCase(), style: m.sectionTitleStyle),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              m.cardPaddingH,
              m.cardPaddingV,
              m.cardPaddingH,
              m.cardPaddingV,
            ),
            decoration: BoxDecoration(
              color: OsdStyle.cardFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: OsdStyle.border),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 一条统计数据（label + value）。
class OsdStat {
  const OsdStat(this.label, this.value, {this.secondary = false, this.accent});

  final String label;
  final String value;

  /// 次要信息：更小字号、更低对比度。
  final bool secondary;

  /// 状态色小圆点；null 表示不显示圆点。
  final Color? accent;
}

/// 统计网格：列数由尺寸表决定（桌面 2 列，极窄屏 1 列），避免重复写 Row。
class OsdStatGrid extends StatelessWidget {
  const OsdStatGrid({super.key, required this.stats});

  final List<OsdStat> stats;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    final int columns = m.columns;
    final rows = <Widget>[];

    for (var i = 0; i < stats.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: m.gridGap));
        final index = i + j;
        cells.add(
          Expanded(
            child: index < stats.length
                ? OsdStatCell(stat: stats[index])
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: m.rowSpacing / 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cells,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// 单元格：上方小号 Label，下方大号 Value。
class OsdStatCell extends StatelessWidget {
  const OsdStatCell({super.key, required this.stat});

  final OsdStat stat;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    final valueStyle = stat.secondary ? m.secondaryValueStyle : m.valueStyle;

    Widget value = Text(
      stat.value,
      style: valueStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (stat.accent != null) {
      value = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: 6),
            decoration: BoxDecoration(
              color: stat.accent,
              shape: BoxShape.circle,
            ),
          ),
          Flexible(child: value),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stat.label,
          style: m.labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        value,
      ],
    );
  }
}

/// Advanced 折叠区：默认收起，点击展开（带轻微动画）。
class OsdAdvanced extends StatefulWidget {
  const OsdAdvanced({super.key, required this.child, this.title = 'Advanced'});

  final Widget child;
  final String title;

  @override
  State<OsdAdvanced> createState() => _OsdAdvancedState();
}

class _OsdAdvancedState extends State<OsdAdvanced> {
  bool _expanded = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    return Padding(
      padding: EdgeInsets.only(top: m.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(
                  horizontal: m.cardPaddingH,
                  vertical: m.advancedVPadding,
                ),
                decoration: BoxDecoration(
                  color: _hover ? Colors.white.withAlpha(12) : OsdStyle.cardFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: OsdStyle.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: m.secondaryValueStyle.copyWith(
                          fontWeight: FontWeight.w500,
                          color: OsdStyle.textPrimary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: m.iconButtonSize * 0.6,
                        color: OsdStyle.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Advanced 里的单条明细：Label 在上，可换行的值在下。
class OsdDetailRow extends StatelessWidget {
  const OsdDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: m.labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: m.secondaryValueStyle.copyWith(height: 1.4),
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
    this.label = 'STREAM URL',
    this.onCopy,
  });

  final String url;
  final String label;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final m = OsdMetricsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: m.labelStyle)),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(60),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OsdStyle.border),
          ),
          child: SelectableText(
            url,
            maxLines: m.urlMaxLines,
            style: m.urlStyle,
          ),
        ),
      ],
    );
  }
}
