// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_selection.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/live_room_route_args.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_card_preview_dialog.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_quick_group_sheet.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser> {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 3 个内置标签。**它们是视图切换 tab，不是筛选条件**（见 [activeTab]）。
  static const builtinTags = ["全部", "直播中", "未开播"];

  /// 「全部 / 直播中 / 未开播」三页的翻页控制器。
  ///
  /// 导航（三个内置视图 + 平台 / 分组）已经收在左侧第二栏，翻页方向跟着
  /// **导航栏位置**走：侧栏在左 → 纵向（Y 轴）翻页，与首页壳
  /// 「侧边栏在左就垂直滑动」是同一条约定（见 `IndexedController`）。
  ///
  /// 手势不参与（页面里是 `NeverScrollableScrollPhysics`）：三页各自都是
  /// 竖向滚动列表，再让纵向手势翻页就和列表抢同一根轴了 —— 理由与首页壳
  /// 的 Section PageView 完全一致。切换的唯一入口是 [selectSidebarItem]。
  final pageController = PageController();

  /// 翻页动画：与首页壳 / 平台 Tab 切换同一条 M3 motion（300ms / emphasized）。
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Curve pageTransitionCurve = Curves.easeInOutCubicEmphasized;

  /// 切到第 [index] 页。
  ///
  /// [activeTab] 是唯一真源（侧栏高亮、回顶目标都读它），这里先写状态再发
  /// 动画；没 attach（单测 / 首帧前）就只更新状态。
  void _goToPage(int index) {
    final changed = activeTab.value != index;
    activeTab.value = index;
    if (!changed || !pageController.hasClients) {
      return;
    }
    pageController.animateToPage(
      index,
      duration: pageTransitionDuration,
      curve: pageTransitionCurve,
    );
  }

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
  /// 内置 tab 只活在 [tagList] 前三项、不入库，但 `'全部'` 是「不属于任何分组」
  /// 的哨兵名：自定义分组撞名会让界面与语义打架，所以直接禁止。
  /// 同步导入的旧备份里万一有同名标签，最多是显示重名，不会让分组失效。
  static bool isReservedTagName(String name) => builtinTags.contains(name.trim());

  /// 当前视图：0=全部（全量平铺）1=直播中 2=未开播。
  final activeTab = 0.obs;

  /// 「全部」视图的筛选态：选中的平台 / 自定义分组；null = 全量平铺。
  ///
  /// 存筛选对象不存分组对象：改名不影响筛选。但**调序会换 id**
  /// （`reorderFollowTag` 重新生成 fractional key）、删除分组也不会回头清理
  /// —— 所以读取一律经 [activeGroup] 校验，失效回落 null（全量平铺），
  /// 绝不让筛选指向一个已经不存在的组（那会渲染出一个空白平铺列表，
  /// 看着像筛选坏了）。
  final activeFilter = Rx<FollowFilter?>(null);

  /// [activeFilter] 对应的自定义分组；不是分组筛选（或分组已不存在）时为 null。
  FollowUserTag? get activeGroup {
    final filter = activeFilter.value;
    if (filter == null || filter.kind != FollowSidebarKind.group) {
      return null;
    }
    return customTags.firstWhereOrNull((t) => t.id == filter.id);
  }

  /// 当前筛选的成员（搜索过滤后，顺序继承 [list]，直播优先）。
  ///
  /// 分组走 [groupedView] 的桶（多归属：一个关注可同时出现在多个分组里）；
  /// 平台走 `visibleList.where(siteId ==)` —— 平台是动态筛选，不依赖任何
  /// 分组数据，新关注自动进来。
  ///
  /// 页面两处用：平铺段自己，以及「没有匹配的关注」空态浮层的判据。
  List<FollowUser> get filteredMembers {
    final filter = activeFilter.value;
    if (filter == null) {
      return const [];
    }
    switch (filter.kind) {
      case FollowSidebarKind.group:
        return groupedView.groups.firstWhereOrNull((g) => g.tag.id == filter.id)?.members ?? const [];
      case FollowSidebarKind.site:
        return visibleList.where((u) => u.siteId == filter.id).toList();
      default:
        return const [];
    }
  }

  /// 当前筛选是否**有效**（分组还在 / 平台是已知站点）。
  ///
  /// 幽灵 id（分组被删 / 调序换了 id）必须回落文件夹总览 —— 留一个空白
  /// 平铺列表，看着像筛选坏了。平台侧同理：站点被下线后 id 不在
  /// `Sites.allSites` 里，也当失效。
  bool get hasActiveFilter {
    final filter = activeFilter.value;
    if (filter == null) {
      return false;
    }
    if (filter.kind == FollowSidebarKind.site) {
      return Sites.allSites.containsKey(filter.id);
    }
    return activeGroup != null;
  }

  /// 第二栏当前选中项的 [FollowSidebarItem.key]（用于高亮）。
  ///
  /// 内置视图与筛选态互斥，所以任意时刻只有一个值；读 Rx 的 [activeTab]，
  /// 切页后侧栏高亮跟着走。
  String? get activeSidebarKey {
    final filter = activeFilter.value;
    if (filter != null) {
      return filter.kind == FollowSidebarKind.site ? 'site:${filter.id}' : 'group:${filter.id}';
    }
    return switch (activeTab.value) {
      1 => 'live',
      2 => 'offline',
      _ => 'all',
    };
  }

  /// 第二栏标签项：3 个内置视图 →（按平台分类开启时）平台 → 自定义分组。
  ///
  /// **必须在 Obx 构建窗口内读**：内部读 `list`、`tagList`、平台开关与每项的
  /// `liveStatus`，任一变化两栏都要重算（计数 / 显隐都会变）。
  ///
  /// 平台项只收**已启用且计数非 0** 的平台：0 计时的平台标签点了也是空列表，
  /// 放在栏里纯噪音；空自定义分组保留（它是拖拽归组的落点，也得让用户看得见
  /// 组存在，与「全部」视图的文件夹卡片同口径）。
  List<FollowSidebarItem> get sidebarItems {
    final items = <FollowSidebarItem>[];
    final live = liveSection.length;
    final offline = offlineSection.length;
    items.add(FollowSidebarItem(
      kind: FollowSidebarKind.all,
      id: 'all',
      label: builtinTags[0],
      count: live + offline,
    ));
    items.add(FollowSidebarItem(
      kind: FollowSidebarKind.live,
      id: 'live',
      label: builtinTags[1],
      count: live,
    ));
    items.add(FollowSidebarItem(
      kind: FollowSidebarKind.offline,
      id: 'offline',
      label: builtinTags[2],
      count: offline,
    ));
    final settings = AppSettingsController.instance;
    if (settings.followGroupBySite.value) {
      final enabled = settings.followSiteGroupSites.toSet();
      for (final siteId in Sites.orderedIds(settings.siteSort)) {
        if (!enabled.contains(siteId)) {
          continue;
        }
        final site = Sites.allSites[siteId];
        if (site == null) {
          continue;
        }
        final count = visibleList.where((u) => u.siteId == siteId).length;
        if (count == 0) {
          continue;
        }
        items.add(FollowSidebarItem(
          kind: FollowSidebarKind.site,
          id: siteId,
          label: site.name,
          site: site,
          count: count,
        ));
      }
    }
    for (final tag in customTags) {
      final members = groupedView.groups.firstWhereOrNull((g) => g.tag.id == tag.id)?.members ?? const [];
      items.add(FollowSidebarItem(
        kind: FollowSidebarKind.group,
        id: tag.id,
        label: tag.tag,
        count: members.length,
      ));
    }
    return items;
  }

  /// 第二栏选中某项 —— 「要么内置视图、要么筛选」的互斥不变式唯一收口。
  ///
  /// * 内置项：清筛选 + 纵向切到对应页（已在页上也清筛选，点「全部」= 退出筛选）。
  /// * 平台 / 分组：设筛选 + 纵向回「全部」页。
  ///
  /// 翻页手势是关掉的（见 [pageController]），所以这里是**唯一**的切页入口，
  /// 侧栏高亮与内容不会脱节。
  void selectSidebarItem(FollowSidebarItem item) {
    switch (item.kind) {
      case FollowSidebarKind.all:
      case FollowSidebarKind.live:
      case FollowSidebarKind.offline:
        activeFilter.value = null;
        final index = switch (item.kind) {
          FollowSidebarKind.live => 1,
          FollowSidebarKind.offline => 2,
          _ => 0,
        };
        _goToPage(index);
        break;
      case FollowSidebarKind.site:
      case FollowSidebarKind.group:
        activeFilter.value = FollowFilter(kind: item.kind, id: item.id);
        _goToPage(0);
        // 平铺列表比文件夹总览矮，不复位滚动会停在半空，
        // 用户会以为「筛选没生效」。
        _scrollAllPageToTop();
        break;
    }
  }

  /// 「全部」页滚回顶部（筛选切换时用）。
  void _scrollAllPageToTop() {
    final scroll = scrollController;
    if (scroll.hasClients && scroll.offset > 0) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    }
  }

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

  /// 关注页当前是否处于主导航可见 Tab。
  ///
  /// 页面被 KeepAlive 保活，切到其他 Tab 后仍挂在树上；返回拦截只能用这个
  /// 状态限定生效范围，否则会吃掉别的 Tab 的系统返回/鼠标侧键。
  final isPageActive = true.obs;

  void setPageActive(bool value) => isPageActive.value = value;

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
  List<FollowUser> get liveSection => visibleList.where((u) => u.liveStatus.value == 2).toList();

  List<FollowUser> get offlineSection => visibleList.where((u) => u.liveStatus.value != 2).toList();

  /// [list] 再叠一层搜索过滤。搜索词为空时就是原样返回。
  List<FollowUser> get visibleList {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) {
      return list;
    }
    return list.where((u) {
      final name = u.displayName;
      return name.toLowerCase().contains(q) ||
          u.userName.toLowerCase().contains(q) ||
          (u.remark?.toLowerCase().contains(q) ?? false) ||
          u.title.value.toLowerCase().contains(q);
    }).toList();
  }

  /// 自定义标签（显示顺序 = fractional id 顺序）。
  ///
  /// `skip(3)` 依赖「内置标签排在 tagList 最前面」这个既有约定
  /// （`setFollowTagDialog` 里也是这么假设的）。
  List<FollowUserTag> get customTags => tagList.skip(3).toList();

  /// userId -> 它所属的自定义分组名（按侧栏顺序）。
  ///
  /// 内容页在 Obx 里一次取好再传给卡片 / 行：`itemBuilder` 在 sliver 布局
  /// 阶段才执行，逐项 `FollowService.userTagNamesOf` 既扫得慢，也赶不上
  /// Obx 的依赖捕获。这里不缓存，分组增删改 / 调序 / 成员变更后重建即可。
  Map<String, List<String>> get groupNamesByFollowId {
    final result = <String, List<String>>{};
    for (final tag in customTags) {
      final name = tag.tag.trim();
      if (name.isEmpty) {
        continue;
      }
      for (final userId in tag.userId) {
        final names = result[userId] ??= <String>[];
        if (!names.contains(name)) {
          names.add(name);
        }
      }
    }
    return result;
  }

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
            liveCount: byTagId[t.id]!.where((u) => u.liveStatus.value == 2).length,
          ),
    ];
    return (groups: groups, ungrouped: ungrouped);
  }

  /// 快速重组：当前勾选中的关注 id 集合。
  ///
  /// 勾选入口是成员行头像的点按（点头像=勾选/取消，点行体其他位置=进直播间），
  /// 不进入独立"选择模式"，与长按菜单、拖拽换组互不干扰。
  final selectedIds = <String>{}.obs;

  /// 勾选中的关注项（按当前列表顺序），编辑弹窗的头像预览用。
  List<FollowUser> get selectedUsers {
    final ids = Set<String>.of(selectedIds);
    return FollowService.instance.followList.where((u) => ids.contains(u.id)).toList();
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
          final created = FollowService.instance.followTagList.firstWhereOrNull((t) => t.tag == trimmed);
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

  /// 把全部勾选中的主播**加入** [target]（多归属：原分组里的成员身份保留）。
  Future<void> reassignSelected(FollowUserTag target) async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    var moved = 0;
    for (final id in ids) {
      final user = FollowService.instance.followList.firstWhereOrNull((u) => u.id == id);
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

  /// 把勾选中的、正在直播的主播一次性开成多开（选择态 ⋮ 菜单里的「多开」）。
  ///
  /// 顺序按**关注列表顺序**（`selectedUsers` 的顺序），不是点击顺序：第 0 路会成为
  /// 直播间页自带的那一格，其余几路预载成棋盘里的格子。
  ///
  /// 上限取设置里的「默认路数」而不是写死 [kMultiPlayMaxTiles]：移动端一次塞四路
  /// 会因放不下而白折叠两格（见 [resolveDefaultMultiPlayTiles]）。
  void openMultiPlayFromSelection() {
    final max = AppSettingsController.instance.multiPlayDefaultTiles.value;
    final result = selectForMultiPlay(selectedUsers, max: max);
    switch (result.problem) {
      case MultiPlaySelectionProblem.empty:
        SmartDialog.showToast("选中的主播都不在直播中");
        return;
      case MultiPlaySelectionProblem.tooMany:
        SmartDialog.showToast("最多同时播放 $max 个直播间");
        return;
      case MultiPlaySelectionProblem.none:
        break;
    }

    final first = result.rooms.first;
    final rest = [
      for (final user in result.rooms.skip(1)) LiveRoomTarget(site: Sites.allSites[user.siteId]!, roomId: user.roomId),
    ];
    clearSelection();
    AppNavigator.toLiveRoomDetail(
      site: Sites.allSites[first.siteId]!,
      roomId: first.roomId,
      together: rest,
    );
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
    SortMethod.online: "在线人数",
    SortMethod.tag: "自定义分组",
  };

  @override
  void onInit() {
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

  /// 关注样式二选一的选项表：紧凑模式（true）/ 卡片模式（false）。
  ///
  /// 只作用于「全部」视图**选中某一分组**时的平铺列表（见 [activeGroup]）——
  /// 文件夹总览下成员固定紧凑行，没有第二种排法，⋮ 里的「模式切换」也因此
  /// 只在筛选态出现。
  static const followStyleMap = {true: "紧凑模式", false: "卡片模式"};

  Future<void> showFollowStyleDialog() async {
    var res = await Utils.showMapOptionDialog(
      title: "关注样式切换",
      followStyleMap,
      AppSettingsController.instance.followStyleNotGrid.value,
    );
    if (res != null) {
      AppSettingsController.instance.setFollowStyleNotGrid(res);
    }
  }

  // 用户自定义顺序dialog
  Future<void> showSortDialog() async {
    var res = await Utils.showMapOptionDialog(sortMap, sortMethod.value, title: "排序方式");
    if (res != null) {
      sortMethod.value = res;
      AppSettingsController.instance.setFollowSortMethod(sortMethod.value);
      // 排序作用于整个关注列表，两段各自继承（未开播那段也就跟着排了）。
      FollowService.instance.liveListSort();
      filterData();
    }
  }

  void removeFollow(FollowUser follow) async {
    var result = await Utils.showAlertDialog("确定要取消关注${follow.displayName}吗?", title: "取消关注");
    if (!result) {
      return;
    }
    // 归属清理由 `FollowService.removeFollowUser` 统一负责
    await FollowService.instance.removeFollowUser(follow.id);
    selectedIds.remove(follow.id);
    filterData();
  }

  Future<void> updateFollow(FollowUser follow) async {
    await FollowService.instance.addFollow(follow);
  }

  Future<void> updateTag(FollowUserTag followUserTag) async {
    await FollowService.instance.updateFollowUserTag(followUserTag);
  }

  // 右键 / 长按后弹出的预览卡片：展示当前封面与标题，操作收在右下角。
  void showBottomMenu(FollowUser item) {
    showFollowCardPreviewDialog(
      item: item,
      groupNames: groupNamesByFollowId[item.id] ?? const [],
      onSetGroup: () => setFollowTagDialog(item),
      onViewDetail: () => AppNavigator.toFollowInfo(item),
      onRemove: () => removeFollow(item),
    );
  }

  /// 设置分组：多选（一个关注可以同时属于多个分组）。
  ///
  /// 打开时勾上它当前所属的组；点 ✓ 才落库 —— 按「新增 / 移除」两个差集执行，
  /// 不做「先清空再全量写」，避免把 fractional id 顺序之外的数据抖一遍。
  void setFollowTagDialog(FollowUser follow) {
    final copiedList = [...tagList.skip(3)];
    final checked = <String>{...FollowService.instance.userTagNamesOf(follow.id)};

    Get.dialog(
      // 勾选状态是 dialog 内的临时状态。不要用 Obx 包懒加载的 ListView：
      // itemBuilder 在布局阶段才执行，Obx 构建窗口里读不到 checked，
      // GetX 会直接抛 “improper use” 并把 dialog 变成一块灰色 ErrorWidget。
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                      final before = FollowService.instance.userTagNamesOf(follow.id).toSet();
                      for (final name in checked.difference(before)) {
                        await FollowService.instance.addUserToTag(follow, name);
                      }
                      for (final name in before.difference(checked)) {
                        await FollowService.instance.removeUserFromTag(follow, name);
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
                  child: ListView.builder(
                    itemCount: copiedList.length,
                    itemBuilder: (context, index) {
                      final tagItem = copiedList[index];
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300, width: 1.0),
                          ),
                        ),
                        child: CheckboxListTile(
                          title: Text(tagItem.tag),
                          value: checked.contains(tagItem.tag),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                checked.add(tagItem.tag);
                              } else {
                                checked.remove(tagItem.tag);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部导航「关注」再次点击：把**当前这一页**滚回顶部，已在顶部则下拉刷新。
  ///
  /// 三页各有独立滚动 / 刷新控制器，基类那对只服务「全部」页，这里按
  /// [activeTab] 当前页选对应控制器；否则在直播中页点回顶会去滚离屏的全部页。
  @override
  void scrollToTopOrRefresh() {
    final (scroll, refresh) = switch (activeTab.value) {
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
    pageController.dispose();
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
typedef FollowGroupedView = ({List<FollowGroup> groups, List<FollowUser> ungrouped});
