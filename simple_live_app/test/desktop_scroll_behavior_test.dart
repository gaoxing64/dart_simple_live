// 回归测试：桌面端应能用鼠标左键左右拖动切换平台标签（与移动端体验一致）。
//
// Flutter 默认的 ScrollBehavior.dragDevices 只含触摸类指针，鼠标被排除在外，
// 桌面端按住左键拖动不会滚动任何 Scrollable：手机上能左右滑动切换平台标签，
// 桌面上却只能点标签。AppScrollBehavior 把 dragDevices 放开为全部指针设备，
// 由 main.dart 挂在 GetMaterialApp.scrollBehavior 上修复该问题。
//
// 本测试直接使用真实的 IndexedPage / HomePage，仅替换网络数据源。
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_page.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 假设置：跳过本地存储，保持顶/底栏常驻（首页走 _buildNormal 分支）。
class FakeSettings extends AppSettingsController {
  FakeSettings() {
    siteSort.value = Sites.allSites.keys.toList();
    homeSort.value = Constant.allHomePages.keys.toList();
    hideTopBar.value = false;
    hideBottomBar.value = false;
    barHideType.value = 1;
    navBarStyle.value = 0;
    firstRun = false;
  }

  @override
  // 不读取本地存储（Hive 在 widget test 的 fake-async 环境下不可用）
  // ignore: must_call_super
  void onInit() {}
}

/// 假数据源：始终返回满一页数据，不触发翻页，聚焦标签切换本身。
class FakeHomeListController extends HomeListController {
  FakeHomeListController(super.site);

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
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

Future<void> pumpHome(
  WidgetTester tester, {
  ScrollBehavior? scrollBehavior,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  Get.reset();
  Get.put<AppSettingsController>(FakeSettings());
  for (final site in Sites.supportSites) {
    // 先注册，HomeController 初始化时不会覆盖
    Get.put<HomeListController>(FakeHomeListController(site), tag: site.id);
  }
  Get.put(IndexedController());

  await tester.pumpWidget(
    GetMaterialApp(home: const IndexedPage(), scrollBehavior: scrollBehavior),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// 搜索页：验证平台标签不再被 NeverScrollableScrollPhysics 锁死。
///
/// 该限制是抖音搜索用 WebView 时的遗留（WebView 会吞横向拖动），后来抖音搜索
/// 改回普通列表，限制就该撤掉；否则首页能左右滑、搜索页不能，两端都不一致。
Future<void> pumpSearch(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  Get.reset();
  Get.put<AppSettingsController>(FakeSettings());
  Get.put(AppSearchController());

  await tester.pumpWidget(
    GetMaterialApp(
      home: const SearchPage(),
      scrollBehavior: const AppScrollBehavior(),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// 以鼠标左键在 [finder] 中心横向拖动 [dx]（负值向左），
/// 并等待 PageView 吸附动画结束（TabController.index 在 ScrollEnd 时才更新）。
Future<void> mouseDrag(WidgetTester tester, Finder finder, double dx) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
  );
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  // 页面吸附 + 尾部计时器，避免用例结束时报 pending timer
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
void main() {
  setUp(() {
    Get.testMode = true;
  });

  test('AppScrollBehavior 放开鼠标等全部指针设备', () {
    const behavior = AppScrollBehavior();
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, containsAll(PointerDeviceKind.values));
  });

  testWidgets('默认滚动行为下鼠标左右拖动不会切换平台标签', (tester) async {
    await pumpHome(tester);
    final home = Get.find<HomeController>();
    expect(home.tabController.index, 0);

    await mouseDrag(tester, find.byType(TabBarView), -300);

    expect(
      home.tabController.index,
      0,
      reason: '默认 dragDevices 不含鼠标，这正是桌面端拖不动的根因',
    );
  });

  testWidgets('AppScrollBehavior 下鼠标左右拖动可切换平台标签', (tester) async {
    await pumpHome(tester, scrollBehavior: const AppScrollBehavior());
    final home = Get.find<HomeController>();
    expect(home.tabController.index, 0);

    await mouseDrag(tester, find.byType(TabBarView), -300);
    expect(
      home.tabController.index,
      1,
      reason: '放开鼠标后，向左拖动应切换到下一个平台',
    );

    // 反向拖回应回到第一个平台
    await mouseDrag(tester, find.byType(TabBarView), 300);
    expect(home.tabController.index, 0, reason: '向右拖动应切回上一个平台');
  });

  testWidgets('搜索页也能左右拖动切换平台', (tester) async {
    await pumpSearch(tester);
    final search = Get.find<AppSearchController>();
    expect(search.tabController.index, 0);

    await mouseDrag(tester, find.byType(TabBarView), -300);
    expect(
      search.tabController.index,
      1,
      reason: '搜索页的平台标签应与首页一样可以左右拖动切换',
    );
  });
}
