import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Condition;
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/app/utils/dynamic_filter.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_tag_manager.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
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

  /// 平台分类子开关：增删 [followSiteGroupSites] 里的一个平台 id。
  ///
  /// 列表只是「启用集合」，展示顺序由关注页侧栏按 siteSort 重排，
  /// 所以重新打开一个平台时追加到末尾即可。
  ///
  /// 关掉某个平台时，顺手清掉关注页正挂着的该平台筛选：否则内容还筛着、
  /// 侧栏却没有对应项可点，高亮与内容对不上。
  void setFollowSiteGroup(String siteId, bool enable) {
    final list = appC.followSiteGroupSites.toList();
    if (enable) {
      if (!list.contains(siteId)) {
        list.add(siteId);
      }
    } else {
      list.remove(siteId);
      _clearSiteFilterIfHidden(siteId);
    }
    appC.setFollowSiteGroupSites(list);
  }

  /// 关掉「按平台分类」主开关：清掉所有平台筛选（分组筛选与它无关，保留）。
  void clearSiteFilters() {
    for (final siteId in appC.followSiteGroupSites.toList()) {
      _clearSiteFilterIfHidden(siteId);
    }
  }

  /// 若关注页正筛着 [siteId]，清掉它。
  ///
  /// 关注页可能还没被访问过（控制器没注册）—— 那就无从谈起：筛选态是运行时
  /// 状态，用户下次进关注页本来就不会恢复。
  void _clearSiteFilterIfHidden(String siteId) {
    if (!Get.isRegistered<FollowUserController>()) {
      return;
    }
    final c = Get.find<FollowUserController>();
    final filter = c.activeFilter.value;
    if (filter != null && filter.kind == FollowSidebarKind.site && filter.id == siteId) {
      c.activeFilter.value = null;
    }
  }

  /// 平台分类子开关的展示顺序：siteSort 在前、`Sites.allSites` 声明序补全
  /// （与关注页侧栏同口径，防 siteSort 缺项时平台整个消失）。
  List<String> get orderedFollowSiteIds => Sites.orderedIds(appC.siteSort);

  /// 「关注样式」二选一（紧凑行 / 卡片网格）。
  ///
  /// 不走 `FollowUserController.showFollowStyleDialog`：那个控制器 onInit 要
  /// `vsync` 建 `TabController`，用户从未进过关注页时只能临时 `Get.put` 一份
  /// 空壳实例（同文件顶部「按平台智能分组」入口的既有理由）。这里只借它的
  /// 选项表，实际写 `AppSettingsController`。
  Future<void> showFollowStyleDialog() async {
    var res = await Utils.showMapOptionDialog(
      title: "关注样式切换",
      FollowUserController.followStyleMap,
      appC.followStyleNotGrid.value,
    );
    if (res != null) {
      appC.setFollowStyleNotGrid(res);
    }
  }

  /// 打开「按平台分类」时静默清理名称与平台显示名相同的旧分组。
  ///
  /// 这些分组多半是已下线的「按平台智能分组」留下的：平台标签是动态筛选，
  /// 同名分组只会让第二栏出现两套入口。删除只移除分组标签，**不取消任何
  /// 关注**（关注本体在 followList，分组只是 userId 成员表上的一层标签）。
  Future<void> cleanupPlatformNamedTags() async {
    final siteNames = <String>{};
    for (final id in appC.followSiteGroupSites) {
      final site = Sites.allSites[id];
      if (site != null) {
        siteNames.add(site.name);
      }
    }
    if (siteNames.isEmpty) {
      return;
    }
    final matched = FollowService.instance.followTagList.where((t) => siteNames.contains(t.tag)).toList();
    if (matched.isEmpty) {
      return;
    }
    for (final t in matched) {
      await FollowService.instance.removeFollowUserTag(t);
      Log.i('清理同名平台分组：${t.tag}');
    }
    updateTagList();
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    // toast 只是告知：SmartDialog 在没有可用 context 的环境（如单测）里会抛，
    // 且是**异步**抛的 —— 同步 try/catch 抓不到，会变成未 await 的 Future 错误
    // 把测试炸红。不能让它把「已经清完脏数据」这件事翻案。
    try {
      await Future(() => SmartDialog.showToast("已清理 ${matched.length} 个同名平台分组"));
    } catch (_) {
      Log.i('清理同名平台分组：toast 无可用的 context，跳过');
    }
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
      // 归属清理由 `FollowService.removeFollowUser` 统一负责
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
    final followedIds = followList.map((follow) => follow.id).toSet(); // set性能略优
    final followedHistories = histories.where((history) => followedIds.contains(history.id)).toList();
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
    final df = dynamicFilter(followedHistories, conditions, takeLast: takeLast.value);
    final uidsToClean = df.map((history) => history.id).toSet();

    final autoCleanPool = followList.where((follow) => uidsToClean.contains(follow.id)).toList();
    return autoCleanPool;
  }
}
