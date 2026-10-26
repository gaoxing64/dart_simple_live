import 'package:simple_live_core/simple_live_core.dart';

/// 合并模式单批处理的**纯决策**：输入本批弹幕与 Rust 分组结果，输出要执行的动作。
///
/// 抽成纯函数是为了可测——真正的副作用（改列表、发飘屏）留在 controller 里。
/// 规则：
/// - `isNew` ⇒ 新建展示项（飘屏也只在这一次发射，带最终计数）
/// - 否则 ⇒ 原地更新已有展示项的计数
/// - 展示项已被聊天区裁掉（或索引越界）⇒ 跳过，不拿旧计数串成新条目
List<DanmakuMergeAction> planDanmakuMerge({
  required List<LiveMessage> batch,
  required List<DanmakuMergeGroup> groups,
  required LiveMessage? Function(String key) lookup,
}) {
  final actions = <DanmakuMergeAction>[];
  for (final group in groups) {
    if (group.firstIndex < 0 || group.firstIndex >= batch.length) {
      actions.add(const DanmakuMergeSkip("firstIndex 越界"));
      continue;
    }
    final message = batch[group.firstIndex];
    if (group.isNew) {
      actions.add(
        DanmakuMergeCreate(
          key: group.key,
          message: message,
          count: group.windowCount,
        ),
      );
      continue;
    }
    final existing = lookup(group.key);
    if (existing == null) {
      actions.add(const DanmakuMergeSkip("展示项已被裁掉"));
      continue;
    }
    actions.add(
      DanmakuMergeBump(
        key: group.key,
        message: existing,
        count: group.windowCount,
      ),
    );
  }
  return actions;
}

/// 合并后的飘屏文案：计数 >1 时附「×N」，否则原样。
String danmakuMergeText(String text, int count) =>
    count > 1 ? "$text ×$count" : text;

/// 合并动作基类
sealed class DanmakuMergeAction {
  const DanmakuMergeAction();
}

/// 新建展示项：聊天区追加，飘屏发射一次
class DanmakuMergeCreate extends DanmakuMergeAction {
  const DanmakuMergeCreate({
    required this.key,
    required this.message,
    required this.count,
  });

  final String key;
  final LiveMessage message;
  final int count;
}

/// 已有展示项：原地把计数更新为 [count]
class DanmakuMergeBump extends DanmakuMergeAction {
  const DanmakuMergeBump({
    required this.key,
    required this.message,
    required this.count,
  });

  final String key;
  final LiveMessage message;
  final int count;
}

/// 跳过（附原因，便于日志排查）
class DanmakuMergeSkip extends DanmakuMergeAction {
  const DanmakuMergeSkip(this.reason);

  final String reason;
}
