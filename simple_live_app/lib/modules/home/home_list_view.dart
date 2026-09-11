import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';

/// 卡片最小宽度：列数 = 可用宽度 / 该值（沿用原 `width ~/ 200` 的密度）。
const double kMinCardWidth = 200;

/// 卡片间距，同时用于 `mainAxisSpacing` / `crossAxisSpacing`。
const double kCardSpacing = 12;

/// 网格行距 = [PageGridView] 的行高 + 行间距。
///
/// 行高直接取 [PageGridView.kDefaultItemExtent] 而不是抄一份魔数：抄的话
/// 那边一改，这里判断「内容填没填满」就会静默失配。
const double kRowPitch = PageGridView.kDefaultItemExtent + kCardSpacing;

/// 上下各 12 的 padding（AppStyle.edgeInsetsA12）。
const double kVerticalPadding = 24;

/// 列数上限。
///
/// 不设上限的话，3840 宽的窗口会排出 19 列（卡片宽只有 200、行高却固定
/// 168），行数太少反而更容易在竖直方向露白；封顶后卡片尺寸更接近常见桌面
/// 布局，也给「减列换行数」留出了空间。
const int kMaxColumns = 12;

/// 内容已到底时，最多允许把列数减少这么多去换行数。
///
/// 只做小幅微调：减太多会让卡片在宽屏上大得离谱，反而比例失调。
const int kMaxColumnReduction = 3;

/// 首页网格列数：先按宽度定；若内容已到底且填不满视口，再小幅减列换行数。
///
/// 为什么只在「已到底」时调整：还有下一页时 `list.length` 每页都在变，跟着改
/// 列数会边加载边重排。到底之后内容量固定，重排一次是稳定的。
///
/// 不额外传「是否正在加载」的原因：本函数只在 [Obx] 里被调用，而该 Obx 只
/// 订阅 `list.length` 与 `canLoadMore`，两者都在 `_doLoad` 收尾处才变，那时
/// `loadding` 已经归位。也就是说生产路径上不存在「加载中重算列数」的时刻，
/// 传一个不可观察的 `loading` 只会给人「已经防住了」的错觉。
///
/// 为什么不拉高卡片去填满：`itemExtent` 是紧约束，把卡片塞进更高的网格单元
/// 会溢出，而且各平台卡片高度不一致会破坏跨平台的视觉一致性。
///
/// [bottomInset] 是被悬浮底栏盖住的那段高度（见
/// [PageGridView.floatingBarInsetOf]），必须从可用高度里扣掉，否则会以为
/// 已经填满、不再减列，底部那片空白就留在那里了。
int resolveHomeColumns({
  required double maxWidth,
  required double maxHeight,
  required int itemCount,
  required bool canLoadMore,
  double bottomInset = 0,
}) {
  final byWidth =
      (maxWidth / kMinCardWidth).floor().clamp(2, kMaxColumns).toInt();

  if (itemCount == 0 || canLoadMore) {
    return byWidth;
  }

  // bottomInset 语义上非负（被悬浮底栏盖住的高度），但
  // PageGridView.floatingBarInsetOf 只是 `padding.bottom - viewPadding.bottom`：
  // 未 extendBody 时 padding.bottom 会被置 0，而 viewPadding.bottom 仍是系统 inset，
  // 二者之差为负（PageGridView / PageListView 里同一表达式都带 `> 0` 守卫）。
  // 负值会让可用高度不减反增，减列判断比预期更激进，与 doc 的语义相反。
  final usableHeight =
      maxHeight - kVerticalPadding - math.max(0, bottomInset);
  if (usableHeight <= 0) {
    return byWidth;
  }

  final minColumns = math.max(2, byWidth - kMaxColumnReduction);
  for (var columns = byWidth; columns >= minColumns; columns--) {
    final rows = (itemCount / columns).ceil();
    if (rows * kRowPitch >= usableHeight) {
      return columns;
    }
  }
  // 减到下限还是填不满：内容实在太少，别再牺牲排版了，交给底部「已到底」
  // 提示去解释那片空白。
  return byWidth;
}

class HomeListView extends StatelessWidget {
  final String tag;
  const HomeListView(this.tag, {super.key});
  HomeListController get controller => Get.find<HomeListController>(tag: tag);

  @override
  Widget build(BuildContext context) {
    return KeepAliveWrapper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 放进 Obx：列数依赖 list.length / canLoadMore，两者变化都要重算
          return Obx(
            () => PageGridView(
              pageController: controller,
              padding: AppStyle.edgeInsetsA12,
              firstRefresh: true,
              showEndBar: true,
              mainAxisSpacing: kCardSpacing,
              crossAxisSpacing: kCardSpacing,
              crossAxisCount: _resolveColumns(context, constraints),
              itemBuilder: (_, i) {
                var item = controller.list[i];
                return LiveRoomCard(controller.site, item);
              },
            ),
          );
        },
      ),
    );
  }

  int _resolveColumns(BuildContext context, BoxConstraints constraints) =>
      resolveHomeColumns(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
        itemCount: controller.list.length,
        canLoadMore: controller.canLoadMore.value,
        bottomInset: PageGridView.floatingBarInsetOf(context),
      );
}
