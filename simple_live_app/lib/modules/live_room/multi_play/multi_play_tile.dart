import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/modules/live_room/player/player_fit.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';

/// 多开网格里的一格：一路播放 + 它自己的弹幕 + 一条底部信息/控制条。
///
/// 不复用 `playerControls`：那套 OSD 有四十多个控件，摆在 240×135 的格子上既点不中
/// 也看不清。这里只留小格子上真能用的几件：换台 / 静音 / 全屏 / 刷新·清晰度·线路 / 关闭。
/// 完整 OSD 仍然可以从聚焦格双击进全屏后使用。
///
/// 信息与控制分居两角、各用一个**自适应大小的胶囊遮罩**兜住（左下：序号+名字+换台；
/// 右下：静音/全屏/更多/关闭），中间不画遮罩——早期那版是一条横跨整幅画面的黑条，
/// 中间一大段纯装饰，既土又白占画面。整组随网格的显隐一起出现/隐藏，不做常驻。
class MultiPlayTile extends StatelessWidget {
  const MultiPlayTile({
    super.key,
    required this.page,
    required this.tile,
    required this.index,
    required this.focused,
    required this.chromeVisible,
    required this.onInteract,
  });

  /// 页面主格：全屏是窗口级操作，只能由它来开。
  final LiveRoomController page;

  /// 本格自己的 controller。
  final LiveRoomController tile;

  /// 在会话 slots 里的下标（0 = 主格，不可关闭）；显示为「第 N 路」。
  final int index;

  final bool focused;

  /// 是否显示底部信息条。由网格统一控制：鼠标在网格里动一下，四路一起出现，
  /// 停手几秒一起隐去。
  final bool chromeVisible;

  /// 本格被交互时通知网格——把「自动隐藏」的倒计时续上（打开菜单时尤其需要）。
  final VoidCallback onInteract;

