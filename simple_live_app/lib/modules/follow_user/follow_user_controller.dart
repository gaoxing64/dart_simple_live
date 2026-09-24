// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_quick_group_sheet.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser>
    with GetSingleTickerProviderStateMixin {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 3 个内置标签。**它们是视图切换 tab，不是筛选条件**（见 [activeTab]）。
  static const builtinTags = ["全部", "直播中", "未开播"];

  /// 「全部 / 直播中 / 未开播」三页的翻页控制器（TabBarView 用）。
  ///
  /// 与首页平台 Tab 同一套范式：`TabController` + `TabBarView`，支持左右滑动 /
  /// 鼠标左键横拖切页，指示器随拖动实时滑动。三页共享 [list] 数据，各自渲染
  /// 自己的段；每页用独立的滚动 / 刷新控制器（见 `liveScrollController` 等）。
  late final TabController tabController;

  /// 直播中 / 未开播两页各自的滚动 + 刷新控制器。
  ///
  /// 不能共用「全部」页那对（[scrollController] / [easyRefreshController]）：
  /// `ScrollController` 挂多个客户端会抛，`EasyRefreshController` 一个实例只能
  /// 服务一个 `EasyRefresh`。「全部」页仍用基类那对（数据主入口 + 首次加载）。
  final liveScrollController = SmoothWheelScrollController();
  final liveRefreshController = EasyRefreshController();
  final offlineScrollController = SmoothWheelScrollController();
  final offlineRefreshController = EasyRefreshController();

  /// 名字是内置标签的保留字时拒绝占用（add / rename 都会调到）。
  ///
  /// 内置 tab 只活在 [tagList] 前三项、不入库，但 `FollowUser.tag` 与
  /// `getTagOptionsWithAll` 都按名字判「全部」哨兵、分组又按名字分桶：
  /// 自定义标签撞名会让界面与语义打架，所以直接禁止。
  /// 同步导入的旧备份里万一有同名标签，最多是显示重名，不会让分组失效。
  static bool isReservedTagName(String name) =>
      builtinTags.contains(name.trim());

  /// 未分组段在 [collapsedGroups] 里的哨兵 key。
  ///
  /// 自定义标签 id 由 fractional indexing 生成（字母开头、至少两位），
  /// 不会撞上这个值。
  static const String kUngroupedKey = "ungrouped";

  /// 当前视图：0=全部（分组文件夹）1=直播中（卡片网格）2=未开播（紧凑行）。
  final activeTab = 0.obs;

  /// 顶部搜索框的内容，空串表示不过滤。
  ///
  /// 过滤在 [visibleList] 这一层做，**不放进 [filterData]** —— 后者会被
  /// `super.refreshData()` 的加载结果覆盖掉，搜索词会被冲掉。
  final searchQuery = "".obs;

  /// 搜索框的文本控制器。
  ///
  /// 页面里那个 `TextField` 必须用它，清空按钮才能真的把**输入框里的字**清掉
  /// —— 只改 [searchQuery] 的话输入框内容还在，看起来像没生效。
  final searchController = TextEditingController();

  /// 顶栏搜索是否处于展开态（点 🔍 展开、点 ← 收起）。系统返回键刻意不接管：
  /// 本页被 `KeepAliveWrapper` 保活，`PopScope` 会连别的 Tab 的返回键一起吃掉。
  final searchExpanded = false.obs;

  void openSearch() => searchExpanded.value = true;

  /// 收起搜索并**清空**关键词：输入框都不见了还留着过滤，用户就没有取消的地方了。
  ///
  /// 必须一并 `unfocus`：收起动画期间输入框还在树上（只是缩到 0 宽），不收焦点
  /// 的话输入法会悬在一个已经看不见的框上，这期间敲的字还会写回 [searchQuery]，
  /// 凭空复活一个没有可见取消入口的过滤。
  void closeSearch() {
    searchExpanded.value = false;
    searchController.clear();
    searchQuery.value = "";
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// 当前要展示的两段数据。
  ///
  /// 在播的（`liveStatus == 2`）在上、走卡片；其余（未开播 + 读取中）在下、
  /// 走紧凑行。**不能直接用 `FollowService.liveList` / `notLiveList`** ——
  /// 那两个都不含「读取中」(status 0) 的房间，直接用会让它们凭空消失。
  /// 读取中的房间归到下面那段，至少还看得见。
  ///
  /// 必须在 `Obx` 里读：内部会读 `list`（RxList）与每项的 `liveStatus`，
  /// 状态一回来两段会自己重切。
  List<FollowUser> get liveSection =>
      visibleList.where((u) => u.liveStatus.value == 2).toList();

  List<FollowUser> get offlineSection =>
      visibleList.where((u) => u.liveStatus.value != 2).toList();

  /// [list] 再叠一层搜索过滤。搜索词为空时就是原样返回。
  List<FollowUser> get visibleList {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) {
      return list;
    }
    return list.where((u) {
      final name = u.remark?.isNotEmpty == true ? u.remark! : u.userName;
      return name.toLowerCase().contains(q) ||
          u.userName.toLowerCase().contains(q) ||
          u.title.value.toLowerCase().contains(q);
    }).toList();
  }

  /// 自定义标签（显示顺序 = fractional id 顺序）。
  ///
  /// `skip(3)` 依赖「内置标签排在 tagList 最前面」这个既有约定
  /// （`setFollowTagDialog` 里也是这么假设的）。
  List<FollowUserTag> get customTags => tagList.skip(3).toList();

  /// 「全部」视图的分组模型：每个自定义标签一组 + 未分组一桶。
  ///
  /// 按**标签名**分桶：`FollowUser.tag` 存的是名字（改名会同步重写成员名字）；
  /// 「全部」以及孤儿名字（标签被删、旧备份遗留 —— `followUserAllDataCheck`
  /// 负责修的那类）落进未分组桶而不是丢失。
  ///
  /// 组内成员顺序继承 `list`（`liveListSort` 已按 sortMethod 排好，直播优先）。
  /// 搜索时空组不产出；不搜索时空组保留（它是拖拽归组的落点，也得让用户
  /// 看得见组存在）。
  ///
  /// 必须在 `Obx` 里读：内部读 `list`、`tagList` 与每项的 `liveStatus`，
  /// 三者任一变化都会自动重切。
  FollowGroupedView get groupedView {
    final tags = customTags;
    final names = {for (final t in tags) t.tag: t};
    final byName = <String, List<FollowUser>>{};
    final ungrouped = <FollowUser>[];
    for (final u in visibleList) {
      if (names.containsKey(u.tag)) {
        (byName[u.tag] ??= []).add(u);
      } else {
        ungrouped.add(u);
      }
    }
    final searching = searchQuery.value.trim().isNotEmpty;
    final groups = [
      for (final t in tags)
        if (!searching || (byName[t.tag]?.isNotEmpty ?? false))
          FollowGroup(
            tag: t,
            members: byName[t.tag] ?? const [],
            liveCount: (byName[t.tag] ?? const [])
                .where((u) => u.liveStatus.value == 2)
                .length,
          ),
    ];
    return (groups: groups, ungrouped: ungrouped);
  }

  /// 折叠中的标签 id 集合。
  ///
  /// 按 id 存：改名不影响折叠态；拖拽调序会换 id（`reorderFollowTag`），
  /// 被移动卡片的折叠态随之重置 —— 可接受。
  final collapsedGroups = <String>{}.obs;

  void toggleGroupCollapsed(String tagId) {
    if (!collapsedGroups.remove(tagId)) {
      collapsedGroups.add(tagId);
    }
    AppSettingsController.instance.setFollowCollapsedGroups(
      collapsedGroups.toList(),
    );
  }

  /// 「全部」视图里是否还有折叠中的分组。
  ///
  /// 顶栏那个按钮据此在「展开全部 / 折叠全部」之间翻转。
  ///
  /// 只认**当前真实存在**的分组：拖拽调序会换掉标签 id、删分组也不会回头清理
  /// 集合，只看 `isNotEmpty` 的话，孤儿 id 会让按钮显示「展开全部」而点下去界面
  /// 上什么都不展开 —— 新按钮的第一下「点了没反应」。
  bool get hasCollapsedGroups {
    final liveIds = {for (final t in customTags) t.id, kUngroupedKey};
    return collapsedGroups.any(liveIds.contains);
  }

  /// 顶栏一键：有折叠就全部展开，否则把自定义分组与未分组段全部折叠。
  ///
  /// 与 [toggleGroupCollapsed] 写同一份存储，重启后保持。
  void toggleAllGroupsCollapsed() {
    // 判据与按钮显示口径共用 [hasCollapsedGroups]：孤儿 id 不该让这一下变成
    // 「只清理、不展开」的空动作。
    if (hasCollapsedGroups) {
      collapsedGroups.clear();
    } else {
      collapsedGroups.assignAll([
        for (final t in customTags) t.id,
        kUngroupedKey,
      ]);
    }
    AppSettingsController.instance.setFollowCollapsedGroups(
      collapsedGroups.toList(),
    );
  }

  /// 拖拽调序分组卡片。索引以 [customTags] 为准（与 `followTagList` 同序）。
  void reorderTag(int oldIndex, int newIndex) {
    FollowService.instance.reorderFollowTag(oldIndex, newIndex);
    // 本地立即刷新（事件回环稍后还会刷一次，先刷省一帧跳变）
    updateTagList();
    // 与分组管理 sheet 同一条链路：事件 → FollowService 重载 →
    // updatedListStream → updateTagList + filterData。
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
  }

  /// 快速重组：当前勾选中的关注 id 集合。
  ///
  /// 勾选入口是成员行头像的点按（点头像=勾选/取消，点行体其他位置=进直播间），
  /// 不进入独立"选择模式"，与长按菜单、拖拽换组互不干扰。
  final selectedIds = <String>{}.obs;

  /// 勾选中的关注项（按当前列表顺序），编辑弹窗的头像预览用。
  List<FollowUser> get selectedUsers {
    final ids = Set<String>.of(selectedIds);
    return FollowService.instance.followList
        .where((u) => ids.contains(u.id))
        .toList();
  }

  void toggleSelected(String id) {
    if (!selectedIds.remove(id)) {
      selectedIds.add(id);
    }
  }

  void clearSelection() => selectedIds.clear();

  /// 「编辑」弹窗：新建分组（默认）+ 移入已有分组 / 移出分组（设计稿补充）。
  void showQuickGroupDialog() {
    if (selectedIds.isEmpty) {
      return;
    }
    final selected = selectedUsers;
    final tags = customTags;
    Get.bottomSheet(
      FollowQuickGroupSheet(
        selected: selected,
        existingTags: tags,
        ungroupTag: tagList.first,
        onCreate: (name) async {
          final trimmed = name.trim();
          if (trimmed.isEmpty) {
            SmartDialog.showToast("请输入分组名称");
            return false;
          }
          if (isReservedTagName(trimmed)) {
            SmartDialog.showToast("「$trimmed」是内置分组名，不能占用");
            return false;
          }
          if (tags.any((t) => t.tag == trimmed)) {
            SmartDialog.showToast("分组名重复，修改失败");
            return false;
          }
          await FollowService.instance.addFollowUserTag(trimmed);
          final created = FollowService.instance.followTagList
              .firstWhereOrNull((t) => t.tag == trimmed);
          if (created == null) {
            return false;
          }
          updateTagList();
          await reassignSelected(created);
          return true;
        },
        onMoveTo: (tag) => reassignSelected(tag),
      ),
      backgroundColor: Get.theme.cardColor,
      // 不放开的话 get 会把 sheet 硬夹在可用高度的 9/16 里
      // （`isScrollControlled: false` 那条分支），键盘一弹、可用高度缩水，
      // 表单尾部（取消 / 创建分组）就被裁到盒子外面。
      isScrollControlled: true,
    );
  }

  /// 把全部勾选中的主播移入 [target]（单组模型：自动从原分组移出）。
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
      await FollowService.instance.setFollowTag(user, target);
      moved++;
    }
    clearSelection();
    filterData();
    SmartDialog.showToast("已将 $moved 位主播移入「${target.tag}」");
  }

  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "直播中", userId: []),
    FollowUserTag(id: "2", tag: "未开播", userId: []),
  ].obs;

  // 用户自定义显示顺序 - default：watchDuration
  Rx<SortMethod> sortMethod = SortMethod.watchDuration.obs;

  // 排序方式
  var sortMap = {
    SortMethod.watchDuration: "观看时长",
    SortMethod.siteId: "直播平台",
    SortMethod.recently: "最近添加",
    SortMethod.userNameASC: "用户名A-Z",
    SortMethod.userNameDESC: "用户名Z-A",
    SortMethod.tag: "自定义分组",
  };

  @override
  void onInit() {
    tabController = TabController(length: builtinTags.length, vsync: this);
    // 切页（点 tab 或横拖落定）后同步 activeTab，供指示器 / 顶部重置逻辑读取。
    tabController.addListener(() {
      if (activeTab.value != tabController.index) {
        activeTab.value = tabController.index;
      }
    });
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream = FollowService.instance.updatedListStream.listen(
      (event) {
        updateTagList();
        filterData();
      },
    );

    sortMethod = AppSettingsController.instance.followSortMethod;
    collapsedGroups.assignAll(
      AppSettingsController.instance.followCollapsedGroups,
    );
    super.onInit();
  }

  @override
  Future refreshData() async {
    await FollowService.instance.loadData();
    updateTagList();
    // 必须 await：super.refreshData 才是真正拉数据的那一次加载，
    // 不等待会让 easy_refresh 的刷新指示器提前收起。
    await super.refreshData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    if (page > 1) {
      return Future.value([]);
    }
    // 一律返回副本：这些 List 是 FollowService 的数据源，直接交出去会与
    // 页面列表共享同一个 List 对象，filterData 的 assignAll / retainWhere
    // 会反过来清空或删改数据源。
    return List.of(FollowService.instance.followList.value);
  }

  void updateTagList() {
    tagList.value = tagList.take(3).toList();
    for (var i in FollowService.instance.followTagList) {
      if (!tagList.contains(i)) {
        tagList.add(i);
      }
    }
  }

  // 数据清洗：不关心中间 data_flow，最终由filterData决定显示数据
  //
  // 注意：本方法绕过 BasePageController._doLoad 直接写 list，因此必须自己
  // 同步分页状态。否则上一次加载留下的 pageEmpty=true 会继续用空态浮层
  // 盖住列表，表现为「切换 tag 没有任何作用」。
  void filterData() {
    bool hideOffline = AppSettingsController.instance.hideOfflineFollow.value;

    // 3 个内置标签是视图切换 tab（见 [activeTab]），不是筛选条件，
    // 一律给完整列表：「全部」按 [groupedView] 分组，另两个视图按 liveStatus 切。
    list.assignAll(FollowService.instance.followList.value);

    // 「隐藏离线关注」把未开播砍掉 —— 分组卡片内的离线成员同样受影响。
    if (hideOffline) {
      list.retainWhere((user) => user.liveStatus.value == 2);
    }

    // 关注列表是本地单页数据源，getData 对 page>1 恒返回空，没有下一页可加载
    canLoadMore.value = false;
    pageEmpty.value = list.isEmpty;
    // 本方法绕过 _doLoad 直接写 list，错误态也要自己清理，
    // 否则上一次加载失败的错误浮层会继续盖住刚切出来的内容
    pageError.value = false;
    // 失败标记同样成对清除。目前 canLoadMore 恒为 false 使门闩读不到，
    // 但状态不一致本身就是隐患：一旦将来关注页接上真实分页，
    // 残留的 loadFailed 会让补页在无可见原因的情况下被挡住。
    loadFailed = false;
    loadMoreFailed.value = false;
  }

  // 用户自定义顺序dialog
  Future<void> showSortDialog() async {
    var res = await Utils.showMapOptionDialog(sortMap, sortMethod.value,
        title: "排序方式");
    if (res != null) {
      sortMethod.value = res;
      AppSettingsController.instance.setFollowSortMethod(sortMethod.value);
      // 排序作用于整个关注列表，两段各自继承（未开播那段也就跟着排了）。
      FollowService.instance.liveListSort();
      filterData();
    }
  }

  void removeFollow(FollowUser follow) async {
    var result = await Utils.showAlertDialog("确定要取消关注${follow.userName}吗?",
        title: "取消关注");
    if (!result) {
      return;
    }
    // 取消关注同时删除标签内的 userId
    if (follow.tag != "全部") {
      var tag = tagList.firstWhereOrNull((tag) => tag.tag == follow.tag);
      if (tag != null) {
        tag.userId.remove(follow.id);
        updateTag(tag);
      }
    }
    await FollowService.instance.removeFollowUser(follow.id);
    selectedIds.remove(follow.id);
    filterData();
  }

  Future<void> updateFollow(FollowUser follow) async {
    await FollowService.instance.addFollow(follow);
  }

  void setFollowTag(FollowUser follow, FollowUserTag targetTag) {
    FollowService.instance.setFollowTag(follow, targetTag);
    filterData();
  }

  Future<void> updateTag(FollowUserTag followUserTag) async {
    await FollowService.instance.updateFollowUserTag(followUserTag);
  }

  // 弹出底部菜单栏
  void showBottomMenu(FollowUser item) {
    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Remix.price_tag_3_line),
              title: const Text('设置分组'),
              onTap: () {
                Get.back();
                setFollowTagDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Remix.information_line),
              title: const Text('查看详情'),
              onTap: () {
                Get.back();
                AppNavigator.toFollowInfo(item);
              },
            ),
          ],
        ),
      ),
      backgroundColor: Get.theme.cardColor,
    );
  }

  void setFollowTagDialog(FollowUser follow) {
    /// 控制单选ui
    List<FollowUserTag> copiedList = [
      tagList.first,
      ...tagList.skip(3),
    ];
    // 初值取该项自己的标签（chips 移除后没有 filterMode 可参考了）；
    // 孤儿名字（标签已删）落到第一项「全部」。
    Rx<FollowUserTag> checkTag = (copiedList.firstWhereOrNull(
              (t) => t.tag == follow.tag,
            ) ??
            copiedList.first)
        .obs;
    final ScrollController scrollController = ScrollController();
    Get.dialog(
      AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '设置分组',
                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  tooltip: "保存",
                  icon: const Icon(
                    Icons.check,
                  ),
                  onPressed: () {
                    setFollowTag(follow, checkTag.value);
                    Get.back();
                  },
                ),
              ],
            ),
            const Divider(),
            Obx(
              () {
                int selectedIndex = copiedList.indexOf(checkTag.value);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (selectedIndex >= 0) {
                    scrollController.animateTo(
                      selectedIndex * 60.0, // 假设每项高度为 60
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                });
                return SizedBox(
                  height: 300,
                  width: 300,
                  child: RadioGroup<FollowUserTag>(
                    groupValue: checkTag.value,
                    onChanged: (value) {
                      checkTag.value = value!;
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: copiedList.length,
                      itemBuilder: (context, index) {
                        var tagItem = copiedList[index];
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey.shade300, width: 1.0),
                            ),
                          ),
                          child: RadioListTile<FollowUserTag>(
                            title: Text(tagItem.tag),
                            value: tagItem,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 底部导航「关注」再次点击：把**当前这一页**滚回顶部，已在顶部则下拉刷新。
  ///
  /// 三页各有独立滚动 / 刷新控制器，基类那对只服务「全部」页，这里按
  /// [tabController] 当前页选对应控制器；否则在直播中页点回顶会去滚离屏的全部页。
  @override
  void scrollToTopOrRefresh() {
    final (scroll, refresh) = switch (tabController.index) {
      1 => (liveScrollController, liveRefreshController),
      2 => (offlineScrollController, offlineRefreshController),
      _ => (scrollController, easyRefreshController),
    };
    if (!scroll.hasClients) {
      return;
    }
    if (scroll.offset > 0) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    } else {
      refresh.callRefresh();
    }
  }

  @override
  void onClose() {
    tabController.dispose();
    liveScrollController.dispose();
    liveRefreshController.dispose();
    offlineScrollController.dispose();
    offlineRefreshController.dispose();
    searchController.dispose();
    onUpdatedIndexedStream?.cancel();
    onUpdatedListStream?.cancel();
    super.onClose();
  }
}

/// 「全部」视图里的一组：标签 + 成员 + 在播数。
class FollowGroup {
  final FollowUserTag tag;
  final List<FollowUser> members;
  final int liveCount;
  const FollowGroup({
    required this.tag,
    required this.members,
    required this.liveCount,
  });
  int get totalCount => members.length;
}

/// 「全部」视图的分组模型（见 `FollowUserController.groupedView`）。
typedef FollowGroupedView
    = ({List<FollowGroup> groups, List<FollowUser> ungrouped});
