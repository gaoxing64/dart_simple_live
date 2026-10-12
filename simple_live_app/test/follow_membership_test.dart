import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/migration_service.dart';

// Task 1 的迁移用例见本文件 `migrateTagMembership` 组。
// Task 2 的归属 API 用例追加在同一个 main() 里（共用下面的内存替身）。

/// 内存版 DB：只覆盖归属链路用到的方法，不碰 Hive。
class FakeDBService extends DBService {
  final follows = <String, FollowUser>{};
  final tags = <String, FollowUserTag>{};

  @override
  List<FollowUser> getFollowList() =>
      follows.values.where((f) => !f.deleted).toList();

  @override
  Future addFollow(FollowUser follow) async => follows[follow.id] = follow;

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

  @override
  Future<void> replaceAllFollowTags(Map<String, FollowUserTag> items) async {
    tags
      ..clear()
      ..addAll(items);
  }

  @override
  FollowUser? getFollow(String id) => follows[id];

  @override
  List<History> getHistories() => const [];
}

class FakeLiveFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 跳过本地存储；`liveListSort` 要读 `followSortMethod`。
class FakeSettings extends AppSettingsController {
  FakeSettings() {
    followSortMethod.value = SortMethod.watchDuration;
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 只测 getter，不触发 onInit 的订阅与本地存储。
class _Probe extends FollowUserController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late FakeDBService db;

  setUp(() {
    Get.testMode = true;
    Get.reset();
    db = FakeDBService();
    Get.put<DBService>(db);
    Get.put<AppSettingsController>(FakeSettings());
    Get.put<FollowService>(FakeLiveFollowService());
  });

  tearDown(() => Get.reset());

  group('migrateTagMembership', () {
    test('把 follow.tag 指向的分组成员补进 userId', () async {
      db.follows['a'] = FollowUser(
        id: 'a',
        roomId: 'a',
        siteId: 'huya',
        userName: 'a',
        face: '',
        addTime: DateTime(2024),
        tag: '我的喜爱',
      );
      db.tags['t0'] = FollowUserTag(id: 't0', tag: '我的喜爱', userId: []);

      await MigrationService.migrateTagMembership();

      expect(db.tags['t0']!.userId, ['a']);
    });

    test('follow.tag 指向不存在的分组时自动建组', () async {
      db.follows['b'] = FollowUser(
        id: 'b',
        roomId: 'b',
        siteId: 'huya',
        userName: 'b',
        face: '',
        addTime: DateTime(2024),
        tag: '孤儿组',
      );

      await MigrationService.migrateTagMembership();

      expect(db.tags.values.map((t) => t.tag), contains('孤儿组'));
      expect(
        db.tags.values.firstWhere((t) => t.tag == '孤儿组').userId,
        ['b'],
      );
    });

    test('tag=全部 的关注不进任何分组', () async {
      db.follows['c'] = FollowUser(
        id: 'c',
        roomId: 'c',
        siteId: 'huya',
        userName: 'c',
        face: '',
        addTime: DateTime(2024),
      );

      await MigrationService.migrateTagMembership();

      expect(db.tags, isEmpty);
    });

    test('已在 userId 里的不重复添加（幂等）', () async {
      db.follows['d'] = FollowUser(
        id: 'd',
        roomId: 'd',
        siteId: 'huya',
        userName: 'd',
        face: '',
        addTime: DateTime(2024),
        tag: 'X',
      );
      db.tags['t0'] = FollowUserTag(id: 't0', tag: 'X', userId: ['d']);

      await MigrationService.migrateTagMembership();

      expect(db.tags['t0']!.userId, ['d']);
    });
  });

  group('FollowService 归属 API', () {
    FollowUser user(String id, {String tag = '全部'}) => FollowUser(
          id: id,
          roomId: id,
          siteId: 'huya',
          userName: id,
          face: '',
          addTime: DateTime(2024),
          tag: tag,
        );

    void seedTags() {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: '我的喜爱', userId: []),
        FollowUserTag(id: 'a1', tag: '常看', userId: []),
      ]);
      db.tags
        ..clear()
        ..addEntries(FollowService.instance.followTagList
            .map((t) => MapEntry(t.id, t)));
      FollowService.instance.followList.assignAll([user('u1')]);
    }

