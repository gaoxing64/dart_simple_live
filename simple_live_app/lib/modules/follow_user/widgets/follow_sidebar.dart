import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';

/// 第二栏标签的种类。
///
/// `all` / `live` / `offline` 是三个内置视图（各占纵向 PageView 一页）；
/// `site` / `group` 不是页，而是「全部」页内的**筛选态**（见
/// [FollowUserController.selectSidebarItem] 的互斥不变式）。
enum FollowSidebarKind { all, live, offline, site, group }

/// 第二栏的筛选态：选中了某个平台或某个自定义分组。
///
/// 与三个内置视图**互斥**（见 [FollowUserController.selectSidebarItem]）——
/// 要么在看某个内置视图，要么在「全部」页里看某个筛选结果。
class FollowFilter {
  final FollowSidebarKind kind;
  final String id;

  const FollowFilter({required this.kind, required this.id});
}

/// 第二栏的一个标签项。
class FollowSidebarItem {
  /// 选中态比较用的稳定 key：内置项取 kind 名，筛选项带上前缀防撞
  /// （自定义分组 id 是 fractional 生成的，理论上可能长出 'all' 这种值）。
  final FollowSidebarKind kind;

  /// 平台 / 分组的原始 id（siteId / tag id）；内置项为 kind 名。
  final String id;

  final String label;

  /// 平台标签的平台信息（用于单色平台 icon）；内置项与分组为 null。
  final Site? site;

  /// 该标签覆盖的关注数（全部 = 直播 + 未开播）。
  final int count;

  const FollowSidebarItem({
    required this.kind,
    required this.id,
    required this.label,
    this.site,
    required this.count,
  });

  String get key => switch (kind) {
        FollowSidebarKind.all => 'all',
        FollowSidebarKind.live => 'live',
        FollowSidebarKind.offline => 'offline',
        FollowSidebarKind.site => 'site:$id',
        FollowSidebarKind.group => 'group:$id',
      };
}

/// 关注页第二栏：竖排标签（内置视图 → 平台 → 自定义分组）。
///
/// 设计要点：
/// * **始终显示**在左侧：竖屏时底部导航栏占的是底部，左边只此一栏。
/// * 选中态 = **左缘**强调线（贴着第一栏与第二栏之间的分栏线）+ 强调色文字。
///   强调线是一条贯穿全栏的指示条，切换时纵向滑动；两端边缘走一快一慢两条
///   曲线（与首页平台 Tab 的 elastic 指示条同口径），滑动途中会被**拉伸**，
///   落位后再收回到常规高度，而不是整条平移。
/// * **栏宽由内容决定**：标签列按最长的一条量出来，再补上左右相等内衬、
///   平台 icon 与计数的位置。窗口变宽不会把栏拉胖；标签变长 / 系统字号变大
///   时它会随之增长。只有低于 [compactBreakpoint] 的窄窗才退化成
///   「两字模式」：标签截到前两个字，平台 icon 与计数一起收起，把宽度让给
///   右侧内容列。
/// * **标签两端对齐**：列宽取最长标签，短标签按字符均摊、撑满同一列，左缘与
///   右缘都对齐（等价于 Word 里的两端对齐）。
/// * 纯展示 + 回调：选中态由调用方（控制器）算好传进来，widget 自己不存
///   业务状态，方便单测。
class FollowSidebar extends StatefulWidget {
  final List<FollowSidebarItem> items;

  /// 当前选中项的 [FollowSidebarItem.key]。
  final String? selectedKey;

  final ValueChanged<FollowSidebarItem> onSelect;

  /// 本栏可用宽度（关注页内容区总宽），只用于给内容驱动的栏宽封顶。
  final double availableWidth;

  /// 窄屏「两字模式」：标签截到前两个字，平台 icon 与计数一起隐藏。
  final bool compact;

  const FollowSidebar({
    required this.items,
    required this.selectedKey,
    required this.onSelect,
    required this.availableWidth,
    required this.compact,
    super.key,
  });

  /// 窄屏阈值：低于它进「两字模式」。
  ///
  /// 手机竖屏（360–430）落在这里；平板竖屏（768）仍走常规宽度。
  static const double compactBreakpoint = 480;

  static bool isCompact(double available) => available < compactBreakpoint;

