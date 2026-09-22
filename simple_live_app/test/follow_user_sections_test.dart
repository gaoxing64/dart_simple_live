// 关注页列表的纯逻辑测试：搜索过滤、liveStatus 二分段、hideOffline 语义、
// 「全部」视图的分组模型（groupedView）。
//
// 这些 getter 不依赖 widget，构造 FollowUser 列表即可断言（#25）。
// 页面视图切换（全部/直播中/未开播）与分组卡片都按这里的切分口径渲染。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/services/follow_service.dart';

/// 只测分段/搜索逻辑：用 `visibleList` / `liveSection` / `offlineSection`
/// 这几个 getter，不触发 onInit 的订阅与本地存储。
class _SectionProbe extends FollowUserController {
  _SectionProbe() : super();

  @override
  // ignore: must_call_super
  void onInit() {}
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
  void onInit() {}
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
  String tag = '全部',
}) {
  return FollowUser(
    id: 'douyu_$name',
    roomId: 'room-$name',
    siteId: 'douyu',
    userName: name,
    face: '',
    addTime: DateTime(2024),
    tag: tag,
  )..liveStatus.value = liveStatus
      ..title.value = title
      ..remark = remark;
}

void main() {
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
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: []),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: []),
      ]);
    }

    test('按标签名分桶；「全部」与孤儿名字落未分组', () {
      seedTags();
      final c = _SectionProbe();
      c.updateTagList();
      c.list.assignAll([
        _user('a', tag: 'CS解说', liveStatus: 2),
        _user('b', tag: 'CS解说'),
        _user('c', tag: 'LOL解说'),
        _user('d'), // 「全部」
        _user('e', tag: '已删标签'), // 标签被删/旧备份遗留的孤儿名
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
        _user('a', tag: 'CS解说'),
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
        _user('c', tag: 'LOL解说'),
        _user('a', tag: 'CS解说'),
      ]);
      expect(c.groupedView.groups.map((g) => g.tag.tag), ['CS解说', 'LOL解说']);
    });
  });
}
