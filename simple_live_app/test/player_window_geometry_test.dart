// 「小窗 → 全屏 → 双击退出」掉进一块小窗尺寸的窗口态（既不在小窗也不在全屏）的回归。
//
// 根因是次序：window_manager 的 Windows 实现里 `setFullScreen(false)` 自己会把窗口摆回
// 「进全屏那一刻」的外框（C++ 的 g_frame_before_fullscreen）。从小窗进全屏时 OS 窗口一直
// 停在小窗外框，那份「全屏前外框」就是小窗矩形；原先 exitFull 把应用的还原点抢在它前面
// 落，于是被这次回弹整个顶掉。修复是把退全屏排到还原**之前**并 await。
//
// 这里钉的是那条**次序不变式**：退完全屏之后，最后一笔摆窗必须是应用的还原点，
// 而不是 OS 的回弹。小窗宿主本身要真播放器（`enterSmallWindow` 读 `player.state`），
// 单测里起不来，所以走窗口化→全屏→退出这条同样经过该不变式的路。
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/window_service.dart';

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用）。
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

class _FakeRoom extends LiveRoomController {
  _FakeRoom()
      : super(
          pSite: Sites.allSites.values.first,
          pRoomId: "r1",
        );
}

/// 一次窗口调用：方法名 + 关键参数。
typedef _Call = ({String method, Map<Object?, Object?> args});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Call> calls;

  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
    Get.put<WindowService>(_FakeWindowService());
    calls = <_Call>[];
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
        // 窗口态几何：1280×720 @ (320,180)。进全屏时采的就是这份。
        case 'getBounds':
          return {
            'x': 320.0,
            'y': 180.0,
            'width': 1280.0,
            'height': 720.0,
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
  /// setTitleBarStyle（只带 SWP_NOSIZE）都不算。
  List<_Call> placements() => calls
      .where((c) => c.method == 'setBounds' || c.method == 'setFullScreen')
      .toList();

  test('退出全屏：还原点排在 setFullScreen(false) 之后落，OS 回弹顶不掉它', () async {
    final room = _FakeRoom();
    room.enterFullScreen();
    await Future<void>.delayed(Duration.zero);
    expect(room.fullScreenState.value, isTrue);

    calls.clear();
    room.exitFull();
    await Future<void>.delayed(Duration.zero);

    final seq = placements();
    // 1) 退全屏必须在场，且必须是**第一**笔摆窗（await 过，才轮到后面的还原）。
    expect(seq.first.method, 'setFullScreen');
    expect(seq.first.args['isFullScreen'], false);

    // 2) 还原点（带宽高的那笔 setBounds）必须落在退全屏之后。
    final sizeRestore = seq.lastWhere(
      (c) => c.method == 'setBounds' && c.args['width'] != null,
    );
    expect(sizeRestore.args['width'], 1280.0);
    expect(sizeRestore.args['height'], 720.0);
    expect(seq.indexOf(sizeRestore), greaterThan(0));

    // 3) 还原之后不得再有任何 setFullScreen —— 那正是 bug 的形状。
    expect(
      seq.sublist(seq.indexOf(sizeRestore) + 1)
          .where((c) => c.method == 'setFullScreen'),
      isEmpty,
      reason: '还原点之后又落了一次退全屏，窗口会被摆回「进全屏那一刻」的外框；'
          '从小窗进的全屏那一刻外框就是小窗矩形，于是退出后停在几百 px 的窗口态。',
    );
    expect(room.fullScreenState.value, isFalse);
  });

  test('进全屏前是最大化态：只 maximize，不做显式还原（与修复前逐字一致）', () async {
    final room = _FakeRoom();
    room.enterFullScreen();
    await Future<void>.delayed(Duration.zero);
    // 还原点采到的是「最大化态的外框」，此刻再 setSize 会把最大化顶掉。
    room.windowMaxState.value = true;

    calls.clear();
    room.exitFull();
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), contains('maximize'));
    expect(
      calls.where((c) => c.method == 'setBounds'),
      isEmpty,
      reason: '最大化这条臂不能 setSize，否则刚 maximize 的窗口被顶回窗口态。',
    );
  });

  test('还原尺寸与还原位置都排在退全屏之后（两笔 setBounds 都在最后）', () async {
    final room = _FakeRoom();
    room.enterFullScreen();
    await Future<void>.delayed(Duration.zero);

    calls.clear();
    room.exitFull();
    await Future<void>.delayed(Duration.zero);

    final names = calls.map((c) => c.method).toList();
    final fullIdx = names.indexOf('setFullScreen');
    final boundsIdx = names.lastIndexOf('setBounds');
    expect(fullIdx, greaterThanOrEqualTo(0));
    expect(boundsIdx, greaterThan(fullIdx));
    // 尺寸一笔、位置一笔（setSize/setPosition 都走 setBounds）。
    expect(names.where((n) => n == 'setBounds').length, 2);
    // 位置那笔只带 x/y，不带宽高。
    final pos = calls.lastWhere((c) => c.method == 'setBounds');
    expect(jsonEncode([pos.args['x'], pos.args['y']]), '[320.0,180.0]');
  });
}
