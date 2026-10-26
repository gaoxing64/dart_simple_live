// 悬浮 dock 导航栏 —— 移植自 FlClash 的 lib/widgets/navigation_dock.dart
// （chen08209/FlClash，本项目仅取其中胶囊底栏那部分，类名由 FloatingNavigationBar
// 改为 [NavigationDock] 以免与被它替换掉的那个同名 widget 混淆）。
//
// 与上游的差异，逐条都有理由：
//
//   * **只移植 dock 本体，丢掉 trailing FAB 槽位**（上游的 [NavigationDock] +
//     [_DockTrailing] + [_SlotMaterialize] + [ElasticPress]/[ElasticButton]）。
//     那一整块是给「dock 右侧挂一个圆形按钮」用的，本项目没有这个需求，而它是
//     全文件里**唯一**用到 [SpringCurve] 的地方 —— `SpringCurve` 在本项目的
//     Flutter 3.47.5 上不存在（只有 `SpringDescription.withDurationAndBounce`）。
//     删掉它同时也去掉了 `AnimatedSize` + `AnimatedSwitcher` 那套双层过渡，
//     底栏只剩一层，开销更小。
//
//   * **[AppShape.full] → [RoundedSuperellipseBorder]**：`AppShape` 是 FlClash
//     自己的形状库（连它 `copyWith` / `getOuterPath` 的用法也是那套API）。
//     本项目统一用 Material 新形状，同一个视觉诉求（药丸）用
//     `RoundedSuperellipseBorder` 表达—— [_dockShape] 收这一份，paint 与
//     clipPath 都用它，不会各写一份半径。
//
//   * **[GlyphIcon] → [Icon]**：上游的图标系统带 fill 动画（按压时图标填充
//     进度），本项目底栏用 Material `Icon`，按压反馈由整条 bar 的弹性 swell
//     承担（见 [_PressTransform]），不依赖逐图标动画。
//
//   * **宽度固定 86 × N，不做上游的「≥5 项就全宽」**：本项目固定 4 个 Tab
//     （首页/关注/分类/我的），全宽会让胶囊在 360 宽屏上拉成每格 80px 的
//     扁条，与项目其它页面的留白节奏不一致。保持与改造前的胶囊同宽，
//     换的只是交互内核与观感。
//
//   * **底栏留白交给调用方**：上游 [NavigationDock.insetOf] 负责算「内容该在
//     什么高度收尾」，本项目由 `Scaffold.extendBody` + `BarCollapse` 处理，
//     这里只管把安全区与间距垫在胶囊下方（同改造前的 `bottomPadding`）。
//
// 交互内核（值得读的部分，都在文件下半段）：
//
//   * **[_Spring]**：一个用 Ticker 手搓的弹簧。之所以不用
//     `AnimationController.animateWith`，是因为后者每次重定向都会重启 ticker，
//     首个帧读不到elapsed time —— 手指每帧移动都重新 springTo 的话，值会被
//     一直按住不动。这里的做法是重定向时**只记下新的起点时刻**，让同一个
//     simulation 连续跑。
//
//   * **[_lensRect]**：透镜的几何。宽度与高度都随速度拉伸（jelly），速度取自
//     `_Spring.velocity`，即 `simulation.dx(t)` —— 按得多快，透镜就拉多扁。
//
//   * **[_RenderLensTint]**：整个观感的关键。用 `pushClipPath` 把每个 destination
//     的内容切成「透镜内/ 外」两份，透镜内那份套一层
//     `ColorFilter.mode(primary, BlendMode.srcIn)` 整体染色。所以拖动时图标是
//     **逐格渐变**变色的，而不是整格突然切换。透镜抬起时内容还会在透镜中心
//     放大（`_lensMagnify`）、并跟着鼠标做视差偏移，而布局与命中测试看到的
//     仍是静止状态 —— 全靠 `paint` 里手推矩阵。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:simple_live_app/app/system_ui_inset.dart';

// ── 布局常量 ────────────────────────────────────────────────────

/// 胶囊高度（不含底部安全区与 [NavigationDock.bottomPadding]）。
const double kNavigationDockHeight = 62;

/// 每个 destination 的固定宽度。
///
/// 它同时也是选中透镜静止时的宽度（见 [_lensRect] 的 `extent`），所以「药丸有多
/// 宽」和「每格占多宽」是同一个数—— 改这一个，两个一起动。
const double kNavigationDockItemExtent = 72;

/// 胶囊外边距：上下左右各留一点，让药丸与内容不贴边。
const double _kBarPadding = 4;

/// 阴影预留空间：胶囊的落影画在自身盒子之外，靠外层 Padding 腾出这段。
const double kNavigationDockShadowRoom = 8;

/// 距屏幕底部的默认间距（叠加在安全区之上）。
const double kNavigationDockBottomPadding = 12;

