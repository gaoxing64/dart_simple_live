import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Condition;
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/app/utils/dynamic_filter.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_tag_manager.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/history_service.dart';

/// 标签管理的逻辑（列表、增删改、排序、bottom sheet）在基类
/// [FollowTagManagerController]，与关注页顶栏入口共享；这里只留关注设置本身。
class FollowAppSettingsController extends FollowTagManagerController {
  final appC = Get.find<AppSettingsController>();

  // 用户自定义条件
  Rx<int> takeLast = 15.obs;
  Rx<int> minutes = 30.obs;

  // 修改用户自定义关注设置
  void setFollowSetting(bool hideOfflineFollow) {
    appC.setHideOfflineFollow(hideOfflineFollow);
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
  }

  // 修改隐藏快速取关按钮
  void setRemoveFollowButton(bool hideFollowCardRemoveButton) {
    appC.setHideRemoveFollowButton(hideFollowCardRemoveButton);
  }

  Future<void> followDataCheck() async {
    await FollowService.instance.followUserAllDataCheck();
    // 通知关注页刷新 tagList/分组视图（与 setFollowSetting 同一条链路）
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    SmartDialog.showToast("数据校准完成");
  }

  // 关注清理功能
  Future<void> cleanFollow(List<FollowUser> cleanPool) async {
    if (cleanPool.isEmpty) {
      SmartDialog.showToast("没有需要清理的用户");
      return;
    }
    SmartDialog.showLoading(msg: "清理中");
    for (var follow in cleanPool) {
      // 取消关注同时删除标签内的 userId
      if (follow.tag != "全部") {
        var tag = userTagList.firstWhere((tag) => tag.tag == follow.tag);
        tag.userId.remove(follow.id);
        await updateTag(tag);
      }
      await FollowService.instance.removeFollowUser(follow.id);
    }
    SmartDialog.dismiss();
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    SmartDialog.showToast("清理完成");
  }

  List<FollowUser> buildAutoCleanPool() {
    var followList = FollowService.instance.followList;
    var histories = HistoryService.instance.getHistories();
    if (histories.isEmpty || followList.isEmpty) return [];
    // 筛选出历史记录里已关注的
    final followedIds =
        followList.map((follow) => follow.id).toSet(); // set性能略优
    final followedHistories =
        histories.where((history) => followedIds.contains(history.id)).toList();
    if (followedHistories.isEmpty) return [];

    List<Condition> conditions = [
      // Condition('siteId', FilterOperator.equals, Constant.kBiliBili),
      Condition(
        'watchDuration',
        FilterOperator.lessThan,
        Duration(minutes: minutes.value),
        comparableValueProvider: (watchDuration) {
          if (watchDuration is String) {
            return watchDuration.toDuration();
          }
          return null;
        },
      ),
    ];
    // 根据动态条件筛选出需要清理的 关注id
    final df =
        dynamicFilter(followedHistories, conditions, takeLast: takeLast.value);
    final uidsToClean = df.map((history) => history.id).toSet();

    final autoCleanPool =
        followList.where((follow) => uidsToClean.contains(follow.id)).toList();
    return autoCleanPool;
  }
}
