import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:fractional_indexing_dart/fractional_indexing_dart.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pinyin/pinyin.dart';
import 'package:pool/pool.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/app/utils/dynamic_sort.dart';
import 'package:simple_live_app/app/utils/extensions/string_normalizer.dart';
import 'package:simple_live_app/models/db/follow_snapshot.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:synchronized/synchronized.dart';

class FollowService extends GetxService {
  StreamSubscription<dynamic>? subscription;

  static FollowService get instance => Get.find<FollowService>();

  final StreamController _updatedListController = StreamController.broadcast();

  Stream get updatedListStream => _updatedListController.stream;

  /// 关注用户列表
  RxList<FollowUser> followList = RxList<FollowUser>();

  /// 休眠用户列表
  RxList<FollowUser> dormantFollowList = RxList<FollowUser>();

  /// 直播中的用户列表
  RxList<FollowUser> liveList = RxList<FollowUser>();

  /// 未直播的用户列表
  RxList<FollowUser> notLiveList = RxList<FollowUser>();

  /// 用户自定义的tag
  RxList<FollowUserTag> followTagList = RxList<FollowUserTag>();

  /// 线程安全
  final _lock = Lock();

  /// 已经更新状态的数量
  var updatedCount = 0;

  /// 是否正在更新
  var updating = false.obs;

  Timer? updateTimer;

  int _totalToUpdate = 0;

  int _refreshCycle = 0;

  bool _snap = false;

  @override
  Future<void> onInit() async {
    subscription = EventBus.instance.listen(Constant.kUpdateFollow, (data) {
      if (data is History) {
        updateFollowHistory(data);
      } else {
        loadData(updateStatus: false);
      }
    });
    await initFollowList();
    initTimer();
    cleanupTombstones();
    super.onInit();
  }

  Future<void> updateTagName(FollowUserTag followUserTag, String newTagName) async {
    // 成员靠 id 关联，改名只是换个显示名，不需要碰任何关注记录。
    await updateFollowUserTag(followUserTag.copyWith(tag: newTagName));
  }

  Future<void> updateFollowUserTag(FollowUserTag tag) async {
    if (tag.tag == '全部') {
      return;
    }
    await DBService.instance.updateFollowTag(tag);
    // 查找并修改
    var index = followTagList.indexWhere((oTag) => oTag.id == tag.id);
    followTagList[index] = tag;
  }

  Future<void> addFollowUserTag(String tag) async {
    // 判断待添加tag是否已存在，存在则return
    if (followTagList.any((item) => item.tag == tag)) {
      SmartDialog.showToast("分组名重复，修改失败");
      return;
    }
    FollowUserTag item = await DBService.instance.addFollowTag(tag);
    followTagList.add(item);
  }

  Future removeFollowUserTag(FollowUserTag tag) async {
    followTagList.remove(tag);
    await DBService.instance.deleteFollowTag(tag.id);
  }

  // 获取用户自定义标签列表
  void getAllTagList() {
    var list = DBService.instance.getFollowTagList();
    followTagList.assignAll(list);
  }

