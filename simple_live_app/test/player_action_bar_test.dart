// 多开网格格子胶囊的最小宽度回归。
//
// Task 9 把格子胶囊接上共用 renderer 后，按钮簇多了弹幕开关（共五颗）：按桌面
// 36×36 的 chrome 摆，240 宽的格子（`kMultiPlayMinTileWidth`）里底部两条胶囊
// （信息胶囊最小 66 + 按钮胶囊 ~184）会顶过 chrome Row 的 224 可用宽，名字被挤成
// 0 再溢出（RenderFlex overflow）。溢出正是「大窗口看不见、把窗口缩小才炸」的那类
// bug，所以用例钉在**最小合法格宽**上，动作切片用 tile 宿主真实的那一份。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用）。
/// windowed 宿主的音量颗绑的是总音量（`VolumeTarget.master`），构建时要读
/// `AppSettingsController.instance.playerVolume/playerMaxVolume`。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

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
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(() {
    Get.reset();
  });

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

  // 条带的结构承诺是「左簇贴左、右簇贴右、余量归中间那道空」（`Spacer` 的语义）。
  // 清晰度／线路包 `Flexible` 时漏了 `fit`：`Flexible` 默认 **tight**（等价 Expanded），
  // 于是两颗文字按钮和 `Spacer` 平分余量，右簇被顶到条带中段——作者 2026-10-03 手测
  // 就是报的这个（截图里音量／原画／线路1／全屏挤在中间，右边空一大片）。
  // 所以这里钉的是**位置**，不是「没溢出」（溢出由下面那条窄窗口用例钉）。
  testWidgets('宽窗口化条带：左簇贴左、右簇贴右，文字按钮不吃掉中间余量', (tester) async {
    final tile = _FakeTile();
    tile.currentQualityInfo.value = "原画";
    tile.currentLineInfo.value = "线路1";
    final layout = resolvePlayerActions(
      host: PlayerHost.windowed,
      availableWidth: 900,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: PlayerActionBar(
                host: PlayerHost.windowed,
                target: tile,
                page: tile,
                bar: layout.bar,
                overflow: layout.overflow,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final barRect = tester.getRect(find.byType(PlayerActionBar));
    // 右簇最后一颗＝全屏颗（windowed 宿主的 `⋮` 归顶簇，底栏不画）。
    expect(
      tester.getRect(find.byTooltip("全屏播放")).right,
      moreOrLessEquals(barRect.right, epsilon: 0.5),
      reason: '右簇必须贴到条带右端，余量留在左右簇之间',
    );
    expect(
      tester.getRect(find.byTooltip("刷新")).left,
      moreOrLessEquals(barRect.left, epsilon: 0.5),
      reason: '左簇贴左端',
    );
    // 左右簇之间那道空是真的空：音量颗（右簇第一颗）离左簇末端远大于按钮间距。
    expect(
      tester.getRect(find.byType(VolumeActionWidget)).left -
          tester.getRect(find.byTooltip("弹幕设置")).right,
      greaterThan(300),
    );
  });

  // 桌面条带（windowed 宿主）的收纳预算给清晰度／线路各 56px（`player_actions.dart`
  // 的 slotWidth），但 renderer 画的是 `Text(target.currentQualityInfo.value)`——宽度
  // 是内容驱动的：「原画(1080P)」这种标签实测就超 56，core 件更是无条件进 bar。
  // 于是 resolver 判「装得下」的窄窗口，真实排版会 RenderFlex 溢出——与格子那条
  // Task 9 量过并修掉的溢出是同一类 bug。用例复刻这个错位：按 resolver 判得下的
  // 宽度取清单（quality/line 留在 bar），再画进更窄的真实宿主里。
  testWidgets('窄窗口化条带含长清晰度／线路标签：文字件可收缩、不溢出', (tester) async {
    final tile = _FakeTile();
    tile.currentQualityInfo.value = "原画(1080P)";
    tile.currentLineInfo.value = "线路1备份备用";
    final layout = resolvePlayerActions(
      host: PlayerHost.windowed,
      availableWidth: 400,
    );
    expect(
      layout.bar.map((e) => e.id).toList(),
      containsAll(<PlayerActionId>[
        PlayerActionId.quality,
        PlayerActionId.line,
      ]),
      reason: '用例必须拿着 resolver 判「装得下」的那份清单（预算 56）',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // 真实可用宽比 resolver 的预算窄：左簇+音量+全屏+⋮ 的固定 chrome
            // 加两颗长文字按钮在这宽度下排不下，必须靠收缩（ellipsis）兜住。
            child: SizedBox(
              width: 360,
              child: PlayerActionBar(
                host: PlayerHost.windowed,
                target: tile,
                page: tile,
                bar: layout.bar,
                overflow: layout.overflow,
              ),
            ),
          ),
        ),
      ),
    );
    // RenderFlex 溢出在绘制阶段上报，多泵一帧保证异常已进采集器。
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: '长文字按钮在窄窗口化条带里必须可收缩，不许 RenderFlex 溢出',
    );
    // 溢出断言不能因「两颗文字按钮根本没排出来」而空过。
    expect(find.byType(TextButton), findsNWidgets(2));
    // 收缩真的生效到省略号上：文字按钮的实宽小于其内容的固有宽。
    expect(
      tester.getSize(find.text("原画(1080P)")).width,
      lessThan(120),
      reason: '清晰度标签应被压缩（ellipsis），而不是按固有宽排出',
    );
  });
}
