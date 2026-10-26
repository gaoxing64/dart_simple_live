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

  @override
  Widget build(BuildContext context) {
    var roomRowCount = MediaQuery.sizeOf(context).width ~/ 200;
    if (roomRowCount < 2) roomRowCount = 2;

    var userRowCount = MediaQuery.sizeOf(context).width ~/ 500;
    if (userRowCount < 1) userRowCount = 1;

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
              itemBuilder: (_, index) {
                final item = controller.list[index];
                return LiveRoomCard(item.site, item.room!);
              },
            )
          : PageGridView(
              pageController: controller,
              padding: AppStyle.edgeInsetsA12,
              firstRefresh: false,
              showEndBar: true,
              crossAxisSpacing: 12,
              crossAxisCount: userRowCount,
              itemExtent: 76,
              skeletonBuilder: (_, __) => const ListRowSkeleton(),
              itemBuilder: (_, index) {
                final site = controller.list[index].site;
                final item = controller.list[index].anchor!;

                return ListTile(
                  leading: NetImage(
                    item.avatar,
                    width: 48,
                    height: 48,
                    borderRadius: 24,
                  ),
                  title: Text(item.userName),
                  subtitle: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(site.name),
                      AppStyle.hGap8,
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.liveStatus ? Colors.green : Colors.grey,
                          borderRadius: AppStyle.radius12,
                        ),
                      ),
                      AppStyle.hGap4,
                      Text(
                        item.liveStatus ? "直播中" : "未开播",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          color: item.liveStatus ? null : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    AppNavigator.toLiveRoomDetail(
                      site: site,
                      roomId: item.roomId,
                    );
                  },
                );
              },
            ),
    );
  }
}
