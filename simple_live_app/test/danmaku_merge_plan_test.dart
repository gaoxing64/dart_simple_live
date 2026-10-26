// 合并模式的纯决策逻辑：Rust 分组结果 -> 新建 / 原地更新 / 跳过。
//
// 钉住的关键行为（合并「氛围」不丢的底线）：
// - 只有 isNew 才新建展示项（飘屏也只在这一刻发射，带最终计数）
// - 非新组只更新已有展示项，绝不新建——否则长刷屏会退化成每 500ms 一条
// - 展示项被聊天区裁掉（或 firstIndex 越界）时跳过，不拿旧计数串成新条目
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/danmaku_merge_plan.dart';
import 'package:simple_live_core/simple_live_core.dart';

LiveMessage _msg(String text, {String user = "u"}) => LiveMessage(
      type: LiveMessageType.chat,
      userName: user,
      message: text,
      color: LiveMessageColor.white,
    );

DanmakuMergeGroup _group({
  required String key,
  required int firstIndex,
  required int windowCount,
  bool isNew = true,
}) =>
    DanmakuMergeGroup(
      key: key,
      firstIndex: firstIndex,
      windowCount: windowCount,
      isNew: isNew,
    );

void main() {
  test('isNew 组新建展示项，带窗口计数与首现消息', () {
    final batch = [_msg("666", user: "小红"), _msg("666", user: "小黄")];
    final actions = planDanmakuMerge(
      batch: batch,
      groups: [_group(key: "666", firstIndex: 0, windowCount: 2)],
      lookup: (_) => null,
    );

    expect(actions, hasLength(1));
    final create = actions.single as DanmakuMergeCreate;
    expect(create.key, "666");
    expect(create.count, 2);
    expect(create.message.userName, "小红", reason: "取首现那条的用户名/颜色/表情");
  });

  test('非新组只更新已有展示项，不新建', () {
    final existing = _msg("666", user: "小红")..repeatCount = 2;
    final actions = planDanmakuMerge(
      batch: [_msg("666", user: "小蓝")],
      groups: [_group(key: "666", firstIndex: 0, windowCount: 5, isNew: false)],
      lookup: (key) => key == "666" ? existing : null,
    );

    expect(actions, hasLength(1));
    final bump = actions.single as DanmakuMergeBump;
    expect(bump.count, 5);
    expect(bump.message, same(existing), reason: "原地更新同一条消息对象");
  });

  test('展示项已被裁掉时跳过，不复活旧计数', () {
    final actions = planDanmakuMerge(
      batch: [_msg("666")],
      groups: [_group(key: "666", firstIndex: 0, windowCount: 9, isNew: false)],
      lookup: (_) => null,
    );

    expect(actions.single, isA<DanmakuMergeSkip>());
  });

  test('firstIndex 越界时跳过（防御 Rust 侧与批长不同步）', () {
    final actions = planDanmakuMerge(
      batch: [_msg("666")],
      groups: [
        _group(key: "666", firstIndex: 3, windowCount: 2),
        _group(key: "777", firstIndex: -1, windowCount: 1),
      ],
      lookup: (_) => null,
    );

    expect(actions.every((a) => a is DanmakuMergeSkip), isTrue);
    expect(actions, hasLength(2));
  });

  test('多组按 Rust 返回顺序产出动作', () {
    final batch = [_msg("666"), _msg("777"), _msg("888")];
    final actions = planDanmakuMerge(
      batch: batch,
      groups: [
        _group(key: "666", firstIndex: 0, windowCount: 3),
        _group(key: "888", firstIndex: 2, windowCount: 2),
      ],
      lookup: (_) => null,
    );

    expect(actions.map((a) => (a as DanmakuMergeCreate).key), ["666", "888"]);
  });

  test('飘屏文案：计数大于 1 才带 ×N', () {
    expect(danmakuMergeText("666", 1), "666");
    expect(danmakuMergeText("666", 3), "666 ×3");
    expect(danmakuMergeText("哈 哈哈", 12), "哈 哈哈 ×12");
  });
}
