# 多分组归属 + 一键按平台智能分组 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 先让一个关注可以同时属于多个分组（多分组归属），再在其上加「一键按平台分组」：把所有关注按直播平台自动归入同名平台分组。

**Architecture:** 把 `FollowUserTag.userId` 提升为归属关系的**唯一真源**，删除 `FollowUser.tag` 这个冷字段（它与 `userId` 双向冷写，正是历史上一连串数据错乱的根源，见 `followUserAllDataCheck` 的注释）。分组视图、排序、拖拽、导入导出、WebDAV 合并全部改为读 `userId`。智能分组是独立的 `SmartGroupService`：按 `FollowUser.siteId` 找到平台名，复用或新建同名分组，把该平台的关注**加入**（不是移到）该分组 —— 因为多归属已经让「加入」不再破坏任何东西。

**Tech Stack:** Flutter（fvm 3.47.6）、Dart、`hive_ce` + `hive_ce_generator`、`get`(GetX)、`fractional_indexing_dart`、`flutter_smart_dialog`、`remixicon` 4.9.3、`material_ui`。

**关键前置认知（实现者必读）：**

- 「分组」在 UI 上一律叫**分组**，代码标识符沿用历史命名 `tag` / `FollowUserTag`。不要重命名，改动面会失控。
- `FollowUserTag.id` 由 `FractionalIndexing` 生成，**显示顺序 = id 字典序**，不是列表顺序。
- `FollowUserController.tagList` 前三项（`全部` / `直播中` / `未开播`）是**视图切换 tab**，不入库；`customTags = tagList.skip(3)` 才是真分组。
- 字符串 `'全部'` 是「不属于任何分组」的哨兵，多处按名字判它。保留这个语义。
- 刷新关注页的唯一链路：`EventBus.emit(Constant.kUpdateFollow)` → `FollowService.loadData` → `updatedListStream` → `FollowUserController.updateTagList() + filterData()`。
- TV 端（`simple_live_tv_app`）有**自己独立的** `FollowUser` 模型，没有 `tag` 字段，本次不受影响。`simple_live_console` 不碰关注数据。
- 测试跑法：`cd simple_live_app && flutter test test/<name>_test.dart`（仓库用 fvm，必要时 `fvm flutter test`）。

---

## 文件结构（先定边界，再拆任务）

| 文件 | 职责 | 本计划中的动作 |
|---|---|---|
| `lib/models/db/follow_user.dart` | 关注实体 | 阶段一末尾删除 `tag` 字段 |
| `lib/models/db/follow_user_tag.dart` | 分组（含成员 id 列表） | 新增 `contains()` / `withMember()` 小工具 |
| `lib/services/follow_service.dart` | 关注 + 分组的唯一写入口 | 新增归属 API；把读 `follow.tag` 的地方改成读 `userId` |
| `lib/services/migration_service.dart` | 版本门控的数据迁移 | 新增 `curDBVer <= 10816` 一段：`tag` → `userId` |
| `lib/services/smart_group_service.dart` | **新建**：按平台批量归组（纯逻辑，不碰 UI） | 新建 |
| `lib/services/db_service.dart` | Hive 盒子封装 | 新增 `replaceAllFollowTags` / `getFollow`，让整表重建与按 id 取关注能被测试替身覆盖 |
| `lib/modules/follow_user/follow_user_controller.dart` | 关注页状态 + 分组视图模型 | `groupedView` 改读 `userId`；新增智能分组入口 |
| `lib/modules/follow_user/follow_user_page.dart` | 关注页 UI | 顶栏 ⋮ 加菜单项；拖拽落点谓词 |
| `lib/modules/follow_user/widgets/follow_group_card.dart` | 分组卡片 | 拖入 = 加入；已在组内不高亮 |
| `lib/modules/follow_user/widgets/follow_quick_group_sheet.dart` | 勾选后的批量编辑 sheet | 「移入」→「加入」；加「移出所有分组」 |
| `lib/modules/follow_user/widgets/smart_group_preview_sheet.dart` | **新建**：智能分组预览 + 确认 | 新建 |
| `lib/modules/follow_user/follow_tag_manager.dart` | 分组管理 sheet | 删组不再回写 `follow.tag` |
| `lib/modules/follow_user/follow_info_setting/*` | 单个关注详情页 | 单选 → 多选 |
| `lib/modules/follow_user/follow_app_setting/*` | 关注设置页 | 清理逻辑去 `tag`；加智能分组入口 |
| `lib/widgets/follow_user_item.dart` | 直播间侧的关注行 | 副标题的 `item.tag` → 派生分组名 |
| `lib/modules/sync/remote_sync/webdav/resources/follow_sync_resource.dart` | WebDAV 合并 | 不再从 `follow.tag` 重建 tagMap |
| `test/follow_membership_test.dart` | **新建**：归属真源翻转的纯逻辑测试 | 新建 |
| `test/smart_group_service_test.dart` | **新建**：智能分组纯逻辑测试 | 新建 |
| `test/follow_test_harness.dart` | widget 测试共享假实现 | 补 `addUserToTag` / `removeUserFromTag` |

**任务顺序的原则：每一步结束后 `flutter analyze` 都必须干净、`flutter test` 都必须全绿。** 因此先加新 API、再翻转读路径、最后删旧字段（删字段会一次性牵动所有残留引用，单独放一个收尾任务）。

---

# 阶段一：多分组归属

## Task 1: 归属迁移 —— 把 `FollowUser.tag` 灌进 `FollowUserTag.userId`

`tag.userId` 现在已经是「准真源」，但历史数据里两边可能不一致（这正是 `followUserAllDataCheck` 存在的理由）。本任务只**补全** `userId`，不删任何东西，所以随时可回退。

**Files:**
- Modify: `simple_live_app/lib/services/migration_service.dart`
- Test: `simple_live_app/test/follow_membership_test.dart`（新建，本任务先写迁移用例）

- [ ] **Step 1: 写失败的测试**

新建 `simple_live_app/test/follow_membership_test.dart`：

```dart
// 关注分组「归属真源」翻转的纯逻辑测试。
//
// 分三组：迁移补全 userId、FollowService 归属 API、groupedView 分组模型。
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

/// 内存版 DB：只覆盖归属链路用到的方法，不碰 Hive。
class _FakeDBService extends DBService {
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

class _LiveFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 跳过本地存储；`liveListSort` 要读 `followSortMethod`。
class _FakeSettings extends AppSettingsController {
  _FakeSettings() {
    followSortMethod.value = SortMethod.watchDuration;
  }

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

void main() {
  late _FakeDBService db;

  setUp(() {
    Get.testMode = true;
    Get.reset();
    db = _FakeDBService();
    Get.put<DBService>(db);
    Get.put<AppSettingsController>(_FakeSettings());
    Get.put<FollowService>(_LiveFollowService());
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: 编译失败 —— `MigrationService.migrateTagMembership` 未定义（`Method not found` / `isn't defined`）。

- [ ] **Step 3: 给 `DBService` 加两个可被测试替身覆盖的方法**

`DBService` 的 `tagBox` / `followBox` 都是 `late Box` 字段，测试替身覆盖不了「裸 `tagBox.clear()` + `putAll`」或 `followBox.get()`。后面 Task 4（数据校准 / 改名 / 删组）和 Task 6（WebDAV 恢复）都要整表重建分组、按 id 取关注，统一改走方法。本任务的测试替身已经预置了这两个 override，所以必须先加：

在 `simple_live_app/lib/services/db_service.dart` 的 `deleteFollowTag` 之后加：

```dart
  /// 用 [items] 整体替换分组表（数据校准 / WebDAV 恢复用）。
  ///
  /// 走方法而不是裸 `tagBox.clear()+putAll`，是为了让测试能用内存替身覆盖它。
  Future<void> replaceAllFollowTags(Map<String, FollowUserTag> items) async {
    await tagBox.clear();
    await tagBox.putAll(items);
  }
```

在同文件 `getFollowExist` 之后加：

```dart
  /// 按 id 取关注（含墓碑）。同样是为了让测试能覆盖，别在业务里裸用 `followBox.get`。
  FollowUser? getFollow(String id) => followBox.get(id);
```

- [ ] **Step 4: 实现迁移方法**

在 `simple_live_app/lib/services/migration_service.dart` 的 `MigrationService` 类内新增（放在 `migrateDataByVersion` 之后）：

```dart
  /// 归属真源迁移：把 `FollowUser.tag` 单向灌进 `FollowUserTag.userId`。
  ///
  /// 多分组归属之后 `userId` 是唯一真源，`FollowUser.tag` 降级为「主分组」展示缓存，
  /// 最终在后续版本删除。这里只做**补全**：
  /// - `tag == '全部'`（哨兵）的关注不进任何分组；
  /// - `tag` 指向的分组不存在时新建（孤儿名字，原来靠 `followUserAllDataCheck` 修）；
  /// - 已在 `userId` 里的跳过，重复执行无副作用。
  static Future<void> migrateTagMembership() async {
    final followList = DBService.instance.getFollowList();
    final tagList = DBService.instance.getFollowTagList();
    final byName = {for (final t in tagList) t.tag: t};

    for (final follow in followList) {
      if (follow.tag == '全部' || follow.tag.isEmpty) {
        continue;
      }
      var tag = byName[follow.tag];
      if (tag == null) {
        tag = await DBService.instance.addFollowTag(follow.tag);
        byName[follow.tag] = tag;
      }
      if (!tag.userId.contains(follow.id)) {
        tag.userId.add(follow.id);
        await DBService.instance.updateFollowTag(tag);
      }
    }
    Log.i("Migration: tag -> userId membership backfilled "
        "(${followList.length} follows, ${byName.length} tags)");
  }
```

同文件顶部已有 `import 'package:simple_live_app/app/log.dart';`，无需新增 import。

- [ ] **Step 4: 把它挂进版本门控迁移链**

`simple_live_app/lib/services/migration_service.dart` 的 `migrateDataByVersion()` 中，在 `if (curDBVer <= 10815) { ... }` 块之后、`LocalStorageService.instance.settingsBox.put(...)` 之前插入：

