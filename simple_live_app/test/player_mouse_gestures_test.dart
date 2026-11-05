// 桌面鼠标手势层：右键＝应用内全屏（铺满窗口），竖向拖动与滚轮＝调总音量。
//
// 作者 2026-11-04 要求对齐 PiliNara：右键不铺满整个屏幕、只铺满当前窗口；
// 画面内上下滑动要像移动端那样调音量并给出居中读数。滚轮是后来补的同一条
// 音量入口（比悬停 icon 更粗犷），页面宿主因此撤掉了悬停滑条。
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_mouse_gestures.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// 与 `player_center_tip_test.dart` 同一套替身。
class _FakeRoom extends LiveRoomController {
  _FakeRoom() : super(pSite: Sites.allSites.values.first, pRoomId: "r1");

  @override
  Future<void> applyTargetVolume() async {}

  /// 记录右键请求的是应用内全屏还是 OS 全屏。
  bool? lastOsFullScreen;

  @override
  void enterFullScreen({bool osFullScreen = true}) {
    lastOsFullScreen = osFullScreen;
    fullScreenState.value = true;
  }

  @override
  void exitFull() {
    fullScreenState.value = false;
  }
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

  /// 挂一层手势层。
  ///
  /// [events] 非空时在层里再嵌一个 tap/双击/长按探测器（`player_controls.dart` 里
  /// 那层 `GestureDetector` 的替身），用来证明新的拖动检测没有把这些既有手势顶掉。
  Future<_FakeRoom> pumpLayer(
    WidgetTester tester, {
    bool fullGestures = true,
    bool competesWithWindowDrag = false,
    List<String>? events,
  }) async {
    final room = _FakeRoom();
    final layer = PlayerMouseGestureLayer(
      controller: room,
      fullGestures: fullGestures,
      competesWithWindowDrag: competesWithWindowDrag,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: events == null ? null : () => events.add('tap'),
        onDoubleTap: events == null ? null : () => events.add('doubleTap'),
        onLongPress: events == null ? null : () => events.add('longPress'),
        child: Container(color: Colors.black),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              // 全屏宿主外层就是 `DragToMoveArea`（pan 阈值 2px）：这里必须挂一个
              // 竞争的 pan，竞技场里才会真的有对手；否则本层是唯一成员，down 一
              // 关闭竞技场就被直接判赢，2px 阈值根本量不出来。
              child: competesWithWindowDrag
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) {},
                      child: layer,
                    )
                  : layer,
            ),
          ),
        ),
      ),
    );
    return room;
  }

  testWidgets('右键进的是应用内全屏，再右键退出；不要求 OS 全屏', (tester) async {
    final room = await pumpLayer(tester);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    await tester.tapAt(center, buttons: kSecondaryButton);
    await tester.pump();
    expect(room.fullScreenState.value, isTrue);
    expect(room.lastOsFullScreen, isFalse, reason: '右键只铺满窗口，不能动 OS 窗口');

    await tester.tapAt(center, buttons: kSecondaryButton);
    await tester.pump();
    expect(room.fullScreenState.value, isFalse);
  });

  testWidgets('中键走 OS 全屏，再按退出（与双击同源）', (tester) async {
    final room = await pumpLayer(tester);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    await tester.tapAt(center, buttons: kMiddleMouseButton);
    await tester.pump();
    expect(room.fullScreenState.value, isTrue);
    expect(room.lastOsFullScreen, isTrue, reason: '中键才动 OS 窗口');

    await tester.tapAt(center, buttons: kMiddleMouseButton);
    await tester.pump();
    expect(room.fullScreenState.value, isFalse);
  });

  testWidgets('单击/双击时的手抖不会顶掉内层 tap/双击，也不弹音量读数', (tester) async {
    final events = <String>[];
    final room = await pumpLayer(tester, events: events);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    /// 带 3px 竖向抖动的点击（每次都用新指针，避免复用指针的竞技场状态）。
    Future<TestGesture> downWithJitter(Offset at, {double dy = -3}) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: at);
      await tester.pump();
      await gesture.down(at);
      await tester.pump();
      await gesture.moveTo(at + Offset(0, dy));
      await tester.pump();
      return gesture;
    }

    Future<void> release(TestGesture gesture) async {
      await gesture.up();
      await gesture.removePointer();
      await tester.pump();
    }

    await release(await downWithJitter(center));
    expect(room.showGestureTip.value, isFalse, reason: '没过激活阈值不能弹读数');
    // 双击探测器会把单击的结果压到双击超时之后：等它走完再看 tap。
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap'], reason: '3px 抖动必须仍算单击——拖动检测不能提前认领');

    // 双击同样带抖动：两下都只有 3px 位移，双击回调仍要照常触发。
    await release(await downWithJitter(center));
    await tester.pump(const Duration(milliseconds: 50));
    await release(await downWithJitter(center, dy: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap', 'doubleTap']);
    expect(room.showGestureTip.value, isFalse, reason: '双击全程都不该弹音量读数');

    // 长按带 3px 抖动：仍要触发换台那条回调。
    final hold = await downWithJitter(center);
    await tester.pump(const Duration(milliseconds: 600));
    await release(hold);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap', 'doubleTap', 'longPress']);
    expect(room.showGestureTip.value, isFalse);
  });

  testWidgets('拖动途中整层被销毁（全屏切换会重建）：读数必须收掉', (tester) async {
    final room = await pumpLayer(tester);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 30));
    await tester.pump();
    expect(room.showGestureTip.value, isTrue);

    // 模拟双击切全屏：手势层的 State 在指针还按着时被卸载，onDragEnd 不会再来。
    await tester.pumpWidget(const SizedBox());
    expect(room.showGestureTip.value, isFalse, reason: '销毁兜底必须收掉读数');

    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
  });

  testWidgets('竖向拖动调整总音量，拖动中显示居中读数，抬起收起', (tester) async {
    final room = await pumpLayer(tester);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(50);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.down(center);
    await tester.pump();
    // 半屏（150px）＝满量程。分几小步走：第一步先过 8px 激活门槛（门槛内的
    // 位移按 `DragStartBehavior.start` 丢弃），之后每步都计入音量。
    await gesture.moveTo(center - const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 30));
    await tester.pump();

    expect(settings.playerVolume.value, greaterThan(50.0), reason: '向上拖应当增大音量');
    expect(room.showGestureTip.value, isTrue);
    expect(room.gestureTipText.value, startsWith("音量 "));

    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
    expect(room.showGestureTip.value, isFalse, reason: '抬手后读数收起');

    // 反方向：向下拖回去并越过起点，音量必须减小。
    final before = settings.playerVolume.value;
    final gesture2 = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture2.addPointer(location: center);
    await tester.pump();
    await gesture2.down(center);
    await tester.pump();
    await gesture2.moveTo(center + const Offset(0, 10));
    await tester.pump();
    await gesture2.moveTo(center + const Offset(0, 20));
    await tester.pump();
    await gesture2.moveTo(center + const Offset(0, 30));
    await tester.pump();
    expect(settings.playerVolume.value, lessThan(before));
    await gesture2.up();
    await gesture2.removePointer();
    await tester.pump();
  });

  testWidgets('画面内滚轮调整总音量，并浮出居中读数', (tester) async {
    final room = await pumpLayer(tester);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(50);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.pump();
    // 每 100px 滚一轮 = 10%（-dy / 1000）；向上滚是增大。
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(settings.playerVolume.value, greaterThan(50.0), reason: '向上滚应当增大音量');
    expect(room.showGestureTip.value, isTrue);
    expect(room.gestureTipText.value, "音量 60%");

    // 反方向：向下滚减小。
    final before = settings.playerVolume.value;
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();
    expect(settings.playerVolume.value, lessThan(before));

    // 一次性提示的计时器：走完它，免得测试框架报 pending timer。
    await tester.pump(kPlayerTipDuration);
    expect(room.showGestureTip.value, isFalse, reason: '读数应当自动收起');
  });

  testWidgets('全屏宿主：2px 就认领竖向拖动，抢在外层拖窗 pan 之前', (tester) async {
    final room = await pumpLayer(tester, competesWithWindowDrag: true);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(50);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 1));
    await tester.pump();
    expect(room.showGestureTip.value, isFalse, reason: '1px 还不该认领');
    await gesture.moveTo(center - const Offset(0, 3));
    await tester.pump();
    expect(room.showGestureTip.value, isTrue, reason: '2px 是拖窗 pan 的阈值，必须不晚于它认领');
    // 激活点即新起点：门槛内的 3px 被丢弃，音量还没动。
    expect(settings.playerVolume.value, 50.0);
    await gesture.moveTo(center - const Offset(0, 40));
    await tester.pump();
    expect(settings.playerVolume.value, greaterThan(50.0));
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
  });

  testWidgets('锁定控制条或禁用滑动控制时，拖动与滚轮都不改音量、不弹读数', (tester) async {
    final room = await pumpLayer(tester, competesWithWindowDrag: true);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(50);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    Future<void> expectInert() async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      await tester.pump();
      await gesture.down(center);
      await tester.pump();
      await gesture.moveTo(center - const Offset(0, 40));
      await tester.pump();
      expect(settings.playerVolume.value, 50.0, reason: '被挡时拖动不能改音量');
      expect(room.showGestureTip.value, isFalse, reason: '被挡时不能弹读数');
      await gesture.up();
      await gesture.removePointer();
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(center);
      await tester.pump();
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      expect(settings.playerVolume.value, 50.0, reason: '被挡时滚轮不能改音量');
      expect(room.showGestureTip.value, isFalse);
    }

    // 1. 设置里禁用滑动控制。
    settings.setVerticalDragLock(true);
    await expectInert();
    settings.setVerticalDragLock(false);

    // 2. 全屏 + 锁定控制条。
    room.fullScreenState.value = true;
    room.lockControlsState.value = true;
    await expectInert();
  });

  testWidgets('音量已在 100% 时继续向上滚：不弹读数（边界去重）', (tester) async {
    final room = await pumpLayer(tester);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(100);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(settings.playerVolume.value, 100.0);
    expect(room.showGestureTip.value, isFalse, reason: '边界上空转不该反复弹读数');
  });

  testWidgets('拖动途中的一次性提示到点也不会收起拖动读数', (tester) async {
    final room = await pumpLayer(tester);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 20));
    await tester.pump();
    expect(room.showGestureTip.value, isTrue);

    // 拖动途中按了快捷键：一次性提示的计时器开始跑，但它到点时不能把读数关掉。
    room.showCenterTip("已静音");
    await tester.pump(kPlayerTipDuration + const Duration(milliseconds: 100));
    expect(room.showGestureTip.value, isTrue, reason: '手势还按着，读数归手势管');

    await gesture.up();
    await tester.pump();
    expect(room.showGestureTip.value, isFalse, reason: '抬手才收起');
    await gesture.removePointer();
  });

  testWidgets('小窗（fullGestures: false）：滚轮还能调音量，但不抢窗口拖动与右键', (tester) async {
    final room = await pumpLayer(tester, fullGestures: false);
    final settings = AppSettingsController.instance;
    settings.setPlayerVolume(50);
    final center = tester.getCenter(find.byType(PlayerMouseGestureLayer));

    // 滚轮保留：小窗里没有别的手势层，这是它唯一的桌面音量入口。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(settings.playerVolume.value, greaterThan(50.0));
    await tester.pump(kPlayerTipDuration);

    // 右键不接：小窗宿主靠 `DragToMoveArea` 拖窗，不能在这里吞掉点击。
    await tester.tapAt(center, buttons: kSecondaryButton);
    await tester.pump();
    expect(room.fullScreenState.value, isFalse);

    // 竖向拖动也不接：内层识别器会在手势竞技场里赢过外层的拖窗 pan。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center - const Offset(0, 30));
    await tester.pump();
    expect(room.showGestureTip.value, isFalse);
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
  });
}
