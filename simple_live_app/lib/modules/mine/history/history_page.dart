import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/history/history_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_app/widgets/skeleton.dart';
import 'package:simple_live_app/widgets/ui/secondary_tap_region.dart';

class HistoryPage extends GetView<HistoryController> {
  const HistoryPage({super.key});

  /// 删除前的确认弹窗。
  ///
  /// 左滑（[Dismissible.confirmDismiss]）、长按、桌面端右键三个入口共用同一份
  /// 文案与判据；只有「删除动作本身」各自执行一次，避免同一条记录被删两次。
  Future<bool> confirmRemove() async {
    return await Utils.showAlertDialog("确定要删除此记录吗?", title: "删除记录");
  }

  @override
  Widget build(BuildContext context) {
    var rowCount = MediaQuery.of(context).size.width ~/ 500;
    if (rowCount < 1) rowCount = 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text("观看记录"),
        actions: [
          TextButton.icon(
            onPressed: controller.clean,
            icon: const Icon(Icons.delete_outline),
            label: const Text("清空"),
          ),
        ],
      ),
      body: PageGridView(
        crossAxisSpacing: 12,
        crossAxisCount: rowCount,
        pageController: controller,
        firstRefresh: true,
        // 列表样式条目（ListTile 约 72 高），行高不能沿用卡片默认值 168
        itemExtent: 76,
        skeletonBuilder: (_, __) => const ListRowSkeleton(),
        itemBuilder: (_, i) {
          var item = controller.list[i];
          var site = Sites.allSites[item.siteId]!;

          // 删除记录：左滑 / 长按 / 桌面端右键共用同一个入口
          Future<void> removeRecord() async {
            if (!await confirmRemove()) {
              return;
            }
            controller.removeItem(item);
          }

          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              padding: AppStyle.edgeInsetsA12,
              alignment: Alignment.centerRight,
              child: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) => confirmRemove(),
            onDismissed: (_) {
              controller.removeItem(item);
            },
            // ListTile 本身不支持次要点击，补一层让桌面端右键也能删除
            child: SecondaryTapRegion(
              onSecondaryTap: removeRecord,
              child: ListTile(
                leading: NetImage(
                  item.face,
                  width: 48,
                  height: 48,
                  borderRadius: 24,
                ),
                title: Text(item.userName),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Image.asset(
                            site.logo,
                            width: 20,
                          ),
                          AppStyle.hGap4,
                          Text(
                            site.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Utils.parseTime(item.updateTime),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                onTap: () {
                  AppNavigator.toLiveRoomDetail(
                      site: site, roomId: item.roomId);
                },
                onLongPress: removeRecord,
              ),
            ),
          );
        },
      ),
    );
  }
}
