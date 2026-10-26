import 'package:flutter/material.dart';
import 'package:simple_live_app/app/utils/watch_history_stats.dart';

const double _cellSize = 12;
const double _cellGap = 3;
const double _cellStride = _cellSize + _cellGap;
const double _dayLabelWidth = 32;

/// 返回按周排列的年度日期；周日为每周第一列，年份之外的日期为 null。
List<List<DateTime?>> buildWatchHeatmapWeeks(int year) {
  final firstDay = DateTime(year);
  final lastDay = DateTime(year, 12, 31);
  final gridStart = firstDay.subtract(Duration(days: firstDay.weekday % 7));
  final weekCount = lastDay.difference(gridStart).inDays ~/ 7 + 1;
  return List.generate(weekCount, (week) {
    return List.generate(7, (weekday) {
      final date = gridStart.add(Duration(days: week * 7 + weekday));
      return date.year == year ? date : null;
    });
  });
}

/// 观看强度：30 分钟、2 小时、5 小时为分档边界。
int watchHeatmapLevel(int seconds) {
  if (seconds <= 0) return 0;
  if (seconds <= 30 * 60) return 1;
  if (seconds <= 2 * 60 * 60) return 2;
  if (seconds <= 5 * 60 * 60) return 3;
  return 4;
}

String formatWatchSeconds(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}

String _fullDate(DateTime date) => '${date.year} 年 ${date.month} 月 ${date.day} 日';

class WatchHeatmap extends StatefulWidget {
  final int year;
  final Map<String, int> dailyWatchSeconds;

  /// 注入用；默认系统今天，用于移动端首帧对齐当前日期。
  final DateTime? today;

  const WatchHeatmap({
    super.key,
    required this.year,
    required this.dailyWatchSeconds,
    this.today,
  });

  @override
  State<WatchHeatmap> createState() => _WatchHeatmapState();
}