/// 命中区域向外扩展的像素：点偏了也能命中胶囊。
const double _kHitSlop = 8;

const double _kIconSize = 24;
const double _kLabelGap = 2;
const double _kLabelInset = 2;
const double _kLabelSize = 10;

/// 文字被压缩到的下限。再窄就交给 Tooltip 显示完整标签。
const double _kMinLabelSize = 9;

// ── 手感常量 ────────────────────────────────────────────────────

/// 按下时整条 bar 的横向膨胀比例（1/8 = 12.5%）。
const double _kPressGrowth = 1 / 8;

/// 膨胀量的绝对上限（px）：超长条按比例膨胀会夸张到变形。
const double _kMaxPressGrowth = 16;

/// 透镜抬起时的额外放大（尺寸方向的增量，两侧各一份）。
const double _kLensGrowth = 14;

/// 透镜中心在「抬起」时的放大比例。
const double _kLensMagnify = 0.12;

/// 鼠标悬停时透镜朝光标靠拢的比例（1 = 完全跟随，0.2 = 只挪两成距离）。
const double _kHoverMagnet = 0.2;

/// destination 内容跟随光标的视差比例（比透镜跟得更少，形成层次）。
const double _kHoverParallax = 0.5;

/// 悬停高亮的alpha 峰值。
const double _kHoverAlpha = 0.08;

/// 鼠标静止在胶囊上时整条 bar 的常驻膨胀量（模拟 iOS 的 hover 抬起）。
const double _kHoverSwell = 0.4;

/// 达到这个速度时 jelly 拉伸到满。
const double _kJellySpeed = 8;

/// jelly 的最大拉伸比例。
const double _kJellyStretch = 0.25;

/// 拖出两端时的橡皮筋上限。
const double _kOverdrag = 0.35;

/// 整条 bar 被横向拖动时的拉伸上限（按短边比例算）。
const double _kPullLimit = 7 / 32;

/// 横向拉伸换算成缩放的比例。
const double _kPullStretch = 0.5;

/// 甩动时的预判时长：按这个时间内的位移决定落到哪一格。
const Duration _kFlingProjection = Duration(milliseconds: 100);

final SpringDescription _kTrackSpring =
    SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 120));

final SpringDescription _kLiftSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 280),
  bounce: 0.2,
);

final SpringDescription _kSettleSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
  bounce: 0.32,
);

final SpringDescription _kHoverSpring =
    SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 260), bounce: 0.18);

final SpringDescription _kFadeSpring =
    SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 200));

/// 药丸形状，paint 与 clipPath 共用这一份定义。
final ShapeBorder _dockShape = RoundedSuperellipseBorder(
  borderRadius: BorderRadius.all(
    Radius.circular(kNavigationDockHeight / 2),
  ),
);

/// iOS 那样的柔和宽投影，而不是 Material 的 elevation。
List<BoxShadow> _dockShadows(ColorScheme colorScheme) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.08 * strength),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * strength),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

/// 橡皮筋阻尼：越界越远，实际位移越趋近 [limit]。
///
/// 公开是因为它与 [_lensRect] 一样是**纯几何函数**，抽出来才能在 widget 测试里
/// 直接扫边界（widget 里那份是私有调用，见 [_rubberBand]）。
double rubberBandOffset(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}

/// dock 内边距 [padding] 造成的每格宽度偏差修正后的位置换算。
///
/// 把「局部坐标 → 以第一格中心为 0 的位置」拆成纯函数：越界量交给
/// [rubberBandOffset] 夹住，方向按 [textDirection] 翻转（RTL 下光标在右、
/// 第一格也在右）。
double dockPositionAt({
  required double dx,
  required double barWidth,
  required double padding,
  required int count,
  required TextDirection textDirection,
}) {
  if (count <= 0) {
    return 0;
  }
  final width = textDirection == TextDirection.ltr ? dx : barWidth - dx;
  final extent = (barWidth - padding * 2) / count;
  final position = (width - padding) / extent - 0.5;
  final lastIndex = count - 1;
  if (position < 0) {
    return rubberBandOffset(position, _kOverdrag);
  }
  if (position > lastIndex) {
    return lastIndex + rubberBandOffset(position - lastIndex, _kOverdrag);
  }
  return position;
}

/// 透镜的盒子。坐标以第一个 destination 的中心为 0。
///
/// [position] 可以是小数（手指停在两格中间）或越界值（被橡皮筋夹过），
/// [velocity] 决定 jelly 拉伸量，[lift]（0~1，按下抬起程度）决定额外放大。
///
/// 公开理由同 [rubberBandOffset]：纯几何，测试直接扫边界。
Rect lensRectFor({
  required double position,
  required double velocity,
  required double extent,
  required double height,
  required double lift,
}) {
  final stretch =
      (velocity.abs() / _kJellySpeed).clamp(0.0, 1.0) * _kJellyStretch;
  final growth = _kLensGrowth * 2 * lift;
  final width = (extent + growth) * (1 + stretch);
  final lensHeight = (height + growth) * (1 - stretch / 2);
  return Rect.fromLTWH(
    (position + 0.5) * extent - width / 2,
    (height - lensHeight) / 2,
    width,
    lensHeight,
  );
}