```dart
    // follow.tag -> followUserTag.userId 归属真源迁移（v1.8.16）
    if (curDBVer <= 10816) {
      await migrateTagMembership();
      // FollowService 已在 main.dart 里先于本方法 put，内存态的 followTagList
      // 是迁移前从 tagBox 读的旧副本，必须重载，否则关注页看不到补上的成员。
      FollowService.instance.getAllTagList();
    }
```

> 为什么用 `curDBVer <= 10816`：`simple_live_app/pubspec.yaml` 当前是 `1.8.15+10815`，`migrateDataByVersion` 末尾会把 `kHiveDbVer` 写成 `Utils.parseVersion(packageInfo.version)`。本功能发版号为 1.8.16 → 10816，门控自然生效。若实际发版号不同，改这里的常量并在提交信息里写明。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: 4 个 `migrateTagMembership` 用例全绿。

- [ ] **Step 6: 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿（本任务纯增量，未改任何既有行为）。

```bash
git add simple_live_app/lib/services/migration_service.dart simple_live_app/test/follow_membership_test.dart
git commit -m "feat(follow): 归属迁移 —— 把 FollowUser.tag 灌进 FollowUserTag.userId"
```

---

## Task 2: `FollowService` 归属 API（加入 / 移出 / 查询）

**Files:**
- Modify: `simple_live_app/lib/models/db/follow_user_tag.dart`
- Modify: `simple_live_app/lib/services/follow_service.dart`
- Test: `simple_live_app/test/follow_membership_test.dart`

- [ ] **Step 1: 写失败的测试**

追加到 `follow_membership_test.dart` 的 `main()` 内（`group('migrateTagMembership', ...)` 之后）：

```dart
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: 编译失败 —— `addUserToTag` / `userTagNamesOf` / `removeUserFromTag` / `removeAllTagsFromUser` 未定义。

- [ ] **Step 3: 给 `FollowUserTag` 加两个小工具**

在 `simple_live_app/lib/models/db/follow_user_tag.dart` 的类末尾（`copyWith` 之后）加：

```dart
  /// 该分组是否含此关注。
  bool contains(String followId) => userId.contains(followId);

  /// 不含则追加，返回是否真的加了（调用方据此决定要不要落库）。
  bool addMember(String followId) {
    if (userId.contains(followId)) {
      return false;
    }
    userId.add(followId);
    return true;
  }
```

- [ ] **Step 4: 实现 `FollowService` 归属 API**

在 `simple_live_app/lib/services/follow_service.dart` 的 `FollowService` 类中，紧跟 `getTagOptionsWithAll()` 之后插入：

```dart
  /// 某关注所属的分组名（按 `followTagList` 顺序）。
  ///
  /// 归属唯一真源是 `FollowUserTag.userId`；`FollowUser.tag` 只是「主分组」缓存，
  /// 二者由 `addUserToTag` / `removeUserFromTag` 一起维护。
  List<String> userTagNamesOf(String followId) => [
        for (final t in followTagList)
          if (t.contains(followId)) t.tag,
      ];

  /// 某关注所属的全部分组对象（按显示顺序）。
  List<FollowUserTag> userTagsOf(String followId) => [
        for (final t in followTagList)
          if (t.contains(followId)) t,
      ];

  /// 把关注加入分组（多归属：不影响它已在的其他分组）。
  ///
  /// [tagName] 传哨兵 `'全部'` 等价于「移出所有分组」，由调用方保证语义；
  /// 这里只处理普通分组名。分组名不存在时静默返回 —— 分组是用户数据，
  /// 名字对不上说明调用方拿了个已经删掉的组，不该再往里写人。
  ///
  /// ⚠️ 不在这里 `liveListSort()`：按「自定义分组」排序时归属变化会影响顺序，
  /// 但一次批量归组（智能分组 / 勾选移入）要动 N 个人，每条都重排就是
  /// O(N² log N)。排序交给调用方在一批操作结束后做一次（见控制器与
  /// `SmartGroupService.execute`）。
  Future<void> addUserToTag(FollowUser user, String tagName) async {
    if (tagName == '全部') {
      return removeAllTagsFromUser(user);
    }
    final tag = followTagList.firstWhereOrNull((t) => t.tag == tagName);
    if (tag == null) {
      return;
    }
    if (!tag.addMember(user.id)) {
      return;
    }
    await updateFollowUserTag(tag);
    // 主分组缓存：没有主分组时，把新加入的组记为主分组，供行副标题展示。
    if (user.tag == '全部' || user.tag.isEmpty) {
      user.tag = tagName;
      await DBService.instance.addFollow(user);
    }
  }

  /// 把关注移出某个分组。移出的是主分组时，主分组顺延到剩余第一个，没有则回 `'全部'`。
  /// 同样不在此重排，理由见 [addUserToTag]。
  Future<void> removeUserFromTag(FollowUser user, String tagName) async {
    if (tagName == '全部') {
      return removeAllTagsFromUser(user);
    }
    final tag = followTagList.firstWhereOrNull((t) => t.tag == tagName);
    if (tag == null || !tag.userId.remove(user.id)) {
      return;
    }
    await updateFollowUserTag(tag);
    if (user.tag == tagName) {
      user.tag = userTagNamesOf(user.id).firstOrNull ?? '全部';
      await DBService.instance.addFollow(user);
    }
  }

  /// 清空某关注的全部归属（回到「未分组」）。只写真的变了的分组。
  Future<void> removeAllTagsFromUser(FollowUser user) async {
    for (final tag in followTagList) {
      if (tag.userId.remove(user.id)) {
        await updateFollowUserTag(tag);
      }
    }
    if (user.tag != '全部') {
      user.tag = '全部';
      await DBService.instance.addFollow(user);
    }
  }
```

> `collection` 包已在该文件顶部导入（`firstWhereOrNull` / `firstOrNull` 可用）。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: 全绿。

- [ ] **Step 6: 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿（新 API 尚未被任何 UI 调用，旧行为不变）。

```bash
git add simple_live_app/lib/models/db/follow_user_tag.dart simple_live_app/lib/services/follow_service.dart simple_live_app/test/follow_membership_test.dart
git commit -m "feat(follow): FollowService 归属 API —— addUserToTag / removeUserFromTag"
```

---

## Task 3: 翻转 `groupedView` —— 分组按 `userId` 分桶

纯逻辑改动，`follow_user_sections_test.dart` 已有 `groupedView` 的用例范式，直接沿用。

**Files:**
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_controller.dart`
- Test: `simple_live_app/test/follow_membership_test.dart`

- [ ] **Step 1: 写失败的测试**

先把探针类加到 `follow_membership_test.dart` 的**顶层**（`main()` 之外）—— Dart 不允许在函数/`group()` 内部声明 `class`，仓库里 `follow_user_sections_test.dart` 的 `_SectionProbe` 也是这么放的：

```dart
/// 只测 getter，不触发 onInit 的订阅与本地存储。
class _Probe extends FollowUserController {
  @override
  // ignore: must_call_super
  void onInit() {}
}
```

再往 `main()` 内追加（`group('FollowService 归属 API', ...)` 之后）：

```dart
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
```

> Dart 不允许在 `group()` 内部声明 `class`。把 `_Probe` 提到文件顶层（`main()` 之外），`group` 里只留 `late _Probe c;` 和 `setUp`。上面代码块里的 `class _Probe` 请照此上移。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: `同一关注出现在它的每个所属分组里` 失败 —— 旧实现按 `u.tag` 单值分桶，`u1` 只出现在第一个匹配的组。

- [ ] **Step 3: 重写 `groupedView`**

替换 `simple_live_app/lib/modules/follow_user/follow_user_controller.dart` 中 `FollowGroupedView get groupedView { ... }` 整个方法体（连同它上面那段「按**标签名**分桶」的文档注释一起换）：

```dart
  /// 「全部」视图的分组模型：每个自定义标签一组 + 未分组一桶。
  ///
  /// 归属唯一真源是 `FollowUserTag.userId`（多分组归属）：一个关注属于 N 个分组，
  /// 就出现在 N 张卡片里；不属于任何分组的落未分组桶。
  /// 组内顺序**继承 `list` 顺序**（`liveListSort` 已按 sortMethod 排好，直播优先），
  /// 不是 `userId` 的插入顺序 —— 否则拖拽调序、切排序方式都会失效。
  /// `userId` 里指向已取关主播的幽灵 id 直接忽略（`followUserAllDataCheck` 负责清）。
  ///
  /// 搜索时空组不产出；不搜索时空组保留（它是拖拽归组的落点，也得让用户
  /// 看得见组存在）。
  ///
  /// 必须在 `Obx` 里读：内部读 `list`、`tagList` 与每项的 `liveStatus`，
  /// 三者任一变化都会自动重切。
  FollowGroupedView get groupedView {
    final tags = customTags;
    // userId -> 它所属的分组 id 集合
    final membership = <String, List<String>>{};
    for (final t in tags) {
      for (final uid in t.userId) {
        (membership[uid] ??= <String>[]).add(t.id);
      }
    }
    final byTagId = <String, List<FollowUser>>{for (final t in tags) t.id: []};
    final ungrouped = <FollowUser>[];
    for (final u in visibleList) {
      final tagIds = membership[u.id];
      if (tagIds == null || tagIds.isEmpty) {
        ungrouped.add(u);
        continue;
      }
      for (final id in tagIds) {
        byTagId[id]!.add(u);
      }
    }
    final searching = searchQuery.value.trim().isNotEmpty;
    final groups = [
      for (final t in tags)
        if (!searching || byTagId[t.id]!.isNotEmpty)
          FollowGroup(
            tag: t,
            members: byTagId[t.id]!,
            liveCount:
                byTagId[t.id]!.where((u) => u.liveStatus.value == 2).length,
          ),
    ];
    return (groups: groups, ungrouped: ungrouped);
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: 全绿。

- [ ] **Step 5: 跑既有分组测试**

Run: `cd simple_live_app && flutter test test/follow_user_sections_test.dart test/follow_grouped_view_test.dart`
Expected: 可能有失败 —— 这两个文件里 `follow_user_sections_test.dart` 的 `groupedView` 用例仍用 `_user('a', tag: 'CS解说')` 造数据、而 `userId` 传的是空列表，翻转后这些人全落未分组。**这是预期的红**，在本 Step 修好它们：把 `seedTags()` 里每个 `FollowUserTag` 的 `userId` 填成对应用户 id。

例：`follow_user_sections_test.dart` 的 `seedTags` 改为

```dart
    void seedTags() {
      FollowService.instance.followTagList.assignAll([
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['douyu_a', 'douyu_b']),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['douyu_c']),
      ]);
    }
