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

class PageGridView extends StatelessWidget {
  final BasePageController pageController;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets? padding;
  final bool firstRefresh;
  final Function()? onLoginSuccess;
  final bool showPageLoadding;
  final double crossAxisSpacing, mainAxisSpacing;
  final int crossAxisCount;

  /// 加载下一页时底部占位的骨架，默认按 [itemExtent] 选择卡片骨架或行骨架
  final IndexedWidgetBuilder? skeletonBuilder;

  /// 每行卡片的固定高度。
  ///
  /// 网格使用普通布局（非瀑布流）：行从左到右依次填充，最后一行不满时
  /// 空位只出现在右侧。瀑布流会按"最矮列"填充，列高不齐时条目会散落在
  /// 不同高度，加载区与已加载区交界处尤其明显。
  ///
  /// 默认值对应 [LiveRoomCard] 的自然高度；列表样式条目（如 `ListTile`）
  /// 必须显式传入自己的行高，否则行会被拉高、行间出现过大空隙。
  final double itemExtent;
  const PageGridView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.onLoginSuccess,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
    this.skeletonBuilder,
    this.itemExtent = 168,
    required this.crossAxisCount,
    super.key,
  });

  /// 行高小于该值时默认改用 [ListRowSkeleton]。
  ///
  /// [LiveRoomCardSkeleton] 内容高约 160，而 `mainAxisExtent` 是**紧**高度
  /// 约束：把卡片骨架放进更矮的网格单元会触发 RenderFlex 溢出。
  /// 显式传入 [skeletonBuilder] 时以调用方为准。
  static const double _cardSkeletonMinExtent = 160;

  Widget _buildSkeleton(BuildContext context, int index) {
    if (skeletonBuilder != null) {
      return skeletonBuilder!(context, index);
    }
    return itemExtent >= _cardSkeletonMinExtent
        ? const LiveRoomCardSkeleton()
        : const ListRowSkeleton();
  }

  @override
  Widget build(BuildContext context) {
    var effectivePadding = padding;
    if (effectivePadding != null) {
      // 悬浮底栏（Scaffold.extendBody）会把底栏高度计入 body 的
      // MediaQuery.padding.bottom；调用方传入显式 padding 会覆盖它，
      // 这里把这段额外高度补回 padding.bottom，避免最后一行被悬浮底栏遮住。
      var mediaQuery = MediaQuery.of(context);
      var floatingBarInset =
          mediaQuery.padding.bottom - mediaQuery.viewPadding.bottom;
      if (floatingBarInset > 0) {
        effectivePadding = effectivePadding.copyWith(
          bottom: effectivePadding.bottom + floatingBarInset,
        );
      }
    }
    final gridPadding = effectivePadding ?? EdgeInsets.zero;
    return Obx(
      () => Stack(
        children: [
          AutoLoadOnScroll(
            pageController: pageController,
            child: EasyRefresh(
              // 只保留下拉刷新。不传 footer / onLoad 是有意为之：
              // easy_refresh 的 Footer 默认 infiniteOffset = 0，触底即自动
              // 触发 onLoad；而刷新瞬间列表被清空、内容高度为 0，滚动位置
              // 恒在底部，footer 会在 armed / processing 之间反复切换——
              // 表现为底部指示器疯狂抽动且页面空白。翻页已由
              // AutoLoadOnScroll（滚动通知 + 布局后主动补页）独家承担，
              // 不需要第二条触发路径。onLoad 为 null 时 easy_refresh 会自动
              // 使用不可见的 NotLoadFooter，上拉不再出现第二个指示器。
              //
              // 下拉刷新在桌面端可用鼠标拖拽触发：easy_refresh 的
              // ERScrollBehavior 把 dragDevices 放开为全部指针设备。
              header: MaterialHeader(
                processedDuration: const Duration(milliseconds: 400),
              ),
              scrollController: pageController.scrollController,
              controller: pageController.easyRefreshController,
              refreshOnStart: firstRefresh,
              onRefresh: pageController.refreshData,
              // 普通网格（按行从左到右）。加载下一页时把骨架按顺序追加为
              // 网格条目：骨架会先补齐真实内容最后一行右侧的空位，再往下续整行，
              // 交界处不会留空。不使用瀑布流：瀑布流按"最矮列"填充，
              // 列高不齐时条目会散落在不同高度、交界处留空。
              child: CustomScrollView(
                // EasyRefresh 只监听这个 controller、不会注入给 child。
                // child 若不使用它，controller 就永远 attach 不上
                // （hasClients 恒为 false），主动补页与 scrollToTop 都会失效。
                controller: pageController.scrollController,
                slivers: [
                  SliverPadding(
                    padding: gridPadding,
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: mainAxisSpacing,
                        crossAxisSpacing: crossAxisSpacing,
                        mainAxisExtent: itemExtent,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // 加载下一页时在底部补骨架（两行），提示用户正在加载
                          if (index >= pageController.list.length) {
                            return _buildSkeleton(context, index);
                          }
                          return itemBuilder(context, index);
                        },
                        childCount: pageController.list.length +
                            (pageController.loadingMore.value
                                ? crossAxisCount * 2
                                : 0),
                      ),
                    ),
                  ),
                  // 加载失败重试条：作为列表最后一个条目内联展示，
                  // 不用 Positioned 悬浮层（那会盖住最后一行内容）
                  if (pageController.showLoadMoreFailedBar)
                    SliverToBoxAdapter(
                      child: LoadMoreFailedBar(pageController: pageController),
                    ),
                ],
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
