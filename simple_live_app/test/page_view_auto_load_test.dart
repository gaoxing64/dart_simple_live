// 回归测试：列表滑动到接近底部时应自动加载下一页。
//
// 原项目使用 flutter_easyrefresh，其 MaterialFooter 默认 enableInfiniteLoad = true，
// 到达底部即自动加载；迁移到 easy_refresh 后必须显式配置 infiniteOffset，
// 否则要越界下拉（且距离足够）才会触发加载。
//
// 本测试直接使用真实的 IndexedPage / HomePage / PageGridView，仅替换网络数据源。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 假设置：跳过本地存储，直接指定顶/底栏收起开关。
class FakeSettings extends AppSettingsController {
  FakeSettings({required bool collapse}) {
    siteSort.value = Sites.allSites.keys.toList();
    homeSort.value = Constant.allHomePages.keys.toList();
    hideTopBar.value = collapse;
    hideBottomBar.value = collapse;
    barHideType.value = 1;
    navBarStyle.value = 0;
    firstRun = false;
  }

  @override
  // 不读取本地存储（Hive 在 widget test 的 fake-async 环境下不可用）
  // ignore: must_call_super
  void onInit() {}
}

/// 假数据源：共 3 页数据，之后返回空表示没有更多。
class FakeHomeListController extends HomeListController {
  FakeHomeListController(super.site);

  final List<int> requestedPages = [];

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page > 3) return [];
    return List.generate(
      pageSize,
      (i) => LiveRoomItem(
        roomId: 'r$page-$i',
        title: 'room $page-$i',
        cover: '',
        userName: 'user $page-$i',
      ),
    );
  }
}

/// 始终返回空数据的控制器，用于验证空列表下不会自动加载。
class EmptyController extends BasePageController<String> {
  int dataCalls = 0;

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    dataCalls++;
    return [];
  }
}

