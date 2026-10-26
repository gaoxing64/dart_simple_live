// 音量浮层的命中测试回归。
//
// 这条缺陷的本质是「画得出来、命中测试进不去」，所以只能用真鼠标手势驱动：
// 悬停按钮 → 把指针移到滑条所在的位置 → 断言滑条仍挂在树上、拖动真的改到绑定的量。
// 任何只看渲染结果的检查（截图、findsWidgets 一次）都证不到这一点。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_action.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// 被测的那一格：音量逻辑（`volumeFactor` / `muted` / `toggleMute` /
/// `nudgeVolumeFactor`）用真实现，只把「下发给 mpv」这一步空掉——
/// widget test 里没有原生播放器，碰 `player` 会去加载动态库。
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

/// 假本地存储：内存实现（与 `follow_test_harness.dart` 那份同形）。
///
/// 为什么必须有它：单播放宿主的写路径经`AppSettingsController.setPlayerVolume`
/// 落到 `LocalStorageService`，而 widget test 里没开任何 Hive box，不注册就直接
/// GetFindCanceled。原先这批用例只直接给 `playerVolume.value` 赋值、从没走过
/// 写路径，所以一直没暴露这个依赖——直到补了「点图标恢复音量」那条，它第一次
/// 真的去写盘。
class _FakeLocalStorage extends LocalStorageService {
  final _mem = <dynamic, dynamic>{};

  @override
  Future init() async {}

  @override
  T getValue<T>(dynamic key, T defaultValue) =>
      _mem.containsKey(key) ? _mem[key] as T : defaultValue;

  @override
  Future setValue<T>(dynamic key, T value) async {
    _mem[key] = value;
  }

  @override
  Future removeValue<T>(dynamic key) async {
    _mem.remove(key);
  }
}

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用）。
/// 单播放宿主的音量颗绑总音量，构建时要读 `AppSettingsController.instance`。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 单播放宿主（页面主格）的替身，同样只空掉「下发给 mpv」。
class _FakeMaster extends LiveRoomController {
  _FakeMaster() : super(pSite: Sites.allSites.values.first, pRoomId: "r0");

