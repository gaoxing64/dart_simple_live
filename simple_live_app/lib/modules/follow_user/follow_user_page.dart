import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_tag_manager.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_group_card.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_app/widgets/collapsible_top_bar_scaffold.dart';
import 'package:simple_live_core/simple_live_core.dart';

class FollowUserPage extends GetView<FollowUserController> {
  const FollowUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    var count = MediaQuery
        .of(context)
        .size
        .width ~/ 500;
    if (count < 1) count = 1;
    var c = MediaQuery
        .of(context)
        .size
        .width ~/ 200;
    if (c < 2) {
      c = 2;
    }
    // 关注页上所有圆形图标按钮（顶栏刷新 / 顶栏分组管理 / 顶栏排序 / 顶栏更多菜单 /
    // 搜索框清空 / 行尾取关）共用这一份规格，hover 与按压反馈因此完全一致。
    // 为什么不放进主题统一给：见 `AppStyle.iconButtonStyle` 的注释。
    final iconButtonStyle = AppStyle.iconButtonStyle(
      Theme.of(context).colorScheme,
    );
    return CollapsibleTopBarScaffold(
      appBar: _buildAppBar(iconButtonStyle),
      body: _buildBody(context, iconButtonStyle, count, c),
    );
  }

  /// 顶栏：标题 + 刷新按钮 + 排序 + 更多菜单（含分组管理）。
  ///
  /// 有勾选时进入选择态（设计稿）：leading 变 ✕（清空选择）、标题变
  /// 「已选择 N 位」、排序按钮换成「一键成组」主色胶囊。
  /// 分组管理入口按设计稿收进右侧 ⋮ 弹层，不再占一个独立图标；
  /// 刷新按钮保留（设计稿没画，但去掉是功能倒退）。
  /// 玻璃胶囊不做：本页顶栏是随滚动收起的 `CollapsibleTopBarScaffold` AppBar，
  /// 玻璃机制（`liquid_glass_nav_defaults.dart`）只服务悬浮导航栏。
  PreferredSizeWidget _buildAppBar(ButtonStyle iconButtonStyle) {
    return AppBar(
      title: Obx(
        () => Text(controller.selectedIds.isEmpty
            ? "关注用户"
            : "已选择 ${controller.selectedIds.length} 位"),
      ),
      actions: [
        // 选择态：一键成组；普通态：排序 dialog。
        Obx(
          () => controller.selectedIds.isEmpty
              ? IconButton(
                  style: iconButtonStyle,
                  tooltip: "排序方式",
                  icon: const Icon(Remix.sort_asc),
                  onPressed: controller.showSortDialog,
                )
              : Padding(
                  padding: AppStyle.edgeInsetsV8.copyWith(right: 4),
                  child: FilledButton.icon(
                    onPressed: controller.showQuickGroupDialog,
                    icon: const Icon(Remix.folder_add_line, size: 18),
                    label: const Text("一键成组"),
                  ),
                ),
        ),
        PopupMenuButton(
          style: iconButtonStyle,
          itemBuilder: (context) {
            // 用自己的 item：官方 `PopupMenuItem` 的 hover 高亮是满宽矩形，
            // 与菜单容器的大圆角对不上。详见 `AppPopupMenuItem`。
            return const [
              AppPopupMenuItem(
                value: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Remix.folder_3_line),
                    AppStyle.hGap12,
                    Text("分组管理"),
                  ],
                ),
              ),
              AppPopupMenuItem(
                value: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Remix.trophy_line),
                    AppStyle.hGap12,
                    Text("赛事订阅"),
                  ],
                ),
              ),
              AppPopupMenuItem(
                value: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Remix.heart_line),
                    AppStyle.hGap12,
                    Text("关注设置"),
                  ],
                ),
              ),
            ];
          },
          onSelected: (value) {
            if (value == 4) {
              Get.toNamed(RoutePath.kSettingsFollow);
            } else if (value == 0) {
              SmartDialog.showToast("此功能暂未开放！敬请期待！");
            } else if (value == 6) {
              showFollowTagManagerSheet();
            }
          },
        ),
      ],
      leading: Obx(() {
        // 选择态：✕ 清空选择并退出。
        if (controller.selectedIds.isNotEmpty) {
          return IconButton(
            style: iconButtonStyle,
            tooltip: "退出选择",
            onPressed: controller.clearSelection,
            icon: const Icon(Icons.close),
          );
        }
        return FollowService.instance.updating.value
            ? IconButton(
                style: iconButtonStyle,
                tooltip: "刷新中",
                onPressed: null,
                icon: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              )
            : IconButton(
                style: iconButtonStyle,
                tooltip: "刷新",
                onPressed: () {
                  controller.refreshData();
                },
                icon: const Icon(Icons.refresh),
              );
      }),
    );
  }

  Widget _buildBody(
      BuildContext context, ButtonStyle iconButtonStyle, int count, int c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 搜索框。**放在 Obx 外面** —— 它自己不订阅数据，放进 Obx 会在列表
        // 刷新时被重建，正在输入的内容和焦点都会丢。
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 4, bottom: 0),
          child: TextField(
            controller: controller.searchController,
            onChanged: (v) => controller.searchQuery.value = v,
            decoration: InputDecoration(
              hintText: "搜索关注的主播",
              prefixIcon: const Icon(Icons.search),
              // 清空按钮：有内容时才出现。
              // **只把这一小块包进 Obx** —— 整个 TextField 是刻意放在外层 Obx
              // 之外的（见上面的注释），整个塞进去会在列表刷新时重建、丢焦点。
              suffixIcon: Obx(
                () => controller.searchQuery.value.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        style: iconButtonStyle,
                        tooltip: "清空",
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.searchController.clear();
                          controller.searchQuery.value = "";
                        },
                      ),
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: AppStyle.radius24,
                borderSide: BorderSide.none,
              ),
              filled: true,
            ),
          ),
        ),
        // 3 个内置视图 tab。要计数，所以在 Obx 里。
        Obx(() {
          final live = controller.liveSection.length;
          final offline = controller.offlineSection.length;
          return _ViewSwitchBar(
            controller: controller,
            counts: [live + offline, live, offline],
          );
        }),
        Obx(
          () {
            final hide =
                AppSettingsController.instance.hideRemoveFollowButton.value;
            final live = controller.liveSection;
            final offline = controller.offlineSection;
            return Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 三页 ViewPager（与首页平台 Tab 同范式）：左右滑动 / 鼠标左键
                  // 横拖切页，指示器随拖动实时滑动。每页 PageGridView 各自滚动，
                  // 「全部」页是数据主入口（firstRefresh:true 唯一触发首次加载）。
                  TabBarView(
                    controller: controller.tabController,
                    children: [
                      KeepAliveWrapper(
                        child: PageGridView(
                          pageController: controller,
                          padding: AppStyle.edgeInsetsA12,
                          firstRefresh: true,
                          // 段与段之间的竖直间距；段内的行距由各段自己的
                          // mainAxisSpacing 管。
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          sections: _buildGroupedSections(count, hide),
                        ),
                      ),
                      PageGridView(
                        pageController: controller,
                        padding: AppStyle.edgeInsetsA12,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        scrollOverride: controller.liveScrollController,
                        refreshOverride: controller.liveRefreshController,
                        sections: _liveSections(live, c),
                      ),
                      PageGridView(
                        pageController: controller,
                        padding: AppStyle.edgeInsetsA12,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        scrollOverride: controller.offlineScrollController,
                        refreshOverride: controller.offlineRefreshController,
                        sections: _offlineSections(offline, count, hide),
                      ),
                    ],
                  ),
                  // 搜索没匹配到任何关注时的提示。
                  //
                  // ⚠️ **必须叠在列表之上，不能取代它** —— 取代它会让
                  // `PageGridView` 不被构建，而它内部的
                  // `EasyRefresh(refreshOnStart: true)` 正是首次进入时
                  // 唯一拉数据的入口。一旦被跳过，`refreshOnStart` 永不触发，
                  // 页面首次进入就永远停在空态、只能靠手动点刷新
                  // （2026-09-15 实测踩过，见 memory）。
                  //
                  // 只在「有搜索词」时提示：列表真的空是「还没加载完」，
                  // 那种情况由 `PageGridView` 自己的空态/加载浮层负责。
                  //
                  // ⚠️ 必须同时排除「正在加载」：首次进入的 refreshOnStart
                  // 与下拉刷新都会先清空 list 再拉，只判空会在刷新过程中
                  // 闪现这条提示（还可能和加载浮层叠在一起）。
                  // 列表本身为空时也不提示（空态交给 PageGridView）。
                  if (live.isEmpty &&
                      offline.isEmpty &&
                      !controller.pageLoadding.value &&
                      controller.list.isNotEmpty &&
                      controller.searchQuery.value.trim().isNotEmpty)
                    const Center(child: Text("没有匹配的关注")),
                ],
              ),
            );
          },
        ),
        // 快速重组首次提示条（设计稿）：有勾选且没点过「知道了」才出现。
        // 操作入口在选择态顶栏（✕ / 已选择 N 位 / 一键成组），这里只做讲解。
        Obx(() {
          if (controller.selectedIds.isEmpty ||
              controller.selectHintDismissed) {
            return const SizedBox.shrink();
          }
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.inverseSurface,
            // 竖屏 extendBody 时让出悬浮底栏高度（同原操作栏的注释）。
            child: Padding(
              padding: EdgeInsets.only(
                bottom: PageGridView.floatingBarInsetOf(context),
              ),
              child: Padding(
                padding: AppStyle.edgeInsetsH12.copyWith(top: 4, bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "点击头像勾选主播，点击其他区域进入直播间",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onInverseSurface,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: controller.dismissSelectHint,
                      child: Text(
                        "知道了",
                        style: TextStyle(color: scheme.onInverseSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// 「直播中」视图的段：卡片网格。
  List<PageGridSection> _liveSections(List<FollowUser> live, int c) {
    return [
      GridSection(
        header: _SectionHeader(live: true, count: live.length),
        crossAxisCount: c,
        itemExtent: PageGridView.kDefaultItemExtent,
        itemCount: live.length,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        itemBuilder: (_, i) => _buildLiveCard(live[i]),
      ),
    ];
  }

  /// 「未开播」视图的段：紧凑行。这里没有分组卡片可拖，行不带状态点（整段都是灰点，
  /// 纯噪音）也不可拖拽。
  List<PageGridSection> _offlineSections(
      List<FollowUser> offline, int count, bool hide) {
    return [
      GridSection(
        header: _SectionHeader(
          live: false,
          count: offline.length,
          // 段头这句排序说明**必须反映真实的排序方式** ——
          // 设计稿写的是「按最近开播时间排序」，但 `SortMethod`
          // 里根本没有这一项，照抄就是在骗用户。
          sortLabel: controller.sortMap[controller.sortMethod.value],
        ),
        crossAxisCount: count,
        itemExtent: FollowMemberRow.rowExtent,
        itemCount: offline.length,
        mainAxisSpacing: 4,
        crossAxisSpacing: 12,
        itemBuilder: (_, i) {
          final u = offline[i];
          return Obx(
            () => FollowMemberRow(
              item: u,
              selected: controller.selectedIds.contains(u.id),
              onToggleSelect: () => controller.toggleSelected(u.id),
              onRemove: hide ? null : () => controller.removeFollow(u),
              onTap: () => _toDetail(u),
              onLongPress: () => controller.showBottomMenu(u),
            ),
          );
        },
      ),
    ];
  }

  /// 「全部」视图：每个标签一张可折叠分组卡片，拖头部可调序；
  /// 未分组的走紧凑行列在卡片下方，未分组段头是「拖出分组」的落点、也可折叠。
  List<PageGridSection> _buildGroupedSections(int count, bool hide) {
    final grouped = controller.groupedView;
    final searching = controller.searchQuery.value.trim().isNotEmpty;
    // 折叠集合必须在这里（Obx 构建窗口内）读一次 —— itemBuilder 是 sliver
    // 惰性调用的，那时 `RxInterface.proxy` 已经为 null，读 RxSet 不会登记订阅，
    // 点折叠箭头就永远等不来重建。
    final collapsed = Set<String>.of(controller.collapsedGroups);
    final sections = <PageGridSection>[];
    if (grouped.groups.isNotEmpty) {
      sections.add(BoxSection(
        child: ReorderableListView.builder(
          shrinkWrap: true,
          // 外层已有滚动（PageGridView 的 CustomScrollView），这里只负责
          // 重排手势、不滚。与分组管理 sheet 同范式同理由。
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: grouped.groups.length,
          // 注意：material_ui 的 onReorderItem 收到的 newIndex 已按删除旧位置
          // 校正过，FollowUserController.reorderTag / FollowService.reorderFollowTag
          // 里都不许再 -1。
          onReorderItem: (int oldIndex, int newIndex) =>
              controller.reorderTag(oldIndex, newIndex),
          itemBuilder: (context, i) {
            final g = grouped.groups[i];
            // 卡片间距垫在 item 自己身上（末段与下一段之间还有段间距 12）。
            return Padding(
              key: ValueKey(g.tag.id),
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: FollowGroupCard(
                group: g,
                collapsed: collapsed.contains(g.tag.id),
                // 搜索时空组被过滤掉了，卡片序号与标签序号对不上，禁调序。
                reorderIndex: searching ? null : i,
                memberColumns: count,
                onToggleCollapsed: () =>
                    controller.toggleGroupCollapsed(g.tag.id),
                onRename: () => FollowTagManagerController.shared
                    .editTagDialog("重命名分组", followUserTag: g.tag),
                onDropMember: (u) => controller.setFollowTag(u, g.tag),
                onMemberTap: _toDetail,
                onMemberLongPress: (u) => controller.showBottomMenu(u),
                onMemberRemove:
                    hide ? null : (u) => controller.removeFollow(u),
                selectedIds: controller.selectedIds,
                onToggleSelect: (u) => controller.toggleSelected(u.id),
              ),
            );
          },
        ),
      ));
    }
    final ungroupedCollapsed = collapsed.contains(_kUngroupedKey);
    // 勾选数在这里（Obx 窗口内）算好再传下去，段头保持纯展示。
    final ungroupedSelectedCount = grouped.ungrouped
        .where((u) => controller.selectedIds.contains(u.id))
        .length;
    if (!searching || grouped.ungrouped.isNotEmpty) {
      sections.add(BoxSection(
        child: _UngroupedSection(
          members: grouped.ungrouped,
          selectedCount: ungroupedSelectedCount,
          hasGroups: grouped.groups.isNotEmpty,
          collapsed: ungroupedCollapsed,
          columns: count,
          hideRemove: hide,
          selectedIds: controller.selectedIds,
          onToggle: () => controller.toggleGroupCollapsed(_kUngroupedKey),
          onDrop: (u) => controller.setFollowTag(u, controller.tagList.first),
          onToggleSelect: (u) => controller.toggleSelected(u.id),
          onMemberTap: _toDetail,
          onMemberLongPress: (u) => controller.showBottomMenu(u),
          onRemove: (u) => controller.removeFollow(u),
        ),
      ));
    }
    return sections;
  }

  /// 未分组段折叠态在 `collapsedGroups` 里的哨兵 key。
  ///
  /// 自定义标签 id 由 fractional indexing 生成（字母开头、至少两位），
  /// 不会撞上这个值。
  static const String _kUngroupedKey = "ungrouped";

  /// 段头高度。紧凑行视图与未分组段头共用这一个值。
  static const double _kSectionHeaderHeight = 34;

  void _toDetail(FollowUser item) {
    AppNavigator.toLiveRoomDetail(
      site: Sites.allSites[item.siteId]!,
      roomId: item.roomId,
    );
  }

  /// 「直播中」视图的卡面。
  ///
  /// **不挂取关按钮、也不带累计观看时长**（用户要求）：卡面只负责吸引点击进直播间，
  /// 「时长统计」与「取关」两件事统一收在紧凑行里。所以这里既不传
  /// `watchDurationSec`，也不传 `onFollowRemove` —— 直播中的主播要取关，
  /// 走「点卡片 → 直播间 → 取消关注」。
  Widget _buildLiveCard(FollowUser item) {
    final site = Sites.allSites[item.siteId]!;
    return LiveRoomCard(
      site,
      LiveRoomItem(
        roomId: item.roomId,
        title: item.title.value,
        cover: item.cover.value,
        userName: item.userName,
        online: item.online.value,
      ),
      onLongPress: () => controller.showBottomMenu(item),
    );
  }
}

/// 段头：状态圆点 + 「正在直播 / 未开播」+ 计数。
class _SectionHeader extends StatelessWidget {
  final bool live;
  final int count;

  /// 未开播那段的排序说明。传**当前真实**的排序方式
  /// （`FollowUserController.sortMap[sortMethod]`），不要照抄设计稿的
  /// 「按最近开播时间排序」—— `SortMethod` 里没有这一项。
  final String? sortLabel;
  const _SectionHeader({
    required this.live,
    required this.count,
    this.sortLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: FollowUserPage._kSectionHeaderHeight,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: live ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          AppStyle.hGap8,
          Text(
            live ? "正在直播" : "未开播",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
          AppStyle.hGap8,
          Expanded(
            child: Text(
              live
                  ? "$count 个直播间正在播出"
                  : "$count 位主播，按${sortLabel ?? "默认方式"}排序",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「全部」视图里的未分组段：整段（段头 + 成员行）是一个「拖出分组」落点。
///
/// 之前只有段头那一条固定高度是 `DragTarget`，把成员拖到未分组的**行**上不会
/// 移出；现在整块包进一个 `DragTarget`，悬停段头或任一成员行都会高亮整块并接收。
/// 段头点击仍是折叠开关；折叠 / 空态时只剩段头，落点依旧覆盖整块。
class _UngroupedSection extends StatelessWidget {
  final List<FollowUser> members;

  /// 未分组里已勾选的人数（设计稿「· 已选 X 位」）。
  final int selectedCount;
  final bool hasGroups;
  final bool collapsed;
  final int columns;
  final bool hideRemove;
  final RxSet<String> selectedIds;
  final VoidCallback onToggle;
  final ValueChanged<FollowUser> onDrop;
  final ValueChanged<FollowUser> onToggleSelect;
  final ValueChanged<FollowUser> onMemberTap;
  final ValueChanged<FollowUser> onMemberLongPress;
  final ValueChanged<FollowUser> onRemove;

  const _UngroupedSection({
    required this.members,
    required this.selectedCount,
    required this.hasGroups,
    required this.collapsed,
    required this.columns,
    required this.hideRemove,
    required this.selectedIds,
    required this.onToggle,
    required this.onDrop,
    required this.onToggleSelect,
    required this.onMemberTap,
    required this.onMemberLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<FollowUser>(
      onWillAcceptWithDetails: (details) => details.data.tag != "全部",
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius8,
            border: Border.all(
              color: highlighted ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
            color: highlighted
                ? scheme.primary.withValues(alpha: 0.08)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scheme, highlighted),
              if (!collapsed && members.isNotEmpty)
                GridView.count(
                  padding: const EdgeInsets.only(bottom: 8),
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  // 外层 PageGridView 已有滚动，这里只把成员摆成多列。
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisExtent: FollowMemberRow.rowExtent,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 12,
                  children: [
                    for (final u in members)
                      // 勾选态在惰性构建里读，必须自带 Obx（同分组卡片成员行）。
                      Obx(
                        () => FollowMemberRow(
                          item: u,
                          liveRing: true,
                          draggable: hasGroups,
                          selected: selectedIds.contains(u.id),
                          onToggleSelect: () => onToggleSelect(u),
                          onRemove: hideRemove ? null : () => onRemove(u),
                          onTap: () => onMemberTap(u),
                          onLongPress: () => onMemberLongPress(u),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme scheme, bool highlighted) {
    return SizedBox(
      height: FollowUserPage._kSectionHeaderHeight,
      child: InkWell(
        borderRadius: AppStyle.radius8,
        onTap: onToggle,
        child: Row(
          children: [
            AppStyle.hGap4,
            AnimatedRotation(
              // 展开时朝下、折叠时朝右，与分组卡片箭头一致。
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: highlighted
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
            AppStyle.hGap8,
            Text(
              "未分组",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            AppStyle.hGap8,
            Text(
              selectedCount > 0
                  ? "${members.length} 位主播 · 已选 $selectedCount 位"
                  : "${members.length} 位主播",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (hasGroups)
              Expanded(
                child: Padding(
                  padding: AppStyle.edgeInsetsH12,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "拖到这里移出分组",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部的 3 个内置 tab：**视图切换**（不再是滚动锚点）。
///
/// 全部 = 分组文件夹视图；直播中 = 卡片网格；未开播 = 紧凑行。
///
/// 直接用 [TabBar]（与首页平台 Tab 同一套机制）：指示器由 TabBar 自己跟随
/// [TabController] 绘制，天然与 body 的 `TabBarView` 同步 —— 手算下划线位置会
/// 和 TabBarView 的实际页码对不上（踩过），交给 TabBar 画才是对的。
class _ViewSwitchBar extends StatelessWidget {
  final FollowUserController controller;

  /// `[全部, 直播中, 未开播]` 三个计数。
  final List<int> counts;

  const _ViewSwitchBar({
    required this.controller,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    // 计数由父级 Obx 读 liveSection/offlineSection 后传进来，选中态由 TabBar
    // 自己跟随 TabController 画 —— 本组件不再需要自己的 Obx（读不到任何 Rx，
    // 硬包一层 GetX 会直接抛「没有可观察变量」）。
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: controller.tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            for (var i = 0; i < FollowUserController.builtinTags.length; i++)
              Tab(
                height: 44,
                child: Text(
                  "${FollowUserController.builtinTags[i]} ${counts[i]}",
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        AppStyle.divider,
      ],
    );
  }
}
