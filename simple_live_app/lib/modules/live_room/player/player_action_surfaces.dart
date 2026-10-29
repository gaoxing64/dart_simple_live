/// 播放器弹层的「本体」层：右侧抽屉／底部抽屉里真正放的那份内容。
///
/// 单独成文件是为了依赖方向：`player_action_views.dart` 的执行层要开这几个抽屉，
/// 而抽屉原先住在渲染层 `player_controls.dart` 里，views 一 import controls 就绕成
/// `views -> controls -> player_action_bar -> views` 这个环（Dart 允许它编译，但
/// renderer 与 views 之间再也说不清谁依赖谁）。本体归本体层：这一层只依赖 controller
/// 和容器 API，渲染层反过来 import 它，环即断开。
///
/// 约定：每个 `show*` 只决定「用哪种容器」，本体不猜宿主——调用方（`invokePlayerAction`
/// 与各条 builder）按 `usesRightPanelSurface(host)` 传 [rightPanel]，竖屏主播另外有一条
/// 既有兜底：画面又窄又高，右侧面板会盖住直播内容，所以恒落底部抽屉。
/// 容器里的清单一律向 controller 取（`buildScaleModeRadioList`、`buildDanmuSettingsBody`），
/// 同一个动作在两种容器下才是同一份内容。
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
import 'package:simple_live_app/widgets/m3e_loading_indicator.dart';

/// [rightPanel]＝这份清单开成右侧面板还是底部抽屉（判据在调用方，见文件头约定）。
/// 默认 true：移动横屏全屏与桌面全屏／小窗／格子都吃默认，只有桌面窗口化显式传 false。
void showLinesInfo(LiveRoomController controller, {bool rightPanel = true}) {
  if (controller.isVertical.value || !rightPanel) {
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

void showQualitesInfo(
  LiveRoomController controller, {
  bool rightPanel = true,
}) {
  if (controller.isVertical.value || !rightPanel) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.qualities.length,
      itemBuilder: (_, i) {
        var item = controller.qualities[i];
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

/// 弹幕设置弹层。
///
/// [perStreamerShield] 由调用的那一层 surface 给：桌面条带／⋮（`invokePlayerAction`）
/// 要的是「这一格主播」的屏蔽面板，传 true。移动端横屏全屏的底栏（
/// `player_controls.dart` 的 `buildFullControls`）不传——移动端不进这套模型，那层在本体
/// 收拢之前就没有这条入口，点了落的是全局屏蔽设置页，行为必须逐位保持原样。
/// [rightPanel]＝容器（判据在调用方）；false 与竖屏主播同样落 `showDanmuSettingsSheet`，
/// 那条本体本来就带 perStreamerShield，所以这里不再往下传。
void showDanmakuSettings(
  LiveRoomController controller, {
  bool perStreamerShield = false,
  bool rightPanel = true,
}) {
  if (controller.isVertical.value || !rightPanel) {
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
          perStreamerShield: perStreamerShield,
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

/// 桌面「画面尺寸」动作的弹层。
///
/// 两条落回底部抽屉的路径同一口径：[rightPanel]＝false（桌面窗口化，右侧面板会盖住
/// 页面右栏）与竖屏主播（画面又窄又高，右侧面板会盖住直播内容）。改造前窗口化条带
/// 根本没有这颗，全屏的「更多设置」开的是右侧面板——所以判据在调用方，不在这里。
void showScaleModeInfo(
  LiveRoomController controller, {
  bool rightPanel = true,
}) {
  if (controller.isVertical.value || !rightPanel) {
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

/// 换台／关注列表：**只有右侧面板这一种容器**，所以它没有 `rightPanel` 参数。
///
/// 作者 2026-10-04 定的是「右侧面板仅在全屏时使用」＋「换台仅在全屏出现」
/// （见 `player_actions.dart` 的 `_available`：pick 只在 fullscreen 与 tile 在场），
/// 两条合起来＝这颗永远开在这块面板里，窗口化压根没有它。
/// ⚠️ 别顺手给它加底部抽屉：`showFollowUserSheet` 的行点击走 `multiPlay.onFollowItemTap`
/// （多开时问的是「加入哪一格」），而这块面板走 `resetRoom`（换掉当前这一路），语义不同。
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
            onRefresh: FollowService.instance.refresh,
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
          // 开播状态还没到（冷启动直接进直播间时 onInit 触发的那一轮）：
          // 空列表不等于「没人播」，先给加载反馈，别让人以为关注丢了。
          if (FollowService.instance.updating.value && FollowService.instance.liveList.isEmpty)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: M3ELoadingIndicator()),
              ),
            ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Positioned(
              right: 12,
              bottom: 12,
              child: Obx(
                () => DesktopRefreshButton(
                  refreshing: FollowService.instance.updating.value,
                  onPressed: FollowService.instance.refresh,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
