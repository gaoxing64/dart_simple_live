import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 音量按钮此刻绑的是哪个量。
///
/// 绑的量按宿主不同是刻意决定（spec §3）：单播放的滑条必须是**总音量**
/// （那是 OSD 里唯一的总音量入口，换成按路系数就等于把它藏了），格子绑**该格系数**。
/// 两者共用同一个浮层形态，面板上不再标「总音量／第 N 路」——它正锚在这一路的按钮
/// 头上，上下文由位置给（作者 2026-10-04：面板里只放滑条）。
class VolumeTarget {
  VolumeTarget.master(LiveRoomController page)
      : _page = page,
        _tile = null;

  VolumeTarget.tile(LiveRoomController tile)
      : _page = null,
        _tile = tile;

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

  /// 图标回答的是「这一路现在听得到吗」：本格被静音（`_owner.volumeFactor`，
  /// 与点击写的 [toggleMute] 同一个量）**或**当前绑定的比值已拖到 0。
  ///
  /// 后者只是显示侧的 `||`：把总音量拖到 0 时用户听到的是无声，图标仍亮
  /// `volume_up` 就是在撒谎；但这一读**不**引入第二条音量权威——写路径只有
  /// [toggleMute]（落 `_owner.volumeFactor`）与滑条（落各自绑定的量），
  /// 拖回总音量>0 图标就自己回来了，临时静音也绝不因此写进设置。
  ///
  /// 滑条回答的是另一个问题：「这一路／总音量现在多大」（master 绑 `playerVolume`、
  /// tile 绑 `volumeFactor`）。
  bool get muted => _owner.muted || ratio <= 0.001;

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

  /// 点一下静音／取消静音。
  ///
  /// 写路径必须与 [muted] 的读路径**对称**——这是它先前单向的根因：[muted] 读的是
  /// `_owner.muted || ratio <= 0.001`（两处任意为0 即静音），而旧的 [LiveRoomController
  /// .toggleMute] 只写 `volumeFactor` 这一套量。于是「总音量被滑条拖到 0」这种静音，
  /// 点图标只会去动 `volumeFactor`（它本来还是 1.0），总音量仍是 0 —— 听感上毫无变化，
  /// 图标也永远回不到 `volume_up`，控件就成了单向的。
  ///
  /// 现在按「是哪一处把它按成静音的」分别还原，两处都归零就两处都还原：
  /// - `volumeFactor == 0`（点图标静音造成的）：交给 [LiveRoomController.toggleMute]
  ///   还原到静音前的系数，与格子宿主同一套语义。
  /// - 总音量 `== 0`（滑条拖到 0 造成的）：写回全量。**不**去还原「拖到 0 之前的值」
  ///   —— 拖动是连续过程，那个值没有 well-defined 的定义（多半是拖动最后一个小步，
  ///   还原回去只有 5% 音量、仍然几乎听不见）。点图标是明确的「把声音还给我」，
  ///   给全量才是明确且一定听得见的答案；这与格子宿主 `_factorBeforeMute` 的初值
  ///   同为 1.0 是一致的。
  void toggleMute() {
    if (muted) {
      if (_owner.muted) {
        _owner.toggleMute();
      }
      if (isMaster && ratio <= 0.001) {
        setValueRatio(1.0);
      }
      return;
    }
    _owner.toggleMute();
  }
}