```

（`_user()` 造出的 id 是 `'douyu_$name'`，见该文件第 53 行。）
`follow_grouped_view_test.dart` 的 `seedGrouped` 里 `userId` 本来就填了，应当直接通过。

Run: `cd simple_live_app && flutter test test/follow_user_sections_test.dart test/follow_grouped_view_test.dart`
Expected: 全绿。

- [ ] **Step 6: 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿。

```bash
git add simple_live_app/lib/modules/follow_user/follow_user_controller.dart simple_live_app/test/
git commit -m "feat(follow): groupedView 翻转归属真源 —— 按 FollowUserTag.userId 分桶"
```

---

## Task 4: 翻转写路径 —— UI 操作改走归属 API

现在 `FollowUser.tag` 还在，但**不再有任何地方以它为读取依据**（除了主分组缓存展示）。

**Files:**
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_controller.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_tag_manager.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_app_setting/follow_app_settings_controller.dart`
- Modify: `simple_live_app/lib/services/follow_service.dart`
- Test: `simple_live_app/test/follow_grouped_view_test.dart`

- [ ] **Step 1: 写失败的测试（拖入分组 = 加入，不移出原分组）**

追加到 `simple_live_app/test/follow_grouped_view_test.dart` 的 `main()` 内：

```dart
  testWidgets('多分组：拖头像进别的组 = 加入，原分组里仍然可见', (tester) async {
    final svc = await seedGrouped(tester);

    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);

    // 甲 原本在 CS解说；把它拖进 LOL解说
    final avatar =
        find.descendant(of: rowOf('甲'), matching: find.byType(NetImage));
    final gesture = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(cardOf('LOL解说')));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(
        find.descendant(of: cardOf('LOL解说'), matching: find.text('甲')),
        findsOneWidget);
    expect(
        find.descendant(of: cardOf('CS解说'), matching: find.text('甲')),
        findsOneWidget,
        reason: '多分组归属：加入新组不该把它从原组踢出去');
    expect(svc.followTagList.firstWhere((t) => t.tag == 'CS解说').userId,
        contains('huya_甲'));
    await settleEnd(tester);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_grouped_view_test.dart`
Expected: 新用例失败 —— 旧 `setFollowTag` 会先从旧组移除。

- [ ] **Step 3: 控制器改用归属 API**

`simple_live_app/lib/modules/follow_user/follow_user_controller.dart`：

3a. 把 `setFollowTag` 方法（约 497-500 行）替换为：

```dart
  /// 拖拽 / 菜单归组：加入目标分组（多归属，不动它已在的组）。
  /// 目标是内置「全部」= 移出所有分组。
  ///
  /// 归属变了要重排一次：按「自定义分组」排序时顺序取决于归属。
  Future<void> setFollowTag(FollowUser follow, FollowUserTag targetTag) async {
    await FollowService.instance.addUserToTag(follow, targetTag.tag);
    FollowService.instance.liveListSort();
    filterData();
  }
```

3b. `reassignSelected`（约 298-316 行）里的 `setFollowTag` 调用与文案改为「加入」：

```dart
  /// 把全部勾选中的主播**加入** [target]（多归属：原分组里的成员身份保留）。
  Future<void> reassignSelected(FollowUserTag target) async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    var moved = 0;
    for (final id in ids) {
      final user = FollowService.instance.followList
          .firstWhereOrNull((u) => u.id == id);
      if (user == null) {
        continue; // 已被取关的幽灵 id，跳过
      }
      await FollowService.instance.addUserToTag(user, target.tag);
      moved++;
    }
    // 一批操作结束后只重排一次（addUserToTag 内部不排，见其注释）
    FollowService.instance.liveListSort();
    clearSelection();
    filterData();
    SmartDialog.showToast("已将 $moved 位主播加入「${target.tag}」");
  }
```

3c. `removeFollow`（约 474-491 行）删掉这段 —— `FollowService.removeFollowUser` 现在自己负责清归属：

```dart
    // 取消关注同时删除标签内的 userId
    if (follow.tag != "全部") {
      var tag = tagList.firstWhereOrNull((tag) => tag.tag == follow.tag);
      if (tag != null) {
        tag.userId.remove(follow.id);
        updateTag(tag);
      }
    }
```

3d. `setFollowTagDialog`（约 535-628 行）整段替换为多选版本：

```dart
  /// 设置分组：多选（一个关注可以同时属于多个分组）。
  ///
  /// 打开时勾上它当前所属的组；点 ✓ 才落库 —— 按「新增 / 移除」两个差集执行，
  /// 不做「先清空再全量写」，避免把 fractional id 顺序之外的数据抖一遍。
  void setFollowTagDialog(FollowUser follow) {
    final copiedList = [...tagList.skip(3)];
    final checked = <String>{...FollowService.instance.userTagNamesOf(follow.id)}.obs;

    Get.dialog(
      AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('设置分组', style: TextStyle(fontSize: 18)),
                IconButton(
                  tooltip: "保存",
                  icon: const Icon(Icons.check),
                  onPressed: () async {
                    final before =
                        FollowService.instance.userTagNamesOf(follow.id).toSet();
                    for (final name in checked.difference(before)) {
                      await FollowService.instance.addUserToTag(follow, name);
                    }
                    for (final name in before.difference(checked)) {
                      await FollowService.instance
                          .removeUserFromTag(follow, name);
                    }
                    FollowService.instance.liveListSort();
                    filterData();
                    Get.back();
                  },
                ),
              ],
            ),
            const Divider(),
            if (copiedList.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有分组，先去「分组管理」新建'),
              )
            else
              SizedBox(
                height: 300,
                width: 300,
                child: Obx(
                  () => ListView.builder(
                    itemCount: copiedList.length,
                    itemBuilder: (context, index) {
                      final tagItem = copiedList[index];
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: Colors.grey.shade300, width: 1.0),
                          ),
                        ),
                        child: CheckboxListTile(
                          title: Text(tagItem.tag),
                          value: checked.contains(tagItem.tag),
                          onChanged: (v) {
                            if (v == true) {
                              checked.add(tagItem.tag);
                            } else {
                              checked.remove(tagItem.tag);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: `FollowService` 里以 `follow.tag` 为依据的逻辑全部翻转**

`simple_live_app/lib/services/follow_service.dart`：

4a. `addFollow`（约 237-246 行）里这段删掉 —— 归属由 `userId` 单向管理，`addFollow` 不再反向改分组：

```dart
    // 更新标签归属
    if (follow.tag != '全部') {
      FollowUserTag? tagObj = followTagList.firstWhereOrNull((t) => t.tag == follow.tag);
      if (tagObj != null) {
        // 自刷新和迁移逻辑一致：删旧增新
        tagObj.userId.remove(follow.id);
        tagObj.userId.add(follow.id);
        await updateFollowUserTag(tagObj);
      }
    }
```

替换为一行注释：

```dart
    // 归属由 FollowUserTag.userId 单向持有，这里不反向同步（历史双写正是错乱之源）。
```

4b. `removeFollowUser`（约 267-275 行）的 `if (follow.tag != "全部") { ... }` 块替换为：

```dart
    // 取消关注 = 从所有分组的成员表里消失（只写真的少了人的那个组）
    for (final tag in followTagList) {
      if (tag.userId.remove(id)) {
        await updateFollowUserTag(tag);
      }
    }
```

4c. `removeFollowUserTag`（约 120-131 行）：删组时不再逐个回写 `follow.tag`，成员表随分组对象一起消失；只需把「主分组」缓存指向被删组的关注重置：

```dart
  Future removeFollowUserTag(FollowUserTag tag) async {
    final memberIds = tag.userId.toList();
    followTagList.remove(tag);
    await DBService.instance.deleteFollowTag(tag.id);
    // 主分组缓存要跟着落地，否则行副标题会显示一个已经不存在的分组名。
    // 注意写 `DBService.instance.addFollow`（裸落库），不要用 FollowService.addFollow：
    // 后者会把 `deleted` 复位成 false，万一成员表里残留了墓碑 id 就等于复活了取关的人。
    for (final id in memberIds) {
      final follow = DBService.instance.getFollow(id);
      if (follow != null && follow.tag == tag.tag) {
        follow.tag = userTagNamesOf(id).firstOrNull ?? '全部';
        await DBService.instance.addFollow(follow);
      }
    }
  }
```

4d. `updateTagName`（约 87-98 行）：成员靠 id 关联，改名不再需要重写每个关注；只更新主分组缓存：

```dart
  Future<void> updateTagName(
      FollowUserTag followUserTag, String newTagName) async {
    final FollowUserTag newTag = followUserTag.copyWith(tag: newTagName);
    await updateFollowUserTag(newTag);
    for (final id in newTag.userId) {
      final follow = DBService.instance.getFollow(id);
      if (follow != null && follow.tag == followUserTag.tag) {
        follow.tag = newTagName;
        await DBService.instance.addFollow(follow);
      }
    }
  }
```

4e. `followUserAllDataCheck`（约 781-829 行）里这两段（约 806-810 行）删掉：

```dart
    for (var follow in followUserListTemp) {
      if (follow.tag != "全部") {
        tagMap.putIfAbsent(follow.tag, () => <String>[]).add(follow.id);
      }
    }
```

并把 `tagMap` 的构造（约 785-787 行）改为「以 userId 为源、剔除已取关的幽灵 id」：

```dart
    final aliveIds = followUserListTemp.map((f) => f.id).toSet();
    final Map<String, List<String>> tagMap = {
      for (var tag in oldTagList)
        tag.tag: tag.userId.where(aliveIds.contains).toList(),
    };
