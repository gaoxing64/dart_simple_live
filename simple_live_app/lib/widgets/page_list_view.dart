import 'dart:io';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
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
  final bool showPCRefreshButton;

  /// 加载下一页时底部占位的骨架，默认使用列表行骨架
  final IndexedWidgetBuilder? skeletonBuilder;
  const PageListView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.showPCRefreshButton = true,
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
    return Obx(
      () => Stack(
        children: [
          AutoLoadOnScroll(
            pageController: pageController,
            child: EasyRefresh(
              header: MaterialHeader(
                processedDuration: const Duration(milliseconds: 400),
              ),
              footer: MaterialFooter(
                processedDuration: const Duration(milliseconds: 400),
              ),
              scrollController: pageController.scrollController,
              controller: pageController.easyRefreshController,
              refreshOnStart: firstRefresh,
              onLoad: () async {
                // 没有更多数据时不再请求，并告知 easy_refresh 停止触发
                if (!pageController.canLoadMore.value) {
                  return IndicatorResult.noMore;
                }
                await pageController.loadData();
                // 请求失败（或并发下没真正加载）时不要显示"加载成功"
                if (pageController.loadFailed) {
                  return IndicatorResult.fail;
                }
                return pageController.canLoadMore.value
                    ? IndicatorResult.success
                    : IndicatorResult.noMore;
              },
              onRefresh: pageController.refreshData,
              child: ListView.separated(
                padding: effectivePadding,
                itemCount: pageController.list.length +
                    (pageController.loadingMore.value ? 3 : 0),
                itemBuilder: (context, index) {
                  // 加载下一页时在底部补几行骨架，提示用户正在加载
                  if (index >= pageController.list.length) {
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: // 加载更多按钮
                Visibility(
              visible: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) &&
                  pageController.canLoadMore.value &&
                  !pageController.pageLoadding.value &&
                  !pageController.pageEmpty.value &&
                  // 自动加载中（底部有骨架占位）时隐藏按钮
                  !pageController.loadingMore.value,
              child: Center(
                child: TextButton(
                  onPressed: pageController.loadData,
                  child: const Text("加载更多"),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: // 加载更多按钮
                Visibility(
              visible: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) &&
                  pageController.canLoadMore.value &&
                  !pageController.pageLoadding.value &&
                  !pageController.pageEmpty.value &&
                  showPCRefreshButton,
              child: Center(
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Get.theme.cardColor.withAlpha(200),
                    elevation: 4,
                  ),
                  onPressed: () {
                    pageController.refreshData();
                  },
                  icon: const Icon(Icons.refresh),
                ),
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
      ),
    );
  }
}
