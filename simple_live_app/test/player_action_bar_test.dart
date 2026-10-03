// 多开网格格子胶囊的最小宽度回归。
//
// Task 9 把格子胶囊接上共用 renderer 后，按钮簇多了弹幕开关（共五颗）：按桌面
// 36×36 的 chrome 摆，240 宽的格子（`kMultiPlayMinTileWidth`）里底部两条胶囊
// （信息胶囊最小 66 + 按钮胶囊 ~184）会顶过 chrome Row 的 224 可用宽，名字被挤成
// 0 再溢出（RenderFlex overflow）。溢出正是「大窗口看不见、把窗口缩小才炸」的那类
// bug，所以用例钉在**最小合法格宽**上，动作切片用 tile 宿主真实的那一份。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';

/// 与 `player_volume_action_test.dart` 同一套替身：音量与状态读写走真实现，只把
/// 「下发给 mpv」空掉——widget test 里没有原生播放器，碰 `player` 会去加载动态库。
class _FakeTile extends LiveRoomController {
  _FakeTile()
      : super(
          pSite: Sites.allSites.values.first,
          pRoomId: "r1",
          isSecondaryTile: true,
          tileSlot: 1,
        );

  @override
  Future<void> applyTargetVolume() async {}
}

/// 左信息胶囊的替身：只复刻它的**硬最小宽度**——按 `multi_play_tile.dart` 的
/// `_buildInfoPill` 结构（内边距 6/2 + 序号牌 22 + 间距 6 + ▾ 30，名字是 Flexible、
/// 会被挤到 0），最小合计 66。不能偷懒用 SizedBox(width: 66)：分配变窄时它的宽度会
/// 被直接夹小、不报溢出，这条用例就在溢出形态下「假过」。
Widget _buildInfoPillStandIn() {
  return const Padding(
    padding: EdgeInsets.only(left: 6, right: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 22, height: 22),
        SizedBox(width: 6),
        SizedBox(width: 30, height: 30),
      ],
    ),
  );
}

void main() {
  testWidgets('格子最小宽度 224 可用：紧凑密度胶囊不溢出', (tester) async {
    final tile = _FakeTile();
    // 与格子调用点同一片：tile 宿主的 core 件平铺、其余进 ⋮；pick 由信息胶囊渲染，
    // 这里滤掉。canCloseTile 取 true——主格之外的格子才是宽度压力最大的一片。
    final layout = resolvePlayerActions(
      host: PlayerHost.tile,
      availableWidth: double.infinity,
      canCloseTile: true,
    );
    final bar = layout.bar.where((e) => e.id != PlayerActionId.pick).toList();
    expect(
      bar.map((e) => e.id).toList(),
      [
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.closeTile,
      ],
      reason: '胶囊必须是 tile 宿主真实的 4 颗 + ⋮ = 5 颗 chrome，宽度断言才不空转',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // 240（kMultiPlayMinTileWidth）− 16：格子底部 chrome 是
            // `Positioned(left: 8, right: 8, …)`，内缩取自 multi_play_tile.dart。
            child: SizedBox(
              width: kMultiPlayMinTileWidth - 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: _buildInfoPillStandIn()),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.black54),
                    child: PlayerActionBar(
                      host: PlayerHost.tile,
                      target: tile,
                      // 条带只在 fullscreenToggle 一处读 page 的窗口级旗标
                      // （smallWindowState/fullScreenState），替身默认 false 足够排这一版。
                      page: tile,
                      bar: bar,
                      overflow: layout.overflow,
                      hug: true,
                      compact: true,
                      onCloseTile: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // RenderFlex 溢出在绘制阶段上报，多泵一帧保证异常已经进采集器。
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: '最小合法格宽下两颗胶囊都不许溢出',
    );

    // 上面的「没溢出」不能因为压根没排出来而空过：五颗按钮真的渲染了，且胶囊
    // 宽度就是紧凑密度的 5×30=150（把紧凑尺寸临时抬回 36，这里与上面的溢出
    // 断言应当一起变红）。
    expect(find.byType(IconButton), findsNWidgets(5));
    expect(tester.getSize(find.byType(PlayerActionBar)).width, 150);
  });
}