```

方法末尾的裸 box 写入（约 823-824 行）：

```dart
    await DBService.instance.tagBox.clear();
    await DBService.instance.tagBox.putAll(res);
```

改走 Step 3 新增的方法（Task 6 的 `inputJson` 测试会跑到这里，替身只覆盖得了方法、覆盖不了字段）：

```dart
    await DBService.instance.replaceAllFollowTags(res);
```

> 校对思路的注释块（约 772-780 行）里第 2、3 条描述的是 `follow.tag` 与 `userId` 不一致的场景，翻转后不存在，请同步改写为：「1：分组里含已取关的幽灵 id；2：分组名重复；3：webdav 同步导致的数据错乱。思路：`followList` 是存在性基础，`tagList` 是归属唯一真源，按前者过滤后者的成员表。」

4f. `listSortByMethod` 的 `tagCondition`（约 571-577 行）改为按「第一个所属分组」的显示顺序：

```dart
    var tagCondition = SortCondition<FollowUser>(
      valueGetter: (item) {
        final names = userTagNamesOf(item.id);
        if (names.isEmpty) {
          return followTagList.length; // 未分组排最后
        }
        return followTagList.indexWhere((t) => t.tag == names.first);
      },
    );
```

4g. `setFollowTag`（约 147-185 行）整段替换为**过渡壳**：

```dart
  /// 过渡壳：关注详情页（`FollowInfoController.changeTag`）还在用「一个分组对象」
  /// 的旧语义，先转发到多归属 API。Task 5 把详情页改成多选后，本方法随之删除。
  Future<void> setFollowTag(FollowUser item, FollowUserTag targetTag) async {
    await addUserToTag(item, targetTag.tag);
  }
```

> **不要在这里直接删除 `setFollowTag`** —— `follow_info_controller.dart:76` 仍在调它，删了本任务结束时 `flutter analyze` 就是红的。「每个任务结束时都能编译、测试全绿」是本计划的硬约束，删除一律放到调用点全部改完之后（Task 5 Step 6）。

- [ ] **Step 5: 分组管理 sheet 去掉 `follow.tag` 依赖**

`simple_live_app/lib/modules/follow_user/follow_tag_manager.dart` 的 `removeTag` 不变（它已委托给 `FollowService.removeFollowUserTag`）。检查 `updateTagName`：Task 4d 已把同步逻辑收进 service，这里无需改动。

`simple_live_app/lib/modules/follow_user/follow_app_setting/follow_app_settings_controller.dart` 的 `cleanFollow`（约 41-59 行）里这段删掉（`removeFollowUser` 已负责）：

```dart
      // 取消关注同时删除标签内的 userId
      if (follow.tag != "全部") {
        var tag = userTagList.firstWhere((tag) => tag.tag == follow.tag);
        tag.userId.remove(follow.id);
        await updateTag(tag);
      }
```

- [ ] **Step 6: 测试 harness 补内存版归属 API**

widget 测试里没有注册 `DBService`（真实现经它写 Hive），所以 `follow_test_harness.dart` 的 `FakeFollowService` 必须把新 API 也改成内存实现，否则 Step 1 的用例会在 `GetFindCanceled` 上炸。在该类中新增（`liveListSort()` 是真实现、只读内存列表，可直接用）：

```dart
  @override
  Future<void> addUserToTag(FollowUser user, String tagName) async {
    if (tagName == '全部') {
      return removeAllTagsFromUser(user);
    }
    final tag = followTagList.where((t) => t.tag == tagName).firstOrNull;
    if (tag == null || !tag.addMember(user.id)) {
      return;
    }
    if (user.tag == '全部' || user.tag.isEmpty) {
      user.tag = tagName;
    }
  }

  @override
  Future<void> removeUserFromTag(FollowUser user, String tagName) async {
    if (tagName == '全部') {
      return removeAllTagsFromUser(user);
    }
    final tag = followTagList.where((t) => t.tag == tagName).firstOrNull;
    if (tag == null || !tag.userId.remove(user.id)) {
      return;
    }
    if (user.tag == tagName) {
      user.tag = userTagNamesOf(user.id).firstOrNull ?? '全部';
    }
  }

  @override
  Future<void> removeAllTagsFromUser(FollowUser user) async {
    for (final tag in followTagList) {
      tag.userId.remove(user.id);
    }
    user.tag = '全部';
  }
```

> `FakeFollowService` 现有的 `setFollowTag` override 先保留 —— 阶段一期间它仍被拖拽路径调用。Task 5 Step 6b 删除 `FollowService.setFollowTag` 过渡壳时，**必须同步删掉这个 override**（`@override` 指向已不存在的父方法会编译失败）。

- [ ] **Step 7: 跑测试确认通过**

Run: `cd simple_live_app && flutter test test/follow_grouped_view_test.dart test/follow_membership_test.dart test/follow_tag_reorder_test.dart`
Expected: 全绿。

- [ ] **Step 8: 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿。

```bash
git add simple_live_app/lib/modules/follow_user/ simple_live_app/lib/services/follow_service.dart simple_live_app/test/
git commit -m "feat(follow): 写路径翻转 —— 归组改为「加入」，取关/删组/改名走 userId"
```

---

## Task 5: UI 语义对齐（拖拽谓词、编辑 sheet、详情页多选、行副标题）

**Files:**
- Modify: `simple_live_app/lib/modules/follow_user/widgets/follow_group_card.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_page.dart`
- Modify: `simple_live_app/lib/modules/follow_user/widgets/follow_quick_group_sheet.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_info_setting/follow_info_controller.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_info_setting/follow_info_page.dart`
- Modify: `simple_live_app/lib/widgets/follow_user_item.dart`
- Test: `simple_live_app/test/follow_grouped_view_test.dart`

- [ ] **Step 1: 写失败的测试（已在组内的成员拖回本组不高亮）**

`follow_grouped_view_test.dart` 顶部已有 `import 'package:flutter/material.dart' show Icons, Key, MediaQuery, SingleChildScrollView;`，本步骤往那个 `show` 列表里补 `Container`。

追加到 `follow_grouped_view_test.dart` 的 `main()`：

```dart
  testWidgets('已在组内的成员拖回本组：不高亮（同组拖回不该像发生了移动）',
      (tester) async {
    await seedGrouped(tester);

    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);

    // 甲 已经在 CS解说 里，把它拖回 CS解说
    final avatar =
        find.descendant(of: rowOf('甲'), matching: find.byType(NetImage));
    final gesture = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(cardOf('CS解说')));
    await tester.pump();

    // 高亮 = DragTarget 收到 candidate 时给最外层 Container 画的 1.5 描边。
    // 同组成员拖回来不该收到 candidate，所以描边必须是透明的。
    final shell = tester.widget<Container>(
      find.descendant(
        of: cardOf('CS解说'),
        matching: find.byType(Container, skipOffstage: false),
      ).first,
    );
    final deco = shell.decoration as BoxDecoration;
    expect((deco.border!.top as BorderSide).color, Colors.transparent,
        reason: '同组成员拖回本组不该高亮');

    await gesture.up();
    await settle(tester);
    await settleEnd(tester);
  });
```

> 若 `find.byType(Container).first` 定位到的不是卡片最外层那个（卡片内部还有别的 `Container`），给 `FollowGroupCard` 最外层 `Container` 加 `key: const Key('group-card-shell')`，改用 `find.byKey(const Key('group-card-shell'))`。加 key 是允许的改动，且更稳。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_grouped_view_test.dart`
Expected: 新用例失败 —— 旧谓词读的是 `details.data.tag`，阶段一之后它只是「主分组」缓存，同组拖回仍会给出高亮。

- [ ] **Step 3: 分组卡片拖拽谓词**

`simple_live_app/lib/modules/follow_user/widgets/follow_group_card.dart` 第 69-72 行：

```dart
    return DragTarget<FollowUser>(
      // 同组成员拖回本组 = 无操作，不显示高亮。
      onWillAcceptWithDetails: (details) => details.data.tag != group.tag.tag,
      onAcceptWithDetails: (details) => onDropMember(details.data),
```

改为：

```dart
    return DragTarget<FollowUser>(
      // 已经在组里的成员拖回来 = 无操作，不高亮（多归属下「加入」是幂等的，
      // 但高亮会误导用户以为发生了移动）。
      onWillAcceptWithDetails: (details) => !group.tag.contains(details.data.id),
      onAcceptWithDetails: (details) => onDropMember(details.data),
```

- [ ] **Step 4: 未分组段的落点谓词**

`simple_live_app/lib/modules/follow_user/follow_user_page.dart` 第 810-812 行：

```dart
    return DragTarget<FollowUser>(
      onWillAcceptWithDetails: (details) => details.data.tag != "全部",
      onAcceptWithDetails: (details) => onDrop(details.data),
```

改为（`_UngroupedSection` 新增一个 `hasMembership` 回调参数，避免 widget 直接摸 service）：

```dart
    return DragTarget<FollowUser>(
      // 只有「至少属于一个分组」的人才值得往未分组拖（移出全部归属）。
      onWillAcceptWithDetails: (details) => hasMembership(details.data),
      onAcceptWithDetails: (details) => onDrop(details.data),
```

`_UngroupedSection` 的字段区，在 `final ValueChanged<FollowUser> onDrop;` 之后加一行：

```dart
  /// 该关注是否至少属于一个分组（决定它能不能被「拖出分组」）。
  final bool Function(FollowUser) hasMembership;
```

并在 `const _UngroupedSection({...})` 的参数列表里、`required this.onDrop,` 之前加 `required this.hasMembership,`。

调用处（约 609-627 行）补：

```dart
          hasMembership: (u) =>
              FollowService.instance.userTagNamesOf(u.id).isNotEmpty,
          onDrop: (u) => controller.setFollowTag(u, controller.tagList.first),
```

（`setFollowTag` 传内置「全部」在 Task 4 里已经等价于「移出所有分组」。）

- [ ] **Step 5: 编辑 sheet 文案与「移出」入口**

`simple_live_app/lib/modules/follow_user/widgets/follow_quick_group_sheet.dart`：

