import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
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

  /// 平台顺序：优先用户在首页排好的 `siteSort`，再按 `Sites.allSites` 声明顺序补全。
  ///
  /// 必须补全而不是直接返回 `siteSort`：它是首页排序的持久化结果，只在
  /// `initSiteSort()` 里补过一次，换设备恢复 / 版本新增站点之后可能不全。
  /// 直接用会把缺掉的已知平台整个漏掉 —— 不但不归组，还会被误算进
  /// `skippedUnknownSite`（那个数字只该是「站点已被移除」的关注）。
  List<String> get _orderedSiteIds {
    final seen = <String>{};
    final ordered = <String>[];
    if (Get.isRegistered<AppSettingsController>()) {
      for (final id in AppSettingsController.instance.siteSort) {
        if (Sites.allSites.containsKey(id) && seen.add(id)) {
          ordered.add(id);
        }
      }
    }
    for (final id in Sites.allSites.keys) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    return ordered;
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
