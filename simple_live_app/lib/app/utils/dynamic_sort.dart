import 'package:simple_live_app/app/utils/dynamic_filter.dart';

/// 排序条件
class SortCondition<T> {
  final Comparable Function(T item) valueGetter;
  final bool ascending;

  SortCondition({
    required this.valueGetter,
    this.ascending = true,
  });
}

extension MappableListExtension<T extends Mappable> on List<T> {
  /// 动态排序函数（**稳定排序**）。
  ///
  /// `List.sort` 不保证稳定，键完全相等的条目会被打乱重排。关注页的增量刷新
  /// 依赖稳定性：刷新期间逐条重排后，结束时这次整表排序若把相等项（例如
  /// 大量观看时长都是 0 的主播）重新洗牌，界面会再跳一次。这里用「原索引」
  /// 作为最后一级比较键，相等项保持既有顺序。
  List<T> dynamicSort(List<SortCondition<T>> sortConditions) {
    final indexed = List.generate(length, (i) => (i, this[i]));
    indexed.sort((a, b) {
      for (final cond in sortConditions) {
        final aValue = cond.valueGetter(a.$2);
        final bValue = cond.valueGetter(b.$2);

        final cmp = aValue.compareTo(bValue);
        if (cmp != 0) return cond.ascending ? cmp : -cmp;
      }
      return a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < length; i++) {
      this[i] = indexed[i].$2;
    }
    return this;
  }
}
