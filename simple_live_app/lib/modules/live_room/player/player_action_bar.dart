import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';

/// 条带／胶囊共用的图标按钮样式底版：小尺寸、无内边距、白色前景。
///
/// 提到文件级：`PlayerActionBar` 组装整行用得到，`buildPlayerActionItem`
/// 逐个排（全屏顶栏走这条）也用得到——同一个动作在两个宿主里必须同形。
/// 密度（按钮最小尺寸）是唯一随 `compact` 变的量，其余属性都出自这同一份底版，
/// 两档不可能在别处悄悄分叉（见 [_iconStyleFor]）。
final ButtonStyle _iconStyleBase = IconButton.styleFrom(
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  foregroundColor: Colors.white,
);

/// 桌面条带的按钮最小尺寸（现状值：桌面窗口化／全屏／小窗的调用点不传 compact，保持原样）。
const Size _kDesktopButtonSize = Size(36, 36);

/// 紧凑密度：按钮 30×30、图标 20——格子接共用 renderer 之前胶囊原本的尺寸。
///
/// WHY 要有这一档：格子最小合法宽度 240 逻辑像素（`kMultiPlayMinTileWidth`，四路 2×2
/// 把窗口缩到下限正好落在这尺寸），底部 chrome 行减去左右各 8 的内缩只剩 224 可用，
/// 而信息胶囊实测最小 66。格子的按钮簇现在有五颗（弹幕／音量／全屏／✕／⋮）：按桌面
/// 36×36 的 chrome 胶囊要 ~184 宽，两条合计 250 > 224，名字挤成 0 后内层 Row 溢出
/// （RenderFlex overflow）；按 30×30 是 ~154，格子重新拿回改造前的余量。
/// 宽度预算由 `test/player_action_bar_test.dart` 按 240 宽钉住，改动这里先看那条。
const Size _kCompactButtonSize = Size(30, 30);
const double _kCompactIconSize = 20;

/// 同一份底版按密度派生出按钮样式：只 merge 最小尺寸，其余属性两档共用。
ButtonStyle _iconStyleFor({required bool compact}) => _iconStyleBase.merge(
  ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size?>(
      compact ? _kCompactButtonSize : _kDesktopButtonSize,
    ),
  ),
);

