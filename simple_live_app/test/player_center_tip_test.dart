// 居中动作反馈的统一入口。
//
// 背景（作者 2026-11-04）：弹幕开关的「弹幕已开启／已关闭」原先只在快捷键路径上
// 以画面居中的方式出现，点条带/`⋮` 里的同一颗按钮却没有任何反馈。现在开关、
// 锁定与静音都把提示放在共用的执行入口里，按钮与快捷键不可能再出现「一边有一边没有」。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// 与 `player_volume_action_test.dart` 同一套替身：只空掉「下发给 mpv」那一步，
/// 提示与开关状态走真实现。
class _FakeRoom extends LiveRoomController {
  _FakeRoom() : super(pSite: Sites.allSites.values.first, pRoomId: "r1");

  @override
  Future<void> applyTargetVolume() async {}
}

class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

class _FakeLocalStorage extends LocalStorageService {
  final _mem = <dynamic, dynamic>{};

  @override
  Future init() async {}

  @override
  T getValue<T>(dynamic key, T defaultValue) => _mem.containsKey(key) ? _mem[key] as T : defaultValue;

  @override
  Future setValue<T>(dynamic key, T value) async {
    _mem[key] = value;
  }

  @override
  Future removeValue<T>(dynamic key) async {
    _mem.remove(key);
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<LocalStorageService>(_FakeLocalStorage());
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('弹幕开关：按钮入口与快捷键共用同一个开关方法，并给出居中提示', (tester) async {
    final room = _FakeRoom();

    invokePlayerAction(
      host: PlayerHost.windowed,
      target: room,
      page: room,
      id: PlayerActionId.danmakuToggle,
    );
    expect(room.showDanmakuState.value, isTrue);
    expect(room.showGestureTip.value, isTrue, reason: '点了按钮也要有居中反馈');
    expect(room.gestureTipText.value, "弹幕已开启");

    invokePlayerAction(
      host: PlayerHost.windowed,
      target: room,
      page: room,
      id: PlayerActionId.danmakuToggle,
    );
    expect(room.showDanmakuState.value, isFalse);
    expect(room.gestureTipText.value, "弹幕已关闭");

    // 计时器到点自动收起，不需要调用方自己管。
    await tester.pump(kPlayerTipDuration);
    expect(room.showGestureTip.value, isFalse);
  });

  testWidgets('锁定/解锁：两侧锁定钮与快捷键 `L` 都走 setLockState，提示同源', (tester) async {
    final room = _FakeRoom();

    room.setLockState();
    expect(room.lockControlsState.value, isTrue);
    expect(room.gestureTipText.value, "控制条已锁定");

    room.setLockState();
    expect(room.lockControlsState.value, isFalse);
    expect(room.gestureTipText.value, "控制条已解锁");

    await tester.pump(kPlayerTipDuration);
    expect(room.showGestureTip.value, isFalse);
  });

  testWidgets('连续两次提示：前一个计时器被取消，不会提前关掉后一个', (tester) async {
    final room = _FakeRoom();

    room.showCenterTip("第一条");
    // 走到第一条计时器的 400ms：此时再发第二条，第一条应被取消。
    await tester.pump(const Duration(milliseconds: 400));
    room.showCenterTip("第二条");
    // 500ms 后是第一条本该到点的时刻（400+500=900）。若取消逻辑失效，
    // 读数会在这里被旧计时器关掉，而第二条其实还有 400ms 才到点。
    await tester.pump(const Duration(milliseconds: 500));
    expect(room.showGestureTip.value, isTrue, reason: '旧计时器必须被取消');
    expect(room.gestureTipText.value, "第二条");

    await tester.pump(const Duration(milliseconds: 500));
    expect(room.showGestureTip.value, isFalse, reason: '新计时器到点才收起');
  });

  testWidgets('条带上的弹幕按钮：真的调到开关与居中提示（不是只测分派器）', (tester) async {
    final room = _FakeRoom();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerActionBar(
            host: PlayerHost.windowed,
            target: room,
            page: room,
            bar: const [PlayerAction(id: PlayerActionId.danmakuToggle, title: "弹幕")],
            overflow: const [],
          ),
        ),
      ),
    );
    // 只有弹幕这一件：条带里唯一的 IconButton 就是它。
    final button = find.byType(IconButton);
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(room.showDanmakuState.value, isTrue, reason: '按钮必须真的翻开关');
    expect(room.gestureTipText.value, "弹幕已开启");

    await tester.tap(button);
    await tester.pump();
    expect(room.showDanmakuState.value, isFalse);
    expect(room.gestureTipText.value, "弹幕已关闭");

    await tester.pump(kPlayerTipDuration);
    expect(room.showGestureTip.value, isFalse);
  });
}