    test('addUserToTag：可同时属于多个分组', () async {
      seedTags();
      final u = FollowService.instance.followList.first;
      await FollowService.instance.addUserToTag(u, '我的喜爱');
      await FollowService.instance.addUserToTag(u, '常看');

      expect(FollowService.instance.userTagNamesOf(u.id), ['我的喜爱', '常看']);
      expect(db.tags['a0']!.userId, ['u1']);
      expect(db.tags['a1']!.userId, ['u1']);
    });

    test('addUserToTag：重复加入不产生重复成员', () async {
      seedTags();
      final u = FollowService.instance.followList.first;
      await FollowService.instance.addUserToTag(u, '我的喜爱');
      await FollowService.instance.addUserToTag(u, '我的喜爱');

      expect(db.tags['a0']!.userId, ['u1']);
    });

    test('removeUserFromTag：只移出该组，别的组不动', () async {
      seedTags();
      final u = FollowService.instance.followList.first;
      await FollowService.instance.addUserToTag(u, '我的喜爱');
      await FollowService.instance.addUserToTag(u, '常看');

      await FollowService.instance.removeUserFromTag(u, '我的喜爱');

      expect(FollowService.instance.userTagNamesOf(u.id), ['常看']);
      expect(db.tags['a0']!.userId, isEmpty);
      expect(db.tags['a1']!.userId, ['u1']);
    });

    test('未知分组名：不抛异常、不改数据', () async {
      seedTags();
      final u = FollowService.instance.followList.first;
      await FollowService.instance.addUserToTag(u, '不存在');
      await FollowService.instance.removeUserFromTag(u, '不存在');

      expect(FollowService.instance.userTagNamesOf(u.id), isEmpty);
    });

    test('removeAllTagsFromUser：清空全部归属', () async {
      seedTags();
      final u = FollowService.instance.followList.first;
      await FollowService.instance.addUserToTag(u, '我的喜爱');
      await FollowService.instance.addUserToTag(u, '常看');

      await FollowService.instance.removeAllTagsFromUser(u);

      expect(FollowService.instance.userTagNamesOf(u.id), isEmpty);
      expect(db.tags['a0']!.userId, isEmpty);
      expect(db.tags['a1']!.userId, isEmpty);
    });
  });

  group('groupedView 按 userId 分桶', () {
    FollowUser user(String id, {String tag = '全部'}) => FollowUser(
          id: id,
          roomId: id,
          siteId: 'huya',
          userName: id,
          face: '',
          addTime: DateTime(2024),
          tag: tag,
        )..liveStatus.value = 1;

    late _Probe c;
    setUp(() {
      c = _Probe();
    });

    test('同一关注出现在它的每个所属分组里', () {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: '我的喜爱', userId: ['u1', 'u2']),
        FollowUserTag(id: 'a1', tag: '常看', userId: ['u1']),
      ]);
      FollowService.instance.followList.assignAll([user('u1'), user('u2')]);
      c.list.assignAll([user('u1'), user('u2')]);
      c.updateTagList();

      final v = c.groupedView;
      expect(v.groups.map((g) => g.tag.tag), ['我的喜爱', '常看']);
      expect(v.groups[0].members.map((u) => u.id), ['u1', 'u2']);
      expect(v.groups[1].members.map((u) => u.id), ['u1']);
      expect(v.ungrouped, isEmpty);
    });

    test('不属于任何分组的落未分组段', () {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: '我的喜爱', userId: ['u1']),
      ]);
      c.list.assignAll([user('u1'), user('u2')]);
      c.updateTagList();

      final v = c.groupedView;
      expect(v.groups[0].members.map((u) => u.id), ['u1']);
      expect(v.ungrouped.map((u) => u.id), ['u2']);
    });

    test('组内顺序继承 list 顺序，不是 userId 顺序', () {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'G', userId: ['u2', 'u1']),
      ]);
      c.list.assignAll([user('u1'), user('u2')]);
      c.updateTagList();

      expect(c.groupedView.groups[0].members.map((u) => u.id), ['u1', 'u2']);
    });

    test('userId 里的幽灵 id（已取关）被忽略', () {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'G', userId: ['u1', 'gone']),
      ]);
      c.list.assignAll([user('u1')]);
      c.updateTagList();

      expect(c.groupedView.groups[0].members.map((u) => u.id), ['u1']);
    });
  });
}
