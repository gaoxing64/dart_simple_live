import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/load_more_failed_bar.dart';
import 'package:simple_live_app/widgets/page_auto_load.dart';
import 'package:simple_live_app/widgets/page_end_bar.dart';
import 'package:simple_live_app/widgets/skeleton.dart';
import 'package:simple_live_app/widgets/ticker_offstage.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/status/app_error_widget.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:get/get.dart';

/// 分段模式的段基类：段头跨整行渲染在这一段上方；为空则不渲染。
abstract class PageGridSection {
  final Widget? header;
  const PageGridSection({this.header});
}

/// 网格里的一段：自带列数、行高、条目数、构建器和可选段头。
///
/// 存在的理由是关注页要把「正在直播的卡片网格」和「未开播的紧凑行」
/// 拼在同一屏里 —— 两段的列数与行高都不同，`PageGridView` 原本那个
/// 单 `SliverGrid` 表达不了（`crossAxisCount` / `mainAxisExtent` 都是单值）。
class GridSection extends PageGridSection {
  final int crossAxisCount;
  final double itemExtent;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  const GridSection({
    required this.crossAxisCount,
    required this.itemExtent,
    required this.itemCount,
    required this.itemBuilder,
    super.header,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
  });
}

/// 整段只有一个任意 widget（跨整行，`SliverToBoxAdapter`）。
///
/// 给关注页的分组折叠卡片用：卡片高度随折叠状态变化，塞不进固定
/// `itemExtent` 的 `SliverGrid`。
///
/// ⚠️ **不受「`itemCount == 0` 整段跳过」规则约束**（它没有 itemCount）：
/// 空的分组卡片也要渲染出来，它是拖拽归组的落点、也要让用户看得见组存在。
/// 要不要显示由调用方决定（比如搜索时不产出这一段）。
class BoxSection extends PageGridSection {
  final Widget child;
  const BoxSection({required this.child, super.header});
}

class PageGridView extends StatelessWidget {
  final BasePageController pageController;

  /// 单段模式的条目构建器。**传了 [sections] 时可以不传**（那时由各段自己的
  /// itemBuilder 负责）。
  final IndexedWidgetBuilder? itemBuilder;
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

  /// 水平间距。
  final double crossAxisSpacing;

  /// 竖直间距。
  ///
  /// ⚠️ 单段模式（[sections] 为空）下它是**网格行距**；分段模式下它被复用为
  /// **段与段之间的间距**，段内行距取 [GridSection.mainAxisSpacing]。
  /// 两者同名不同义，分段场景按「行距」的语义传值会静默变成段间距。
  final double mainAxisSpacing;

  /// 单段模式的列数。**传了 [sections] 时这个值不参与渲染**（各段自带列数）。
  final int crossAxisCount;

  /// 分段渲染（可选）。
  ///
  /// 给了它就按 [PageGridSection] 逐段渲染，**忽略 [itemExtent] / [crossAxisCount]
  /// 以及「按 pageController.list 长度补骨架」那套逻辑** —— 分段场景（关注页）
  /// 的两段条目数由调用方自己算，且它是一次性全量数据、没有下一页。
  /// 为空则沿用原来的单 `SliverGrid` 行为，首页 / 搜索 / 分类详情不受影响。
  final List<PageGridSection>? sections;

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

  /// 覆盖滚动/刷新控制器（关注页 TabBarView 用）。
  ///
  /// 关注页把「全部 / 直播中 / 未开播」拆成 [TabBarView] 的三页，三页共享同一份
  /// 数据与 [pageController]，但每页必须有**自己**的 `ScrollController` 与
  /// `EasyRefreshController`（`EasyRefreshController` 内部持有刷新状态，一个实例
  /// 不能同时挂多个 `EasyRefresh`；`ScrollController` 多客户端会直接抛）。
  /// 不传就沿用 [pageController] 自带的那一对，首页 / 搜索 / 分类等单列表页不受影响。
  final ScrollController? scrollOverride;
  final EasyRefreshController? refreshOverride;
  const PageGridView({
    this.itemBuilder,
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
    this.crossAxisCount = 1,
    this.sections,
    this.scrollOverride,
    this.refreshOverride,
    super.key,
  }) : assert(
          itemBuilder != null || sections != null,
          'PageGridView 需要 itemBuilder（单段模式）或 sections（分段模式）之一',
        );

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