/// widget 内部用的别名，保持调用处简短。
double _rubberBand(double overshoot, double limit) =>
    rubberBandOffset(overshoot, limit);

Rect _lensRect({
  required double position,
  required double velocity,
  required double extent,
  required double height,
  required double lift,
}) => lensRectFor(
  position: position,
  velocity: velocity,
  extent: extent,
  height: height,
  lift: lift,
);

/// 一个「弹簧趋近目标值」的量，目标可以每帧都被手指改写。
///
/// 为什么不用 [AnimationController.animateWith]：那个方法会重启 ticker，
/// 重启后首个帧读不到 elapsed time —— 手指每帧移动都重新 springTo 的话，
/// 值会被一直按在起点不动。这里的 [springTo] 在 ticker 已在跑时**只更新起点
/// 时刻**，让同一个 [SpringSimulation] 连续演下去。
class _Spring extends ChangeNotifier implements ValueListenable<double> {
  _Spring(TickerProvider vsync, this._value) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  double _now = 0;
  double _start = 0;

  @override
  double get value => _value;

  double get target => _simulation == null ? _value : _target;

  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  void springTo(double target, SpringDescription spring) {
    _simulation = SpringSimulation(spring, _value, target, velocity);
    _target = target;
    if (_ticker.isActive) {
      // 已经在跑：只挪起点，模拟本身继续 —— 这样每帧重定向也不会卡住。
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null;
    _ticker.stop();
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// 量出标签的渲染尺寸：用来判断「放得下就正常显示，放不下就缩字号，再不行
/// 就交给 Tooltip」。
({double width, double height}) _measureLabel(
  BuildContext context,
  String label,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final size = (width: painter.width, height: painter.height);
  painter.dispose();
  return size;
}

/// 一个 destination：图标 + 文字。
class NavigationDockDestination {
  const NavigationDockDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;

  /// 选中时用的图标。为 null 时沿用 [icon]，只靠颜色区分。
  final IconData? selectedIcon;

  final String label;
}

/// 让偏离鼠标的触摸（最多 [_kHitSlop]）仍然命中胶囊。
class _HitSlop extends SingleChildRenderObjectWidget {
  const _HitSlop({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlop();
}

class _RenderHitSlop extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (size.isEmpty ||
        !(Offset.zero & size).inflate(_kHitSlop).contains(position)) {
      return false;
    }
    if (!hitTestChildren(result, position: _onSpine(position))) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  /// 药丸的圆头会裁掉命中测试，直的中段不会 —— 把边缘的点掰到中线上。
  Offset _onSpine(Offset position) {
    final radius = size.shortestSide / 2;
    return Offset(
      position.dx.clamp(radius, size.width - radius),
      size.height / 2,
    );
  }
}

/// 整条 bar 的弹性形变：按下时 swell，横向拖动时拉伸。
///
/// 只影响绘制 —— 布局、命中测试、以及任何挂在子节点上的东西（Tooltip、
/// 菜单）看到的都是静止状态。
class _PressTransform extends SingleChildRenderObjectWidget {
  const _PressTransform({required this.lift, required this.pull, super.child});

  final double lift;
  final Offset pull;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPressTransform(lift: lift, pull: pull);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPressTransform renderObject,
  ) {
    renderObject
      ..lift = lift
      ..pull = pull;
  }
}

class _RenderPressTransform extends RenderProxyBox {
  _RenderPressTransform({required double lift, required Offset pull})
    : _lift = lift,
      _pull = pull;

  double _lift;
  Offset _pull;

  set lift(double value) {
    if (value == _lift) {
      return;
    }
    _lift = value;
    markNeedsPaint();
  }

  set pull(Offset value) {
    if (value == _pull) {
      return;
    }
    _pull = value;
    markNeedsPaint();
  }

  Matrix4 get _transform {
    final swell =
        1 + _lift * math.min(_kPressGrowth * 2, _kMaxPressGrowth / size.longestSide);
    final scaleX = swell * (1 + _pull.dx.abs() / size.width * _kPullStretch);
    final scaleY = swell * (1 + _pull.dy.abs() / size.height * _kPullStretch);
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)..setTranslationRaw(
      center.dx * (1 - scaleX) + _pull.dx,
      center.dy * (1 - scaleY) + _pull.dy,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty || (_lift == 0 && _pull == Offset.zero)) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}

/// 鼠标指针下的高亮块：画在光标所在的那一格，并朝光标方向倾一点。
class _HoverHighlight extends StatelessWidget {
  const _HoverHighlight({
    required this.position,
    required this.extent,
    required this.opacity,
  });

  final double position;
  final double extent;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final alpha = _kHoverAlpha * opacity.clamp(0.0, 1.0);
    if (alpha == 0) {
      return const SizedBox.shrink();
    }
    return Positioned.directional(
      textDirection: Directionality.of(context),
      start: position * extent,
      top: 0,
      bottom: 0,
      width: extent,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha),
          shape: _dockShape,
        ),
      ),
    );
  }
}

