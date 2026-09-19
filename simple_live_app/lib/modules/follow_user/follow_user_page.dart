import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';
import 'package:simple_live_app/widgets/filter_button.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/net_image.dart';
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
    // 关注页上所有圆形图标按钮（顶栏刷新 / 顶栏更多菜单 / 搜索框清空 /
    // 下段行尾取关）共用这一份规格，hover 与按压反馈因此完全一致。
    // 为什么不放进主题统一给：见 `AppStyle.iconButtonStyle` 的注释。
    final iconButtonStyle = AppStyle.iconButtonStyle(
      Theme.of(context).colorScheme,
    );
    return CollapsibleTopBarScaffold(
      appBar: _buildAppBar(iconButtonStyle),
      body: _buildBody(iconButtonStyle, count, c),
    );
  }

  /// 顶栏：标题 + 刷新按钮 + 更多菜单。
  ///
  /// 之前直接 `Scaffold(appBar: AppBar(...))`，顶栏固定不可收起；现在改用
  /// [CollapsibleTopBarScaffold]，顶栏在「滑动收起」开启后跟随滑动收起/展开。
  PreferredSizeWidget _buildAppBar(ButtonStyle iconButtonStyle) {
    return AppBar(
      title: const Text("关注用户"),
      actions: [
        PopupMenuButton(
          style: iconButtonStyle,
          itemBuilder: (context) {
            // 用自己的 item：官方 `PopupMenuItem` 的 hover 高亮是满宽矩形，
            // 与菜单容器的大圆角对不上。详见 `AppPopupMenuItem`。
            return const [
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
                value: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Remix.sort_asc),
                    AppStyle.hGap12,
                    Text("按序排列"),
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
            } else if (value == 2) {
              controller.showSortDialog();
            }
          },
        ),
      ],
      leading: Obx(
        () => FollowService.instance.updating.value
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
              ),
      ),
    );
  }

  Widget _buildBody(
      ButtonStyle iconButtonStyle, int count, int c) {
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
        // 3 个内置标签（滚动锚点）+ 自定义标签（筛选）。要计数，所以在 Obx 里。
        Obx(() {
          final live = controller.liveSection.length;
          final offline = controller.offlineSection.length;
          return _AnchorTabBar(
            controller: controller,
            liveCount: live,
            counts: [live + offline, live, offline],
            // 直接复用 build 顶部算好的 c：_sectionTop(2) 的几何反推依赖
            // 这里的列数**必须等于**下段实际渲染的 GridSection.crossAxisCount，
            // 两份各写一份公式迟早会改漏一处。
            cardColumns: c,
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
                  KeepAliveWrapper(
                    child: PageGridView(
                      pageController: controller,
                      padding: AppStyle.edgeInsetsA12,
                      firstRefresh: true,
                      // 段与段之间的竖直间距；段内的行距由各段自己的
                      // mainAxisSpacing 管。
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      sections: [
                        // 上段：正在直播，走卡片网格。
                        GridSection(
                          header:
                              _SectionHeader(live: true, count: live.length),
                          crossAxisCount: c,
                          itemExtent: PageGridView.kDefaultItemExtent,
                          itemCount: live.length,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          itemBuilder: (_, i) => _buildLiveCard(live[i]),
                        ),
                        // 下段：未开播（含读取中），走紧凑行。列数沿用紧凑模式
                        // 原来的 width ~/ 500，行因此比上面的卡片宽。
                        GridSection(
                          header: _SectionHeader(
                            live: false,
                            count: offline.length,
                            // 段头这句排序说明**必须反映真实的排序方式** ——
                            // 设计稿写的是「按最近开播时间排序」，但 `SortMethod`
                            // 里根本没有这一项，照抄就是在骗用户。
                            sortLabel:
                                controller.sortMap[controller.sortMethod.value],
                          ),
                          crossAxisCount: count,
                          itemExtent: _kCompactRowExtent,
                          itemCount: offline.length,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 12,
                          itemBuilder: (_, i) =>
                              _buildOfflineRow(offline[i], hide),
                        ),
                      ],
                    ),
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

  /// 段头高度。**必须固定** —— 顶部锚点 tab 是按几何硬算滚动 offset 的，
  /// 段头一旦随内容撑开，offset 就不准了。
  static const double _kSectionHeaderHeight = 34;

  /// 紧凑段的行高。`_OfflineRow` 是 48 头像 + 两行文字，上下各留 16 ⇒ 80 正好。
  static const double _kCompactRowExtent = 80;

  /// 「正在直播」那一段的卡面。
  ///
  /// **不挂取关按钮、也不带累计观看时长**（用户要求）：卡面只负责吸引点击进直播间，
  /// 「时长统计」与「取关」两件事统一收在下段的紧凑行里。所以这里既不传
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

  Widget _buildOfflineRow(FollowUser item, bool hideRemove) {
    return _OfflineRow(
      item: item,
      // 取关按钮**只在这段紧凑行里出现**（上段卡面已经不带按钮了），
      // 由「隐藏快速取关按钮」开关控制显隐。
      onRemove: hideRemove ? null : () => controller.removeFollow(item),
      onTap: () => AppNavigator.toLiveRoomDetail(
        site: Sites.allSites[item.siteId]!,
        roomId: item.roomId,
      ),
      onLongPress: () => controller.showBottomMenu(item),
    );
  }
}

/// 段头：状态圆点 + 「正在直播 / 未开播」+ 计数。
///
/// 高度必须固定（`FollowUserPage._kSectionHeaderHeight`）—— 顶部锚点 tab
/// 按几何算滚动 offset，段头一浮动就算不准。
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

/// 未开播那一段的紧凑行。
///
/// **没有复用 `FollowUserItem`**，两个原因：
/// 1. 那是个 `ListTile`，内容定位由 `titleAlignment` / `_isDense` / 三行假定
///    等一整套默认规则决定。放进**固定行高**的网格单元里时内容会偏上
///    （实测：行高 96 逻辑，内容中心比行中心高 11 逻辑像素；
///    改成 `ListTileTitleAlignment.center` 也没纠正过来）。
///    这里用显式的 `Row` + `Center`，位置完全可控。
/// 2. `FollowUserItem` 还被播放器侧 3 处复用，改它的布局会连带影响那边。
///
/// `InkWell` 铺满整个网格单元，所以 hover 高亮是**整行**、内容居中后上下留白相等。
class _OfflineRow extends StatelessWidget {
  final FollowUser item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const _OfflineRow({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onRemove,
  });

  static const double _faceSize = 48;

  /// 第二行的「平台 · 累计观看 N 小时」。没有观看记录时只显示平台名，
  /// 不留孤零零的分隔符。
  static String _durationMeta(Site site, FollowUser item) {
    final duration = watchDurationText(item.watchDurationSec);
    return duration.isEmpty ? site.name : "${site.name} · $duration";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site = Sites.allSites[item.siteId]!;
    return Material(
      type: MaterialType.transparency,
      // 圆角要**三处一起给**才真的圆：Material 的 `borderRadius` + `clipBehavior`
      // 负责把 ink 裁成圆角，InkWell 的 `borderRadius` 负责高亮本身是圆角。
      // 全局 `listTileTheme.shape` 只管 `ListTile`，这里是自己拼的 InkWell，
      // 必须显式指定（否则就是直角，和列表别处不一致 —— 用户报过）。
      borderRadius: AppStyle.radius8,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppStyle.radius8,
        onTap: onTap,
        onLongPress: onLongPress,
        // 桌面端右键 = 长按，和列表别处保持一致。
        onSecondaryTap: onLongPress,
        child: Center(
          child: Padding(
            padding: AppStyle.edgeInsetsL16.copyWith(right: 4),
            child: Row(
              children: [
                // 未开播的头像压暗，和网格里那套占位用同一套视觉语言。
                ColorFiltered(
                  colorFilter: AppStyle.offlineDim,
                  child: NetImage(
                    item.face,
                    width: _faceSize,
                    height: _faceSize,
                    borderRadius: _faceSize / 2,
                  ),
                ),
                AppStyle.hGap12,
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.remark?.isNotEmpty == true
                            ? item.remark!
                            : item.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface,
                        ),
                      ),
                      AppStyle.vGap4,
                      Row(
                        children: [
                          Image.asset(site.logo, width: 16),
                          AppStyle.hGap4,
                          Expanded(
                            child: Text(
                              // 没有观看记录时 watchDurationText 返回空串，
                              // 不能在末尾留一个孤零零的「·」
                              _durationMeta(site, item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    // 统一规格：40dp 圆形高亮。**不要**在这里再叠
                    // `visualDensity: compact` / `padding: zero` /
                    // `constraints: BoxConstraints()` —— 那套组合会把它压到
                    // 16dp，几乎看不见（用户报过）。要更小改
                    // `AppStyle.kIconButtonSize`。
                    style: AppStyle.iconButtonStyle(scheme),
                    tooltip: "取消关注",
                    onPressed: onRemove,
                    icon: const Icon(Remix.dislike_line),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部的 3 个锚点标签 + 自定义标签筛选。
///
/// 做成 `StatefulWidget` 是为了**跟着滚动更新高亮**：只靠点击设置高亮的话，
/// 用户手动滚到别的段之后，高亮会停在错的那一项上。
class _AnchorTabBar extends StatefulWidget {
  final FollowUserController controller;

  /// `[全部, 直播中, 未开播]` 三个计数。
  final List<int> counts;

  /// 上段（正在直播）的条目数，算锚点偏移要用。
  final int liveCount;

  /// 卡片段的列数。
  final int cardColumns;

  const _AnchorTabBar({
    required this.controller,
    required this.counts,
    required this.liveCount,
    required this.cardColumns,
  });

  @override
  State<_AnchorTabBar> createState() => _AnchorTabBarState();
}

class _AnchorTabBarState extends State<_AnchorTabBar> {
  /// 锚点滚动动画进行中。这期间**不要**用滚动位置反推高亮 —— 动画途中会经过
  /// 中间那一段，高亮会来回跳一下。
  bool _anchorScrolling = false;

  @override
  void initState() {
    super.initState();
    widget.controller.scrollController.addListener(_syncActiveTab);
  }

  @override
  void dispose() {
    widget.controller.scrollController.removeListener(_syncActiveTab);
    super.dispose();
  }

  /// 第 [index] 段的顶部偏移。
  ///
  /// **不能用 `Scrollable.ensureVisible`** —— 两段都在 sliver 里，没构建的子项
  /// 拿不到 RenderObject，滚到未构建的区域会直接失败。所以按固定几何硬算。
  /// 这里与 `PageGridView._buildSectionSlivers` 的 padding 规则是**耦合**的：
  /// 段头高固定、段内行距 = itemExtent + spacing、段间距 = mainAxisSpacing。
  double _sectionTop(int index) {
    const pad = 12.0; // AppStyle.edgeInsetsA12
    const gap = 12.0; // PageGridView.mainAxisSpacing（也是段内行距）
    if (index == 0 || widget.liveCount == 0) {
      // 上段为空会被整段跳过，下段就落到最上面。
      return pad;
    }
    if (index == 1) {
      return pad;
    }
    final rows =
        (widget.liveCount + widget.cardColumns - 1) ~/ widget.cardColumns;
    return pad +
        FollowUserPage._kSectionHeaderHeight +
        rows * (PageGridView.kDefaultItemExtent + gap);
  }

  void _syncActiveTab() {
    if (_anchorScrolling) {
      return;
    }
    final scroll = widget.controller.scrollController;
    if (!scroll.hasClients) {
      return;
    }
    final offset = scroll.offset;
    final int next;
    if (offset < _sectionTop(1) - 8) {
      next = 0;
    } else if (offset < _sectionTop(2) - 8) {
      next = 1;
    } else {
      next = 2;
    }
    if (next != widget.controller.activeTab.value) {
      widget.controller.activeTab.value = next;
    }
  }

  Future<void> _onTap(int index) async {
    final controller = widget.controller;
    controller.activeTab.value = index;
    // 「全部」顺带把自定义标签筛选也清掉 —— 它成了锚点之后没有别的入口能清。
    if (index == 0 &&
        !FollowUserController.isBuiltinTag(controller.filterMode.value)) {
      controller.setFilterMode(controller.tagList.first);
    }
    final scroll = controller.scrollController;
    if (!scroll.hasClients) {
      return;
    }
    _anchorScrolling = true;
    try {
      await scroll.animateTo(
        index == 0 ? 0 : _sectionTop(index),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _anchorScrolling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 这里必须**自己包一层 Obx**。本组件是在页面的 Obx 里被构造的，但
    // `activeTab` / `tagList` / `filterMode` 都是在**本组件内部**读的 ——
    // 外层那个 Obx 只追踪它自己 build 期间读到的 Rx，追踪不到子组件内部的读。
    // 不包的话：滚动时高亮不会跟着变、切换自定义标签也不会重绘（实测踩过）。
    return Obx(() {
      final scheme = Theme.of(context).colorScheme;
      final controller = widget.controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < FollowUserController.builtinTags.length; i++)
                Expanded(child: _buildTab(scheme, i)),
            ],
          ),
          AppStyle.divider,
          // 自定义标签仍然是筛选。3 个内置标签变成锚点之后，这里是唯一还能改变
          // 列表内容的入口。`skip(3)` 依赖「内置标签排在 tagList 最前面」这个
          // 既有约定（`setFollowTagDialog` 里也是这么假设的）。
          if (controller.tagList.length > 3)
            Padding(
              padding: AppStyle.edgeInsetsL8.copyWith(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 12,
                  children: controller.tagList
                      .skip(3)
                      .map(
                        (option) => FilterButton(
                          text: option.tag,
                          selected: controller.filterMode.value == option,
                          onTap: () => controller.setFilterMode(option),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildTab(ColorScheme scheme, int index) {
    final selected = widget.controller.activeTab.value == index;
    // 计数为 0 的段没有落点，点了也不会有反应（例如开了「隐藏离线关注」时的
    // 未开播段），所以直接置灰并禁用点击。
    final enabled = widget.counts[index] > 0;
    final color = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
        : (selected ? scheme.primary : scheme.onSurfaceVariant);
    return InkWell(
      onTap: enabled ? () => _onTap(index) : null,
      child: Padding(
        padding: AppStyle.edgeInsetsV8,
        child: Column(
          children: [
            Text(
              "${FollowUserController.builtinTags[index]} ${widget.counts[index]}",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            AppStyle.vGap4,
            Container(
              height: 2,
              width: 28,
              decoration: BoxDecoration(
                color:
                    selected && enabled ? scheme.primary : Colors.transparent,
                borderRadius: AppStyle.radius4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
