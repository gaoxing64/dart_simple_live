import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_selection.dart';

FollowUser _user(String id, {required int liveStatus}) {
  final user = FollowUser(
    id: id,
    roomId: id,
    siteId: "bilibili",
    userName: id,
    face: "",
    addTime: DateTime(2026, 1, 1),
  );
  // 0=未知 1=未开播 2=直播中
  user.liveStatus.value = liveStatus;
  return user;
}

void main() {
  group('selectForMultiPlay', () {
    test('全部未开播 → empty', () {
      final result = selectForMultiPlay([
        _user("a", liveStatus: 1),
        _user("b", liveStatus: 0),
      ]);
      expect(result.problem, MultiPlaySelectionProblem.empty);
      expect(result.rooms, isEmpty);
    });

    test('空选择 → empty', () {
      final result = selectForMultiPlay([]);
      expect(result.problem, MultiPlaySelectionProblem.empty);
    });

    test('只有 1 位在播 → 通过（退化成单画面由调用方处理）', () {
      final result = selectForMultiPlay([
        _user("a", liveStatus: 2),
        _user("b", liveStatus: 1),
      ]);
      expect(result.problem, MultiPlaySelectionProblem.none);
      expect(result.rooms.map((e) => e.id), ["a"]);
    });

    test('正好 4 位在播 → 通过', () {
      final result = selectForMultiPlay([
        for (var i = 0; i < 4; i++) _user("u$i", liveStatus: 2),
      ]);
      expect(result.problem, MultiPlaySelectionProblem.none);
      expect(result.rooms.length, 4);
    });

    test('5 位在播 → tooMany，且不偷偷截断', () {
      final result = selectForMultiPlay([
        for (var i = 0; i < 5; i++) _user("u$i", liveStatus: 2),
      ]);
      expect(result.problem, MultiPlaySelectionProblem.tooMany);
      expect(result.rooms.length, 5);
    });

    test('混入未开播的先剔除、再判上限', () {
      final result = selectForMultiPlay([
        _user("a", liveStatus: 2),
        _user("b", liveStatus: 1),
        _user("c", liveStatus: 2),
        _user("d", liveStatus: 0),
        _user("e", liveStatus: 2),
      ]);
      expect(result.problem, MultiPlaySelectionProblem.none);
      expect(result.rooms.map((e) => e.id), ["a", "c", "e"]);
    });

    test('上限可覆盖', () {
      final result = selectForMultiPlay(
        [for (var i = 0; i < 3; i++) _user("u$i", liveStatus: 2)],
        max: 2,
      );
      expect(result.problem, MultiPlaySelectionProblem.tooMany);
    });

    test('顺序保持传入顺序', () {
      final result = selectForMultiPlay([
        _user("z", liveStatus: 2),
        _user("a", liveStatus: 2),
      ]);
      expect(result.rooms.map((e) => e.id), ["z", "a"]);
    });
  });

  group('focusedSlotAfterRemoval', () {
    int next(int focused, int removed, int remaining) => focusedSlotAfterRemoval(
          focused: focused,
          removedIndex: removed,
          remainingLength: remaining,
        );

    test('删掉聚焦格之前的：焦点跟着同一格前移一位', () {
      expect(next(2, 0, 3), 1);
      expect(next(3, 1, 3), 2);
    });

    test('删掉聚焦格之后的：焦点不动', () {
      expect(next(0, 2, 3), 0);
      expect(next(1, 3, 3), 1);
    });

    test('删掉聚焦格自己：夹到最后一格', () {
      // 4 格删第 3 格（焦点就是它）→ 剩 3 格，焦点落到 2
      expect(next(3, 3, 3), 2);
      // 2 格删第 1 格 → 剩 1 格，焦点落到 0
      expect(next(1, 1, 1), 0);
    });

    test('越界一律夹回合法范围', () {
      expect(next(5, 0, 2), 1);
      expect(next(0, 0, 5), 0);
    });
  });
}