/// 条带／顶栏／格子胶囊共用的按钮样式，按密度取档。
///
/// 对外暴露这一个而不是让宿主各自照抄参数：格子的信息胶囊 ▾、顶栏的右上簇与底栏
/// 必须是同一份 chrome。曾经格子那边手写了一份复制品（30×30/zero/white 逐字段重写），
/// 样式来源就分了两处——收在本文件里，两档才不会再各自漂移。
ButtonStyle playerActionIconStyle({bool compact = false}) =>
    _iconStyleFor(compact: compact);

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
    this.iconSize,
    this.onCloseTile,
    this.hug = false,
    this.compact = false,
  });

  final PlayerHost host;
  final LiveRoomController target;
  final LiveRoomController page;
  final List<PlayerAction> bar;
  final List<PlayerAction> overflow;
  final TextStyle? textStyle;
  final VoidCallback? onInteract;

  /// 图标尺寸；null＝按密度取默认（桌面条带 24，紧凑胶囊 20）。
  final double? iconSize;
  final VoidCallback? onCloseTile;

  /// true＝紧凑密度：按钮最小尺寸压到 30×30、默认图标 20，`⋮` 与音量颗同档，
  /// 整颗胶囊一致；false（桌面窗口化／全屏／小窗都不传）＝现状 36×36／24。
  /// WHY 需要这一档见 [_kCompactButtonSize] 的注释（240 宽的格子）。
  final bool compact;

  /// true＝贴紧内容（格子胶囊：无界主轴的孩子，`Spacer` 会直接抛错）；
  /// false＝窗口化／全屏整幅底栏，保留 `Spacer` 把左右簇推向两端。
  final bool hug;

  /// 底栏那一行：左簇 → 余量 → 右簇（末尾是 `⋮`，仅无顶栏的宿主画它）。
  ///
  /// 右上那一簇不由这里渲染：它要跟着返回键与标题排在同一条顶栏里（标题是容器结构
  /// 不是动作，见 spec §8 的建模口径），由 `player_controls.dart` 拿
  /// [playerTopClusterItems] + [PlayerOverflowButton] 自己拼——两处共用同两个部件，
  /// `⋮` 的判定只此一份。
  ///
  /// WHY 右簇整体套 `Expanded` 而不是老写法 `[...left, Spacer(), ...right]`：
  /// 清晰度／线路是**内容驱动宽度**的文字按钮，窄窗口里要能收缩（下面包 `Flexible`），
  /// 而 `Flexible` 默认 `fit` 是 **tight**（等价 `Expanded`）——它和 `Spacer` 一起
  /// 平分余量，右簇就被顶到条带中段（作者 2026-10-03 手测报的位置不对，实宽差 290px）。
  /// 套进 `Expanded` 后余量只由这一道空吃，内层按 `end` 排、收缩发生在内层，
  /// 两个诉求不再互相挤。
  @override
  Widget build(BuildContext context) {
    // 图标尺寸没显式传时按密度取默认：桌面 24、紧凑胶囊 20（两档的 chrome 是一个
    // 整体旋钮，不让「30×30 的按钮配 24 的图标」这种半紧凑组合出现）。
    final effectiveIconSize = iconSize ?? (compact ? _kCompactIconSize : 24.0);
    final buttonStyle = _iconStyleFor(compact: compact);
    final left = <Widget>[];
    final right = <Widget>[];
    for (final action in bar) {
      // 有顶栏的宿主（窗口化／全屏）里，右上那一簇的件不占底栏；小窗与格子没有顶栏，
      // resolver 已经把同样的件留在 bar 里，这里再滤一次就会把它变孤儿——所以判据
      // 与 resolver 完全同一份（hasTopCluster），绝不各判各的。
      if (hasTopCluster(host) && action.placeInTopBar) {
        continue;
      }
      var item = buildPlayerActionItem(
        action: action,
        host: host,
        target: target,
        page: page,
        textStyle: textStyle,
        iconSize: effectiveIconSize,
        compact: compact,
        onInteract: onInteract,
        onCloseTile: onCloseTile,
      );
      // 文字按钮（清晰度／线路）的实宽是内容驱动的：resolver 的收纳预算按 56px
      // 记，可「原画(1080P)」这类标签真实排版远超它——不包 Flexible，窄窗口里
      // 固定的 core 件加超长读数会把 Row 顶出 RenderFlex 溢出（窗口化／全屏条带
      // 的实测错位，回归钉在 test/player_action_bar_test.dart）。
      // `fit` 必须是 loose：tight 会去抢余量（见 build 的 WHY），只给上限、不占位。
      // hug（格子胶囊）在无界主轴里包 Flexible 会直接抛错，且 tile 宿主的
      // quality/line 恒是 menuOnly、进不了 bar——收缩只给有界宿主。
      if (!hug &&
          (action.id == PlayerActionId.quality ||
              action.id == PlayerActionId.line)) {
        item = Flexible(fit: FlexFit.loose, child: item);
      }
      (action.rightSide ? right : left).add(item);
    }
    // ⋮ 的可见性问的是「抽屉里到底有几行」，不是「overflow 有几项」：
    // overflow 可能只装着 volume/closeTile 这两类抽屉里点不动的锚定件，
    // 那种时候 showActionMenu 会直接 return，画出来的 ⋮ 就是颗死按钮。
    // 所以两边都用 actionableMenuItems 这同一个判定，不在这儿另抄一份过滤。
    final overflowButton = PlayerOverflowButton(
      host: host,
      target: target,
      page: page,
      overflow: overflow,
      placement: PlayerActionPlacement.bottom,
      iconSize: effectiveIconSize,
      buttonStyle: buttonStyle,
      onInteract: onInteract,
    );
    return Row(
      mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
      children: [
        ...left,
        // hug 时主轴无界，Expanded 孩子（Expanded 本身就是）直接抛错：
        // 格子那颗胶囊整条走 MainAxisSize.min，由内容自己定宽。
        if (hug) ...[
          ...right,
          overflowButton,
        ] else
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [...right, overflowButton],
            ),
          ),
      ],
    );
  }
}

/// 一簇的落点：视频区右上角那一簇，还是底栏／格子胶囊。
enum PlayerActionPlacement { top, bottom }

/// `⋮` 本身，连同「这一簇该不该画它」的判定。
///
/// WHY 收成一个 widget 而不是两个宿主各判一次：`⋮` 全应用只有**一个**落点——
/// 有顶栏的宿主在右上簇，没有的（小窗、格子）在底栏。判在两处就会出现
/// 「件排在顶簇、`⋮` 画在底栏」这种两头都找不到的组合；判据与 resolver 分簇
/// 用的是同一个 [hasTopCluster]，两边不可能漂移。
class PlayerOverflowButton extends StatelessWidget {
  const PlayerOverflowButton({
    super.key,
    required this.host,
    required this.target,
    required this.page,
    required this.overflow,
    required this.placement,
    required this.buttonStyle,
    this.iconSize = 24,
    this.onInteract,
  });

  final PlayerHost host;
  final LiveRoomController target;
  final LiveRoomController page;
  final List<PlayerAction> overflow;
  final PlayerActionPlacement placement;
  final ButtonStyle buttonStyle;
  final double? iconSize;
  final VoidCallback? onInteract;

  @override
  Widget build(BuildContext context) {
    if ((placement == PlayerActionPlacement.top) != hasTopCluster(host)) {
      return const SizedBox.shrink();
    }
    final rows = actionableMenuItems(overflow);
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: "更多",
      iconSize: iconSize,
      style: buttonStyle,
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
    );
  }
}

