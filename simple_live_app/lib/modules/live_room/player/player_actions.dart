/// 播放覆盖层的动作清单：这个宿主此刻该有哪些动作、哪些平铺、哪些收进 `⋮`。
///
/// 之所以抽成纯函数：窗口化／全屏／小窗／多开格原先是三套各自硬编码的 `Row`
/// （`player_controls.dart` 的 `buildFullControls` / `buildControls` 与
/// `multi_play_tile.dart` 的两个胶囊），同一个动作在四处有有无、语义还打架。
/// 清单同源之后，「一致」变成可以断言的性质（见 `test/player_action_set_test.dart`）。
///
/// 模型只决定「哪些、在哪」：图标与按下行为归 renderer——弹幕开关用的是 asset
/// `ImageIcon`、清晰度用的是文字按钮，形态本来就不一律，硬塞进数据类只会更难懂。
/// 移动端不进这套模型（`playerControls` 恒按平台门短路；页级「更多」只有移动端分支
/// 短路走原来的底部抽屉，桌面分支与条带共用这份清单）。
library;

enum PlayerHost { windowed, fullscreen, smallWindow, tile }

enum PlayerActionId {
  refresh,
  danmakuToggle,
  danmakuSettings,
  volume,
  quality,
  line,
  screenshot,
  pick,
  scale,
  smallWindow,
  fullscreenToggle,
  closeTile,
  share,
  copyUrl,
  openApp,
  debugInfo,
  autoExit,
}

enum PlayerActionTier {
  /// 宽度再窄也留在条带里（音量／弹幕／全屏／刷新这几个是「这条带还在」的底线）
  core,

  /// 宽度够才平铺，否则沉进 `⋮`
  whenFits,

  /// 恒在 `⋮` 里
  menuOnly,
}

/// 一条动作的「存在性」声明：是什么、占多宽、在哪一簇、全屏放顶栏还是底栏。
///
/// 「此刻平铺还是收进 `⋮`」不写在字段里——那是 `_tierFor` 按宿主现算的内部判断
/// （见 `resolvePlayerActions`）。刻意不设 `tier` 字段：清单里写死的 `tier` 会被
/// `_tierFor` 的结果覆盖，两处各说各话；改清单那行只是静默无效的 no-op。
class PlayerAction {
  const PlayerAction({
    required this.id,
    required this.title,
    this.slotWidth = 40,
    this.placeInTopBar = false,
    this.rightSide = false,
  });

  final PlayerActionId id;
  final String title;

  /// 平铺时占的宽度预算：图标按钮 40，文字按钮（清晰度／线路）56。
  final double slotWidth;

  /// 全屏宿主里放顶栏还是底栏（窗口化没有顶栏，这个字段被忽略）。
  final bool placeInTopBar;

  /// 条带内的左右簇：false 跟「刷新／弹幕」同侧，true 跟「音量／全屏」同侧。
  final bool rightSide;
}

class PlayerActionLayout {
  const PlayerActionLayout({required this.bar, required this.overflow});

  final List<PlayerAction> bar;
  final List<PlayerAction> overflow;

  bool get hasOverflow => overflow.isNotEmpty;
}

const double kOverflowButtonWidth = 40;

/// 声明顺序＝条带里的显示顺序（左簇 → 右簇，`⋮` 恒在最右）。
///
/// 清单只携带「存在性」字段，不写 tier：某个动作此刻是平铺还是进 `⋮`，一律由
/// `_tierFor` 按宿主现算（`PlayerAction` 也没有 tier 字段可读），保持单一真相源。
const List<PlayerAction> _kAllActions = [
  PlayerAction(
    id: PlayerActionId.refresh,
    title: "刷新",
  ),
  PlayerAction(
    id: PlayerActionId.danmakuToggle,
    title: "弹幕",
  ),
  PlayerAction(
    id: PlayerActionId.danmakuSettings,
    title: "弹幕设置",
  ),
  PlayerAction(
    id: PlayerActionId.screenshot,
    title: "截图",
    placeInTopBar: true,
  ),
  PlayerAction(
    id: PlayerActionId.pick,
    title: "换台",
  ),
  PlayerAction(
    id: PlayerActionId.volume,
    title: "音量",
    rightSide: true,
  ),
  PlayerAction(
    id: PlayerActionId.quality,
    // ⚠️ title 写「切换清晰度」而不是「清晰度」：这个 title 只在 `⋮`／页级「更多」抽屉里
    // 露出来（条带上这两颗是文字按钮，画的是当前清晰度/线路名，见 buildPlayerActionItem），
    // 而点开的那两个弹层标题本来就叫「切换清晰度」/「切换线路」。清单同源之后两处共用
    // 同一个 title，取用户熟悉已久的那份措辞，不让「合流」顺手把菜单文案改短。
    title: "切换清晰度",
    slotWidth: 56,
    rightSide: true,
  ),
  PlayerAction(
    id: PlayerActionId.line,
    title: "切换线路",
    slotWidth: 56,
    rightSide: true,
  ),
  PlayerAction(
    id: PlayerActionId.scale,
    title: "画面尺寸",
  ),
  PlayerAction(
    id: PlayerActionId.smallWindow,
    title: "小窗播放",
    rightSide: true,
  ),
  PlayerAction(
    id: PlayerActionId.fullscreenToggle,
    title: "全屏",
    rightSide: true,
  ),
  // 关闭排在最右簇末尾：今天 `multi_play_tile` 的胶囊里「关闭这一路」就在「更多」
  // 之后、整条最右；声明顺序＝输出顺序，Task 9 接线才接得住这颗。
  PlayerAction(
    id: PlayerActionId.closeTile,
    title: "关闭这一路",
    rightSide: true,
  ),
  PlayerAction(
    id: PlayerActionId.debugInfo,
    title: "播放信息",
  ),
  PlayerAction(
    id: PlayerActionId.autoExit,
    title: "定时关闭",
  ),
  PlayerAction(
    id: PlayerActionId.share,
    title: "分享直播间",
  ),
  PlayerAction(
    id: PlayerActionId.copyUrl,
    title: "复制链接",
  ),
  PlayerAction(
    id: PlayerActionId.openApp,
    title: "APP 中打开",
  ),
];

