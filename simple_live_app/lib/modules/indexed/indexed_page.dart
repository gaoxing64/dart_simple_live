import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';
import 'package:simple_live_app/modules/debug/glass_debug/glass_debug_controller.dart';
import 'package:simple_live_app/widgets/collapse_slot.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({super.key});

  /// 切换时的视差幅度（占页面宽/高的比例）
  static const double _parallaxFraction = 0.08;

  /// 悬浮胶囊导航栏（移植自 PiliPlus）
  ///
  /// 开启 Liquid Glass 后只替换胶囊背景，布局、指示器与交互
  /// 仍然全部走悬浮胶囊自身的实现。
  Widget _buildFloatingNavBar() {
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
          liquidGlassSettings: debug?.buildSettings(),
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

  /// 底栏收起容器（即时=动画，同步=跟随偏移）
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
          builder: (_, factor, child) => CollapseSlot(
            factor: factor,
            alignment: Alignment.topCenter,
            child: child!,
          ),
          child: nav,
        );
      }
      // 同步
      var factor =
          1 - controller.barOffset.value / IndexedController.maxBarOffset;
      return CollapseSlot(
        factor: factor,
        alignment: Alignment.topCenter,
        child: nav,
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
      // 悬浮样式：内容延伸到导航栏下方（Scaffold 会把它计入 body 的
      // MediaQuery.padding.bottom，页面自行留白即可）
      final useFloatingNavBar = navBarStyle != 0;
      return OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          // 导航入口在左边（横屏的 NavigationRail）就上下切换，在下面（竖屏的
          // 底部导航栏）就左右切换——滑动方向始终与导航栏所在位置一致。
          final axis = isLandscape ? Axis.vertical : Axis.horizontal;
          return Scaffold(
            extendBody:
                orientation == Orientation.portrait && useFloatingNavBar,
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
                        child: PageView(
                          controller: controller.pageController,
                          // 方向跟着导航栏位置走：侧边栏在左 → 垂直滑动；
                          // 底栏在下 → 水平滑动。换轴不会丢页码，见
                          // IndexedController.pageController 的文档注释
                          scrollDirection: axis,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (var i = 0; i < controller.pages.length; i++)
                              _buildTransitionPage(axis, i, controller.pages[i]),
                          ],
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
                      1 => _buildFloatingNavBar(),
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