  /// 底部条里的图标按钮统一样式：小尺寸、无内边距、白色前景。
  static final ButtonStyle _iconStyle = IconButton.styleFrom(
    minimumSize: const Size(30, 30),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: AppStyle.radius8,
        border: Border.all(
          color: focused ? colorScheme.primary : Colors.white12,
          width: focused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: Obx(_buildVideo)),
          Positioned.fill(child: _buildStates()),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onInteract();
                page.multiPlay.focusSlot(index);
              },
              onDoubleTap: () {
                // 双击切换全屏，与单画面「双击视频」一致：进得去也出得来。
                // 之前只调 enterFullScreen，进了全屏再双击还是「进全屏」，
                // 于是只能靠 ESC 退出——和单画面割裂。
                //
                // 双击时 Flutter 会先派发一次 onTap（焦点已落在这一格），这里再显式
                // 设一次只是不依赖那个行为。
                page.multiPlay.focusSlot(index);
                if (page.fullScreenState.value) {
                  page.exitFull();
                } else {
                  page.enterFullScreen();
                }
              },
            ),
          ),
          // ⚠️ 隐藏时**不能**把这一层从树里摘掉：`PopupMenuButton` 在菜单打开期间若被
          // unmount，`showButtonMenu` 的 `.then` 里有 `if (!mounted) return null`
          // （popup_menu.dart），选中的结果会被静默丢弃——表现就是「更多」里的三项和
          // 换台都点了没反应。所以这里是「常挂 + IgnorePointer + 淡出」，不是条件移除。
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              ignoring: !chromeVisible,
              child: AnimatedOpacity(
                opacity: chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Row(
                  // 两个胶囊分居左右，中间的空白**不画遮罩**——早期那版是一条横跨
                  // 整幅画面的黑条，中间一大段纯装饰，既土又白占画面。
                  // 用 spaceBetween 而不是 Spacer：Spacer 会先按 flex 占掉一半，
                  // 窄格子下信息胶囊会被无谓地挤短。
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: _buildInfoPill(colorScheme)),
                    _buildControlsPill(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 左下角的信息胶囊：`① 主播名 ▾`。
  ///
  /// 遮罩只包住这一簇；名字用 `Flexible` 兜住（窄格子自动省略号），
  /// 4×1 那种只有 240 宽的格子也不会溢出。
  Widget _buildInfoPill(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: AppStyle.radius8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 序号与名字只是展示，必须包 IgnorePointer：`Text`（`RenderParagraph`）本身
          // 会参与命中测试，不包起来这一簇就成了死区，点它落不到正下方
          // 「点一下切焦点」的手势上（之前重构时把这层弄丢了，昵称就点不动了）。
          IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSlotBadge(colorScheme),
                const SizedBox(width: 6),
                Flexible(child: _buildName()),
              ],
            ),
          ),
          _buildSwitchButton(),
        ],
      ),
    );
  }

  /// 右下角的按钮胶囊：静音 / 全屏 / 更多 / 关闭。
  Widget _buildControlsPill() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: AppStyle.radius8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TileVolumeButton(page: page, tile: tile, onInteract: onInteract),
          _buildFullScreenButton(),
          _buildMoreButton(),
          // 主格是页面本身（路由绑定死的那个 controller），销不得：关它等于拆整页
          if (index > 0) _buildCloseButton(),
        ],
      ),
    );
  }

  /// 序号圆牌。后面所有「第 N 路」的引用（换台菜单、侧栏跟随提示）都靠它对上号。
  Widget _buildSlotBadge(ColorScheme colorScheme) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: focused ? colorScheme.primary : Colors.white24,
        shape: BoxShape.circle,
      ),
      child: Text(
        "${index + 1}",
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w600,
          color: focused ? colorScheme.onPrimary : Colors.white,
        ),
      ),
    );
  }

  Widget _buildName() {
    return Obx(() {
      final name = tile.detail.value?.userName;
      return Text(
        (name == null || name.isEmpty) ? "第${index + 1}路" : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.white),
      );
    });
  }

  /// 昵称后的 ▾：换这一格播哪一路。
  ///
  /// 菜单只列**正在直播**的关注主播，每行「主播名 + 平台」——认陌生人够用，
  /// 又比带头像的面板轻。
  Widget _buildSwitchButton() {
    return PopupMenuButton<FollowUser>(
      tooltip: "换台",
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: const Icon(Icons.arrow_drop_down),
      style: _iconStyle,
      // 菜单开着时把网格那几秒倒计时续上，避免底栏（连同这个入口）被隐藏
      onOpened: onInteract,
      itemBuilder: (context) {
        // 在菜单打开时才扫关注列表：之前放在 build 里，四格每帧都要扫一遍
        final entries = page.multiPlay.buildSwitchEntries();
        if (entries.isEmpty) {
          return const [
            AppPopupMenuItem<FollowUser>(
              enabled: false,
              child: SizedBox(
                width: 220,
                child: Text("关注列表里没有正在直播的主播"),
              ),
            ),
          ];
        }
        return [
          for (final entry in entries)
            AppPopupMenuItem<FollowUser>(
              value: entry.user,
              // 定宽：菜单容器宽度可能是无界的，Expanded 撞上无界约束会直接报错
              child: SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.user.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.platform,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (entry.isPlaying) ...[
                      const SizedBox(width: 6),
                      const Text("在播", style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
        ];
      },
      onSelected: (user) {
        final site = Sites.allSites[user.siteId];
        if (site == null) {
          return;
        }
        page.multiPlay.replaceTileRoom(tile, site, user.roomId);
      },
    );
  }

  Widget _buildFullScreenButton() {
    return IconButton(
      tooltip: "全屏",
      style: _iconStyle,
      iconSize: 20,
      icon: const Icon(Icons.fullscreen),
      onPressed: () {
        onInteract();
        page.multiPlay.focusSlot(index);
        if (page.fullScreenState.value) {
          page.exitFull();
        } else {
          page.enterFullScreen();
        }
      },
    );
  }

  /// 低频动作收进「更多」：刷新 / 切换清晰度 / 切换线路。
  Widget _buildMoreButton() {
    return PopupMenuButton<int>(
      tooltip: "更多",
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: const Icon(Icons.more_horiz),
      style: _iconStyle,
      onOpened: onInteract,
      itemBuilder: (context) => const [
        AppPopupMenuItem(value: 1, child: Text("刷新")),
        AppPopupMenuItem(value: 2, child: Text("切换清晰度")),
        AppPopupMenuItem(value: 3, child: Text("切换线路")),
      ],
      onSelected: (value) {
        switch (value) {
          case 1:
            tile.refreshRoom();
          case 2:
            tile.showQualitySheet();
          case 3:
            tile.showPlayUrlsSheet();
        }
      },
    );
  }

  Widget _buildCloseButton() {
    return IconButton(
      tooltip: "关闭这一路",
      style: _iconStyle,
      iconSize: 20,
      icon: const Icon(Icons.close),
      onPressed: () {
        onInteract();
        page.multiPlay.removeTile(tile);
      },
    );
  }

  Widget _buildVideo() {
    final settings = AppSettingsController.instance;
    final fit = resolvePlayerFit();
    return Video(
      key: tile.globalPlayerKey,
      controller: tile.videoController,
      pauseUponEnteringBackgroundMode: settings.playerAutoPause.value,
      resumeUponEnteringForegroundMode: settings.playerAutoPause.value,
      // 弹幕层必须在 controls 里：buildDanmuView 返回的是 Positioned.fill，
      // 直接当 controls 的返回值会因为不在 Stack 里而报错。
      controls: (state) => Stack(children: [buildDanmuView(state, tile)]),
      aspectRatio: fit.aspectRatio,
      fit: fit.fit,
      // 保持唤醒由主格那份负责，四路各开一次没有意义
      wakelock: false,
    );
  }

  /// 加载 / 未开播 / 加载失败三态。
  ///
  /// 副格不走 `SmartDialog.showLoading`（那是全局单例浮层，四路会互相顶掉），
  /// 所以加载态只能在格子里自己表达。
  Widget _buildStates() {
    return Obx(() {
      if (tile.loadError.value) {
        return _buildCenterLabel("加载失败", tile.error?.toString());
      }
      if (tile.detail.value == null) {
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        );
      }
      if (!tile.liveStatus.value) {
        return _buildCenterLabel("未开播", null);
      }
      return const SizedBox.shrink();
    });
  }

  Widget _buildCenterLabel(String text, String? detail) {
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 音量按钮：点一下静音 / 取消静音；**指针悬停在它上面滚动滚轮**可微调这一路的音量。
///
/// 只有静音开关是不够用的：静音状态下想「加一点点声音」就无路可走，只能先取消静音再去
/// 动总音量，而那会连带影响其他路。滚轮改的是这一路自己的音量系数，与可选压低叠加。
/// 改完在按钮上方浮一个百分比、停 1.2 秒自隐——否则滚轮的改动完全看不见。
class _TileVolumeButton extends StatefulWidget {
  const _TileVolumeButton({
    required this.page,
    required this.tile,
    required this.onInteract,
  });

  final LiveRoomController page;
  final LiveRoomController tile;
  final VoidCallback onInteract;

  /// 滚轮一格的步进。
  static const double _step = 0.05;

  @override
  State<_TileVolumeButton> createState() => _TileVolumeButtonState();
}

class _TileVolumeButtonState extends State<_TileVolumeButton> {
  bool _showingTip = false;
  Timer? _tipTimer;

  void _showTip() {
    _tipTimer?.cancel();
    if (!_showingTip) {
      setState(() => _showingTip = true);
    }
    _tipTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showingTip = false);
      }
    });
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = widget.tile;
    return Listener(
      // 只在指针停在这个按钮上滚动才动这一路，避免与页面别处的滚轮抢
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        widget.onInteract();
        widget.page.multiPlay.nudgeTileVolume(
          tile,
          event.scrollDelta.dy > 0 ? -_TileVolumeButton._step : _TileVolumeButton._step,
        );
        _showTip();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Obx(
            () => IconButton(
              tooltip: tile.muted ? "取消静音（悬停滚轮调音量）" : "静音（悬停滚轮调音量）",
              style: MultiPlayTile._iconStyle,
              iconSize: 20,
              icon: Icon(tile.muted ? Icons.volume_off : Icons.volume_up),
              onPressed: () {
                widget.onInteract();
                widget.page.multiPlay.toggleTileMute(tile);
              },
            ),
          ),
          if (_showingTip)
            Positioned(
              right: 0,
              bottom: 34,
              child: IgnorePointer(
                child: Obx(
                  () => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: AppStyle.radius8,
                    ),
                    child: Text(
                      "${(tile.volumeFactor.value * 100).round()}%",
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}