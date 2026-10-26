// 回归测试：打开搜索页时，默认选中的平台要跟随首页当前所在的平台。
//
// 背景：首页和搜索页的平台 tab 都取自同一个 `Sites.supportSites`（顺序一致），但搜索页
// 原先写死从下标 0 开始，于是在虎牙看直播时点搜索会弹回哔哩哔哩。现在由首页把当前平台的
// **id** 通过路由参数带过来（`HomeController.toSearch` → `Get.arguments` →
// `AppSearchController`），搜索页再按 id 反查下标。
//
// 传 id 而不是下标：下标会随设置里的「网站排序」变化，id 不会。
//
// 这里锁两件事：
//   1. 路由参数确实能传到搜索页的控制器（`Get.arguments` 在 binding 阶段可读）；
//   2. `index` 与 `TabController.initialIndex` 必须一起对齐——只设 initialIndex 的话，
//      界面停在虎牙、`doSearch()` 却会打到哔哩哔哩。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/routes/app_pages.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

void main() {
  late Directory tempDir;

  // 只初始化一次 Hive，临时目录留给系统回收（与 theme_mode_test 同做法）。
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('slive_search_initial_site');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    Get.testMode = true;
    await Get.put(LocalStorageService()).init();
    // Sites.supportSites 依赖它读取「网站排序」
    Get.put(AppSettingsController());
  });

  tearDown(() {
    Get.reset();
  });

  /// 平台 id 在 tab 列表里的下标（与生产代码同一个列表、同一个顺序）。
  int indexOf(String siteId) =>
      Sites.supportSites.indexWhere((e) => e.id == siteId);

  group('首页 tab -> 平台 id 的映射', () {
    test('取到的就是该下标的平台', () {
      for (var i = 0; i < Sites.supportSites.length; i++) {
        expect(siteIdAtHomeTab(i), Sites.supportSites[i].id);
      }
    });

    test('虎牙的下标不是 0（否则下面的用例会假通过）', () {
      expect(indexOf(Constant.kHuya), isNot(0));
    });

    test('下标越界时返回 null，交给搜索页回落到第一个', () {
      expect(siteIdAtHomeTab(-1), isNull);
      expect(siteIdAtHomeTab(Sites.supportSites.length), isNull);
    });
  });

  group('搜索页的初始平台', () {
    test('没带平台时停在第一个', () {
      final controller = AppSearchController();

      expect(controller.index, 0);
      expect(controller.tabController.index, 0);
    });

    test('带了平台 id 时，index 与 tabController 一起对齐', () {
      final controller = AppSearchController(initialSiteId: Constant.kHuya);

      expect(controller.index, indexOf(Constant.kHuya));
      expect(
        controller.tabController.index,
        controller.index,
        reason: '只设 initialIndex 不同步 index 的话，搜索会打到别的平台',
      );
    });

    test('带了已不存在的平台 id 时回落到第一个', () {
      final controller = AppSearchController(initialSiteId: 'not-a-site');

      expect(controller.index, 0);
      expect(controller.tabController.index, 0);
    });
  });

  group('端到端：首页在虎牙时点搜索', () {
    testWidgets('搜索页默认停在虎牙', (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: const Scaffold(),
          getPages: AppPages.routes,
        ),
      );

      final home = Get.put(HomeController());
      final huyaIndex = indexOf(Constant.kHuya);
      home.tabController.index = huyaIndex;

      home.toSearch();
      await tester.pumpAndSettle();

      final search = Get.find<AppSearchController>();
      expect(
        search.index,
        huyaIndex,
        reason: '首页在虎牙，搜索页也应当默认落在虎牙',
      );
      expect(search.initialSiteId, Constant.kHuya);
    });

    testWidgets('首页在抖音时点搜索，搜索页默认停在抖音', (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: const Scaffold(),
          getPages: AppPages.routes,
        ),
      );

      final home = Get.put(HomeController());
      final douyinIndex = indexOf(Constant.kDouyin);
      home.tabController.index = douyinIndex;

      home.toSearch();
      await tester.pumpAndSettle();

      expect(Get.find<AppSearchController>().index, douyinIndex);
    });

    testWidgets('关掉搜索后再打开，仍然重新跟随首页', (tester) async {
      // 「每次打开都继承」而不是「只在第一次打开时继承」——所以这里要确认搜索页
      // 的控制器确实随路由销毁，第二次打开拿到的是新实例。
      await tester.pumpWidget(
        GetMaterialApp(
          home: const Scaffold(),
          getPages: AppPages.routes,
        ),
      );

      final home = Get.put(HomeController());
      final huyaIndex = indexOf(Constant.kHuya);
      final douyinIndex = indexOf(Constant.kDouyin);

      home.tabController.index = huyaIndex;
      home.toSearch();
      await tester.pumpAndSettle();
      expect(Get.find<AppSearchController>().index, huyaIndex);

      Get.back();
      await tester.pumpAndSettle();

      // 回到首页后切到抖音，再打开搜索
      home.tabController.index = douyinIndex;
      home.toSearch();
      await tester.pumpAndSettle();
      expect(
        Get.find<AppSearchController>().index,
        douyinIndex,
        reason: '第二次打开不能沿用上一次的抖音/虎牙，必须重新读首页',
      );
    });
  });
}
