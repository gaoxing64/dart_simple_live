// 关注页列表的纯逻辑测试：搜索过滤、liveStatus 二分段、hideOffline 语义。
//
// 这些 getter 不依赖 widget，构造 FollowUser 列表即可断言（#25）。
// 页面层 `_AnchorTabBar` 的锚点几何依赖 `liveSection`/`offlineSection` 的
// 切分口径，切错一段，点「未开播」就会滚到错误位置。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
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
}) {
  return FollowUser(
    id: 'douyu_$name',
    roomId: 'room-$name',
    siteId: 'douyu',
    userName: name,
    face: '',
    addTime: DateTime(2024),
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

    // 数据源由 FollowService 提供，filterData 内置标签分支会取它
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
}
