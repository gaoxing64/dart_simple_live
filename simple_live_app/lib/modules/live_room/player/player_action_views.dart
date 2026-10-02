import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';

/// 动作 id → 真实调用。
///
/// [target] 是这一路（窗口化/全屏＝页面主格，多开时＝聚焦格；格子＝本格），
/// [page] 恒是页面主格：窗口级动作（小窗、全屏、定时关闭）只能由它执行，
/// 四路各跑一份倒计时或直接 `exit(0)` 是不能接受的。
/// 窗口级旗标也只有 page 那份会被真正写入，判断状态同样读 page（见 smallWindow 分支）。
void invokePlayerAction({
  required LiveRoomController target,
  required LiveRoomController page,
  required PlayerActionId id,
}) {
  switch (id) {
    case PlayerActionId.refresh:
      target.refreshRoom();
    case PlayerActionId.danmakuToggle:
      target.showDanmakuState.value = !target.showDanmakuState.value;
    case PlayerActionId.danmakuSettings:
      target.showDanmuSettingsSheet();
    case PlayerActionId.screenshot:
      target.saveScreenshot();
    case PlayerActionId.quality:
      target.showQualitySheet();
    case PlayerActionId.line:
      target.showPlayUrlsSheet();
    case PlayerActionId.scale:
      target.showPlayerSettingsSheet();
    case PlayerActionId.smallWindow:
      // 小窗态下同一个位置的动作是「退出小窗」，由 renderer 换 title，这里只看状态。
      // WHY 旗标读 page 而不是 target：这两面旗标只被「调用的接收者」写
      // （enterFullScreen/exitFull/enterSmallWindow 写自己的，见
      // player_controller.dart:615/689/773/836），而多开下窗口级调用全走 page
      // （multi_play_tile.dart:93/241、live_room_page.dart:111），副格的旗标恒为
      // false。读 target 会恒走「进入」分支：退不出去，还会在已全屏时重跑
      // _captureNormalGeometry（player_controller.dart:631）把还原几何覆盖成满屏
      // 矩形。状态与调用同一个控制器，renderer 换 title 才用得上同一个读法。
      if (page.smallWindowState.value) {
        page.exitSmallWindow();
      } else {
        page.enterSmallWindow();
      }
    case PlayerActionId.fullscreenToggle:
      if (page.fullScreenState.value) {
        page.exitFull();
      } else {
        page.enterFullScreen();
      }
    case PlayerActionId.debugInfo:
      target.showDebugInfo();
    case PlayerActionId.autoExit:
      page.showAutoExitSheet();
    case PlayerActionId.share:
      target.share();
    case PlayerActionId.copyUrl:
      target.copyUrl();
    case PlayerActionId.openApp:
      target.openNaviteAPP();
    case PlayerActionId.pick:
    case PlayerActionId.volume:
    case PlayerActionId.closeTile:
      // pick 与 volume 是锚定控件，renderer 直接画对应 widget，不走这里；
      // closeTile 需要格子的 index，由 renderer 闭包带走。
      break;
  }
}

/// `⋮` 的内容：桌面右侧抽屉，按清单顺序列出「图标 + 标题」。
///
/// 抽屉自带返回按钮（`Utils.showRightDialog` 的头），点外部是否关闭沿用现有行为，
/// 本次不改。移动端不会走到这里（平台门短路）。
///
/// [items] 允许直接把 resolver 的 `layout.overflow` 递进来，所以这里必须自己滤掉
/// 三类「在抽屉里点不动」的行：`pick`/`volume` 是锚定控件、`closeTile` 需要格子的
/// index，它们在 `invokePlayerAction` 里刻意是 no-op（见那里的注释）。不滤就渲染出
/// 一排「看得见、点了没反应」的死行。滤完为空则整颗 `⋮` 不弹，避免只有头的空抽屉。
void showActionMenu({
  required String title,
  required List<PlayerAction> items,
  required void Function(PlayerActionId) onSelect,
}) {
  final rows =
      items
          .where(
            (item) =>
                item.id != PlayerActionId.pick &&
                item.id != PlayerActionId.volume &&
                item.id != PlayerActionId.closeTile,
          )
          .toList();
  if (rows.isEmpty) {
    return;
  }
  Utils.showRightDialog(
    title: title,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final item in rows)
          ListTile(
            leading: Icon(playerActionIcon(item.id)),
            title: Text(item.title),
            onTap: () {
              Utils.hideRightDialog();
              onSelect(item.id);
            },
          ),
      ],
    ),
  );
}

