import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/load_more_failed_bar.dart';
import 'package:simple_live_app/widgets/page_auto_load.dart';
import 'package:simple_live_app/widgets/page_end_bar.dart';
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

  /// 是否在列表已到底时展示「已到底」提示条。
  ///
  /// 只对「会翻到尽头」的流式列表开启（首页 / 搜索 / 分类详情）。关注页、
  /// 历史记录是一次性全量数据，末尾显示「没有更多了」没有意义。
  ///
  /// 判据是 [BasePageController.showEndBar]，即「已经没有下一页」，与平台无关。
  final bool showEndBar;

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
  /// 默认值 [kDefaultItemExtent] 对应 [LiveRoomCard] 的自然高度；列表样式
  /// 条目（如 `ListTile`）必须显式传入自己的行高，否则行会被拉高、
  /// 行间出现过大空隙。
  final double itemExtent;
  const PageGridView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.showEndBar = false,
    this.onLoginSuccess,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
    this.skeletonBuilder,
    this.itemExtent = kDefaultItemExtent,
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

  /// 默认行高，对应 [LiveRoomCard] 的自然高度。
  ///
  /// 公开出来是为了让调用方在按视口推算排版（例如首页决定列数）时
  /// 不必再抄一份魔数——抄一份的话，这里一改就会静默失配。
  static const double kDefaultItemExtent = 168;

  /// 悬浮底栏（`Scaffold.extendBody`）给 body 额外带来的底部高度。
  ///
  /// 调用方若在 `LayoutBuilder` 里按约束高度推算可用空间（例如首页判断
  /// 「内容能不能填满视口」来决定列数），必须减掉这一段，否则会高估可用高度、
  /// 以为已经填满，底部那片被悬浮导航栏盖住的空间就没人管了。
  static double floatingBarInsetOf(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.padding.bottom - mediaQuery.viewPadding.bottom;
  }

  @override
  Widget build(BuildContext context) {
    var effectivePadding = padding;
    if (effectivePadding != null) {
      // 悬浮底栏（Scaffold.extendBody）会把底栏高度计入 body 的
      // MediaQuery.padding.bottom；调用方传入显式 padding 会覆盖它，
      // 这里把这段额外高度补回 padding.bottom，避免最后一行被悬浮底栏遮住。
      final floatingBarInset = floatingBarInsetOf(context);
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
                  // 尾部提示条（加载失败重试条 / 已到底条）必须跟着网格一起
                  // 让开悬浮底栏：上面的 SliverPadding 只把底部内边距加在了
                  // 网格自己身上，若把这两条直接追加在它之后，滚到底时它们会
                  // 正好落进悬浮胶囊导航栏（Scaffold.extendBody）覆盖的区域，
                  // 整条被遮住看不见。
                  if (pageController.showLoadMoreFailedBar)
                    SliverPadding(
                      padding: EdgeInsets.only(bottom: gridPadding.bottom),
                      sliver: SliverToBoxAdapter(
                        child:
                            LoadMoreFailedBar(pageController: pageController),
                      ),
                    ),
                  // 已到底提示条。与上面的重试条互斥（一个要 canLoadMore 为
                  // true、一个要为 false），不会同时出现。
                  if (showEndBar && pageController.showEndBar)
                    SliverPadding(
                      padding: EdgeInsets.only(bottom: gridPadding.bottom),
                      sliver: const SliverToBoxAdapter(child: PageEndBar()),
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
