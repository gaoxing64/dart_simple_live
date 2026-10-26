/// 直播间横屏聊天侧栏的宽度约束。
///
/// 纯算术、无 IO、无平台依赖：只回答「给定窗口宽和期望值，侧栏该多宽」，
/// 不碰设置与窗口 API，单测可扫边界（与 `multi_play_layout.dart` 同一分层思路）。
library;

import 'dart:math' as math;

/// 侧栏可拖到的最小宽度：再窄，长昵称与正文都读不下去。
const double kLiveRoomSidebarMinWidth = 240;

/// 侧栏可拖到的最大宽度：再宽只是给聊天留白，画面反而被挤小。
const double kLiveRoomSidebarMaxWidth = 560;

/// 视频区至少要留的宽度；窗口不够宽时优先保证画面。
const double kLiveRoomSidebarVideoMinWidth = 320;

/// 分隔条宽度。拖动热区按它算，底栏右侧留白也必须带上它才能与侧栏对齐。
const double kLiveRoomSidebarHandleWidth = 12;

/// 把期望宽度夹进「窗口放得下」的范围。
///
/// 窗口窄到连最小侧栏 + 最小视频区都给不出时，以侧栏下限为准——视频区是
/// `Expanded`，还能继续缩，而侧栏的 `SizedBox` 不能小于下限。
double resolveLiveRoomSidebarWidth({
  required double desired,
  required double availableWidth,
}) {
  final upperByWindow = availableWidth - kLiveRoomSidebarVideoMinWidth;
  final upper = math.min(
    kLiveRoomSidebarMaxWidth,
    math.max(kLiveRoomSidebarMinWidth, upperByWindow),
  );
  return desired.clamp(kLiveRoomSidebarMinWidth, upper);
}
