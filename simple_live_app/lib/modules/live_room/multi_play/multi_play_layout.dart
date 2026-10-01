/// 多开播放的布局引擎。
///
/// 纯算术、无 IO、无平台依赖（与 `PipAspectCalculator` 同一分层思路）：
/// 只回答「几路、怎么排、每格多大、窗口最小能到多少」，不碰任何 window/播放器 API，
/// 因此可以在 Dart VM 单测里把边界情况扫一遍。
library;

import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart' show immutable;

/// 多开路数上限。想降到 3 路只需改这一个常量，下游（布局、最小窗口、设置项）全自适应。
const int kMultiPlayMaxTiles = 4;

/// 格子之间的间距（逻辑像素）。
const double kMultiPlaySpacing = 8;

/// 单格最小宽度。低于此值不再塞得下有意义的一路画面。
const double kMultiPlayMinTileWidth = 240;

/// 单格最小高度（= 240 × 9/16，与 16:9 自洽）。
const double kMultiPlayMinTileHeight = 135;

/// 多开窗口下限里要预留的 chrome 尺寸（逻辑像素）。
///
/// 横屏时视频区右侧恒有 [kMultiPlayChromeWidth] 宽的聊天栏，纵向是 AppBar + 底栏。
/// 页面那边切底栏、算下限都按这两个值走，别各写各的。
const double kMultiPlayChromeWidth = 300;
const double kMultiPlayChromeHeight = 100;

/// 排布形态。UI 用它决定要不要画分隔线 / 是否需要横竖切换。
enum MultiPlayArrangement { single, sideBySide, stacked, grid }

/// 候选排布表：路数 → 按声明顺序排列的 `[rows, columns]`。
///
/// 声明顺序即「形状等价时的倾向」：2 路先横排、3/4 路先 2×2（宽窗最常见）。
const Map<int, List<List<int>>> _kArrangementCandidates = {
  1: [
    [1, 1],
  ],
  2: [
    [1, 2],
    [2, 1],
  ],
  3: [
    [2, 2],
    [1, 3],
    [3, 1],
  ],
  4: [
    [2, 2],
    [1, 4],
    [4, 1],
  ],
};

/// 一个可见格在网格中的位置。
@immutable
class MultiPlayTileSlot {
  const MultiPlayTileSlot({
    required this.index,
    required this.row,
    required this.col,
  });

  /// 房间下标（与 `MultiPlaySession.slots` 的下标一致，即「第几个加进来的」）。
  final int index;
  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiPlayTileSlot &&
          other.index == index &&
          other.row == row &&
          other.col == col;

  @override
  int get hashCode => Object.hash(index, row, col);

  @override
  String toString() => 'MultiPlayTileSlot($index @ $row,$col)';
}

/// 一次布局计算的结果。
@immutable
class MultiPlayLayoutSpec {
  const MultiPlayLayoutSpec({
    required this.arrangement,
    required this.rows,
    required this.columns,
    required this.slots,
    required this.hiddenIndexes,
    required this.totalCount,
    required this.tileAspect,
    required this.cellWidth,
    required this.cellHeight,
    required this.spacing,
  });

  final MultiPlayArrangement arrangement;
  final int rows;
  final int columns;

  /// 可见格，**恒按加入顺序**（第 0 格在左上角，其余按行优先排）。
  ///
  /// 排布与焦点无关：点某一格只会改高亮边框和音量，绝不会让画面跳位置。
  /// 早期版本把聚焦格排在第一位，结果「点下面那格，它就窜到左上角」，
  /// 用户明确否掉了这个行为。
  final List<MultiPlayTileSlot> slots;

  /// 因窗口过小被折叠、本次不渲染的房间下标（从最后加入的开始丢）。
  ///
  /// 正常路径上不该出现：多开窗口下限就是按当前路数「不折叠」算出来的
  /// （见 [resolveMultiPlayMinimumWindowSize]），`setMinimumSize` 会挡住再缩小。
  /// 它是下限设置失败或异常窄屏时的兜底。
  final List<int> hiddenIndexes;

