/// 多开的纯函数帮手：批量入口的选择过滤，以及「关掉一格后焦点落在哪」。
library;

import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';

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