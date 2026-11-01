extension DurationStringExtensions on String {
  /// 将 "HH:MM:SS" 格式的字符串转换为 Duration
  Duration toDuration() {
    final parts = split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid duration format: $this');
    }

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = int.tryParse(parts[2]) ?? 0;

    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }
}

extension DurationExtensions on Duration {
  /// 将 Duration 转换为紧凑格式的字符串（如 "2h30m15s"）
  String toHMSString() {
    final hours = inHours; // 计算总小时数
    final minutes = inMinutes.remainder(60); // 计算剩余分钟数
    final seconds = inSeconds.remainder(60); // 计算剩余秒数

    // 格式化分钟和秒为两位数
    final minutesStr = minutes.toString().padLeft(2, '0');
    final secondsStr = seconds.toString().padLeft(2, '0');

    return '$hours:$minutesStr:$secondsStr';
  }
}

/// 「累计观看 N 小时」这类文案。
///
/// 不足一小时退到分钟、不足一分钟退到秒 —— 直接取整小时会出现
/// 「累计观看 0 小时」这种没有意义的文案。
///
/// 关注页的紧凑成员行（`FollowMemberRow`）用它。
/// ⚠️ 上段 `LiveRoomCard` **不再**显示累计观看时长（用户要求），别再加回去。
/// 「无观看记录」的规则也收敛在这里：返回空串由调用方决定是否显示，
/// 不要再各写一份 `> 0` 守卫（关注一个新主播就是 0，很容易命中）。
String watchDurationText(int seconds) {
  if (seconds <= 0) {
    return "";
  }
  if (seconds >= 3600) {
    return "累计观看 ${seconds ~/ 3600} 小时";
  }
  if (seconds >= 60) {
    return "累计观看 ${seconds ~/ 60} 分钟";
  }
  return "累计观看 $seconds 秒";
}
