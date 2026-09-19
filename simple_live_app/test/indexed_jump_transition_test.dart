// 回归测试：跨多个 Tab 的跳切（如「首页 → 我的」）也要有切换动画。
//
// 顺序切换是 PageView 自己整页平移；跳切如果也走 animateToPage，中间那些还没
// 实例化的占位页（SizedBox）会以空白形式闪过，所以实现改为 jumpToPage 瞬时
// 定位 + 视口补一次「滑入 + 淡入」。本测试锁住这个补丁：
//   * 跳切后的头几帧，视口必须处在过渡位移上，结束后精确归位；
//   * 顺序切换不受影响 —— 它照旧由 PageView 整页平移承担，视口本身不动。
//
// 本测试直接使用真实的 IndexedPage，仅替换网络数据源与本地存储。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 假设置：跳过本地存储，保持顶/底栏常驻，导航栏用默认样式。
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

/// 关注服务依赖 Hive 与网络，测试里只保留「空列表」状态。
class FakeFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> loadData({bool updateStatus = true, int? cycle}) async {}
}

Future<IndexedController> pumpIndexed(
  WidgetTester tester, {
  bool landscape = false,
}) async {
  tester.view.physicalSize = landscape
      ? const Size(800 * 3, 400 * 3)
      : const Size(400 * 3, 800 * 3);
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
  Get.put<AppSettingsController>(FakeSettings());
  Get.put<FollowService>(FakeFollowService());
  for (final site in Sites.supportSites) {
    // 先注册，HomeController 初始化时不会覆盖
    Get.put<HomeListController>(FakeHomeListController(site), tag: site.id);
  }
  Get.put(IndexedController());

  await tester.pumpWidget(GetMaterialApp(home: const IndexedPage()));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return Get.find<IndexedController>();
}

/// IndexedPage 的 PageView 视口左上角。
///
/// 取 `first` 是因为 TabBarView 内部也用了 PageView，而 `find.byType` 按深度
/// 优先前序返回，外层的视口一定排在前面。视口自身的盒子不随翻页移动，所以这个
/// 读数只会被跳切过渡影响 —— 正好用来区分「视口在动」和「页内内容在动」。
Offset viewportOrigin(WidgetTester tester) =>
    tester.getTopLeft(find.byType(PageView).first);

double viewportLeft(WidgetTester tester) => viewportOrigin(tester).dx;

double viewportTop(WidgetTester tester) => viewportOrigin(tester).dy;

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('向前跳切（首页 → 我的）沿来向滑入并归位', (tester) async {
    final indexed = await pumpIndexed(tester);
    final settled = viewportLeft(tester);

    indexed.setIndex(3);
    await tester.pump();

    final start = viewportLeft(tester);
    expect(
      start,
      greaterThan(settled + 10),
      reason: '跳切必须给视口一个起始位移，否则就是原来的瞬移',
    );

    await tester.pump(const Duration(milliseconds: 110));
    final mid = viewportLeft(tester);
    expect(mid, lessThan(start), reason: '位移应随过渡衰减');
    expect(mid, greaterThan(settled), reason: '过渡中不该提前归位');

    await tester.pump(const Duration(milliseconds: 300));
    expect(
      viewportLeft(tester),
      moreOrLessEquals(settled, epsilon: 0.01),
      reason: '过渡结束后视口必须精确回到原处',
    );
    expect(
      indexed.pageController.page,
      3,
      reason: '过渡期间不能重挂 PageView —— 重挂会退回 initialPage，停在首页',
    );
  });

  testWidgets('反向跳切（我的 → 首页）朝反方向滑入', (tester) async {
    final indexed = await pumpIndexed(tester);
    final settled = viewportLeft(tester);

    indexed.setIndex(3);
    await tester.pump(const Duration(milliseconds: 400));

    indexed.setIndex(0);
    await tester.pump();
    expect(
      viewportLeft(tester),
      lessThan(settled - 10),
      reason: '往回跳时内容应自另一侧滑入',
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(viewportLeft(tester), moreOrLessEquals(settled, epsilon: 0.01));
  });

  testWidgets('顺序切换（首页 → 关注）不触发视口过渡', (tester) async {
    final indexed = await pumpIndexed(tester);
    final settled = viewportLeft(tester);

    indexed.setIndex(1);
    await tester.pump();
    expect(
      viewportLeft(tester),
      moreOrLessEquals(settled, epsilon: 0.01),
      reason: '相邻页切换由 PageView 整页平移完成，视口不该再叠一层位移',
    );

    await tester.pump(const Duration(milliseconds: 110));
    expect(
      viewportLeft(tester),
      moreOrLessEquals(settled, epsilon: 0.01),
      reason: '顺序切换全程视口保持静止',
    );

    // 换页会让 easy_refresh 排一个零延时计时器，跑完它再结束，否则报 pending timer
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('横屏跳切改为纵向滑入', (tester) async {
    final indexed = await pumpIndexed(tester, landscape: true);
    final settled = viewportTop(tester);
    final settledLeft = viewportLeft(tester);

    indexed.setIndex(3);
    await tester.pump();
    expect(
      viewportTop(tester),
      greaterThan(settled + 10),
      reason: '横屏时导航栏在左侧、视口是垂直的，位移也该跟着换轴',
    );
    expect(
      viewportLeft(tester),
      moreOrLessEquals(settledLeft, epsilon: 0.01),
      reason: '换轴后不该在水平方向留下位移',
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(viewportTop(tester), moreOrLessEquals(settled, epsilon: 0.01));
  });
}