/// 右上角那一簇的 widget（截图／换台／小窗…），不含 `⋮`（另调 [PlayerOverflowButton]）。
///
/// 窗口化顶栏与全屏顶栏都走这里：件、图标、按下行为与底栏同源，两处不可能分叉。
List<Widget> playerTopClusterItems({
  required PlayerActionLayout layout,
  required PlayerHost host,
  required LiveRoomController target,
  required LiveRoomController page,
  TextStyle? textStyle,
  double? iconSize,
  bool compact = false,
  VoidCallback? onInteract,
}) {
  final effectiveIconSize = iconSize ?? (compact ? _kCompactIconSize : 24.0);
  return [
    for (final action in layout.topBar)
      buildPlayerActionItem(
        action: action,
        host: host,
        target: target,
        page: page,
        textStyle: textStyle,
        iconSize: effectiveIconSize,
        compact: compact,
        onInteract: onInteract,
      ),
  ];
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
  bool compact = false,
  VoidCallback? onInteract,
  VoidCallback? onCloseTile,
}) {
  // 按钮 chrome 只由密度派生一份（底版共用，见 _iconStyleFor）；顶栏调用点不传
  // compact，拿到的就是桌面 36×36，与条带同形。
  final buttonStyle = _iconStyleFor(compact: compact);
  switch (action.id) {
    case PlayerActionId.danmakuToggle:
      // 开／关两个 asset 图标，是「状态」而不是「动作名」，所以不能收进 ⋮ 用通用图标。
      return Obx(
        () => IconButton(
          tooltip: target.showDanmakuState.value ? "关闭弹幕" : "开启弹幕",
          iconSize: iconSize,
          style: buttonStyle,
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
              // 收缩支持：M3 默认 minimumSize 是 64×36——外层 Flexible 压到 64
              // 以下时它顶不住，溢出照旧。宽度下限归零，高度维持默认 36，
              // 观感（内容宽时）与原来逐像素一致。
              minimumSize: const Size(0, 36),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (textStyle ?? const TextStyle()).copyWith(
                color: Colors.white,
                fontSize: labelFontSize,
              ),
            ),
          );
        },
      );
    case PlayerActionId.volume:
      return VolumeActionWidget(
        target: host == PlayerHost.tile
            ? VolumeTarget.tile(target)
            : VolumeTarget.master(page),
        style: buttonStyle,
        iconSize: iconSize,
        overlayPopover: host == PlayerHost.tile,
        onInteract: onInteract,
      );
    case PlayerActionId.closeTile:
      return IconButton(
        tooltip: action.title,
        iconSize: iconSize,
        style: buttonStyle,
        icon: const Icon(Icons.close),
        onPressed: onCloseTile,
      );
    case PlayerActionId.smallWindow:
      return Obx(
        () => IconButton(
          tooltip: page.smallWindowState.value ? "退出小窗" : action.title,
          iconSize: iconSize,
          style: buttonStyle,
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
          // 图标按宿主分：桌面条带在接 renderer 前用的是项目图标族（Remix），
          // Task 8 接线时漂成了 Material——作者没点头这条视觉改动，这里改回原样。
          // 格子胶囊在 Task 9 接 renderer 之前就是 Material `Icons.fullscreen`，
          // 维持现状不动它。⋮ 抽屉的图标表（playerActionIcon）不受影响。
          final iconData = host == PlayerHost.tile
              ? (showExit ? Icons.fullscreen_exit : Icons.fullscreen)
              : (showExit ? Remix.fullscreen_exit_fill : Remix.fullscreen_line);
          return IconButton(
            tooltip: showExit ? "退出全屏" : "全屏播放",
            iconSize: iconSize,
            style: buttonStyle,
            icon: Icon(iconData, color: Colors.white),
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
    case PlayerActionId.danmakuSettings:
      // 桌面条带里保持项目的 asset 图标（原窗口化/移动条带同形）；漂成 Icons.tune
      // 是 Task 8 接线时发生的，作者未认可。抽屉里的表格形态仍走 playerActionIcon。
      // （tile 宿主这颗恒是 menuOnly、进不了平铺 bar，本分支只在桌面条带出现。）
      return IconButton(
        tooltip: action.title,
        iconSize: iconSize,
        style: buttonStyle,
        icon: ImageIcon(
          const AssetImage('assets/icons/icon_danmaku_setting.png'),
          size: iconSize,
          color: Colors.white,
        ),
        onPressed: () {
          onInteract?.call();
          invokePlayerAction(target: target, page: page, id: action.id);
        },
      );
    default:
      return IconButton(
        tooltip: action.title,
        iconSize: iconSize,
        style: buttonStyle,
        // 刷新颗与全屏颗同理：桌面条带回到项目图标族 Remix.refresh_line（Task 8
        // 接线时漂成 Icons.refresh，作者未认可）；tile 宿主维持 Material 表。
        // 换台颗同理回到改造前顶栏那颗 `Remix.play_list_2_line`——作者要求右上这一簇
        // 与改造前一致，图标也算一致的一部分。
        icon: Icon(
          host == PlayerHost.tile
              ? playerActionIcon(action.id)
              : switch (action.id) {
                  PlayerActionId.refresh => Remix.refresh_line,
                  PlayerActionId.pick => Remix.play_list_2_line,
                  _ => playerActionIcon(action.id),
                },
          color: Colors.white,
        ),
        onPressed: () {
          onInteract?.call();
          invokePlayerAction(target: target, page: page, id: action.id);
        },
      );
  }
}
