import 'dart:io';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_surfaces.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_osd_overlay.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';
import 'package:window_manager/window_manager.dart';

Widget playerControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  return Obx(() {
    // 移动端不进这套模型：安卓走下面两个既有 builder 的原样清单，
    // 桌面才用 resolver 驱动的条带（spec §3 的平台门）。
    if (Platform.isAndroid || Platform.isIOS) {
      if (controller.fullScreenState.value) {
        return buildFullControls(videoState, controller);
      }
      return buildControls(
        videoState.context.orientation == Orientation.portrait,
        videoState,
        controller,
      );
    }
    return controller.fullScreenState.value
        ? _buildDesktopFullControls(videoState, controller)
        : _buildDesktopControls(videoState, controller);
  });
}

Widget buildDragToMoveArea({required Widget child}) {
  return (!Platform.isAndroid && !Platform.isIOS)
      ? DragToMoveArea(
          child: child,
        )
      : child;
}

/// 手势提示那块黑底圆角卡片（`gestureTipText` 非空时浮在画面正中）。
///
/// 两个桌面 builder 与两个移动 builder 共用一份；之前它在 `buildFullControls` 与
/// `buildControls` 各写了一遍，逐字相同。提出来不是改行为，是消重复——
/// 移动路径的渲染与原来逐位一致。
Widget _gestureTip(LiveRoomController controller) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      controller.gestureTipText.value,
      style: const TextStyle(fontSize: 18, color: Colors.white),
    ),
  );
}

