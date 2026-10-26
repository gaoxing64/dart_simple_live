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
  /// 触屏专用的「静音这一路」：桌面音量颗点击＝静音、悬停＝滑条，而触屏没有 hover，
  /// 那颗只能改成「点击弹滑条」，静音这个动作就没了入口 —— 收进 `⋮` 这一行补回来。
  muteTile,
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

/// 一条动作的「存在性」声明：是什么、占多宽、在哪一簇、放顶栏还是底栏。
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

  /// 放在视频区**右上角那一簇**还是底栏（作者 2026-10-03 定：截图／小窗／更多在右上，
  /// 与改造前一致；换台也在这簇，但它只在全屏在场，见 `_available` 的 pick 分支。
  /// 底栏只留刷新·弹幕·弹幕设置·音量·清晰度·线路·全屏）。
  /// 只对 [`hasTopCluster`] 为真的宿主有效——小窗几百 px、格子嵌在画面里，
  /// 两者都没有顶栏可放，这几件照样留在各自的底栏／胶囊里。
  final bool placeInTopBar;

  /// 条带内的左右簇：false 跟「刷新／弹幕」同侧，true 跟「音量／全屏」同侧。
  final bool rightSide;
}

/// 这个宿主有没有「右上角那一簇」可放。
///
/// 一处定义，两处问它：resolver 决定带 `placeInTopBar` 的件落到哪个清单，
/// renderer 决定 `⋮` 画在哪一簇——两边各判一次就会出现「件在 topBar 里、`⋮`
/// 却在底栏」这种两头都找不到入口的组合。
bool hasTopCluster(PlayerHost host) =>
    host == PlayerHost.windowed || host == PlayerHost.fullscreen;

/// 这个宿主的清单类弹层用**右侧面板**还是**底部抽屉**。
///
/// 判据是宿主，不是「这是不是一份清单」——改造前就是这个口径，作者 2026-10-04 手测后
/// 定回来：窗口化那条（旧 `buildControls`）的清晰度／线路／弹幕设置全落底部抽屉，
/// 同名动作在全屏（旧 `buildFullControls`）里开的才是右侧面板。
/// 窗口化右侧本来就站着聊天／SC／关注那一栏，再来一块 400 宽的面板会把它整个盖掉。
///
/// 小窗与格子留右侧面板：小窗在改造前复用的正是全屏那一套；格子是浮在画面上的胶囊，
/// 底部抽屉会横切另外几路的画面。
/// **触屏（[isDesktop] 为 false）一律底部抽屉**：手机竖屏只有 ~360 逻辑像素宽，
/// `showRightDialog` 那 320~400 宽的面板根本放不下，多开的格子只能从下面升起来。
///
/// 移动端**单画面**不经过这里（`playerControls` 的平台门短路，两条老 builder 各自直调
/// `showQualitySheet` / `showQualitesInfo`），行为逐字不变。
bool usesRightPanelSurface(PlayerHost host, {required bool isDesktop}) =>
    isDesktop && host != PlayerHost.windowed;

class PlayerActionLayout {
  const PlayerActionLayout({
    required this.topBar,
    required this.bar,
    required this.all,
    required this.overflow,
  });

  /// 右上角那一簇（`⋮` 也归它，见 [hasTopCluster]）。无顶栏的宿主恒空。
  final List<PlayerAction> topBar;

  /// 底栏／格子胶囊里平铺的件。
  final List<PlayerAction> bar;

  /// 此刻**在场**的全部动作（顶簇 + 底栏 + 被收纳的），按 `_kAllActions` 的声明顺序。
  ///
  /// 页级「更多」要的就是这一份：它是直达入口，不受条带宽度约束。顺序单独存一份而不是
  /// `[...topBar, ...bar, ...overflow]` 现拼——那样拼出来是「三簇顺序拼接」，
  /// 与条带里的声明顺序不一致，同一个动作在两个菜单里会换个位置出现。
  final List<PlayerAction> all;
  final List<PlayerAction> overflow;

