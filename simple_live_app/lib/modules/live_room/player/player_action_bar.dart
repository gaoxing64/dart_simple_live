import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';

/// 条带／胶囊里那颗统一尺寸的图标按钮样式：小尺寸、无内边距、白色前景。
///
/// 提到文件级：`PlayerActionBar` 组装整行用得到，`buildPlayerActionItem`
/// 逐个排（全屏顶栏走这条）也用得到——同一个动作在两个宿主里必须同形。
final ButtonStyle _iconStyle = IconButton.styleFrom(
  minimumSize: const Size(36, 36),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  foregroundColor: Colors.white,
);

/// 底栏按钮（含「多开播放」胶囊）的文字样式。
///
/// ⚠️ 必须自己带上字族：`TextButton.styleFrom(textStyle: …)` 在 Flutter 里的取值是
/// `widgetStyle ?? themeStyle ?? defaultStyle`——**取第一个非空、不做合并**
/// （见 `ButtonStyleButton.effectiveValue`）。所以只写 `TextStyle(fontSize: 14)` 会让
/// 按钮文字丢掉设置里选的字体、退回系统默认字体，跟同屏其他文字对不上。
/// 页面里的底栏曾经各写一份这个 getter，跨不了库（私有 getter 别人 import 不到），
/// 于是提到这里当公共 helper，条带／顶栏／页面三处共用一个来源。
TextStyle playerToolbarTextStyle() => TextStyle(
  fontSize: 14,
  fontFamily: AppStyleSettingController.instance.curFontName.value,
);

