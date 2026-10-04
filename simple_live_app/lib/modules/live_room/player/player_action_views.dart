import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_session.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_surfaces.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';

/// 动作 id → 真实调用。
///
/// [target] 是这一路（窗口化/全屏＝页面主格，多开时＝聚焦格；格子＝本格），
/// [page] 恒是页面主格：窗口级动作（小窗、全屏、定时关闭）只能由它执行，
/// 四路各跑一份倒计时或直接 `exit(0)` 是不能接受的。
/// 窗口级旗标也只有 page 那份会被真正写入，判断状态同样读 page（见 smallWindow 分支）。
///
/// [host] 只用来决定**清单类弹层开成哪种容器**（[usesRightPanelSurface]）：动作本身与
/// 宿主无关，容器有关——改造前就是窗口化底部抽屉、全屏右侧面板两套并存。
void invokePlayerAction({
  required PlayerHost host,
  required LiveRoomController target,
  required LiveRoomController page,
  required PlayerActionId id,
}) {
  final rightPanel = usesRightPanelSurface(
    host,
    isDesktop: AppSettingsController.isDesktop,
  );
  switch (id) {
    case PlayerActionId.refresh:
      target.refreshRoom();
    case PlayerActionId.danmakuToggle:
      target.showDanmakuState.value = !target.showDanmakuState.value;
    case PlayerActionId.danmakuSettings:
      // 容器跟着宿主走（见函数头的 [host]）：桌面窗口化落底部抽屉，全屏／小窗／格子
      // 落右侧面板。竖屏主播在这些实现内部另外还有一条落底部抽屉的兜底。
      // perStreamerShield 在这条臂上恒 true：调到这里的一定是桌面／格子那几层，
      // 要的是这一格主播自己的屏蔽面板（移动端横屏全屏那层不走这里，见平台门）。
      showDanmakuSettings(
        target,
        perStreamerShield: true,
        rightPanel: rightPanel,
      );
    case PlayerActionId.screenshot:
      target.saveScreenshot();
    case PlayerActionId.quality:
      showQualitesInfo(target, rightPanel: rightPanel);
    case PlayerActionId.line:
      showLinesInfo(target, rightPanel: rightPanel);
    case PlayerActionId.scale:
      showScaleModeInfo(target, rightPanel: rightPanel);
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
        // 退出全屏只是把窗口收回常态，不是「换了一路」，所以焦点一律不动。
        page.exitFull();
      } else {
        // 双击/全屏那一路要先成为焦点，否则侧栏与音量权威跟着别的流走。
        // 走会话已有的 focusSlot 这条路，不在格子侧另造一套聚焦机制。
        final session = page.multiPlay;
        if (target != page) {
          final index = session.slots.indexOf(target);
          if (index >= 0) {
            session.focusSlot(index);
          }
        }
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
      // 换台点开的是**右侧面板**（作者定：这块带头像+刷新+「在播」的面板比锚定小列表好用，
      // 锚定那份只适合多开的格子）。它现在也只在全屏与格子在场
      // （`_available` 的 pick 分支），所以这里不需要 [rightPanel] 那条分叉。
      showFollowUser(target);
    case PlayerActionId.volume:
    case PlayerActionId.muteTile:
      // volume 那颗是悬停/点击锚定件、closeTile 需要格子的 index，两者都由 renderer
      // 直接画，不走这里（见 actionableMenuItems：它俩也不会出现在抽屉里）。
      // muteTile 反过来：它就是给 `⋮` 抽屉用的一行，写的量与桌面那颗点音量完全相同
      // （`toggleMute` 落 `_owner.volumeFactor`，不落盘），两条入口共用一个权威。
      target.toggleMute();
    case PlayerActionId.closeTile:
      break;
  }
}

/// `⋮` 抽屉真正会列出来的行。
///
/// **[items] 与抽屉内容之间的唯一判定**：`volume` 是悬停锚定件、`closeTile` 需要格子的
/// index，两类在 `invokePlayerAction` 里刻意是 no-op（见那里的注释），放进抽屉就是
/// 「看得见、点了没反应」的死行，所以要滤掉。
///
/// `pick`（换台）**不在过滤名单里**：它现在是一条普通的「点开右侧面板」动作，
/// 与清晰度／线路同类，抽屉里那一行点了有真实去处。
///
/// WHY 对外暴露：条带上的 `⋮` 按钮和 `showActionMenu` 必须用同一个问句决定「有没有东西可看」。
/// 各自判一次就会分叉——窄窗口把某件挤进 overflow 时，`overflow.isNotEmpty` 为真、
/// 滤完为空，于是画出一颗点了什么都不发生的 `⋮`。可见性用这个函数算，两处永不打架。
List<PlayerAction> actionableMenuItems(List<PlayerAction> items) {
  return items
      .where(
        (item) =>
            item.id != PlayerActionId.volume &&
            item.id != PlayerActionId.closeTile,
      )
      .toList();
}

