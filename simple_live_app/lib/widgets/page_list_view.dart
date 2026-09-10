import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/load_more_failed_bar.dart';
import 'package:simple_live_app/widgets/page_auto_load.dart';
import 'package:simple_live_app/widgets/skeleton.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/status/app_error_widget.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:get/get.dart';

class PageListView extends StatelessWidget {
  final BasePageController pageController;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsets? padding;
  final bool firstRefresh;
  final Function()? onLoginSuccess;
  final bool showPageLoadding;

  /// 加载下一页时底部占位的骨架，默认使用列表行骨架
  final IndexedWidgetBuilder? skeletonBuilder;
  const PageListView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.separatorBuilder,
    this.onLoginSuccess,
    this.skeletonBuilder,
    super.key,
  });

  /// 距底部多远开始自动加载下一页见 [kAutoLoadExtent]。

  @override
  Widget build(BuildContext context) {
    var effectivePadding = padding;
    if (effectivePadding != null) {
      // 悬浮底栏（Scaffold.extendBody）会把底栏高度计入 body 的
      // MediaQuery.padding.bottom；调用方传入显式 padding 会覆盖它，
      // 这里把这段额外高度补回 padding.bottom，避免最后一项被悬浮底栏遮住。
      var mediaQuery = MediaQuery.of(context);
      var floatingBarInset =
          mediaQuery.padding.bottom - mediaQuery.viewPadding.bottom;
      if (floatingBarInset > 0) {
        effectivePadding = effectivePadding.copyWith(
          bottom: effectivePadding.bottom + floatingBarInset,
        );
      }
    }
    return Obx(() {
      // 在 Obx 内取一次，保证 itemCount 与 itemBuilder 使用同一组索引，
      // 避免两处各自读 list.length / loadingMore 造成漂移
      final listLength = pageController.list.length;
      final skeletonCount = pageController.loadingMore.value ? 3 : 0;
      final showRetry = pageController.showLoadMoreFailedBar;
      return Stack(
        children: [
          AutoLoadOnScroll(
            pageController: pageController,
            child: EasyRefresh(
              // 只保留下拉刷新，不传 footer / onLoad——原因与 [PageGridView]
              // 一致：footer 默认 infiniteOffset = 0，刷新时列表清空、滚动
              // 位置恒在底部，会在 armed / processing 间反复切换导致指示器
              // 抽动。翻页由 AutoLoadOnScroll 承担。
              header: MaterialHeader(
                processedDuration: const Duration(milliseconds: 400),
              ),
              scrollController: pageController.scrollController,
              controller: pageController.easyRefreshController,
              refreshOnStart: firstRefresh,
              onRefresh: pageController.refreshData,
              child: ListView.separated(
                // 必须与 EasyRefresh 共用同一个 controller，见 PageGridView 说明
                controller: pageController.scrollController,
                padding: effectivePadding,
                itemCount: listLength + skeletonCount + (showRetry ? 1 : 0),
                itemBuilder: (context, index) {
                  // 重试条固定排在骨架之后（showRetry 与 loadingMore 互斥，
                  // 不会出现"骨架 + 重试条"同时在的怪状态）
                  if (showRetry && index == listLength + skeletonCount) {
                    return LoadMoreFailedBar(pageController: pageController);
                  }
                  // 加载下一页时在底部补几行骨架，提示用户正在加载
                  if (index >= listLength) {
                    return skeletonBuilder?.call(context, index) ??
                        const ListRowSkeleton();
                  }
                  return itemBuilder(context, index);
                },
                separatorBuilder:
                    separatorBuilder ?? (context, i) => const SizedBox(),
              ),
            ),
          ),
          Offstage(
            offstage: !pageController.pageEmpty.value,
            child: AppEmptyWidget(
              onRefresh: () => pageController.refreshData(),
            ),
          ),
          Offstage(
            offstage: !(showPageLoadding && pageController.pageLoadding.value),
            child: const AppLoaddingWidget(),
          ),
          Offstage(
            offstage: !pageController.pageError.value,
            child: AppErrorWidget(
              errorMsg: pageController.errorMsg.value,
              onRefresh: () => pageController.refreshData(),
            ),
          ),
        ],
      );
    });
  }
}