- 第 145 行文案 `'将已选的 $n 位主播加入该分组，原分组中的成员不受影响'` 改为
  `'将已选的 $n 位主播加入该分组；一个主播可以同时属于多个分组'`。
- 第 156 行 `'或移入已有分组'` 改为 `'或加入已有分组'`。
- 第 172-175 行那个 chip：

```dart
                        FilterButton(
                          text: '全部（移出分组）',
                          onTap: () => _moveTo(widget.ungroupTag),
                        ),
```

改为：

```dart
                        FilterButton(
                          text: '移出所有分组',
                          onTap: () => _moveTo(widget.ungroupTag),
                        ),
```

`FollowUserController.reassignSelected` 已能处理「全部」= 移出所有归属（`addUserToTag` 的 `'全部'` 分支走 `removeAllTagsFromUser`），无需再改。

- [ ] **Step 6: 详情页分组设置改多选**

`simple_live_app/lib/modules/follow_user/follow_info_setting/follow_info_controller.dart`：

把 `selectedTag` 字段（第 20 行）换成：

```dart
  /// 已勾选的分组名（多归属）。
  final RxSet<String> checkedTags = <String>{}.obs;
```

`_initTagOptions`（第 43-59 行）替换为：

```dart
  void _initTagOptions() {
    tagOptions.assignAll(FollowService.instance.followTagList);
    final current = followUser.value;
    checkedTags.assignAll(current == null
        ? const <String>[]
        : FollowService.instance.userTagNamesOf(current.id));
  }
```

`changeTag`（第 73-79 行）替换为：

```dart
  /// 勾选/取消一个分组（多归属，即时落库）。
  Future<void> toggleTag(FollowUserTag tag) async {
    final current = followUser.value;
    if (current == null) return;
    if (checkedTags.contains(tag.tag)) {
      checkedTags.remove(tag.tag);
      await FollowService.instance.removeUserFromTag(current, tag.tag);
    } else {
      checkedTags.add(tag.tag);
      await FollowService.instance.addUserToTag(current, tag.tag);
    }
    followUser.refresh();
  }
```

`_migrateTo`（第 164-176 行）里 `tag: current.tag,` 这一行**保留**（`FollowUser.tag` 此刻还在），并在 `await FollowService.instance.addFollow(newFollow);`（第 180 行）之后补一行把归属搬过去：

```dart
    // 迁移换了 id，归属要跟着搬到新 id 上
    for (final tagName in FollowService.instance.userTagNamesOf(current.id)) {
      await FollowService.instance.addUserToTag(newFollow, tagName);
    }
```

- [ ] **Step 6b: 删掉 Task 4 留下的过渡壳**

详情页改完多选后，`FollowService.setFollowTag` 已无调用点。删除 `simple_live_app/lib/services/follow_service.dart` 中 Task 4 Step 4g 加的过渡壳方法，并确认 `follow_info_controller.dart` 里不再有任何 `setFollowTag` 调用：

Run: `cd simple_live_app && flutter analyze`
Expected: 无 `undefined_method` / `unused_element` 报错。

`simple_live_app/lib/modules/follow_user/follow_info_setting/follow_info_page.dart` 第 97-119 行那段 `SettingsMenu<String>` 替换为 chip 多选：

```dart
          // 分组设置：多归属，点 chip 勾选/取消
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Obx(() {
              final items = controller.tagOptions;
              if (items.isEmpty) {
                return const Text('还没有分组，先去「关注设置 → 分组管理」新建');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('分组设置', style: Theme.of(context).textTheme.bodyLarge),
                  AppStyle.vGap8,
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final t in items)
                        FilterButton(
                          text: t.tag,
                          selected: controller.checkedTags.contains(t.tag),
                          onTap: () => controller.toggleTag(t),
                        ),
                    ],
                  ),
                ],
              );
            }),
          ),
```

该文件需补 import：`package:simple_live_app/widgets/filter_button.dart`。

- [ ] **Step 7: 行副标题显示派生分组名**

`simple_live_app/lib/widgets/follow_user_item.dart` 第 151-161 行那段 `item.tag` 的 `Text` 替换为：

```dart
            Text(
              // 归属唯一真源是分组的成员表，这里显示它所属的分组（多个用 · 连接，
              // 整体仍截到 8 字，避免长组名把行尾挤没）。
              () {
                final names =
                    FollowService.instance.userTagNamesOf(item.id);
                if (names.isEmpty) return '全部';
                final joined = names.join(' · ');
                return joined.length > 8 ? '${joined.substring(0, 8)}...' : joined;
              }(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
```

该文件需补 import：`package:simple_live_app/services/follow_service.dart`。

- [ ] **Step 8: 跑测试 + 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿。若 `follow_grouped_view_test.dart` 里「拖到未分组的丁行 = 移出分组」那条失败，原因是 `hasMembership` 谓词 —— 丙 属于 LOL解说，`userTagNamesOf` 非空，应当接受；检查 Step 4 的 `hasMembership` 是否接错。

```bash
git add simple_live_app/lib/modules/follow_user/ simple_live_app/lib/widgets/follow_user_item.dart simple_live_app/test/follow_grouped_view_test.dart
git commit -m "feat(follow): UI 语义对齐多分组 —— 拖入=加入、详情页多选、行副标题派生"
```

---

## Task 6: 导入导出 & WebDAV 兼容

`FollowUser.tag` 作为「主分组」缓存暂时保留在 JSON 里，同时新增 `tags` 数组；读时两者都认。

**Files:**
- Modify: `simple_live_app/lib/services/follow_service.dart`
- Modify: `simple_live_app/lib/modules/sync/remote_sync/webdav/resources/follow_sync_resource.dart`
- Test: `simple_live_app/test/follow_membership_test.dart`

- [ ] **Step 1: 写失败的测试（JSON 往返保住多归属）**

追加到 `follow_membership_test.dart` 的 `main()`：

```dart
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
```

该文件顶部需补 `import 'dart:convert';`。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart`
Expected: `generateJson 带 tags 数组` 失败（当前导出的是 `"tag":"我的喜爱"`）。

- [ ] **Step 3: 导出加 `tags`**

`simple_live_app/lib/services/follow_service.dart` 的 `generateJson`（约 740-759 行），把 `"tag": item.tag` 换成：

```dart
            "tag": item.tag,
            "tags": userTagNamesOf(item.id),
```

- [ ] **Step 4: 导入认两种格式**

`inputJson`（约 761-770 行）替换为：

```dart
  Future inputJson(String content) async {
    var data = jsonDecode(content);

    for (var item in data) {
      var follow = FollowUser.fromJson(item);
      await DBService.instance.addFollow(follow);
      // 新版带 tags 数组；旧备份只有单个 tag 字段，两者都认。
      final names = <String>[];
      if (item['tags'] is List) {
        names.addAll((item['tags'] as List).whereType<String>());
      } else if (item['tag'] is String) {
        names.add(item['tag'] as String);
      }
      for (final name in names) {
        if (name.isEmpty || name == '全部') {
          continue;
        }
        if (!followTagList.any((t) => t.tag == name)) {
          await addFollowUserTag(name);
        }
        await addUserToTag(follow, name);
      }
    }

    await followUserAllDataCheck();
  }
```

- [ ] **Step 5: WebDAV 合并不再从 `follow.tag` 重建分组**

`simple_live_app/lib/modules/sync/remote_sync/webdav/resources/follow_sync_resource.dart` 的 `merge`（约 99-133 行），把第 111-131 行那段（`// tags after merge, logic from data_check` 起，含 `for (var follow in resFollows) { if (follow.tag != "全部") ... }`）替换为「按分组名并集合并成员表，再剔除已不存在的关注」：

```dart
    // tags 合并：归属唯一真源是 userId 成员表，按分组名取并集，
    // 再剔除已经不存在（或已是墓碑）的关注，避免把幽灵成员同步回来。
    final aliveIds = resFollows.where((f) => !f.deleted).map((f) => f.id).toSet();
    final Map<String, Set<String>> merged = {
      for (var tag in local.tags) tag.tag: tag.userId.where(aliveIds.contains).toSet(),
    };
    for (var tag in remote.tags) {
      merged.putIfAbsent(tag.tag, () => <String>{}).addAll(
            tag.userId.where(aliveIds.contains),
          );
    }
    final resTags = <FollowUserTag>[];
    String? lastKey;
    for (var entry in merged.entries) {
      lastKey = FractionalIndexing.generateKeyBetween(lastKey, null);
      resTags.add(FollowUserTag(
        id: lastKey,
        tag: entry.key,
        userId: entry.value.toList(),
      ));
    }
```

- [ ] **Step 6: 跑测试 + 全量回归 + 提交**

Run: `cd simple_live_app && flutter test test/follow_membership_test.dart && flutter test`
Expected: 全绿。

```bash
git add simple_live_app/lib/services/follow_service.dart simple_live_app/lib/modules/sync/ simple_live_app/test/follow_membership_test.dart
git commit -m "feat(follow): 导入导出与 WebDAV 合并改为以成员表为归属真源"
```

---

## Task 7: 删除 `FollowUser.tag` 冷字段（收尾）

所有读路径都已翻转，现在删掉它，一次性清理残留引用。

**Files:**
- Modify: `simple_live_app/lib/models/db/follow_user.dart`
- Regenerate: `simple_live_app/lib/models/db/follow_user.g.dart`
- Modify: `simple_live_app/lib/services/follow_service.dart`
- Modify: `simple_live_app/lib/services/migration_service.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_info_setting/follow_info_controller.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_controller.dart`
- Modify: 所有 `FollowUser(..., tag: ...)` 的测试文件

- [ ] **Step 1: 删除模型字段**

`simple_live_app/lib/models/db/follow_user.dart`：
- 构造函数删 `this.tag = "全部",`
- 删字段声明 `@HiveField(7) String tag;`（连同上面无关注释）
- `fromJson` 删 `tag: json["tag"] ?? "全部",`
- `toJson` 删 `"tag": tag,`

- [ ] **Step 2: 重新生成 adapter**

Run: `cd simple_live_app && dart run build_runner build --delete-conflicting-outputs`
Expected: 构建成功，`follow_user.g.dart` 的 `read` 不再引用 field 7、`write` 的 `writeByte(15)` 变 `writeByte(14)`。

