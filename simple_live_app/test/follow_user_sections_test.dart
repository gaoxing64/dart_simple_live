// 关注页列表的纯逻辑测试：搜索过滤、liveStatus 二分段、hideOffline 语义、
// 「全部」视图的分组模型（groupedView）。
//
// 这些 getter 不依赖 widget，构造 FollowUser 列表即可断言（#25）。
// 页面视图切换（全部/直播中/未开播）与分组卡片都按这里的切分口径渲染。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
import 'package:simple_live_app/services/follow_service.dart';

/// 只测分段/搜索逻辑：用 `visibleList` / `liveSection` / `offlineSection`
/// 这几个 getter，不触发 onInit 的订阅与本地存储。
class _SectionProbe extends FollowUserController {
  _SectionProbe() : super();

  @override
  // ignore: must_call_super
  void onInit() {}
}

/// 侧栏 / 筛选态的 probe：切页状态（[FollowUserController.activeTab]）不依赖
/// 任何 widget，跳过 onInit 也能直接测；不接事件总线、不读本地存储。
///
/// 收尾要 `onClose`（释放 PageController），所以单独包一层 teardown。
class _SidebarProbe extends FollowUserController {
  _SidebarProbe() : super();

  @override
  // ignore: must_call_super
  void onInit() {}
}

_SidebarProbe _sidebarProbe() {
  final c = _SidebarProbe();
  addTearDown(c.onClose);
  return c;
}

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用），
/// 直接指定关注页用到的两个开关。
class _FakeSettings extends AppSettingsController {
  _FakeSettings() {
    hideOfflineFollow.value = false;
    followSortMethod.value = SortMethod.watchDuration;
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// `FollowService.onInit` 会读 Hive 并起定时器，测试里不需要。
class _FakeFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

FollowUser _user(
  String name, {
  int liveStatus = 0,
  String remark = '',
  String title = '',
  String siteId = 'douyu',
}) {
  return FollowUser(
    id: '${siteId}_$name',
    roomId: 'room-$name',
    siteId: siteId,
    userName: name,
    face: '',
    addTime: DateTime(2024),
  )
    ..liveStatus.value = liveStatus
    ..title.value = title
    ..remark = remark;
}

void main() {
  // `selectSidebarItem` 会走 `pageController.animateToPage`（无 clients 时跳过），
  // 纯单元测试下状态断言不受动画影响；binding 仍然备好，widget 用例要用。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
    // FollowService 的构造不碰存储（存储都在 onInit 的 loadData 里），
    // 直接 put 一个空的，再由用例往 followList 塞数据
    Get.put<FollowService>(_FakeFollowService());
  });

  tearDown(() => Get.reset());

  test('liveStatus==2 归上段，其余（含读取中 0）归下段', () {
    final c = _SectionProbe();
    c.list.assignAll([
      _user('在线主播', liveStatus: 2),
      _user('下播主播', liveStatus: 4),
      _user('读取中', liveStatus: 0),
    ]);

    expect(c.liveSection.map((u) => u.userName), ['在线主播']);
    // 读取中的房间不能凭空消失：归到下段至少还看得见
    expect(
      c.offlineSection.map((u) => u.userName),
      ['下播主播', '读取中'],
    );
  });

  test('搜索命中 remark / userName / title，大小写不敏感', () {
    final c = _SectionProbe();
    c.list.assignAll([
      // userName 不含「三」，只能靠备注命中
      _user('老大', remark: '三哥'),
      _user('李四', title: '深夜电台'),
      _user('王五', title: 'ABC直播间'),
    ]);
    c.searchQuery.value = '三';

    expect(c.visibleList.map((u) => u.userName), ['老大']);

    c.searchQuery.value = '电台';
    expect(c.visibleList.map((u) => u.userName), ['李四']);

    // 大小写不敏感（标题里的英文）
    c.searchQuery.value = 'abc';
    expect(c.visibleList.map((u) => u.userName), ['王五']);

    // 空串 = 不过滤
    c.searchQuery.value = '';
    expect(c.visibleList.length, 3);
  });

  test('hideOfflineFollow=true 时 filterData 只留下播那段', () {
    AppSettingsController.instance.hideOfflineFollow.value = true;

    // 数据源由 FollowService 提供，filterData 一律取完整列表再按开关裁剪
    FollowService.instance.followList.assignAll([
      _user('在线主播', liveStatus: 2),
      _user('下播主播', liveStatus: 4),
      _user('读取中', liveStatus: 0),
    ]);

    final c = _SectionProbe();
    // filterData 会用数据源覆盖 list，再按 hideOffline 砍掉未开播那段
    c.filterData();

    expect(c.list.map((u) => u.userName), ['在线主播']);
    expect(c.offlineSection, isEmpty);
  });