/// 音量按钮的三态：点击＝静音这一路，悬停＝出滑条浮层，滚轮＝±5%。
///
/// 点击静音要保住：原先格子上「点一下静音」是快按，滑条做成悬停弹出之后仍然不改它，
/// 否则「静音这路」从一次点击变成两次操作。
///
/// **四宿主一种形态**（作者 2026-10-04 定）：窗口化／全屏／小窗／格子的滑条都浮在按钮
/// **正上方居中**，样式回到改造前那条 `showVolumeSlider`——`Theme.cardColor` 圆角 12 的
/// 面板 + 默认 Material `Slider`（宽 200）。此前桌面条带走「行内向左长」、格子走
/// 「右上浮层」两套，他对手实物判的是：细白轨不像 Material、浮层偏在 icon 右上方。
/// 面板里只放滑条（连「总音量／第 N 路」那行标题也去掉：面板就锚在这一路的按钮正上方，
/// 上下文由锚点给）。
///
/// WHY 浮层必须挂进 `Overlay`，而不是在按钮外面套一层
/// `Stack(clipBehavior: Clip.none)` + `Positioned`（下一个读到这里的人一定会想再试
/// 一次 Positioned）：命中测试是逐层按**盒子自己的尺寸**把关的 —— `RenderBox.hitTest`
/// 先要求 `size.contains(position)` 才进孩子；`Positioned` 孩子不参与 `RenderStack` 的
/// 尺寸（那层 Stack 的盒子就只有按钮那么大），`RenderStack` 又只覆写了 `hitTestChildren`、
/// 没覆写 `hitTest`，而 `clipBehavior: Clip.none` 只影响绘制。结果浮在按钮盒外的滑条
/// 画得出来、指针进不去：移过去就掉出按钮的 `MouseRegion`（`onExit` → 当场收起），
/// 点它还会穿到下层。
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
    this.isTouch = false,
    this.onInteract,
  });

  final VolumeTarget target;
  final ButtonStyle style;
  final double iconSize;
  final VoidCallback? onInteract;

  static const double _step = 0.05;

  /// 面板宽度＝滑条宽 + 左右内边距。定位要夹取水平位置，得先知道自己是多宽。
  static const double _sliderWidth = 200;
  static const double _panelPadding = 4;
  static const double _panelWidth = _sliderWidth + _panelPadding * 2;

  /// 浮层与按钮之间的空隙，靠 [_hideGrace] 跨过去。
  static const double _popoverGap = 6;

  /// 收起宽限：只要够指针跨过按钮盒与浮层之间那 6px 就行，不该做成可感知的延迟。
  static const Duration _hideGrace = Duration(milliseconds: 150);

  /// 触屏上浮层停留多久后自动收起（没有 hover 可以依赖，也没有点外部就关的遮罩）。
  /// 每次拖动滑条都会重新计时，所以「拖到一半被收掉」不会发生。
  static const Duration _touchLinger = Duration(milliseconds: 2500);

  /// true＝触屏（没有 hover）：点击这颗按钮开/关浮层，**不再**是静音。
  /// 静音在触屏上另有入口——`⋮` 里那行 `muteTile`（见 `player_actions.dart` 的
  /// [PlayerActionId.muteTile]）。桌面恒 false，保持「点＝静音 / 悬停＝滑条」。
  final bool isTouch;

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

  /// 触屏上浮层的停留计时（[_touchLinger]）。桌面恒为 null。
  Timer? _touchTimer;

  @override
  void dispose() {
    _tipTimer?.cancel();
    _hideTimer?.cancel();
    _touchTimer?.cancel();
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
    _scheduleHide();
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
    _touchTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _hovering = false;
      _popoverHovered = false;
    });
    _syncPopover();
  }

  /// 触屏：点一下开浮层、再点一下关。没有 hover 可依赖，停留时间只能由计时器给；
  /// 每次拖动滑条都会重新计时（见 `_buildSlider` 的 onChanged），不会拖到一半被收掉。
  void _toggleByTouch() {
    if (_popover.isShowing) {
      _hide();
      return;
    }
    setState(() => _hovering = true);
    _syncPopover();
    _restartTouchLinger();
  }

  void _restartTouchLinger() {
    _touchTimer?.cancel();
    _touchTimer = Timer(VolumeActionWidget._touchLinger, _hide);
  }

  /// 可见性由两块区域共同决定：指针在按钮上、或在浮层里，两边都离开才收起。
  void _syncPopover() {
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

  /// 默认 Material `Slider`：改造前那条 `showVolumeSlider` 就是这个形态。
  /// 别再套自定义 `SliderTheme`（细白轨 + `RoundedRectSliderTrackShape` 是上一版的样子，
  /// 作者判「不像 Material Design」），深浅主题跟着 `cardColor` 一起走。
  Widget _buildSlider() {
    return Obx(() {
      // 只夹**显示**用的比值，不引入第二条音量权威：存储里可能留着比后来调低的
      // `playerMaxVolume` 更大的值（只有 `setPlayerMaxVolume` 会夹一次，读盘时不夹），
      // 而 `Slider(value:)` 断言 `value <= max`，越界就直接崩。写回去仍然是原值。
      final ratio = widget.target.ratio.clamp(0.0, 1.0);
      return SizedBox(
        width: VolumeActionWidget._sliderWidth,
        child: Slider(
          value: ratio,
          onChanged: (value) {
            widget.onInteract?.call();
            widget.target.setValueRatio(value);
            // 拖动也要浮一下读数：与滚轮同一条规则。之前只有 `_onPointerSignal`
            // 调 `_showTip`，于是「滚着调有百分比、拖着调没有」——而拖动恰恰是
            // 眼睛盯着滑条的时候，那一刻最需要读数确认拖到了哪儿。
            // 每次拖动都重新计时，持续拖动期间读数会一直挂着。
            _showTip();
            if (widget.isTouch) {
              _restartTouchLinger();
            }
          },
        ),
      );
    });
  }

  /// 滚轮改完浮一下百分比：滑条虽然一直在面板里，但滚的时候眼睛未必在看它，
  /// 有个读数才知道这次改到了哪儿。颜色交给面板的 `Material`（`cardColor` 上不能用
  /// 死白色，浅色主题会直接看不见）。
  Widget _buildTip() {
    return IgnorePointer(
      child: Obx(
        () => Text(
          "${(widget.target.ratio * 100).round()}%",
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  /// 浮层本体：由 `OverlayPortal` 构建在 `Overlay` 里，跟着按钮定位，
  /// 并且**自带** `MouseRegion`（指针落进来就不收起）。
  ///
  /// 它是本 widget 元素树里的孩子（只是被渲染到 Overlay 上），所以读得到宿主状态
  /// （`_showingTip`），宿主 `setState` 会直接带它重建。
  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    // 按钮的**上边中点**，换算到 Overlay 的坐标系（OverlayPortal 每帧布局时重算，
    // 所以胶囊/条带移位时浮层会跟着走）。取中点不是右上角：改造前那条
    // `SmartDialog.showAttach` 用的就是 `Alignment.topCenter`，浮层正压在 icon 头上；
    // 上一版锚在右上角再向左展开，作者手测判的就是这个「多开时浮层偏了」。
    final anchor = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(info.childSize.width / 2, 0),
    );
    // 夹在 Overlay 内：贴窗口左右边的格子（多开 2×2 里最左／最右那两格）不能让
    // 208 宽的面板被裁掉一半。
    const gap = VolumeActionWidget._popoverGap;
    final panelWidth = VolumeActionWidget._panelWidth;
    final left = (anchor.dx - panelWidth / 2).clamp(
      4.0,
      (info.overlaySize.width - panelWidth - 4.0).clamp(4.0, double.infinity),
    );
    final bottom = info.overlaySize.height - anchor.dy + gap;
    return Positioned(
      left: left,
      bottom: bottom,
      child: MouseRegion(
        onEnter: (_) => _onPopoverEnter(),
        onExit: (_) => _scheduleHide(),
        child: Material(
          // 与改造前 `showVolumeSlider` 同一份底：cardColor + 圆角 12 + 内边距 4。
          color: Theme.of(context).cardColor,
          borderRadius: AppStyle.radius12,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(VolumeActionWidget._panelPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 读数也放进面板里：它若还留在按钮那一层的 `Positioned`，
                // 会被这块 Overlay 面板盖住，滚轮调完看不见数值。
                if (_showingTip) _buildTip(),
                _buildSlider(),
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
        // 只在指针停在这颗按钮上滚动才动这一路，避免与页面别处的滚轮抢。
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _onPointerSignal(event);
          }
        },
        child: Obx(() {
          final muted = widget.target.muted;
          return IconButton(
            tooltip: widget.isTouch
                ? "音量"
                : muted
                ? "取消静音（悬停可调音量）"
                : "静音（悬停可调音量）",
            style: widget.style,
            iconSize: widget.iconSize,
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () {
              widget.onInteract?.call();
              if (widget.isTouch) {
                _toggleByTouch();
                return;
              }
              widget.target.toggleMute();
            },
          );
        }),
      ),
    );
    // 锚点就是这个按钮区域本身：`overlayChildLayoutBuilder` 在每次布局时把它的
    // 位置与尺寸交给 `_buildPopover`，浮层因此能跟着窗口缩放/胶囊移位。
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _popover,
      overlayChildBuilder: _buildPopover,
      child: control,
    );
  }
}
