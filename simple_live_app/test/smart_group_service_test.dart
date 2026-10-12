// 一键按平台分组的纯逻辑测试。
//
// 只验「谁进了哪个组」，不碰 UI：SmartGroupService 经 FakeDBService 走内存，
// Sites.allSites 是静态表。`execute()` 收尾的 `liveListSort()` 要读
// `followSortMethod`，所以按仓库惯例（见 follow_membership_test.dart）注册
// 不读本地存储的 FakeSettings；它的 `siteSort` 保持空，`_orderedSiteIds`
// 仍回退到 `Sites.allSites` 的声明顺序。
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/smart_group_service.dart';

class _FakeDBService extends DBService {
  final tags = <String, FollowUserTag>{};
  final follows = <String, FollowUser>{};

  @override
  List<FollowUserTag> getFollowTagList() => tags.values.toList();

  @override
  Future updateFollowTag(FollowUserTag followTag) async =>
      tags[followTag.id] = followTag;

  @override
  Future deleteFollowTag(String id) async => tags.remove(id);

  @override
  bool getFollowTagExist(String id) => tags.containsKey(id);

  @override
  bool getFollowTagExistByTag(String tag) =>
      tags.values.any((item) => item.tag == tag);

  @override
  FollowUserTag? getFollowTag(String tag) =>
      tags.values.firstWhereOrNull((item) => item.tag == tag);

  @override
  Future<FollowUserTag> addFollowTag(String tag) async {
    if (getFollowTagExistByTag(tag)) {
      return getFollowTag(tag)!;
    }
    final item = FollowUserTag(id: 'g${tags.length}', tag: tag, userId: []);
    tags[item.id] = item;
    return item;
  }

  // `addUserToTag` 会顺带写主分组缓存（FollowUser.tag），真实现在这里落
  // followBox；测试里没开 Hive，必须换内存实现。
  @override
  Future addFollow(FollowUser follow) async => follows[follow.id] = follow;
}

class _LiveFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 跳过本地存储的假设置：`liveListSort` 要读 `followSortMethod`。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

FollowUser u(String id, String siteId) => FollowUser(
      id: id,
      roomId: id,
      siteId: siteId,
      userName: id,
      face: '',
      addTime: DateTime(2024),
    );

