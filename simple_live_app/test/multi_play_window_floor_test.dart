// 「多开中进全屏 → 关掉副格」后半态的回归。
//
// 根因：关掉最后一路副格时 `MultiPlaySession.refreshWindowFloor` 走 !isActive 分支，
// 把窗口 setSize 回「进多开前」的尺寸；而此刻 OS 窗口还在全屏——window_manager 的
// `setBounds` 就是一次 `SetWindowPos`（windows/window_manager.cpp:742），既不退全屏、
// 也不动 C++ 侧 `g_is_window_fullscreen`——于是窗口缩回窗口化尺寸，Dart 侧
// `fullScreenState` 仍是 true，停在「在全屏、画面却不全屏」的半态。
// 修复：全屏态（小窗 implies fullScreenState==true）下本方法一概不摆窗口几何，
// 也不采还原点；几何归 `exitFull` 消费的 `_lastWindowSize` 管。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_session.dart';
import 'package:simple_live_app/services/window_service.dart';

/// 跳过本地存储（Hive 在 fake-async 环境下不可用）。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 弹幕字号重算要读真实窗口尺寸并广播事件，与本用例无关，空掉。
class _FakeWindowService extends WindowService {
  @override
  Future<double> danmakuFontClamped() async => 20;
}

/// 音量下发会惰性构造真播放器（media_kit `Player` → `DynamicLibrary.open`），
/// 单测环境没有 libmpv，一律空转——本文件守护的是窗口几何，不是音量。
class _FakeRoom extends LiveRoomController {
  _FakeRoom()
      : super(
          pSite: Sites.allSites.values.first,
          pRoomId: "r1",
        );

  @override
  Future<void> applyTargetVolume() async {}
}

class _FakeTile extends LiveRoomController {
  _FakeTile()
      : super(
          pSite: Sites.allSites.values.last,
          pRoomId: "r2",
          isSecondaryTile: true,
          tileSlot: 1,
        );

  @override
  Future<void> applyTargetVolume() async {}
}

/// 下限计算要读各格 `player.state`（真播放器），本文件不关心排布，覆写成定值——
/// 守护的是「几何摆不摆」，不是「下限算多少」。
class _FakeSession extends MultiPlaySession {
  _FakeSession(super.page);

  @override
  Size requiredMinimumWindowSize() => const Size(900, 700);
}

/// 一次窗口调用：方法名 + 关键参数。
typedef _Call = ({String method, Map<Object?, Object?> args});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Call> calls;

  /// 当前 `getBounds` 回报的窗口外框（全屏期换成显示器矩形）。
  late Rect bounds;

  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
    Get.put<WindowService>(_FakeWindowService());
    calls = <_Call>[];
    bounds = const Rect.fromLTWH(320, 180, 1000, 700);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('window_manager'), (call) async {
      calls.add((
        method: call.method,
        args: call.arguments is Map
            ? Map<Object?, Object?>.from(call.arguments as Map)
            : <Object?, Object?>{},
      ));
      switch (call.method) {
        case 'getBounds':
          return {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          };
        case 'isMaximized':
          return false;
        case 'isFullScreen':
          return false;
      }
      return null;
    });
  });

  tearDown(() {
    Get.reset();
  });

  /// 只保留**会改窗口摆放**的调用；读取类（getBounds/isMaximized）与
  /// setMinimumSize（只存值）都不算。
  List<_Call> placements() => calls
      .where((c) => c.method == 'setBounds' || c.method == 'setFullScreen')
      .toList();

  test('窗口态下关掉最后一路副格：还原多开前尺寸（现有行为不变）', () async {
    final page = _FakeRoom();
    final session = _FakeSession(page);
    session.enabled.value = true;
    final tile = _FakeTile();
    tile.attachHostSession(session);
    session.slots.add(tile);

    // 进多开：采到还原点 1000×700，下限 900×700（当前尺寸已不低于下限）。
    await session.refreshWindowFloor();

    calls.clear();
    session.removeTile(tile);
    await Future<void>.delayed(Duration.zero);

    final restores =
        placements().where((c) => c.args['width'] != null).toList();
    expect(restores, hasLength(1));
    expect(restores.single.args['width'], 1000.0);
    expect(restores.single.args['height'], 700.0);
    expect(page.fullScreenState.value, isFalse);
  });

  test('全屏态下关掉最后一路副格：一笔摆窗都不落，状态停在全屏', () async {
    final page = _FakeRoom();
    final session = _FakeSession(page);
    session.enabled.value = true;
    final tile = _FakeTile();
    tile.attachHostSession(session);
    session.slots.add(tile);
    await session.refreshWindowFloor();

    // 进全屏：只翻旗标——守卫读的就是它；OS 侧几何由 window_manager 自己管。
    page.fullScreenState.value = true;

    calls.clear();
    session.removeTile(tile);
    await Future<void>.delayed(Duration.zero);

    expect(
      placements(),
      isEmpty,
      reason: '全屏期 setSize 会把 OS 全屏窗改小（SetWindowPos 不退全屏），'
          '而 fullScreenState 仍是 true → 「在全屏、画面却不全屏」。',
    );
    expect(page.fullScreenState.value, isTrue);
    // 下限照样交还常规值：setMinimumSize 只存值、不碰摆放。
    final minCalls = calls.where((c) => c.method == 'setMinimumSize').toList();
    expect(minCalls, hasLength(1));
    expect(minCalls.single.args['width'], 436.0);
    expect(minCalls.single.args['height'], 280.0);
  });

  test('全屏期加入的一路：不把显示器矩形采成还原点', () async {
    final page = _FakeRoom();
    final session = _FakeSession(page);
    session.enabled.value = true;
    final tile = _FakeTile();
    tile.attachHostSession(session);
    session.slots.add(tile);

    // 全屏期 getBounds 回报的是显示器矩形（真实全屏窗就是这个尺寸）。
    bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
    page.fullScreenState.value = true;
    await session.refreshWindowFloor();

    // 退满屏：窗口几何由 exitFull 摆回，这里只翻旗标。
    page.fullScreenState.value = false;
    bounds = const Rect.fromLTWH(320, 180, 1000, 700);

    calls.clear();
    session.removeTile(tile);
    await Future<void>.delayed(Duration.zero);

    expect(
      placements().where((c) => c.args['width'] != null),
      isEmpty,
      reason: '全屏期采到的「还原点」是显示器矩形，拿它摆窗口会把窗口撑满屏幕；'
          '没采就不该有还原可摆。',
    );
  });
}