/// 选中透镜本体：药丸底色。
class _Lens extends StatelessWidget {
  const _Lens({
    required this.position,
    required this.velocity,
    required this.extent,
    required this.height,
    required this.lift,
  });

  final double position;
  final double velocity;
  final double extent;
  final double height;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rect = _lensRect(
      position: position,
      velocity: velocity,
      extent: extent,
      height: height,
      lift: lift,
    );
    return PositionedDirectional(
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          // 抬起时往primary 里多混一点，按下瞬间就「亮」起来。
          color: Color.alphaBlend(
            colorScheme.onSecondaryContainer.withValues(
              alpha: 0.08 * lift.clamp(0.0, 1.0),
            ),
            colorScheme.secondaryContainer,
          ),
          shape: _dockShape,
        ),
      ),
    );
  }
}

/// 单个 destination 的内容（图标 + 文字）。
///
/// 外层 [_LensTint] 负责染色与形变；这里只管把内容摆成 M3 的两行布局。
class _FloatingBarItem extends StatefulWidget {
  const _FloatingBarItem({
    required this.destination,
    required this.selected,
    required this.index,
    required this.lens,
    required this.hoverAt,
    required this.lift,
    required this.labelStyle,
    required this.labelHeight,
    required this.labelOverflows,
    required this.onActivate,
  });

  final NavigationDockDestination destination;
  final bool selected;
  final int index;
  final _Spring lens;

  /// 鼠标悬停位置，以第一个 destination 的中心为 0。
  final ValueListenable<double?> hoverAt;
  final ValueListenable<double> lift;
  final TextStyle? labelStyle;
  final double labelHeight;
  final bool labelOverflows;
  final VoidCallback onActivate;

  @override
  State<_FloatingBarItem> createState() => _FloatingBarItemState();
}

