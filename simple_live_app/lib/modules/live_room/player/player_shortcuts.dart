/// 直播间视频区的键盘快捷键**执行层**。
///
/// 键位是用户可配的（模型、默认值、编解码与匹配规则都在 `shortcut_binding.dart`，
/// 覆盖表存在 `AppSettingsController.shortcutOverrides`）。本文件只做两件事：
/// 把按下的键经配置解析成 [PlayerShortcut]，再把动作派给**既有入口**
/// （`invokePlayerAction` / `VolumeTarget` / 页面手势方法）。动作实现一处都不复制——
/// 复制出来的第二份动作语义，迟早与按钮那一条漂移。
///
/// 默认键位（参考 PiliPlus 的播放器手势集，直播场景做两处最小适配：直播没有进度条，
/// 原本归 seek 的 ←/→ 改成上下切线路；换台面板只在全屏与多开格生效，与
/// `_available(PlayerActionId.pick)` 的既有裁定同源）：
///
/// | 键 | 动作 |
/// |---|---|
/// | `Space` | 播放 / 暂停 |
/// | `F` | 全屏 / 退出全屏 |
/// | `Esc` | 退出 / 关闭播放器 |
/// | `D` | 弹幕开关 |
/// | `P` | 小窗播放 / 退出小窗 |
/// | `M` | 静音 / 取消静音 |
/// | `S` | 截图 |
/// | `L` | 锁定 / 解锁控制条 |
/// | `R` | 刷新直播间 |
/// | `Q` | 清晰度 |
/// | `G` | 换台（仅全屏／多开格） |
/// | `↑` / `↓` | 音量 ±5% |
/// | `←` / `→` | 上 / 下一条线路（仅多线路时） |
/// | `Enter` | 显示 / 隐藏控制条 |
/// | `1`–`4` | 多开时聚焦第 N 路 |
library;

import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 音量每按一次的步进，与音量浮层滚轮（`VolumeActionWidget._step`）同一个量。
const double kShortcutVolumeStep = 0.05;

/// 把 [PlayerShortcuts] 挂到视频区外面，快捷键即在此子树有焦点时生效。
///
/// 焦点策略（与 PiliPlus `PlayerFocus` 同一个模式）：
/// - `autofocus: true` 让进直播间就能直接按键；
/// - [Listener] 的 `onPointerDown` 负责**抢回**焦点——用户点过聊天栏、点过条带按钮
///   之后焦点在别处，点一下画面快捷键就回来。
///
/// `Listener` 不参与手势竞技（只旁听指针事件），所以它不会顶掉内部控制条自己的
/// `onTap` / 双击判定；`HitTestBehavior.translucent` 保证孩子照常命中。
class PlayerShortcuts extends StatefulWidget {
  const PlayerShortcuts({
    super.key,
    required this.controller,
    required this.child,
  });

  /// 页面主格。窗口级动作（全屏／小窗）与多开聚焦都以它为准。
  final LiveRoomController controller;

  final Widget child;

  @override
  State<PlayerShortcuts> createState() => _PlayerShortcutsState();
}