void main() {
  late _FakeDBService db;

  setUp(() {
    Get.testMode = true;
    Get.reset();
    db = _FakeDBService();
    Get.put<DBService>(db);
    Get.put<AppSettingsController>(_FakeSettings());
    Get.put<FollowService>(_LiveFollowService());
    Get.put(SmartGroupService());
  });

  tearDown(() => Get.reset());

  test('preview：按平台汇总全部关注人数', () {
    FollowService.instance.followList.assignAll([
      u('a', 'huya'),
      u('b', 'huya'),
      u('c', 'douyu'),
    ]);

    final p = SmartGroupService.instance.preview();

    expect(p.totalFollows, 3);
    // 顺序 = Sites.allSites 的声明顺序（bilibili→douyu→huya→douyin→twitch），
    // 所以斗鱼在虎牙前面 —— 别按「人数多的排前面」想当然。
    expect(p.items.map((e) => e.siteName), ['斗鱼直播', '虎牙直播']);
    expect(p.items.last.userCount, 2);
    expect(p.items.first.userCount, 1);
  });

  test('preview：标记哪些平台分组已经存在', () {
    FollowService.instance.followList.assignAll([u('a', 'huya')]);
    FollowService.instance.followTagList.assignAll([
      FollowUserTag(id: 'a0', tag: '虎牙直播', userId: []),
    ]);

    final p = SmartGroupService.instance.preview();

    expect(p.items.single.tagAlreadyExists, isTrue);
    expect(p.newTagCount, 0);
  });

  test('execute：创建平台分组并填入该平台全部关注', () async {
    FollowService.instance.followList.assignAll([
      u('a', 'huya'),
      u('b', 'douyu'),
    ]);

    final r = await SmartGroupService.instance.execute();

    expect(r.tagsCreated, 2);
    expect(r.membersAdded, 2);
    expect(FollowService.instance.userTagNamesOf('a'), ['虎牙直播']);
    expect(FollowService.instance.userTagNamesOf('b'), ['斗鱼直播']);
    expect(db.tags.length, 2, reason: '要真的落库');
  });

  test('execute：多归属 —— 手动分组的人同时进平台分组', () async {
    FollowService.instance.followList.assignAll([u('a', 'huya')]);
    FollowService.instance.followTagList.assignAll([
      FollowUserTag(id: 'a0', tag: '我的喜爱', userId: ['a']),
    ]);
    db.tags['a0'] = FollowService.instance.followTagList.first;

    await SmartGroupService.instance.execute();

    expect(FollowService.instance.userTagNamesOf('a'), contains('我的喜爱'));
    expect(FollowService.instance.userTagNamesOf('a'), contains('虎牙直播'));
  });

  test('execute：幂等 —— 第二次跑 0 新增', () async {
    FollowService.instance.followList.assignAll([u('a', 'huya')]);

    await SmartGroupService.instance.execute();
    final second = await SmartGroupService.instance.execute();

    expect(second.tagsCreated, 0);
    expect(second.membersAdded, 0);
    expect(FollowService.instance.followTagList.length, 1);
    expect(FollowService.instance.userTagNamesOf('a'), ['虎牙直播']);
  });

  test('execute：未知平台跳过，不建空组', () async {
    FollowService.instance.followList.assignAll([u('a', 'nowhere')]);

    final r = await SmartGroupService.instance.execute();

    expect(r.tagsCreated, 0);
    expect(FollowService.instance.followTagList, isEmpty);
  });

  test('execute：没有关注时不建任何组', () async {
    final r = await SmartGroupService.instance.execute();
    expect(r.tagsCreated, 0);
    expect(r.membersAdded, 0);
  });

  test('preview/result：Task 9 要用的派生统计字段', () async {
    FollowService.instance.followList.assignAll([
      u('a', 'huya'), // 已在虎牙组里
      u('b', 'huya'), // 待加入
      u('c', 'nowhere'), // 未知平台，跳过
    ]);
    FollowService.instance.followTagList.assignAll([
      FollowUserTag(id: 'a0', tag: '虎牙直播', userId: ['a']),
    ]);

    final p = SmartGroupService.instance.preview();

    expect(p.skippedUnknownSite, 1);
    expect(p.items.single.pendingCount, 1); // 只有 b 是本次新增
    expect(p.pendingTotal, 1);

    final r = await SmartGroupService.instance.execute();
    expect(r.didNothing, isFalse);

    final again = await SmartGroupService.instance.execute();
    expect(again.didNothing, isTrue);
  });

  test('preview/execute：siteSort 不全时，缺掉的已知平台照常归组、不算「未知平台」', () async {
    // siteSort 是首页排序的持久化结果，只在 initSiteSort() 里补全过一次；
    // 换设备恢复 / 版本加站点后它可能不全。缺掉的已知平台既不能漏归组，
    // 也不能被算进 skippedUnknownSite —— 那个数字是给「站点已被移除」看的。
    Get.delete<AppSettingsController>();
    Get.put<AppSettingsController>(_FakeSettings()..siteSort.assignAll(['huya']));

    FollowService.instance.followList.assignAll([
      u('a', 'bilibili'),
      u('b', 'huya'),
      u('c', 'twitch'),
      u('d', 'nowhere'), // 真·未知平台，只有它该被跳过
    ]);

    final p = SmartGroupService.instance.preview();

    expect(p.skippedUnknownSite, 1);
    // siteSort 里有的排最前，剩下的按 Sites.allSites 声明顺序补在后面
    expect(p.items.map((e) => e.siteId), ['huya', 'bilibili', 'twitch']);
    expect(p.totalMembers, 3);

    final r = await SmartGroupService.instance.execute();

    expect(r.tagsCreated, 3);
    expect(r.membersAdded, 3);
    expect(FollowService.instance.followTagList.map((t) => t.tag),
        ['虎牙直播', '哔哩哔哩', 'Twitch']);
  });
}
