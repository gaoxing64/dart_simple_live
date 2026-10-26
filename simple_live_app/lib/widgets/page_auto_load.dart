import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';

/// 距底部多远开始自动加载下一页。
const double kAutoLoadExtent = 200;

/// 把"会改 Rx 状态"的动作挪到帧外执行。
///
/// 滚动通知经常在 layout 阶段派发：内容尺寸变化走
/// [ScrollMetricsNotification]，惯性滚动收尾也会在 `RenderViewport`
/// 布局时派发 `ScrollStartNotification`。此时若同步执行
/// `loadData()` / 写 `loadMoreFailed`，会立刻让 [Obx] `markNeedsBuild`，
/// Flutter 随即抛出 "Build scheduled during frame"。
///
/// 这不是偶发——桌面默认窗口 1280×720、6 列、首页 30 条约 5 行，
/// `extentAfter` 约 180 < [kAutoLoadExtent]，首屏数据一到达就会命中。
///
/// 推迟一个微任务即可避开：微任务要等当前帧的同步调用栈跑完才执行，
/// 那时改状态是合法的；代价只有一次事件循环，而 `loadding` 守卫仍在，
/// 同一帧内的重复通知依旧只会真正加载一次。
void outsideFrame(void Function() action) {
  if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
    action();
    return;
  }
  scheduleMicrotask(action);
}

/// 接近底部时自动加载下一页，返回是否发起了加载。
///
/// 这是翻页的**唯一**触发路径。
///
/// 原项目使用 flutter_easyrefresh，其 MaterialFooter 默认
/// `enableInfiniteLoad = true`：滑到（接近）底部就会自动加载。
/// 迁移到 easy_refresh 后该行为丢失（默认必须越界下拉且距离足够才触发，
/// 表现为"触底后还要再滑一下"），且 easy_refresh 的 `infiniteOffset`
/// 只在触摸滚动时生效——鼠标滚轮走的是 `forcePixels`，不会经过
/// `applyBoundaryConditions`，滚轮永远触发不了。
/// 因此统一用滚动通知驱动：触摸拖动、惯性滚动、鼠标滚轮都能自动加载。
///
/// 后来连 footer 本身也一并移除了（`PageGridView` / `PageListView` 不再传
/// `footer` 与 `onLoad`）：footer 默认 `infiniteOffset = 0`，会在刷新把列表
/// 清空时于 armed / processing 之间反复切换，导致底部指示器抽动。既然翻页
/// 已由这里独家负责，footer 就成了纯粹的风险源。
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
    // 一并收起重试条：离开底部等于重新武装自动重试。
    // ⚠️ 内容不满一屏时 extentAfter 恒为 0，走不到这里——
    // 这正是短列表失败后重试条必须常驻的原因。
    outsideFrame(() => pageController.loadMoreFailed.value = false);
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
  outsideFrame(pageController.loadData);
  return true;
}

/// 内容填不满视口时主动补页，返回是否发起了加载。
///
/// 为什么需要它：[autoLoadIfNeeded] 依赖滚动通知，而 Flutter 只在
/// `extentBefore` / `extentInside` / `extentAfter` 变化时才派发通知
/// （见 `ScrollPosition._isMetricsChanged`）。当列表内容不足一屏时
/// `maxScrollExtent` 恒为 0、`pixels` 恒为 0、视口尺寸不变，这三项在
/// "空列表 → 首页数据到达"前后**完全一致**，通知永远不会派发，于是：
///
/// * 首屏只铺两三行就停住，必须手动点"加载更多"才能填满窗口；
/// * 内容不够高时列表不可滚动，滚轮再怎么拨也不会产生滚动事件；
/// * 窗口最大化后列数变多、行数变少，下方留白同样不会被补齐。
///
/// 这里绕开通知机制，在布局完成后直接读 [ScrollController.position]
/// 判断。守卫条件复用 [autoLoadIfNeeded]，两处判断不会漂移。
bool fillViewportIfNeeded(BasePageController pageController) {
  final controller = pageController.scrollController;
  if (!controller.hasClients) {
    return false;
  }
  final position = controller.position;
  // 首次布局完成前读取 extentAfter 会触发断言
  if (!position.hasContentDimensions) {
    return false;
  }
  return autoLoadIfNeeded(pageController, position);
}

/// 把滚动通知接到 [autoLoadIfNeeded] 上，并在每次布局后主动补页。
///
/// 同时监听 [ScrollNotification]（拖动/惯性/滚轮）与
/// [ScrollMetricsNotification]（内容尺寸变化，例如窗口缩放、骨架占位增减）。
///
/// [LayoutBuilder] 负责捕获视口尺寸变化（窗口缩放 / 最大化）后重新评估；
/// 普通 rebuild 则覆盖列表增删与骨架增减。
class AutoLoadOnScroll extends StatefulWidget {
  final BasePageController pageController;
  final Widget child;
  const AutoLoadOnScroll({
    required this.pageController,
    required this.child,
    super.key,
  });

  @override
  State<AutoLoadOnScroll> createState() => _AutoLoadOnScrollState();
}

class _AutoLoadOnScrollState extends State<AutoLoadOnScroll> {
  /// 同一帧只排一次检查，避免 build 被反复触发时堆积回调。
  bool _fillCheckScheduled = false;

  /// 布局完成后再检查：此时 [ScrollPosition] 才拿到本次布局的 maxScrollExtent。
  ///
  /// 补页会让 `list` / `loadingMore` 变化，进而再次 rebuild 并调度下一次
  /// 检查，自然形成"补一页 → 再看是否填满"的循环；循环由
  /// `canLoadMore == false`、`loadFailed` 或"内容已超出视口"终止。
  void _scheduleFillCheck() {
    if (_fillCheckScheduled) {
      return;
    }
    _fillCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillCheckScheduled = false;
      if (!mounted) {
        return;
      }
      fillViewportIfNeeded(widget.pageController);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFillCheck();
    return LayoutBuilder(
      builder: (context, constraints) {
        // 约束变化（窗口缩放、列数变化）时重新检查
        _scheduleFillCheck();
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            autoLoadIfNeeded(widget.pageController, notification.metrics);
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              autoLoadIfNeeded(widget.pageController, notification.metrics);
              return false;
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
