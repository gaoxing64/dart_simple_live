import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';

/// 距底部多远开始自动加载下一页。
const double kAutoLoadExtent = 200;

/// 接近底部时自动加载下一页，返回是否发起了加载。
///
/// 原项目使用 flutter_easyrefresh，其 MaterialFooter 默认
/// `enableInfiniteLoad = true`：滑到（接近）底部就会自动加载。
/// 迁移到 easy_refresh 后该行为丢失（默认必须越界下拉且距离足够才触发，
/// 表现为"触底后还要再滑一下"），且 easy_refresh 的 `infiniteOffset`
/// 只在触摸滚动时生效——鼠标滚轮走的是 `forcePixels`，不会经过
/// `applyBoundaryConditions`，滚轮永远触发不了。
/// 因此统一用滚动通知驱动：触摸拖动、惯性滚动、鼠标滚轮都能自动加载。
///
/// [PageGridView] 与 [PageListView] 共用这里的实现，避免两处守卫条件漂移。
bool autoLoadIfNeeded(
  BasePageController pageController,
  ScrollMetrics metrics,
) {
  if (metrics.axis != Axis.vertical) {
    return false;
  }
  // 远离底部：解除"失败后不自动重试"的门闩，用户再次触底时可以重试
  if (metrics.extentAfter > kAutoLoadExtent) {
    pageController.loadFailed = false;
    return false;
  }
  if (pageController.list.isEmpty) {
    return false;
  }
  if (!pageController.canLoadMore.value || pageController.loadding) {
    return false;
  }
  // 上一次加载失败后不再自动重试：失败会让底部骨架消失、内容高度收缩，
  // Flutter 随后派发 ScrollMetricsNotification，这里会被再次调用，
  // 形成"请求失败 → 重试 → 再失败"的请求风暴。
  if (pageController.loadFailed) {
    return false;
  }
  pageController.loadData();
  return true;
}

/// 把滚动通知接到 [autoLoadIfNeeded] 上。
///
/// 同时监听 [ScrollNotification]（拖动/惯性/滚轮）与
/// [ScrollMetricsNotification]（内容尺寸变化，例如窗口缩放、骨架占位增减）。
class AutoLoadOnScroll extends StatelessWidget {
  final BasePageController pageController;
  final Widget child;
  const AutoLoadOnScroll({
    required this.pageController,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        autoLoadIfNeeded(pageController, notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          autoLoadIfNeeded(pageController, notification.metrics);
          return false;
        },
        child: child,
      ),
    );
  }
}
