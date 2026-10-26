import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/aggregate_search_controller.dart';
import 'package:simple_live_app/modules/search/aggregate_search_view.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_page.dart';

class _FakeSettings extends AppSettingsController {
  _FakeSettings() {
    siteSort.value = Sites.allSites.keys.toList();
    homeSort.value = Constant.allHomePages.keys.toList();
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

Future<void> drainEasyRefreshTimers(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> pumpSearchPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  Get.reset();
  Get.put<AppSettingsController>(_FakeSettings());
  Get.put(AppSearchController());
  await tester.pumpWidget(
    GetMaterialApp(
      home: const SearchPage(),
      scrollBehavior: const AppScrollBehavior(),
    ),
  );
  await drainEasyRefreshTimers(tester);
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('聚合搜索关闭时保留平台 Tab', (tester) async {
    await pumpSearchPage(tester);

    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('斗鱼直播'), findsOneWidget);
    expect(find.byType(AggregateSearchView), findsNothing);
  });

  testWidgets('聚合搜索开启时隐藏平台 Tab 并保留房间/主播切换', (tester) async {
    await pumpSearchPage(tester);
    final settings = Get.find<AppSettingsController>();

    settings.aggregateSearchEnabled.value = true;
    await drainEasyRefreshTimers(tester);

    expect(find.text('哔哩哔哩'), findsNothing);
    expect(find.text('斗鱼直播'), findsNothing);
    expect(find.byType(AggregateSearchView), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
    final searchModeMenu = tester.widget<PopupMenuButton<int>>(
      find.byType(PopupMenuButton<int>),
    );
    expect(searchModeMenu.position, PopupMenuPosition.under);
    expect(
      searchModeMenu.borderRadius,
      const BorderRadius.all(Radius.circular(20)),
    );
    expect(find.text('房间'), findsOneWidget);
    final aggregateController = Get.find<AggregateSearchController>(
      tag: AggregateSearchController.tag,
    );
    expect(aggregateController.searchMode.value, 0);

    await tester.tap(find.text('房间'));
    await drainEasyRefreshTimers(tester);
    expect(find.text('主播'), findsOneWidget);

    await tester.tap(find.text('主播'));
    await drainEasyRefreshTimers(tester);
    expect(find.text('主播'), findsOneWidget);
    expect(Get.find<AppSearchController>().searchMode.value, 1);
    expect(aggregateController.searchMode.value, 1);

    expect(
      Get.isRegistered<AggregateSearchController>(
        tag: AggregateSearchController.tag,
      ),
      isTrue,
    );
  });
}
