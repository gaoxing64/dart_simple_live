/// 多开的纯函数帮手：批量入口的选择过滤，以及「关掉一格后焦点落在哪」。
library;

import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';

/// 关注列表里那颗「加入多开」icon 只在一种情况下出现：**这一路还没在多开里**。
///
/// 已经在多开里的行**什么都不显示**——原先那里摆过路号徽章 + ✕，两条都被否了：
/// - 序号（「第 N 路」）在关注列表里没有信息量。它回答不了「我在看哪一路」（面板不显示
///   聚焦格），也回答不了「这一格多大了」（格子的大小得看网格）。真要看位置，网格里
///   每格左下角本来就有同一颗序号牌。
/// - ✕ 与网格里那颗重复，且**主格上是死的**：主格是页面本身，销不得。关格子在网格里
///   点那颗 ✕ 更直观——那里能直接看到「关掉的是哪一格」，而在列表里隔着一层焦点关系。
///
/// 于是只剩「加入」一个动作，判定退化成一句话，不必再抽成三分支的枚举。
/// 纯函数留在这里是为了让「已在多开 → 不显示」这条判据可单测。
bool shouldShowMultiPlayAddAction(int slot) => slot < 0;

/// 批量多开时，选中的关注里有没有可用的直播。
enum MultiPlaySelectionProblem { none, empty, tooMany }

/// 从「关注页选择态」选中的主播里挑出能一起多开的那几路。
///
/// 纯函数（只做过滤与上限判断），便于单测覆盖：
/// - 过滤掉未开播的——多开是看直播，未开播的没有意义；
/// - 超过 [max] 路时整体拒绝，**不偷偷截断**：用户明确选了 5 个却只打开 4 个更让人困惑。
({List<FollowUser> rooms, MultiPlaySelectionProblem problem}) selectForMultiPlay(
  List<FollowUser> selected, {
  int max = kMultiPlayMaxTiles,
}) {
  final live = selected.where((u) => u.liveStatus.value == 2).toList();
  if (live.isEmpty) {
    return (rooms: const <FollowUser>[], problem: MultiPlaySelectionProblem.empty);
  }
  if (live.length > max) {
    return (rooms: live, problem: MultiPlaySelectionProblem.tooMany);
  }
  return (rooms: live, problem: MultiPlaySelectionProblem.none);
}

/// 关掉某一格之后，焦点下标应该落在哪。
///
/// 规则是「跟着同一格走」：删掉的是聚焦格**之前**的，整体前移一位，这样用户看到的
/// 聚焦描边和听到的那一路都不会因为关掉别格而漂移；聚焦格自己被删（或越界）时夹到
/// 最后一格。抽成纯函数是因为这里是典型的 off-by-one 高发区，值得单测钉住。
int focusedSlotAfterRemoval({
  required int focused,
  required int removedIndex,
  required int remainingLength,
}) {
  var next = focused;
  if (removedIndex < focused) {
    next -= 1;
  }
  if (next >= remainingLength) {
    next = remainingLength - 1;
  }
  if (next < 0) {
    next = 0;
  }
  return next;
}