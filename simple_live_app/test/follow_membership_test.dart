import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
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
}