  /// 分段模式的 sliver 列表。
  ///
  /// 横向内边距每段各自吃一份（单段模式是一个 `SliverPadding` 罩住整块网格）；
  /// 段与段之间留 [mainAxisSpacing] 的竖直间距，最外面补上 `gridPadding` 的上下边距
  /// —— 最后那段也必须吃到 `gridPadding.bottom`，否则滚到底会被悬浮胶囊导航栏盖住。
  ///
  /// 条目数为 0 的 [GridSection] **整段跳过（含段头）**：过滤或「隐藏离线关注」
  /// 之后留一个光秃秃的段头比不显示更奇怪。[BoxSection] 不受此规则约束
  /// （见其类注释），要不要显示由调用方决定。
  List<Widget> _buildSectionSlivers(EdgeInsets gridPadding) {
    final list = <Widget>[];
    final horizontal = EdgeInsets.only(
      left: gridPadding.left,
      right: gridPadding.right,
    );
    final visible = sections!
        .where((s) => s is! GridSection || s.itemCount > 0)
        .toList();
    for (var i = 0; i < visible.length; i++) {
      final section = visible[i];
      final isFirst = i == 0;
      final isLast = i == visible.length - 1;
      if (section.header != null) {
        list.add(
          SliverPadding(
            padding: horizontal.copyWith(
              top: isFirst ? gridPadding.top : mainAxisSpacing,
            ),
            sliver: SliverToBoxAdapter(child: section.header),
          ),
        );
      } else if (!isFirst) {
        list.add(
          SliverToBoxAdapter(child: SizedBox(height: mainAxisSpacing)),
        );
      }
      if (section case final BoxSection box) {
        list.add(
          SliverPadding(
            padding: horizontal.copyWith(
              top: isFirst && section.header == null ? gridPadding.top : 0,
            ),
            sliver: SliverToBoxAdapter(child: box.child),
          ),
        );
      } else if (section case final GridSection grid) {
        list.add(
          SliverPadding(
            padding: horizontal.copyWith(
              top: isFirst && section.header == null ? gridPadding.top : 0,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: grid.crossAxisCount,
                mainAxisSpacing: grid.mainAxisSpacing,
                crossAxisSpacing: grid.crossAxisSpacing,
                mainAxisExtent: grid.itemExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                grid.itemBuilder,
                childCount: grid.itemCount,
              ),
            ),
          ),
        );
      }
      if (isLast && gridPadding.bottom > 0) {
        list.add(
          SliverToBoxAdapter(child: SizedBox(height: gridPadding.bottom)),
        );
      }
    }
    return list;
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
              // （应用级 AppScrollBehavior 也做了同样的放开，见 main.dart；
              // 这里保留是因为 ERScrollBehavior 还负责去掉越界光晕与滚动条。）
              header: MaterialHeader(
                processedDuration: const Duration(milliseconds: 400),
              ),
              scrollController: scrollOverride ?? pageController.scrollController,
              controller: refreshOverride ?? pageController.easyRefreshController,
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
                controller: scrollOverride ?? pageController.scrollController,
                slivers: [
                  if (sections == null)
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
                            return itemBuilder!(context, index);
                          },
                          childCount: pageController.list.length +
                              (pageController.loadingMore.value
                                  ? crossAxisCount * 2
                                  : 0),
                        ),
                      ),
                    )
                  else
                    ..._buildSectionSlivers(gridPadding),
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
          TickerOffstage(
            offstage: !pageController.pageEmpty.value,
            child: AppEmptyWidget(
              onRefresh: () => pageController.refreshData(),
            ),
          ),
          TickerOffstage(
            offstage: !(showPageLoadding && pageController.pageLoadding.value),
            child: const AppLoaddingWidget(),
          ),
          TickerOffstage(
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