  /// 内容驱动栏宽的上限。
  ///
  /// 不受上限时，一个超长分组名会把内容列挤没；超过这条线后标签改走省略号。
  /// 240 对 13px 字号约容得下 14 个汉字，远宽于内置项与常见分组名。
  static const double maxWidth = 240;

  /// 内容列至少保留的宽度（紧凑行一行所需），栏宽封顶时给它让路。
  static const double minContentWidth = 152;

  /// 条目总高度（含条目间距），选中指示条按它计算纵向位置。
  static const double _kItemExtent = 44;

  /// 指示条两端相对条目上/下缘的缩进。
  ///
  /// 取条目 hover 高亮的圆角半径（[AppStyle.radius8]）：圆角段没有竖直边，
  /// 指示条只覆盖中间那段直边，两端才会落在圆角的转角处，而不是像整行
  /// 那样在视觉上比 hover 还高。
  static double get indicatorInset => AppStyle.radius8.topLeft.x;

  /// 指示条高度 = 整行高度减去上下两个圆角。
  /// 滑动途中高度仍会被拉伸。
  static double get _indicatorHeight => _kItemExtent - indicatorInset * 2;

  /// 指示条宽度。
  static const double _kIndicatorWidth = 3;

  /// 条目左右内衬。指示条贴在最左缘，不占条目内衬。
  static const double _kItemPaddingLeft = 12;
  static const double _kItemPaddingRight = 12;

  /// 标签与计数之间的最小间距；平台 icon 也占一份同宽的间距。
  static const double _kItemGap = 8;

  static const double _kLabelFontSize = 13;
  static const double _kCountFontSize = 12;
  static const double _kSiteIconSize = 14;

  /// 指示条滑动时长 / 基础曲线（与首页 Tab 切换一致）。
  static const Duration _kIndicatorDuration = Duration(milliseconds: 300);
  static const Curve _kIndicatorCurve = Curves.ease;

  /// 窄屏只留前两个字（按字符簇取，避免把 emoji / 组合字符截断）。
  static String compactLabel(String text) {
    final chars = text.characters;
    if (chars.length <= 2) {
      return text;
    }
    return chars.take(2).toString();
  }

  @override
  State<FollowSidebar> createState() => _FollowSidebarState();
}

