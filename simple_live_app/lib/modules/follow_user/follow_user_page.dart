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
    // 收起搜索只给 ← 按钮，不抢系统返回键：本页被 `KeepAliveWrapper` 保活，
    // 切到别的 Tab 之后仍然挂在树里，`PopScope` 会连别的 Tab 的返回键一起吃掉。
    return CollapsibleTopBarScaffold(
      appBar: _buildAppBar(iconButtonStyle),
      body: _buildBody(context, count, c),
    );
  }

  /// 顶栏搜索展开/收起的时长与曲线。
  ///
  /// 三个槽位（leading / title / actions）共用同一份，展开才像「一个动作」
  /// 而不是三处各跳一下。曲线沿用本页折叠卡片与顶栏收起的口径。
  static const Duration _kSearchAnim = Duration(milliseconds: 280);
  static const Curve _kSearchIn = Curves.easeOutCubic;
  static const Curve _kSearchOut = Curves.easeInCubic;

  /// leading 里单个图标的占位宽度。普通态并排两个图标（刷新 + 展开/折叠）。
  static const double _kLeadingSlotWidth = 96;

  /// leading 左侧留白。
  ///
  /// `leadingWidth` 放宽后 leading 内容整体贴左（不再被 `Center` 居中），只隔着
  /// 按钮自己那点内衬，横屏时几乎贴住左侧导航栏；补这一段回到 Material 惯例。
  static const double _kLeadingInset = 8;

  static const double _kLeadingWidth = _kLeadingInset + _kLeadingSlotWidth;

  /// leading 里一个状态的外壳：**定宽** + 内容贴左，key 交给 `AnimatedSwitcher`。
  ///
  /// `AnimatedSwitcher` 内部那个 Stack 取最宽子项做尺寸、对齐写死居中：普通态是
  /// 两个图标（96），选择态只有一个 ✕（48）。不统一宽度的话，过渡途中 Stack 仍
  /// 按 96 宽布局，✕ 会被居中摆在两个图标中间，等过渡结束才跳回左端。
  Widget _leadingSlot(String key, Widget child) {
    return SizedBox(
      key: ValueKey(key),
      width: _kLeadingSlotWidth,
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  /// 顶栏槽位的通用切换：淡入淡出 + 沿水平方向滑一小段（纯 transform，
  /// 不改布局，所以不会牵动顶栏高度）。
  Widget _fadeSlideSlot(Widget child, {double from = 0.12}) {
    return AnimatedSwitcher(
      duration: _kSearchAnim,
      switchInCurve: _kSearchIn,
      switchOutCurve: _kSearchOut,
      transitionBuilder: (inner, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          // 同一条动画驱动进出：入站时 from→0（从那一侧滑进来），
          // 出站时 0→from（往同一侧滑出去），整组像是被推让开的。
          position: Tween(begin: Offset(from, 0), end: Offset.zero)
              .animate(animation),
          child: inner,
        ),
      ),
      child: child,
    );
  }

  /// 顶栏：标题 + 刷新按钮 + 搜索 + 排序 + 更多菜单（含分组管理）。
  ///
  /// 搜索是**图标 + 原位展开**：点右侧 🔍 后，title 槽位换成胶囊输入框（从右边缘
  /// 长出来）、右侧整排图标让位；胶囊的外观与交互照搬搜索页，返回键收在胶囊内部
  /// （见 [_buildSearchField]）—— 不再叠一个常驻的搜索行在 tab 上方，那一行平时
  /// 不提供任何信息，却常年吃掉一格高度。
  /// 顶栏高度必须恒等于 `preferredSize`（`CollapsibleTopBarScaffold` 拿它换算
  /// 收起比例），所以宽度过渡只发生在 title 槽位内部，整体高度一帧都不变。
  ///
  /// 有勾选时进入选择态（设计稿）：leading 变 ✕（清空选择）、标题变
  /// 「已选择 N 位」、排序按钮换成「编辑」主色胶囊；此时不给搜索入口。
  /// 分组管理入口按设计稿收进右侧 ⋮ 弹层，不再占一个独立图标；
  /// 刷新按钮保留（设计稿没画，但去掉是功能倒退）。
  /// 玻璃胶囊不做：本页顶栏是随滚动收起的 `CollapsibleTopBarScaffold` AppBar，
  /// 玻璃机制（`liquid_glass_nav_defaults.dart`）只服务悬浮导航栏。
  PreferredSizeWidget _buildAppBar(ButtonStyle iconButtonStyle) {
    return AppBar(
      // 普通态 leading 要并排放两个图标（刷新 + 一键展开/折叠全部分组），
      // 默认的 56 只够一个，放到 [_kLeadingWidth]（左内边距 + 两个图标位）。
      // 标题居中（`AppBarTheme.centerTitle`），且 `NavigationToolbar` 会在居中
      // 位置撞到 leading 时把标题右移，不会重叠。
      leadingWidth: _kLeadingWidth,
      title: Obx(
        // 胶囊从右边缘（🔍 图标所在的位置）横向长出来，标题原地淡出 ——
        // 视觉上就是「那个图标被拉成了输入框」。宽度只在 title 槽位内部变，
        // 顶栏高度恒定，所以不违反 `CollapsibleTopBarScaffold` 的收起前提。
        () => AnimatedSwitcher(
          duration: _kSearchAnim,
          switchInCurve: _kSearchIn,
          switchOutCurve: _kSearchOut,
          transitionBuilder: (inner, animation) =>
              // 只有输入框吃宽度过渡；标题文字只淡出 —— 一起裁的话字会被
              // 逐帧切掉半截，看着像被擦掉而不是让位。
              inner.key == const ValueKey('title')
                  ? FadeTransition(opacity: animation, child: inner)
                  // 不能直接用 `SizeTransition`：它本质是**直角** `ClipRect`
                  // （框架文档原话），胶囊从右往左长出来时左端会被切成一条直边，
                  // 与右端自己的圆角不对称。这里换成圆角裁剪，半径与输入框的
                  // 胶囊一致，几何与时长不变。
                  : AnimatedBuilder(
                      animation: animation,
                      builder: (_, child) => ClipRRect(
                        borderRadius: AppStyle.radius24,
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: animation.value,
                          child: child,
                        ),
                      ),
                      child: FadeTransition(opacity: animation, child: inner),
                    ),
          child: controller.searchExpanded.value
              ? _buildSearchField(iconButtonStyle)
              // 只读 searchExpanded 与 selectedIds，输入过程不重建这一层；
              // 否则光标与输入法组合态会丢。
              : Text(
                  key: const ValueKey('title'),
                  controller.selectedIds.isEmpty
                      ? "关注用户"
                      : "已选择 ${controller.selectedIds.length} 位",
                ),
        ),
      ),
      actions: [
        // 整组右侧图标一起让位（淡出 + 向右滑），而不是三个各自消失。
        // key 跟着状态走，所以「普通态 → 选择态」也是交叉淡入淡出而非硬切。
        Obx(() {
          final expanded = controller.searchExpanded.value;
          final selecting = controller.selectedIds.isNotEmpty;
          final actions = _fadeSlideSlot(
            KeyedSubtree(
              key: ValueKey(
                  '${expanded ? 'x' : 'c'}${selecting ? 's' : 'n'}'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 搜索入口。展开态让位给输入框；选择态不给（leading 已经是
                  // 退出选择的 ✕，同屏两个返回控件没意义）。
                  if (!expanded && !selecting)
                    IconButton(
                      style: iconButtonStyle,
                      tooltip: "搜索",
                      onPressed: controller.openSearch,
                      icon: const Icon(Icons.search),
                    ),
                  if (!expanded)
                    // 选择态：编辑；普通态：排序 dialog。
                    (selecting
                        ? Padding(
                            padding: AppStyle.edgeInsetsV8.copyWith(right: 4),
                            child: FilledButton.icon(
                              onPressed: controller.showQuickGroupDialog,
                              icon: const Icon(Remix.folder_add_line, size: 18),
                              label: const Text("编辑"),
                            ),
                          )
                        : IconButton(
                            style: iconButtonStyle,
                            tooltip: "排序方式",
                            icon: const Icon(Remix.sort_asc),
                            onPressed: controller.showSortDialog,
                          )),
                  if (!expanded)
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
              ),
            ),
          );
          // 让位不只是淡出：宽度也要一起收回，见 [_SlotWidthCollapse]。
          return _SlotWidthCollapse(visible: !expanded, child: actions);
        }),
      ],
      leading: Obx(() {
        // 搜索态的返回键收在胶囊内部（见 [_buildSearchField]），所以这里只剩
        // 「选择态 ✕」与「普通态刷新 + 展开/折叠」两种；两者都用 [_leadingSlot]
        // 统一宽度，切换时不位移。
        final Widget slot;
        if (controller.selectedIds.isNotEmpty) {
          final close = IconButton(
            key: const ValueKey('close'),
            style: iconButtonStyle,
            tooltip: "退出选择",
            onPressed: controller.clearSelection,
            icon: const Icon(Icons.close),
          );
          slot = _leadingSlot('close', close);
        } else {
          // 普通态两个图标：刷新 + 一键展开/折叠全部分组。
          // 只有「全部」视图有分组卡片可折叠；关注列表也空时按钮没意义。
          final showFoldAll = controller.activeTab.value == 0 &&
              (controller.customTags.isNotEmpty || controller.list.isNotEmpty);
          final folded = controller.hasCollapsedGroups;
          final icons = Row(
            key: const ValueKey('normal'),
            mainAxisSize: MainAxisSize.min,
            children: [
              // 刷新 ⇄ 刷新中 仍按原来那样单独淡入淡出 —— 外面那层
              // `_fadeSlideSlot` 只负责「普通态 ⇄ 搜索/选择态」的整体切换。
              _fadeSlideSlot(
                FollowService.instance.updating.value
                    ? IconButton(
                        key: const ValueKey('refreshing'),
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
                        key: const ValueKey('refresh'),
                        style: iconButtonStyle,
                        tooltip: "刷新",
                        onPressed: () {
                          controller.refreshData();
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                from: -0.12,
              ),
              if (showFoldAll)
                IconButton(
                  key: const ValueKey('fold-all'),
                  style: iconButtonStyle,
                  tooltip: folded ? "展开全部分组" : "折叠全部分组",
                  onPressed: controller.toggleAllGroupsCollapsed,
                  icon: Icon(folded ? Icons.unfold_more : Icons.unfold_less),
                ),
            ],
          );
          slot = _leadingSlot('normal', icons);
        }
        // ↻ 与 ✕ 一律从左侧进出，方向固定才对称：不能只在切换的那一趟带位移。
        return Padding(
          padding: const EdgeInsets.only(left: _kLeadingInset),
          child: _fadeSlideSlot(slot, from: -0.12),
        );
      }),
    );
  }

  /// 展开态占在顶栏 title 槽位上的胶囊搜索框。
  ///
  /// 外观与交互照搬搜索页的顶栏输入框（`search_page.dart`），只去掉关注页没有的
  /// 「房间 / 主播」切换。返回键收进胶囊**内部**：它不再占 leading 槽位，也就没有
  /// 「← 与输入框之间空一截」「左侧图标被挤」这类问题。
  ///
  /// `autofocus`：点图标就是要输入，不再多跳一次「点一下输入框」。
  /// 外层 `Obx` 只读 `searchExpanded`，输入过程不会重建这一层。
  Widget _buildSearchField(ButtonStyle iconButtonStyle) {
    return TextField(
      key: const Key('follow-search-field'),
      controller: controller.searchController,
      autofocus: true,
      onChanged: (v) => controller.searchQuery.value = v,
      decoration: InputDecoration(
        hintText: "搜索关注的主播",
        border: OutlineInputBorder(borderRadius: AppStyle.radius24),
        contentPadding: AppStyle.edgeInsetsH12,
        prefixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              style: iconButtonStyle,
              tooltip: "收起搜索",
              onPressed: controller.closeSearch,
              icon: const Icon(Icons.arrow_back),
            ),
            AppStyle.hGap8,
          ],
        ),
        // 清空按钮：有内容时才出现。只把这一小块包进 Obx，理由同上。
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
      ),
    );
  }

  Widget _buildBody(BuildContext context, int count, int c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    final ungroupedCollapsed = collapsed.contains(
      FollowUserController.kUngroupedKey,
    );
    // 勾选数与在播数在这里（Obx 窗口内）算好再传下去，段头保持纯展示。
    final ungroupedSelectedCount = grouped.ungrouped
        .where((u) => controller.selectedIds.contains(u.id))
        .length;
    final ungroupedLiveCount = grouped.ungrouped
        .where((u) => u.liveStatus.value == 2)
        .length;
    if (!searching || grouped.ungrouped.isNotEmpty) {
      sections.add(BoxSection(
        child: _UngroupedSection(
          members: grouped.ungrouped,
          liveCount: ungroupedLiveCount,
          selectedCount: ungroupedSelectedCount,
          hasGroups: grouped.groups.isNotEmpty,
          collapsed: ungroupedCollapsed,
          columns: count,
          hideRemove: hide,
          selectedIds: controller.selectedIds,
          onToggle: () => controller.toggleGroupCollapsed(
            FollowUserController.kUngroupedKey,
          ),
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

/// 让顶栏某个槽位的**宽度**随状态收放（纯绘制，不碰顶栏高度）。
///
/// 右侧那排图标让位时不能只淡出：`AnimatedSwitcher` 会把退场的那一份一直留在
/// 布局里（内部 Stack 取最宽子项），于是宽度要等整段过渡结束才还给 title 槽位，
/// 而搜索框的 `SizeTransition` 同时长跑完 —— 它先长满「被挤窄的宽度」，紧接着
/// 一帧内被迫变宽，看着就是闪一下。
///
/// 曲线与 title 槽位同源：让位时 easeOutCubic 尽早腾地方，让回来时 easeInCubic
/// 等对方先缩走。
class _SlotWidthCollapse extends StatelessWidget {
  /// true = 恢复自身宽度；false = 收到 0 宽（让位）。
  final bool visible;

  final Widget child;

  const _SlotWidthCollapse({
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1.0 : 0.0),
      duration: FollowUserPage._kSearchAnim,
      curve: visible ? FollowUserPage._kSearchOut : FollowUserPage._kSearchIn,
      builder: (_, factor, inner) => ClipRect(
        child: Align(
          // 贴右边缘收放：图标本来就是朝右边退场的，宽度也朝右收才自然。
          alignment: Alignment.centerRight,
          widthFactor: factor,
          child: inner,
        ),
      ),
      child: child,
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

  /// 未分组里正在直播的人数（与 [selectedCount] 同在 Obx 窗口内算好传入）。
  final int liveCount;

  /// 未分组里已勾选的人数（段头「· 已选 X」）。
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
    required this.liveCount,
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
            // 与分组卡片同一口径 `● N/M 在播`：原来只写「M 位主播」，
            // 把在播信息整个丢了，两套口径并排看着像漏改。
            FollowCountLabel(
              live: liveCount,
              total: members.length,
              selected: selectedCount,
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