Future<FakeHomeListController> pumpApp(
  WidgetTester tester, {
  required bool collapse,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  Get.reset();
  Get.put<AppSettingsController>(FakeSettings(collapse: collapse));

  final controllers = <FakeHomeListController>[];
  for (final site in Sites.supportSites) {
    final controller = FakeHomeListController(site);
    controllers.add(controller);
    // 先注册，IndexedController/HomeController 初始化时不会覆盖
    Get.put<HomeListController>(controller, tag: site.id);
  }
  Get.put(IndexedController());

  await tester.pumpWidget(GetMaterialApp(home: const IndexedPage()));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return controllers.first;
}

/// 逐帧滑动：dy > 0 表示手指上移（内容下滚）。
Future<void> swipe(WidgetTester tester, double dy) async {
  final center = tester.getCenter(find.byType(CustomScrollView).first);
  final gesture = await tester.startGesture(center);
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, -dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
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

/// 滑到列表底部（不做任何额外的越界下拉）。
///
/// 每补一页内容高度就增加一页，因此循环次数必须留够：一次滑动 300px，
/// 预算 60 次 ≈ 18000px，足以覆盖 BasePageController.pageSize（30 条 ≈ 2700px）
/// 连补三页后的总高度。到底即 break，预算宽裕不会拖慢用例。
Future<void> scrollToBottom(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    final position = gridPosition(tester);
    if (position.maxScrollExtent - position.pixels <= 20) break;
    await swipe(tester, 300);
  }
}

/// 等待 easy_refresh 的 processed 计时器结束，避免测试结束时报 pending timer。
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Get.reset();
  });

  for (final collapse in [false, true]) {
    testWidgets(
      '滑到底部自动加载下一页（顶/底栏收起=$collapse）',
      (tester) async {
        final controller = await pumpApp(tester, collapse: collapse);

        // 首屏（refreshOnStart）只加载第一页
        expect(controller.requestedPages, [1]);

        // 一次滑动到接近底部，不进行任何越界下拉
        await scrollToBottom(tester);

        // 到达底部应自动连续加载，直到没有更多数据
        expect(
          controller.requestedPages,
          [1, 2, 3, 4],
          reason: '到达底部应自动加载下一页，直到数据取完',
        );
        expect(controller.canLoadMore.value, isFalse);
        await settle(tester);
      },
    );
  }

  testWidgets('没有更多数据后不会重复请求', (tester) async {
    final controller = await pumpApp(tester, collapse: true);
    await scrollToBottom(tester);
    final requests = List<int>.of(controller.requestedPages);
    expect(requests.last, 4);

    // 继续上下滑动，不应再发起请求
    await swipe(tester, 300);
    await swipe(tester, -300);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.requestedPages, requests);
    await settle(tester);
  });

  testWidgets('空列表（firstRefresh=false）拖动不会自动请求', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = EmptyController();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: false,
          crossAxisCount: 2,
          itemBuilder: (_, i) => Text(controller.list[i]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.dataCalls, 0);

    // 手指上移（内容下滚）拖动：列表为空时不应触发加载请求
    for (var i = 0; i < 3; i++) {
      await swipe(tester, 300 + i * 100.0);
    }
    expect(controller.dataCalls, 0, reason: '列表为空时不应自动请求下一页');
    await settle(tester);
  });

  testWidgets('先空列表后出数据（搜索页场景）仍能自动加载', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = LateDataController();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: false,
          crossAxisCount: 2,
          itemBuilder: (_, i) => Container(
            height: 160,
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.requestedPages, isEmpty);

    // 模拟"搜索"后加载第一页
    controller.ready = true;
    await controller.loadData();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.requestedPages, [1]);

    // 滑到底部应自动加载下一页
    await scrollToBottom(tester);
    expect(
      controller.requestedPages.take(2).toList(),
      [1, 2],
      reason: '有数据后到底部应自动加载',
    );
    await settle(tester);
  });

  testWidgets('内容不足一屏时自动补齐，无需拖动或点击', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 每页只返回 4 条（两行），单页远不足以填满窗口
    final controller = ShortPageController();
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 不做任何交互：内容不足一屏时应主动补页，而不是停在第一页
    expect(
      controller.requestedPages.length,
      greaterThanOrEqualTo(2),
      reason: '单页不足一屏应自动补页，实际 ${controller.requestedPages}',
    );
    expect(
      controller.requestedPages.length,
      lessThanOrEqualTo(5),
      reason: '内容填满窗口后应停止加载，实际 ${controller.requestedPages}',
    );

    // 补页的判据是"内容超出一屏"：修复前停在两行，maxScrollExtent 恒为 0，
    // 列表既不可滚动、也不会再派发通知，加载链就此停滞
    final position = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((state) => state.position)
        .firstWhere((p) => p.axis == Axis.vertical);
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '补齐后内容应能撑满并超出一屏',
    );

    // 填满后静置不应继续请求
    final loaded = controller.requestedPages.length;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      controller.requestedPages.length,
      loaded,
      reason: '填满窗口后应停止自动加载',
    );
    await settle(tester);
  });

  testWidgets('窗口变大后内容不足一屏会自动补齐', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = PagedGridController();
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
    // 首屏 24 条（12 行）已撑满 800 高的窗口，不应补页
    expect(controller.requestedPages, [1]);

    // 模拟窗口最大化：视口高度骤增，原内容不再满屏
    tester.view.physicalSize = const Size(400 * 3, 4000 * 3);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      controller.requestedPages.length,
      greaterThan(1),
      reason: '视口变大后应继续补页，实际 ${controller.requestedPages}',
    );
    await settle(tester);
  });

  testWidgets('鼠标滚轮滚到底部自动加载', (tester) async {
    final controller = await pumpGrid(tester);
    expect(controller.requestedPages, [1]);

    // 滚轮到底后 pointerScroll 不会再改变位置，因此要在滚动过程中触发
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(CustomScrollView).first)),
    );
    var notches = 0;
    while (notches < 300) {
      final position = gridPosition(tester);
      if (position.maxScrollExtent - position.pixels <= 0) break;
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      // 每格都要等滚动动画走完：滚轮由 SmoothWheelScrollController 驱动
      // （见 app_scroll_behavior.dart），是 180ms 的动画而不是瞬时跳转。
      // 必须用 pumpAndSettle —— 重启动画后的第一帧 elapsed 恒为 0，
      // pump(时长) 只出一帧，位置永远不动。
      await tester.pumpAndSettle();
      notches++;
    }
    expect(
      controller.requestedPages.contains(2),
      isTrue,
      reason: '滚轮滑到底部应自动加载第二页',
    );
    await settle(tester);
  });

  testWidgets('缓慢拖动触底即自动加载（无需再滑一次）', (tester) async {
    final controller = await pumpGrid(tester);
    expect(controller.requestedPages, [1]);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(CustomScrollView).first));
    for (var i = 0; i < 400; i++) {
      final position = gridPosition(tester);
      if (position.maxScrollExtent - position.pixels <= 0) break;
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      controller.requestedPages.contains(2),
      isTrue,
      reason: '触底后应自动加载第二页',
    );
    await gesture.up();
    await settle(tester);
  });

  testWidgets('加载下一页失败后不会无限重试', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = FailAfterFirstPageController();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: true,
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          itemExtent: 120,
          itemBuilder: (_, i) => Container(
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 首屏只有 4 条、不足一屏，会自动补第二页——该页请求失败
    expect(
      controller.requestedPages,
      [1, 2],
      reason: '首屏不足一屏会自动补页，实际 ${controller.requestedPages}',
    );

    // 触底触发第二页（会失败）。失败后骨架消失 → 内容收缩 → 尺寸变化通知
    // 又会立刻触发一次自动加载，若不设门闩会形成"每帧一个请求 + 一个错误提示"
    // 的请求风暴（曾实测单次滑动后连续请求 14 次）。
    await swipe(tester, 300);
    await tester.pump(const Duration(milliseconds: 500));
    final attempts = controller.requestedPages.length;
    expect(controller.errors, isNotEmpty, reason: '第二页应失败一次');
    expect(
      attempts,
      lessThanOrEqualTo(3),
      reason: '失败后只允许极少次尝试（补页 1 次 + 至多 1 次边界触发），'
          '实际 ${controller.requestedPages}',
    );

    // 静置 4 秒：不应继续重试（修复前这里会持续请求）
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      controller.requestedPages.length,
      attempts,
      reason: '静置时不应继续自动重试，实际 ${controller.requestedPages}',
    );
    expect(
      controller.errors.length,
      attempts - 1,
      reason: '每个失败请求只提示一次错误',
    );
    await settle(tester);
  });

  testWidgets('失败后离开底部再触底可以重试', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = FailAfterFirstPageController(firstPageCount: 24);
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: true,
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          itemExtent: 120,
          itemBuilder: (_, i) => Container(
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    await scrollToBottom(tester);
    // 只断言"触底尝试过第二页"，不断言精确次数：
    // 失败后列表底部会多出一条重试条（约 45px），内容高度变化会让
    // 滑动过程中 extentAfter 短暂越过阈值、合法地解除门闩并多试一次
    expect(
      controller.requestedPages.take(2),
      [1, 2],
      reason: '触底应尝试加载第二页，实际 ${controller.requestedPages}',
    );
    expect(controller.errors, isNotEmpty, reason: '第二页应失败一次');
    final afterFail = controller.requestedPages.length;

    // 离开底部（extentAfter 远大于阈值）→ 门闩解除
    await swipe(tester, -400);
    await swipe(tester, -400);
    // 再次触底 → 允许重试一次
    await scrollToBottom(tester);
    expect(
      controller.requestedPages.length,
      greaterThan(afterFail),
      reason: '用户主动离开底部后再次触底应允许重试，'
          '实际 ${controller.requestedPages}',
    );
    // 上界取 +4：失败后列表末尾会多出/收起重试条（约 45px），内容高度随之
    // 变化，滑动中 extentAfter 会数次越过阈值、合法地多试几次。
    // 这里真正要守住的是"不出现请求风暴"——修复前单次滑动会连续请求 14 次。
    expect(
      controller.requestedPages.length,
      lessThanOrEqualTo(afterFail + 4),
      reason: '每次触底只允许少量重试，实际 ${controller.requestedPages}',
    );
    await settle(tester);
  });

  testWidgets('内容不满一屏时补页失败：重试条常驻，点击后恢复加载', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 首屏仅 4 条（不足一屏），之后每页都失败
    final controller = FailAfterFirstPageController(firstPageCount: 4);
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: true,
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          itemExtent: 120,
          itemBuilder: (_, i) => Container(
            color: const Color(0xFF00FF00),
            child: Text(controller.list[i]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(controller.requestedPages, [1, 2], reason: '首屏不足一屏会自动补页');

    // 核心断言：内容不满一屏时 extentAfter 恒为 0，门闩永远不会自行解除，
    // 因此必须有常驻的重试条，否则用户无路可走（下拉刷新是唯一出口）
    expect(
      find.text("加载失败，点击重试"),
      findsOneWidget,
      reason: '短列表补页失败后应出现常驻重试条',
    );
    expect(controller.showLoadMoreFailedBar, isTrue);

    // 静置不应自行重试（门闩仍在工作）
    final beforeTap = controller.requestedPages.length;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(controller.requestedPages.length, beforeTap,
        reason: '重试条出现不代表会自动重试，实际 ${controller.requestedPages}');

    // 点击重试 → 应重新发起请求（该控制器永久失败，用来验证点击确实生效）
    await tester.tap(find.text("加载失败，点击重试"));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      controller.requestedPages.length,
      greaterThan(beforeTap),
      reason: '点击重试条必须真的重新请求，实际 ${controller.requestedPages}',
    );
    expect(
      find.text("加载失败，点击重试"),
      findsOneWidget,
      reason: '再次失败后重试条应重新出现',
    );
    await settle(tester);
  });

  test('加载下一页途中刷新：不丢刷新、不把第二页当成第一页', () async {
    final controller = GatedSecondPageController();
    await controller.loadData();
    expect(controller.currentPage, 2);
    expect(controller.list.length, 4);

    // 第二页挂起时执行刷新
    final loadMore = controller.loadData();
    final refresh = controller.refreshData();
    controller.gate.complete();
    await loadMore;
    await refresh;

    expect(
      controller.requestedPages.where((p) => p == 1).length,
      2,
      reason: '刷新应真正发起第一页请求（不能被守卫丢弃）：'
          '${controller.requestedPages}',
    );
    expect(
      controller.list.every((e) => e.startsWith('p1-')),
      isTrue,
      reason: '刷新后列表应只包含第一页数据：${controller.list}',
    );
    expect(controller.currentPage, 2, reason: '刷新后应从第二页继续');
  });
}

