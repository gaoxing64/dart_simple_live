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
/// * 窄窗「两字模式」：标签只显示前两个字、平台 icon 隐藏，把宽度让给内容列。
/// * 纯展示 + 回调：选中态由调用方（控制器）算好传进来，widget 自己不存
///   业务状态，方便单测。
class FollowSidebar extends StatefulWidget {
  final List<FollowSidebarItem> items;

  /// 当前选中项的 [FollowSidebarItem.key]。
  final String? selectedKey;

  final ValueChanged<FollowSidebarItem> onSelect;

  /// 本栏宽度（由 [FollowSidebar.widthFor] 按窗口宽度算好传入）。
  final double width;

  /// 窄屏「两字模式」：标签截到前两个字、隐藏平台 icon。
  final bool compact;

  const FollowSidebar({
    required this.items,
    required this.selectedKey,
    required this.onSelect,
    required this.width,
    required this.compact,
    super.key,
  });

  /// 窄屏阈值：低于它进「两字模式」。
  ///
  /// 手机竖屏（360–430）落在这里；平板竖屏（768）仍走常规宽度。
  static const double compactBreakpoint = 480;

  /// 两字模式下的固定栏宽。
  ///
  /// 左内衬 12 + 两字约 26 + 最小间距 8 + 三位计数约 21 + 右内衬 12
  /// ≈ 79，取 80：再窄三位计数就会把标签挤成省略号。
  static const double compactWidth = 80;

  static bool isCompact(double available) => available < compactBreakpoint;

  /// 常规模式的固定栏宽。
  ///
  /// **不随窗口宽度放大**：二级栏在任何窗口宽度下都保持同一视觉重量，
  /// 宽出来的空间全部让给内容列。140 ≈ 左内衬 12 + 平台 icon 14 + 间距 8
  /// + 最长内置平台名 52 + 间距 8 + 三位计数 21 + 右内衬 12（127，留余量）。
  static const double normalWidth = 140;

  /// 侧栏宽度只有两档：窄窗「两字模式」用 [compactWidth]，
  /// 其余宽度固定 [normalWidth]（不按窗口比例缩放）。
  static double widthFor(double available) => isCompact(available) ? compactWidth : normalWidth;

  /// 条目总高度（含条目间距），选中指示条按它计算纵向位置。
  static const double _kItemExtent = 44;

  /// 指示条高度与整行（hover 高亮区域）等高；宽度 3。
  /// 滑动途中高度仍会被拉伸。
  static const double _kIndicatorHeight = _kItemExtent;
  static const double _kIndicatorWidth = 3;

  /// 条目左右内衬。指示条贴在最左缘，不占条目内衬。
  static const double _kItemPaddingLeft = 12;
  static const double _kItemPaddingRight = 12;

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
    final top = index * FollowSidebar._kItemExtent + (FollowSidebar._kItemExtent - FollowSidebar._kIndicatorHeight) / 2;
    return (top, top + FollowSidebar._kIndicatorHeight);
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
    return SizedBox(
      width: widget.width,
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
                    child: _buildItem(context, item),
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

  Widget _buildItem(BuildContext context, FollowSidebarItem item) {
    final scheme = Theme.of(context).colorScheme;
    final selected = item.key == widget.selectedKey;
    // 选中态 = 强调色文字；左缘强调线由全栏共用的指示条负责。
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final label = widget.compact ? FollowSidebar.compactLabel(item.label) : item.label;
    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : null,
        color: color,
      ),
    );
    final countText = Text(
      "${item.count}",
      style: TextStyle(
        fontSize: 12,
        color: color,
      ),
    );
    return InkWell(
      borderRadius: AppStyle.radius8,
      onTap: () => widget.onSelect(item),
      child: Padding(
        padding: const EdgeInsets.only(
          left: FollowSidebar._kItemPaddingLeft,
          right: FollowSidebar._kItemPaddingRight,
        ),
        child: Row(
          children: [
            if (widget.compact) ...[
              // 两字模式下计数仍贴栏右缘，左右内衬相等（12/12）；
              // 栏宽已收到 80，计数与文字之间不会空出一大截。
              Expanded(child: labelText),
              AppStyle.hGap8,
              countText,
            ] else ...[
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: labelText),
                    // 平台 icon 跟在平台名之后；用卡面右下角 chip 那枚单色
                    // 图标（site.iconData），比彩色 logo 更适合缩在文字旁。
                    // 两字模式（上面分支）整个隐藏。
                    if (item.site != null) ...[
                      AppStyle.hGap8,
                      Icon(
                        item.site!.iconData,
                        size: 14,
                        color: color,
                      ),
                    ],
                  ],
                ),
              ),
              AppStyle.hGap8,
              countText,
            ],
          ],
        ),
      ),
    );
  }
}
