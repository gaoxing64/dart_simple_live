import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/url_parse.dart';
import 'package:simple_live_app/models/db/follow_user.dart' show FollowUser;
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/history_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class FollowInfoController extends BasePageController<FollowUser> {
  final Rxn<FollowUser> followUser = Rxn<FollowUser>();

  // 所属分组候选：用户自定义分组（多选 chips）
  final RxList<FollowUserTag> tagOptions = <FollowUserTag>[].obs;

  // 当前关注勾选着的分组名（多归属：可以同时属于多个分组）
  final RxSet<String> checkedTags = <String>{}.obs;

  // 平台迁移预留：列出除当前平台外的其余平台
  final RxList<Site> migrationSites = <Site>[].obs;

  // 平台迁移：输入链接
  final TextEditingController migrationUrlController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    // 读取传入的 FollowUser
    final args = Get.arguments;
    if (args is FollowUser) {
      followUser.value = args;
    } else if (args is Map && args['follow'] is FollowUser) {
      followUser.value = args['follow'] as FollowUser;
    }

    _initTagOptions();
    _initMigrationSites();
  }

  void _initTagOptions() {
    tagOptions.assignAll(FollowService.instance.followTagList);

    // 勾选态直接取归属真源（成员表 `FollowUserTag.userId`），
    // `FollowUser.tag` 只是主分组缓存，不能拿来当勾选依据。
    final current = followUser.value;
    checkedTags.assignAll(
      current == null ? const <String>[] : FollowService.instance.userTagNamesOf(current.id),
    );
  }

  void _initMigrationSites() {
    final current = followUser.value;
    if (current == null) {
      migrationSites.clear();
      return;
    }
    final List<Site> all = Sites.supportSites;
    migrationSites.assignAll(
      all.where((s) => s.id != current.siteId).toList(),
    );
  }

  /// 勾选/取消一个分组：多归属下这是「加入/移出该分组」，不动其他分组。
  /// 批量结束后只重排一次（`addUserToTag` 内部不排，见其注释）。
  Future<void> toggleTag(String name) async {
    final current = followUser.value;
    if (current == null) return;
    if (checkedTags.contains(name)) {
      checkedTags.remove(name);
      await FollowService.instance.removeUserFromTag(current, name);
    } else {
      checkedTags.add(name);
      await FollowService.instance.addUserToTag(current, name);
    }
    FollowService.instance.liveListSort();
    followUser.refresh();
  }

  Future<void> updateRemark(String newRemark) async {
    final current = followUser.value;
    if (current == null) return;
    current.remark = newRemark;
    await FollowService.instance.addFollow(current);
    followUser.refresh();
  }

  Future<void> pasteFromClipboard() async {
    final content = await Utils.getClipboard();
    if (content != null) {
      migrationUrlController.text = content;
    }
  }

  Future<void> parseAndMigrate() async {
    final url = migrationUrlController.text.trim();
    if (url.isEmpty) {
      SmartDialog.showToast('链接不能为空');
      return;
    }
    final result = await UrlParse.instance.parse(url);
    if (result.isEmpty || result.first == '') {
      SmartDialog.showToast('无法解析此链接');
      return;
    }
    final String newRoomId = result.first as String;
    final Site newSite = result[1] as Site;

    final current = followUser.value;
    if (current == null) return;

    // 防呆
    bool contain = FollowService.instance.getFollowExist("${newSite.id}_$newRoomId");
    if (contain == true) {
      SmartDialog.showToast('目标主播已关注，无需迁移');
      return;
    }

    final confirmed = await Get.dialog<bool>(AlertDialog(
      title: const Text('确认迁移'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('从：${Sites.allSites[current.siteId]?.name}  房间号：${current.roomId}'),
          const SizedBox(height: 8),
          Text('到：${newSite.name}  房间号：$newRoomId'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: const Text('确定'),
        ),
      ],
    ));

    if (confirmed != true) return;

    await _migrateTo(newSite, newRoomId);
    SmartDialog.showToast('迁移成功');
  }

  @override
  Future<void> refreshData() async {
    pageLoadding.value = true;
    var site = Sites.allSites[followUser.value?.siteId]!;
    await _migrateTo(site, followUser.value!.roomId);
    pageLoadding.value = false;
    SmartDialog.showToast('已刷新用户信息');
  }

  Future<void> _migrateTo(Site targetSite, String targetRoomId) async {
    final current = followUser.value;
    if (current == null) return;
    // 获取目标直播间详细信息 用于更新主播名和头像
    LiveRoomDetail detail = await targetSite.liveSite.getRoomDetail(roomId: targetRoomId);
    // 复制并更新关键信息
    final FollowUser newFollow = FollowUser(
        id: '${targetSite.id}_$targetRoomId',
        roomId: targetRoomId,
        siteId: targetSite.id,
        userName: detail.userName,
        face: detail.userAvatar,
        addTime: current.addTime,
        watchDuration: current.watchDuration,
        watchDurationSec: current.watchDurationSec,
        tag: current.tag,
        remark: current.remark,
        romanName: current.romanName)
      ..liveStatus.value = current.liveStatus.value;

    // 替换关注
    // 归属随迁移带走：多归属真源在 `FollowUserTag.userId`，而 `removeFollowUser`
    // 会把旧 id 从所有成员表里清掉 —— 所以旧归属必须在删之前记下来，
    // 换绑后再把新关注加回去，否则主播会掉进「未分组」。
    final tagNames = FollowService.instance.userTagNamesOf(current.id);
    await FollowService.instance.removeFollowUser(current.id);
    await FollowService.instance.addFollow(newFollow);
    for (final name in tagNames) {
      await FollowService.instance.addUserToTag(newFollow, name);
    }

    // 更新关注同时 更新历史记录数据
    History? oldHistory = HistoryService.instance.getHistory(current.id);
    // null直接生成
    if (oldHistory != null) {
      await HistoryService.instance.delHistory(oldHistory.id);
    }
    final History newHistory = History(
      id: '${targetSite.id}_$targetRoomId',
      roomId: targetRoomId,
      siteId: targetSite.id,
      userName: detail.userName,
      face: detail.userAvatar,
      watchDuration: newFollow.watchDuration,
      updateTime: DateTime.now(),
    );
    await HistoryService.instance.addOrUpdateHistory(newHistory);

    // 刷新本地数据并更新UI
    await FollowService.instance.loadData(updateStatus: false);
    followUser.value = newFollow;
    _initMigrationSites();
  }
}