- [ ] **Step 3: 清掉所有编译错误**

Run: `cd simple_live_app && flutter analyze`
Expected: 一批 `The getter 'tag' isn't defined for the type 'FollowUser'` / `No named parameter with the name 'tag'`。逐处修：

3a. `lib/services/follow_service.dart`
- `updateTagName`：删掉整个「回写 follow.tag」的 for 循环，方法只剩
  ```dart
  Future<void> updateTagName(
      FollowUserTag followUserTag, String newTagName) async {
    // 成员靠 id 关联，改名只是换个显示名，不需要碰任何关注记录。
    await updateFollowUserTag(followUserTag.copyWith(tag: newTagName));
  }
  ```
- `removeFollowUserTag`：删掉「重置主分组缓存」的 for 循环，只剩
  ```dart
  Future removeFollowUserTag(FollowUserTag tag) async {
    followTagList.remove(tag);
    await DBService.instance.deleteFollowTag(tag.id);
  }
  ```
- `addUserToTag` / `removeUserFromTag` / `removeAllTagsFromUser`：删掉所有 `user.tag = ...` 与相关的 `DBService.instance.addFollow(user)` 分支（只保留成员表操作 + `liveListSort()`）。
- `generateJson`：删 `"tag": item.tag,` 一行（`tags` 已在）。
- 文件内其它 `follow.tag` / `item.tag`（`FollowUser` 的）残留一并删除。

3b. `lib/services/migration_service.dart`
- 删掉 `curDBVer <= 10709` 那段（约 68-82 行，它把 `tag.tag` 写进 `followList[i].tag`）。留一行注释说明该迁移已被 `migrateTagMembership` 取代。
- `migrateTagMembership` 现在没法再读 `follow.tag`：改为**幂等空操作并标注历史**，或直接删除并在 `migrateDataByVersion` 里去掉调用。选择删除，并在原调用处留注释：
  ```dart
    // v1.8.16：follow.tag 已删除，归属真源是 FollowUserTag.userId，
    // 无需再回填（历史迁移见 git blame: migrateTagMembership）。
  ```

3c. `lib/modules/follow_user/follow_info_setting/follow_info_controller.dart`
- `_migrateTo` 里 `tag: current.tag,` 删掉；归属搬运改用 Task 5 已加的循环（它读的是 `userTagNamesOf`，不依赖字段）。

3d. `lib/modules/follow_user/follow_user_controller.dart`
- `isReservedTagName` 的文档注释里「`FollowUser.tag` 与 `getTagOptionsWithAll` 都按名字判『全部』哨兵」改写为：「内置 tab 只活在 `tagList` 前三项、不入库，但 `'全部'` 是「不属于任何分组」的哨兵名：自定义分组撞名会让界面与语义打架，所以直接禁止。」
- `groupedView` 上方若还残留 `FollowUser.tag` 相关注释，一并清理。

3e. 测试文件里所有 `FollowUser(..., tag: 'X')`：改为构造后往 `followTagList` 对应分组的 `userId` 里塞 id。
- `test/follow_grouped_view_test.dart`：`_u(String name, {String tag = '全部', int live = 1})` 去掉 `tag` 参数；`seedGrouped` 的 `tags:` 已经填了 `userId`，把 `users:` 里的 `tag:` 实参删掉即可。断言 `expect(user.tag, 'LOL解说')` 改为 `expect(svc.userTagNamesOf('huya_丁'), contains('LOL解说'))`；`expect(...tag, '全部')` 改为 `expect(svc.userTagNamesOf(...), isEmpty)`。
- `test/follow_user_sections_test.dart`：同上，`_user` 去掉 `tag` 参数，用例靠 `userId` 造归属。
- `test/viewpager_drag_test.dart`：`_u` 去掉 `tag` 参数；`tags:` 里已填 `userId`。
- `test/follow_membership_test.dart`：Task 1 的 `migrateTagMembership` 用例整体删除（该函数已不存在）；其余 `user(..., tag: ...)` 辅助去掉 `tag`。

- [ ] **Step 4: 跑全量测试**

Run: `cd simple_live_app && flutter analyze && flutter test`
Expected: analyze 无 error；测试全绿。

- [ ] **Step 5: 提交**

```bash
git add simple_live_app/lib simple_live_app/test
git commit -m "refactor(follow)!: 删除 FollowUser.tag 冷字段 —— FollowUserTag.userId 为归属唯一真源"
```

> **老数据兼容**：`hive_ce` 的 adapter 按 `numOfFields` 逐字段读，旧记录里多出来的 field 7 会被忽略，不会崩。旧版本 app 读到新记录时 `fields[7] == null` → 回退 `'全部'`，即「分组归属在旧版本看来丢失」，但成员表本身随 `tagBox` 一起同步，重新升级到新版本后归属自动回来。这条要在 PR 描述里写明。

---

# 阶段二：一键按平台智能分组

## Task 8: `SmartGroupService` —— 纯逻辑，可单测

设计（已与用户确认）：

- 范围：**所有**关注都加入自己平台的分组（多归属下不破坏任何东西），不是只填补未分组的。
- 分组名：平台全名，取 `Sites.allSites[siteId]!.name`（`哔哩哔哩` / `斗鱼直播` / `虎牙直播` / `抖音直播` / `Twitch`）。
- 幂等：同名分组复用；已在该平台组里的人不重复加。重复点第二次 = 0 新增。
- 未知 `siteId`（站点被移除）跳过，不建组。
- 顺序：优先用 `AppSettingsController.instance.siteSort`（用户在首页排好的平台顺序），未注册时回退 `Sites.allSites.keys` 的声明顺序 —— 这样纯逻辑测试不必注册设置控制器。

**Files:**
- Create: `simple_live_app/lib/services/smart_group_service.dart`
- Create: `simple_live_app/test/smart_group_service_test.dart`

- [ ] **Step 1: 写失败的测试**

新建 `simple_live_app/test/smart_group_service_test.dart`：

```dart
// 一键按平台分组的纯逻辑测试。
//
// 只验「谁进了哪个组」，不碰 UI：SmartGroupService 经 FakeDBService 走内存，
// Sites.allSites 是静态表，不需要注册任何控制器。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/smart_group_service.dart';

class _FakeDBService extends DBService {
  final tags = <String, FollowUserTag>{};

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
}

class _LiveFollowService extends FollowService {
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
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/smart_group_service_test.dart`
Expected: 编译失败 —— `smart_group_service.dart` 不存在。

- [ ] **Step 3: 实现 `SmartGroupService`**

新建 `simple_live_app/lib/services/smart_group_service.dart`：

```dart
import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/follow_service.dart';

/// 一键按平台分组：把每个关注**加入**以它所在平台命名的分组。
///
/// 为什么不是「移到」：归属唯一真源是 `FollowUserTag.userId` 成员表，一个关注
/// 可以同时属于「我的喜爱」和「虎牙直播」，所以按平台归组不会冲掉用户手工
/// 整理的任何分组。
///
/// 幂等：同名分组复用、已在组内的成员跳过 —— 连点两次第二次是 0 新增。
/// 未知 siteId（站点被移除）跳过，不建空组。
class SmartGroupService extends GetxService {
  static SmartGroupService get instance => Get.find<SmartGroupService>();

  /// 只算不改，给确认弹窗用。
  SmartGroupPreview preview() {
    final svc = FollowService.instance;
    final items = <SmartGroupPreviewItem>[];
    for (final siteId in _orderedSiteIds) {
      final site = Sites.allSites[siteId];
      if (site == null) continue;
      final users =
          svc.followList.where((u) => u.siteId == siteId).toList();
      if (users.isEmpty) continue;
      final tag = _tagByName(site.name);
      items.add(SmartGroupPreviewItem(
        siteId: siteId,
        siteName: site.name,
        userCount: users.length,
        tagAlreadyExists: tag != null,
        // 已经在这个组里的人数 —— 决定「这次会真的新增几个成员」。
        alreadyMemberCount: tag == null
            ? 0
            : users.where((u) => tag.contains(u.id)).length,
      ));
    }
    // 落在已知平台之外的关注也要给个数，否则用户会以为「总数」算错了。
    final known = _orderedSiteIds.toSet();
    final orphan = svc.followList
        .where((u) => !known.contains(u.siteId))
        .toList();
    return SmartGroupPreview(
      items: items,
      totalFollows: svc.followList.length,
      skippedUnknownSite: orphan.length,
    );
  }

  /// 执行归组，返回统计。
  Future<SmartGroupResult> execute() async {
    final svc = FollowService.instance;
    var tagsCreated = 0;
    var membersAdded = 0;

    for (final siteId in _orderedSiteIds) {
      final site = Sites.allSites[siteId];
      if (site == null) continue;
      final users = svc.followList.where((u) => u.siteId == siteId).toList();
      if (users.isEmpty) continue;

      var tag = _tagByName(site.name);
      if (tag == null) {
        await svc.addFollowUserTag(site.name);
        tag = _tagByName(site.name);
        if (tag == null) {
          // 重名被拒（理论上不会走到：刚查过不存在）。记日志跳过，别硬写。
          Log.w('SmartGroup: 创建分组「${site.name}」失败，跳过');
          continue;
        }
        tagsCreated++;
      }

      for (final user in users) {
        final before = tag.userId.length;
        await svc.addUserToTag(user, site.name);
        if (tag.userId.length > before) {
          membersAdded++;
        }
      }
    }

    // 整批归组结束后只重排一次（addUserToTag 内部不排，见其注释）
    if (membersAdded > 0) {
      svc.liveListSort();
    }

    Log.i('SmartGroup: created $tagsCreated tags, added $membersAdded memberships');
    return SmartGroupResult(tagsCreated: tagsCreated, membersAdded: membersAdded);
  }

  FollowUserTag? _tagByName(String name) =>
      FollowService.instance.followTagList.firstWhereOrNull((t) => t.tag == name);

  /// 平台顺序：优先用户在首页排好的 `siteSort`，没注册（纯逻辑测试）时退回声明顺序。
  List<String> get _orderedSiteIds {
    if (Get.isRegistered<AppSettingsController>()) {
      final sort = AppSettingsController.instance.siteSort;
      if (sort.isNotEmpty) {
        return sort.toList();
      }
    }
    return Sites.allSites.keys.toList();
  }
}

/// 确认弹窗的数据：一个平台一行。
class SmartGroupPreviewItem {
  final String siteId;
  final String siteName;
  final int userCount;

  /// 同名分组是否已存在（弹窗上区分「复用」与「新建」）。
  final bool tagAlreadyExists;

  /// 该平台里**已经**在这个分组中的人数（复用场景）。`userCount - alreadyMemberCount`
  /// 就是本次会真的新增的成员数。
  final int alreadyMemberCount;

  const SmartGroupPreviewItem({
    required this.siteId,
    required this.siteName,
    required this.userCount,
    required this.tagAlreadyExists,
    this.alreadyMemberCount = 0,
  });

  /// 本次将新增的成员数。
  int get pendingCount => userCount - alreadyMemberCount;
}

class SmartGroupPreview {
  final List<SmartGroupPreviewItem> items;
  final int totalFollows;

  /// 因平台未知而无法归组的关注数。
  final int skippedUnknownSite;

  const SmartGroupPreview({
    required this.items,
    required this.totalFollows,
    this.skippedUnknownSite = 0,
  });

  int get newTagCount => items.where((e) => !e.tagAlreadyExists).length;
  int get reuseTagCount => items.where((e) => e.tagAlreadyExists).length;
  int get totalMembers => items.fold(0, (sum, e) => sum + e.userCount);

  /// 本次执行会真的产生的成员新增总数（含新建组的成员）。
  int get pendingTotal => items.fold(0, (sum, e) => sum + e.pendingCount);
}

class SmartGroupResult {
  final int tagsCreated;
  final int membersAdded;

  const SmartGroupResult({required this.tagsCreated, required this.membersAdded});

  bool get didNothing => tagsCreated == 0 && membersAdded == 0;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd simple_live_app && flutter test test/smart_group_service_test.dart`
