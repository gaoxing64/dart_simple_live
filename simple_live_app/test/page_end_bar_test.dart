// 回归测试：列表「到底」这件事要明确告诉用户，而不是留一片没有解释的空白；
// 同时守护首页网格的列数自适应逻辑。
//
// 背景：各平台能给出的内容量差异很大，翻到尽头时底部那片空白会让用户以为
// 还在加载或以为列表坏了。App 层用「没有下一页」这个通用事实（而不是某个
// 平台的特例）决定是否展示 [PageEndBar]。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/modules/home/home_list_view.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

LiveRoomItem _room(int id) => LiveRoomItem(
      roomId: 'r$id',
      title: 'room $id',
      cover: '',
      userName: 'user$id',
    );

/// 首屏即到底的内容源：一次给出全部内容，服务端明确说没有更多。
class EndsAtFirstPageController extends BasePageController<LiveRoomItem> {
  EndsAtFirstPageController({this.gateCount = -1});

  /// 挂起的页码（-1 表示不挂起）。用于观察"加载中"这一帧的界面状态。
  final int gateCount;
  Completer<void> gate = Completer<void>();
  final List<int> requestedPages = [];

  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page == gateCount) {
      await gate.future;
    }
    serverHasMore = false;
    return List.generate(45, _room);
  }
}

/// 真分页内容源：翻到最后一页后服务端说没有更多。
class PagedController extends BasePageController<LiveRoomItem> {
  PagedController({this.pages = 3});

  final int pages;
  final List<int> requestedPages = [];

  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    serverHasMore = page < pages;
    if (page > pages) return [];
    return List.generate(pageSize, (i) => _room((page - 1) * pageSize + i));
  }
}

ScrollPosition gridPosition(WidgetTester tester) {
  return tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((state) => state.position)
      .firstWhere((position) => position.axis == Axis.vertical);
}

/// 滚轮滚到底（桌面端真实交互路径）。
Future<void> wheelToBottom(WidgetTester tester) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byType(CustomScrollView).first)),
  );
  for (var i = 0; i < 300; i++) {
    final position = gridPosition(tester);
    if (position.maxScrollExtent - position.pixels <= 0) break;
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 500));
}

