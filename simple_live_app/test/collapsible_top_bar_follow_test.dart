// 回归测试：关注页滑动收起顶栏 / 底栏。
//
// 底栏收起在 IndexedPage 顶层统一处理，所有 Tab 都生效；顶栏收起依赖每个
// Tab 自己的 CollapsibleTopBarScaffold。本测试锁住关注页的**两件事**：
//
// 1. 收起生效：同步模式跟手位移、即时模式动画收起，两种模式下顶栏与内容区
//    都随滑动上移 / 复原；
// 2. 收起必须是纯绘制：过程中内容区（页面最重的滚动列表）的**尺寸恒定**。
//    旧实现用 `Align(heightFactor:)` 真实压缩顶栏高度，每帧都会触发父级重排
//    （列表视口尺寸变化 + 栏内 Material 重算），同步模式在安卓上就是掉帧的来源。
//    一旦有人把收起改回「改布局」，这里会立刻失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/bar_collapse.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 假设置：顶/底栏收起全开，导航栏样式可选。
class FakeSettings extends AppSettingsController {
  FakeSettings({this.hideType = 1, this.navStyle = 0}) {
    siteSort.value = Sites.allSites.keys.toList();
    homeSort.value = Constant.allHomePages.keys.toList();
    hideTopBar.value = true;
    hideBottomBar.value = true;
    barHideType.value = hideType;
    navBarStyle.value = navStyle;
    firstRun = false;
  }

