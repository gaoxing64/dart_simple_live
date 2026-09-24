import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';
import 'package:simple_live_app/modules/debug/glass_debug/glass_debug_controller.dart';
import 'package:simple_live_app/widgets/bar_collapse.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({super.key});

  /// 切换时的视差幅度（占页面宽/高的比例）
  static const double _parallaxFraction = 0.08;

  /// 悬浮胶囊导航栏（移植自 PiliPlus）
  ///
  /// 开启 Liquid Glass 后整条底栏（胶囊 + 图标文字 + 选中药丸）改由
  /// liquid_glass_easy 绘制（见 [FloatingNavigationBar.liquidGlass]）。
  Widget _buildFloatingNavBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final settings = AppSettingsController.instance;
      final useGlass = settings.liquidGlassEffect.value;
      // Debug 构建下接入调试页参数，供浅色模式可读性调优
      final debug = useGlass && GlassDebugController.enabled
          ? GlassDebugController.instance
          : null;
      return Center(
        // heightFactor: 1 防止 Center 占满 Scaffold 底栏槽位高度；
        // Center 同时让胶囊按内容宽度居中，不被槽位的紧约束拉成整屏宽
        heightFactor: 1,
        child: FloatingNavigationBar(
          selectedIndex: controller.index.value,
          onDestinationSelected: controller.setIndex,
          liquidGlass: useGlass,
          liquidGlassItemPadding: debug?.itemPadding.value ??
              kFloatingNavBarLiquidGlassItemPadding,
          liquidGlassStyle: debug?.buildBarStyle(),
          liquidGlassItemStyle: debug?.buildItemStyle(
            selectedColor: colors.primary,
            unselectedColor: colors.onSurfaceVariant,
          ),
          liquidGlassPillStyle: debug?.buildPillStyle(colors.brightness),
          destinations: controller.items
              .map(
                (item) => FloatingNavigationDestination(
                  icon: Icon(item.iconData),
                  label: item.title,
                ),
              )
              .toList(),
        ),
      );
    });
  }

  Widget _buildDefaultNavBar() {
    return Obx(() {
      final selectedIndex = controller.index.value;
      final nav = NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: controller.setIndex,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: controller.items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.iconData),
                label: item.title,
              ),
            )
            .toList(),
      );
      // Material NavigationBar 内部用 SafeArea 避让系统栏，退出全屏后部分设备不再
      // 上报恢复后的底部 inset，这里把解析后的高度补进 MediaQuery 交给它
      // （见 SystemUiBottomInset）
      return Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final bottom = SystemUiBottomInset.resolve(
            mediaQuery.padding.bottom,
            systemBar: mediaQuery.viewPadding.bottom,
            viewSize: mediaQuery.size,
          );
          if (bottom <= mediaQuery.padding.bottom) {
            return nav;
          }
          return MediaQuery(
            data: mediaQuery.copyWith(
              padding: mediaQuery.padding.copyWith(bottom: bottom),
              viewPadding: mediaQuery.viewPadding.copyWith(
                bottom: math.max(mediaQuery.viewPadding.bottom, bottom),
              ),
            ),
            child: nav,
          );
        },
      );
    });
  }

  /// 底栏收起容器（即时=动画，同步=跟随偏移）。
  ///
  /// 收起必须**纯绘制**（[BarCollapse] 只做平移+裁剪，盒子尺寸恒定）：
  /// 底栏处在 `Scaffold.bottomNavigationBar` 槽位里，一旦它的高度发生变化，
  /// Scaffold 就会重新布局 body —— 而 body 是整个页面（含滚动列表）。
  /// 同步模式下这个高度每帧都在变，等于每帧把最重的子树多排一次，安卓上直接掉帧。
  /// 现在槽位高度恒定，Scaffold 只在真正需要时布局一次。
  Widget _buildBottomBar(Widget nav) {
    var settings = AppSettingsController.instance;
    return Obx(() {
      if (!settings.hideBottomBar.value) {
        return nav;
      }
      if (settings.barHideType.value == 0) {
        // 即时
        var show = controller.showBottomBar.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: show ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubicEmphasized,
          builder: (_, factor, child) => BarCollapse(
            factor: factor,
            fromTop: false,
            child: child!,
          ),
          child: nav,
        );
      }
      // 同步
      return Obx(
        () => BarCollapse(
          factor:
              1 - controller.barOffset.value / IndexedController.maxBarOffset,
          fromTop: false,
          child: nav,
        ),
      );
    });
  }

  /// 给单个页面套上 [SlideTransition]。
  ///
  /// [PageView] 负责整页平移（Material 的 slide 过渡本身就是它），这里再让
  /// 内容相对页面容器反向位移一小段：新页滑入时内容略微滞后、旧页滑出时略微
  /// 领先，形成 parallax 层次感。位移量跟随 `PageController.page`，切页结束
  /// 自然归零；静止时 [AnimatedBuilder] 收不到通知，不产生额外重建。
  ///
  /// [pageIndex] 是该页在 [PageView] 里的位置，和 `controller.index`（当前选中的
  /// 导航项）不是一回事，别混用。
  Widget _buildTransitionPage(Axis axis, int pageIndex, Widget child) {
    return AnimatedBuilder(
      animation: controller.pageController,
      builder: (context, inner) {
        var delta = 0.0;
        final pageController = controller.pageController;
        if (pageController.hasClients &&
            pageController.position.haveDimensions) {
          final page = pageController.page;
          if (page != null) {
            delta = (page - pageIndex).clamp(-1.0, 1.0);
          }
        }
        final shift = -delta * _parallaxFraction;
        return SlideTransition(
          position: AlwaysStoppedAnimation<Offset>(
            axis == Axis.vertical ? Offset(0, shift) : Offset(shift, 0),
          ),
          child: inner,
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final navBarStyle = AppSettingsController.instance.navBarStyle.value;
      return OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          // 导航入口在左边（横屏的 NavigationRail）就上下切换，在下面（竖屏的
          // 底部导航栏）就左右切换——滑动方向始终与导航栏所在位置一致。
          final axis = isLandscape ? Axis.vertical : Axis.horizontal;
          return Scaffold(
            // 竖屏下 body 一律延伸到导航栏下方（两种导航栏样式都是）：
            // * 底栏收起是纯绘制的平移，槽位高度恒定（见 [_buildBottomBar]），
            //   而 `extendBody` 让 body 的约束不再依赖底栏高度 —— 两者合起来
            //   保证同步模式下底栏每帧变化**不会**触发 body 重排；
            // * 底栏滑出后，让出的那条空间由内容（列表）自己补上，而不是露出底色。
            // 底栏高度会通过 MediaQuery.padding.bottom 传给页面，列表自己留白
            // （`PageGridView.floatingBarInsetOf` / 各页显式 padding）。
            extendBody: orientation == Orientation.portrait,
            body: NotificationListener<ScrollNotification>(
              onNotification: controller.onScrollNotification,
              child: Row(
                children: [
                  Visibility(
                    visible: orientation == Orientation.landscape,
                    child: Obx(
                      () => NavigationRail(
                        selectedIndex: controller.index.value,
                        onDestinationSelected: controller.setIndex,
                        labelType: NavigationRailLabelType.none,
                        destinations: controller.items
                            .map(
                              (item) => NavigationRailDestination(
                                icon: Icon(item.iconData),
                                label: Text(item.title),
                                padding: AppStyle.edgeInsetsV8,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Obx(
                      () => Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: orientation == Orientation.landscape
                                ? BorderSide(
                                    color: Colors.grey.withAlpha(50),
                                    width: 1,
                                  )
                                : BorderSide.none,
                          ),
                        ),
                        // PageView 是惰性视口：默认 allowImplicitScrolling=false，
                        // 缓存范围为 0 个视口，只 inflate / 布局当前页。
                        // IndexedStack 只省绘制不省布局（RenderIndexedStack 的
                        // performLayout 继承 RenderStack，仍会布局全部子节点），
                        // 切过几个 Tab 后每次改窗口尺寸都要布局所有页面。
                        // children 每次都是新列表快照：PageView 内部用
                        // SliverChildListDelegate，其 shouldRebuild 是引用比较，
                        // 且 PageView 文档要求传入的 children 之后不得再被改动；
                        // 生成过程会读 pages.length / pages[i]，让这个 Obx 依赖
                        // pages，setIndex 里惰性填充 pages[i] 后能重建。
                        child: _JumpTransition(
                          controller: controller,
                          axis: axis,
                          child: PageView(
                            controller: controller.pageController,
                            // 方向跟着导航栏位置走：侧边栏在左 → 垂直滑动；
                            // 底栏在下 → 水平滑动。换轴不会丢页码，见
                            // IndexedController.pageController 的文档注释
                            scrollDirection: axis,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (var i = 0; i < controller.pages.length; i++)
                                _buildTransitionPage(
                                  axis,
                                  i,
                                  controller.pages[i],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: orientation == Orientation.portrait
                ? _buildBottomBar(
                    switch (navBarStyle) {
                      1 => _buildFloatingNavBar(context),
                      _ => _buildDefaultNavBar(),
                    },
                  )
                : null,
          );
        },
      );
    });
  }
}

/// 跨多个 Tab 跳切（如「首页 → 分类」）时的视口过渡：滑入 + 淡入。
///
/// 跳切走的是 [PageController.jumpToPage] 瞬时定位（为什么不用 animateToPage
/// 见 `IndexedController.jumpTick`），动静全靠这里补：按
/// [IndexedController.jumpDirection] 从来向滑入一小段，位移量与顺序切换的视差
/// [IndexedPage._parallaxFraction] 同量级，同时淡入，避免「点一下整屏瞬移」。
///
/// 过渡只作用在 [PageView] 这个视口容器上，且包装层必须常驻（见 [build] 里的
/// 说明）：外层 Element 一旦被换掉，PageView 会卸载重挂，而 [PageController]
/// 在拿不到旧 position 时按 `initialPage` 起算 —— 页码会被打回第一页。
class _JumpTransition extends StatefulWidget {
  const _JumpTransition({
    required this.controller,
    required this.axis,
    required this.child,
  });

  final IndexedController controller;
  final Axis axis;
  final Widget child;

  @override
  State<_JumpTransition> createState() => _JumpTransitionState();
}

class _JumpTransitionState extends State<_JumpTransition> with SingleTickerProviderStateMixin {
  /// 起始不透明度。不取 0：整页全透明的那一帧会露出 Scaffold 底色，闪一下。
  static const double _minOpacity = 0.6;

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: IndexedController.jumpTransitionDuration,
    // 静止在终态：没有跳切时这一层不出力
    value: 1,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _animation,
    curve: IndexedController.pageTransitionCurve,
  );

  Worker? _jumpWorker;

  /// 本次跳切的位移起点（单位尺寸的比例），静止态无意义。
  ///
  /// 在跳切那一刻从控制器取方向，不能挪进 [build] 现算：承载 [PageView] 的那个
  /// Obx 只依赖 `pages`，切到已经实例化过的 Tab 时（`pages` 没变）不会重建，
  /// 现算就会沿上一次的方向滑，方向是反的。
  Offset _travel = Offset.zero;

  void _onJump(int _) {
    final sign = widget.controller.jumpDirection.value;
    final magnitude = IndexedPage._parallaxFraction;
    _travel = widget.axis == Axis.vertical
        ? Offset(0, sign * magnitude)
        : Offset(sign * magnitude, 0);
    // forward 会同步把进度打回 0 并通知，下面那层随即用新起点重建
    _animation.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _jumpWorker = ever<int>(widget.controller.jumpTick, _onJump);
  }

  @override
  void dispose() {
    _jumpWorker?.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final progress = _progress.value;
        // ⚠️ 这两层必须**常驻**，不能按 `progress >= 1` 省略：子树结构一变，
        // 同位置的 Element 就对不上，PageView 会被卸载重挂 —— 重挂时新
        // Scrollable 先 attach、旧的后 detach，中途 `PageController` 挂着两个
        // position，页内 `_buildTransitionPage` 读 `position` 会撞上断言；而且
        // 重挂后 PageController 拿不到旧 position，会退回 initialPage。
        // 静止态下 opacity=1、位移=0，两层都不产生实际效果。
        return Opacity(
          opacity: _minOpacity + (1 - _minOpacity) * progress,
          child: FractionalTranslation(
            // 与 `_buildTransitionPage` 同口径：位移是单位尺寸的比例，不是像素
            translation: _travel * (1 - progress),
            child: child!,
          ),
        );
      },
      // 视口外层统一挂滚轮兜底（见 [_WheelBarFallback]）：放在这里而不是各个
      // 列表里，是因为它要在**所有**页内滚动区之后补位，同时又在 shell 的
      // PageView 之内；页面自己的列表、AppBar 上的滚轮都能覆盖到。
      child: _WheelBarFallback(
        controller: widget.controller,
        child: widget.child,
      ),
    );
  }
}

/// 滚轮兜底：列表滚不动时，把这一格增量交给顶/底栏收起。
///
/// `Scrollable` 只在「这一格确实会滚动」时才参与 `pointerSignalResolver` 竞争
/// （`_receivedPointerSignal` 的前置判断），贴边 / 内容不足一屏时它直接弃权 ——
/// 事件既不滚动、也不派发任何滚动通知，同步模式的顶/底栏就永远收不到驱动。
/// 表现就是用户看到的那条：页面留白（内容不足一屏）时，滚轮怎么滚都拉不出被
/// 隐藏的「关注用户」抬头，只有拖动越界能拉出来。
///
/// 这里以**后注册**的方式补位：解析器「先注册者胜」，列表真的能滚动时它的回调
/// 已经占了位，我们的注册会被忽略 —— 不会和滚动通知重复驱动栏位。
///
/// 接住之后怎么走见 [IndexedController.onWheelUnconsumed]：同步模式按距离并自己
/// 补一条过渡动画（列表滚不动时没有滚动动画可搭），即时模式只认方向。
class _WheelBarFallback extends StatelessWidget {
  final IndexedController controller;
  final Widget child;

  const _WheelBarFallback({
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        // 栏位只跟竖向滚动走；横向滚轮（含水平滚动区里的事件）不参与。
        final delta = event.scrollDelta.dy;
        if (delta == 0) {
          return;
        }
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (_) => controller.onWheelUnconsumed(delta),
        );
      },
      child: child,
    );
  }
}
