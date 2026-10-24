import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/history.dart';

History _history() => History(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播',
      face: '',
      updateTime: DateTime(2026, 10, 24, 12),
    );

void main() {
  test('旧 JSON 缺每日字段时回落空表', () {
    final history = History.fromJson({
      'id': 'huya_123',
      'roomId': '123',
      'siteId': 'huya',
      'userName': '主播',
      'face': '',
      'updateTime': DateTime(2026, 10, 24, 12).toString(),
    });

    expect(history.dailyWatchSeconds, isEmpty);
    expect(history.dailySyncSeconds, isEmpty);
  });

  test('JSON 往返保留每日观看与未同步增量', () {
    final history = _history()
      ..dailyWatchSeconds = {
        '2026-10-24': 120,
      }
      ..dailySyncSeconds = {
        '2026-10-24': 30,
      };

    final restored = History.fromJson(history.toJson());
    expect(restored.dailyWatchSeconds, history.dailyWatchSeconds);
    expect(restored.dailySyncSeconds, history.dailySyncSeconds);
  });

  test('copyWith 保留每日字段', () {
    final history = _history()
      ..dailyWatchSeconds = {'2026-10-24': 60}
      ..dailySyncSeconds = {'2026-10-24': 15};

    final copied = history.copyWith(userName: '新主播名');
    expect(copied.dailyWatchSeconds, {'2026-10-24': 60});
    expect(copied.dailySyncSeconds, {'2026-10-24': 15});
  });
}
