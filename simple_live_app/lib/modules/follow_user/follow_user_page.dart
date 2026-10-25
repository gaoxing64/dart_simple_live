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
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
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
    // 关注页上所有圆形图标按钮（顶栏刷新 / 顶栏分组管理 / 顶栏排序 / 顶栏更多菜单 /
    // 搜索框清空 / 行尾取关）共用这一份规格，hover 与按压反馈因此完全一致。
    // 为什么不放进主题统一给：见 `AppStyle.iconButtonStyle` 的注释。
    final iconButtonStyle = AppStyle.iconButtonStyle(
      Theme.of(context).colorScheme,
    );
    final page = CollapsibleTopBarScaffold(
      appBar: _buildAppBar(iconButtonStyle),
      // 侧栏宽度由它自己的内容决定（见 [FollowSidebar]），列数不能在这层
      // 用「整窗宽 - 固定侧栏宽」算；把可用宽度传下去，由内容列在剩余空间
      // 里自己量（见 [_buildBody]）。
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = FollowSidebar.isCompact(constraints.maxWidth);
          return _buildBody(context, constraints.maxWidth, compact);
        },
      ),
    );
    // 搜索展开时，系统返回 / 鼠标侧键先收起搜索。
    // 必须同时限定关注页当前可见：本页被 KeepAlive 保活，切到别的 Tab 后仍
    // 在树上，无条件 PopScope 会吞掉其他 Tab 的返回操作。
    return Obx(() {
      final intercept = controller.isPageActive.value && controller.searchExpanded.value;
      return PopScope(
        key: const ValueKey('follow-back-scope'),
        canPop: !intercept,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && controller.searchExpanded.value) {
            controller.closeSearch();
          }
        },
        child: page,
      );
    });
  }

  /// 顶栏搜索展开/收起的时长与曲线。
  ///
  /// 三个槽位（leading / title / actions）共用同一份，展开才像「一个动作」
  /// 而不是三处各跳一下。曲线沿用本页折叠卡片与顶栏收起的口径。
  static const Duration _kSearchAnim = Duration(milliseconds: 280);
  static const Curve _kSearchIn = Curves.easeOutCubic;
  static const Curve _kSearchOut = Curves.easeInCubic;

  /// leading 状态槽的宽度。普通态只有刷新、选择态只有 ✕；
  /// 保留原两图标槽的视觉留白，切换时不位移。
  static const double _kLeadingSlotWidth = 96;

  /// leading 左侧留白。
  ///
  /// `leadingWidth` 放宽后 leading 内容整体贴左（不再被 `Center` 居中），只隔着
  /// 按钮自己那点内衬，横屏时几乎贴住左侧导航栏；补这一段回到 Material 惯例。
  static const double _kLeadingInset = 8;

  static const double _kLeadingWidth = _kLeadingInset + _kLeadingSlotWidth;

  /// leading 里一个状态的外壳：**定宽** + 内容贴左，key 交给 `AnimatedSwitcher`。
  ///
  /// `AnimatedSwitcher` 内部那个 Stack 取最宽子项做尺寸、对齐写死居中：普通态
  /// 与选择态图标数不同（刷新 / ✕）。不统一宽度的话，过渡途中 Stack 仍按
  /// 槽宽布局，✕ 会被居中摆放，等过渡结束才跳回左端。
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
          position: Tween(begin: Offset(from, 0), end: Offset.zero).animate(animation),
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
  /// 刷新按钮只在普通态保留；搜索展开时返回键在胶囊内部，leading 整槽收起。
  /// 顶栏随滚动收起，顶栏不做玻璃/形变效果：底部 dock 的那套形变只服务
  /// 底栏自身（见 [NavigationDock]），套到会随滚动改变高度的 AppBar 上会打架。
  PreferredSizeWidget _buildAppBar(ButtonStyle iconButtonStyle) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Obx(() {
        // 搜索展开且未进入选择态时，返回键在胶囊内部，leading 没有存在意义；
        // 一旦有勾选仍要保留退出选择的 ✕，所以这里不是只看 searchExpanded。
        final collapseLeading = controller.searchExpanded.value && controller.selectedIds.isEmpty;
        return _buildAppBarContent(iconButtonStyle, collapseLeading);
      }),
    );
  }

  /// 顶栏本体；[collapseLeading] 为 true 时 leading 槽位与刷新按钮一起收起。
  Widget _buildAppBarContent(ButtonStyle iconButtonStyle, bool collapseLeading) {
    return AppBar(
      // 普通态 leading 放刷新，选择态放 ✕；搜索展开时返回键在胶囊内部，
      // leadingWidth 直接收成 0，把整条顶栏让给输入框。
      // 标题居中（`AppBarTheme.centerTitle`），且 `NavigationToolbar` 会在居中
      // 位置撞到 leading 时把标题右移，不会重叠。
      leadingWidth: collapseLeading ? 0 : _kLeadingWidth,
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
                  controller.selectedIds.isEmpty ? "关注用户" : "已选择 ${controller.selectedIds.length} 位",
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
              key: ValueKey('${expanded ? 'x' : 'c'}${selecting ? 's' : 'n'}'),
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
                    // 选择态：两个动作直接外显（移入分组 / 多开播放）；普通态：排序。
                    // 都只留图标 + tooltip —— 原来那个「编辑」文案不明所以；去掉文案
                    // 正好腾出宽度，让「多开播放」不必再藏进 ⋮ 菜单里。
                    (selecting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                style: iconButtonStyle,
                                tooltip: "移入分组",
                                onPressed: controller.showQuickGroupDialog,
                                icon: const Icon(Remix.folder_add_line),
                              ),
                              IconButton(
                                style: iconButtonStyle,
                                tooltip: "多开播放",
                                onPressed: controller.openMultiPlayFromSelection,
                                icon: const Icon(Remix.play_circle_line),
                              ),
                            ],
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
                        return [
                          const AppPopupMenuItem(
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
                          // 「模式切换」全局可见：直播中 / 未开播两页与
                          // 平台 / 分组平铺都读同一个布局设置，不再有
                          // 「文件夹总览下点了没意义」的筛选态限制。
                          const AppPopupMenuItem(
                            value: 1,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Remix.blender_line),
                                AppStyle.hGap12,
                                Text("模式切换"),
                              ],
                            ),
                          ),
                          const AppPopupMenuItem(
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
                          const AppPopupMenuItem(
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
                        } else if (value == 1) {
                          controller.showFollowStyleDialog();
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
        // 搜索态的返回键收在胶囊内部（见 [_buildSearchField]），搜索展开且
        // 未勾选时 leading 整槽（连同刷新按钮）收起；有勾选则保留退出选择的 ✕。
        if (collapseLeading) {
          return const SizedBox.shrink();
        }
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
          // 普通态只有一个图标：刷新。文件夹总览（可折叠分组卡片）已随
          // 二级菜单导航移除，一键展开/折叠没有对象可用了。
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

  /// 三栏布局的第二、三栏：竖排标签侧栏 + 内容列表。
  ///
  /// 侧栏**始终显示**：竖屏时底部导航栏占的是底部，左边只此一栏；宽度由
  /// 标签内容决定（[FollowSidebar] 自己量），长分组名到上限后省略截断。
  /// 内容列的列数必须在**扣掉侧栏后的剩余宽度**里算：`MediaQuery` 的整窗宽
  /// 会把侧栏占掉的那一截也算进去，宽窗口会少算一档。
  /// （第一栏是外壳的 NavigationRail / 底部导航，不归本页管。）
  Widget _buildBody(BuildContext context, double availableWidth, bool compact) {
    return Row(
      // 侧栏高度只占内容本身（不再是 Expanded 撑满），不 stretch 会被 Row
      // 按交叉轴居中，整栏浮在页面中段而不是从顶部往下排。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => FollowSidebar(
            availableWidth: availableWidth,
            compact: compact,
            items: controller.sidebarItems,
            selectedKey: controller.activeSidebarKey,
            onSelect: controller.selectSidebarItem,
          ),
        ),
        // 二级菜单与内容之间**不画分割线**：菜单项的强调线与留白已经够了，
        // 再插一根竖线反而把内容区切碎。
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              var count = width ~/ 500;
              if (count < 1) count = 1;
              // 卡片模式仍以 2 列为下限：手机竖屏一律两列，保证一屏能看
              // 足够多的直播间（1 列大卡实测太宽、效率低）。窄屏的宽度
              // 让给「紧凑侧栏」——它在两字模式下连计数一起收起。
              var c = width ~/ 200;
              if (c < 2) {
                c = 2;
              }
              return Obx(
                () {
                  final hide = AppSettingsController.instance.hideRemoveFollowButton.value;
                  final live = controller.liveSection;
                  final offline = controller.offlineSection;
                  // 本帧所有卡片 / 行共用同一份分组名映射。必须在这里（Obx
                  // 构建窗口内）读，分组增删改 / 调序后侧栏与内容一起重建。
                  final groupNames = controller.groupNamesByFollowId;
                  // 筛选态的空态判据：选中了某个平台 / 分组、但过滤后没有成员。
                  // 在 Obx 构建窗口内读 hasActiveFilter / filteredMembers（内部读
                  // groupedView → list / tagList / liveStatus），筛选失效回落、
                  // 搜索词变化都会自动重算。
                  final filterEmpty = controller.hasActiveFilter && controller.filteredMembers.isEmpty;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 三页 ViewPager：侧栏在左，翻页走**纵轴**（与首页壳
                      // 「侧边栏在左就垂直滑动」同一约定）。
                      // 手势不参与：每页都是竖向滚动列表，再让纵向手势翻页会
                      // 和列表抢同一根轴；切换入口只有左侧第二栏。
                      PageView(
                        controller: controller.pageController,
                        scrollDirection: Axis.vertical,
                        physics: const NeverScrollableScrollPhysics(),
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
                              sections: _buildGroupedSections(count, c, hide, groupNames),
                            ),
                          ),
                          PageGridView(
                            pageController: controller,
                            padding: AppStyle.edgeInsetsA12,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            scrollOverride: controller.liveScrollController,
                            refreshOverride: controller.liveRefreshController,
                            sections: _liveSections(live, count, c, groupNames),
                          ),
                          PageGridView(
                            pageController: controller,
                            padding: AppStyle.edgeInsetsA12,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            scrollOverride: controller.offlineScrollController,
                            refreshOverride: controller.offlineRefreshController,
                            sections: _offlineSections(offline, count, c, hide, groupNames),
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
                      if ((filterEmpty || (live.isEmpty && offline.isEmpty)) &&
                          !controller.pageLoadding.value &&
                          controller.list.isNotEmpty &&
                          controller.searchQuery.value.trim().isNotEmpty)
                        const Center(child: Text("没有匹配的关注")),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// 「直播中」视图的段：卡片网格 / 紧凑行（随全局布局设置，见 [_liveSections]）。
  List<PageGridSection> _liveSections(
    List<FollowUser> live,
    int count,
    int c,
    Map<String, List<String>> groupNames,
  ) {
    final cardMode = AppSettingsController.instance.followStyleNotGrid.value == false;
    return [
      GridSection(
        header: _SectionHeader(live: true, count: live.length),
        crossAxisCount: cardMode ? c : count,
        itemExtent: cardMode ? PageGridView.kDefaultItemExtent : FollowMemberRow.rowExtent,
        itemCount: live.length,
        mainAxisSpacing: cardMode ? 12 : 4,
        crossAxisSpacing: 12,
        itemBuilder: (_, i) {
          final u = live[i];
          final groups = groupNames[u.id] ?? const <String>[];
          if (cardMode) {
            return _buildLiveCard(u, groups);
          }
          // 紧凑行也要能看出在播：头像描边圈 + 直播标题
          // （FollowMemberRow 自己会按 liveStatus 切副标题）。
          return Obx(() {
            final selected = controller.selectedIds.contains(u.id);
            return FollowMemberRow(
              item: u,
              // 进入选择态后全页展示标签，便于批量判断与多选。
              groupNames: controller.selectedIds.isNotEmpty ? groups : const [],
              draggable: false,
              selected: selected,
              onToggleSelect: () => controller.toggleSelected(u.id),
              onTap: () => _toDetail(u),
              onLongPress: () => controller.showBottomMenu(u),
            );
          });
        },
      ),
    ];
  }

  /// 「未开播」视图的段：紧凑行 / 卡片网格（随全局布局设置）。
  ///
  /// 紧凑行没有分组卡片可拖，行不带状态点（整段都是灰点，纯噪音）也不可拖拽。
  /// 卡片模式的封面 / 标题回退见 [_buildLiveCard]。
  List<PageGridSection> _offlineSections(
    List<FollowUser> offline,
    int count,
    int c,
    bool hide,
    Map<String, List<String>> groupNames,
  ) {
    final cardMode = AppSettingsController.instance.followStyleNotGrid.value == false;
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
        crossAxisCount: cardMode ? c : count,
        itemExtent: cardMode ? PageGridView.kDefaultItemExtent : FollowMemberRow.rowExtent,
        itemCount: offline.length,
        mainAxisSpacing: cardMode ? 12 : 4,
        crossAxisSpacing: 12,
        itemBuilder: (_, i) {
          final u = offline[i];
          final groups = groupNames[u.id] ?? const <String>[];
          if (cardMode) {
            return _buildLiveCard(u, groups);
          }
          return Obx(() {
            final selected = controller.selectedIds.contains(u.id);
            return FollowMemberRow(
              item: u,
              groupNames: controller.selectedIds.isNotEmpty ? groups : const [],
              selected: selected,
              onToggleSelect: () => controller.toggleSelected(u.id),
              onRemove: hide ? null : () => controller.removeFollow(u),
              onTap: () => _toDetail(u),
              onLongPress: () => controller.showBottomMenu(u),
            );
          });
        },
      ),
    ];
  }

  /// 「全部」页的段。
  ///
  /// 选中了某个平台 / 分组时平铺它的成员（[hasActiveFilter]，平台也算、
  /// 幽灵 id 不算）；否则平铺**全部**关注（顺序继承 [list]，直播优先）。
  ///
  /// 曾经的文件夹总览（一组一张可折叠卡片 + 未分组段）已随二级菜单导航移除：
  /// 分组改从第二栏的分组标签进，平铺列表与分组筛选共用一套渲染，
  /// 「全部」页也因此和别的页一样吃关注样式（紧凑 / 卡片）设置。
  List<PageGridSection> _buildGroupedSections(
    int count,
    int c,
    bool hide,
    Map<String, List<String>> groupNames,
  ) {
    if (controller.hasActiveFilter) {
      return _buildFilterSections(
        _filterLabel(controller.activeFilter.value!),
        controller.filteredMembers,
        count,
        c,
        hide,
        groupNames,
      );
    }
    return _buildFilterSections(
      FollowUserController.builtinTags[0],
      controller.visibleList,
      count,
      c,
      hide,
      groupNames,
    );
  }

  /// 筛选态段头上显示的名字：平台取平台名，分组取组名。
  ///
  /// 分组失效（被删 / 调序换 id）时回落空串：此时成员也是空表，
  /// 段头整段被 `PageGridView` 跳过（itemCount==0），不会露出空白标题。
  String _filterLabel(FollowFilter filter) {
    if (filter.kind == FollowSidebarKind.site) {
      return Sites.allSites[filter.id]?.name ?? filter.id;
    }
    return controller.activeGroup?.tag ?? '';
  }

  /// 「全部」页与平台 / 分组筛选共用的平铺段：一个 GridSection，成员不套文件夹卡片。
  ///
  /// 紧凑模式列数/行高与未开播紧凑行一致（[count] / [FollowMemberRow.rowExtent]）；
  /// 卡片模式与「直播中」页同口径（[c] 列 / [PageGridView.kDefaultItemExtent]），
  /// 直接复用 [_buildLiveCard] —— 勾选/长按行为与那一页一致（卡面同样不挂
  /// 取关按钮，要取关切回紧凑模式或进直播间）。
  ///
  /// 段头是 [label]（「全部」/ 平台名 / 组名）+「● N/M 在播」。
  List<PageGridSection> _buildFilterSections(
    String label,
    List<FollowUser> members,
    int count,
    int c,
    bool hide,
    Map<String, List<String>> groupNames,
  ) {
    final liveCount = members.where((u) => u.liveStatus.value == 2).length;
    final cardMode = AppSettingsController.instance.followStyleNotGrid.value == false;
    return [
      GridSection(
        header: _FilterHeader(label: label, live: liveCount, total: members.length),
        crossAxisCount: cardMode ? c : count,
        itemExtent: cardMode ? PageGridView.kDefaultItemExtent : FollowMemberRow.rowExtent,
        itemCount: members.length,
        mainAxisSpacing: cardMode ? 12 : 4,
        crossAxisSpacing: 12,
        itemBuilder: (_, i) {
          final u = members[i];
          final groups = groupNames[u.id] ?? const <String>[];
          if (cardMode) {
            return _buildLiveCard(u, groups);
          }
          return Obx(() {
            final selected = controller.selectedIds.contains(u.id);
            return FollowMemberRow(
              item: u,
              groupNames: controller.selectedIds.isNotEmpty ? groups : const [],
              // 平铺态没有分组卡片可拖，头像不起拖（换组走顶栏「移入分组」）。
              draggable: false,
              selected: selected,
              onToggleSelect: () => controller.toggleSelected(u.id),
              onRemove: hide ? null : () => controller.removeFollow(u),
              onTap: () => _toDetail(u),
              onLongPress: () => controller.showBottomMenu(u),
            );
          });
        },
      ),
    ];
  }

  /// 段头高度。紧凑行视图与平铺段头共用这一个值。
  static const double _kSectionHeaderHeight = 34;

  void _toDetail(FollowUser item) {
    AppNavigator.toLiveRoomDetail(
      site: Sites.allSites[item.siteId]!,
      roomId: item.roomId,
    );
  }

  /// 直播中 / 未开播视图共用的卡面（布局设置选「卡片模式」时）。
  ///
  /// **不挂取关按钮、也不带累计观看时长**（用户要求）：卡面只负责吸引点击进直播间，
  /// 「时长统计」与「取关」两件事统一收在紧凑行里。所以这里既不传
  /// `watchDurationSec`，也不传 `onFollowRemove` —— 直播中的主播要取关，
  /// 走「点卡片 → 直播间 → 取消关注」。
  ///
  /// 未开播的房间没有封面（接口只在直播中下发）：封面区改由 `avatar` 画成
  /// **圆形头像占位**，不再把头像拉满整块封面 —— 拉满和直播画面混在一起，
  /// 一眼分不出在播与否（内置逻辑见 `LiveRoomCard._AvatarCover`）。
  /// 直播中即便封面为空也保持原行为（走 logo 兜底），占位只服务未开播。
  /// 标题同理只在直播中才有，未开播兜底成「未开播」，避免和下方主播名重复。
  Widget _buildLiveCard(FollowUser item, List<String> groupNames) {
    final site = Sites.allSites[item.siteId]!;
    // 逐卡 Obx：勾选态的描边/光晕要靠它当场刷新（外层不会因勾选而重建）
    return Obx(
      () {
        final isLive = item.liveStatus.value == 2;
        final selected = controller.selectedIds.contains(item.id);
        return LiveRoomCard(
          site,
          LiveRoomItem(
            roomId: item.roomId,
            title: item.title.value.isEmpty && !isLive ? "未开播" : item.title.value,
            cover: item.cover.value,
            userName: item.userName,
            online: item.online.value,
          ),
          avatar: isLive ? '' : item.face,
          // 选择态下所有卡片都展示标签，未选中项也必须可比较。
          groupNames: controller.selectedIds.isNotEmpty ? groupNames : const [],
          onLongPress: () => controller.showBottomMenu(item),
          selected: selected,
          onToggleSelect: () => controller.toggleSelected(item.id),
        );
      },
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
              live ? "$count 个直播间正在播出" : "$count 位主播，按${sortLabel ?? "默认方式"}排序",
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

/// 平铺列表的段头：「全部」/ 平台名 / 组名 + 「● N/M 在播」。
class _FilterHeader extends StatelessWidget {
  final String label;
  final int live;
  final int total;

  const _FilterHeader({
    required this.label,
    required this.live,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: FollowUserPage._kSectionHeaderHeight,
      child: Row(
        children: [
          AppStyle.hGap4,
          // 窄列（侧栏占宽后）下标题 + 计数会超宽，标题要能缩。
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          AppStyle.hGap8,
          FollowCountLabel(live: live, total: total),
        ],
      ),
    );
  }
}

/// 段头右侧的计数：`● 3/4 在播`。
///
/// 圆点只在有在播成员时出现并取主题色，零在播就是灰字 `0/3 在播` —— 两种情况下
/// 这段文字的宽度都稳定，不会因为有组在播就把标题挤成省略号。
class FollowCountLabel extends StatelessWidget {
  final int live;
  final int total;

  const FollowCountLabel({
    required this.live,
    required this.total,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        children: [
          if (live > 0)
            TextSpan(
              text: '● ',
              style: TextStyle(fontSize: 10, color: scheme.primary),
            ),
          TextSpan(
            text: '$live/$total 在播',
            style: live > 0 ? TextStyle(color: scheme.primary) : null,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