/// 动作 → 图标表，条带与 `⋮` 抽屉共用同一份：同一个动作在两个宿主里要长一样。
/// 弹幕开关在条带里由 renderer 换成 asset 的 `ImageIcon`，与本表无关。
IconData playerActionIcon(PlayerActionId id) {
  return switch (id) {
    PlayerActionId.refresh => Icons.refresh,
    PlayerActionId.danmakuToggle => Icons.chat_bubble_outline,
    PlayerActionId.danmakuSettings => Icons.tune,
    PlayerActionId.screenshot => Icons.camera_alt_outlined,
    PlayerActionId.pick => Icons.playlist_play,
    PlayerActionId.quality => Icons.high_quality,
    PlayerActionId.line => Icons.switch_video_outlined,
    PlayerActionId.scale => Icons.aspect_ratio_outlined,
    PlayerActionId.smallWindow => Icons.picture_in_picture,
    PlayerActionId.fullscreenToggle => Icons.fullscreen,
    PlayerActionId.closeTile => Icons.close,
    PlayerActionId.debugInfo => Icons.info_outline_rounded,
    PlayerActionId.autoExit => Icons.timer_outlined,
    PlayerActionId.share => Icons.share,
    PlayerActionId.copyUrl => Icons.copy,
    PlayerActionId.openApp => Icons.open_in_new,
    PlayerActionId.volume => Icons.volume_up,
  };
}

/// 换台：把这一格／这一路换成关注列表里另一个正在直播的直播间。
///
/// 数据源就是 `MultiPlaySession.buildSwitchEntries()`——非多开时它的 slots 只有页面主格
/// 自己，所以单画面也能直接用同一个列表，`playingSlot >= 0` 即「已在本会话里播」。
/// 换台走 `replaceTileRoom`：它在单画面下等价于 `resetRoom`（主格也在自己的 slots 里），
/// 命中别的格子时只把焦点移过去，不建第二个实例。
///
/// 菜单开着时 [onOpened] 要把网格的自动隐藏倒计时续上；宿主侧必须常挂这个按钮
/// （`IgnorePointer` + 淡出），否则 `showButtonMenu` 的 `.then` 会因 unmount 丢掉选中结果。
class FollowPickButton extends StatelessWidget {
  const FollowPickButton({
    super.key,
    required this.target,
    required this.icon,
    this.style,
    this.iconSize,
    this.tooltip = "换台",
    this.onOpened,
  });

  final LiveRoomController target;
  final Widget icon;
  final ButtonStyle? style;
  final double? iconSize;
  final String tooltip;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FollowUser>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      iconSize: iconSize,
      style: style,
      icon: icon,
      onOpened: onOpened,
      itemBuilder: (context) {
        // 在菜单打开时才扫关注列表：放在 build 里，四格每帧都要扫一遍
        final entries = target.multiPlay.buildSwitchEntries();
        if (entries.isEmpty) {
          return const [
            AppPopupMenuItem<FollowUser>(
              enabled: false,
              child: SizedBox(
                width: 220,
                child: Text("关注列表里没有正在直播的主播"),
              ),
            ),
          ];
        }
        return [
          for (final entry in entries)
            AppPopupMenuItem<FollowUser>(
              value: entry.user,
              // 定宽：菜单容器宽度可能是无界的，Expanded 撞上无界约束会直接报错
              child: SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.user.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.platform,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (entry.isPlaying) ...[
                      const SizedBox(width: 6),
                      const Text("在播", style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
        ];
      },
      onSelected: (user) {
        final site = Sites.allSites[user.siteId];
        if (site == null) {
          return;
        }
        target.multiPlay.replaceTileRoom(target, site, user.roomId);
      },
    );
  }
}
