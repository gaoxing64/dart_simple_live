import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/utils/watch_history_stats.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/watch_heatmap.dart';

void main() {
  test('年度网格 7 行，年份外补 null，天数与年份一致', () {
    final weeks = buildWatchHeatmapWeeks(2026);

    expect(weeks.every((week) => week.length == 7), isTrue);
    final dates = weeks.expand((week) => week.whereType<DateTime>()).toList();
    expect(dates.length, 365);
    expect(dates.map((date) => date.year).toSet(), {2026});
    expect(weeks[0].contains(null), isTrue);
    expect(weeks[0][DateTime(2026, 1, 1).weekday % 7], DateTime(2026, 1, 1));
    expect(dates.last, DateTime(2026, 12, 31));
  });

  test('强度分档按 30 分钟 / 2 小时 / 5 小时', () {
    expect(watchHeatmapLevel(0), 0);
    expect(watchHeatmapLevel(1), 1);
    expect(watchHeatmapLevel(30 * 60), 1);
    expect(watchHeatmapLevel(30 * 60 + 1), 2);
    expect(watchHeatmapLevel(2 * 60 * 60), 2);
    expect(watchHeatmapLevel(2 * 60 * 60 + 1), 3);
    expect(watchHeatmapLevel(5 * 60 * 60), 3);
    expect(watchHeatmapLevel(5 * 60 * 60 + 1), 4);
  });

  test('观看时长文案覆盖分钟、整小时和空值', () {
    expect(formatWatchSeconds(0), '0 分钟');
    expect(formatWatchSeconds(59), '0 分钟');
    expect(formatWatchSeconds(60), '1 分钟');
    expect(formatWatchSeconds(3600), '1 小时');
    expect(formatWatchSeconds(3661), '1 小时 1 分钟');
  });

  testWidgets('窄屏横向滑动，有记录的日子显示日期和时长提示', (tester) async {
    final day = DateTime(2026, 10, 24);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: WatchHeatmap(
                year: 2026,
                dailyWatchSeconds: {watchDateKey(day): 3661},
                // 锚定 1 月，保持本用例只验证格子间距，不被首帧对齐今天影响。
                today: DateTime(2026, 1, 2),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(ValueKey('watch-day-${watchDateKey(day)}')), findsOneWidget);

    // 相邻周列按 12dp 单元格 + 3dp 间隔排布；旧实现漏了列间隔，
    // 格子会横向粘成条，月份标签也会越往右偏得越多。
    final jan1 = tester.getRect(find.byKey(const ValueKey('watch-day-2026-01-01')));
    final jan4 = tester.getRect(find.byKey(const ValueKey('watch-day-2026-01-04')));
    final jan2 = tester.getRect(find.byKey(const ValueKey('watch-day-2026-01-02')));
    expect(jan4.left - jan1.left, closeTo(15, 0.5));
    expect(jan2.top - jan1.top, closeTo(15, 0.5));

    const expectedTooltip = '2026 年 10 月 24 日\n观看 1 小时 1 分钟';
    final dayElement = tester.element(find.byKey(ValueKey('watch-day-${watchDateKey(day)}')));
    // material_ui 的 Tooltip 与测试可直接导入的 Tooltip 存在同名类型歧义，
    // 这里按祖先节点断言消息，避免依赖具体 import。
    Object? tooltipWidget;
    dayElement.visitAncestorElements((element) {
      if (element.widget.runtimeType.toString() == 'Tooltip') {
        tooltipWidget = element.widget;
        return false;
      }
      return true;
    });
    expect(tooltipWidget, isNotNull);
    expect((tooltipWidget! as dynamic).message, expectedTooltip);

    // 移动端只滚动格子区：横向滚动后，周标签必须留在原位。
    final weekdayLabelBefore = tester.getRect(find.text('一')).left;
    final monthLabelBefore = tester.getRect(find.text('1 月')).left;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('一')).left, closeTo(weekdayLabelBefore, 0.5));
    expect(tester.getRect(find.text('1 月')).left, lessThan(monthLabelBefore));
  });

  testWidgets('移动端首帧把当前日期滚进可视区域', (tester) async {
    final today = DateTime(2026, 10, 24);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: WatchHeatmap(
                year: 2026,
                dailyWatchSeconds: const {},
                today: today,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heatRect = tester.getRect(find.byType(WatchHeatmap));
    final dayRect = tester.getRect(
      find.byKey(ValueKey('watch-day-${watchDateKey(today)}')),
    );
    // 周标签固定占左侧 32dp；当前日期列应落在剩余滚动视口内。
    expect(dayRect.left, greaterThanOrEqualTo(heatRect.left + 32));
    expect(dayRect.right, lessThanOrEqualTo(heatRect.right));
    // 默认从 1 月开始；对齐 10 月后必然已经发生横向滚动。
    expect(
      tester.getRect(find.byKey(const ValueKey('watch-day-2026-01-01'))).left,
      lessThan(heatRect.left),
    );
  });

  testWidgets('非当前年份不做当前日期对齐，仍从 1 月开始', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: WatchHeatmap(
                year: 2025,
                dailyWatchSeconds: const {},
                today: DateTime(2026, 10, 24),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heatRect = tester.getRect(find.byType(WatchHeatmap));
    expect(
      tester.getRect(find.byKey(const ValueKey('watch-day-2025-01-01'))).left,
      greaterThanOrEqualTo(heatRect.left + 32),
    );
  });

  testWidgets('宽屏整年直接放下，不需要横向滚动', (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: WatchHeatmap(year: 2026, dailyWatchSeconds: const {}),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('12 月'), findsOneWidget);
  });
}
