import 'dart:io';

import 'package:floating/floating.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/chat_emoticon_span.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_grid.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/modules/live_room/player/player_fit.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/context_menu.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

class LiveRoomPage extends GetView<LiveRoomController> {
  const LiveRoomPage({super.key});

  /// 横屏时右侧聊天栏的宽度。
  ///
  /// 底栏要与上面一行同宽切段，两处必须用同一个值；这个值同时也是多开窗口下限里
  /// 预留的 chrome 宽（`kMultiPlayChromeWidth`），别各写各的。
  static const double _kSidebarWidth = kMultiPlayChromeWidth;

  /// 底栏按钮（含「多开播放」胶囊）的文字样式。
  ///
  /// 与桌面播放条带／全屏顶栏共用 `player_action_bar.dart` 里那一份来源：
  /// 这个 getter 原先是本文件的私有实现，跨不到播放器那边，于是条带与页面各写一份、
  /// 字族逻辑也可能漂移。现在两处都走同一个公共 helper（见 `playerToolbarTextStyle`），
  /// 包括它带上的 ⚠️ 字族覆盖陷阱说明。
  static TextStyle get _toolbarTextStyle => playerToolbarTextStyle();

  @override
  Widget build(BuildContext context) {
    final page = Obx(
      () {
        if (controller.loadError.value) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("直播间加载失败"),
            ),
            body: Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LottieBuilder.asset(
                    'assets/lotties/error.json',
                    height: 140,
                    repeat: false,
                  ),
                  const Text(
                    "直播间加载失败",
                    textAlign: TextAlign.center,
                  ),
                  AppStyle.vGap4,
                  Text(
                    controller.error?.toString() ?? "未知错误",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  AppStyle.vGap4,
                  Text(
                    "${controller.rxSite.value.id} - ${controller.rxRoomId.value}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: controller.copyErrorDetail,
                        icon: const Icon(Remix.file_copy_line),
                        label: const Text("复制信息"),
                      ),
                      TextButton.icon(
                        onPressed: controller.refreshRoom,
                        icon: const Icon(Remix.refresh_line),
                        label: const Text("刷新"),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        }
        if (controller.fullScreenState.value) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (e, r) {
              controller.exitFull();
            },
            child: Scaffold(
              body: buildLiveRoomVideoArea(),
            ),
          );
        } else {
          return buildPageUI();
        }
      },
    );
    if (!Platform.isAndroid) {
      return page;
    }
    return PiPSwitcher(
      floating: controller.pip,
      childWhenDisabled: page,
      childWhenEnabled: buildMediaPlayer(),
    );
  }

  /// 聊天区、底部操作与各弹窗跟随的那一路：多开时是聚焦格，单画面时就是页面主格。
  ///
  /// 视频区不用它——单画面的 `Video` 恒绑页面主格自己的控制器，多开时视频区是网格。
  LiveRoomController get room => controller.focused;

  Widget buildPageUI() {
    final page = OrientationBuilder(
      builder: (context, orientation) {
        return Obx(() {
          // 移动端多开的横屏＝全屏骨架：不画 AppBar、不画那条 300px 侧栏，画面吃满整屏，
          // 聊天收进悬浮按钮 + 底部抽屉（作者定「横屏＝全屏骨架，画面吃满」）。
          // 单画面的横屏仍是原来那套带侧栏的 `buildTabletUI`，一个字不动。
          if (!AppSettingsController.isDesktop &&
              controller.multiPlay.isActive &&
              orientation == Orientation.landscape) {
            return Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: buildLiveRoomVideoArea()),
                  buildChatFloatingButton(context),
                ],
              ),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Obx(
                () => Text(room.detail.value?.title ?? "直播间"),
              ),
              actions: buildAppbarActions(context),
            ),
            body: orientation == Orientation.portrait
                ? buildPhoneUI(context)
                : buildTabletUI(context),
          );
        });
      },
    );
    // 多开时返回键的第一段只关掉其余几路，再按一次才离开直播间：
    // 一次 ESC 就把四路连播放器一起毁掉，代价比单画面大得多。
    return Obx(
      () => controller.multiPlay.isActive
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  return;
                }
                controller.multiPlay.closeAllTiles();
              },
              child: page,
            )
          : page,
    );
  }

  Widget buildPhoneUI(BuildContext context) {
    // 竖屏多开：视频区不能再锁 16/9 条带——360 宽的手机那条只有 ≈202px 高，
    // 两格上下叠每格剩 ~97px，够不到 `kMultiPlayMinTileHeight`(135)，布局引擎会
    // 直接把多开折成一格。所以多开时改成按格数定高（每格仍是 16:9），
    // 主播信息条与聊天区收起，聊天走悬浮按钮 + 底部抽屉。
    return Obx(() {
      if (AppSettingsController.isDesktop || !controller.multiPlay.isActive) {
        return Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: buildLiveRoomVideoArea(),
            ),
            buildUserProfile(context),
            buildMessageArea(context),
            buildBottomActions(context),
          ],
        );
      }
      final size = MediaQuery.sizeOf(context);
      // 夹不出来（屏太矮）就退回 16/9 那一档高度：此时网格会被引擎折成 1 格，
      // 比硬排两格各自低于下限要好。
      final videoHeight =
          resolvePortraitVideoHeight(
            screenW: size.width,
            screenH: size.height,
            rows: 2,
          ) ??
          size.width * 9 / 16;
      return Column(
        children: [
          SizedBox(
            height: videoHeight,
            child: Stack(
              children: [
                Positioned.fill(child: buildLiveRoomVideoArea()),
                buildChatFloatingButton(context),
              ],
            ),
          ),
          buildBottomActions(context),
        ],
      );
    });
  }

  Widget buildTabletUI(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: buildLiveRoomVideoArea(),
              ),
              SizedBox(
                width: _kSidebarWidth,
                child: Column(
                  children: [
                    buildSidebarFollowHint(context),
                    buildUserProfile(context),
                    buildMessageArea(context),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              top: BorderSide(
                color: Colors.grey.withAlpha(25),
              ),
            ),
          ),
          padding: AppStyle.edgeInsetsV4.copyWith(
            // 传页面自己的 context：平台补报底部 inset 时这一层能自动重建
            bottom: AppStyle.bottomBarHeightOf(context) + 4,
          ),
          child: Row(
            children: [
              // 与上面一行同宽地切成两段：左段对齐视频区、右段对齐侧栏。
              // 「多开播放」要右对齐到视频区的右边距，只能这么放——原来那条单行跨整窗，
              // 它的最右端其实已经落到侧栏下面，跟视频区脱钩了。
              Expanded(
                child: Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: _toolbarTextStyle,
                      ),
                      onPressed: () => room.refreshRoom(),
                      icon: const Icon(Remix.refresh_line),
                      label: const Text("刷新"),
                    ),
                    Obx(
                      () => room.followed.value
                          ? TextButton.icon(
                              style: TextButton.styleFrom(
                                textStyle: _toolbarTextStyle,
                              ),
                              onPressed: () => room.removeFollowUser(),
                              icon: const Icon(Remix.heart_fill),
                              label: const Text("取消关注"),
                            )
                          : TextButton.icon(
                              style: TextButton.styleFrom(
                                textStyle: _toolbarTextStyle,
                              ),
                              onPressed: () => room.followUser(),
                              icon: const Icon(Remix.heart_line),
                              label: const Text("关注"),
                            ),
                    ),
                    const Expanded(child: Center()),
                    // 移动端单画面的横屏也要有入口（多开横屏走另一套全屏骨架，
                    // 这条底栏那时根本不画）。竖屏底栏同理，见 `buildBottomActions`。
                    _buildMultiPlayToggle(
                      context,
                      iconOnly: !AppSettingsController.isDesktop,
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              SizedBox(
                width: _kSidebarWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: _toolbarTextStyle,
                      ),
                      onPressed: () => room.share(),
                      icon: const Icon(Remix.share_line),
                      label: const Text("分享"),
                    ),
                    (Platform.isWindows || Platform.isLinux)
                        ? TextButton.icon(
                            style: TextButton.styleFrom(
                              textStyle: _toolbarTextStyle,
                            ),
                            onPressed: () => room.visitWebLive(),
                            icon: const Icon(Remix.chrome_fill),
                            label: const Text("浏览器打开"),
                          )
                        : TextButton.icon(
                            style: TextButton.styleFrom(
                              textStyle: _toolbarTextStyle,
                            ),
                            onPressed: () => room.copyUrl(),
                            icon: const Icon(Remix.file_copy_line),
                            label: const Text("复制链接"),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        //buildBottomActions(context),
      ],
    );
  }

  /// 多开播放开关：胶囊。关闭态是普通文字按钮，开启态用强调色填充 + 带上 `3/4` 路数。
  ///
  /// 横屏挂在底栏**视频区那一段**的右端（与视频区右边距对齐）；竖屏/窄窗挂在底栏最右端。
  /// 不额外占一行——多一条 40px 的窄条是不必要的。
  /// [iconOnly] 给移动端用：竖屏底栏那三个 `Expanded`（关注/刷新/分享）已经把 360px
  /// 占满，文字胶囊挤不进去，只留图标。
  Widget _buildMultiPlayToggle(
    BuildContext context, {
    bool iconOnly = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final session = controller.multiPlay;
      final on = session.enabled.value;
      final counting = on && session.slots.length > 1;
      return TextButton.icon(
        style: TextButton.styleFrom(
          textStyle: _toolbarTextStyle,
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 8 : 14),
          foregroundColor: on ? scheme.onPrimary : null,
          backgroundColor: on ? scheme.primary : null,
        ),
        onPressed: () => session.setEnabled(!on),
        icon: const Icon(Remix.play_circle_line, size: 18),
        label: iconOnly
            ? const SizedBox.shrink()
            : Text(
                counting ? "多开播放 · ${session.slots.length}/$kMultiPlayMaxTiles" : "多开播放",
              ),
      );
    });
  }

  /// 多开时的聊天入口：画面右下角一颗悬浮按钮，点开底部抽屉看聊天。
  ///
  /// 它挂在视频区那层 Stack 上、**不放进格子的 chrome**：格子那层会跟着 4s 淡出，
  /// 聊天入口淡掉了就成了找不到的功能。
  Widget buildChatFloatingButton(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Obx(
        () => controller.multiPlay.isActive
            ? FloatingActionButton(
                heroTag: "multiPlayChat",
                onPressed: () => showMultiPlayChatSheet(context),
                child: const Icon(Icons.chat_bubble_outline),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// 多开时的聊天浮层：底部抽屉里放**同一个** [buildUserProfile] + [buildMessageArea]，
  /// 内容照旧跟随聚焦格（两处都走 `room` getter）。
  ///
  /// 已知取舍：抽屉每次打开重建，所以丢滚动位置、Tab 回到第一个。
  /// 比常驻的半屏 `DraggableScrollableSheet` 轻，也不会永久占画面。
  void showMultiPlayChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.7,
        child: Column(
          children: [
            buildUserProfile(sheetContext),
            buildMessageArea(sheetContext),
          ],
        ),
      ),
    );
  }

  /// 侧栏跟随提示：聊天/SC 跟着聚焦格走这件事在界面上本来完全无形，
  /// 这里给一行短状态（`① 主播名 · 侧栏跟随`）。只在真的多开时出现——
  /// 单画面没有「跟谁」的问题，摆一行状态反而是噪音。
  Widget buildSidebarFollowHint(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final session = controller.multiPlay;
      if (!session.isActive) {
        return const SizedBox.shrink();
      }
      final slot = session.focusedSlot.value.clamp(0, session.slots.length - 1);
      final name = session.slots[slot].detail.value?.userName;
      return Container(
        width: double.infinity,
        color: scheme.primary.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Text(
                "${slot + 1}",
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            AppStyle.hGap8,
            Flexible(
              child: Text(
                (name == null || name.isEmpty) ? "第${slot + 1}路" : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              " · 侧栏跟随",
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ],
        ),
      );
    });
  }

  Widget buildMediaPlayer() {
    // 读本格**有效**的画面尺寸（按格覆盖优先，否则全局）：`updateScaleMode()`、
    // `MultiPlaySession.tileAspect()` 用的都是有效值，这里若读全局，三方就各说各话——
    // 带着按格覆盖进单画面时，`Video` 的初始参数会静默把画面翻回全局档（下次重建生效）。
    final fit = resolvePlayerFit(controller.effectiveScaleMode);
    return Stack(
      children: [
        Video(
          key: controller.globalPlayerKey,
          controller: controller.videoController,
          pauseUponEnteringBackgroundMode: controller.pauseOnBackground,
          resumeUponEnteringForegroundMode: controller.pauseOnBackground,
          controls: (state) {
            return playerControls(state, controller);
          },
          aspectRatio: fit.aspectRatio,
          fit: fit.fit,
          // 自己实现
          wakelock: false,
        ),
        Obx(
          () => Visibility(
            visible: !controller.liveStatus.value,
            child: const Center(
              child: Text(
                "未开播",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 视频区：单画面走 [buildMediaPlayer]，多画面换成网格。
  ///
  /// 2026-10-04 拆掉了原来那道「移动端恒单画面」的平台门：手机上现在也渲染网格
  /// （竖屏 1×2、横屏 2×2）。放开是安全的——格子的 `controls` 只画弹幕层
  /// （`multi_play_tile.dart` 的 `_buildVideo`），**不走** `playerControls`，
  /// 所以移动端单画面那两条老 builder 不会漏进格子里。
  /// Android 的 `PiPSwitcher` 那条只认单画面，多开下由 `enablePIP` 开头直接拒绝。
  Widget buildLiveRoomVideoArea() {
    return Obx(
      () => controller.multiPlay.isActive
          ? buildMultiPlayGrid(controller)
          : buildMediaPlayer(),
    );
  }

  Widget buildUserProfile(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
          bottom: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: AppStyle.edgeInsetsA8.copyWith(
        left: 12,
        right: 12,
      ),
      child: Obx(
        () => Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(50)),
                borderRadius: AppStyle.radius24,
              ),
              child: NetImage(
                room.detail.value?.userAvatar ?? "",
                width: 48,
                height: 48,
                borderRadius: 24,
              ),
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.detail.value?.userName ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppStyle.vGap4,
                  Row(
                    children: [
                      Image.asset(
                        room.site.logo,
                        width: 20,
                      ),
                      AppStyle.hGap4,
                      Text(
                        room.site.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppStyle.hGap12,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Remix.fire_fill,
                  size: 20,
                  color: Colors.orange,
                ),
                AppStyle.hGap4,
                Text(
                  Utils.onlineToString(
                    room.detail.value?.online ?? 0,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBottomActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: AppStyle.bottomBarHeightOf(context)),
      child: Row(
        children: [
          Expanded(
            child: Obx(
              () => room.followed.value
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: _toolbarTextStyle,
                      ),
                      onPressed: () => room.removeFollowUser(),
                      icon: const Icon(Remix.heart_fill),
                      label: const Text("取消关注"),
                    )
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: _toolbarTextStyle,
                      ),
                      onPressed: () => room.followUser(),
                      icon: const Icon(Remix.heart_line),
                      label: const Text("关注"),
                    ),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: _toolbarTextStyle,
              ),
              onPressed: () => room.refreshRoom(),
              icon: const Icon(Remix.refresh_line),
              label: const Text("刷新"),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: _toolbarTextStyle,
              ),
              onPressed: () => room.share(),
              icon: const Icon(Remix.share_line),
              label: const Text("分享"),
            ),
          ),
          // 竖屏/窄窗没有视频区下方那条，开关就挂在这条底栏的最右端；
          // 移动端 2026-10-04 起也显示（多开适配到手机），但只给图标——三个
          // `Expanded` 已经把 360px 占满。
          const SizedBox(width: 8),
          _buildMultiPlayToggle(
            context,
            iconOnly: !AppSettingsController.isDesktop,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget buildMessageArea(BuildContext context) {
    return Expanded(
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: EdgeInsets.zero,
              indicatorWeight: 1.0,
              tabs: [
                const Tab(
                  text: "聊天",
                ),
                Tab(
                  child: Obx(
                    () => Text(
                      room.superChats.isNotEmpty ? "SC(${room.superChats.length})" : "SC",
                    ),
                  ),
                ),
                const Tab(
                  text: "关注",
                ),
                const Tab(
                  text: "设置",
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Obx(
                    () => Stack(
                      children: [
                        ListView.separated(
                          controller: room.scrollController,
                          separatorBuilder: (_, i) => Obx(
                            () => SizedBox(
                              // *2与原来的EdgeInsets.symmetric(vertical: )做兼容
                              height: AppSettingsController.instance.chatTextGap.value * 2,
                            ),
                          ),
                          padding: AppStyle.edgeInsetsA12,
                          itemCount: room.messages.length,
                          itemBuilder: (context, i) {
                            var item = room.messages[i];
                            return buildMessageItem(item, context);
                          },
                        ),
                        Visibility(
                          visible: room.disableAutoScroll.value,
                          child: Positioned(
                            right: 12,
                            bottom: 12,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                room.disableAutoScroll.value = false;
                                room.chatScrollToBottom();
                              },
                              icon: const Icon(Icons.expand_more),
                              label: const Text("最新"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  buildSuperChats(),
                  buildFollowList(),
                  buildSettings(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMessageItem(LiveMessage message, BuildContext context) {
    if (message.userName == "LiveSysMessage") {
      return Obx(
        () => SelectableText(
          message.message,
          style: TextStyle(
            color: Colors.grey,
            fontSize: AppSettingsController.instance.chatTextSize.value,
          ),
        ),
      );
    }

    return Obx(
      () => AppSettingsController.instance.chatBubbleStyle.value
          ? Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withAlpha(25),
                      //borderRadius: AppStyle.radius8,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding: AppStyle.edgeInsetsA4.copyWith(left: 12, right: 12),
                    child: SelectableText.rich(
                      TextSpan(
                        text: "${message.userName}：",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: AppSettingsController.instance.chatTextSize.value,
                        ),
                        children: buildChatMessageSpans(
                          context,
                          message,
                          TextStyle(
                            // 必须用本地的 Theme.of(context)：Get.isDarkMode 不建立
                            // InheritedWidget 依赖，主题切换后这里不会重建，气泡文字
                            // 会一直停在旧配色上（浅色底 + 白字）。
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : AppColors.black333,
                            fontSize: AppSettingsController
                                .instance.chatTextSize.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SelectableText.rich(
              TextSpan(
                text: "${message.userName}：",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: AppSettingsController.instance.chatTextSize.value,
                ),
                children: buildChatMessageSpans(
                  context,
                  message,
                  TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : AppColors.black333,
                    fontSize: AppSettingsController.instance.chatTextSize.value,
                  ),
                ),
              ),
              contextMenuBuilder: _contextMenuBuilder,
            ),
    );
  }

  Widget _contextMenuBuilder(BuildContext context, EditableTextState editableTextState) {
    return customContextMenuBuilder(
      context,
      editableTextState,
      {
        '屏蔽用户': (s) => room.addCurBlockAccount(s),
        '屏蔽关键词': (s) => room.addCurBlockWord(s),
      },
    );
  }

  Widget buildSuperChats() {
    return KeepAliveWrapper(
      child: Obx(
        () => ListView.separated(
          padding: AppStyle.edgeInsetsA12,
          itemCount: room.superChats.length,
          separatorBuilder: (_, i) => AppStyle.vGap12,
          itemBuilder: (_, i) {
            var item = room.superChats[i];
            return SuperChatCard(
              item,
            );
          },
        ),
      ),
    );
  }

  /// 「设置」页签。
  ///
  /// 屏蔽项跟着聊天区走聚焦格（[room]），因为聊天显示的就是那一路的消息；
  /// 其余（弹幕设置、定时关闭、画面尺寸）都是全局或窗口级设置，走 [controller]。
  Widget buildSettings(BuildContext context) {
    return ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        Obx(
          () => Visibility(
            visible: controller.autoExitEnable.value,
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              visualDensity: VisualDensity.compact,
              title: Text("${parseDuration(controller.countdown.value)}后自动关闭"),
            ),
          ),
        ),
        // 多开参数旋钮。原来整段被「仅桌面」的平台门挡着（当时移动端根本没有多开），
        // 移动端适配后放开：里面四个旋钮（压低开关与比例、各格弹幕、每路缓存）都是
        // 纯设置项，没有一个是窗口/平台相关的。
        // 「多画面」开关在视频区底栏（那里才是它管的行为），这里只留参数旋钮；
        // 没开多画面时整段不渲染（也不加解释性提示）。每个旋钮各自包 Obx —— 它们的
        // 取值要能随点击当场刷新，只订阅 enabled 是不够的。
        Obx(() {
          if (!controller.multiPlay.enabled.value) {
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              Padding(
                padding: AppStyle.edgeInsetsA12,
                child: Text(
                  "多开播放",
                  style: context.textTheme.titleSmall,
                ),
              ),
              SettingsCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Obx(
                      () => SettingsSwitch(
                        title: "非聚焦自动压低",
                        value: AppSettingsController.instance.multiPlayDuckEnabled.value,
                        onChanged: (e) {
                          AppSettingsController.instance.setMultiPlayDuckEnabled(e);
                          // 设置只落盘，正在跑的几路要重下一次音量
                          controller.multiPlay.applyVolumes();
                        },
                      ),
                    ),
                    // 比例那行只在压低开着时出现：`SettingsNumber` 没有 disabled 态，
                    // 关着还摆在那儿是「可编辑但不生效」的假供应——按项目里
                    // 「空集合不显示」的规矩，直接不渲染比灰掉更诚实。
                    Obx(() {
                      if (!AppSettingsController.instance.multiPlayDuckEnabled.value) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          AppStyle.divider,
                          SettingsNumber(
                            title: "非聚焦音量",
                            value: (AppSettingsController.instance.multiPlayDuckVolume.value * 100).round(),
                            min: 0,
                            max: 100,
                            step: 5,
                            unit: "%",
                            onChanged: (e) {
                              AppSettingsController.instance.setMultiPlayDuckVolume(e / 100);
                              // 设置只落盘，正在跑的四路要重下一次音量
                              controller.multiPlay.applyVolumes();
                            },
                          ),
                        ],
                      );
                    }),
                    AppStyle.divider,
                    Obx(
                      () => SettingsSwitch(
                        title: "各格显示弹幕",
                        subtitle: "关掉后四路都不画弹幕，CPU 会明显下来",
                        value: AppSettingsController.instance.multiPlayTileDanmaku.value,
                        onChanged: controller.multiPlay.setTileDanmakuVisible,
                      ),
                    ),
                    AppStyle.divider,
                    Obx(
                      () => SettingsNumber(
                        title: "每路缓存",
                        subtitle: "四路各占一份，重进直播间生效",
                        value: AppSettingsController.instance.multiPlayTileBufferSize.value,
                        min: 8,
                        max: 32,
                        step: 4,
                        unit: "MiB",
                        onChanged: AppSettingsController.instance.setMultiPlayTileBufferSize,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "聊天区",
            style: context.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(
                () => SettingsNumber(
                  title: "文字大小",
                  value: AppSettingsController.instance.chatTextSize.value.toInt(),
                  min: 8,
                  max: 36,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatTextSize(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "上下间隔",
                  value: AppSettingsController.instance.chatTextGap.value.toInt(),
                  min: 0,
                  max: 12,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatTextGap(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsSwitch(
                  title: "气泡样式",
                  value: AppSettingsController.instance.chatBubbleStyle.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatBubbleStyle(e);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "更多设置",
            style: context.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "关键词屏蔽",
                onTap: () => room.showFollowBlockShield(),
              ),
              SettingsAction(
                title: "用户屏蔽",
                onTap: () => room.showFollowBlockShield(blockWords: false),
              ),
              AppStyle.divider,
              SettingsAction(
                title: "弹幕设置",
                onTap: controller.showDanmuSettingsSheet,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "定时关闭",
                onTap: controller.showAutoExitSheet,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "画面尺寸",
                onTap: controller.showPlayerSettingsSheet,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "自定义画面尺寸",
                onTap: controller.showAspectRatioSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildFollowList() {
    return Obx(
      () => Stack(
        children: [
          RefreshIndicator(
            onRefresh: FollowService.instance.loadData,
            child: ListView.builder(
              itemCount: FollowService.instance.liveList.length,
              itemBuilder: (_, i) {
                var item = FollowService.instance.liveList[i];
                return Obx(
                  () => FollowUserItem(
                    item: item,
                    // 多开时可能好几路同时在播，命中任意一格都算「在播」
                    playing: controller.multiPlay.slots.any(
                      (t) => t.site.id == item.siteId && t.roomId == item.roomId,
                    ),
                    onTap: () {
                      controller.multiPlay.onFollowItemTap(
                        Sites.allSites[item.siteId]!,
                        item.roomId,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Positioned(
              right: 12,
              bottom: 12,
              child: Obx(
                () => DesktopRefreshButton(
                  refreshing: FollowService.instance.updating.value,
                  onPressed: FollowService.instance.loadData,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> buildAppbarActions(BuildContext context) {
    return [
      IconButton(
        tooltip: "更多",
        onPressed: () {
          showMore();
        },
        icon: const Icon(Icons.more_horiz),
      ),
    ];
  }

  /// 房间菜单。
  ///
  /// 桌面走视频区同一份动作清单（`resolvePlayerActions` + `showActionMenu`），移动端仍
  /// 是下面那份底部抽屉清单——移动端不进这套模型，两条分支各管一个平台，内容不再两处各写一份。
  /// 两支**容器相同**（都是底部抽屉：这页此刻就是窗口化），只是清单同源。
  ///
  /// 多开时的分工：路由级动作（刷新 / 清晰度 / 线路 / 截图 / 分享 / 链接 / 播放信息，
  /// 以及可按格独立的画面尺寸）跟着聚焦格（[room]）走；定时关闭、小窗、全屏是窗口级，
  /// 恒走页面主格（[controller]）——四路各跑一份倒计时或直接 `exit(0)` 是不能接受的。
  /// 桌面把这条分工交给 `invokePlayerAction` 的 target/page（窗口级只认 page），移动分支
  /// 逐条写死；多开只在桌面可用（`MultiPlaySession` 按平台门短路），那里 [room] 与
  /// [controller] 恒为同一个控制器，两支说法一致。
  void showMore() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // 与视频区条带同一份清单：两处内容同源，不再各写一份 ListTile。
      final layout = resolvePlayerActions(
        host: PlayerHost.windowed,
        // 抽屉不受条带宽度约束：给足宽度让全部动作进 overflow 之外的部分也列出来
        availableWidth: 4000,
        isVertical: room.isVertical.value,
        hasQuality: room.hasMultipleQualities,
        hasLine: room.hasMultipleLines,
      );
      showActionMenu(
        title: "更多",
        // 页级这颗「更多」本来就挂在窗口化的 AppBar 上，容器跟着窗口化走＝底部抽屉
        // （改造前它就是 `showModalBottomSheet`，行内再落各自的底部 sheet）。
        rightPanel: false,
        // 页级菜单列**全集**，当直达入口用——它不是「条带放不下的那些」那份子集。
        // 用 `layout.all`（= `_kAllActions` 的声明顺序）而不是 bar+overflow 现拼：
        // 拆簇之后「平铺的」分顶簇与底栏两份，现拼出来的顺序与条带里的不一致。
        // 抽屉里点了没反应的锚定件（volume）由 showActionMenu 内部的
        // actionableMenuItems 统一滤掉，这里不再另判一次。
        items: layout.all,
        onSelect: (id) => invokePlayerAction(
          host: PlayerHost.windowed,
          target: room,
          page: controller,
          id: id,
        ),
      );
      return;
    }
    // 移动端：原来的底部抽屉清单原样保留（不进模型）。
    showModalBottomSheet(
      context: Get.context!,
      constraints: const BoxConstraints(
        maxWidth: 600,
      ),
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.only(
          bottom: AppStyle.bottomBarHeightOf(sheetContext),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text("刷新"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                room.refreshRoom();
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              trailing: const Icon(Icons.chevron_right),
              title: const Text("切换清晰度"),
              onTap: () {
                Get.back();
                room.showQualitySheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.switch_video_outlined),
              title: const Text("切换线路"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                room.showPlayUrlsSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio_outlined),
              title: const Text("画面尺寸"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                controller.showPlayerSettingsSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text("截图"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                room.saveScreenshot();
              },
            ),
            Visibility(
              visible: Platform.isAndroid,
              child: ListTile(
                leading: const Icon(Icons.picture_in_picture),
                title: const Text("小窗播放"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  controller.enablePIP();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text("定时关闭"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                controller.showAutoExitSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_sharp),
              title: const Text("分享直播间"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                room.share();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("复制链接"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                room.copyUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text("APP 中打开"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                room.openNaviteAPP();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text("播放信息"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                room.showDebugInfo();
              },
            ),
          ],
        ),
      ),
    );
  }

  String parseDuration(int sec) {
    // 转为时分秒
    var h = sec ~/ 3600;
    var m = (sec % 3600) ~/ 60;
    var s = sec % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}小时${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    if (m > 0) {
      return "${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    return "${s.toString().padLeft(2, '0')}秒";
  }
}
