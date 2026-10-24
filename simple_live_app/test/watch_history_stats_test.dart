import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/utils/watch_history_stats.dart';

void main() {
  group('watchDateKey', () {
    test('本地日期补零，且不依赖 UTC 偏移', () {
      expect(watchDateKey(DateTime(2026, 1, 2)), '2026-01-02');
      expect(watchDateKey(DateTime(2026, 10, 24, 23, 59)), '2026-10-24');
    });
  });

  group('splitWatchSeconds', () {
    test('同一天直接返回一个键', () {
      final result = splitWatchSeconds(
        end: DateTime(2026, 10, 24, 12, 30),
        seconds: 1800,
      );
      expect(result, {'2026-10-24': 1800});
    });

    test('跨午夜按两个本地日期拆分，总量不变', () {
      final result = splitWatchSeconds(
        end: DateTime(2026, 10, 25, 0, 1),
        seconds: 120,
      );
      expect(result, {'2026-10-24': 60, '2026-10-25': 60});
    });

    test('跨月拆分', () {
      final result = splitWatchSeconds(
        end: DateTime(2026, 2, 1, 0, 1),
        seconds: 120,
      );
      expect(result, {'2026-01-31': 60, '2026-02-01': 60});
    });

    test('跨年拆分', () {
      final result = splitWatchSeconds(
        end: DateTime(2027, 1, 1, 0, 1),
        seconds: 120,
      );
      expect(result, {'2026-12-31': 60, '2027-01-01': 60});
    });

    test('非正值返回空表，长区间总数严格守恒', () {
      expect(splitWatchSeconds(end: DateTime(2026), seconds: 0), isEmpty);
      expect(splitWatchSeconds(end: DateTime(2026), seconds: -1), isEmpty);

      final end = DateTime(2026, 3, 2, 13, 45);
      const seconds = 86400 * 2 + 3661;
      final result = splitWatchSeconds(end: end, seconds: seconds);
      expect(result.values.fold<int>(0, (total, value) => total + value), seconds);
    });
  });

  group('mergeWatchDays', () {
    test('正数累加，不修改入参，负值忽略', () {
      final base = {'2026-10-24': 60};
      final delta = {'2026-10-24': 30, '2026-10-25': 90, '2026-10-26': -1};
      final merged = mergeWatchDays(base, delta);

      expect(merged, {'2026-10-24': 90, '2026-10-25': 90});
      expect(base, {'2026-10-24': 60});
      expect(delta, {'2026-10-24': 30, '2026-10-25': 90, '2026-10-26': -1});
    });
  });
}
