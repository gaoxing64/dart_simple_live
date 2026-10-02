/// 这一路此刻该给多大 mpv 音量（百分比）。
///
/// 单独抽成纯函数是因为这条规则被四种入口改：焦点变、总音量滑条、该格滚轮、
/// 设置里的压低开关。原来它内联在 `LiveRoomController.resolveTargetVolume` 里，
/// 每次都要连着 `AppSettingsController` 与 `MultiPlaySession` 才能推，真值没法测。
///
/// 「压低」现在是可选行为（设置默认关）：关掉后每路只由自己的系数决定，
/// 焦点不再影响音量——这是「每路独立控制」那半边需求。
library;

double resolveTileVolume({
  required double master,
  required bool duckEnabled,
  required double duckRatio,
  required double factor,
  required bool focused,
}) {
  if (factor <= 0.001) {
    return 0;
  }
  final duck = duckEnabled && !focused ? duckRatio : 1.0;
  return master * duck * factor;
}
