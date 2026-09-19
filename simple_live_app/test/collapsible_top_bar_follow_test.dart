// 回归测试：关注页滑动收起顶栏。
//
// 底栏收起在 IndexedPage 顶层统一处理，所有 Tab 都生效；顶栏收起依赖每个
// Tab 自己的 CollapsibleTopBarScaffold。本测试锁住关注页的行为：
//   * 同步模式：手指拖动列表，顶栏跟随收起（barOffset 增加、CollapseSlot 变矮）；
//   * 即时模式：向上滑动列表，顶栏动画收起（showTopBar=false 且 CollapseSlot 归零）。
//
// 本测试直接使用真实的 IndexedPage / FollowUserPage，仅替换网络数据源与本地存储。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/collapse_slot.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 假设置：顶/底栏收起全开，导航栏用默认样式。
class FakeSettings extends AppSettingsController {
  FakeSettings({this.hideType = 1}) {
    siteSort.value = Sites.allSites.keys.toList();
    homeSort.value = Constant.allHomePages.keys.toList();
    hideTopBar.value = true;
    hideBottomBar.value = true;
    barHideType.value = hideType;
    navBarStyle.value = 0;
    firstRun = false;
  }

  final int hideType;

  @override
  // 不读取本地存储（Hive 在 widget test 的 fake-async 环境下不可用）
  // ignore: must_call_super
  void onInit() {}
}

/// 假数据源：只给第一页数据，不触发翻页。
class FakeHomeListController extends HomeListController {
  FakeHomeListController(super.site);

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    if (page > 1) return [];
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

/// 关注服务：预置一批未开播（status 0）的关注，让关注页列表足够长、可以滚动。
class FakeFollowService extends FollowService {
  FakeFollowService() {
    final now = DateTime.now();
    followList.addAll(
      List.generate(
        30,
        (i) => FollowUser(
          id: 'huya_r$i',
          roomId: 'r$i',
          siteId: 'huya',
          userName: 'anchor $i',
          face: '',
          addTime: now,
        ),
      ),
    );
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> loadData({bool updateStatus = true, int? cycle}) async {}
}

Future<IndexedController> pumpIndexed(
  WidgetTester tester, {
  int hideType = 1,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // 我的页顶部读版本号，不打桩会在 build 里抛 LateInitializationError
  Utils.packageInfo = PackageInfo(
    appName: 'Slive',
    packageName: 'com.gx.slive',
    version: '1.0.0',
    buildNumber: '1',
  );

  Get.reset();
  Get.put<AppSettingsController>(FakeSettings(hideType: hideType));
  Get.put<FollowService>(FakeFollowService());
  for (final site in Sites.supportSites) {
    Get.put<HomeListController>(FakeHomeListController(site), tag: site.id);
  }
  Get.put(IndexedController());

  await tester.pumpWidget(GetMaterialApp(home: const IndexedPage()));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return Get.find<IndexedController>();
}

/// 切到关注页并等数据就位。
Future<void> gotoFollowPage(WidgetTester tester, IndexedController indexed) async {
  indexed.setIndex(1);
  // 首次实例化关注页：refreshOnStart 拉数据 + easy_refresh 收起动画
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 关注页顶栏的收起槽高度（展开=56，收起=0）。
double followTopBarSlotHeight(WidgetTester tester) {
  // 「关注用户」是关注页 AppBar 的标题，用它定位该页自己的 CollapseSlot。
  final slot = find.ancestor(
    of: find.text('关注用户'),
    matching: find.byType(CollapseSlot),
  );
  if (slot.evaluate().isEmpty) {
    // 没进收起模式（普通 Scaffold），视为未收起。
    return 56;
  }
  return tester.getSize(slot.first).height;
}

/// 关注页里那个 PageGridView（限定在含「关注用户」的子树内）。
Finder followGrid(WidgetTester tester) {
  final scaffold = find.ancestor(
    of: find.text('关注用户'),
    matching: find.byType(Scaffold, skipOffstage: false),
  );
  return find.descendant(of: scaffold.first, matching: find.byType(PageGridView));
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('同步模式：关注页向上拖动列表，顶栏跟随收起', (tester) async {
    final indexed = await pumpIndexed(tester);
    await gotoFollowPage(tester, indexed);

    expect(followTopBarSlotHeight(tester), 56, reason: '初始应完全展开');

    await tester.drag(followGrid(tester), const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(indexed.barOffset.value, greaterThan(0),
        reason: '同步模式下拖动必须累计 barOffset');
    expect(followTopBarSlotHeight(tester), lessThan(56),
        reason: '顶栏必须跟着收起，不能固定不动');

    // 反向拖回，顶栏应重新展开
    await tester.drag(followGrid(tester), const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(followTopBarSlotHeight(tester), 56, reason: '反向滑动顶栏应展开回去');

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('即时模式：关注页向上滑动列表，顶栏动画收起', (tester) async {
    final indexed = await pumpIndexed(tester, hideType: 0);
    await gotoFollowPage(tester, indexed);

    expect(followTopBarSlotHeight(tester), 56, reason: '初始应完全展开');

    await tester.drag(followGrid(tester), const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(indexed.showTopBar.value, false, reason: '即时模式向上滑应置 showTopBar=false');
    // 动画进行中，槽高应正在变小（给足时间后应到 0）
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(followTopBarSlotHeight(tester), 0, reason: '顶栏必须收起到 0');

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });
}