/// 第二页会挂起，直到 [gate] 被放行。
class GatedSecondPageController extends BasePageController<String> {
  final Completer<void> gate = Completer<void>();
  final List<int> requestedPages = [];

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page == 2) {
      await gate.future;
    }
    return List.generate(4, (i) => 'p$page-$i');
  }
}

/// 第一页成功、之后每页都失败（模拟网络异常）。
class FailAfterFirstPageController extends BasePageController<String> {
  FailAfterFirstPageController({this.firstPageCount = 4});

  /// 第一页返回的条数（不覆盖 BasePageController.pageSize）
  final int firstPageCount;
  final List<int> requestedPages = [];
  final List<Object> errors = [];

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page == 1) {
      return List.generate(firstPageCount, (i) => 'p1-$i');
    }
    throw Exception('network down');
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    // 不弹 Toast（测试环境未初始化 SmartDialog）
    errors.add(exception);
  }
}

/// 多页数据源，用于滚轮 / 拖动自动加载测试。
class PagedGridController extends BasePageController<String> {
  PagedGridController({this.pages = 6});

  final int pages;
  final List<int> requestedPages = [];

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page > pages) return [];
    return List.generate(pageSize, (i) => 'p$page-$i');
  }
}

/// 每页只有 4 条数据，内容不足一屏。
class ShortPageController extends BasePageController<String> {
  final List<int> requestedPages = [];

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (page > 6) return [];
    return List.generate(4, (i) => 'p$page-$i');
  }
}

/// 用 PageGridView 直接搭建的列表（用于滚轮 / 拖动测试）。
Future<PagedGridController> pumpGrid(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final controller = PagedGridController();
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
  return controller;
}

/// 一开始返回空（模拟未搜索），ready 后返回数据。
class LateDataController extends BasePageController<String> {
  final List<int> requestedPages = [];
  bool ready = false;

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    if (!ready || page > 2) return [];
    return List.generate(pageSize, (i) => 'p$page-$i');
  }
}