class _FollowSidebarState extends State<FollowSidebar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 上一次的选中下标，用于区分「选中项真的变了」和普通重建。
  int? _selectedIndex;

  bool _visible = false;

  /// 本次动画的起止上下缘；动画中途改选时以当前可见上下缘为新起点。
  double _startTop = 0;
  double _startBottom = 0;
  double _targetTop = 0;
  double _targetBottom = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FollowSidebar._kIndicatorDuration,
      value: 1,
    );
    _selectedIndex = _indexOfSelection();
    _snapTo(_selectedIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _indexOfSelection() {
    final index = widget.items.indexWhere((i) => i.key == widget.selectedKey);
    return index < 0 ? null : index;
  }

  /// 第 [index] 项对应的指示条上下缘（Stack 坐标系，已含条目本身的居中）。
  (double, double) _bandOf(int index) {
    final top = index * FollowSidebar._kItemExtent + (FollowSidebar._kItemExtent - FollowSidebar._indicatorHeight) / 2;
    return (top, top + FollowSidebar._indicatorHeight);
  }

  void _snapTo(int? index) {
    if (index == null) {
      _visible = false;
      return;
    }
    final (top, bottom) = _bandOf(index);
    _visible = true;
    _startTop = _targetTop = top;
    _startBottom = _targetBottom = bottom;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant FollowSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _indexOfSelection();
    final band = index == null ? null : _bandOf(index);
    // 选中项与落点都没变：普通重建（列表刷新、计数变化）不动动画。
    if (index == _selectedIndex && (band == null || (band.$1 == _targetTop && band.$2 == _targetBottom))) {
      return;
    }
    // 动画途中改选：把当前看到的上下缘当作新起点，避免跳变。
    final (currentTop, currentBottom) = _visible ? _visualBand() : (band?.$1 ?? 0, band?.$2 ?? 0);
    _selectedIndex = index;
    if (band == null) {
      _visible = false;
      _controller.stop();
      return;
    }
    _visible = true;
    _startTop = currentTop;
    _startBottom = currentBottom;
    _targetTop = band.$1;
    _targetBottom = band.$2;
    _controller.forward(from: 0);
  }

  /// 当前可见的指示条上下缘。
  ///
  /// 与 Material 的 elastic Tab 指示条同口径：向下的移动里，下缘（先导边）
  /// 走减速曲线（先快后慢），上缘（拖尾边）走加速曲线（先慢后快），
  /// 于是条本身在途中被拉长，落位后两端重合恢复原高。
  (double, double) _visualBand() {
    final double progress = FollowSidebar._kIndicatorCurve.transform(_controller.value);
    final bool movingDown = _targetTop > _startTop;
    final double leading = math.sin(progress * math.pi / 2);
    final double trailing = 1 - math.cos(progress * math.pi / 2);
    return (
      _lerp(_startTop, _targetTop, movingDown ? trailing : leading),
      _lerp(_startBottom, _targetBottom, movingDown ? leading : trailing),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = _measure(context);
    return SizedBox(
      width: metrics.width,
      child: SingleChildScrollView(
        padding: AppStyle.edgeInsetsV8,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in widget.items)
                  SizedBox(
                    key: ValueKey('sidebar-${item.key}'),
                    height: FollowSidebar._kItemExtent,
                    child: _buildItem(context, item, metrics),
                  ),
              ],
            ),
            // 选中指示条：贴着左缘（与第一栏之间的分栏线）上下滑动。
            if (_visible)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final (top, bottom) = _visualBand();
                  return Positioned(
                    key: const ValueKey('sidebar-indicator'),
                    left: 0,
                    top: top,
                    width: FollowSidebar._kIndicatorWidth,
                    height: bottom - top,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppStyle.radius4,
                        color: scheme.primary,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 按「最长标签 + 计数 + 固定内衬」算出栏宽，再按上限截断。
  ///
  /// 标签一律按选中态字重（w600）量：选中时变粗不会把栏宽顶得跳一下。
  _SidebarMetrics _measure(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final labelStyle = baseStyle.merge(
      const TextStyle(fontSize: FollowSidebar._kLabelFontSize),
    );
    final boldLabelStyle = labelStyle.copyWith(fontWeight: FontWeight.w600);
    final countStyle = baseStyle.merge(
      const TextStyle(fontSize: FollowSidebar._kCountFontSize),
    );

    // 两字模式连计数一起收起：这时栏里只剩标签，不再为计数留列。
    final showCount = !widget.compact;
    var labelWidth = 0.0;
    var countWidth = 0.0;
    var showSiteIcon = false;
    for (final item in widget.items) {
      final label = widget.compact ? FollowSidebar.compactLabel(item.label) : item.label;
      labelWidth = math.max(labelWidth, _measureLabel(label, boldLabelStyle, textScaler, textDirection));
      if (showCount) {
        countWidth = math.max(countWidth, _measureText('${item.count}', countStyle, textScaler, textDirection));
      }
      showSiteIcon = showSiteIcon || (!widget.compact && item.site != null);
    }

    final iconExtent = showSiteIcon ? FollowSidebar._kItemGap + FollowSidebar._kSiteIconSize : 0.0;
    final countExtent = showCount ? FollowSidebar._kItemGap + countWidth : 0.0;
    final naturalWidth = FollowSidebar._kItemPaddingLeft +
        labelWidth +
        iconExtent +
        countExtent +
        FollowSidebar._kItemPaddingRight;
    // 封顶：既不超过 [FollowSidebar.maxWidth]，也给内容列留出最小宽度。
    final limit = math.min(
      FollowSidebar.maxWidth,
      math.max(0.0, widget.availableWidth - FollowSidebar.minContentWidth),
    );
    final width = math.min(naturalWidth, limit);
    final fixedWidth = FollowSidebar._kItemPaddingLeft +
        iconExtent +
        countExtent +
        FollowSidebar._kItemPaddingRight;
    return _SidebarMetrics(
      width: width,
      labelWidth: math.max(0.0, width - fixedWidth),
      labelStyle: labelStyle,
      countStyle: countStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
  }

  /// 标签宽度按**逐字符**量：两端对齐时每个字符是独立的一块，
  /// 宽度口径要和渲染一致，不能拿整串的 shaping 结果去比。
  static double _measureLabel(
    String text,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    var width = 0.0;
    for (final character in text.characters) {
      width += _measureText(character, style, textScaler, textDirection);
    }
    return width;
  }

  Widget _buildItem(BuildContext context, FollowSidebarItem item, _SidebarMetrics metrics) {
    final scheme = Theme.of(context).colorScheme;
    final selected = item.key == widget.selectedKey;
    // 选中态 = 强调色文字；左缘强调线由全栏共用的指示条负责。
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final label = widget.compact ? FollowSidebar.compactLabel(item.label) : item.label;
    final labelText = _JustifiedLabel(
      key: ValueKey('sidebar-label-${item.key}'),
      text: label,
      semanticsLabel: item.label,
      width: metrics.labelWidth,
      style: metrics.labelStyle.copyWith(
        fontWeight: selected ? FontWeight.w600 : null,
        color: color,
      ),
      textScaler: metrics.textScaler,
      textDirection: metrics.textDirection,
    );
    final countText = Text(
      "${item.count}",
      style: metrics.countStyle.copyWith(color: color),
    );
    final body = InkWell(
      borderRadius: AppStyle.radius8,
      onTap: () => widget.onSelect(item),
      child: Padding(
        padding: const EdgeInsets.only(
          left: FollowSidebar._kItemPaddingLeft,
          right: FollowSidebar._kItemPaddingRight,
        ),
        child: Row(
          children: [
            labelText,
            // 平台 icon 跟在平台名之后；用卡面右下角 chip 那枚单色
            // 图标（site.iconData），比彩色 logo 更适合缩在文字旁。
            // 两字模式整个隐藏。
            if (!widget.compact && item.site != null) ...[
              AppStyle.hGap8,
              Icon(
                item.site!.iconData,
                size: FollowSidebar._kSiteIconSize,
                color: color,
              ),
            ],
            // 两字模式只留标签本身（栏宽也照着两字算）；
            // 常规模式计数一律贴栏右缘，标签列已经定宽，左右两端都对齐。
            if (!widget.compact) ...[
              const Spacer(),
              AppStyle.hGap8,
              countText,
            ],
          ],
        ),
      ),
    );
    // 手机端两字标签无法分辨前两个字相同的分组：长按看完整名（桌面悬停
    // 同样生效）。完整名已由内层 Semantics 提供，这里不再重复朗读。
    if (!widget.compact || label == item.label) {
      return body;
    }
    return Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: body,
    );
  }
}

/// 栏宽测量结果。
class _SidebarMetrics {
  final double width;

  /// 标签列的固定宽度（不含左右内衬、icon 与计数）。
  final double labelWidth;

  final TextStyle labelStyle;
  final TextStyle countStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  const _SidebarMetrics({
    required this.width,
    required this.labelWidth,
    required this.labelStyle,
    required this.countStyle,
    required this.textScaler,
    required this.textDirection,
  });
}

double _measureText(
  String text,
  TextStyle style,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// 撑满 [width] 的单行标签：逐字符排开，首尾分别贴住左右缘。
///
/// 单行文本在 Flutter 里没有现成的两端对齐（`TextAlign.justify` 只作用于
/// 软换行的非末行），`letterSpacing` 又会把间距分到两端、把首字推进来；
/// 这里直接按字符簇拆开，用 `spaceBetween` 把剩余宽度均摊到字与字之间。
/// 放不下时（栏宽被封顶）退回普通省略号文本。
class _JustifiedLabel extends StatelessWidget {
  final String text;

  /// 视觉上可能被两字模式截断，但读屏始终读完整标签。
  final String? semanticsLabel;

  final double width;
  final TextStyle style;
  final TextScaler textScaler;
  final TextDirection textDirection;

  const _JustifiedLabel({
    required this.text,
    this.semanticsLabel,
    required this.width,
    required this.style,
    required this.textScaler,
    required this.textDirection,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final characters = text.characters.toList();
    var naturalWidth = 0.0;
    for (final character in characters) {
      naturalWidth += _measureText(character, style, textScaler, textDirection);
    }
    final Widget content;
    if (naturalWidth > width + 0.5) {
      content = SizedBox(
        width: width,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
    } else if (characters.length < 2) {
      content = SizedBox(
        width: width,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        ),
      );
    } else {
      // 视觉上是逐字符的 Row；语义仍按整条标签朗读。
      content = SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          textDirection: textDirection,
          children: [
            for (final character in characters)
              Text(
                character,
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
          ],
        ),
      );
    }
    return Semantics(
      label: semanticsLabel ?? text,
      child: ExcludeSemantics(child: content),
    );
  }
}