/// 该动作在这个宿主是否存在（不是「是否平铺」，那由 `_tierFor` 现算）。
bool _available(
  PlayerActionId id,
  PlayerHost host, {
  required bool canCloseTile,
  required bool hasQuality,
  required bool hasLine,
}) {
  switch (id) {
    case PlayerActionId.closeTile:
      return host == PlayerHost.tile && canCloseTile;
    case PlayerActionId.quality:
      return hasQuality;
    case PlayerActionId.line:
      return hasLine;
    case PlayerActionId.smallWindow:
      // 小窗是窗口级动作：格子碰不得（`enterSmallWindow` 在多开下直接 toast 拒绝）。
      // smallWindow 宿主时它表示「退出小窗」，仍然在场。
      return host != PlayerHost.tile;
    default:
      return true;
  }
}

PlayerActionTier _tierFor(
  PlayerActionId id,
  PlayerHost host, {
  required bool isVertical,
}) {
  switch (host) {
    case PlayerHost.tile:
      return switch (id) {
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume ||
        PlayerActionId.pick ||
        PlayerActionId.fullscreenToggle ||
        PlayerActionId.closeTile => PlayerActionTier.core,
        _ => PlayerActionTier.menuOnly,
      };
    case PlayerHost.smallWindow:
      // 小窗只有几百 px，右侧抽屉会盖住画面：平铺四件，其余一律进 ⋮（作者选定）。
      return switch (id) {
        PlayerActionId.smallWindow ||
        PlayerActionId.fullscreenToggle ||
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume => PlayerActionTier.core,
        _ => PlayerActionTier.menuOnly,
      };
    case PlayerHost.windowed:
    case PlayerHost.fullscreen:
      // 竖屏主播原先是直接 Offstage 掉清晰度/线路，现在降级进 ⋮（spec §9）。
      if (isVertical &&
          (id == PlayerActionId.quality || id == PlayerActionId.line)) {
        return PlayerActionTier.menuOnly;
      }
      return switch (id) {
        PlayerActionId.refresh ||
        PlayerActionId.danmakuToggle ||
        PlayerActionId.volume ||
        PlayerActionId.fullscreenToggle => PlayerActionTier.core,
        PlayerActionId.danmakuSettings ||
        PlayerActionId.screenshot ||
        PlayerActionId.pick ||
        PlayerActionId.quality ||
        PlayerActionId.line ||
        PlayerActionId.smallWindow => PlayerActionTier.whenFits,
        _ => PlayerActionTier.menuOnly,
      };
  }
}

/// 一条候选在「这个宿主此刻」的判定：清单条目 + `_tierFor` 现算出的档。
///
/// 私有、且只活在 resolver 内部——`PlayerAction` 不带 tier 正是为了不给下游
/// （Task 5/6/8/9/10）留一个能读到「过时 tier」的入口。
typedef _Resolved = ({PlayerAction action, PlayerActionTier tier});

PlayerActionLayout resolvePlayerActions({
  required PlayerHost host,
  required double availableWidth,
  bool isVertical = false,
  bool canCloseTile = false,
  bool hasQuality = true,
  bool hasLine = true,
}) {
  final candidates = <_Resolved>[
    for (final action in _kAllActions)
      if (_available(
        action.id,
        host,
        canCloseTile: canCloseTile,
        hasQuality: hasQuality,
        hasLine: hasLine,
      ))
        (
          action: action,
          tier: _tierFor(action.id, host, isVertical: isVertical),
        ),
  ];

  // 要不要给 `⋮` 留位：有 menuOnly 的候选，或者非 menuOnly 的候选本身已经超宽。
  final flexibleTotal = candidates
      .where((e) => e.tier != PlayerActionTier.menuOnly)
      .fold<double>(0, (sum, e) => sum + e.action.slotWidth);
  final needsMenu =
      candidates.any((e) => e.tier == PlayerActionTier.menuOnly) ||
      flexibleTotal > availableWidth;

  final bar = <PlayerAction>[];
  final overflow = <PlayerAction>[];
  var budget = availableWidth - (needsMenu ? kOverflowButtonWidth : 0);
  for (final candidate in candidates) {
    final action = candidate.action;
    if (candidate.tier == PlayerActionTier.menuOnly) {
      overflow.add(action);
      continue;
    }
    // core 无条件在场：宽度不够也要留住，这是「常驻至少三件」的底线。
    if (candidate.tier == PlayerActionTier.core ||
        budget >= action.slotWidth) {
      bar.add(action);
      budget -= action.slotWidth;
      continue;
    }
    overflow.add(action);
  }
  return PlayerActionLayout(bar: bar, overflow: overflow);
}
