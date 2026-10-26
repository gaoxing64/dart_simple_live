import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';

/// Material 3 Expressive 风格的 loading 指示器。
///
/// 一个在若干 Material 形状之间连续变形、同时持续自转的图形，用来替代
/// 圆环形的 [CircularProgressIndicator]。形状序列、时序、缩放与弹簧曲线
/// 对齐 AOSP `material3/LoadingIndicator.kt`（Apache-2.0），多边形的几何
/// 运算由 `material_new_shapes` 提供。
///
/// 注意动画是无限循环的：放在常驻 `Offstage` 的三态切换里时，请配合
/// `TickerOffstage` 使用——本 widget 的 ticker 会随 `TickerMode` 一起停下。
class M3ELoadingIndicator extends StatefulWidget {
  const M3ELoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.polygons,
    this.semanticsLabel,
  })  : assert(size > 0),
        assert(polygons == null || polygons.length > 1);

  /// 正方形边长（逻辑像素）。图形本体的绘制直径约为 [size] 的 79%，
  /// 保证旋转与变形过程中不会被裁切。
  final double size;

  /// 图形颜色，默认取 [ProgressIndicatorThemeData.color]，
  /// 再回落到主题的 `colorScheme.primary`。
  final Color? color;

  /// 需要变形的形状序列，至少两个；默认使用 M3 loading 规范的 7 个形状。
  final List<RoundedPolygon>? polygons;

  /// 无障碍标签，默认「加载中」。
  final String? semanticsLabel;

  /// M3 loading 规范里的变形序列（与 AOSP 一致）。想在 [polygons] 里改序列时
  /// 可以基于它做增删。
  ///
  /// **不可变**：组件内部会按引用持有它，外部 add / remove 会污染所有正在
  /// 显示的实例（`_polygons` 已改，但已构建的 `_morphs` 还是旧形状，
  /// 渲染会前后矛盾）。
  /// ⚠️ 不能写 `const [...]`：`MaterialShapes.*` 是 `static final`，
  /// 不是编译期常量，加 `const` 会报「Constant evaluation error」。
  static final List<RoundedPolygon> defaultPolygons =
      List.unmodifiable([
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ]);

  /// 计算形状序列在容器内的缩放系数（≤ 1）。
  ///
  /// 直接按 [RoundedPolygon.calculateBounds] 缩放会在形状旋转到某些角度时被
  /// 裁切，所以要用 [RoundedPolygon.calculateMaxBounds] 对照。系数只减不增，
  /// 结果保证「静态包围盒 × 系数」不会超出归一化尺寸，绘制时不会溢出容器。
  static double scaleFactorFor(List<RoundedPolygon> polygons) {
    var factor = 1.0;
    for (final polygon in polygons) {
      final bounds = polygon.calculateBounds();
      final maxBounds = polygon.calculateMaxBounds();
      final scaleX = (bounds[2] - bounds[0]) / (maxBounds[2] - maxBounds[0]);
      final scaleY = (bounds[3] - bounds[1]) / (maxBounds[3] - maxBounds[1]);
      // 取 max 以兼顾 pill 这类长条形，避免整体被压得过小。
      factor = math.min(factor, math.max(scaleX, scaleY));
    }
    return factor;
  }

  @override
  State<M3ELoadingIndicator> createState() => _M3ELoadingIndicatorState();
}

