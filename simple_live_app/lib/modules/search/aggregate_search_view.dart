import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/aggregate_search_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_app/widgets/skeleton.dart';

class AggregateSearchView extends StatelessWidget {
  const AggregateSearchView({super.key});

  AggregateSearchController get controller =>
      Get.find<AggregateSearchController>(tag: AggregateSearchController.tag);

  /// 按条目**自带的数据**渲染，不按当前模式猜类型。
  ///
  /// 猜类型就得写 `item.room!` / `item.anchor!`：模式切换与列表清空之间一旦出现
  /// 混排，强解包直接 Null check 崩溃、整页红屏，而这个不变量视图侧看不见也不设防。
  Widget _itemWidget(AggregateSearchItem item) {
    final room = item.room;
    if (room != null) {
      return LiveRoomCard(item.site, room);
    }
    final anchor = item.anchor;
    if (anchor == null) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: NetImage(
        anchor.avatar,
        width: 48,
        height: 48,
        borderRadius: 24,
      ),
      title: Text(anchor.userName),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.site.name),
          AppStyle.hGap8,
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: anchor.liveStatus ? Colors.green : Colors.grey,
              borderRadius: AppStyle.radius12,
            ),
          ),
          AppStyle.hGap4,
          Text(
            anchor.liveStatus ? "直播中" : "未开播",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: anchor.liveStatus ? null : Colors.grey,
            ),
          ),
        ],
      ),
      onTap: () {
        AppNavigator.toLiveRoomDetail(
          site: item.site,
          roomId: anchor.roomId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var roomRowCount = AppStyle.gridRowCount(
      MediaQuery.sizeOf(context).width,
      itemWidth: 200,
      minCount: 2,
    );

    var userRowCount = AppStyle.gridRowCount(
      MediaQuery.sizeOf(context).width,
      itemWidth: 500,
      minCount: 1,
    );

    return Obx(
      () => controller.searchMode.value == 0
          ? PageGridView(
              pageController: controller,
              padding: AppStyle.edgeInsetsA12,
              firstRefresh: false,
              showEndBar: true,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              crossAxisCount: roomRowCount,
              showPageLoadding: true,
              itemBuilder: (_, index) => _itemWidget(controller.list[index]),
            )
          : PageGridView(
              pageController: controller,
              padding: AppStyle.edgeInsetsA12,
              firstRefresh: false,
              showEndBar: true,
              crossAxisSpacing: 12,
              crossAxisCount: userRowCount,
              itemExtent: 76,
              showPageLoadding: true,
              skeletonBuilder: (_, __) => const ListRowSkeleton(),
              itemBuilder: (_, index) => _itemWidget(controller.list[index]),
            ),
    );
  }
}
