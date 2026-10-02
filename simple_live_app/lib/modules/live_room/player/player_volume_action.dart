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

  /// 归一化到 0~1，用于显示百分比与滚轮步进。
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

  bool get muted => ratio <= 0.001;

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

  void toggleMute() => _owner.toggleMute();
}

/// 音量按钮的三态：点击＝静音这一路，悬停＝出滑条，滚轮＝±5%。
///
/// 点击静音要保住：原先格子上「点一下静音」是快按，滑条做成悬停弹出之后仍然不改它，
/// 否则「静音这路」从一次点击变成两次操作。
///
/// 滑条是**同一个 `MouseRegion` 的孩子**，不能飘出去用 `SmartDialog`：飘出去就不在
/// hover 区内，指针移到滑条上会触发 `onExit`，滑条立刻消失、根本拖不动。
/// [floatPopover] 为 true 时（格子宿主）滑条浮在按钮上方、向左上展开，
/// 因为格子胶囊只有 240px 宽，行内展开会把旁边的昵称挤成省略号；
/// 条带宿主用行内展开（向左长，右侧那簇不动，Expanded 吃掉宽度），零位移。
///
/// ⚠️ 接线时复核浮层那一种：命中测试是逐层按**盒子自己的尺寸**把关的
/// （`RenderBox.hitTest` 里的 `size.contains`），`Stack(clipBehavior: Clip.none)`
/// 只是让浮层画得出来，浮在按钮盒之外的部分仍不属于这个 `MouseRegion` 的区域——
/// 指针一移过去就 `onExit`（滑条当场消失），点它也会穿到下层。行内那一种没这问题，
/// 滑条是 Row 的孩子、盒子跟着一起变大，天然在 hover 区内。
///
/// 悬停是桌面专属输入：触屏没有 `onEnter`，滑条永远不展开，但按钮的点击路径照常工作，
/// 所以移动端不会因为这套三态而丢功能。
class VolumeActionWidget extends StatefulWidget {
  const VolumeActionWidget({
    super.key,
    required this.target,
    required this.style,
    this.iconSize = 24,
    this.floatPopover = false,
    this.onInteract,
  });

  final VolumeTarget target;
  final ButtonStyle style;
  final double iconSize;
  final bool floatPopover;
  final VoidCallback? onInteract;

  static const double _step = 0.05;
  static const double _sliderWidth = 88;

  @override
  State<VolumeActionWidget> createState() => _VolumeActionWidgetState();
}

class _VolumeActionWidgetState extends State<VolumeActionWidget> {
  bool _hovering = false;
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
      final ratio = widget.target.ratio;
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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        // 只在指针停在这颗按钮（含它自己的滑条/读数）上滚动才动这一路，
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
          if (widget.floatPopover) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                button,
                if (_hovering)
                  Positioned(
                    right: 0,
                    bottom: 30,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: AppStyle.radius8,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.target.label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                            _buildSlider(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_showingTip)
                  Positioned(right: 0, bottom: 34, child: _buildTip()),
              ],
            );
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
  }
}