class _M3ELoadingIndicatorState extends State<M3ELoadingIndicator>
    with TickerProviderStateMixin {
  /// 自转一圈的时间（AOSP 常量）。
  static const Duration _rotationDuration = Duration(milliseconds: 4666);

  /// 每两个形状之间的变形间隔（AOSP 常量）。
  static const Duration _morphInterval = Duration(milliseconds: 650);

  static const double _quarterTurn = 90;
  static const double _fullTurn = 360;

  /// 图形绘制尺寸 / 容器尺寸（AOSP：48 的容器内放 38 的活动尺寸）。
  static const double _activeSizeRatio = 38 / 48;

  /// AOSP 的变形曲线：阻尼比 0.6、刚度 200 的弹簧，末端吸附。
  static final SpringSimulation _morphSpring = SpringSimulation(
    SpringDescription.withDampingRatio(ratio: 0.6, stiffness: 200, mass: 1),
    0.0,
    1.0,
    5.0,
    snapToEnd: true,
  );

  /// ⚠️ 这三个**不能**声明成 `late final`：`didUpdateWidget` 里序列变化时
  /// 会重新赋值，`final` 的二次赋值会抛
  /// `LateInitializationError: Field '_polygons' has already been initialized`。
  late List<RoundedPolygon> _polygons;
  late List<Morph> _morphs;

  /// 归一化多边形缩放到容器内所需的系数（避免旋转时被裁切）。
  late double _shapeScale;

  /// 单次变形的进度，由弹簧驱动。
  late final AnimationController _morph;

  /// 持续自转。
  late final AnimationController _rotation;

  /// 变形节拍：每走完一轮触发下一次变形。
  late final AnimationController _metronome;

  /// 当前正在变形的形状对下标。
  int _index = 0;

  /// 累积的目标旋转角度，每次变形再加 90°。
  double _stepRotation = _quarterTurn;
  double _lastMetronome = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _setupPolygons();
    _morph = AnimationController.unbounded(vsync: this);
    _rotation = AnimationController(vsync: this, duration: _rotationDuration);
    _metronome = AnimationController(vsync: this, duration: _morphInterval)
      ..addListener(_onMetronome);
  }

  @override
  void didUpdateWidget(covariant M3ELoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 序列可能在运行期变化（按主题 / 配置切换形状）：形状对与缩放系数都是
    // 从序列算出来的，不重建会继续按旧形状渲染。
    if (widget.polygons != oldWidget.polygons) {
      _setupPolygons();
      // 变形进度回到第一对形状，避免下标越界 / 形状错位。
      _index = 0;
      _stepRotation = _quarterTurn;
      _morph
        ..value = 0
        ..animateWith(_morphSpring);
    }
  }

  /// 按 [widget.polygons] 重建形状对与缩放系数。
  ///
  /// 构造函数里只有 `assert(polygons.length > 1)`，release 构建会剥离断言：
  /// 传空列表会让 `_morphs` 为空、build 里 `_morphs[_index]` 每帧抛 RangeError；
  /// 长度 1 则退化为形状自己变形给自己。这里兜底回默认序列。
  void _setupPolygons() {
    final polygons = widget.polygons;
    _polygons = (polygons == null || polygons.length < 2)
        ? M3ELoadingIndicator.defaultPolygons
        : polygons;
    _morphs = [
      for (var i = 0; i < _polygons.length; i++)
        Morph(_polygons[i], _polygons[(i + 1) % _polygons.length]),
    ];
    _shapeScale = M3ELoadingIndicator.scaleFactorFor(_polygons);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开启「减弱动态效果」时只画静态图形，不做无限动画。
    if (_reduceMotion) {
      _stop();
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    _metronome.dispose();
    _rotation.dispose();
    _morph.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _start() {
    if (_running) return;
    _running = true;
    _rotation.repeat();
    _metronome.repeat();
    _lastMetronome = 0;
    _morph
      ..value = 0
      ..animateWith(_morphSpring);
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    _metronome.stop();
    _rotation.stop();
    _morph.stop();
  }

  /// 节拍器每次回绕代表一个变形周期结束，切到下一对形状。
  void _onMetronome() {
    final value = _metronome.value;
    if (value < _lastMetronome) {
      _nextShape();
    }
    _lastMetronome = value;
  }

  void _nextShape() {
    _index = (_index + 1) % _morphs.length;
    _stepRotation = (_stepRotation + _quarterTurn) % _fullTurn;
    _morph
      ..value = 0
      ..animateWith(_morphSpring);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        ProgressIndicatorTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    final reduceMotion = _reduceMotion;

    return Semantics(
      label: widget.semanticsLabel ?? "加载中",
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_morph, _rotation]),
            builder: (context, child) {
              final progress = _morph.value.clamp(0.0, 1.0);
              final rotation = reduceMotion
                  ? 0.0
                  : progress * _quarterTurn +
                      _stepRotation +
                      _rotation.value * _fullTurn;
              return Transform.rotate(
                angle: rotation * math.pi / 180,
                child: CustomPaint(
                  painter: _MorphPainter(
                    morph: _morphs[_index],
                    progress: progress,
                    // 减弱动态效果时固定展示首个形状。
                    staticShape: reduceMotion ? _polygons.first : null,
                    color: color,
                    scaleFactor: _shapeScale * _activeSizeRatio,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.morph,
    required this.progress,
    required this.color,
    required this.scaleFactor,
    this.staticShape,
  });

  final Morph morph;
  final double progress;
  final RoundedPolygon? staticShape;
  final Color color;
  final double scaleFactor;

  /// 复用同一个 [Morph]，每帧把 [progress] 转成路径再绘制。
  @override
  void paint(Canvas canvas, Size size) {
    final shape = staticShape;
    final path = shape != null
        ? shape.toPath()
        : morph.toPath(progress: progress);

    // 归一化多边形的坐标约在 1×1 的范围内，乘上 size 即目标尺寸；
    // 再按实际 bounds 中心回正，兼容不以原点为中心的图形。
    final center = path.getBounds().center;
    final scale = size.width * scaleFactor;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) {
    return oldDelegate.morph != morph ||
        oldDelegate.progress != progress ||
        oldDelegate.staticShape != staticShape ||
        oldDelegate.color != color ||
        oldDelegate.scaleFactor != scaleFactor;
  }
}