  @override
  Future<void> applyTargetVolume() async {}
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
  testWidgets('鼠标从按钮移到浮层滑条上：滑条不消失，拖得动这一路',
      (tester) async {
    final tile = _FakeTile();
    // 起点放在中间偏左，往右拖才是「变大」（系数上限 1.0）
    tile.volumeFactor.value = 0.4;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    final button = find.byType(IconButton);
    final buttonRect = tester.getRect(button);
    await gesture.addPointer(location: buttonRect.center);
    await tester.pump();
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget, reason: '悬停按钮应当展开滑条');

    final sliderCenter = tester.getCenter(slider);
    // 浮层必须正压在按钮**上方居中**（改造前 `SmartDialog.showAttach` 的
    // `Alignment.topCenter`）。上一版锚在按钮右上角再向左展开，多开时浮层明显偏在
    // icon 右上方——作者 2026-10-04 手测报的「图体偏移」。
    expect(
      sliderCenter.dx,
      moreOrLessEquals(buttonRect.center.dx, epsilon: 0.5),
      reason: '浮层水平中心必须对齐 icon，不能偏左偏右',
    );
    // 面板里只有滑条：不画「第 N 路」标题，也不重复一颗音量图标。
    expect(
      find.text("第2路"),
      findsNothing,
      reason: '浮层标题已按作者定的形态去掉',
    );
    // 浮层浮在按钮上方：目标点必须落在按钮盒**之外**，否则整条用例只是在原地踏步，
    // 证不到「浮层自己接住了指针」这件事。
    expect(
      buttonRect.contains(sliderCenter),
      isFalse,
      reason: '滑条中心应当在按钮盒外，才有命中测试可证',
    );

    // 真实路径要先穿过按钮与浮层之间那段空隙（两个 MouseRegion 都不命中）。
    // 停在空隙里还没到宽限期，滑条不该收（收得太快 = 旧实现里那个 onExit 当场拆台）。
    await gesture.moveTo(Offset(sliderCenter.dx, buttonRect.top - 2));
    await tester.pump();
    expect(slider, findsOneWidget, reason: '穿过空隙时不该立刻收起');

    // 走进浮层：宽限期被浮层自己的 onEnter 取消，之后即便留在浮层里超过 150ms
    // 也不收——留住它的不是按钮的 hover（指针早就离开按钮盒了）。
    await gesture.moveTo(sliderCenter);
    await tester.pump();
    expect(slider, findsOneWidget, reason: '指针移进浮层后滑条必须还在');
    await tester.pump(const Duration(milliseconds: 300));
    expect(slider, findsOneWidget, reason: '指针停在浮层里时不该收起');

    // 拖它：必须真的改到绑定的量（这一路的 volumeFactor）
    final before = tile.volumeFactor.value;
    await gesture.down(sliderCenter);
    await tester.pump();
    await gesture.moveTo(sliderCenter + const Offset(25, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      tile.volumeFactor.value,
      greaterThan(before),
      reason: '拖动必须改到本格系数',
    );

    // 收尾：两处都离开后过宽限期必须收起（顺带确认没有挂着的定时器）
    await gesture.moveTo(Offset(buttonRect.right + 80, buttonRect.bottom + 80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(slider, findsNothing, reason: '按钮与浮层都离开后应当收起');
  });

  testWidgets('触屏：点音量颗弹滑条、再点收起；这颗不再负责静音', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
              isTouch: true,
            ),
          ),
        ),
      ),
    );
    final button = find.byType(IconButton);
    expect(
      find.byType(Slider),
      findsNothing,
      reason: '触屏上没点就不该有浮层（桌面是悬停才出）',
    );

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget, reason: '点一下就该出滑条');
    expect(
      tile.muted,
      isFalse,
      reason: '触屏的点击归「开滑条」，静音另有 ⋮ 里那行 muteTile',
    );

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(Slider), findsNothing, reason: '再点一下收起');
  });

  testWidgets('桌面（isTouch 默认 false）：点音量颗仍是静音、不弹滑条', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(tile.muted, isTrue, reason: '触屏适配不能改动桌面那颗的语义');
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('总音量拖到 0：图标显示 volume_off，但写路径一个字不动', (tester) async {
    final page = _FakeMaster();
    final settings = AppSettingsController.instance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.master(page),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );
    // 这一路系数 1、总音量 100：volume_up。
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    // 显示侧读合并：总音量拖到 0 时用户听到的是无声，图标不能还说「这一路没静音」。
    settings.playerVolume.value = 0.0;
    await tester.pump();
    expect(
      find.byIcon(Icons.volume_off),
      findsOneWidget,
      reason: '总音量为 0 时图标必须说实话',
    );
    // 但这一读**不是**第二条音量权威：什么都没被写过。
    expect(page.volumeFactor.value, 1.0, reason: '显示判定不落任何写');
    // 拖回去，图标自己回来。
    settings.playerVolume.value = 100.0;
    await tester.pump();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('总音量拖到 0 后点图标：双向恢复（这是先前单向的回归）', (tester) async {
    final page = _FakeMaster();
    final settings = AppSettingsController.instance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.master(page),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );
    final button = find.byType(IconButton);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    // 用户把总音量滑条拖到 0：图标如实变成静音态。
    settings.playerVolume.value = 0.0;
    await tester.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    // 此时点图标必须把声音还回来 —— 修复前这里点下去毫无变化：
    // toggleMute 只写 volumeFactor（它还是 1.0），总音量仍是 0。
    await tester.tap(button);
    await tester.pump();
    expect(
      settings.playerVolume.value,
      greaterThan(0.0),
      reason: '点图标必须把总音量带回来，否则控件是单向的',
    );
    expect(
      find.byIcon(Icons.volume_up),
      findsOneWidget,
      reason: '总音量恢复后图标必须回到 volume_up',
    );

    // 反方向也要成立：点图标静音 → 再点恢复（这一段是旧有行为，别改坏）。
    await tester.tap(button);
    await tester.pump();
    expect(page.muted, isTrue, reason: '点一下应当静音');
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(page.muted, isFalse, reason: '再点一下应当取消静音');
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('两处同时为 0（系数与总音量）时点图标：两处都恢复', (tester) async {
    final page = _FakeMaster();
    final settings = AppSettingsController.instance;
    page.volumeFactor.value = 0.0;
    settings.playerVolume.value = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.master(page),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(page.muted, isFalse, reason: '系数那一份也要被还原');
    expect(settings.playerVolume.value, greaterThan(0.0),
        reason: '总音量那一份也要被还原');
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('拖动滑条也会显示百分比读数（滚轮之外的那条路径）', (tester) async {
    final tile = _FakeTile();
    tile.volumeFactor.value = 0.4;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    final button = find.byType(IconButton);
    final buttonRect = tester.getRect(button);
    await gesture.addPointer(location: buttonRect.center);
    await tester.pump();

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget, reason: '悬停应当展开滑条');
    // 还没动：没有读数。
    expect(find.textContaining('%'), findsNothing);

    final sliderCenter = tester.getCenter(slider);
    await gesture.moveTo(Offset(sliderCenter.dx, buttonRect.top - 2));
    await tester.pump();
    await gesture.moveTo(sliderCenter);
    await tester.pump();
    // 真拖一把：先前只有滚轮路径调 `_showTip`，这里读数是不出来的。
    await gesture.down(sliderCenter);
    await tester.pump();
    await gesture.moveTo(sliderCenter + const Offset(25, 0));
    await tester.pump();
    expect(
      find.textContaining('%'),
      findsOneWidget,
      reason: '拖动滑条必须浮出百分比读数',
    );
    await gesture.up();
    await tester.pump();

    // 读数应当与这一路当时的实际系数一致。
    final shown = tester
        .widget<Text>(find.textContaining('%'))
        .data!;
    expect(
      shown.trim(),
      '${(tile.volumeFactor.value * 100).round()}%',
      reason: '读数必须反映拖动后的真实值',
    );
  });

  testWidgets('桌面音量颗 tooltip 带静音键帽 M', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
              isTouch: false,
            ),
          ),
        ),
      ),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNotNull);
    // 键帽是 WidgetSpan：toPlainText() 只给 U+FFFC，读不到它的文字，必须把
    // WidgetSpan 的 child 单独 pump 出来断言（同 player_tooltip_test 的 _keycapText）。
    final keycap = (tooltip.richMessage! as TextSpan)
        .children!
        .whereType<WidgetSpan>()
        .single
        .child;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: keycap)));
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('触屏音量颗不挂静音键帽（点它是弹滑条，不是静音）', (tester) async {
    final tile = _FakeTile();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeActionWidget(
              target: VolumeTarget.tile(tile),
              style: const ButtonStyle(),
              isTouch: true,
            ),
          ),
        ),
      ),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.richMessage, isNull);
    expect(tooltip.message, '音量');
  });
}
