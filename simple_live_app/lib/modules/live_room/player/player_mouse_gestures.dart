import 'package:flutter/gestures.dart'
    show
        DragEndDetails,
        DragStartDetails,
        DragUpdateDetails,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerMoveEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent,
        TapGestureRecognizer,
        VerticalDragGestureRecognizer,
        kPrimaryButton,
        kPrecisePointerPanSlop,
        kTouchSlop;
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';

/// 桌面鼠标手势层：右键切换「窗口全屏」，中键切换 OS 全屏，竖向拖动调总音量，
/// 滚轮在画面内任意位置调总音量。
///
/// 右键进的是**应用内全屏**（`enterFullScreen(osFullScreen: false)`）：页面切到
/// 全屏骨架、视频铺满当前窗口，OS 窗口保持原样。中键才是 OS 全屏（PiliNara 的
/// 两键分工）；双击仍走原本的 OS 全屏切换。
///
/// 音量拖动沿用移动端口径：半屏高度换满量程、显示居中百分比浮层。桌面没有应用内
/// 亮度可调，左右两侧都调音量（PiliNara 在桌面端也是这么做的）。滚轮与竖向拖动
/// 是画面上的粗犷入口，不必把指针精确停在 icon 上；音量 icon 的悬停滑条仍然保留，
/// 但页面宿主不再接滚轮（滚动只归这一层）。
///
/// 竖向拖动的检测方式随宿主分两种（见 [competesWithWindowDrag]）：
/// - 窗口化：裸指针跟踪，8px 内完全不进手势竞技场，单击/双击的抖动不会把指针
///   从内层 tap 识别器手里抢走；
/// - 全屏：外层套着 `DragToMoveArea` 的 pan（鼠标阈值 2px），必须在竞技场里
///   不晚于它认领，否则竖向拖动会变成拖窗口。
///
/// ⚠️ 小窗宿主不要挂右键/拖拽（[fullGestures] 传 false，只留滚轮）：内层竖向
/// 识别器会在手势竞技场里赢过外层 `DragToMoveArea` 的 pan（阈值只有它的一半），
/// 整窗就竖着拖不动了。小窗里保留原来的「任意方向拖窗」。
class PlayerMouseGestureLayer extends StatefulWidget {
  const PlayerMouseGestureLayer({
    super.key,
    required this.controller,
    required this.child,
    this.fullGestures = true,
    this.competesWithWindowDrag = false,
  });

  final LiveRoomController controller;
  final Widget child;

  /// false＝只接滚轮（小窗）；true＝滚轮 + 右键/中键 + 竖向拖拽。
  final bool fullGestures;

  /// 外层是否套着 `DragToMoveArea`（全屏宿主）。
  ///
  /// true 时竖向拖动必须用识别器、且阈值贴着拖窗 pan 取 2px——命中链先到本层，
  /// 同一次 move 两边都过线时本层先 accept，窗口才不会被拖走。
  /// false（窗口化）没有竞争的 pan，用裸 `Listener` 跟踪、8px 后才激活：
  /// 这样点击/双击/长按的抖动根本不进竞技场，内层识别器不会被无谓地顶掉。
  final bool competesWithWindowDrag;

  @override
  State<PlayerMouseGestureLayer> createState() => _PlayerMouseGestureLayerState();
}

class _PlayerMouseGestureLayerState extends State<PlayerMouseGestureLayer> {
  /// 裸 `Listener` 模式下真正激活拖动所需的累计竖向位移。
  ///
  /// 窗口化宿主没有竞争的 pan，不必进竞技场；但鼠标是精确指针，单击/双击时手部
  /// 那点抖动如果直接当拖动，就会在点击时弹出一条「音量 100%」。所以先只记录
  /// 按下点，位移过线才把本次手势升级成拖动（并以此处为新起点，见 [_beginDrag]）。
  static const double _activationSlop = 8;

  /// 裸模式下的按下点；null＝当前没有按着主键。
  double? _pressY;

  double _startY = 0;
  double _startRatio = 1;
  int _lastPercent = -1;
  double _height = 1;

  /// 读数与音量已由本次拖动接管。
  bool _dragging = false;

  /// 竖向拖动走裸指针（窗口化）还是识别器（全屏，见 [widget.competesWithWindowDrag]）。
  bool get _listenerDrag => !widget.competesWithWindowDrag;