  /// 会话里的总路数（含被折叠的）。
  final int totalCount;

  final double tileAspect;

  /// 单格尺寸（逻辑像素），已按 [spacing] 从可用区域里扣除。
  final double cellWidth;
  final double cellHeight;

  final double spacing;

  /// 是否有格被折叠（`hiddenIndexes` 非空即真）。
  bool get degraded => hiddenIndexes.isNotEmpty;

  /// 某个可见格的矩形（相对视频区域左上角）。
  ///
  /// 排布的全部尺寸换算都收在这里，网格只负责把结果画出来——两处各算一遍迟早会对不上。
  Rect rectOf(MultiPlayTileSlot slot) {
    return Rect.fromLTWH(
      slot.col * (cellWidth + spacing),
      slot.row * (cellHeight + spacing),
      cellWidth,
      cellHeight,
    );
  }
}

/// 由可用区域尺寸与路数推导排布。
///
/// 语义（顺序即优先级）：
/// 1. 路数夹到 `[1, kMultiPlayMaxTiles]`；可见格**恒按加入顺序**排（不随焦点变）。
/// 2. 候选排布按「块形状与窗口形状的接近程度」排序：`blockAspect = (cols/rows) ×
///    tileAspect`，取 `|log(blockAspect / windowAspect)|` 最小者；距离相等时按
///    [_kArrangementCandidates] 的声明顺序（宽窗倾向）。
/// 3. 取第一个「每格都不小于最小尺寸」的候选。全不可行则丢掉最后加入的一格后重试，
///    直到只剩 1 格。
/// 4. 传进来的 [maxWidth]/[maxHeight] 是**视频区域**（已扣掉 AppBar、侧栏等），
///    窗口整体下限请用 [resolveMultiPlayMinimumWindowSize] 计算。
///
/// 注意签名里**没有焦点**：焦点只影响高亮与音量分配，不影响谁在第几格。
MultiPlayLayoutSpec resolveMultiPlayLayout({
  required double maxWidth,
  required double maxHeight,
  required int roomCount,
  required double tileAspect,
  double spacing = kMultiPlaySpacing,
  double minTileWidth = kMultiPlayMinTileWidth,
  double minTileHeight = kMultiPlayMinTileHeight,
}) {
  final total = roomCount.clamp(1, kMultiPlayMaxTiles);
  final aspect = _usableAspect(tileAspect);

  for (var visible = total; visible >= 1; visible--) {
    final candidate = _pickArrangement(
      count: visible,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      spacing: spacing,
      minTileWidth: minTileWidth,
      minTileHeight: minTileHeight,
      tileAspect: aspect,
    );
    // 只剩一格时无论多小都接受：再退就没有可退的了。
    if (candidate == null && visible > 1) {
      continue;
    }
    final rows = candidate?[0] ?? 1;
    final cols = candidate?[1] ?? 1;
    final cellWidth = math.max(0.0, (maxWidth - (cols - 1) * spacing) / cols);
    final cellHeight = math.max(0.0, (maxHeight - (rows - 1) * spacing) / rows);

    final slots = <MultiPlayTileSlot>[];
    for (var i = 0; i < visible; i++) {
      slots.add(MultiPlayTileSlot(index: i, row: i ~/ cols, col: i % cols));
    }
    return MultiPlayLayoutSpec(
      arrangement: _arrangementOf(rows, cols, visible),
      rows: rows,
      columns: cols,
      slots: slots,
      hiddenIndexes: [for (var i = visible; i < total; i++) i],
      totalCount: total,
      tileAspect: aspect,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      spacing: spacing,
    );
  }

  // 不可达：`visible == 1` 一定会在循环里返回。
  throw StateError('多开布局无法解析（maxWidth=$maxWidth, maxHeight=$maxHeight）');
}

