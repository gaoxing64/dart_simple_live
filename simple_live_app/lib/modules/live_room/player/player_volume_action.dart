import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 音量按钮此刻绑的是哪个量。
///
/// 形态一致、绑的量按宿主不同是刻意决定（spec §3）：单播放的滑条必须是**总音量**
/// （那是 OSD 里唯一的总音量入口，换成按路系数就等于把它藏了），格子绑**该格系数**。
/// 浮层标题把区别写出来（`总音量` / `第 2 路`），免得用户在格子上拖了一下发现四路都变了。
class VolumeTarget {
  VolumeTarget.master(LiveRoomController page)
      : label = "总音量",
        _page = page,
        _tile = null;

  VolumeTarget.tile(LiveRoomController tile)
      : label = "第${tile.tileSlot + 1}路",
        _page = null,
        _tile = tile;

  final String label;
  final LiveRoomController? _page;
  final LiveRoomController? _tile;

  /// 是否绑总音量（true＝单播放宿主，false＝格子宿主）。
  bool get isMaster => _tile == null;

  /// 这一路／这一页的 controller：静音与「总音量变更后重算各路」都归它。
  LiveRoomController get _owner => _tile ?? _page!;

  /// 换算给显示与滚轮步进的音量比值（tile 本来就是 0~1 的系数，master 是
  /// `playerVolume / playerMaxVolume`——上限被调低过又留着更大的音量时它会 >1，
  /// 只在显示侧夹住，这里不替设置再夹一遍）。
  double get ratio {
    if (isMaster) {
      final settings = AppSettingsController.instance;
      // playerMaxVolume 是 Rx<int>（mpv 的 volume-max）：这里只做归一化，
      // 上限的夹取仍然只在设置侧那一条路径上。
      final max = settings.playerMaxVolume.value.toDouble();
      return max <= 0 ? 0 : settings.playerVolume.value / max;
    }
    return _tile!.volumeFactor.value;
  }

  /// 图标只回答一件事：「这一路被我静音了吗」——所以两种宿主都读 `_owner` 的
  /// `volumeFactor`，与点击写的 [toggleMute] 是同一个量（单播放条带上曾经读的是
  /// 总音量派生的比值，于是点静音把声音压掉了、图标却仍是 `volume_up`）。
  ///
  /// 滑条回答的是另一个问题：「这一路／总音量现在多大」（master 绑 `playerVolume`、
  /// tile 绑 `volumeFactor`），所以图标与滑条刻意不对称：把总音量拖到 0，图标仍是
  /// `volume_up`，因为这路本身并没有被静音。静音也绝不写 0 总音量——那会把一个
  /// 临时状态持久化进设置。
  bool get muted => _owner.muted;

  void setValueRatio(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    if (isMaster) {
      final settings = AppSettingsController.instance;
      // 先转 double 再乘：int×double 的静态类型是 num，喂不进 setPlayerVolume。
      final max = settings.playerMaxVolume.value.toDouble();
      settings.setPlayerVolume(max * clamped);
      // 总音量是唯一的音量权威：压低开启时非聚焦格按 ratio 跟着走
      _owner.multiPlay.applyVolumes();
      return;
    }
    // 唯一的夹取路径是 nudgeVolumeFactor：这里把绝对值换算成增量交给它，
    // 顺带由它维护「静音前的系数」，取消静音才能还原到拖过的值。
    _tile!.nudgeVolumeFactor(clamped - _tile!.volumeFactor.value);
  }

  void nudge(double deltaRatio) => setValueRatio(ratio + deltaRatio);

  /// 点一下静音／取消静音这一路：写的是 `_owner.volumeFactor`，与 [muted] 读的
  /// 同一个量（两种宿主都一样），并由它记住静音前的系数。
  void toggleMute() => _owner.toggleMute();
}