  /// 与移动端竖向手势同一组开关：设置里禁用滑动控制、或全屏锁定控制条时都不接。
  bool get _blocked {
    final c = widget.controller;
    return AppSettingsController.instance.verticalDragLock.value ||
        (c.lockControlsState.value && c.fullScreenState.value);
  }

  /// 右键：应用内全屏。
  ///
  /// 锁定控制条时只挡「退出」——锁本来就是防误触退出的；进入动作在锁生效的状态
  /// 里根本不会出现，不必挡。
  void _toggleWindowFullscreen() {
    final c = widget.controller;
    if (c.smallWindowState.value) {
      return;
    }
    if (c.fullScreenState.value) {
      if (c.lockControlsState.value) {
        return;
      }
      c.exitFull();
    } else {
      c.enterFullScreen(osFullScreen: false);
    }
  }

  /// 中键：OS 全屏（与双击同源，只是多一个鼠标入口），锁定语义同右键。
  void _toggleOsFullscreen() {
    final c = widget.controller;
    if (c.smallWindowState.value) {
      return;
    }
    if (c.fullScreenState.value) {
      if (c.lockControlsState.value) {
        return;
      }
      c.exitFull();
    } else {
      c.enterFullScreen();
    }
  }

  /// 升级成拖动：快照起始音量、接管居中读数。返回是否真的开始（被锁时不开始）。
  ///
  /// [y] 是**激活点**而不是按下点：裸模式把 8px 门槛内的位移丢弃（同识别器的
  /// `DragStartBehavior.start`），读数不会因为门槛而凭空跳 2~3%。
  bool _beginDrag(double y) {
    if (_blocked) {
      return false;
    }
    _dragging = true;
    _startY = y;
    _startRatio = VolumeTarget.master(widget.controller).ratio.clamp(0.0, 1.0).toDouble();
    final percent = (_startRatio * 100).round();
    _lastPercent = percent;
    final c = widget.controller;
    // 拖动期间浮层归手势管：撤掉一次性提示的计时器，否则它可能在拖动中途把读数关掉。
    c.centerTipTimer?.cancel();
    c.gestureTipHeldByDrag = true;
    c.gestureTipText.value = "音量 $percent%";
    c.showGestureTip.value = true;
    return true;
  }

  void _applyDrag(double dy) {
    final height = _height > 0 ? _height : 1.0;
    // 半屏高度 = 满量程，与 `setGestureVolume` 同一口径；向上拖增大。
    final ratio = (_startRatio + dy / (height * 0.5)).clamp(0.0, 1.0).toDouble();
    final percent = (ratio * 100).round();
    if (percent == _lastPercent) {
      return;
    }
    _lastPercent = percent;
    widget.controller.gestureTipText.value = "音量 $percent%";
    VolumeTarget.master(widget.controller).setValueRatio(ratio);
  }