class _WatchHeatmapState extends State<WatchHeatmap> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _todayCellKey = GlobalKey();

  /// 已做过“对齐当前日期”的年份。避免父级 Obx 重建时把用户手动滚动拉回去。
  int? _alignedYear;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _levelColor(ColorScheme scheme, int level) {
    if (level == 0) {
      return scheme.surfaceContainerHighest.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.4 : 0.7,
      );
    }
    const alphas = [0.0, 0.28, 0.48, 0.72, 1.0];
    return scheme.primary.withValues(alpha: alphas[level]);
  }

  /// 当前日期所在周列的横向居中偏移；非当前年份回到最前面。
  void _alignToTodayOnce(DateTime today) {
    if (_alignedYear == widget.year) {
      return;
    }
    _alignedYear = widget.year;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final todayContext = _todayCellKey.currentContext;
      if (todayContext != null) {
        // alignment 0.5 = 让当天格尽量居中；贴边年份由框架自动夹到边界。
        Scrollable.ensureVisible(
          todayContext,
          alignment: 0.5,
          duration: Duration.zero,
        );
        return;
      }
      // 非当前年份没有当天格：切换年份后回到 1 月。
      if (_scrollController.hasClients && _scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weeks = buildWatchHeatmapWeeks(widget.year);
    final firstDay = DateTime(widget.year);
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final gridWidth = weeks.length * _cellStride;
    // 7 行格子：6 行完整 stride + 最后一行只占格子本身。
    final gridHeight = _cellStride * 6 + _cellSize;
    final today = widget.today ?? DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
        );

    final weekdayLabels = _WeekdayLabels(labelStyle: labelStyle);
    final grid = SizedBox(
      width: gridWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthLabels(
            year: widget.year,
            gridStart: gridStart,
            width: gridWidth,
            labelStyle: labelStyle,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final week in weeks)
                // 周列必须显式占满一个 stride：单元格本身只有 12dp，
                // 少了右侧 3dp 间隔时列会按 12dp 紧贴，月份标签却按 15dp
                // 定位，越往右偏得越多（整片还会糊成横条）。
                SizedBox(
                  width: _cellStride,
                  height: gridHeight,
                  child: Column(
                    children: [
                      for (var weekday = 0; weekday < 7; weekday++)
                        Padding(
                          padding: EdgeInsets.only(bottom: weekday == 6 ? 0 : _cellGap),
                          child: _DayCell(
                            key: week[weekday] == normalizedToday ? _todayCellKey : null,
                            date: week[weekday],
                            seconds: week[weekday] == null
                                ? 0
                                : widget.dailyWatchSeconds[watchDateKey(week[weekday]!)] ?? 0,
                            emptyColor: _levelColor(scheme, 0),
                            color: _levelColor(
                              scheme,
                              watchHeatmapLevel(
                                week[weekday] == null
                                    ? 0
                                    : widget.dailyWatchSeconds[watchDateKey(week[weekday]!)] ?? 0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth = _dayLabelWidth + gridWidth;
        // 桌面/宽屏：整张年度图直接放下。
        // 移动端：只滚动格子 + 月份标签；周标签固定在左侧，图例固定在
        // 可视宽度内，避免“横向滚动把坐标轴一起带走”的难用形态。
        final canFit = constraints.maxWidth >= requiredWidth;
        final heat = canFit
            ? SizedBox(
                width: requiredWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    weekdayLabels,
                    grid,
                  ],
                ),
              )
            : () {
                // 首帧（以及切换年份后）对齐当前日期；用户随后手动滚动不被覆盖。
                _alignToTodayOnce(today);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _dayLabelWidth,
                      // 顶部 20dp 是月份标签行，保证“一/三/五”始终对齐格子行。
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          weekdayLabels,
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _scrollController,
                        child: grid,
                      ),
                    ),
                  ],
                );
              }();

        final legendWidth = canFit ? requiredWidth : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heat,
            const SizedBox(height: 12),
            SizedBox(
              width: legendWidth,
              child: Row(
                children: [
                  const Spacer(),
                  Text('少', style: labelStyle),
                  const SizedBox(width: 6),
                  for (var level = 0; level <= 4; level++)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Container(
                        width: _cellSize,
                        height: _cellSize,
                        decoration: BoxDecoration(
                          color: _levelColor(scheme, level),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text('多', style: labelStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthLabels extends StatelessWidget {
  final int year;
  final DateTime gridStart;
  final double width;
  final TextStyle? labelStyle;

  const _MonthLabels({
    required this.year,
    required this.gridStart,
    required this.width,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 20,
      child: Stack(
        children: [
          for (var month = 1; month <= 12; month++)
            Positioned(
              left: (DateTime(year, month).difference(gridStart).inDays ~/ 7) * _cellStride,
              child: Text('$month 月', style: labelStyle),
            ),
        ],
      ),
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  final TextStyle? labelStyle;

  const _WeekdayLabels({required this.labelStyle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _dayLabelWidth,
      child: Column(
        children: [
          for (var weekday = 0; weekday < 7; weekday++)
            SizedBox(
              height: weekday == 6 ? _cellSize : _cellStride,
              child: weekday == 1 || weekday == 3 || weekday == 5
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        const ['', '一', '', '三', '', '五', ''][weekday],
                        style: labelStyle,
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime? date;
  final int seconds;
  final Color emptyColor;
  final Color color;

  const _DayCell({
    super.key,
    required this.date,
    required this.seconds,
    required this.emptyColor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final current = date;
    if (current == null) return const SizedBox(width: _cellSize, height: _cellSize);
    return Tooltip(
      message: '${_fullDate(current)}\n${seconds > 0 ? '观看 ${formatWatchSeconds(seconds)}' : '没有观看记录'}',
      child: Container(
        key: ValueKey('watch-day-${watchDateKey(current)}'),
        width: _cellSize,
        height: _cellSize,
        decoration: BoxDecoration(
          color: seconds > 0 ? color : emptyColor,
          borderRadius: BorderRadius.circular(2.5),
        ),
      ),
    );
  }
}