/// 音量按钮的三态：点击＝静音这一路，悬停＝出滑条，滚轮＝±5%。
///
/// 点击静音要保住：原先格子上「点一下静音」是快按，滑条做成悬停弹出之后仍然不改它，
/// 否则「静音这路」从一次点击变成两次操作。
///
/// 两种放置：
/// * 条带宿主（[overlayPopover] == false）滑条**行内**展开：滑条排在按钮之前、向左长，
///   右侧那簇不动（宽度由宿主的 `Expanded` 吃掉），零位移。
/// * 格子宿主（true）滑条**浮在按钮上方**、向左上展开：格子胶囊只有 240px 宽，
///   行内展开会把旁边的昵称挤成省略号。
///
/// WHY 浮层那一种必须挂进 `Overlay`，而不是在按钮外面套一层
/// `Stack(clipBehavior: Clip.none)` + `Positioned`（下一个读到这里的人一定会想再试
/// 一次 Positioned）：命中测试是逐层按**盒子自己的尺寸**把关的 —— `RenderBox.hitTest`
/// 先要求 `size.contains(position)` 才进孩子；`Positioned` 孩子不参与 `RenderStack` 的
/// 尺寸（那层 Stack 的盒子就只有按钮那么大），`RenderStack` 又只覆写了 `hitTestChildren`、
/// 没覆写 `hitTest`，而 `clipBehavior: Clip.none` 只影响绘制。结果浮在按钮盒外的滑条
/// 画得出来、指针进不去：移过去就掉出按钮的 `MouseRegion`（`onExit` → 当场收起），
/// 点它还会穿到下层。行内那一种没这问题，滑条是 Row 的真孩子、盒子跟着一起变大。
///
/// 同一套 `Positioned` 挂到 `Overlay` 上就同时画得出、点得动：Overlay 的
/// `_RenderTheater` 盒子铺满整屏，`Positioned` 的孩子既落在它的命中区域里、又按自身
/// 内容定尺寸（Overlay 发给 overlay 孩子的是铺满整屏的紧约束，只有 `Positioned` 会把
/// 松约束传给孩子 —— 直接返回面板本体会被拉成整屏，底色与 `MouseRegion` 跟着盖住全屏）。
/// 这正是 Flutter 自己 `Tooltip` 的做法，这里用
/// `OverlayPortal.overlayChildLayoutBuilder` 拿锚点在 Overlay 里的位置。
///
/// 指针从按钮走到浮层要穿过两者之间那段空隙（两个 `MouseRegion` 都不命中），
/// 所以收起走 [_hideGrace] 宽限：离开按钮先计时，落进浮层就取消。
///
/// 悬停是桌面专属输入：触屏没有 `onEnter`，滑条永远不展开，但按钮的点击路径照常工作，
/// 所以移动端不会因为这套三态而丢功能。
class VolumeActionWidget extends StatefulWidget {
  const VolumeActionWidget({
    super.key,
    required this.target,
    required this.style,
    this.iconSize = 24,
    this.overlayPopover = false,
    this.onInteract,
  });

  final VolumeTarget target;
  final ButtonStyle style;
  final double iconSize;

  /// true＝滑条浮在按钮上方并挂进 `Overlay`（格子宿主）；false＝行内展开（条带宿主）。
  final bool overlayPopover;
  final VoidCallback? onInteract;

  static const double _step = 0.05;
  static const double _sliderWidth = 88;

  /// 浮层与按钮之间的空隙，靠 [_hideGrace] 跨过去。
  static const double _popoverGap = 6;

  /// 收起宽限：只要够指针跨过按钮盒与浮层之间那 6px 就行，不该做成可感知的延迟。
  static const Duration _hideGrace = Duration(milliseconds: 150);

  @override
  State<VolumeActionWidget> createState() => _VolumeActionWidgetState();
}

class _VolumeActionWidgetState extends State<VolumeActionWidget> {
  /// 浮层的开关（内容见 `_buildPopover`）。
  final OverlayPortalController _popover = OverlayPortalController();

  /// 指针停在按钮上。
  bool _hovering = false;

  /// 指针停在浮层里（滑条能被拖住就靠它）。
  bool _popoverHovered = false;

  bool _showingTip = false;
  Timer? _tipTimer;
  Timer? _hideTimer;

  @override
  void dispose() {
    _tipTimer?.cancel();
    _hideTimer?.cancel();
    // 浮层是 `OverlayPortal` 的孩子，随本 widget 一起卸载，不必（也不该在 dispose 里）
    // 再调 `_popover.hide()`——那时控制器的 attach 目标已经没了。
    super.dispose();
  }

  void _onButtonEnter() {
    _hideTimer?.cancel();
    setState(() => _hovering = true);
    _syncPopover();
  }

  void _onButtonExit() {
    // 行内那一种滑条就在本盒子里，指针走到它上面不会失焦，保持原来那样立即收起。
    if (widget.overlayPopover) {
      _scheduleHide();
    } else {
      _hide();
    }
  }

  /// 浮层自己的 `MouseRegion`：指针落进来就把收起计时取消掉。
  void _onPopoverEnter() {
    _hideTimer?.cancel();
    setState(() => _popoverHovered = true);
    _syncPopover();
  }