  void _endDrag() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    final c = widget.controller;
    c.gestureTipHeldByDrag = false;
    c.showGestureTip.value = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kPrimaryButton == 0) {
      _pressY = null;
      return;
    }
    _pressY = event.position.dy;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pressY = _pressY;
    if (pressY == null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    if (_dragging) {
      _applyDrag(_startY - event.position.dy);
      return;
    }
    if ((pressY - event.position.dy).abs() < _activationSlop) {
      return;
    }
    if (!_beginDrag(event.position.dy)) {
      // 被设置/锁挡住：本次按键不再跟踪，免得每次 move 都重试。
      _pressY = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pressY = null;
    _endDrag();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pressY = null;
    _endDrag();
  }

  /// 识别器模式的回调（全屏宿主）。
  void _onDragStart(DragStartDetails details) {
    _beginDrag(details.globalPosition.dy);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    _applyDrag(_startY - details.globalPosition.dy);
  }

  void _onDragEnd([DragEndDetails? details]) {
    _endDrag();
  }

  /// 滚轮：画面内任意位置都能调音量，不必把指针停在音量 icon 上。
  ///
  /// 按位移比例换算（PiliNara 的做法）：滚轮一格 ≈ 5%（Windows 上 Flutter 每格
  /// 约 53 逻辑像素），触控板的小步进则是连续的细调。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _dragging || _blocked) {
      return;
    }
    final delta = -event.scrollDelta.dy / 1000;
    if (delta == 0) {
      return;
    }
    final target = VolumeTarget.master(widget.controller);
    final before = target.ratio;
    // 已在边界（0%/100%）：再往同方向滚不会改变比值，但 `nudge` 会一路写到设置。
    // 先挡掉，高频滚轮在边界上空转时不做无意义的落盘与读数刷新。
    if ((delta > 0 && before >= 1.0) || (delta < 0 && before <= 0.0)) {
      return;
    }
    target.nudge(delta);
    final now = target.ratio;
    if (now == before) {
      return;
    }
    final percent = (now.clamp(0.0, 1.0) * 100).round();
    widget.controller.showCenterTip("音量 $percent%");
  }

  @override
  void dispose() {
    // 全屏切换会把这一层整棵换掉（双击的第二下就发生在指针还按着的时候）：
    // 拖动中途被销毁时 onDragEnd 不会再来，不在这里收尾，居中读数就永远停在画面上。
    if (_dragging) {
      widget.controller.gestureTipHeldByDrag = false;
      widget.controller.showGestureTip.value = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _onPointerSignal,
          // 裸模式才在这里跟拖动；识别器模式由下面的 RawGestureDetector 负责。
          // 右键/中键的 down 也会路过这里，非主键直接忽略。
          onPointerDown: _listenerDrag && widget.fullGestures ? _onPointerDown : null,
          onPointerMove: _listenerDrag && widget.fullGestures ? _onPointerMove : null,
          onPointerUp: _listenerDrag && widget.fullGestures ? _onPointerUp : null,
          onPointerCancel: _listenerDrag && widget.fullGestures ? _onPointerCancel : null,
          child: _buildGestureDetector(),
        );
      },
    );
  }

  /// 右键/中键恒用识别器（单击语义，与拖动互不干扰）；竖向拖动按宿主二选一：
  /// - 全屏：装 [_VolumeDragRecognizer]，2px 抢在 `DragToMoveArea` 的 pan 之前认领；
  /// - 窗口化：这里不装竖向识别器，由外层 `Listener` 裸跟踪（见 [_listenerDrag]）。
  Widget _buildGestureDetector() {
    if (!widget.fullGestures) {
      return widget.child;
    }
    final gestures = <Type, GestureRecognizerFactory>{
      // 右键与中键共用一颗 TapGestureRecognizer：两种按键各有独立回调，
      // 它只会在带对应回调的按键上参与竞技场（见 TapGestureRecognizer 类文档）。
      TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        TapGestureRecognizer.new,
        (instance) {
          instance.onSecondaryTapUp = (_) => _toggleWindowFullscreen();
          instance.onTertiaryTapUp = (_) => _toggleOsFullscreen();
        },
      ),
    };
    if (!_listenerDrag) {
      gestures[_VolumeDragRecognizer] = GestureRecognizerFactoryWithHandlers<_VolumeDragRecognizer>(
        () => _VolumeDragRecognizer(isBlocked: () => _blocked),
        (instance) {
          instance
            ..onStart = _onDragStart
            ..onUpdate = _onDragUpdate
            ..onEnd = _onDragEnd
            ..onCancel = _onDragEnd;
        },
      );
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: gestures,
      child: widget.child,
    );
  }
}

/// 全屏宿主的竖向拖动识别器：阈值贴着 [DragToMoveArea] 的 pan 取
/// [kPrecisePointerPanSlop]（2px），保证同一次 move 两边都过线时本层先 accept。
///
/// 鼠标是精确指针，[VerticalDragGestureRecognizer] 默认 1px 就判 drag start；这里
/// 特意放大到 2px，与竞争的 pan 同档。触摸保留系统的 slop。被锁时直接不认领，
/// 让外层的拖窗 pan 照常工作。
class _VolumeDragRecognizer extends VerticalDragGestureRecognizer {
  _VolumeDragRecognizer({required this.isBlocked}) : super(allowedButtonsFilter: _primaryButtonOnly);

  final bool Function() isBlocked;

  static bool _primaryButtonOnly(int buttons) => (buttons & kPrimaryButton) != 0;

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    if (isBlocked()) {
      return false;
    }
    if (pointerDeviceKind == PointerDeviceKind.touch) {
      return globalDistanceMoved.abs() > (deviceTouchSlop ?? kTouchSlop);
    }
    return globalDistanceMoved.abs() >= kPrecisePointerPanSlop;
  }
}
