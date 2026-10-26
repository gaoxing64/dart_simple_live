String watchDateKey(DateTime date) {
  final localDate = date.toLocal();
  final month = localDate.month.toString().padLeft(2, '0');
  final day = localDate.day.toString().padLeft(2, '0');
  return '${localDate.year}-$month-$day';
}

/// 将截至 [end] 的整秒时长按本地日期拆分，每一天使用真实的本地午夜边界。
Map<String, int> splitWatchSeconds({
  required DateTime end,
  required int seconds,
}) {
  if (seconds <= 0) {
    return {};
  }

  final localEnd = end.toLocal();
  var cursor = localEnd.subtract(Duration(seconds: seconds));
  var remaining = seconds;
  final result = <String, int>{};

  while (remaining > 0) {
    final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
    final microsecondsToMidnight = nextMidnight.difference(cursor).inMicroseconds;
    final secondsToMidnight = (microsecondsToMidnight / Duration.microsecondsPerSecond).ceil();
    final currentSeconds = remaining < secondsToMidnight ? remaining : secondsToMidnight;
    final key = watchDateKey(cursor);
    result[key] = (result[key] ?? 0) + currentSeconds;
    remaining -= currentSeconds;
    cursor = cursor.add(Duration(seconds: currentSeconds));
  }
  return result;
}

/// 返回新映射；[delta] 中的正数秒数累加到 [base]，不修改任何入参。
Map<String, int> mergeWatchDays(
  Map<String, int> base,
  Map<String, int> delta,
) {
  final result = Map<String, int>.from(base);
  for (final entry in delta.entries) {
    if (entry.value <= 0) {
      continue;
    }
    result[entry.key] = (result[entry.key] ?? 0) + entry.value;
  }
  return result;
}