class _FloatingBarItemState extends State<_FloatingBarItem>
    with SingleTickerProviderStateMixin {
  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onActivate();
        return null;
      },
    ),
  };
  late final _Spring _parallax = _Spring(this, 0);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.hoverAt.addListener(_followPointer);
  }

  @override
  void didUpdateWidget(covariant _FloatingBarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverAt != widget.hoverAt) {
      oldWidget.hoverAt.removeListener(_followPointer);
      widget.hoverAt.addListener(_followPointer);
    }
    _followPointer();
  }

  @override
  void dispose() {
    widget.hoverAt.removeListener(_followPointer);
    _parallax.dispose();
    super.dispose();
  }

  /// 内容朝光标方向偏一点（比透镜跟得少），形成层次。
  void _followPointer() {
    final hoverAt = widget.hoverAt.value;
    final offset = hoverAt == null ? 0.0 : hoverAt - widget.index;
    // 差得超过半格就直接归零，免得相邻格也被拽着走。
    final target = offset.abs() > 0.5 ? 0.0 : offset * _kHoverMagnet * _kHoverParallax;
    if (target != _parallax.target) {
      _parallax.springTo(target, _kHoverSpring);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.onSurfaceVariant;
    final icon = widget.selected
        ? (widget.destination.selectedIcon ?? widget.destination.icon)
        : widget.destination.icon;
    final content = _LensTint(
      lens: widget.lens,
      lift: widget.lift,
      parallax: _parallax,
      index: widget.index,
      color: colorScheme.primary,
      textDirection: Directionality.of(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kLabelInset),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: _kIconSize, color: color),
            const SizedBox(height: _kLabelGap),
            SizedBox(
              height: widget.labelHeight,
              child: Center(
                child: Text(
                  widget.destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: widget.labelStyle?.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return FocusableActionDetector(
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.destination.label,
        // 子节点（图标 + 文字）会被读屏重复念一遍，这里整个排除。
        excludeSemantics: true,
        onTap: widget.onActivate,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: _focused
                ? colorScheme.onSurface.withValues(alpha: 0.1)
                : Colors.transparent,
            // 聚焦描边只在键盘聚焦时出现，不能走 _dockShape（它没有 copyWith，
            // 也不该为了一个边框复制一份形状）—— 这里按同一半径重建。
            shape: RoundedSuperellipseBorder(
              borderRadius: const BorderRadius.all(
                Radius.circular(kNavigationDockHeight / 2),
              ),
              side: _focused
                  ? BorderSide(color: colorScheme.secondary, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: widget.labelOverflows
              ? Tooltip(message: widget.destination.label, child: content)
              : content,
        ),
      ),
    );
  }
}

/// 把透镜下的内容染成 [color]，透镜外的不动 —— 切到透镜形状，
/// 于是透镜扫过时destination 是「逐格渐变」变色而不是整格突变。
///
/// 透镜抬起时内容在透镜中心放大，并跟着 [parallax] 偏移；但布局与命中测试
/// 看到的仍是静止状态（形变全在 [paint] 里手推矩阵）。
class _LensTint extends SingleChildRenderObjectWidget {
  const _LensTint({
    required this.lens,
    required this.lift,
    required this.parallax,
    required this.index,
    required this.color,
    required this.textDirection,
    super.child,
  });

  final _Spring lens;
  final ValueListenable<double> lift;
  final ValueListenable<double> parallax;
  final int index;
  final Color color;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLensTint(
      lens: lens,
      lift: lift,
      parallax: parallax,
      index: index,
      color: color,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderLensTint renderObject) {
    renderObject
      ..lens = lens
      ..lift = lift
      ..parallax = parallax
      ..index = index
      ..color = color
      ..textDirection = textDirection;
  }
}

class _RenderLensTint extends RenderProxyBox {
  _RenderLensTint({
    required _Spring lens,
    required ValueListenable<double> lift,
    required ValueListenable<double> parallax,
    required int index,
    required Color color,
    required TextDirection textDirection,
  }) : _lens = lens,
       _lift = lift,
       _parallax = parallax,
       _index = index,
       _color = color,
       _textDirection = textDirection;

  final _outside = LayerHandle<ClipPathLayer>();
  final _inside = LayerHandle<ClipPathLayer>();
  final _tint = LayerHandle<ColorFilterLayer>();
  final _outsideMotion = LayerHandle<TransformLayer>();
  final _insideMotion = LayerHandle<TransformLayer>();

  _Spring _lens;
  set lens(_Spring value) {
    if (value == _lens) {
      return;
    }
    if (attached) {
      _lens.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lens = value;
    markNeedsPaint();
  }

  ValueListenable<double> _lift;
  set lift(ValueListenable<double> value) {
    if (value == _lift) {
      return;
    }
    if (attached) {
      _lift.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lift = value;
    markNeedsPaint();
  }

  ValueListenable<double> _parallax;
  set parallax(ValueListenable<double> value) {
    if (value == _parallax) {
      return;
    }
    if (attached) {
      _parallax.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _parallax = value;
    markNeedsPaint();
  }

  int _index;
  set index(int value) {
    if (value == _index) {
      return;
    }
    _index = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _lens.addListener(markNeedsPaint);
    _lift.addListener(markNeedsPaint);
    _parallax.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _lens.removeListener(markNeedsPaint);
    _lift.removeListener(markNeedsPaint);
    _parallax.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _outside.layer = null;
    _inside.layer = null;
    _tint.layer = null;
    _outsideMotion.layer = null;
    _insideMotion.layer = null;
    super.dispose();
  }

  /// 本destination 在整条 bar 坐标系里的透镜盒。
  Rect get _lensBounds {
    final rect = _lensRect(
      position: _lens.value - _index,
      velocity: _lens.velocity,
      extent: size.width,
      height: size.height,
      lift: _lift.value,
    );
    return _textDirection == TextDirection.ltr
        ? rect
        : Rect.fromLTRB(
            size.width - rect.right,
            rect.top,
            size.width - rect.left,
            rect.bottom,
          );
  }

  Matrix4? get _motion {
    // 越靠近透镜中心，放大越明显。
    final emphasis = (1 - (_lens.value - _index).abs()).clamp(0.0, 1.0);
    final scale = 1 + _kLensMagnify * emphasis * _lift.value;
    final direction = _textDirection == TextDirection.ltr ? 1 : -1;
    final shift = _parallax.value * size.width * direction;
    if (scale == 1 && shift == 0) {
      return null;
    }
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx * (1 - scale) + shift,
      center.dy * (1 - scale),
      0,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final motion = _motion;
    if (motion != null) {
      transform.multiply(motion);
    }
  }

  void _paintMoved(
    PaintingContext context,
    Offset offset,
    Matrix4? motion,
    LayerHandle<TransformLayer> handle,
  ) {
    if (child == null) {
      return;
    }
    // pushTransform 只接受非 null 矩阵：无动效时直接走裸 paint，并把上一帧
    // 留下的变换层丢掉（否则形变消退后那一帧仍带着旧矩阵）。
    if (motion == null) {
      handle.layer = null;
      super.paint(context, offset);
      return;
    }
    handle.layer = context.pushTransform(
      needsCompositing,
      offset,
      motion,
      super.paint,
      oldLayer: handle.layer,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    final motion = _motion;
    final bounds = Offset.zero & size;
    final content = motion == null ? bounds : MatrixUtils.transformRect(motion, bounds);
    final lensBounds = _lensBounds;
    // 相邻两格刚好不重叠：透镜静止在别处时，这一格完全不被裁。
    if (!lensBounds.overlaps(content)) {
      _outside.layer = null;
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
      _paintMoved(context, offset, motion, _outsideMotion);
      return;
    }
    final reach = content.expandToInclude(bounds).inflate(_kLabelInset);
    final lens = _dockShape.getOuterPath(lensBounds);
    // even-odd：外框减去透镜孔 = 透镜外的那部分。
    _outside.layer = context.pushClipPath(
      needsCompositing,
      offset,
      reach,
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(reach)
        ..addPath(lens, Offset.zero),
      (context, offset) => _paintMoved(context, offset, motion, _outsideMotion),
      oldLayer: _outside.layer,
    );
    _inside.layer = context.pushClipPath(
      needsCompositing,
      offset,
      lensBounds,
      lens,
      (context, offset) => _paintTinted(context, offset, lensBounds, motion),
      oldLayer: _inside.layer,
    );
  }

  void _paintTinted(
    PaintingContext context,
    Offset offset,
    Rect lensBounds,
    Matrix4? motion,
  ) {
    // srcIn：只保留图形本身的 alpha，颜色整体换成 primary。
    final filter = ColorFilter.mode(_color, BlendMode.srcIn);
    if (needsCompositing) {
      _tint.layer = context.pushColorFilter(
        offset,
        filter,
        (context, offset) =>
            _paintMoved(context, offset, motion, _insideMotion),
        oldLayer: _tint.layer,
      );
      return;
    }
    _tint.layer = null;
    final canvas = context.canvas
      ..saveLayer(lensBounds.shift(offset), Paint()..colorFilter = filter);
    _paintMoved(context, offset, motion, _insideMotion);
    canvas.restore();
  }
}

/// 悬浮药丸导航栏：选中的位置是一枚可以在各格之间**拖动**的透镜。
///
/// 手感参照 iOS tab bar：
///
/// * 按下 → 整条 bar 弹性 swell（[_PressTransform]），透镜抬起并放大；
/// * 拖动 → 透镜跟手横移，速度越快拉得越扁（jelly，velocity 取自弹簧瞬时速度），
///   拖出两端有橡皮筋，整条 bar 也跟着横向拉伸；
/// * 松手 → 透镜吸附到最近一格并过冲回弹；甩动时按 [_kFlingProjection] 内的位移
///   预判落点，最多越过手指所在格一格；
/// * 桌面端鼠标 → 悬停高亮 + 透镜朝光标磁吸倾斜 + 内容视差。
///
/// 尺寸与安全区由调用方给：[height] 不含底部安全区，[bottomPadding] 会叠加在
/// 安全区之上。
class NavigationDock extends StatefulWidget {
  const NavigationDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.bottomPadding = kNavigationDockBottomPadding,
    this.height = kNavigationDockHeight,
    this.itemExtent = kNavigationDockItemExtent,
  }) : assert(destinations.length >= 2),
       assert(selectedIndex >= 0),
       assert(selectedIndex < destinations.length);

  final List<NavigationDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 胶囊与屏幕底部的间距，叠加在安全区之上。
  final double bottomPadding;

  /// 胶囊高度（不含底部安全区）。
  final double height;

  /// 每格宽度，同时是透镜静止时的宽度。
  final double itemExtent;

  @override
  State<NavigationDock> createState() => _NavigationDockState();
}

class _NavigationDockState extends State<NavigationDock>
    with TickerProviderStateMixin {
  late final _Spring _lens = _Spring(this, widget.selectedIndex.toDouble());
  late final _Spring _lift = _Spring(this, 0);
  late final _Spring _hover = _Spring(this, 0);
  late final _Spring _hoverShow = _Spring(this, 0);
  late final _Spring _swell = _Spring(this, 0);
  late final _Spring _stretch = _Spring(this, 0);
  late final Listenable _barMotion = Listenable.merge([_swell, _stretch]);
  late final Listenable _motion = Listenable.merge([_lens, _lift]);
  late final Listenable _hoverMotion = Listenable.merge([_hover, _hoverShow]);
  int? _pointer;
  int? _pressedIndex;
  double _pressX = 0;
  bool _dragging = false;
  VelocityTracker? _tracker;
  Offset? _cursor;
  final ValueNotifier<double?> _hoverAt = ValueNotifier(null);

  int get _lastIndex => math.max(0, widget.destinations.length - 1);

  int get _selectedIndex => widget.selectedIndex.clamp(0, _lastIndex);

  @override
  void didUpdateWidget(covariant NavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rest = _lensRest;
    // 按着的时候不动 —— 让拖拽接管，否则手指还在格子上透镜就跳走了。
    if (_pressedIndex == null && _lens.target != rest) {
      _lens.springTo(rest, _kSettleSpring);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _lift.dispose();
    _hover.dispose();
    _hoverShow.dispose();
    _swell.dispose();
    _stretch.dispose();
    _hoverAt.dispose();
    super.dispose();
  }

  /// 局部坐标 → 以第一格中心为 0 的位置（可越界，越界量交给橡皮筋）。
  double _positionAt(Offset localPosition) {
    final size = context.size!;
    return dockPositionAt(
      dx: localPosition.dx,
      barWidth: size.width,
      padding: _kBarPadding,
      count: widget.destinations.length,
      textDirection: Directionality.of(context),
    );
  }

  int _indexAt(double position) => position.round().clamp(0, _lastIndex);

  /// 朝光标倾一点（不是完全跟过去）。
  double _leanAt(double position) {
    final index = _indexAt(position);
    return index + (position - index) * _kHoverMagnet;
  }

  /// 透镜的静止位置：光标不在选中格上时就老老实实待在选中格。
  double get _lensRest {
    final hoverAt = _hoverAt.value;
    if (hoverAt == null || _indexAt(hoverAt) != _selectedIndex) {
      return _selectedIndex.toDouble();
    }
    return _leanAt(hoverAt);
  }

  void _leanLens() {
    if (_pressedIndex != null || _indexAt(_lens.target) != _selectedIndex) {
      return;
    }
    final rest = _lensRest;
    if (_lens.target != rest) {
      _lens.springTo(rest, _kHoverSpring);
    }
  }

  void _showHover() {
    final cursor = _cursor;
    if (cursor == null || _pointer != null || widget.destinations.isEmpty) {
      return;
    }
    final position = _positionAt(cursor);
    final target = _leanAt(position);
    _hoverAt.value = position;
    if (_hoverShow.target == 0 && _hoverShow.value == 0) {
      _hover.jumpTo(target);
    } else {
      _hover.springTo(target, _kHoverSpring);
    }
    _hoverShow.springTo(1, _kFadeSpring);
    _leanLens();
  }

  void _settleSwell() {
    final target = _cursor == null ? 0.0 : _kHoverSwell;
    if (_pointer == null && _swell.target != target) {
      _swell.springTo(target, _kSettleSpring);
    }
  }

  void _handleHover(PointerHoverEvent event) {
    // 引擎会在触摸落下前合成一次 hover，且触摸指针要等remove 才消失 ——
    // 不滤掉的话，点一下就会留下高亮。
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    _cursor = event.localPosition;
    _showHover();
    _settleSwell();
  }

  void _handleExit(PointerExitEvent event) {
    _cursor = null;
    _hoverShow.springTo(0, _kFadeSpring);
    _hoverAt.value = null;
    _leanLens();
    _settleSwell();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _hoverShow.springTo(0, _kFadeSpring);
    _hoverAt.value = null;
    _swell.springTo(1, _kLiftSpring);
    _press(event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _pointer) {
      _tracker?.addPosition(event.timeStamp, event.localPosition);
      _slide(event.localPosition);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null) {
      _fling(tracker.getVelocity().pixelsPerSecond.dx);
    }
    _release(commit: event is PointerUpEvent);
    _stretch.springTo(0, _kSettleSpring);
    if (_cursor != null) {
      _cursor = event.localPosition;
      _showHover();
    }
    _settleSwell();
  }

  void _press(Offset localPosition) {
    if (widget.destinations.isEmpty) {
      return;
    }
    final index = _indexAt(_positionAt(localPosition));
    _pressedIndex = index;
    _pressX = localPosition.dx;
    _dragging = false;
    _lift.springTo(1, _kLiftSpring);
    _lens.springTo(index.toDouble(), _kSettleSpring);
  }

  void _slide(Offset localPosition) {
    if (_pressedIndex == null) {
      return;
    }
    if (!_dragging) {
      if ((localPosition.dx - _pressX).abs() < kTouchSlop) {
        return;
      }
      _dragging = true;
    }
    final size = context.size!;
    final overshoot =
        localPosition.dx - localPosition.dx.clamp(0.0, size.width);
    _stretch.springTo(
      _rubberBand(overshoot, size.shortestSide * _kPullLimit),
      _kTrackSpring,
    );
    final position = _positionAt(localPosition);
    _lens.springTo(position, _kTrackSpring);
    final index = _indexAt(position);
    if (index != _pressedIndex) {
      HapticFeedback.selectionClick();
      _pressedIndex = index;
    }
  }

  /// 甩动落点：按 [_kFlingProjection] 内的位移预判，最多越过手指所在格一格 ——
  /// 无上限的话一次快速横扫能连跳好几格。
  void _fling(double velocityX) {
    final pressed = _pressedIndex;
    if (!_dragging || pressed == null) {
      return;
    }
    final extent =
        (context.size!.width - _kBarPadding * 2) / widget.destinations.length;
    final direction = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    final lead =
        velocityX /
        extent *
        direction *
        _kFlingProjection.inMicroseconds /
        Duration.microsecondsPerSecond;
    final index = (_lens.target + lead)
        .round()
        .clamp(pressed - 1, pressed + 1)
        .clamp(0, _lastIndex);
    if (index != pressed) {
      HapticFeedback.selectionClick();
      _pressedIndex = index;
    }
  }

  void _release({required bool commit}) {
    final index = _pressedIndex;
    if (index == null) {
      return;
    }
    _pressedIndex = null;
    _dragging = false;
    _lift.springTo(0, _kSettleSpring);
    if (!commit) {
      // 取消（手指被系统接管等）：弹回原来的选中格，不提交。
      _lens.springTo(_selectedIndex.toDouble(), _kSettleSpring);
      return;
    }
    _lens.springTo(index.toDouble(), _kSettleSpring);
    if (index != widget.selectedIndex) {
      widget.onDestinationSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: _kLabelSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final labels = [
      for (final destination in widget.destinations)
        _measureLabel(context, destination.label, labelStyle),
    ];
    final widest = labels.fold(
      0.0,
      (width, label) => math.max(width, label.width),
    );
    final lineHeight = labels.fold(
      0.0,
      (height, label) => math.max(height, label.height),
    );

    final width = widget.destinations.length * widget.itemExtent;
    final bar = DecoratedBox(
      decoration: ShapeDecoration(
        shape: _dockShape,
        shadows: _dockShadows(colorScheme),
      ),
      child: Material(
        color: colorScheme.surfaceContainer,
        shape: _dockShape,
        // 用裸指针事件而不是手势识别器：拖动在竞技场里抢不到任何对手，
        // 而等识别器胜出的 tap 会让透镜「迟到」才抬起。
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: MouseRegion(
            onHover: _handleHover,
            onExit: _handleExit,
            child: Padding(
              padding: const EdgeInsets.all(_kBarPadding),
              // RepaintBoundary 放在 LayoutBuilder 之上：重建它下面的东西会把
              // 约束传下去，那次重绘会波及整条 dock。
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final extent =
                        constraints.maxWidth /
                        math.max(1, widget.destinations.length);
                    final room = extent - _kLabelInset * 2;
                    // 放得下就正常字号；放不下先缩，但不低于 _kMinLabelSize，
                    // 再放不下就交给 Tooltip。
                    final labelScale = widest <= room
                        ? 1.0
                        : math.max(room / widest, _kMinLabelSize / _kLabelSize);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (widget.destinations.isNotEmpty)
                          AnimatedBuilder(
                            animation: _motion,
                            builder: (context, _) => _Lens(
                              position: _lens.value,
                              velocity: _lens.velocity,
                              extent: extent,
                              height: constraints.maxHeight,
                              lift: _lift.value,
                            ),
                          ),
                        if (widget.destinations.isNotEmpty)
                          AnimatedBuilder(
                            animation: _hoverMotion,
                            builder: (context, _) => _HoverHighlight(
                              position: _hover.value,
                              extent: extent,
                              opacity: _hoverShow.value,
                            ),
                          ),
                        Row(
                          children: [
                            for (final (index, destination)
                                in widget.destinations.indexed)
                              Expanded(
                                child: _FloatingBarItem(
                                  destination: destination,
                                  selected: index == _selectedIndex,
                                  index: index,
                                  lens: _lens,
                                  hoverAt: _hoverAt,
                                  lift: _lift,
                                  labelStyle: labelStyle?.copyWith(
                                    fontSize: _kLabelSize * labelScale,
                                  ),
                                  labelHeight: lineHeight,
                                  labelOverflows:
                                      labels[index].width * labelScale > room,
                                  onActivate: () =>
                                      widget.onDestinationSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        kNavigationDockShadowRoom,
        0,
        // 退出全屏后部分设备不再上报恢复后的系统栏高度，交给 SystemUiBottomInset 兜底
        widget.bottomPadding +
            SystemUiBottomInset.resolve(
              MediaQuery.viewPaddingOf(context).bottom,
              viewSize: MediaQuery.sizeOf(context),
            ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HitSlop(
            child: SizedBox(
              width: width,
              height: widget.height,
              child: AnimatedBuilder(
                animation: _barMotion,
                builder: (_, child) => _PressTransform(
                  lift: _swell.value,
                  pull: Offset(_stretch.value, 0),
                  child: child,
                ),
                child: RepaintBoundary(child: bar),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