Future<C> pumpGrid<C extends BasePageController<LiveRoomItem>>(
  WidgetTester tester,
  C controller, {
  bool showEndBar = true,
}) async {
  tester.view.physicalSize = const Size(1280 * 3, 720 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(GetMaterialApp(
    home: Scaffold(
      body: PageGridView(
        pageController: controller,
        firstRefresh: true,
        showEndBar: showEndBar,
        crossAxisCount: 6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        itemBuilder: (_, i) => SizedBox(
          height: 168,
          child: Text(controller.list[i].roomId),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return controller;
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Get.reset();
  });

  // ---------- 列数自适应（纯逻辑） ----------

  group('resolveHomeColumns', () {
    test('仍有下一页时只看宽度', () {
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 12,
          canLoadMore: true,
        ),
        6,
        reason: '还有下一页时内容量每页都在变，跟着改列数会边加载边重排',
      );
    });

    test('空列表时保持按宽度', () {
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 0,
          canLoadMore: false,
        ),
        6,
      );
    });

    test('内容已填满视口时不减列', () {
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          // 45 条 / 6 列 = 8 行 × 180 = 1440 > 696
          itemCount: 45,
          canLoadMore: false,
        ),
        6,
      );
    });

    test('已到底且填不满时减列换行数（最大化露白场景）', () {
      // 12 条在 6 列下只有 2 行（360 < 696），减到 3 列变 4 行（720）刚好铺满
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 12,
          canLoadMore: false,
        ),
        3,
      );
    });

    test('悬浮底栏占位计入可用高度，会促成减列', () {
      // 8 条在 6/5/4 列下都只有 2 行（360 < 696），只有减到 3 列才变 3 行（540）
      // 扣掉 200 的底栏后可用高度只剩 496，540 就够铺满了
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 8,
          canLoadMore: false,
        ),
        6,
        reason: '不扣底栏时 540 也填不满 696，不该减列',
      );
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 8,
          canLoadMore: false,
          bottomInset: 200,
        ),
        3,
        reason: '底栏盖住的那段必须扣掉，否则会以为已经填满、把空白留在那里',
      );
    });

    test('减列有上限，减到下限仍填不满则退回按宽度', () {
      // 7 条只有减到 2 列才够（4 行），但上限是减 3 列（6→3），够不着就放弃
      expect(
        resolveHomeColumns(
          maxWidth: 1280,
          maxHeight: 720,
          itemCount: 7,
          canLoadMore: false,
        ),
        6,
        reason: '内容实在太少时不应把卡片拉得比例失调，交给结束提示解释空白',
      );
    });

    test('窄窗口不会减到 2 列以下', () {
      expect(
        resolveHomeColumns(
          maxWidth: 400,
          maxHeight: 720,
          itemCount: 3,
          canLoadMore: false,
        ),
        2,
      );
    });
  });

  // ---------- 到底状态 ----------

  test('首屏即到底的内容源不会再自动补页', () async {
    final controller = EndsAtFirstPageController();
    await controller.refreshData();

    expect(controller.list.length, 45);
    expect(controller.canLoadMore.value, isFalse,
        reason: '没有下一页时不能让自动补页继续空转');
    expect(controller.showEndBar, isTrue);
  });

  testWidgets('滚轮到底不发起新请求，并展示结束条', (tester) async {
    final controller = await pumpGrid(tester, EndsAtFirstPageController());

    expect(controller.requestedPages, [1], reason: '首屏只请求一次');

    // 结束条在列表最末尾，必须先滚到底才会被构建出来
    await wheelToBottom(tester);
    expect(
      controller.requestedPages,
      [1],
      reason: '已经到底，滚轮不应再发起分页请求',
    );
    expect(
      find.text('没有更多了'),
      findsOneWidget,
      reason: '到底要给用户一个明确解释，而不是一片空白',
    );

    // 静置也不该补页
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(controller.requestedPages, [1]);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('真分页平台翻到尽头展示「没有更多了」', (tester) async {
    final controller = await pumpGrid(tester, PagedController(pages: 3));

    // 一路加载到第 3 页：该页服务端即声明没有更多，之后不再请求
    await wheelToBottom(tester);
    expect(
      controller.requestedPages,
      [1, 2, 3],
      reason: '服务端在第 3 页就说没有更多了，不该再试探第 4 页',
    );
    expect(controller.canLoadMore.value, isFalse);
    expect(find.text('没有更多了'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('未开启 showEndBar 的列表不显示结束条', (tester) async {
    final controller =
        await pumpGrid(tester, EndsAtFirstPageController(), showEndBar: false);

    expect(controller.showEndBar, isTrue, reason: '控制器状态仍然是"到底"');
    expect(find.text('没有更多了'), findsNothing,
        reason: '关注页 / 历史记录是一次性全量数据，结束条没有意义');
  });

  testWidgets('加载中不显示结束条，加载完成后恢复', (tester) async {
    // 第 2 页会挂起，好让"加载中"这一帧稳定可观察
    final controller =
        await pumpGrid(tester, EndsAtFirstPageController(gateCount: 2));

    await wheelToBottom(tester);
    expect(controller.showEndBar, isTrue);
    expect(find.text('没有更多了'), findsOneWidget);

    // 手动拉起一次加载：结束条应让位给底部骨架
    controller.currentPage = 2;
    final loading = controller.loadData();
    await tester.pump();
    expect(controller.showEndBar, isFalse, reason: '加载中不显示结束条');
    expect(find.text('没有更多了'), findsNothing);

    controller.gate.complete();
    await loading;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.showEndBar, isTrue, reason: '加载结束且仍无下一页应恢复');
    expect(find.text('没有更多了'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });
}