Expected: 全绿。若 `execute：创建平台分组并填入该平台全部关注` 因 `addFollowUserTag` 需要 `DBService.addFollowTag` 而失败，给 `_FakeDBService` 补上 `addFollowTag` / `getFollowTagExist` / `getFollowTagExistByTag` / `getFollowTag` 四个 override（照抄 Task 1 里 `_FakeDBService` 的实现）。

- [ ] **Step 5: 注册服务**

`simple_live_app/lib/main.dart` 第 121 行 `Get.put(FollowService());` 之后加：

```dart
  Get.put(SmartGroupService());
```

并在 import 区加 `import 'package:simple_live_app/services/smart_group_service.dart';`。

- [ ] **Step 6: 全量回归 + 提交**

Run: `cd simple_live_app && flutter test`
Expected: 全绿。

```bash
git add simple_live_app/lib/services/smart_group_service.dart simple_live_app/lib/main.dart simple_live_app/test/smart_group_service_test.dart
git commit -m "feat(follow): SmartGroupService —— 一键按平台分组（幂等、多归属）"
```

---

## Task 9: 确认弹窗 + 顶栏 ⋮ 入口

**Files:**
- Create: `simple_live_app/lib/modules/follow_user/widgets/smart_group_preview_sheet.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_page.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_user_controller.dart`
- Modify: `simple_live_app/lib/modules/follow_user/follow_app_setting/follow_app_settings_page.dart`
- Test: `simple_live_app/test/follow_smart_group_ui_test.dart`

- [ ] **Step 1: 写失败的 widget 测试**

新建 `simple_live_app/test/follow_smart_group_ui_test.dart`：

```dart
// 智能分组入口：顶栏 ⋮ →「按平台智能分组」→ 预览确认 → 真的归组。
//
// ⚠️ `pumpIndexed` 内部会 `Get.reset()`，所以 `SmartGroupService` 必须在它之后注册。
import 'package:flutter_test/flutter_test.dart';
// ⚠️ 本应用跑在 material_ui 上，`PopupMenuButton` 要用它导出的那个，
// 换成 flutter/material 的 `find.byType` 永远匹配不上（同 follow_search_test.dart 的教训）。
import 'package:material_ui/material_ui.dart' show PopupMenuButton;
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/smart_group_preview_sheet.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/smart_group_service.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, String siteId) => FollowUser(
      id: '${siteId}_$name',
      roomId: 'r-$name',
      siteId: siteId,
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = 1;

/// 注册智能分组服务（必须在 pumpIndexed 之后）。
void useSmartGroup() => Get.put(SmartGroupService());

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('⋮ 菜单里有「按平台智能分组」，点开预览并确认后完成归组',
      (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya'), _u('乙', 'huya'), _u('丙', 'douyu')],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    // 打开 ⋮ 弹层
    await tester.tap(find.byType(PopupMenuButton<int>).last);
    await settle(tester);
    expect(find.text('按平台智能分组'), findsOneWidget);

    await tester.tap(find.text('按平台智能分组'));
    await settle(tester);

    expect(find.byType(SmartGroupPreviewSheet), findsOneWidget);
    expect(find.textContaining('虎牙直播'), findsWidgets);
    expect(find.textContaining('斗鱼直播'), findsWidgets);

    await tester.tap(find.text('开始分组'));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_甲'), contains('虎牙直播'));
    expect(svc.userTagNamesOf('huya_乙'), contains('虎牙直播'));
    expect(svc.userTagNamesOf('douyu_丙'), contains('斗鱼直播'));
    expect(find.byType(SmartGroupPreviewSheet), findsNothing);

    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3)); // 排干 toast 计时器
  });

  testWidgets('全部关注都已在对应平台分组里时，只 toast 不弹空表', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya')],
      tags: [FollowUserTag(id: 'a0', tag: '虎牙直播', userId: ['huya_甲'])],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    await Get.find<FollowUserController>().runSmartGrouping();
    await settle(tester);

    expect(find.byType(SmartGroupPreviewSheet), findsNothing);
    expect(find.text('开始分组'), findsNothing);
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('关注设置页入口：复用同一个 runSmartGrouping', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya')],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    // 关注页已经建好控制器，shared 命中现成实例
    await FollowUserController.shared.runSmartGrouping();
    await settle(tester);
    expect(find.text('开始分组'), findsOneWidget);
    await tester.tap(find.text('开始分组'));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_甲'), contains('虎牙直播'));
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd simple_live_app && flutter test test/follow_smart_group_ui_test.dart`
Expected: 编译失败 —— `smart_group_preview_sheet.dart` 不存在。

- [ ] **Step 3: 实现预览确认 sheet**

新建 `simple_live_app/lib/modules/follow_user/widgets/smart_group_preview_sheet.dart`：

```dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/smart_group_service.dart';

/// 一键按平台分组：预览 + 确认。
///
/// 把「将发生什么」摊开在点下去之前 —— 这个动作会一次改几十条归属，
/// 没有预览就等于盲操作。已有同名分组标「复用」，新建标「新建」。
class SmartGroupPreviewSheet extends StatefulWidget {
  /// 确认后的实际执行（由调用方负责刷新关注页）。
  final Future<void> Function() onConfirm;

  const SmartGroupPreviewSheet({
    required this.onConfirm,
    super.key,
  });

  @override
  State<SmartGroupPreviewSheet> createState() => _SmartGroupPreviewSheetState();
}

class _SmartGroupPreviewSheetState extends State<SmartGroupPreviewSheet> {
  late final SmartGroupPreview _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _preview = SmartGroupService.instance.preview();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) Get.back();
    } catch (e) {
      SmartDialog.showToast("分组失败：$e");
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: AppStyle.edgeInsetsV8,
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: AppStyle.radius24,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: AppStyle.edgeInsetsA16.copyWith(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Remix.magic_line),
                      AppStyle.hGap8,
                      Text(
                        '按平台智能分组',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  AppStyle.vGap12,
                  Text(
                    '把 ${_preview.totalFollows} 位关注按平台归组；'
                    '一个主播可以同时属于多个分组，已有分组不会被改动。',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  AppStyle.vGap12,
                  for (final item in _preview.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            item.tagAlreadyExists
                                ? Remix.folder_3_line
                                : Remix.folder_add_line,
                            size: 18,
                            color: item.tagAlreadyExists
                                ? scheme.onSurfaceVariant
                                : scheme.primary,
                          ),
                          AppStyle.hGap8,
                          Text(item.siteName),
                          AppStyle.hGap8,
                          Text(
                            item.tagAlreadyExists ? '复用' : '新建',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${item.userCount} 位',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_preview.skippedUnknownSite > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '另有 ${_preview.skippedUnknownSite} 位所属平台已不在支持列表，跳过。',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA16.copyWith(top: 0, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: Get.back,
                  child: const Text('取消'),
                ),
                AppStyle.hGap8,
                FilledButton(
                  onPressed: _busy ? null : _run,
                  child: const Text('开始分组'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 打开预览确认。无可分组内容时只 toast，不弹一张空表。
Future<void> showSmartGroupPreview(Future<void> Function() onConfirm) async {
  final preview = SmartGroupService.instance.preview();
  if (preview.items.isEmpty) {
    SmartDialog.showToast('没有可分组的关注');
    return;
  }
  // 判「有没有活要干」要看**本次会新增的成员数**，不能只看「有没有新建组」：
  // 平台组可能早就存在但漏了后来新关注的人，那种情况照样要跑。
  if (preview.pendingTotal == 0) {
    SmartDialog.showToast('所有关注都已在对应平台分组里');
    return;
  }
  Get.bottomSheet(
    SmartGroupPreviewSheet(onConfirm: onConfirm),
    backgroundColor: Get.theme.cardColor,
    isScrollControlled: true,
  );
}
```

- [ ] **Step 4: 控制器入口**

`simple_live_app/lib/modules/follow_user/follow_user_controller.dart` 加方法（放 `showSortDialog` 之后）：