/// 给定路数下「不折叠」所需的窗口最小尺寸（逻辑像素，含 [chromeWidth]/[chromeHeight]）。
///
/// 以宽窗排布为基准（1 路 1×1、2 路 1×2、3/4 路 2×2），并按 [tileAspect] 把
/// 「最小宽 × 最小高」放大到该比例——窄高窗口能翻转成 4×1 排布，其单格高度需求
/// 由可行性回退覆盖，宽窗基准仍是安全下限。
///
/// 约定：返回值是**整个窗口**的尺寸，调用方需保证传给
/// [resolveMultiPlayLayout] 的区域尺寸 = 返回值 − chrome。满足该约定时
/// `resolveMultiPlayLayout(...).degraded == false` 恒成立（见单测）。
Size resolveMultiPlayMinimumWindowSize({
  required int roomCount,
  required double tileAspect,
  double spacing = kMultiPlaySpacing,
  double chromeWidth = 0,
  double chromeHeight = 0,
  double minTileWidth = kMultiPlayMinTileWidth,
  double minTileHeight = kMultiPlayMinTileHeight,
}) {
  final total = roomCount.clamp(1, kMultiPlayMaxTiles);
  final aspect = _usableAspect(tileAspect);
  final reference = _kArrangementCandidates[total]!.first;
  final rows = reference[0];
  final cols = reference[1];

  final cellWidth = math.max(minTileWidth, minTileHeight * aspect);
  final cellHeight = math.max(minTileHeight, minTileWidth / aspect);
  final blockWidth = cols * cellWidth + (cols - 1) * spacing;
  final blockHeight = rows * cellHeight + (rows - 1) * spacing;
  return Size(blockWidth + chromeWidth, blockHeight + chromeHeight);
}

/// 在候选中挑出第一个可行的排布；全不可行返回 null。
List<int>? _pickArrangement({
  required int count,
  required double maxWidth,
  required double maxHeight,
  required double spacing,
  required double minTileWidth,
  required double minTileHeight,
  required double tileAspect,
}) {
  final candidates = _kArrangementCandidates[count]!;
  final windowAspect = (maxWidth > 0 && maxHeight > 0 && maxWidth.isFinite && maxHeight.isFinite)
      ? maxWidth / maxHeight
      : tileAspect;
  final sorted = candidates.toList()
    ..sort((a, b) {
      final da = _shapeDistance(a, tileAspect, windowAspect);
      final db = _shapeDistance(b, tileAspect, windowAspect);
      if (da == db) {
        // Dart 的 sort 不稳定，这里显式按声明顺序兜底，保证「形状等价时倾向宽排」。
        return candidates.indexOf(a) - candidates.indexOf(b);
      }
      return da.compareTo(db);
    });

  for (final candidate in sorted) {
    final rows = candidate[0];
    final cols = candidate[1];
    final cellWidth = (maxWidth - (cols - 1) * spacing) / cols;
    final cellHeight = (maxHeight - (rows - 1) * spacing) / rows;
    if (cellWidth >= minTileWidth && cellHeight >= minTileHeight) {
      return candidate;
    }
  }
  return null;
}

/// 块形状与窗口形状的「差距」，取对数距离以对称对待横竖。
double _shapeDistance(List<int> candidate, double tileAspect, double windowAspect) {
  final blockAspect = (candidate[1] / candidate[0]) * tileAspect;
  if (blockAspect <= 0 || windowAspect <= 0) {
    return 0;
  }
  return math.log(blockAspect / windowAspect).abs();
}

MultiPlayArrangement _arrangementOf(int rows, int cols, int count) {
  if (count <= 1) {
    return MultiPlayArrangement.single;
  }
  if (rows == 1) {
    return MultiPlayArrangement.sideBySide;
  }
  if (cols == 1) {
    return MultiPlayArrangement.stacked;
  }
  return MultiPlayArrangement.grid;
}

double _usableAspect(double aspect) {
  if (!aspect.isFinite || aspect <= 0) {
    return 16 / 9;
  }
  return aspect;
}