/// `⋮` 的内容：按清单顺序列出「图标 + 标题」，容器由调用方给。
///
/// [rightPanel]＝true 开右侧面板（全屏／小窗／格子），false 开底部抽屉（桌面窗口化、
/// 页级 AppBar 那颗「更多」）。判据与清单类弹层同一份（`usesRightPanelSurface`），
/// 别在这里再问一次平台。移动端不会走到这里（平台门短路）。
///
/// [items] 允许直接把 resolver 的 `layout.overflow` 递进来，所以行先过
/// [actionableMenuItems]（滤由它一处定义，与条带那颗 `⋮` 的可见性同源）。
/// 滤完为空则整颗 `⋮` 不弹，避免只有头的空容器。
void showActionMenu({
  required String title,
  required List<PlayerAction> items,
  required bool rightPanel,
  required void Function(PlayerActionId) onSelect,
}) {
  final rows = actionableMenuItems(items);
  if (rows.isEmpty) {
    return;
  }
  final list = ListView(
    padding: EdgeInsets.zero,
    children: [
      for (final item in rows)
        ListTile(
          leading: Icon(playerActionIcon(item.id)),
          title: Text(item.title),
          onTap: () {
            // 收起的是自己那块容器：右侧面板归 hideRightDialog，
            // 底部抽屉是模态路由，只能 Get.back（与页级「更多」改造前同一写法）。
            if (rightPanel) {
              Utils.hideRightDialog();
            } else {
              Get.back();
            }
            onSelect(item.id);
          },
        ),
    ],
  );
  if (rightPanel) {
    Utils.showRightDialog(title: title, child: list);
    return;
  }
  Utils.showBottomSheet(title: title, child: list);
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
    PlayerActionId.muteTile => Icons.volume_off,
  };
}

/// 换台：把**多开网格里的某一格**换成关注列表里另一个正在直播的直播间。
///
/// 只有格子用它——格子没有「屏幕右侧」可用（一块 400 宽的面板从屏幕右边弹出来，
/// 看不出在换哪一格），锚定在 ▾ 上的小列表才是它该有的形态。全屏的换台走
/// 右侧面板（`showFollowUser`，见 `invokePlayerAction` 的 pick 分支）；窗口化没有这颗。
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
      itemBuilder: (context) =>
          // 在菜单打开时才扫关注列表：放在 build 里，四格每帧都要扫一遍
          followPickMenuItems(target.multiPlay.buildSwitchEntries()),
      onSelected: (user) => pickFollowUser(target, user),
    );
  }
}

/// 换台菜单的行：**内容只此一份**。
///
/// 两个开法共用它——格子里那颗 ▾（`PopupMenuButton`，点一下就地展开）与移动端
/// **长按格子**（`showFollowPickMenu`，长按点当锚点）。后者不走 `showButtonMenu`
/// 是因为那需要一个跨 rebuild 稳定的 `GlobalKey` 指向那颗按钮，而 `MultiPlayTile`
/// 是 StatelessWidget：键每次 build 都是新的 → `PopupMenuButtonState` 被重挂载 →
/// `showButtonMenu().then` 里那句 `if (!mounted) return null` 会把选中结果静默丢掉
/// （这坑在本仓库踩过，见 `player_controls.dart` 与项目笔记）。
List<PopupMenuEntry<FollowUser>> followPickMenuItems(
  List<MultiPlaySwitchEntry> entries,
) {
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
}

/// 长按格子开的换台菜单：内容与 ▾ 同一份，锚点就是长按那一点。
Future<FollowUser?> showFollowPickMenu({
  required BuildContext context,
  required Offset position,
  required List<MultiPlaySwitchEntry> entries,
}) {
  return showMenu<FollowUser>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: followPickMenuItems(entries),
  );
}

/// 选中一路之后真正换台。▾ 与长按两条开法共用。
///
/// 走 `replaceTileRoom`：单画面下它等价于 `resetRoom`（主格也在自己的 slots 里），
/// 命中别的格子时只把焦点移过去，不建第二个实例。
void pickFollowUser(LiveRoomController target, FollowUser user) {
  final site = Sites.allSites[user.siteId];
  if (site == null) {
    return;
  }
  target.multiPlay.replaceTileRoom(target, site, user.roomId);
}
