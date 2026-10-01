import 'dart:async';

import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_tile.dart';

/// 多开网格：按窗口形状把 N 路摆成 1×2 / 2×1 / 2×2 / 1×4 / 4×1，
/// 窗口不够大时折叠掉最后加入的格子。
///
/// **格子位置只跟加入顺序有关**：切换焦点只改高亮描边和音量，画面不会跳位置。
Widget buildMultiPlayGrid(LiveRoomController controller) =>
    _MultiPlayGrid(controller: controller);

class _MultiPlayGrid extends StatefulWidget {
  const _MultiPlayGrid({required this.controller});

  final LiveRoomController controller;

  @override
  State<_MultiPlayGrid> createState() => _MultiPlayGridState();
}

class _MultiPlayGridState extends State<_MultiPlayGrid> {
  /// 各路昵称是否显示。
  ///
  /// 是**网格级**而不是格子级：鼠标进到网格里（或点了任意一格）就四路一起显示，
  /// 停下几秒或指针离开网格再一起隐藏。多开时面对的多半是陌生主播，昵称要能一眼
  /// 全看到才好决定切哪一路；只亮指针底下那一格等于逼着人一格一格划过去。
  bool _namesVisible = false;
  Timer? _namesHideTimer;

  /// 停手后多久隐藏。比单画面 OSD 的 5s 略短，网格上元素更密、更该早点让开。
  static const Duration _namesHideDelay = Duration(seconds: 4);

  void _showNames() {
    _namesHideTimer?.cancel();
    if (!_namesVisible) {
      setState(() => _namesVisible = true);
    }
    _namesHideTimer = Timer(_namesHideDelay, () {
      if (mounted) {
        setState(() => _namesVisible = false);
      }
    });
  }

  void _hideNames() {
    _namesHideTimer?.cancel();
    _namesHideTimer = null;
    if (_namesVisible) {
      setState(() => _namesVisible = false);
    }
  }

  @override
  void dispose() {
    _namesHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.multiPlay;
    return MouseRegion(
      // onHover 每次指针移动都触发：动鼠标＝续上显示时间，停手 4s 自动隐藏。
      // 只有可见性真的变化时才 setState，避免每次移动都重建整片网格。
      onEnter: (_) => _showNames(),
      onHover: (_) => _showNames(),
      onExit: (_) => _hideNames(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Obx(() {
            final spec = resolveMultiPlayLayout(
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight,
              roomCount: session.slots.length,
              tileAspect: session.focusedTileAspect(),
            );
            // 字号要在 build 里算（这里读得到设置 → 订阅），下发排到帧后：build 里不改状态。
            final danmakuFontSize = session.resolveTileDanmakuFontSize(spec);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              session.applyTileDanmakuFontSize(danmakuFontSize);
            });
            final focusedSlot = session.focusedSlot.value;
            return Stack(
              children: [
                for (final slot in spec.slots)
                  Positioned.fromRect(
                    rect: spec.rectOf(slot),
                    child: MultiPlayTile(
                      // key 用每格自己的稳定编号：用 slot.index 的话，删掉靠前的一格
                      // 会让后面所有格子的 key 前移，导致它们无谓重建（纹理重建、闪一下）
                      key: ValueKey('multi_play_tile_${session.slots[slot.index].tileId}'),
                      page: widget.controller,
                      tile: session.slots[slot.index],
                      index: slot.index,
                      focused: slot.index == focusedSlot,
                      chromeVisible: _namesVisible,
                      onInteract: _showNames,
                    ),
                  ),
                if (spec.degraded)
                  Positioned(
                    right: kMultiPlaySpacing,
                    bottom: kMultiPlaySpacing,
                    child: _FoldedHint(count: spec.hiddenIndexes.length),
                  ),
              ],
            );
          });
        },
      ),
    );
  }
}

/// 「有几路因为窗口太小没显示」。
///
/// 折叠是静默的——播放器还在跑、只是没画出来，不告诉用户就会变成「我明明加了四路，
/// 怎么只有两格」。
class _FoldedHint extends StatelessWidget {
  const _FoldedHint({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: AppStyle.radius8),
      child: Text(
        "另有 $count 路未显示",
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}