import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/history_service.dart';

void main() {
  group('RoomWatchClock', () {
    test('累计时长 = 基线 + 本次会话已走时长', () async {
      final clock = RoomWatchClock(baseline: const Duration(minutes: 10))..start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(clock.isRunning, isTrue);
      expect(clock.elapsed.inMilliseconds, greaterThan(0));
      expect(clock.total, greaterThan(const Duration(minutes: 10)));
      expect(clock.total, lessThan(const Duration(minutes: 11)));
    });

    test('落盘推进基线：连续两次落盘不会把同一段时间算两遍', () async {
      final clock = RoomWatchClock(baseline: const Duration(minutes: 1))..start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      clock.commit();
      final afterFirst = clock.total;
      expect(afterFirst, greaterThan(const Duration(minutes: 1)));
      // reset 只清零，紧接的这几微秒仍会走到表上，所以按毫秒粒度断言
      expect(clock.elapsed.inMilliseconds, 0);

      // 同一时刻再落一次：这一段时间已经进过基线了，总量不能再涨。
      clock.commit();
      expect((clock.total - afterFirst).abs(), lessThan(const Duration(milliseconds: 5)));
    });

    test('commit 之后继续走表，总量只加第二段', () async {
      final clock = RoomWatchClock(baseline: Duration.zero)..start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      clock.commit();
      final afterFirst = clock.total;

      await Future<void>.delayed(const Duration(milliseconds: 40));
      final total = clock.total;
      expect(total, greaterThan(afterFirst));
      expect(
        total.inMilliseconds,
        lessThan(280),
        reason: '两段约 150+40ms；若把第一段重复计入会到 ~340ms',
      );
    });

    test('rewind 保留累计时长，只把本次会话归零，且表继续走', () async {
      final clock = RoomWatchClock(baseline: const Duration(seconds: 5))..start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final total = clock.total;

      clock.rewind(total);
      expect(clock.elapsed.inMilliseconds, 0);
      expect((clock.total - total).abs(), lessThan(const Duration(milliseconds: 5)));
      // 时钟在表里就应该一直在走：只有 HistoryService.stop 会摘掉它
      expect(clock.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(clock.total, greaterThan(total));
    });

    test('重复 start 不重置计时、也不改基线', () async {
      final clock = RoomWatchClock(baseline: Duration.zero)..start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final before = clock.elapsed;

      clock.start();
      expect(clock.total, greaterThanOrEqualTo(before));
      expect(clock.elapsed, greaterThanOrEqualTo(before));
    });

    test('反复落盘时总量单调不减', () async {
      final clock = RoomWatchClock(baseline: const Duration(minutes: 1))..start();
      var last = clock.total;
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        clock.commit();
        expect(clock.total, greaterThanOrEqualTo(last));
        last = clock.total;
      }
    });
  });
}