```dart
  /// 一键按平台分组。
  ///
  /// 无可分组内容时 `showSmartGroupPreview` 自己只 toast、不弹空表；
  /// 顶栏与关注设置页两个入口都走这里，行为完全一致。
  Future<void> runSmartGrouping() async {
    await showSmartGroupPreview(() async {
      final result = await SmartGroupService.instance.execute();
      // 分组建/改完要走既有链路刷新关注页与分组管理 sheet。
      EventBus.instance.emit(Constant.kUpdateFollow, 0);
      filterData();
      if (result.didNothing) {
        SmartDialog.showToast('所有关注都已在对应平台分组里');
      } else {
        SmartDialog.showToast(
          '已新建 ${result.tagsCreated} 个分组，归组 ${result.membersAdded} 位主播',
        );
      }
    });
  }
```

补 import：`package:simple_live_app/modules/follow_user/widgets/smart_group_preview_sheet.dart`、`package:simple_live_app/services/smart_group_service.dart`。

- [ ] **Step 5: 顶栏 ⋮ 菜单加项**

`simple_live_app/lib/modules/follow_user/follow_user_page.dart` 的 `itemBuilder` 里，在「分组管理」`AppPopupMenuItem(value: 6, ...)` 之后插入：

```dart
                          const AppPopupMenuItem(
                            value: 7,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Remix.magic_line),
                                AppStyle.hGap12,
                                Text("按平台智能分组"),
                              ],
                            ),
                          ),
```

`onSelected` 里加分支：

```dart
                        } else if (value == 7) {
                          controller.runSmartGrouping();
                        } else if (value == 6) {
```

（保持原有 `value == 6 → showFollowTagManagerSheet()` 不变，只是把新分支插在它前面。）

- [ ] **Step 6: 关注设置页加入口**

`simple_live_app/lib/modules/follow_user/follow_app_setting/follow_app_settings_page.dart` 的「分组管理」`SettingsCard` 内，`SettingsAction(title: "分组管理", ...)` 之后加：

```dart
                    AppStyle.divider,
                    SettingsAction(
                      leading: const Icon(Remix.magic_line),
                      title: "按平台智能分组",
                      subtitle: "把所有关注按平台归入同名分组，已有分组不受影响",
                      onTap: () =>
                          FollowUserController.shared.runSmartGrouping(),
                    ),
```

`FollowUserController` 目前没有 `shared` 静态访问器 —— 在 `follow_user_controller.dart` 类内加（照 `FollowTagManagerController.shared` 的写法）：

```dart
  /// 设置页入口复用关注页控制器（它已注册在 Get 里）。
  static FollowUserController get shared =>
      Get.isRegistered<FollowUserController>()
          ? Get.find<FollowUserController>()
          : Get.put(FollowUserController());
```

> 注意：`FollowUserController` 的 `onInit` 会建 `TabController`（需要 `vsync`）并订阅事件流。设置页在关注页之后进过、控制器已保活时 `shared` 直接命中现成实例；若从未进过关注页，`Get.put` 会新建一个 —— 这条路径要实测（Step 8 覆盖）。若新建实例出问题，改为在设置页直接调 `SmartGroupService` + `EventBus.emit(kUpdateFollow)`，不借控制器。

补 import：`package:remixicon/remixicon.dart`（已有）、`package:simple_live_app/modules/follow_user/follow_user_controller.dart`。

- [ ] **Step 7: 跑测试**

Run: `cd simple_live_app && flutter test test/follow_smart_group_ui_test.dart`
Expected: 全绿。第一条若卡在 `find.byType(PopupMenuButton<int>).last`，原因是关注页只有一个 `PopupMenuButton`，`.last` 可用；若顶栏在收起态导致按钮离屏，先 `await tester.dragFrom(const Offset(200, 400), const Offset(0, 300))` 展开顶栏（同 `follow_grouped_view_test.dart` 的做法）。

- [ ] **Step 8: 补设置页入口的测试**

追加到 `follow_smart_group_ui_test.dart`：

```dart
  testWidgets('关注设置页入口：复用同一个 runSmartGrouping', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya')],
      tags: [],
    );
    Get.put(SmartGroupService());
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    // 关注页已经建好控制器，设置页走 shared 命中它
    await FollowUserController.shared.runSmartGrouping();
    await settle(tester);
    expect(find.text('开始分组'), findsOneWidget);
    await tester.tap(find.text('开始分组'));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_甲'), contains('虎牙直播'));
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });
```

Run: `cd simple_live_app && flutter test test/follow_smart_group_ui_test.dart`
Expected: 全绿。

- [ ] **Step 9: 提交**

```bash
git add simple_live_app/lib/modules/follow_user/ simple_live_app/test/follow_smart_group_ui_test.dart
git commit -m "feat(follow): 智能分组入口 —— 顶栏 ⋮ 与关注设置页 + 预览确认"
```

---

## Task 10: 全量回归 & 手工验收

**Files:** 无新增

- [ ] **Step 1: 静态检查**

Run: `cd simple_live_app && flutter analyze`
Expected: `No issues found!`（或与改动前基线一致 —— 先跑一次 `git stash` 前的基线对比，别把历史告警算进本次）。

- [ ] **Step 2: 全量测试**

Run: `cd simple_live_app && flutter test`
Expected: 全绿。

- [ ] **Step 3: 手工验收清单（桌面 + 移动端各跑一遍）**

- [ ] 老数据升级：装 1.8.15 造几个分组（含一个孤儿名字），升级到本次版本，分组与成员完整
- [ ] 「全部」视图：一个主播同时在「我的喜爱」和「虎牙直播」两张卡片里出现
- [ ] 拖头像进别的组 = 加入；原组里仍然在
- [ ] 拖头像回自己已在的组：不高亮、不重复
- [ ] 拖到未分组段 = 移出所有分组
- [ ] 长按 → 设置分组：chip 多选，勾两个都保留
- [ ] 勾选多人 → 移入分组：加入，不移动
- [ ] 分组管理：改名后成员不丢；删组只删这个组，别人的组不受影响
- [ ] 排序方式「自定义分组」：按第一个所属分组排
- [ ] 顶栏 ⋮ → 按平台智能分组：预览列出每个平台 + 复用/新建标记，确认后生成
- [ ] 再点一次智能分组：toast「所有关注都已在对应平台分组里」，不产生重复
- [ ] 关注设置页入口：同样可用
- [ ] 导出 JSON → 清空 → 导入：多归属回来
- [ ] 导入一份**旧版**（只有 `tag` 字段）JSON：归属回来
- [ ] WebDAV 双向同步后分组不丢、不产生幽灵成员
- [ ] 「数据校准」按钮跑一遍：不炸、不把成员表清空

- [ ] **Step 4: 最终提交**

```bash
git status --short
git add -A
git commit -m "chore(follow): 多分组归属 + 一键按平台分组 验收收尾"
```

（若 Step 3 无改动需要提交，跳过本步。）

---

## Self-Review 结论

**1. 需求覆盖**

| 需求 | 实现位置 |
|---|---|
| 智能分组入口 | Task 9（顶栏 ⋮ + 关注设置页） |
| 一键把所有关注按平台分组 | Task 8 `execute()`，范围=全部关注（用户确认） |
| 平台名作分组名 | Task 8 `_orderedSiteIds` + `Sites.allSites[id].name`（用户确认） |
| 执行前列出将创建的分组与人数 | Task 9 `SmartGroupPreviewSheet`（用户确认） |
| 多标签→多分组归属 | Task 1-7（用户要求一起规划） |
| 归属唯一真源 = `tag.userId` | Task 3-7（用户确认） |
| 成员出现在每个所属分组 | Task 3 `groupedView`（用户确认） |

**2. 占位符扫描**：已清除。全文没有 TBD / TODO / 「类似 Task N」/ 「自行补充错误处理」；每个改代码的 Step 都给完整代码与精确文件路径，每个验证 Step 都给命令 + 期望输出。Task 4 Step 4g 的 `setFollowTag` 过渡壳不是占位 —— 它是为了让「Task 4 结束时仍能编译」而刻意保留的真实实现，Task 5 Step 6b 明确删除它。

**3. 类型一致性**：`addUserToTag(FollowUser, String)` / `removeUserFromTag(FollowUser, String)` / `removeAllTagsFromUser(FollowUser)` / `userTagNamesOf(String)` / `userTagsOf(String)` 全程签名一致（参数是**分组名字符串**，不是 `FollowUserTag` —— 控制器传 `targetTag.tag`）；`FollowUserTag.contains(String)` / `addMember(String)` 在 Task 2 定义、Task 5 使用；`DBService.replaceAllFollowTags(Map<String, FollowUserTag>)` 在 Task 1 Step 3 定义，Task 4 / Task 6 的整表重建走它；`SmartGroupPreview` 的 `items` / `totalFollows` / `skippedUnknownSite` / `pendingTotal` / `newTagCount` 与 `SmartGroupPreviewItem` 的 `userCount` / `alreadyMemberCount` / `pendingCount` / `tagAlreadyExists`、`SmartGroupResult` 的 `tagsCreated` / `membersAdded` / `didNothing` 在 Task 8 定义、Task 9 使用，命名一致。

**4. 任务间可编译性**：每个 Task 结束时 `flutter analyze` 必须干净。两处刻意留的过渡：Task 4 的 `FollowService.setFollowTag` 壳（Task 5 Step 6b 删）、Task 4-6 期间保留的 `FollowUser.tag` 字段（Task 7 一次性删并清掉所有残留引用）。

**已知风险（实现时盯住）**

1. `FollowUserController.shared` 在「从未进过关注页」的情况下会新建带 `TabController` 的实例 —— Task 9 Step 6 已给出退路（设置页直调 service）。
2. Task 7 删字段后，旧版本 app 读新记录会把归属看成「全部」；成员表在 `tagBox` 里，重新升级后自动回来。要在 PR 描述写明。
3. `groupedView` 每次重建都遍历所有成员表；几百关注 + 几十分组时要在 profile 里看一眼，必要时把 `membership` 缓存到 service 层（本计划不做）。
4. 智能分组一次写 N 个分组、M 条成员，`addUserToTag` 每条都落一次库。若明显卡顿，改为批量 `putAll`（本计划不做，先保证正确）。