  final int hideType;
  final int navStyle;

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
  int navStyle = 0,
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
  Get.put<AppSettingsController>(
    FakeSettings(hideType: hideType, navStyle: navStyle),
  );
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
Future<void> gotoFollowPage(
    WidgetTester tester, IndexedController indexed) async {
  indexed.setIndex(1);
  // 首次实例化关注页：refreshOnStart 拉数据 + easy_refresh 收起动画
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 关注页里那个 PageGridView（限定在含「关注用户」的子树内，
/// 避免命中保活中的首页同名组件）。
Finder followGrid(WidgetTester tester) {
  final scaffold = find.ancestor(
    of: find.text('关注用户'),
    matching: find.byType(Scaffold, skipOffstage: false),
  );
  return find.descendant(
    of: scaffold.first,
    matching: find.byType(PageGridView),
  );
}

/// 关注页顶栏的收起容器（定高槽位，尺寸应始终等于 toolbar 高度）。
///
/// ⚠️ 注意：这个盒子的**位置恒定不变**（收起就是靠它内部平移实现的），
/// 要判断栏"收起了多少"必须读它内部子节点的绘制位置，见 [followBarTitleTop]。
Finder followBar(WidgetTester tester) => find
    .ancestor(of: find.text('关注用户'), matching: find.byType(BarCollapse))
    .first;

/// 顶栏标题的绘制位置（含 [BarCollapse] 的平移），用它衡量顶栏收起程度。
double followBarTitleTop(WidgetTester tester) =>
    tester.getTopLeft(find.text('关注用户')).dy;

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('同步模式：顶栏跟手收起，且内容区尺寸恒定（不重排）', (tester) async {
    final indexed = await pumpIndexed(tester);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final barSlotSize = tester.getSize(followBar(tester));
    final gridSize = tester.getSize(grid);
    final gridTop = tester.getTopLeft(grid).dy;
    final barTop = followBarTitleTop(tester);
    // 列表视口尺寸 / 滚动范围：旧实现每帧改栏高 ⇒ 视口尺寸每帧变 ⇒ 滚动位置
    // 被反复校正，表现为拖动时"抽动"。这里钉死收起全程这两项都不变。
    final position = Get.find<FollowUserController>().scrollController.position;
    final viewport = position.viewportDimension;
    final maxExtent = position.maxScrollExtent;

    expect(indexed.barOffset.value, 0, reason: '初始应完全展开');

    // 分多帧慢慢拖动，逐帧检查：内容区尺寸恒定 + 顶栏位移严格等于累计偏移
    for (var i = 0; i < 4; i++) {
      await tester.drag(grid, const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getSize(grid),
        gridSize,
        reason: '第 $i 帧：收起过程中内容区尺寸不得变化（变化=每帧重排）',
      );
      expect(
        tester.getSize(followBar(tester)),
        barSlotSize,
        reason: '第 $i 帧：顶栏槽位高度必须恒定，否则父级会跟着重排',
      );
      expect(
        position.viewportDimension,
        viewport,
        reason: '第 $i 帧：列表视口尺寸不得随收起变化（否则滚动位置被反复校正）',
      );
      expect(
        position.maxScrollExtent,
        maxExtent,
        reason: '第 $i 帧：滚动范围不得随收起变化',
      );
      expect(
        barTop - followBarTitleTop(tester),
        moreOrLessEquals(indexed.barOffset.value, epsilon: 0.01),
        reason: '第 $i 帧：顶栏位移必须与累计偏移严格一致（跟手）',
      );
      expect(
        gridTop - tester.getTopLeft(grid).dy,
        moreOrLessEquals(indexed.barOffset.value, epsilon: 0.01),
        reason: '第 $i 帧：内容区必须与顶栏同步上移',
      );
    }

    expect(indexed.barOffset.value, greaterThan(0),
        reason: '同步模式下拖动必须累计 barOffset');

    // 拖足够远：完全收起，顶栏整条移出、内容区恰好上移一个顶栏高度
    await tester.drag(grid, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(indexed.barOffset.value, IndexedController.maxBarOffset,
        reason: '拖够距离后应完全收起');
    expect(barTop - followBarTitleTop(tester),
        moreOrLessEquals(IndexedController.maxBarOffset, epsilon: 0.01));
    expect(gridTop - tester.getTopLeft(grid).dy,
        moreOrLessEquals(IndexedController.maxBarOffset, epsilon: 0.01));
    expect(tester.getSize(grid), gridSize, reason: '拖动结束后内容区尺寸仍应恒定');

    // 反向拖回：顶栏与内容区一起复原
    await tester.drag(grid, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(indexed.barOffset.value, 0);
    expect(followBarTitleTop(tester), moreOrLessEquals(barTop, epsilon: 0.01));
    expect(tester.getTopLeft(grid).dy, moreOrLessEquals(gridTop, epsilon: 0.01));

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('即时模式：顶栏动画收起、内容区上移，尺寸同样恒定', (tester) async {
    final indexed = await pumpIndexed(tester, hideType: 0);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final barSlotSize = tester.getSize(followBar(tester));
    final gridSize = tester.getSize(grid);
    final gridTop = tester.getTopLeft(grid).dy;
    final barTop = followBarTitleTop(tester);

    await tester.drag(grid, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(indexed.showTopBar.value, false,
        reason: '即时模式向上滑应置 showTopBar=false');
    expect(tester.getSize(grid), gridSize, reason: '收起动画同样不得改变内容区尺寸');

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 完全收起：顶栏整体移出槽位（视觉上不可见），内容区上移一个 toolbar 高度
    expect(
      followBarTitleTop(tester),
      lessThanOrEqualTo(barTop - barSlotSize.height + 0.5),
      reason: '顶栏必须完全移出槽位',
    );
    expect(
      tester.getTopLeft(grid).dy,
      moreOrLessEquals(gridTop - barSlotSize.height, epsilon: 0.5),
      reason: '内容区应恰好上移一个顶栏高度',
    );

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('底栏收起不改布局：悬浮胶囊样式下内容区尺寸也恒定', (tester) async {
    final indexed = await pumpIndexed(tester, navStyle: 1);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final gridSize = tester.getSize(grid);

    await tester.drag(grid, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 16));

    expect(indexed.barOffset.value, greaterThan(0));
    expect(tester.getSize(grid), gridSize,
        reason: '底栏收起不得改变 body 约束（否则每帧重排整页）');

    await tester.pump(const Duration(milliseconds: 400));
  });
}
