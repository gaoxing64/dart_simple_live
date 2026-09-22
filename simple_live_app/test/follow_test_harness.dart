// 关注页 widget 测试的共享 harness：假设置 / 假首页 / 假关注服务 + 页面泵取。
//
// 从 `collapsible_top_bar_follow_test.dart` 提取，供收起顶栏回归与
// 分组视图测试共用。
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
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

/// 关注服务假实现。
///
/// * 默认预置 30 个未开播（status 0）关注，让列表足够长、可以滚动；
///   分组用例传自定义 `users`/`tags`。
/// * `setFollowTag` / `reorderFollowTag` 走内存 —— 真实现经 DBService 写
///   Hive，widget test 里没注册 DBService。
class FakeFollowService extends FollowService {
  FakeFollowService({List<FollowUser>? users, List<FollowUserTag>? tags}) {
    followList.addAll(users ?? _defaultUsers());
    if (tags != null) followTagList.assignAll(tags);
  }

  static List<FollowUser> _defaultUsers() {
    final now = DateTime.now();
    return List.generate(
      30,
      (i) => FollowUser(
        id: 'huya_r$i',
        roomId: 'r$i',
        siteId: 'huya',
        userName: 'anchor $i',
        face: '',
        addTime: now,
      ),
    );
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> loadData({bool updateStatus = true, int? cycle}) async {}

  @override
  Future<void> setFollowTag(FollowUser item, FollowUserTag targetTag) async {
    for (final t in followTagList) {
      t.userId.remove(item.id);
    }
    if (targetTag.tag != '全部') {
      final tar = followTagList.where((t) => t.tag == targetTag.tag).firstOrNull;
      if (tar != null && !tar.userId.contains(item.id)) {
        tar.userId.add(item.id);
      }
    }
    item.tag = targetTag.tag;
  }

  @override
  Future<void> addFollowUserTag(String tag) async {
    if (followTagList.any((item) => item.tag == tag)) {
      return;
    }
    // id 只需唯一且排在既有标签之后；不写 Hive
    followTagList.add(
      FollowUserTag(id: 'zz${followTagList.length}-$tag', tag: tag, userId: []),
    );
  }

  @override
  void reorderFollowTag(int oldIndex, int newIndex) {
    final item = followTagList.removeAt(oldIndex);
    followTagList.insert(newIndex.clamp(0, followTagList.length), item);
  }
}

/// 假本地存储：内存实现 —— 真实现写 Hive box，widget test 里没开任何 box。
/// 关注页的折叠态等设置会经 `AppSettingsController` 的 setter 走到这里，
/// 不注册会直接 GetFindCanceled。
class FakeLocalStorageService extends LocalStorageService {
  final _mem = <dynamic, dynamic>{};

  @override
  Future init() async {}

  @override
  T getValue<T>(dynamic key, T defaultValue) =>
      _mem.containsKey(key) ? _mem[key] as T : defaultValue;

  @override
  T? getNullValue<T>(dynamic key, T? defaultValue) =>
      _mem.containsKey(key) ? _mem[key] as T? : defaultValue;

  @override
  Future setValue<T>(dynamic key, T value) async {
    _mem[key] = value;
  }

  @override
  Future removeValue<T>(dynamic key) async {
    _mem.remove(key);
  }

  @override
  Future flush() async {}
}

Future<IndexedController> pumpIndexed(
  WidgetTester tester, {
  int hideType = 1,
  int navStyle = 0,
  FakeFollowService? followService,
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
  Get.put<LocalStorageService>(FakeLocalStorageService());
  Get.put<AppSettingsController>(
    FakeSettings(hideType: hideType, navStyle: navStyle),
  );
  Get.put<FollowService>(followService ?? FakeFollowService());
  for (final site in Sites.supportSites) {
    Get.put<HomeListController>(FakeHomeListController(site), tag: site.id);
  }
  Get.put(IndexedController());

  // SmartDialog 的 toast（重组完成提示等）需要 attach：与 main.dart 同款
  // 挂 observer + builder，否则 showToast 抛 LateInitializationError。
  // scrollBehavior 也与 main.dart 对齐（AppScrollBehavior 放开鼠标拖拽），
  // 否则「鼠标拖拽切页」类用例在测试里测不到真实行为。
  await tester.pumpWidget(GetMaterialApp(
    scrollBehavior: const AppScrollBehavior(),
    navigatorObservers: [FlutterSmartDialog.observer],
    builder: FlutterSmartDialog.init(),
    home: const IndexedPage(),
  ));
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

/// 让当前所有动画/微任务推进一段时间（不 pumpAndSettle —— easy_refresh 有循环动画）。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 用例收尾：跑完 easy_refresh 的 processed 完成计时器（400ms），
/// 否则 teardown 会报 pending timer。
Future<void> settleEnd(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 500));
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
