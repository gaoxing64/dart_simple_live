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
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

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

Future<void> pumpSearchPage(
  WidgetTester tester, {
  double logicalWidth = 400,
}) async {
  tester.view.physicalSize = Size(logicalWidth * 3, 800 * 3);
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
    // 聚合模式下模式只有聚合控制器那一份。这里断言按平台路径的页面 Rx 没被写：
    // 两处都存模式就会在在途请求期间「标签读一份、列表读另一份」而错位。
    expect(Get.find<AppSearchController>().searchMode.value, 0);
    expect(aggregateController.searchMode.value, 1);

    expect(
      Get.isRegistered<AggregateSearchController>(
        tag: AggregateSearchController.tag,
      ),
      isTrue,
    );
  });

  testWidgets('聚合结果条目可渲染，360 宽不溢出', (tester) async {
    // 窄屏（360 逻辑宽）跑一次真实条目：itemBuilder 里的卡片/ListTile 只有
    // 被真正构建过，列数公式与固定行高的溢出才会暴露。封面传空串走本地 logo
    // 占位（NetImage 对空 URL 不发网络请求），测试不依赖外网。
    await pumpSearchPage(tester, logicalWidth: 360);
    Get.find<AppSettingsController>().aggregateSearchEnabled.value = true;
    await drainEasyRefreshTimers(tester);

    final aggregate = Get.find<AggregateSearchController>(
      tag: AggregateSearchController.tag,
    );
    final site = Sites.allSites[Constant.kBiliBili]!;

    aggregate.list.assignAll([
      AggregateSearchItem.room(
        site,
        LiveRoomItem(
          roomId: 'r1',
          title: '这是一个很长很长用来验证单行省略的房间标题',
          cover: '',
          userName: '主播名字一',
          online: 12345,
        ),
      ),
      AggregateSearchItem.room(
        site,
        LiveRoomItem(
          roomId: 'r2',
          title: '房间二',
          cover: '',
          userName: '主播名字二',
        ),
      ),
    ]);
    await drainEasyRefreshTimers(tester);

    expect(find.text('这是一个很长很长用来验证单行省略的房间标题'), findsOneWidget);
    expect(find.text('房间二'), findsOneWidget);
    // 条目必须真的以卡片形态构建过，itemBuilder 的分支才算被覆盖
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // 直接翻模式位（走 updateSearchMode 会触发 _beginQuery 清空刚播种的列表），
    // 这里只验主播条目在窄屏单列下的渲染。
    aggregate.searchMode.value = 1;
    aggregate.list.assignAll([
      AggregateSearchItem.anchor(
        site,
        LiveAnchorItem(
          roomId: 'a1',
          avatar: '',
          userName: '主播一',
          liveStatus: true,
        ),
      ),
    ]);
    await drainEasyRefreshTimers(tester);

    expect(find.text('主播一'), findsOneWidget);
    expect(find.text('直播中'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