/// 桌面窗口化的底栏：与全屏用同一份清单、同一个 renderer，只是没有顶栏。
///
/// WHY 外层用 `Obx` 而不是直接把 reactive 读取塞进 `LayoutBuilder.builder`：
/// `Obx` 的自动订阅发生在它 builder 的**同步执行期**；`LayoutBuilder` 的 builder
/// 是布局阶段才跑的，那时订阅窗口早就关了，塞进去的读取一个都订不上。于是清晰度列表
/// 加载完（`qualities.assignAll`）、竖屏判定翻转都不会重算 layout，条带停在初始那份。
/// 所以这里同步读 reactive 值，返回 `LayoutBuilder` 只做量宽这件非 reactive 的事。
Widget _buildDesktopControls(VideoState videoState, LiveRoomController controller) {
  return Obx(() {
    final isVertical = controller.isVertical.value;
    final hasQuality = controller.hasMultipleQualities;
    final hasLine = controller.hasMultipleLines;
    return LayoutBuilder(
      builder: (context, constraints) {
        // availableWidth 扣掉条带自己的左右内边距（各 12），否则 resolver 会按整窗宽
        // 判「装得下」，实际渲染时被 Padding 再挤一次 → 平铺件溢出。
        final layout = resolvePlayerActions(
          host: PlayerHost.windowed,
          availableWidth: constraints.maxWidth - 24,
          isVertical: isVertical,
          hasQuality: hasQuality,
          hasLine: hasLine,
        );
        return Stack(
          children: [
            Container(),
            buildDanmuView(videoState, controller),
            Center(
              child: StreamBuilder(
                stream: videoState.widget.controller.player.stream.buffering,
                initialData: videoState.widget.controller.player.state.buffering,
                builder: (_, s) => Visibility(
                  visible: s.data ?? false,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: controller.onTap,
                onDoubleTapDown: controller.onDoubleTap,
                onVerticalDragStart: controller.onVerticalDragStart,
                onVerticalDragUpdate: controller.onVerticalDragUpdate,
                onVerticalDragEnd: controller.onVerticalDragEnd,
                child: MouseRegion(
                  onEnter: controller.onEnter,
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
            // 顶栏：只有右上那一簇（截图／换台／小窗 + `⋮`），没有返回键与标题——
            // 那两个是全屏容器结构，窗口化里返回走页级 AppBar。
            // WHY 窗口化也要有这一簇（作者 2026-10-03）：改造前「截图／关注列表／更多」
            // 就挂在右上角，接线后全被塞进底栏，顶上一片空——同一批动作在两种形态下
            // 位置不同，正是这轮重构要消灭的东西。滑入时序、渐变方向与全屏顶栏同源。
            Obx(
              () => AnimatedPositioned(
                left: 0,
                right: 0,
                top: controller.showControlsState.value ? 0 : -48,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      ...playerTopClusterItems(
                        layout: layout,
                        host: PlayerHost.windowed,
                        target: controller,
                        page: controller,
                        textStyle: playerToolbarTextStyle(),
                        onInteract: controller.showControls,
                      ),
                      PlayerOverflowButton(
                        host: PlayerHost.windowed,
                        target: controller,
                        page: controller,
                        overflow: layout.overflow,
                        placement: PlayerActionPlacement.top,
                        buttonStyle: playerActionIconStyle(),
                        onInteract: controller.showControls,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 底栏：桌面窗口化此前用一坨硬编码 Row（含安卓可见性门），换成 resolver 驱动。
            // 这里再套一层 Obx：滑入/滑出由 showControlsState 驱动，交互
            // （onInteract→controller.showControls）把自动隐藏计时续上，与原来一致。
            // 订阅必须写在本 Obx 的 builder 里（读 controller.showControlsState.value），
            // 外层那个 Obx 只订了 layout 的输入。
            Obx(
              () => AnimatedPositioned(
                left: 0,
                right: 0,
                bottom: controller.showControlsState.value ? 0 : -48,
                duration: const Duration(milliseconds: 200),
                // 渐变遮罩带（spec §4：条带视觉保持）：没有它，白色图标直接坐在
                // 亮画面上看不见；也与全屏底栏、移动条带同一形态。
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: PlayerActionBar(
                    host: PlayerHost.windowed,
                    target: controller,
                    page: controller,
                    bar: layout.bar,
                    overflow: layout.overflow,
                    textStyle: playerToolbarTextStyle(),
                    onInteract: controller.showControls,
                  ),
                ),
              ),
            ),
            Obx(
              () => Offstage(
                offstage: !controller.showGestureTip.value,
                child: Center(child: _gestureTip(controller)),
              ),
            ),
            Positioned.fill(child: buildOsdOverlay(controller)),
          ],
        );
      },
    );
  });
}

/// 桌面全屏／小窗的底栏 + 顶栏 + 锁定 + 拖拽。
///
/// 小窗态：`host = smallWindow`，只画底栏（顶栏的返回/标题/顶栏动作在窗口级小窗里
/// 没有落点，且会盖住画面），底栏动作集收成四件（退出小窗／全屏播放／弹幕／音量）+ ⋮。
/// 全屏态：顶栏手排（要插返回键与标题，标题是容器结构不是动作），底栏走 renderer。
/// 两个底栏宿主都用同一个 resolver 产物与同一个 `PlayerActionBar`，差别只在顶栏有无。
///
/// `host` 读 `smallWindowState`：它必须在外层 `Obx` 的 builder 里同步读（见
/// `_buildDesktopControls` 的 WHY），否则从全屏进小窗（`fullScreenState` 恒 true，
/// 外层 `playerControls` 不会重建）时 host 冻在 fullscreen、顶栏退不掉。
Widget _buildDesktopFullControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  var padding = MediaQuery.of(videoState.context).padding;
  return Obx(() {
    // 小窗 implies fullScreenState==true，所以 host 先判小窗再判全屏，否则小窗会错用
    // 全屏宿主（顶栏冒出来、动作集也没收成四件）。
    final host = controller.smallWindowState.value
        ? PlayerHost.smallWindow
        : PlayerHost.fullscreen;
    final isVertical = controller.isVertical.value;
    final hasQuality = controller.hasMultipleQualities;
    final hasLine = controller.hasMultipleLines;
    // 顶栏只在非小窗的全屏画：小窗没有返回/标题那一行。
    final showTopBar = host == PlayerHost.fullscreen;
    return buildDragToMoveArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = resolvePlayerActions(
            host: host,
            availableWidth: constraints.maxWidth - 24,
            isVertical: isVertical,
            hasQuality: hasQuality,
            hasLine: hasLine,
          );
          return Stack(
            children: [
              Container(),
              buildDanmuView(videoState, controller),
              Center(
                child: StreamBuilder(
                  stream: videoState.widget.controller.player.stream.buffering,
                  initialData:
                      videoState.widget.controller.player.state.buffering,
                  builder: (_, s) => Visibility(
                    visible: s.data ?? false,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: controller.onTap,
                  onDoubleTapDown: controller.onDoubleTap,
                  onLongPress: () {
                    if (controller.lockControlsState.value) {
                      return;
                    }
                    // 长按＝换台，与右上角那颗「换台」同一个去处（右侧面板）。
                    // 曾经为了「同一块浮层」把长按改成弹条带上那颗锚定菜单的键（GlobalKey +
                    // showButtonMenu），作者 2026-10-03 否掉了那个形态：锚定小列表只适合
                    // 多开的格子，单画面要用改造前那块带头像与刷新的右侧面板。
                    showFollowUser(controller);
                  },
                  onVerticalDragStart: controller.onVerticalDragStart,
                  onVerticalDragUpdate: controller.onVerticalDragUpdate,
                  onVerticalDragEnd: controller.onVerticalDragEnd,
                  child: MouseRegion(
                    onHover: (PointerHoverEvent event) {
                      controller.onHover(event, videoState.context);
                    },
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
              // 顶部：返回 + 标题 + placeInTopBar 动作。手排而非交给 PlayerActionBar，
              // 因为返回键与标题插在动作之间（容器结构不是动作，见 spec §8）。
              // 滑入/滑出用本 Obx 内同步读的两个旗标（visible = 显示控制 && 未锁）。
              if (showTopBar)
                Obx(
                  () {
                    final visible =
                        controller.showControlsState.value &&
                        !controller.lockControlsState.value;
                    return AnimatedPositioned(
                      left: 0,
                      right: 0,
                      top: visible ? 0 : -(48 + padding.top),
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        height: 48 + padding.top,
                        padding: EdgeInsets.only(
                          left: padding.left + 12,
                          right: padding.right + 12,
                          top: padding.top,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: "退出全屏",
                              // 返回键走 exitFull：这条顶栏只在 host==fullscreen 出现
                              // （pip 时 showTopBar 为假），此刻 smallWindowState 恒
                              // false，不必再判退小窗那条臂。
                              onPressed: controller.exitFull,
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            AppStyle.hGap12,
                            Expanded(
                              child: Text(
                                "${controller.detail.value?.title} - ${controller.detail.value?.userName}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            AppStyle.hGap12,
                            // 右上那一簇（截图／换台／小窗…）与窗口化顶栏共用同一个组装函数，
                            // `⋮` 也在这簇里（hasTopCluster 为真的宿主）——两处若各排一次，
                            // 「件在顶簇、⋮ 在底栏」这种两头找不到的组合迟早会出现。
                            ...playerTopClusterItems(
                              layout: layout,
                              host: PlayerHost.fullscreen,
                              target: controller,
                              page: controller,
                              textStyle: playerToolbarTextStyle(),
                              onInteract: controller.showControls,
                            ),
                            PlayerOverflowButton(
                              host: PlayerHost.fullscreen,
                              target: controller,
                              page: controller,
                              overflow: layout.overflow,
                              placement: PlayerActionPlacement.top,
                              buttonStyle: playerActionIconStyle(),
                              onInteract: controller.showControls,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              // 底部：小窗宿主（host==smallWindow）也走这条，只是 layout 收成四件。
              Obx(
                () {
                  final visible =
                      controller.showControlsState.value &&
                      !controller.lockControlsState.value;
                  return AnimatedPositioned(
                    left: 0,
                    right: 0,
                    bottom: visible ? 0 : -(80 + padding.bottom),
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      padding: EdgeInsets.only(
                        left: padding.left + 12,
                        right: padding.right + 12,
                        bottom: padding.bottom,
                      ),
                      child: PlayerActionBar(
                        host: host,
                        target: controller,
                        page: controller,
                        bar: layout.bar,
                        overflow: layout.overflow,
                        textStyle: playerToolbarTextStyle(),
                        onInteract: controller.showControls,
                      ),
                    ),
                  );
                },
              ),
              // 右侧锁定
              Obx(
                () => AnimatedPositioned(
                  top: 0,
                  bottom: 0,
                  right: controller.showControlsState.value
                      ? padding.right + 12
                      : -(64 + padding.right),
                  duration: const Duration(milliseconds: 200),
                  child: buildLockButton(controller),
                ),
              ),
              // 左侧锁定
              Obx(
                () => AnimatedPositioned(
                  top: 0,
                  bottom: 0,
                  left: controller.showControlsState.value
                      ? padding.left + 12
                      : -(64 + padding.right),
                  duration: const Duration(milliseconds: 200),
                  child: buildLockButton(controller),
                ),
              ),
              Obx(
                () => Offstage(
                  offstage: !controller.showGestureTip.value,
                  child: Center(child: _gestureTip(controller)),
                ),
              ),
              Positioned.fill(child: buildOsdOverlay(controller)),
            ],
          );
        },
      ),
    );
  });
}


Widget buildFullControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  var padding = MediaQuery.of(videoState.context).padding;
  return buildDragToMoveArea(
    child: Stack(
      children: [
        Container(),
        buildDanmuView(videoState, controller),

        Center(
          child: // 中间
              StreamBuilder(
            stream: videoState.widget.controller.player.stream.buffering,
            initialData: videoState.widget.controller.player.state.buffering,
            builder: (_, s) => Visibility(
              visible: s.data ?? false,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.onTap,
            onDoubleTapDown: controller.onDoubleTap,
            onLongPress: () {
              if (controller.lockControlsState.value) {
                return;
              }
              showFollowUser(controller);
            },
            onVerticalDragStart: controller.onVerticalDragStart,
            onVerticalDragUpdate: controller.onVerticalDragUpdate,
            onVerticalDragEnd: controller.onVerticalDragEnd,
            child: MouseRegion(
              onHover: (PointerHoverEvent event) {
                controller.onHover(event, videoState.context);
              },
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent,
                // child: Visibility(
                //   //拖拽区域
                //   visible: controller.smallWindowState.value,
                //   child: DragToMoveArea(
                //       child: Container(
                //     width: double.infinity,
                //     height: double.infinity,
                //     color: Colors.transparent,
                //   )),
                // ),
              ),
            ),
          ),
        ),

        // 顶部
        Obx(
          () => AnimatedPositioned(
            left: 0,
            right: 0,
            top: (controller.showControlsState.value && !controller.lockControlsState.value) ? 0 : -(48 + padding.top),
            duration: const Duration(milliseconds: 200),
            child: Container(
              height: 48 + padding.top,
              padding: EdgeInsets.only(
                left: padding.left + 12,
                right: padding.right + 12,
                top: padding.top,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black87,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: controller.smallWindowState.value
                        ? "退出小窗"
                        : "退出全屏",
                    onPressed: () {
                      if (controller.smallWindowState.value) {
                        controller.exitSmallWindow();
                      } else {
                        controller.exitFull();
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: Text(
                      "${controller.detail.value?.title} - ${controller.detail.value?.userName}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  AppStyle.hGap12,
                  IconButton(
                    tooltip: "截图",
                    onPressed: () {
                      controller.saveScreenshot();
                    },
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    tooltip: "关注列表",
                    onPressed: () {
                      showFollowUser(controller);
                    },
                    icon: const Icon(
                      Remix.play_list_2_line,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  Visibility(
                    visible: Platform.isAndroid,
                    child: IconButton(
                      tooltip: "小窗播放",
                      onPressed: () {
                        controller.enablePIP();
                      },
                      icon: const Icon(
                        Icons.picture_in_picture,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "更多设置",
                    onPressed: () {
                      showPlayerSettings(controller);
                    },
                    icon: const Icon(
                      Icons.more_horiz,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 底部
        Obx(
          () => AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: (controller.showControlsState.value && !controller.lockControlsState.value)
                ? 0
                : -(80 + padding.bottom),
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black87,
                  ],
                ),
              ),
              padding: EdgeInsets.only(
                left: padding.left + 12,
                right: padding.right + 12,
                bottom: padding.bottom,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "刷新",
                    onPressed: () {
                      controller.refreshRoom();
                    },
                    icon: const Icon(
                      Remix.refresh_line,
                      color: Colors.white,
                    ),
                  ),
                  Offstage(
                    offstage: controller.showDanmakuState.value,
                    child: IconButton(
                      tooltip: "开启弹幕",
                      onPressed: () => controller.showDanmakuState.value =
                          !controller.showDanmakuState.value,
                      icon: const ImageIcon(
                        AssetImage('assets/icons/icon_danmaku_open.png'),
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !controller.showDanmakuState.value,
                    child: IconButton(
                      tooltip: "关闭弹幕",
                      onPressed: () => controller.showDanmakuState.value =
                          !controller.showDanmakuState.value,
                      icon: const ImageIcon(
                        AssetImage('assets/icons/icon_danmaku_close.png'),
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "弹幕设置",
                    onPressed: () {
                      showDanmakuSettings(controller);
                    },
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_setting.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  const Expanded(child: Center()),
                  Tooltip(
                    message: "切换清晰度",
                    child: TextButton(
                      onPressed: () {
                        showQualitesInfo(controller);
                      },
                      child: Obx(
                        () => Text(
                          controller.currentQualityInfo.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: "切换线路",
                    child: TextButton(
                      onPressed: () {
                        showLinesInfo(controller);
                      },
                      child: Text(
                        controller.currentLineInfo.value,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                  IconButton(
                    // 和顶部返回按钮同一个动作，提示文案也要一致：
                    // 小窗态下两处都该说「退出小窗」，不然同一屏两个同义按钮
                    // 给出不同提示。
                    tooltip: controller.smallWindowState.value
                        ? "退出小窗"
                        : "退出全屏",
                    onPressed: () {
                      if (controller.smallWindowState.value) {
                        controller.exitSmallWindow();
                      } else {
                        controller.exitFull();
                      }
                    },
                    icon: Icon(
                      // 退出小窗用与「小窗播放」入口相同的图标，
                      // 全屏的进入/退出才用 fullscreen 图标族
                      controller.smallWindowState.value
                          ? Icons.picture_in_picture
                          : Remix.fullscreen_exit_fill,
                      color: Colors.white,
                    ),
                  ),
                  Obx(
                    // only pip
                    () => Visibility(
                      visible: controller.smallWindowState.value,
                      child: IconButton(
                        tooltip: "全屏播放",
                        onPressed: () {
                          controller.enterFullScreen();
                        },
                        icon: const Icon(
                          Remix.fullscreen_line,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 右侧锁定
        Obx(
          () => AnimatedPositioned(
            top: 0,
            bottom: 0,
            right: controller.showControlsState.value ? padding.right + 12 : -(64 + padding.right),
            duration: const Duration(milliseconds: 200),
            child: buildLockButton(controller),
          ),
        ),
        // 左侧锁定
        Obx(
          () => AnimatedPositioned(
            top: 0,
            bottom: 0,
            left: controller.showControlsState.value ? padding.left + 12 : -(64 + padding.right),
            duration: const Duration(milliseconds: 200),
            child: buildLockButton(controller),
          ),
        ),
        Obx(
          () => Offstage(
            offstage: !controller.showGestureTip.value,
            child: Center(child: _gestureTip(controller)),
          ),
        ),
        // OSD 统计浮层（Flutter 自绘，开关开启时显示）
        Positioned.fill(child: buildOsdOverlay(controller)),
      ],
    ),
  );
}

/// OSD 统计浮层（Flutter 自绘，开关开启时显示）。
Widget buildOsdOverlay(LiveRoomController controller) {
  return Obx(
    () => controller.showOSDStats.value
        ? PlayerOsdOverlay(
            controller: controller,
            onClose: () => controller.showOSDStats.value = false,
          )
        : const SizedBox.shrink(),
  );
}

/// 左右两侧的锁定按钮。
///
/// 提示语按**动作**描述（锁定 / 解锁），与图标表示的**状态**相反，
/// 和系统「返回」按钮那类 tooltip 的习惯一致。
Widget buildLockButton(LiveRoomController controller) {
  return Center(
    child: Tooltip(
      message: controller.lockControlsState.value ? "解锁" : "锁定",
      child: InkWell(
        onTap: () {
          controller.setLockState();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: AppStyle.radius8,
          ),
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              controller.lockControlsState.value
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildControls(
  bool isPortrait,
  VideoState videoState,
  LiveRoomController controller,
) {
  return Stack(
    children: [
      Container(),
      buildDanmuView(videoState, controller),
      // 中间
      Center(
        child: StreamBuilder(
          stream: videoState.widget.controller.player.stream.buffering,
          initialData: videoState.widget.controller.player.state.buffering,
          builder: (_, s) => Visibility(
            visible: s.data ?? false,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: GestureDetector(
          onTap: controller.onTap,
          onDoubleTapDown: controller.onDoubleTap,
          onVerticalDragStart: controller.onVerticalDragStart,
          onVerticalDragUpdate: controller.onVerticalDragUpdate,
          onVerticalDragEnd: controller.onVerticalDragEnd,
          //onLongPress: controller.showDebugInfo,
          child: MouseRegion(
            onEnter: controller.onEnter,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),
        ),
      ),
      Obx(
        () => AnimatedPositioned(
          left: 0,
          right: 0,
          bottom: controller.showControlsState.value ? 0 : -48,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black87,
                ],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: "刷新",
                  onPressed: () {
                    controller.refreshRoom();
                  },
                  icon: const Icon(
                    Remix.refresh_line,
                    color: Colors.white,
                  ),
                ),
                Offstage(
                  offstage: controller.showDanmakuState.value,
                  child: IconButton(
                    tooltip: "开启弹幕",
                    onPressed: () => controller.showDanmakuState.value =
                        !controller.showDanmakuState.value,
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_open.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                Offstage(
                  offstage: !controller.showDanmakuState.value,
                  child: IconButton(
                    tooltip: "关闭弹幕",
                    onPressed: () => controller.showDanmakuState.value =
                        !controller.showDanmakuState.value,
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_close.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "弹幕设置",
                  onPressed: () {
                    controller.showDanmuSettingsSheet();
                  },
                  icon: const ImageIcon(
                    AssetImage('assets/icons/icon_danmaku_setting.png'),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const Expanded(child: Center()),
                Offstage(
                  offstage: isPortrait,
                  child: Tooltip(
                    message: "切换清晰度",
                    child: TextButton(
                      onPressed: () {
                        controller.showQualitySheet();
                      },
                      child: Obx(
                        () => Text(
                          controller.currentQualityInfo.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Offstage(
                  offstage: isPortrait,
                  child: Tooltip(
                    message: "切换线路",
                    child: TextButton(
                      onPressed: () {
                        controller.showPlayUrlsSheet();
                      },
                      child: Text(
                        controller.currentLineInfo.value,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "全屏播放",
                  onPressed: () {
                    controller.enterFullScreen();
                  },
                  icon: const Icon(
                    Remix.fullscreen_line,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Obx(
        () => Offstage(
          offstage: !controller.showGestureTip.value,
          child: Center(child: _gestureTip(controller)),
        ),
      ),
      // OSD 统计浮层（Flutter 自绘，开关开启时显示）
      Positioned.fill(child: buildOsdOverlay(controller)),
    ],
  );
}

Widget buildDanmuView(VideoState videoState, LiveRoomController controller) {
  var padding = MediaQuery.of(videoState.context).padding;
  // completed: resizeDanmakuFontSize if clamped is true
  // danmakuFontResize is temp
  // 多开时每格有自己的字号（按格子高度算），优先于「按整窗高度缩放」的口径
  var reSize = controller.danmakuFontSizeOverride ?? controller.resolveWindowScaledDanmakuFontSize();
  controller.danmakuView ??= DanmakuScreen(
    createdController: controller.initDanmakuController,
    option: DanmakuOption(
      fontSize: reSize,
      area: AppSettingsController.instance.danmuArea.value,
      duration: AppSettingsController.instance.danmuSpeed.value,
      opacity: AppSettingsController.instance.danmuOpacity.value,
      strokeWidth: AppSettingsController.instance.danmuStrokeWidth.value,
      fontWeight: AppSettingsController.instance.danmuFontWeight.value,
      fontFamily: AppStyleSettingController.instance.curFontName.value,
    ),
  );
  return Positioned.fill(
    top: padding.top,
    bottom: padding.bottom,
    child: Obx(
      () => Offstage(
        offstage: !controller.showDanmakuState.value,
        child: Padding(
          padding: controller.fullScreenState.value
              ? EdgeInsets.only(
                  top: AppSettingsController.instance.danmuTopMargin.value,
                  bottom: AppSettingsController.instance.danmuBottomMargin.value,
                )
              : EdgeInsets.zero,
          child: controller.danmakuView!,
        ),
      ),
    ),
  );
}