  /// 某关注所属的分组名（按 `followTagList` 顺序）。
  ///
  /// 归属唯一真源是 `FollowUserTag.userId`（多分组归属），本方法是它的读取口。
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
  /// 但一次批量归组（勾选移入分组）要动 N 个人，每条都重排就是
  /// O(N² log N)。排序交给调用方在一批操作结束后做一次（见控制器）。
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
  }

  /// 把关注移出某个分组。同样不在此重排，理由见 [addUserToTag]。
  Future<void> removeUserFromTag(FollowUser user, String tagName) async {
    if (tagName == '全部') {
      return removeAllTagsFromUser(user);
    }
    final tag = followTagList.firstWhereOrNull((t) => t.tag == tagName);
    if (tag == null || !tag.userId.remove(user.id)) {
      return;
    }
    await updateFollowUserTag(tag);
  }

  /// 清空某关注的全部归属（回到「未分组」）。只写真的变了的分组。
  Future<void> removeAllTagsFromUser(FollowUser user) async {
    for (final tag in followTagList) {
      if (tag.userId.remove(user.id)) {
        await updateFollowUserTag(tag);
      }
    }
  }

  void updateFollowTagOrder(FollowUserTag oldTag, FollowUserTag newTag) {
    // 改变先落库再读库最后更新ui，这中间需要同步等待，数据流程糟糕，开发心智负担重
    // 内存优先：实现外表操作结束后异步落库，多写代码 但逻辑较为简单
    followTagList.removeWhere((x) => x.id == oldTag.id);
    followTagList.add(newTag);
    // hive 以 id排序，额外进行排序操作
    followTagList.sort((tagA, tagB) => tagA.id.compareTo(tagB.id));

    DBService.instance.deleteFollowTag(oldTag.id);
    DBService.instance.updateFollowTag(newTag);
  }

  /// 按显示顺序移动一个标签（关注页拖拽调序与分组管理 sheet 共用）。
  ///
  /// 顺序由 fractional id 承载，重排 = 换 id 重新落库，**移动过的标签 id 会变**
  /// （按 id 存的折叠态等会随之重置）。索引以 [followTagList]（仅自定义标签）为准。
  ///
  /// ⚠️ `onReorderItem` 回调给出的 `newIndex` **已经是删除旧位置后的插入索引**
  /// （框架内部做过校正），这里不能再减一次。
  ///
  /// ⚠️ 相邻 key 必须在「item 已移出列表」的状态下取：先插回再取
  /// `[insertAt]` 会取到 item 自己 —— 向下拖会抛 `a >= b` 异常，
  /// 向上拖会算出撞车 id 并在落库时覆盖掉另一个分组
  /// （2026-09-22 实测丢组，回归见 test/follow_tag_reorder_test.dart）。
  void reorderFollowTag(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) {
      return;
    }
    final item = followTagList.removeAt(oldIndex);
    final insertAt = newIndex.clamp(0, followTagList.length);
    final newKey = FractionalIndexing.generateKeyBetween(insertAt > 0 ? followTagList[insertAt - 1].id : null,
        insertAt < followTagList.length ? followTagList[insertAt].id : null);
    updateFollowTagOrder(item, item.copyWith(id: newKey));
  }

  // 添加关注
  Future<void> addFollow(FollowUser follow) async {
    // follow变动过程中romanName统一变化
    String romanName = "";
    if (follow.remark != null && follow.remark!.isNotEmpty) {
      romanName = PinyinHelper.getShortPinyin(follow.romanName!);
    } else {
      romanName = PinyinHelper.getShortPinyin(follow.userName);
    }
    follow.romanName = romanName.normalize();
    // 重新关注时清除墓碑标记
    follow.deleted = false;
    follow.updateTime = 0;

    // 归属由 FollowUserTag.userId 单向持有，这里不反向同步（历史双写正是错乱之源）。

    // live_room_controller.add 已同步history
    // db.add 其实是update会直接更新数据，所以外表也应该实现此功能：有则更，无则添加
    int index = followList.indexWhere((f) => f.id == follow.id);
    if (index != -1) {
      followList[index] = follow;
    } else {
      followList.add(follow);
    }
    liveListSort(); // 每次数据操作后外表进行业务刷新
    await DBService.instance.addFollow(follow);
  }

  // 取消关注（墓碑机制）
  Future<void> removeFollowUser(String id) async {
    // 存储在线状态，数据修改应followList外表和followBox内表保持同步
    // 后续业务逻辑中，将规避直接业务在数据库上操作，落库操作只执行一次
    // 从而规避业务逻辑直读数据库导致的数据混乱
    FollowUser follow = followList.firstWhere((x) => x.id == id);
    followList.removeWhere((x) => x.id == id);
    // 取消关注 = 从所有分组的成员表里消失（只写真的少了人的那个组）
    for (final tag in followTagList) {
      if (tag.userId.remove(id)) {
        await updateFollowUserTag(tag);
      }
    }
    liveListSort();
    // 设置墓碑标记，而非直接删除记录
    follow.deleted = true;
    follow.updateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await DBService.instance.addFollow(follow);
  }

  // 判断关注是否存在
  bool getFollowExist(String id) {
    return DBService.instance.getFollowExist(id);
  }

  // 更新关注的历史记录
  Future<void> updateFollowHistory(History history) async {
    var follow = followList.where((follow) => follow.id == history.id).firstOrNull;
    if (follow == null) {
      return;
    } else {
      // sync watch-part between history and follow
      follow.syncDuration = history.syncDuration;
      follow.watchDuration = history.watchDuration;
      follow.watchDurationSec = history.watchDuration!.toDuration().inSeconds;
      await addFollow(follow);
    }
    Log.i("已更新当前播放的观看时长：${follow.watchDurationSec}");
  }

  void initTimer() {
    if (AppSettingsController.instance.autoUpdateFollowEnable.value) {
      updateTimer?.cancel();
      _refreshCycle = 0;
      updateTimer = Timer.periodic(
        Duration(minutes: AppSettingsController.instance.autoUpdateFollowDuration.value),
        (timer) {
          CoreLog.i("Update Follow Timer - Cycle: $_refreshCycle");
          loadData(updateStatus: true, cycle: _refreshCycle);
          _refreshCycle = (_refreshCycle + 1) % 2; // 2-cycle rotation
        },
      );
    } else {
      updateTimer?.cancel();
    }
  }

  // 此操作只在初始化时调用一次
  Future<void> initFollowList() async {
    List<FollowUser> list = DBService.instance.getFollowList();

    if (list.isEmpty) {
      updating.value = false;
      followList.assignAll(list);
      liveList.clear();
      notLiveList.clear();
      _updatedListController.add(0);
      return;
    }
    var followSnapshot = AppSettingsController.instance.followSnapshot;
    bool followSnapshotEnable = AppSettingsController.instance.followSnapshotEnable.value;
    // whether to recover snapshot depends on expireAt
    if (followSnapshot != null &&
        followSnapshot.expireAt > DateTime.now().microsecondsSinceEpoch &&
        followSnapshotEnable) {
      final snapshotMap = {for (var item in followSnapshot.followSnapshotItems) item.id: item};
      for (var item in list) {
        final resItem = snapshotMap[item.id];
        if (resItem != null) {
          item.applySnapshot(resItem);
        }
      }
      _snap = true;
      Log.i("FollowService: follow-snapshot has recovered, expireAt: ${followSnapshot.expireAt}");
    }
    followList.assignAll(list);
    if (_snap) {
      liveListSort();
    }
    _buildDormantList();
    getAllTagList();
  }

  /// 构建休眠用户列表
  void _buildDormantList() {
    final threshold = AppSettingsController.instance.dormancyThreshold.value;
    if (threshold <= 0) {
      dormantFollowList.clear();
      return;
    }
    final cutoff = DateTime.now().subtract(Duration(days: threshold)).millisecondsSinceEpoch ~/ 1000;
    dormantFollowList.assignAll(
      followList.where((u) => u.lastWatchTime! > 0 && u.lastWatchTime! < cutoff),
    );
  }

  /// 解冻：用户进入直播间时调用
  void resumeUser(String userId) {
    // 更新 lastWatchTime 如果已关注
    var follow = followList.firstWhereOrNull((u) => u.id == userId);
    if (follow != null) {
      follow.lastWatchTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      DBService.instance.addFollow(follow);
      // 从休眠列表移除
      dormantFollowList.removeWhere((u) => u.id == userId);
    }
  }

  Future<void> loadData({bool updateStatus = true, int? cycle}) async {
    // snapshot 恢复跳过第一次状态更新
    if (_snap) {
      _snap = false;
      return;
    }
    if (updateStatus) {
      startUpdateStatus(cycle: cycle);
    } else {
      _updatedListController.add(0);
    }
  }

  void multiRoundPriority() {
    final historyList = DBService.instance.getHistories();
    final Map<String, int> historyRankMap = {for (var i = 0; i < historyList.length; i++) historyList[i].id: i};
    final int maxRank = historyList.isNotEmpty ? historyList.length : 1;

    Duration maxDuration = const Duration();
    for (var user in followList) {
      final duration = user.watchDuration!.toDuration();
      if (duration > maxDuration) {
        maxDuration = duration;
      }
    }
    final double maxDurationInSeconds = maxDuration.inSeconds > 0 ? maxDuration.inSeconds.toDouble() : 1.0;

    // 休眠用户 ID 集合
    final dormantIds = dormantFollowList.map((u) => u.id).toSet();

    // 简单线性加权组合算法，目前认定观看时长和最近观看时间权重一致
    // 如果用户历史行为序列非常长：可替换为时间衰减 + 观看时长加权
    followList.sort((a, b) {
      // 静态权重
      const double wDuration = 0.5;
      const double wRecency = 0.5;
      // 在线降权，离线增权
      const double wOnline = 0.3;
      const double wOffline = 1 - wOnline;

      // 动态权重
      double normDurationA = a.watchDurationSec.toDouble() / maxDurationInSeconds;
      int rankA = historyRankMap[a.id] ?? maxRank;
      double normRecencyA = (maxRank - rankA).toDouble() / maxRank;
      double wDormantA = dormantIds.contains(a.id) ? 0.0 : 1.0;
      double scoreA = ((wDuration * normDurationA) + (wRecency * normRecencyA)) *
          (a.liveStatus.value == 2 ? wOnline : wOffline) *
          wDormantA;

      double normDurationB = b.watchDurationSec.toDouble() / maxDurationInSeconds;
      int rankB = historyRankMap[b.id] ?? maxRank;
      double normRecencyB = (maxRank - rankB).toDouble() / maxRank;
      double wDormantB = dormantIds.contains(b.id) ? 0.0 : 1.0;
      double scoreB = ((wDuration * normDurationB) + (wRecency * normRecencyB)) *
          (b.liveStatus.value == 2 ? wOnline : wOffline) *
          wDormantB;

      return scoreB.compareTo(scoreA);
    });
  }

  void startUpdateStatus({int? cycle}) async {
    List<FollowUser> usersToUpdate;
    final totalUsers = followList.length;
    final douyinCount = followList.where((x) => x.siteId == 'douyin').length;

    //tips: 噪音用户画像（高风险平台：90%; 多次手刷; 单高关注数>50; 频繁切直播间; 不登录反复高危操作; 移动宽带用户; 反复关注取消; 多ip切换; 特殊地区风控; 多端在线请求; 黑号）
    if (cycle != null && (totalUsers > 100 || douyinCount > 50)) {
      // 简单28
      final topNCount = (totalUsers * 0.2).round(); // Top 20%
      final bottomNCount = (totalUsers * 0.2).round(); // Bottom 20%
      final middlePartEndIndex = totalUsers - bottomNCount;
      multiRoundPriority();
      final topNUsers = followList.sublist(0, topNCount);
      final middleUsers = followList.sublist(topNCount, middlePartEndIndex);
      if (cycle == 0) {
        usersToUpdate = topNUsers;
        CoreLog.i("Update Follow: Cycle 0, updating top ${usersToUpdate.length}/$totalUsers users.");
      } else {
        usersToUpdate = [...topNUsers, ...middleUsers];
        CoreLog.i("Update Follow: Cycle 1, updating top+middle ${usersToUpdate.length}/$totalUsers users.");
      }
    } else {
      usersToUpdate = List.from(followList);
      if (cycle != null) {
        CoreLog.i("Update Follow: List <= 100, updating all ${usersToUpdate.length} users.");
      }
    }
    _totalToUpdate = usersToUpdate.length;
    updatedCount = 0;
    updating.value = true;

    if (_totalToUpdate == 0) {
      updating.value = false;
      filterData();
      return;
    }

    var threadCount = AppSettingsController.instance.updateFollowThreadCount.value;

    var pool = Pool(threadCount);
    var tasks = <Future>[];

    for (var user in usersToUpdate) {
      tasks.add(pool.withResource(() => updateLiveInformation(user)));
    }
    await Future.wait(tasks);
    await pool.close();

    // 增量检查：自动解冻 lastWatchTime >= cutoff 的用户
    final threshold = AppSettingsController.instance.dormancyThreshold.value;
    if (threshold > 0 && dormantFollowList.isNotEmpty) {
      final cutoff = DateTime.now().subtract(Duration(days: threshold)).millisecondsSinceEpoch ~/ 1000;
      dormantFollowList.removeWhere((u) => u.lastWatchTime != null && u.lastWatchTime! >= cutoff);
    }

    // frequency of snapshot-saving and expireAt calculation depend on user-setting: auto-update
    final minutes = AppSettingsController.instance.autoUpdateFollowDuration.value;
    final expireAt = DateTime.now().add(Duration(minutes: minutes)).microsecondsSinceEpoch;
    AppSettingsController.instance.setFollowSnapshot(
      FollowSnapshot(
        expireAt: expireAt,
        followSnapshotItems: followList.map((e) => e.toSnapshot()).toList(),
      ),
    );
    Log.i("FollowService: follow-snapshot has saved, time: ${DateTime.now()}");
  }

  /// 增量重排通知的节流间隔。
  ///
  /// 刷新期间每检测完一条都会重排（见 [reflowFollowItem]），但 UI 不必跟着
  /// 重建同样多次；把这一小段时间内完成的条目合并成一批、只发一次
  /// 「列表已更新」事件。**这里不排序**，整表排序仍只在 [filterData] 里做一次。
  static const Duration _kIncrementalNotifyInterval = Duration(milliseconds: 150);

  Timer? _incrementalNotifyTimer;
  bool _incrementalNotifyPending = false;

  Future updateLiveInformation(FollowUser item) async {
    final oldStatus = item.liveStatus.value;
    try {
      var site = Sites.allSites[item.siteId]!;
      LiveRoomDetail detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
      item.liveStatus.value = detail.status ? 2 : 1;
      item.cover.value = detail.status ? detail.cover : "";
      item.title.value = detail.title;
      // 未开播时接口仍会回上一次直播的人气值，直接展示就是「未开播卡片顶着 160.9万」
      // 那种假数据，这里和 cover 一样按状态清掉。
      item.online.value = detail.status ? detail.online : 0;
      if (oldStatus != item.liveStatus.value) {
        // 状态变了就**立刻**把它挪到该在的位置：直播的一检出就往上浮，
        // 而不是等整轮刷新结束再统一跳一次。
        reflowFollowItem(item);
        _scheduleIncrementalNotify();
      }
    } catch (e) {
      Log.logPrint(e);
    } finally {
      await _lock.synchronized(() {
        updatedCount++;
      });
      if (updatedCount >= _totalToUpdate) {
        filterData();
        updating.value = false;
      }
    }
  }

  /// 增量重排：把 [item] 挪到当前排序下它该在的位置（**不是排序**）。
  ///
  /// 刷新期间只有 [FollowUser.liveStatus] 在变，其余排序键（观看时长 /
  /// 添加时间 / 平台 / 用户名 / 分组归属）都是静态的，且列表在上一轮
  /// [liveListSort] 后已有序 —— 所以只需一次线性扫描定位插入点、一次移动。
  /// 整表排序仍然只在 [filterData] 结束时执行一次，性能口径不变。
  void reflowFollowItem(FollowUser item) {
    final index = followList.indexOf(item);
    if (index < 0) {
      return;
    }
    final conditions = _followSortConditions(
      AppSettingsController.instance.followSortMethod.value,
    );
    followList.removeAt(index);
    var insertAt = followList.length;
    for (var i = 0; i < followList.length; i++) {
      if (_compareFollow(item, followList[i], conditions) < 0) {
        insertAt = i;
        break;
      }
    }
    followList.insert(insertAt, item);
  }

  /// 与 [listSortByMethod] 同一套比较规则：直播优先，再按用户选的排序方式。
  /// 增量重排据此定位插入点，两条路必须同口径，否则结束时还会再跳一次。
  ///
  /// [conditions] 由调用方在循环外算好传入：逐次比较都重建条件对象太浪费。
  int _compareFollow(
    FollowUser a,
    FollowUser b,
    List<SortCondition<FollowUser>> conditions,
  ) {
    final liveCmp = a.liveStatus.value.compareTo(b.liveStatus.value);
    if (liveCmp != 0) {
      return -liveCmp;
    }
    for (final cond in conditions) {
      final cmp = cond.valueGetter(a).compareTo(cond.valueGetter(b));
      if (cmp != 0) {
        return cond.ascending ? cmp : -cmp;
      }
    }
    return 0;
  }

  /// 增量重排的 UI 通知节流：一批最多发一次。
  void _scheduleIncrementalNotify() {
    _incrementalNotifyPending = true;
    if (_incrementalNotifyTimer?.isActive ?? false) {
      return;
    }
    _incrementalNotifyTimer = Timer(_kIncrementalNotifyInterval, () {
      if (!_incrementalNotifyPending) {
        return;
      }
      _incrementalNotifyPending = false;
      _updatedListController.add(0);
    });
  }

  void filterData() {
    // 收尾的那次完整刷新会覆盖增量结果，挂着的节流通知没有意义
    _incrementalNotifyTimer?.cancel();
    _incrementalNotifyPending = false;
    liveListSort();
    _updatedListController.add(0);
  }

  void liveListSort() {
    listSortByMethod(followList, AppSettingsController.instance.followSortMethod.value);
    liveList.assignAll(followList.where((x) => x.liveStatus.value == 2));
    notLiveList.assignAll(followList.where((x) => x.liveStatus.value == 1));
  }

  void listSortByMethod(List<FollowUser> list, SortMethod sortMethod) {
    var liveCondition = SortCondition<FollowUser>(
      valueGetter: (item) => item.liveStatus.value, // Rx<int>
      ascending: false,
    );
    list.dynamicSort([liveCondition, ..._followSortConditions(sortMethod)]);
  }

  /// 用户所选排序方式对应的字段条件（不含「直播优先」那一档）。
  List<SortCondition<FollowUser>> _followSortConditions(SortMethod sortMethod) {
    var watchDurationCondition = SortCondition<FollowUser>(
      valueGetter: (item) => item.watchDurationSec,
      ascending: false,
    );
    var siteIdCondition = SortCondition<FollowUser>(
      valueGetter: (item) {
        final order = AppSettingsController.instance.siteSort;
        // 返回索引作为 Comparable
        return order.indexOf(item.siteId);
      },
    );
    var recentlyCondition = SortCondition<FollowUser>(
      valueGetter: (item) => item.addTime,
      ascending: false,
    );
    var userNameASCCondition = SortCondition<FollowUser>(
      valueGetter: (item) => item.romanName ?? "",
      ascending: true,
    );
    var userNameDESCCondition = SortCondition<FollowUser>(
      valueGetter: (item) => item.romanName ?? "",
      ascending: false,
    );
    var tagCondition = SortCondition<FollowUser>(
      valueGetter: (item) {
        final names = userTagNamesOf(item.id);
        if (names.isEmpty) {
          return followTagList.length; // 未分组排最后
        }
        return followTagList.indexWhere((t) => t.tag == names.first);
      },
    );
    switch (sortMethod) {
      case SortMethod.watchDuration:
        return [watchDurationCondition];
      case SortMethod.siteId:
        return [siteIdCondition, watchDurationCondition];
      case SortMethod.recently:
        return [recentlyCondition];
      case SortMethod.userNameASC:
        return [userNameASCCondition];
      case SortMethod.userNameDESC:
        return [userNameDESCCondition];
      case SortMethod.tag:
        return [tagCondition, watchDurationCondition];
    }
  }

  void exportFile() async {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }

    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }

      var dir = "";
      if (Platform.isIOS) {
        dir = (await getApplicationDocumentsDirectory()).path;
      } else {
        dir = await FilePicker.getDirectoryPath() ?? "";
      }

      if (dir.isEmpty) {
        return;
      }
      var jsonFile = File('$dir/SimpleLive_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json');
      var jsonText = generateJson();
      await jsonFile.writeAsString(jsonText);
      SmartDialog.showToast("已导出关注列表");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导出失败：$e");
    }
  }

  void inputFile() async {
    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }
      var file = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) {
        return;
      }
      var jsonFile = File(file.files.single.path!);
      await inputJson(await jsonFile.readAsString());
      SmartDialog.showToast("导入成功");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导入失败:$e");
    } finally {
      loadData();
    }
  }

  void exportText() {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }
    var content = generateJson();
    Get.dialog(
      AlertDialog(
        title: const Text("导出为文本"),
        content: TextField(
          controller: TextEditingController(text: content),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () {
              Utils.copyToClipboard(content);
              Get.back();
            },
            child: const Text("复制"),
          ),
        ],
      ),
    );
  }

  void inputText() async {
    final TextEditingController textController = TextEditingController();
    await Get.dialog(
      AlertDialog(
        title: const Text("从文本导入"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "请输入内容",
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () async {
              var content = await Utils.getClipboard();
              if (content != null) {
                textController.text = content;
              }
            },
            child: const Text("粘贴"),
          ),
          TextButton(
            onPressed: () async {
              if (textController.text.isEmpty) {
                SmartDialog.showToast("内容为空");
                return;
              }
              try {
                await inputJson(textController.text);
                SmartDialog.showToast("导入成功");
                Get.back();
                loadData();
              } catch (e) {
                SmartDialog.showToast("导入失败，请检查内容是否正确");
              }
            },
            child: const Text("导入"),
          ),
        ],
      ),
    );
  }

  String generateJson() {
    var data = followList
        .map(
          (item) => {
            "siteId": item.siteId,
            "id": item.id,
            "roomId": item.roomId,
            "userName": item.userName,
            "face": item.face,
            "watchDuration": item.watchDuration,
            "watchDurationSec": item.watchDurationSec,
            "addTime": item.addTime.toString(),
            "remark": item.remark,
            "romanName": item.romanName,
            // tag 是「主分组」展示缓存，保留给旧版本读取（旧版本只认这个字段）；
            // tags 是归属真源（多分组），新版本读取以它为准。
            "tag": userTagNamesOf(item.id).firstOrNull ?? '全部',
            "tags": userTagNamesOf(item.id),
          },
        )
        .toList();
    return jsonEncode(data);
  }

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

  // 数据校对
  // 核心关注数据有几种错乱情况，需要进行校对，需要一定时间复核代码
  // 1：分组里含已取关的幽灵 id
  // 2: 分组名重复
  // 3: webdav 同步导致的数据错乱
  // 校对思路：followList 是存在性基础，tagList 是归属唯一真源，按前者过滤后者的成员表
  // 根据此思路，可以重写文件导入导出以及webdav恢复逻辑
  Future<void> followUserAllDataCheck() async {
    var followUserListTemp = DBService.instance.getFollowList();
    var historyListTemp = DBService.instance.getHistories();
    var oldTagList = DBService.instance.getFollowTagList();
    final aliveIds = followUserListTemp.map((f) => f.id).toSet();
    final Map<String, List<String>> tagMap = {
      for (var tag in oldTagList) tag.tag: tag.userId.where(aliveIds.contains).toList(),
    };

    for (FollowUser follow in followUserListTemp) {
      // 手动添加罗马音
      if (follow.remark != null && follow.remark!.isNotEmpty) {
        var roman = PinyinHelper.getShortPinyin(follow.remark!).normalize();
        follow.romanName = roman;
      } else {
        follow.romanName = PinyinHelper.getShortPinyin(follow.userName).normalize();
      }
      // 手动同步 watchDurationSec
      var historyItem = historyListTemp.where((history) => follow.id == history.id).firstOrNull;
      // 用户可能存在删除历史记录可能
      if (historyItem != null) {
        follow.watchDurationSec = historyItem.watchDuration!.toDuration().inSeconds;
      }
      await DBService.instance.addFollow(follow);
    }
    Log.i("transfer follow.name to roman is down!");
    // 落库
    final Map<String, FollowUserTag> res = {};
    String? lastKey;
    for (var entry in tagMap.entries) {
      lastKey = FractionalIndexing.generateKeyBetween(lastKey, null);
      final followUserTag = FollowUserTag(
        id: lastKey,
        tag: entry.key,
        userId: entry.value,
      );
      res[followUserTag.id] = followUserTag;
    }
    await DBService.instance.replaceAllFollowTags(res);
    // 重建的是 tagBox；内存里的 followTagList 必须同步重载，
    // 否则分组管理 sheet 不重启就一直显示校准前的旧列表
    getAllTagList();
    Log.i("Follow-Service: data check down，follows:${followUserListTemp.length}，tags:${tagMap.length}");
  }

  /// 清理墓碑记录：删除 updateTime 超过15天的墓碑
  Future<void> cleanupTombstones() async {
    // 墓碑保留15天 = 15 * 24 * 60 * 60 秒
    const int tombstoneTTL = 15 * 24 * 60 * 60;
    final beforeTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - tombstoneTTL;
    final count = await DBService.instance.cleanupTombstones(beforeTimestamp);
    if (count > 0) {
      Log.i("Follow-Service: cleaned $count tombstone records");
    }
  }

  @override
  void onClose() {
    updateTimer?.cancel();
    _incrementalNotifyTimer?.cancel();
    subscription?.cancel();
    super.onClose();
  }
}