class _PlayerShortcutsState extends State<PlayerShortcuts> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerShortcuts');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 这一帧该按哪个宿主解释动作。
  ///
  /// 次序不能反：小窗态下 `fullScreenState` 同样为 true（见
  /// `PlayerController.enterSmallWindow`），先判全屏就会把小窗认成全屏，
  /// `P` 的「退出」分支永远走不到。多开排在前面，因为网格里每一格用的都是
  /// `PlayerHost.tile` 那份清单。
  PlayerHost get _host {
    final page = widget.controller;
    if (page.smallWindowState.value) {
      return PlayerHost.smallWindow;
    }
    if (page.multiPlay.isActive) {
      return PlayerHost.tile;
    }
    if (page.fullScreenState.value) {
      return PlayerHost.fullscreen;
    }
    return PlayerHost.windowed;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 只认按下与系统重复；抬起（KeyUpEvent）什么都不做。
    final isPress = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isPress && !isRepeat) {
      return KeyEventResult.ignored;
    }
    // 设置关掉时整体放行，Tab／方向键遍历等默认行为逐位不变。
    // 放行不等于「退出/关闭播放器」也失效：那个键由 `main.dart` 的全局链兜底，
    // 它读的是同一份配置但不受本开关约束（开关管的是播放器动作，不是应用级收口）。
    if (!AppSettingsController.instance.keyboardControl.value) {
      return KeyEventResult.ignored;
    }
    final hk = HardwareKeyboard.instance;
    final shortcut = matchShortcut(
      AppSettingsController.instance.effectiveShortcuts,
      event.logicalKey,
      shift: hk.isShiftPressed,
      ctrl: hk.isControlPressed,
      alt: hk.isAltPressed,
      meta: hk.isMetaPressed,
    );
    if (shortcut == null) {
      return KeyEventResult.ignored;
    }
    // 长按重复只放给音量：按住 ↑/↓ 连续加减是想要的节拍，而按住 F/D/M/L/P
    // 若也吃重复，就会一路来回开关全屏／弹幕／静音——那是纯粹的手感事故。
    // 吞掉但不执行：返回 handled 免得重复事件再冒到上层去干别的。
    if (isRepeat && !repeatablePlayerShortcuts.contains(shortcut)) {
      return KeyEventResult.handled;
    }
    // 空格与回车是 Flutter 用来「激活当前聚焦控件」的那两个键。Tab 走进视频区内部
    // 某颗按钮时（此时 primary focus 是那颗按钮而不是本节点），这两键必须留给它——
    // 否则键盘用户按不动控制条上的任何按钮了。
    //
    // 判据是**按下的键**而不是解析出的动作：键位可改之后，「会不会与控件激活撞车」
    // 只取决于按的是哪个键。用户把播放/暂停改到 `J`，那 `J` 就该无条件生效；
    // 反过来把别的动作改到空格，空格仍要让给聚焦中的按钮。
    if ((event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.enter) &&
        !_focusNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    _invoke(shortcut);
    return KeyEventResult.handled;
  }

  /// 「退出/关闭播放器」在直播间里的三级语义。
  ///
  /// 与 `main.dart` 那条全局链同源，但**多了第三级**：那两条都落空时收起当前页。
  /// 三级依次是：关弹窗 → 退出全屏/小窗 → 离开直播间。
  ///
  /// 为什么要在这里另写一份而不是让事件冒到 `main.dart`：焦点链只走一趟，本节点
  /// 返回 ignored 之后确实会到那条链，但本节点就再也无从知道「它有没有真的做了什么」，
  /// 于是没法决定要不要补第三级。写全三级、就地消费，是唯一能表达这个语义的形状。
  ///
  /// 第二级读 `page.fullScreenState` 而不是 `windowManager.isFullScreen()`：
  /// 前者覆盖移动端与桌面端的「应用内全屏」，后者只认 OS 全屏——用后者的话，
  /// 手机上按 Esc 会直接跳去第三级，把「退出全屏」这一档整个吃掉。
  void _exitPlayer(LiveRoomController page) {
    if (SmartDialog.checkExist()) {
      Utils.appBack();
      return;
    }
    if (page.fullScreenState.value) {
      // exitFull 自己会分辨小窗态（`smallWindowState` 为真时转交 exitSmallWindow）。
      page.exitFull();
      return;
    }
    // 多开时这一层会被页面的 PopScope 拦下，只收起其余几路，与侧键/返回键同语义。
    Utils.appBack();
  }

  void _invoke(PlayerShortcut shortcut) {
    final page = widget.controller;
    if (shortcut == PlayerShortcut.exitPlayer) {
      _exitPlayer(page);
      return;
    }
    // 非窗口级动作都作用于**聚焦格**：多开时聊天区、音量权威跟着它走，
    // 快捷键没有理由另立一份「作用于主格」的口径。
    final target = page.focused;
    final host = _host;

    switch (shortcut) {
      case PlayerShortcut.exitPlayer:
        // 上面已经截走；这条臂只为穷尽性存在，不该被走到。
        break;

      case PlayerShortcut.playPause:
        if (target.playbackPlaying) {
          target.playbackPause();
        } else {
          target.playbackPlay();
        }

      case PlayerShortcut.volumeUp:
      case PlayerShortcut.volumeDown:
        final delta = shortcut == PlayerShortcut.volumeUp
            ? kShortcutVolumeStep
            : -kShortcutVolumeStep;
        // 绑哪个量跟按钮同源（见 `player_action_bar.dart` 的 volume 分支）：
        // 格子绑本格系数，其余宿主绑总音量。
        if (host == PlayerHost.tile) {
          VolumeTarget.tile(target).nudge(delta);
        } else {
          VolumeTarget.master(page).nudge(delta);
        }

      case PlayerShortcut.prevLine:
      case PlayerShortcut.nextLine:
        if (!target.hasMultipleLines) {
          return;
        }
        final count = target.playUrls.length;
        final current = target.currentLineIndex;
        final int next;
        if (current < 0) {
          // 还没定过线路（`currentLineIndex` 初值 -1）：两个方向都落到第一条，
          // 拿 -1 去取模会算出「最后一条」，那是个凭空的跳转。
          next = 0;
        } else {
          final delta = shortcut == PlayerShortcut.nextLine ? 1 : -1;
          next = (current + delta + count) % count;
        }
        target.changePlayLine(next);

      case PlayerShortcut.toggleControls:
        target.onTap();

      case PlayerShortcut.lockControls:
        target.setLockState();

      case PlayerShortcut.focusSlot1:
      case PlayerShortcut.focusSlot2:
      case PlayerShortcut.focusSlot3:
      case PlayerShortcut.focusSlot4:
        final session = page.multiPlay;
        if (!session.isActive) {
          return;
        }
        final index = switch (shortcut) {
          PlayerShortcut.focusSlot1 => 0,
          PlayerShortcut.focusSlot2 => 1,
          PlayerShortcut.focusSlot3 => 2,
          _ => 3,
        };
        // 越界（例如只有两路却按了 4）静默忽略，`focusSlot` 自己也会挡一道。
        session.focusSlot(index);

      case PlayerShortcut.pick:
        // 换台有两副面孔，跟着宿主已有的形态走，不为快捷键新造第三种 UI：
        // - 全屏／多开格：开那块右侧面板（与条带上那颗 ▾ 同一个入口）。
        // - 窗口化（非全屏）：右侧面板在这里根本不该出现——它会盖住页面右栏的
        //   聊天区（作者对 pick 的既有裁定，见 `_available`）。改成把右栏切到
        //   「关注」Tab：同一个功能，用这个宿主本来就有的一栏承载。
        if (host == PlayerHost.fullscreen || host == PlayerHost.tile) {
          invokePlayerAction(
            host: host,
            target: target,
            page: page,
            id: PlayerActionId.pick,
          );
          return;
        }
        // 小窗里没有聊天栏可切，也不该开面板（会盖住画面）：保持不响应。
        if (host == PlayerHost.smallWindow) {
          return;
        }
        page.chatTab.value = LiveRoomController.kChatTabFollow;

      case PlayerShortcut.fullscreen:
      case PlayerShortcut.danmakuToggle:
      case PlayerShortcut.smallWindow:
      case PlayerShortcut.mute:
      case PlayerShortcut.screenshot:
      case PlayerShortcut.refresh:
      case PlayerShortcut.quality:
        invokePlayerAction(
          host: host,
          target: target,
          page: page,
          id: switch (shortcut) {
            PlayerShortcut.fullscreen => PlayerActionId.fullscreenToggle,
            PlayerShortcut.danmakuToggle => PlayerActionId.danmakuToggle,
            PlayerShortcut.smallWindow => PlayerActionId.smallWindow,
            PlayerShortcut.mute => PlayerActionId.volume,
            PlayerShortcut.screenshot => PlayerActionId.screenshot,
            PlayerShortcut.refresh => PlayerActionId.refresh,
            _ => PlayerActionId.quality,
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: widget.child,
      ),
    );
  }
}