/// 播放条带／胶囊的渲染器：把 resolver 的产物画出来，三个宿主共用。
///
/// 图标在这里决定（模型不持有图标）：弹幕开关用 asset `ImageIcon`、清晰度／线路用
/// 文字按钮——它们是「读数」不是「动作」，宽度随内容变。
///
/// 文字按钮必须带 [textStyle]：`ButtonStyle.textStyle` 与主题的 buttonTheme 是覆盖
/// 关系而不是合并关系，只写 fontSize 会把用户设定的字族丢掉。
class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({
    super.key,
    required this.host,
    required this.target,
    required this.page,
    required this.bar,
    required this.overflow,
    this.textStyle,
    this.onInteract,
    this.trailing,
    this.iconSize = 24,
    this.onCloseTile,
    this.hug = false,
  });

  final PlayerHost host;
  final LiveRoomController target;
  final LiveRoomController page;
  final List<PlayerAction> bar;
  final List<PlayerAction> overflow;
  final TextStyle? textStyle;
  final VoidCallback? onInteract;
  final Widget? trailing;
  final double iconSize;
  final VoidCallback? onCloseTile;

  /// true＝贴紧内容（格子胶囊：无界主轴的孩子，`Spacer` 会直接抛错）；
  /// false＝窗口化／全屏整幅底栏，保留 `Spacer` 把左右簇推向两端。
  final bool hug;

  /// 底栏那一行：左簇 → `Spacer` → 右簇 → `⋮`。
  ///
  /// 顶栏不由这里渲染：它要插返回键与标题（容器结构，不是动作，见 spec §8 的建模口径），
  /// 由 `player_controls.dart` 用同一个 `buildPlayerActionItem` 自己排。
  ///
  /// `Spacer()` 而不是 `Expanded(child: Center())`：resolver 已经把左右簇分好，
  /// `Spacer` 吃掉余量即可，且不会像 flex 那样先分掉一半宽度。
  @override
  Widget build(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (final action in bar) {
      if (host == PlayerHost.fullscreen && action.placeInTopBar) {
        continue;
      }
      final item = buildPlayerActionItem(
        action: action,
        host: host,
        target: target,
        page: page,
        textStyle: textStyle,
        iconSize: iconSize,
        onInteract: onInteract,
        onCloseTile: onCloseTile,
      );
      (action.rightSide ? right : left).add(item);
    }
    // ⋮ 的可见性问的是「抽屉里到底有几行」，不是「overflow 有几项」：
    // overflow 可能只装着 pick/volume/closeTile 这三类抽屉里点不动的锚定件，
    // 那种时候 showActionMenu 会直接 return，画出来的 ⋮ 就是颗死按钮。
    // 所以两边都用 actionableMenuItems 这同一个判定，不在这儿另抄一份过滤。
    final menuItems = actionableMenuItems(overflow);
    return Row(
      mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
      children: [
        ...left,
        // hug 时主轴无界，Expanded 孩子（Spacer 就是 Expanded）直接抛错：
        // 格子那颗胶囊整条走 MainAxisSize.min，由内容自己定宽。
        if (!hug) const Spacer(),
        ...right,
        if (menuItems.isNotEmpty)
          IconButton(
            tooltip: "更多",
            iconSize: iconSize,
            style: _iconStyle,
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {
              onInteract?.call();
              showActionMenu(
                title: "更多",
                items: overflow,
                onSelect: (id) => invokePlayerAction(
                  target: target,
                  page: page,
                  id: id,
                ),
              );
            },
          ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 单个动作的 widget。**文件级函数**：`PlayerActionBar` 负责组装整行，全屏顶栏要自己插
/// 返回键与标题，所以拿这个函数逐个排——两处画同一个动作必须是同一个函数，否则又分叉。
///
/// WHY 窗口级旗标读 `page` 而不是 `target`：`fullScreenState`/`smallWindowState` 只被
/// 页面主格写（见 `invokePlayerAction` 的同源注释），副格恒为 false——读 target 会让
/// 标题永远停在「进入」那一面，退不出去。renderer 的标题翻转必须与它调用的那条臂同源。
Widget buildPlayerActionItem({
  required PlayerAction action,
  required PlayerHost host,
  required LiveRoomController target,
  required LiveRoomController page,
  required TextStyle? textStyle,
  double iconSize = 24,
  VoidCallback? onInteract,
  VoidCallback? onCloseTile,
}) {
  switch (action.id) {
    case PlayerActionId.danmakuToggle:
      // 开／关两个 asset 图标，是「状态」而不是「动作名」，所以不能收进 ⋮ 用通用图标。
      return Obx(
        () => IconButton(
          tooltip: target.showDanmakuState.value ? "关闭弹幕" : "开启弹幕",
          iconSize: iconSize,
          style: _iconStyle,
          icon: ImageIcon(
            AssetImage(
              target.showDanmakuState.value
                  ? 'assets/icons/icon_danmaku_close.png'
                  : 'assets/icons/icon_danmaku_open.png',
            ),
            size: iconSize,
            color: Colors.white,
          ),
          onPressed: () => invokePlayerAction(
            target: target,
            page: page,
            id: action.id,
          ),
        ),
      );
    case PlayerActionId.quality:
    case PlayerActionId.line:
      return Obx(
        () {
          // 字号随宿主尺寸定（条带 24 用 15，胶囊小图标用 13），颜色固定白。
          final labelFontSize = iconSize > 20 ? 15.0 : 13.0;
          return TextButton(
            style: TextButton.styleFrom(
              textStyle: textStyle,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              onInteract?.call();
              invokePlayerAction(target: target, page: page, id: action.id);
            },
            // ⚠️ 子 Text 的 style 是「整体替换」而不是合并 TextButton 的 textStyle：
            // `ButtonStyleButton.effectiveValue` 取 `widgetStyle ?? themeStyle ?? defaultStyle`
            // 的第一份非空（见 live_room_page 里 _toolbarTextStyle 的同一陷阱），所以这里
            // 只写 color/fontSize 会把 [textStyle] 带来的用户字族丢掉，清晰度／线路
            // 就与同屏其它文字对不上。以 [textStyle] 为底再覆盖颜色字号，字族才留得住。
            child: Text(
              action.id == PlayerActionId.quality
                  ? target.currentQualityInfo.value
                  : target.currentLineInfo.value,
              style: (textStyle ?? const TextStyle()).copyWith(
                color: Colors.white,
                fontSize: labelFontSize,
              ),
            ),
          );
        },
      );
    case PlayerActionId.pick:
      return FollowPickButton(
        target: target,
        style: _iconStyle,
        iconSize: iconSize,
        icon: const Icon(Icons.arrow_drop_down),
        onOpened: onInteract,
      );
    case PlayerActionId.volume:
      return VolumeActionWidget(
        target: host == PlayerHost.tile
            ? VolumeTarget.tile(target)
            : VolumeTarget.master(page),
        style: _iconStyle,
        iconSize: iconSize,
        overlayPopover: host == PlayerHost.tile,
        onInteract: onInteract,
      );
    case PlayerActionId.closeTile:
      return IconButton(
        tooltip: action.title,
        iconSize: iconSize,
        style: _iconStyle,
        icon: const Icon(Icons.close),
        onPressed: onCloseTile,
      );
    case PlayerActionId.smallWindow:
      return Obx(
        () => IconButton(
          tooltip: page.smallWindowState.value ? "退出小窗" : action.title,
          iconSize: iconSize,
          style: _iconStyle,
          icon: Icon(Icons.picture_in_picture, color: Colors.white),
          onPressed: () => invokePlayerAction(
            target: target,
            page: page,
            id: action.id,
          ),
        ),
      );
    case PlayerActionId.fullscreenToggle:
      // 小窗态里这颗是「全屏播放」（spec §小窗四件之一）。
      // WHY 不直接复用 invokePlayerAction 的 fullscreenToggle：pip 下 fullScreenState
      // 恒真，那条臂会判成「退出全屏」→exitFull→exitSmallWindow，于是小窗底栏冒出两颗
      // 「退出小窗」、把桌面原来那颗「全屏播放」入口弄丢（ruling 6：旧 builder 已有的
      // 行为不能因为接 resolver 就掉）。所以 pip 宿主自己走 enterFullScreen。
      return Obx(
        () {
          final pip = page.smallWindowState.value;
          final full = page.fullScreenState.value;
          final showExit = full && !pip;
          return IconButton(
            tooltip: showExit ? "退出全屏" : "全屏播放",
            iconSize: iconSize,
            style: _iconStyle,
            icon: Icon(
              showExit ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: () {
              onInteract?.call();
              if (pip) {
                page.enterFullScreen();
              } else {
                invokePlayerAction(target: target, page: page, id: action.id);
              }
            },
          );
        },
      );
    default:
      return IconButton(
        tooltip: action.title,
        iconSize: iconSize,
        style: _iconStyle,
        icon: Icon(playerActionIcon(action.id), color: Colors.white),
        onPressed: () {
          onInteract?.call();
          invokePlayerAction(target: target, page: page, id: action.id);
        },
      );
  }
}
