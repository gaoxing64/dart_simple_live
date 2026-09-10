// 回归测试：加载下一页时列表底部应出现骨架占位（用于视觉提示）。
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_app/widgets/page_list_view.dart';
import 'package:simple_live_app/widgets/skeleton.dart';

/// 第二页会挂起，直到 [release] 被调用
class SlowSecondPageController extends BasePageController<String> {
  final Completer<void> secondPageGate = Completer<void>();
  final List<int> requestedPages = [];

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page == 2) {
      await secondPageGate.future;
    }
    if (page > 3) return [];
    return List.generate(pageSize, (i) => 'p$page-$i');
  }
}

Future<void> pumpGrid(
  WidgetTester tester,
  SlowSecondPageController controller,
) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GetMaterialApp(
    home: Scaffold(
      body: PageGridView(
        pageController: controller,
        firstRefresh: true,
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        itemBuilder: (_, i) => Container(
          height: 160,
          color: const Color(0xFF00FF00),
          child: Text(controller.list[i]),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

ScrollPosition gridPosition(WidgetTester tester) {
  return tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((state) => state.position)
      .firstWhere(
        (position) =>
            position.axis == Axis.vertical && position.maxScrollExtent > 0,
      );
}

Future<void> swipe(WidgetTester tester, double dy) async {
  final center = tester.getCenter(find.byType(CustomScrollView).first);
  final gesture = await tester.startGesture(center);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(0, -dy / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('PageGridView 加载下一页时显示骨架，加载完成后消失', (tester) async {
    final controller = SlowSecondPageController();
    await pumpGrid(tester, controller);
    expect(controller.requestedPages, [1]);
    expect(find.byType(LiveRoomCardSkeleton), findsNothing);

    // 滑到接近底部，触发第二页加载（该页会挂起）
    var guard = 0;
    while (guard < 20) {
      final position = gridPosition(tester);
      if (position.maxScrollExtent - position.pixels <= 150) break;
      await swipe(tester, 300);
      guard++;
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.requestedPages.contains(2), isTrue, reason: '应触发第二页加载');
    expect(controller.loadingMore.value, isTrue, reason: '正在加载下一页');
    expect(
      find.byType(LiveRoomCardSkeleton),
      findsWidgets,
      reason: '加载下一页时应显示骨架占位',
    );

    // 放行第二页，骨架消失
    controller.secondPageGate.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(controller.loadingMore.value, isFalse);
    expect(
      find.byType(LiveRoomCardSkeleton),
      findsNothing,
      reason: '加载完成后骨架应消失',
    );
    expect(controller.list.length, greaterThan(24));
  });

  testWidgets('PageListView 加载下一页时显示行骨架', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = SlowSecondPageController();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageListView(
          pageController: controller,
          firstRefresh: true,
          itemBuilder: (_, i) => Container(
            height: 80,
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(ListRowSkeleton), findsNothing);

    // 滚到接近底部触发加载
    var guard = 0;
    while (guard < 20) {
      final position = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .map((state) => state.position)
          .firstWhere(
            (position) =>
                position.axis == Axis.vertical &&
                position.maxScrollExtent > 0,
          );
      if (position.maxScrollExtent - position.pixels <= 150) break;
      final center = tester.getCenter(find.byType(ListView).first);
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      guard++;
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.loadingMore.value, isTrue, reason: '正在加载下一页');
    expect(find.byType(ListRowSkeleton), findsWidgets, reason: '应显示行骨架');

    controller.secondPageGate.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(ListRowSkeleton), findsNothing);
  });

  testWidgets('骨架区按普通网格从左到右排列，不随瀑布流散落', (tester) async {
    tester.view.physicalSize = const Size(1285, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 20 条真实数据（6 列，最后一行不满，瀑布流列高不齐）
    final controller = _OddCountController();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: false,
          padding: const EdgeInsets.all(12),
          crossAxisCount: 6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          itemBuilder: (_, i) => Container(
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await controller.loadData();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 最后一行（20 条 = 3 整行 + 2 条）应靠左：第 19、20 条位于第 1、2 列
    final lastCount = controller.list.length;
    final rSecondLast = tester.getRect(find.text('p${lastCount - 2}'));
    final rLast = tester.getRect(find.text('p${lastCount - 1}'));
    expect(
      (rSecondLast.top - rLast.top).abs(),
      lessThan(1),
      reason: '最后一条真实数据应与其他同行',
    );
    expect(rSecondLast.left, lessThanOrEqualTo(13), reason: '最后一行应从第 1 列开始');
    expect(rLast.left, greaterThan(rSecondLast.left), reason: '最后一行的数据应向右排列');

    // 模拟加载更多中
    controller.loadding = true;
    controller.loadingMore.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final rects = find
        .byType(LiveRoomCardSkeleton)
        .evaluate()
        .map((e) {
      final box = e.renderObject as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList();
    expect(rects, isNotEmpty);

    // 20 条数据（第 4 行只有第 1、2 列是真实内容）：
    // 骨架第一行应先补齐第 3~6 列（与真实内容同一行），再往下补整行
    final firstRowY = rects.map((r) => r.top).reduce((a, b) => a < b ? a : b);
    final firstRow = rects.where((r) => (r.top - firstRowY).abs() < 1).toList();
    final xs = firstRow.map((r) => r.left.round()).toList()..sort();
    // 与真实内容最后一行同高（同一行）
    expect(
      (firstRowY - rLast.top).abs(),
      lessThan(1),
      reason: '骨架第一行应与真实内容最后一行在同一行',
    );
    // 补齐最后一行右侧的空位：4 张，从第 3 列开始，向左无空缺
    expect(firstRow.length, 4, reason: '最后一行剩余 4 个空位应补骨架');
    expect(
      toSetOf(xs).length,
      4,
      reason: '补齐的空位应从真实内容右侧开始，中间不留空缺',
    );
    expect(xs.first, greaterThanOrEqualTo(400), reason: '第 1、2 列已被真实内容占用');

    // 第二行骨架应是完整的一排
    final secondRowY = rects
        .map((r) => r.top)
        .where((y) => (y - firstRowY).abs() >= 1)
        .reduce((a, b) => a < b ? a : b);
    final secondRow =
        rects.where((r) => (r.top - secondRowY).abs() < 1).toList();
    expect(secondRow.length, 6, reason: '第二排骨架应完整');
    controller.loadding = false;
    controller.loadingMore.value = false;
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('小行高网格（列表样式条目）的骨架不会溢出', (tester) async {
    // 搜索页用户列表（itemExtent 76）、关注列表（itemExtent 96）用的是
    // ListTile 风格条目，远矮于卡片骨架（约 160 高）。SliverGrid 的
    // mainAxisExtent 是**紧**高度约束，套用卡片骨架会 RenderFlex 溢出。
    for (final extent in [76.0, 96.0]) {
      final overflow = await pumpGridWithSkeleton(
        tester,
        itemExtent: extent,
        skeletonBuilder: (_, __) => const ListRowSkeleton(),
      );
      expect(
        overflow,
        isNull,
        reason: 'itemExtent=$extent 时行骨架不应溢出',
      );
    }
  });

  testWidgets('未显式传骨架时按行高自动选择（不溢出）', (tester) async {
    final overflow = await pumpGridWithSkeleton(tester, itemExtent: 76);
    expect(
      overflow,
      isNull,
      reason: 'itemExtent 小于卡片骨架高度时应回退到行骨架',
    );
    expect(find.byType(ListRowSkeleton), findsWidgets, reason: '应使用行骨架');
  });

  testWidgets('列表样式的网格按传入 itemExtent 排列行', (tester) async {
    // history_page 等列表样式页面若不传 itemExtent，会使用卡片行高（168），
    // 行间出现过大的空隙。
    await pumpGridWithSkeleton(
      tester,
      itemExtent: 76,
      itemCount: 3,
      loadingMore: false,
    );
    final first = tester.getTopLeft(find.text('row0')).dy;
    final second = tester.getTopLeft(find.text('row1')).dy;
    expect(second - first, closeTo(76, 1), reason: '行距应与 itemExtent 一致');
  });
}

/// 渲染一个「正在加载下一页」的网格，返回本帧捕获到的异常（无异常为 null）。
///
/// [itemExtent] 为网格行高；[skeletonBuilder] 为空时走 PageGridView 的默认骨架。
Future<Object?> pumpGridWithSkeleton(
  WidgetTester tester, {
  required double itemExtent,
  IndexedWidgetBuilder? skeletonBuilder,
  int itemCount = 6,
  bool loadingMore = true,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final controller = BasePageController<String>();
  controller.list.value = List.generate(itemCount, (i) => 'row$i');
  controller.canLoadMore.value = true;
  // 阻止自动加载干扰（直接模拟"正在加载下一页"的状态）
  controller.loadding = true;
  controller.loadingMore.value = loadingMore;
  await tester.pumpWidget(GetMaterialApp(
    home: Scaffold(
      body: PageGridView(
        pageController: controller,
        firstRefresh: false,
        crossAxisCount: 1,
        itemExtent: itemExtent,
        skeletonBuilder: skeletonBuilder,
        itemBuilder: (_, i) => ListTile(title: Text(controller.list[i])),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.takeException();
}

/// 去重（List 没有 distinct 方法）
Set<int> toSetOf(List<int> xs) => xs.toSet();

/// 20 条数据（6 列时最后一行不满）
class _OddCountController extends BasePageController<String> {
  @override
  Future<List<String>> getData(int page, int pageSize) async {
    if (page > 1) return [];
    return List.generate(20, (i) => 'p$i');
  }
}