  /// 有没有被收纳的项。
  ///
  /// 现在只被 `test/player_action_set_test.dart` 的收纳断言使用——renderer 那颗 `⋮`
  /// 的可见性问的是「抽屉里到底有几行」（`actionableMenuItems`，见
  /// `player_action_views.dart`），和「overflow 非空」是两个问题。**不要当死代码删**：
  /// 它是测试表达「沉下去的东西还在」这语义的入口。
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
    placeInTopBar: true,
  ),
  PlayerAction(
    id: PlayerActionId.volume,
    title: "音量",
    rightSide: true,
  ),
  // 触屏格子的「静音这一路」。`_available` 让它只在 `tile + 触屏` 在场，`_tierFor` 的
  // tile 分支默认档就是 menuOnly，所以它永远只出现在 `⋮` 里，不占胶囊那 224px 的宽度预算。
  PlayerAction(
    id: PlayerActionId.muteTile,
    title: "静音这一路",
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
    placeInTopBar: true,
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
///
/// [isTouch] 只有格子宿主用得上：触屏上音量颗的点击被改成「弹滑条」（没 hover 可用），
/// 静音这个动作需要另一个入口，见 [PlayerActionId.muteTile]。
bool _available(
  PlayerActionId id,
  PlayerHost host, {
  required bool canCloseTile,
  required bool hasQuality,
  required bool hasLine,
  required bool isTouch,
}) {
  switch (id) {
    case PlayerActionId.closeTile:
      return host == PlayerHost.tile && canCloseTile;
    case PlayerActionId.muteTile:
      return host == PlayerHost.tile && isTouch;
    case PlayerActionId.pick:
      // 换台只在全屏右上那一簇与多开格子的 ▾：改造前的窗口化条带根本没有这颗
      // （要换台先进全屏），作者 2026-10-04 定回这个口径——「右侧面板仅在全屏时使用」，
      // 而换台点开的那块就是右侧面板。小窗也没有这颗（它本来就收成四件）。
      return host == PlayerHost.fullscreen || host == PlayerHost.tile;
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
      // pick（换台）在桌面宿主是常驻平铺：它点开的是右侧面板（与改造前同一块），
      // 并非锚定件、进得了抽屉；但它一旦因宽度沉下去，右上那一簇就少一件作者明确
      // 要求待在原位的入口，所以与音量同类按常驻处理。
      return switch (id) {
        PlayerActionId.refresh ||
        PlayerActionId.danmakuToggle ||
        PlayerActionId.pick ||
        PlayerActionId.volume ||
        PlayerActionId.fullscreenToggle => PlayerActionTier.core,
        PlayerActionId.danmakuSettings ||
        PlayerActionId.screenshot ||
        PlayerActionId.quality ||
        PlayerActionId.line ||
        PlayerActionId.smallWindow => PlayerActionTier.whenFits,
        _ => PlayerActionTier.menuOnly,
      };
  }
}

/// 一条候选在「这个宿主此刻」的判定：清单条目 + `_tierFor` 现算出的档 + 落哪一簇。
///
/// 私有、且只活在 resolver 内部——`PlayerAction` 不带 tier 正是为了不给下游
/// （Task 5/6/8/9/10）留一个能读到「过时 tier」的入口。
typedef _Resolved = ({PlayerAction action, PlayerActionTier tier, bool onTop});

/// [isTouch] 默认 false —— 桌面所有调用点都不传，产出的清单必须与触屏适配之前逐字相同
/// （回归钉在 `test/player_action_set_test.dart`）。它只影响一件事：触屏格子的
/// [PlayerActionId.muteTile] 是否在场。
PlayerActionLayout resolvePlayerActions({
  required PlayerHost host,
  required double availableWidth,
  bool isVertical = false,
  bool canCloseTile = false,
  bool hasQuality = true,
  bool hasLine = true,
  bool isTouch = false,
}) {
  final topHost = hasTopCluster(host);
  final candidates = <_Resolved>[
    for (final action in _kAllActions)
      if (_available(
        action.id,
        host,
        canCloseTile: canCloseTile,
        hasQuality: hasQuality,
        hasLine: hasLine,
        isTouch: isTouch,
      ))
        (
          action: action,
          tier: _tierFor(action.id, host, isVertical: isVertical),
          // 没有顶栏的宿主（小窗、格子）把带 `placeInTopBar` 的件留在底栏：
          // 否则它既不在顶簇也不在底簇，成了谁也渲染不到的孤儿。
          onTop: topHost && action.placeInTopBar,
        ),
  ];

  // **分簇预算**：右上那一簇与底栏各自量一次宽。共用一个总预算的话，「挪去顶栏那几件」
  // 仍记在底栏头上，底栏会误判装不下、白白把件收进 ⋮。
  // `⋮` 归顶簇持有（见 [hasTopCluster]），所以只有顶簇给它留位；底簇装不下的件沉进
  // 的是同一份 overflow，也就是顶栏那颗 `⋮` 的抽屉。
  double budgetFor({required bool onTop}) {
    final inCluster = candidates.where((e) => e.onTop == onTop);
    final nonMenuTotal = inCluster
        .where((e) => e.tier != PlayerActionTier.menuOnly)
        .fold<double>(0, (sum, e) => sum + e.action.slotWidth);
    final hostsMenu = onTop == topHost;
    // 「有没有东西可收」问的是整份清单：menuOnly 那几件（画面尺寸／分享…）没有
    // placeInTopBar，按声明落在底簇，可 `⋮` 是**顶簇**的那颗——所以判据不能只看本簇，
    // 否则顶簇不留位、底簇白留 40，那颗 ⋮ 挤到顶簇最后一颗按钮的位置上。
    final hasAnyMenuContent = candidates.any(
      (e) => e.tier == PlayerActionTier.menuOnly,
    );
    final needsMenu =
        (hostsMenu && hasAnyMenuContent) || nonMenuTotal > availableWidth;
    return availableWidth - (needsMenu ? kOverflowButtonWidth : 0);
  }

  final topBar = <PlayerAction>[];
  final bar = <PlayerAction>[];
  final overflow = <PlayerAction>[];
  var topBudget = budgetFor(onTop: true);
  var barBudget = budgetFor(onTop: false);
  for (final candidate in candidates) {
    final action = candidate.action;
    if (candidate.tier == PlayerActionTier.menuOnly) {
      overflow.add(action);
      continue;
    }
    final budget = candidate.onTop ? topBudget : barBudget;
    // core 无条件在场：宽度不够也要留住，这是「常驻至少三件」的底线。
    if (candidate.tier == PlayerActionTier.core ||
        budget >= action.slotWidth) {
      if (candidate.onTop) {
        topBar.add(action);
        topBudget -= action.slotWidth;
      } else {
        bar.add(action);
        barBudget -= action.slotWidth;
      }
      continue;
    }
    overflow.add(action);
  }
  return PlayerActionLayout(
    topBar: topBar,
    bar: bar,
    // candidates 本身就是 `_kAllActions` 的声明顺序（上面只是往里跳不存在项），
    // 所以「全集」直接取它，不用再从三个分簇清单现拼一份顺序出来。
    all: [for (final c in candidates) c.action],
    overflow: overflow,
  );
}