  /// 离开按钮**或**离开浮层都走这里，而不是直接收起：两处之间那段空隙里两个
  /// `MouseRegion` 都不命中，立刻收就等于「鼠标永远追不上滑条」。
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(VolumeActionWidget._hideGrace, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _hovering = false;
      _popoverHovered = false;
    });
    _syncPopover();
  }

  /// 可见性由两块区域共同决定：指针在按钮上、或在浮层里，两边都离开才收起。
  void _syncPopover() {
    // 行内那一种没有 OverlayPortal（滑条就在本盒子里），控制器闲着。
    if (!widget.overlayPopover) {
      return;
    }
    if (_hovering || _popoverHovered) {
      if (!_popover.isShowing) {
        _popover.show();
      }
    } else if (_popover.isShowing) {
      _popover.hide();
    }
  }

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

  void _onPointerSignal(PointerScrollEvent event) {
    widget.onInteract?.call();
    widget.target.nudge(
      event.scrollDelta.dy > 0
          ? -VolumeActionWidget._step
          : VolumeActionWidget._step,
    );
    _showTip();
  }

  Widget _buildSlider(BuildContext context) {
    return Obx(() {
      // 只夹**显示**用的比值，不引入第二条音量权威：存储里可能留着比后来调低的
      // `playerMaxVolume` 更大的值（只有 `setPlayerMaxVolume` 会夹一次，读盘时不夹），
      // 而 `Slider(value:)` 断言 `value <= max`，越界就直接崩。写回去仍然是原值。
      final ratio = widget.target.ratio.clamp(0.0, 1.0);
      return SizedBox(
        width: VolumeActionWidget._sliderWidth,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: ratio,
            onChanged: (value) {
              widget.onInteract?.call();
              widget.target.setValueRatio(value);
            },
          ),
        ),
      );
    });
  }

  /// 滚轮改完浮一下百分比：滑条只在悬停时出现，滚轮却常常发生在「刚滚完就走」，
  /// 没有读数就完全看不见这次改了什么。
  Widget _buildTip() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: AppStyle.radius8,
        ),
        child: Obx(
          () => Text(
            "${(widget.target.ratio * 100).round()}%",
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 浮层本体：由 `OverlayPortal` 构建在 `Overlay` 里，跟着按钮定位，
  /// 并且**自带** `MouseRegion`（指针落进来就不收起）。
  ///
  /// 它是本 widget 元素树里的孩子（只是被渲染到 Overlay 上），所以读得到宿主状态
  /// （`_showingTip`、`target.label`），宿主 `setState` 会直接带它重建。
  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    // 按钮的右上角，换算到目标 Overlay 的坐标系（OverlayPortal 每帧布局时重算，
    // 所以胶囊/条带移位时浮层会跟着走）。
    final anchor = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(info.childSize.width, 0),
    );
    final gap = VolumeActionWidget._popoverGap;
    // 面板右下角停在按钮右上角上方 `gap` 处：向左上展开，不挤动格子胶囊里旁边的
    // 控件。按钮贴近 Overlay 上沿时浮层会被裁掉，留位由接线方（Task 9）复核。
    final right = info.overlaySize.width - anchor.dx;
    final bottom = info.overlaySize.height - anchor.dy + gap;
    return Positioned(
      right: right,
      bottom: bottom,
      child: MouseRegion(
        onEnter: (_) => _onPopoverEnter(),
        onExit: (_) => _scheduleHide(),
        child: Material(
          // 浮层里没有 Scaffold，而 `Slider` 调试期断言要有 Material 祖先；
          // 顺便由它画面板底色与圆角。
          color: Colors.black54,
          borderRadius: AppStyle.radius8,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.target.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    // 读数也放进面板里：它若还留在按钮那一层的 `Positioned`，
                    // 会被这块 Overlay 面板盖住，滚轮调完看不见数值。
                    if (_showingTip) ...[
                      const SizedBox(width: 4),
                      _buildTip(),
                    ],
                  ],
                ),
                _buildSlider(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final control = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onButtonEnter(),
      onExit: (_) => _onButtonExit(),
      child: Listener(
        // 只在指针停在这颗按钮（含行内展开的滑条/读数）上滚动才动这一路，
        // 避免与页面别处的滚轮抢。
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _onPointerSignal(event);
          }
        },
        child: Obx(() {
          final button = IconButton(
            tooltip: widget.target.muted ? "取消静音（悬停可调音量）" : "静音（悬停可调音量）",
            style: widget.style,
            iconSize: widget.iconSize,
            icon: Icon(widget.target.muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () {
              widget.onInteract?.call();
              widget.target.toggleMute();
            },
          );
          if (widget.overlayPopover) {
            // 滑条不在这棵树里，它由 `OverlayPortal` 渲染进 Overlay
            // （见 `_buildPopover` 的 WHY：按钮盒外的 Positioned 接不住指针）。
            return button;
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hovering) _buildSlider(context),
              button,
              if (_showingTip)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const SizedBox(width: 0, height: 24),
                    Positioned(right: 0, bottom: 26, child: _buildTip()),
                  ],
                ),
            ],
          );
        }),
      ),
    );
    if (!widget.overlayPopover) {
      return control;
    }
    // 锚点就是这个按钮区域本身：`overlayChildLayoutBuilder` 在每次布局时把它的
    // 位置与尺寸交给 `_buildPopover`，浮层因此能跟着窗口缩放/胶囊移位。
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _popover,
      overlayChildBuilder: _buildPopover,
      child: control,
    );
  }
}
