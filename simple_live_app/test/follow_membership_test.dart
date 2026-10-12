import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/resources/follow_sync_resource.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/migration_service.dart';

// Task 1 的迁移用例见本文件 `migrateTagMembership` 组。
// Task 2 的归属 API 用例追加在同一个 main() 里（共用下面的内存替身）。
// Task 6 的导入导出 / WebDAV 合并用例见 `JSON 导出导入`、`备份向后兼容`、`WebDAV 合并` 组。

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

/// 跳过 Hive：`FollowSyncResource.merge` 只读「上次恢复时间」，
/// 测试里没有本地存储，一律回落到默认值（2026-01-01）。
class FakeLocalStorage extends LocalStorageService {
  @override
  T getValue<T>(dynamic key, T defaultValue) => defaultValue;
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

  group('JSON 导出导入', () {
    FollowUser user(String id, {String tag = '全部'}) => FollowUser(
          id: id,
          roomId: id,
          siteId: 'huya',
          userName: id,
          face: '',
          addTime: DateTime(2024),
          tag: tag,
        );

    setUp(() {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: '我的喜爱', userId: ['u1', 'u2']),
        FollowUserTag(id: 'a1', tag: '常看', userId: ['u1']),
      ]);
      FollowService.instance.followList.assignAll([
        user('u1', tag: '我的喜爱'),
        user('u2', tag: '我的喜爱'),
      ]);
    });

    test('generateJson 带 tags 数组', () {
      final json = FollowService.instance.generateJson();
      expect(json, contains('"tags":["我的喜爱","常看"]'));
      expect(json, contains('"tags":["我的喜爱"]'));
    });

    test('inputJson 认 tags，也认旧版单个 tag', () async {
      final payload = jsonEncode([
        {
          "siteId": "huya", "id": "n1", "roomId": "n1", "userName": "n1",
          "face": "", "addTime": "2024-01-01 00:00:00.000",
          "tags": ["A", "B"],
        },
        {
          "siteId": "huya", "id": "n2", "roomId": "n2", "userName": "n2",
          "face": "", "addTime": "2024-01-01 00:00:00.000",
          "tag": "旧版单分组",
        },
      ]);

      await FollowService.instance.inputJson(payload);

      expect(FollowService.instance.userTagNamesOf('n1'), ['A', 'B']);
      expect(FollowService.instance.userTagNamesOf('n2'), ['旧版单分组']);
    });
  });

  group('备份向后兼容', () {
    FollowUser user(String id, {String tag = '全部'}) => FollowUser(
          id: id,
          roomId: id,
          siteId: 'huya',
          userName: id,
          face: '',
          addTime: DateTime(2024),
          tag: tag,
        );

    setUp(() {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: '我的喜爱', userId: ['u1', 'u2']),
        FollowUserTag(id: 'a1', tag: '常看', userId: ['u1']),
      ]);
      FollowService.instance.followList.assignAll([
        user('u1', tag: '我的喜爱'),
        user('u2', tag: '我的喜爱'),
      ]);
    });

    test('旧备份→新版本：只带 tag 字段的旧备份还原出正确归属', () async {
      final payload = jsonEncode([
        {
          "siteId": "huya", "id": "o1", "roomId": "o1", "userName": "o1",
          "face": "", "addTime": "2024-01-01 00:00:00.000",
          "tag": "旧版A",
        },
        {
          "siteId": "huya", "id": "o2", "roomId": "o2", "userName": "o2",
          "face": "", "addTime": "2024-01-01 00:00:00.000",
          "tag": "旧版B",
        },
        {
          "siteId": "huya", "id": "o3", "roomId": "o3", "userName": "o3",
          "face": "", "addTime": "2024-01-01 00:00:00.000",
          "tag": "全部",
        },
      ]);

      await FollowService.instance.inputJson(payload);

      expect(FollowService.instance.userTagNamesOf('o1'), ['旧版A']);
      expect(FollowService.instance.userTagNamesOf('o2'), ['旧版B']);
      expect(FollowService.instance.userTagNamesOf('o3'), isEmpty);
    });

    test('新备份→旧版本：旧版只认 tag 字段也能安全读取新备份', () {
      final json = FollowService.instance.generateJson();

      // 新格式必须同时带 tags（归属真源），旧字段 tag 保留给旧版本
      expect(json, contains('"tags":'));

      // 旧版解析器只读自己认识的字段，多余的 tags 直接忽略，不能崩
      final legacyItems =
          (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      for (final item in legacyItems) {
        expect(item['tag'], isA<String>());
        final legacy = FollowUser.fromJson(item);
        expect(legacy.tag, isNotEmpty);
      }
      // 旧版按 tag 单字段重建分组时，主分组（首个所属分组）保持不变
      expect(legacyItems.firstWhere((e) => e['id'] == 'u1')['tag'], '我的喜爱');
      expect(legacyItems.firstWhere((e) => e['id'] == 'u2')['tag'], '我的喜爱');
    });

    test('导出→导入往返：多分组归属不丢', () async {
      final payload = FollowService.instance.generateJson();

      // 清空后重新导入，模拟「卸载重装后从备份恢复」
      FollowService.instance.followList.clear();
      FollowService.instance.followTagList.clear();
      db.follows.clear();
      db.tags.clear();

      await FollowService.instance.inputJson(payload);

      expect(FollowService.instance.userTagNamesOf('u1'), ['我的喜爱', '常看']);
      expect(FollowService.instance.userTagNamesOf('u2'), ['我的喜爱']);
    });
  });

  group('WebDAV 合并', () {
    FollowUser user(
      String id, {
      String tag = '全部',
      bool deleted = false,
      int updateTime = 0,
    }) =>
        FollowUser(
          id: id,
          roomId: id,
          siteId: 'huya',
          userName: id,
          face: '',
          addTime: DateTime(2026, 2, 1),
          tag: tag,
          deleted: deleted,
          updateTime: updateTime,
        );

    setUp(() {
      Get.put<LocalStorageService>(FakeLocalStorage());
    });

    test('merge 按分组名并集合并成员表，保住多归属', () {
      final local = FollowBundle(
        follows: [
          user('u1', tag: '我的喜爱'),
          user('u2', tag: '我的喜爱'),
        ],
        tags: [
          FollowUserTag(id: 'l0', tag: '我的喜爱', userId: ['u1', 'u2']),
          FollowUserTag(id: 'l1', tag: '常看', userId: ['u1']),
        ],
      );
      final remote = FollowBundle(
        follows: [
          user('u1', tag: '我的喜爱'),
          user('u3', tag: '常看'),
        ],
        tags: [
          FollowUserTag(id: 'r0', tag: '常看', userId: ['u1', 'u3']),
        ],
      );

      final merged = FollowSyncResource().merge(local, remote);

      final members = {for (final t in merged.tags) t.tag: t.userId.toSet()};
      expect(members['我的喜爱'], {'u1', 'u2'});
      expect(members['常看'], {'u1', 'u3'});
    });

    test('merge 剔除成员表里的幽灵 id 与墓碑', () {
      final local = FollowBundle(
        follows: [
          user('u1', tag: 'G'),
          // 墓碑：已取关，同步后仍在 resFollows 里，但不能算分组成员
          user(
            'u9',
            tag: 'G',
            deleted: true,
            updateTime: DateTime(2026, 3, 1).millisecondsSinceEpoch ~/ 1000,
          ),
        ],
        tags: [
          FollowUserTag(id: 'l0', tag: 'G', userId: ['u1', 'u9', 'gone']),
        ],
      );
      final remote = FollowBundle(
        follows: [user('u3', tag: '远组')],
        tags: [
          FollowUserTag(id: 'r0', tag: '远组', userId: ['u3', 'gone']),
        ],
      );

      final merged = FollowSyncResource().merge(local, remote);

      final members = {for (final t in merged.tags) t.tag: t.userId.toSet()};
      expect(members['G'], {'u1'});
      expect(members['远组'], {'u3'});
    });
  });
}
