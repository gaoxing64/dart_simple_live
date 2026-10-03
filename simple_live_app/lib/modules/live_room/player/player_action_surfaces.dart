/// 播放器弹层的「本体」层：右侧抽屉／底部抽屉里真正放的那份内容。
///
/// 单独成文件是为了依赖方向：`player_action_views.dart` 的执行层要开这几个抽屉，
/// 而抽屉原先住在渲染层 `player_controls.dart` 里，views 一 import controls 就绕成
/// `views -> controls -> player_action_bar -> views` 这个环（Dart 允许它编译，但
/// renderer 与 views 之间再也说不清谁依赖谁）。本体归本体层：这一层只依赖 controller
/// 和容器 API，渲染层反过来 import 它，环即断开。
///
/// 约定：每个 `show*` 只决定「用哪种容器」（桌面右侧抽屉；竖屏主播与移动端落回底部
/// 抽屉），容器里的清单一律向 controller 取（`buildScaleModeRadioList`、
/// `buildDanmuSettingsBody`），同一个动作在两种宿主下才是同一份内容。
library;

import 'dart:io';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

void showLinesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayUrlsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "线路",
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.playUrls.length,
      itemBuilder: (_, i) {
        return ListTile(
          selected: controller.currentLineIndex == i,
          title: Text.rich(
            TextSpan(
              text: "线路${i + 1}",
              children: [
                WidgetSpan(
                    child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppStyle.radius4,
                    border: Border.all(
                      color: Colors.grey,
                    ),
                  ),
                  padding: AppStyle.edgeInsetsH4,
                  margin: AppStyle.edgeInsetsL8,
                  child: Text(
                    controller.playUrls[i].contains(".flv") ? "FLV" : "HLS",
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                )),
              ],
            ),
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            //controller.currentLineIndex = i;
            //controller.setPlayer();
            controller.changePlayLine(i);
          },
        );
      },
    ),
  );
}

void showQualitesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.qualites.length,
      itemBuilder: (_, i) {
        var item = controller.qualites[i];
        return ListTile(
          selected: controller.currentQuality == i,
          title: Text(
            item.quality,
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          trailing: IconButton(
            tooltip: "复制直链",
            icon: const Icon(Icons.copy),
            onPressed: () async {
              try {
                var playUrl = await controller.site.liveSite.getPlayUrls(
                    detail: controller.detail.value!, quality: item);
                if (playUrl.urls.isNotEmpty) {
                  Utils.copyToClipboard(playUrl.urls.first);
                  SmartDialog.showToast("已复制直链");
                } else {
                  SmartDialog.showToast("无法获取播放链接");
                }
              } catch (e) {
                SmartDialog.showToast("获取直链失败: $e");
              }
            },
          ),
          onTap: () {
            Utils.hideRightDialog();
            controller.currentQuality = i;
            controller.getPlayUrl();
          },
        );
      },
    ),
  );
}

void showDanmakuSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showDanmuSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "弹幕设置",
    width: 400,
    child: ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        // 本体向 controller 取（与画面尺寸那条同一个约定）：抽屉版此前自己抄了一份
        // `DanmuSettingsView`，少抄的正是 `onTapDanmuShield`——桌面从条带/⋮ 进弹幕
        // 设置就再也点不到「关键词屏蔽」这条入口了。收起的是抽屉本身，所以给
        // hideRightDialog 而不是 `Get.back`。
        controller.buildDanmuSettingsBody(
          onDismiss: Utils.hideRightDialog,
        ),
      ],
    ),
  );
}

void showPlayerSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "设置",
    width: 320,
    child: ListView(
      padding: AppStyle.edgeInsetsV12,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsH16,
          child: Text(
            "画面尺寸",
            style: Get.textTheme.titleMedium,
          ),
        ),
        // 单选列表本体与底部抽屉共用 controller 那一份（含 Task 7 的按格写入）：
        // 这里原先自己写了一份「只写全局」的 RadioGroup，多开中从这条路径进来
        // 会把刚设好的按格覆盖顶掉。
        controller.buildScaleModeRadioList(),
      ],
    ),
  );
}

/// 桌面「画面尺寸」动作的右侧抽屉（spec §3：清单类弹层统一成右侧抽屉）。
///
/// 竖屏主播落回底部抽屉——与 `showQualitesInfo` 改造前就有的兜底同一口径：
/// 竖屏画面又窄又高，右侧抽屉会盖住直播内容，底部抽屉从下方升起来不挡脸。
/// 这条兜底本次保留，不改成右侧。
void showScaleModeInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: controller.scaleModeSheetTitle,
    width: 320,
    child: ListView(
      padding: AppStyle.edgeInsetsV12,
      children: [controller.buildScaleModeRadioList()],
    ),
  );
}

void showFollowUser(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showFollowUserSheet();
    return;
  }

  Utils.showRightDialog(
    title: "关注列表",
    width: 400,
    child: Obx(
      () => Stack(
        children: [
          RefreshIndicator(
            onRefresh: FollowService.instance.loadData,
            child: ListView.builder(
              itemCount: FollowService.instance.liveList.length,
              itemBuilder: (_, i) {
                var item = FollowService.instance.liveList[i];
                return Obx(
                  () => FollowUserItem(
                    item: item,
                    playing: controller.rxSite.value.id == item.siteId && controller.rxRoomId.value == item.roomId,
                    onTap: () {
                      Utils.hideRightDialog();
                      controller.resetRoom(
                        Sites.allSites[item.siteId]!,
                        item.roomId,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Positioned(
              right: 12,
              bottom: 12,
              child: Obx(
                () => DesktopRefreshButton(
                  refreshing: FollowService.instance.updating.value,
                  onPressed: FollowService.instance.loadData,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