  group('groupedView（「全部」分组视图）', () {
    void seedTags() {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['douyu_a', 'douyu_b']),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['douyu_c']),
      ]);
    }

    test('按成员表分桶；不在任何成员表里的落未分组', () {
      seedTags();
      final c = _SectionProbe();
      c.updateTagList();
      c.list.assignAll([
        _user('a', liveStatus: 2),
        _user('b'),
        _user('c'),
        _user('d'), // 不属于任何分组（「全部」哨兵语义）
        _user('e'), // 旧备份遗留的孤儿归属：等价于「不在任何成员表里」
      ]);

      final v = c.groupedView;
      expect(v.groups.map((g) => g.tag.tag), ['CS解说', 'LOL解说']);
      expect(v.groups[0].members.map((u) => u.userName), ['a', 'b']);
      // liveCount 只数 liveStatus==2；0（读取中）计入总数不计入直播数
      expect(v.groups[0].liveCount, 1);
      expect(v.groups[0].totalCount, 2);
      expect(v.groups[1].liveCount, 0);
      expect(v.ungrouped.map((u) => u.userName), ['d', 'e']);
    });

    test('空组不搜索时保留（拖拽落点），搜索时隐藏', () {
      seedTags();
      final c = _SectionProbe();
      c.updateTagList();
      c.list.assignAll([
        _user('a'),
        _user('d'),
      ]);

      expect(c.groupedView.groups.map((g) => g.tag.tag), ['CS解说', 'LOL解说']);

      c.searchQuery.value = 'a';
      // 「LOL解说」组没有命中成员，搜索时不产出；「CS解说」命中保留
      expect(c.groupedView.groups.map((g) => g.tag.tag), ['CS解说']);
      expect(c.groupedView.ungrouped, isEmpty);
    });

    test('组顺序 = tagList.skip(3) 顺序（fractional id 序）', () {
      seedTags();
      final c = _SectionProbe();
      c.updateTagList();
      expect(c.customTags.map((t) => t.id), ['a0', 'a1']);
      c.list.assignAll([
        _user('c'),
        _user('a'),
      ]);
      expect(c.groupedView.groups.map((g) => g.tag.tag), ['CS解说', 'LOL解说']);
    });
  });

  group('第二栏 sidebarItems', () {
    test('默认（按平台分类关闭）= 3 个内置项，计数 = 在播 + 未开播', () {
      final c = _sidebarProbe();
      c.list.assignAll([
        _user('直播A', liveStatus: 2),
        _user('直播B', liveStatus: 2),
        _user('未开播C'),
        _user('读取中D'),
      ]);

      final items = c.sidebarItems;
      expect(items.map((i) => i.kind), [
        FollowSidebarKind.all,
        FollowSidebarKind.live,
        FollowSidebarKind.offline,
      ]);
      expect(items.map((i) => i.label), ['全部', '直播中', '未开播']);
      // 读取中计入总数、不计入在播
      expect(items.map((i) => i.count), [4, 2, 2]);
    });

    test('开启后平台项插在中间（siteSort 序），0 计数平台隐藏', () {
      final settings = AppSettingsController.instance;
      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(Sites.orderedIds(settings.siteSort));
      final c = _sidebarProbe();
      c.list.assignAll([
        _user('虎牙A', siteId: 'huya', liveStatus: 2),
        _user('斗鱼B', siteId: 'douyu'),
        // 抖音 / B站 / Twitch 一个关注都没有 → 不占侧栏
      ]);

      final items = c.sidebarItems;
      expect(items.map((i) => i.kind), [
        FollowSidebarKind.all,
        FollowSidebarKind.live,
        FollowSidebarKind.offline,
        FollowSidebarKind.site,
        FollowSidebarKind.site,
      ]);
      // 平台序跟 siteSort（默认 = allSites 声明序：B站/斗鱼/虎牙/抖音/Twitch）
      expect(items.map((i) => i.label), [
        '全部',
        '直播中',
        '未开播',
        '斗鱼直播',
        '虎牙直播',
      ]);
      expect(items.map((i) => i.count), [2, 1, 1, 1, 1]);
      // 平台项带上 Site，widget 才能画 logo
      expect(items[3].site?.id, 'douyu');
    });

    test('关掉单个平台子开关，对应平台项消失', () {
      final settings = AppSettingsController.instance;
      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(['huya', 'douyu']);
      final c = _sidebarProbe();
      c.list.assignAll([
        _user('虎牙A', siteId: 'huya'),
        _user('斗鱼B', siteId: 'douyu'),
      ]);

      expect(
        c.sidebarItems.where((i) => i.kind == FollowSidebarKind.site).map((i) => i.label),
        ['斗鱼直播', '虎牙直播'],
      );

      settings.followSiteGroupSites.remove('douyu');
      expect(
        c.sidebarItems.where((i) => i.kind == FollowSidebarKind.site).map((i) => i.label),
        ['虎牙直播'],
      );
    });

    test('自定义分组排在平台之后；空分组保留（拖拽落点）', () {
      final settings = AppSettingsController.instance;
      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(['huya']);
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_a']),
        FollowUserTag(id: 'a1', tag: '空组', userId: <String>[]),
      ]);
      final c = _sidebarProbe();
      c.updateTagList();
      c.list.assignAll([_user('a', siteId: 'huya')]);

      expect(
        c.sidebarItems.map((i) => '${i.kind.name}:${i.label}'),
        [
          'all:全部',
          'live:直播中',
          'offline:未开播',
          'site:虎牙直播',
          'group:CS解说',
          'group:空组',
        ],
      );
    });
  });

  group('selectSidebarItem 互斥不变式', () {
    test('内置项：清筛选 + 切到对应页', () {
      final c = _sidebarProbe();
      c.list.assignAll([_user('a', liveStatus: 2)]);

      c.selectSidebarItem(c.sidebarItems[1]);
      expect(c.activeFilter.value, isNull);
      expect(c.activeTab.value, 1);
      expect(c.activeSidebarKey, 'live');

      // 已在目标页上也清筛选：点「全部」= 退出筛选
      c.activeFilter.value = const FollowFilter(
        kind: FollowSidebarKind.site,
        id: 'huya',
      );
      c.selectSidebarItem(c.sidebarItems[0]);
      expect(c.activeFilter.value, isNull);
      expect(c.activeTab.value, 0);
      expect(c.activeSidebarKey, 'all');
    });

    test('平台 / 分组项：设筛选 + 回「全部」页', () {
      final settings = AppSettingsController.instance;
      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(['huya']);
      final c = _sidebarProbe();
      c.list.assignAll([_user('a', siteId: 'huya', liveStatus: 2)]);

      // 先在「直播中」页，再点平台项：应回到第 0 页并带上筛选
      c.activeTab.value = 1;
      final siteItem = c.sidebarItems.firstWhere((i) => i.kind == FollowSidebarKind.site);
      c.selectSidebarItem(siteItem);
      expect(c.activeTab.value, 0);
      expect(c.activeFilter.value?.kind, FollowSidebarKind.site);
      expect(c.activeFilter.value?.id, 'huya');
      expect(c.activeSidebarKey, 'site:huya');
    });

    test('切页只走侧栏：activeTab 是唯一真源（无手势翻页旁路）', () {
      final c = _sidebarProbe();
      c.list.assignAll([_user('a')]);

      // 直接写 activeTab（相当于外部改状态）时，侧栏高亮立刻跟上
      c.activeTab.value = 2;
      expect(c.activeSidebarKey, 'offline');

      // 侧栏点「直播中」：状态切过去，筛选不受影响
      c.selectSidebarItem(c.sidebarItems[1]);
      expect(c.activeTab.value, 1);
      expect(c.activeSidebarKey, 'live');
    });

    test('筛选失效（分组被删）回落 null，不会渲染空白平铺', () {
      final c = _sidebarProbe();
      c.list.assignAll([_user('a')]);
      c.activeFilter.value = const FollowFilter(
        kind: FollowSidebarKind.group,
        id: 'ghost',
      );

      expect(c.activeGroup, isNull);
      expect(c.filteredMembers, isEmpty);
    });
  });

  group('filteredMembers（筛选态成员）', () {
    test('分组走 groupedView 桶（多归属，顺序继承 list）', () {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['douyu_a', 'douyu_b']),
      ]);
      final c = _sidebarProbe();
      c.updateTagList();
      c.list.assignAll([
        _user('a'),
        _user('b', liveStatus: 2),
      ]);
      c.activeFilter.value = const FollowFilter(
        kind: FollowSidebarKind.group,
        id: 'a0',
      );

      // 顺序继承 list（直播优先是 liveListSort 排好的，不在这里重复造）
      expect(c.filteredMembers.map((u) => u.userName), ['a', 'b']);
      expect(c.activeGroup?.tag, 'CS解说');
    });

    test('平台走 siteId 过滤：新关注自动进来，不依赖任何分组', () {
      final c = _sidebarProbe();
      c.list.assignAll([
        _user('虎牙A', siteId: 'huya', liveStatus: 2),
        _user('斗鱼B', siteId: 'douyu'),
        _user('虎牙C', siteId: 'huya'),
      ]);
      c.activeFilter.value = const FollowFilter(
        kind: FollowSidebarKind.site,
        id: 'huya',
      );

      // 只按 siteId 切，顺序继承 list；未建任何分组
      expect(c.filteredMembers.map((u) => u.userName), ['虎牙A', '虎牙C']);
      expect(c.activeGroup, isNull);
    });

    test('搜索词同时作用于平台筛选', () {
      final c = _sidebarProbe();
      c.list.assignAll([
        _user('虎牙A', siteId: 'huya', remark: '大主播'),
        _user('虎牙B', siteId: 'huya'),
      ]);
      c.activeFilter.value = const FollowFilter(
        kind: FollowSidebarKind.site,
        id: 'huya',
      );
      c.searchQuery.value = '大主播';

      expect(c.filteredMembers.map((u) => u.userName), ['虎牙A']);
    });
  });
}
