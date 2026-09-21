import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/modules/debug/glass_debug/glass_debug_controller.dart';
import 'package:simple_live_app/modules/debug/glass_debug/glass_debug_page.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';
import 'package:simple_live_app/widgets/liquid_glass_nav_defaults.dart';

void main() {
  setUp(() {
    // 控制器是 GetX 单例（Get.put permanent），跨用例复用 ——
    // 每个用例开始先打回默认值，避免互相污染
    GlassDebugController.instance.reset();
  });

  // 预览区必须钉在顶部：往下面拖滑块调参数时，预览不能跟着一起卷走，
  // 否则就没法「边调边看」。
  testWidgets('Liquid Glass 调试页：预览区置顶，不随参数列表滚动', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // GetView 需要控制器已注册（生产入口是 kDebugMode 下从设置页进）
    GlassDebugController.instance;

    await tester.pumpWidget(const MaterialApp(home: GlassDebugPage()));
    await tester.pumpAndSettle();

    // 预览区：页面上唯一的 FloatingNavigationBar
    final previewBar = find.byType(FloatingNavigationBar);
    expect(previewBar, findsOneWidget);
    final previewRect = tester.getRect(previewBar);

    // 结构性保证：预览不在滚动列表里
    expect(
      find.ancestor(of: previewBar, matching: find.byType(ListView)),
      findsNothing,
    );

    // 往下滚参数列表
    final sectionTitle = find.text("胶囊本体");
    final titleBefore = tester.getRect(sectionTitle);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    // 列表确实滚动了（否则下面的断言会假通过）
    final titleAfter = tester.getRect(sectionTitle);
    expect(
      titleAfter.top,
      lessThan(titleBefore.top),
      reason: "参数列表没有滚动，本用例无法证明预览置顶",
    );

    // 预览原地不动
    expect(tester.getRect(previewBar), previewRect);
  });

  // 单项重置：调了半天只想留下其中一项时，不必记住想留的值再整体重置
  testWidgets('Liquid Glass 调试页：单项重置只影响自己', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = GlassDebugController.instance;

    await tester.pumpWidget(const MaterialApp(home: GlassDebugPage()));
    await tester.pumpAndSettle();

    // itemPadding 是第一个分组的第一项，初始必定可见
    final row = find
        .ancestor(
          of: find.text("itemPadding 内边距"),
          matching: find.byType(Row),
        )
        .first;
    final resetButton =
        find.descendant(of: row, matching: find.byType(IconButton));

    // 没改动过 → 置灰不可点
    expect(tester.widget<IconButton>(resetButton).onPressed, isNull);

    // 改两项：一项要留下来，一项要重置。
    //
    // 注意别挑「iconSize 调大 + itemPadding 调大」这种组合：
    // 包内 LiquidGlassNavTabCell 的 Column（图标+间距+文字）没有弹性，
    // 胶囊 64 高扣掉 2×itemPadding 后装不下就会溢出（那是包的问题，不是本页的）。
    // 这里要验的是「单项重置不牵连别人」，选一对安全的参数即可。
    controller.itemPadding.value = 10;
    controller.barSaturation.value = 2.0;
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(resetButton).onPressed, isNotNull);

    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    expect(
      controller.itemPadding.value,
      LiquidGlassNavDefaults.itemPadding,
      reason: "itemPadding 应回到默认值",
    );
    expect(
      controller.barSaturation.value,
      2.0,
      reason: "单项重置不该动到别的参数",
    );
    // 回到默认值后按钮重新置灰
    expect(tester.widget<IconButton>(resetButton).onPressed, isNull);
  });

  // 防漂移：参数表的 `initial` 必须等于各 Rx 字段的**构造初值**。
  //
  // ⚠️ 这里刻意用一个未注册的新实例，而不是单例：
  // reset() 会把每个 Rx 写回 param.initial，若先 reset 再断言，两边必然相等，
  // 用例就恒真了 —— 恰好发现不了它想拦的那类漂移（改了字段初值却没改表里的
  // initial）。新实例的 Rx 初值只由字段字面量决定，不受 reset 污染。
  test('Liquid Glass 调试页：参数表 initial == 各 Rx 字段的构造初值', () {
    final fresh = GlassDebugController();

    for (final param in fresh.allParams) {
      expect(
        param.value.value,
        param.initial,
        reason: "${param.label} 的 Rx 构造初值与参数表 initial 不一致",
      );
      expect(
        param.isModified,
        isFalse,
        reason: "${param.label} 构造出来就被标记为已改动",
      );
    }
    expect(fresh.pillAnimated.value, GlassDebugController.pillAnimatedInitial);
    expect(fresh.pillAnimatedModified, isFalse);

    // 加参数时请一并把它放进某个分组（否则它没法单项重置），
    // 这个数字顺带提醒你确认一遍。
    expect(fresh.allParams.length, 15);
  });

  // 跨文件守护：线上固化的默认样式必须等于调试页在默认值下构造出来的样式。
  //
  // 两边现在读同一份 [LiquidGlassNavDefaults]、走同一段 build* 代码，所以这条用例
  // 在「有人只改了一边」时会立刻红 —— 这正是 floating_navigation_bar 的注释所
  // 承诺的那层保护（之前并不存在：那边全是私有常量，测试够不着）。
  test('Liquid Glass 调试页：线上默认样式 == 控制器按默认值构造的样式', () {
    // 未注册的新实例 = 没被任何滑杆改动过 = 全默认值
    final controller = GlassDebugController();
    const selected = Color(0xFF112233);
    const unselected = Color(0xFF778899);

    final onlineBar = FloatingNavigationBar.defaultLiquidGlassBarStyle;
    final debugBar = controller.buildBarStyle();
    expect(debugBar.appearance.color, onlineBar.appearance.color);
    expect(debugBar.appearance.blur.sigmaX, onlineBar.appearance.blur.sigmaX);
    expect(debugBar.appearance.blur.sigmaY, onlineBar.appearance.blur.sigmaY);
    expect(debugBar.appearance.saturation, onlineBar.appearance.saturation);
    expect(debugBar.appearance.shadow?.blur, onlineBar.appearance.shadow?.blur);
    expect(
      debugBar.appearance.shadow?.opacity,
      onlineBar.appearance.shadow?.opacity,
    );
    expect(debugBar.refraction.distortion, onlineBar.refraction.distortion);
    expect(
      debugBar.refraction.distortionWidth,
      onlineBar.refraction.distortionWidth,
    );
    expect(
      debugBar.refraction.chromaticAberration,
      onlineBar.refraction.chromaticAberration,
    );

    final onlineItem = FloatingNavigationBar.defaultLiquidGlassItemStyle(
      selectedColor: selected,
      unselectedColor: unselected,
    );
    final debugItem = controller.buildItemStyle(
      selectedColor: selected,
      unselectedColor: unselected,
    );
    expect(debugItem.selectedColor, onlineItem.selectedColor);
    expect(debugItem.unselectedColor, onlineItem.unselectedColor);
    expect(debugItem.iconSize, onlineItem.iconSize);
    expect(debugItem.labelFontSize, onlineItem.labelFontSize);
    expect(debugItem.iconLabelGap, onlineItem.iconLabelGap);

    for (final brightness in Brightness.values) {
      final onlinePill =
          FloatingNavigationBar.defaultLiquidGlassPillStyle(brightness);
      final debugPill = controller.buildPillStyle(brightness);
      expect(
        debugPill.color,
        onlinePill.color,
        reason: "$brightness 下药丸填充色不一致",
      );
      expect(debugPill.animated, onlinePill.animated);
      expect(debugPill.animationDuration, onlinePill.animationDuration);
      // 默认圆角 = 0 → 两边都不传 rest，交回包按高度自适应
      expect(onlinePill.rest, isNull);
      expect(debugPill.rest, isNull);
    }
  });

  // 滑杆的取值是 min + (max-min)*i/divisions 离散化出来的，而 divisions 被 clamp
  // 到 600：tint 0-255 的步长是 0.425，65 不落在刻度上（最近的刻度 65.025）。
  // 用精确比较（或远小于半格的容差）会让用户把滑杆拖回默认位置后按钮仍然亮着，
  // 而显示看起来就是 65 —— 容差取半格才盖得住这种量化误差。
  test('Liquid Glass 调试页：滑杆刻度导致的极小偏差不算「已改动」', () {
    final controller = GlassDebugController.instance..reset();
    final tint = controller.capsuleParams.firstWhere(
      (param) => param.label.startsWith("tint"),
    );

    // tint 0-255 → 600 档 → 步长 0.425，半格 0.2125
    controller.barTintAlpha.value = 65.025; // 离默认值最近的滑杆刻度
    expect(tint.isModified, isFalse, reason: "显示上仍是 65，重置按钮不该亮");
    expect(tint.display, "65");

    // 但真调了一格就得算「已改动」
    controller.barTintAlpha.value = 65.45; // 65 + 一格
    expect(tint.isModified, isTrue);

    controller.barTintAlpha.value = 70;
    expect(tint.isModified, isTrue);
    expect(tint.display, "70");
  });

  // 导出代码里药丸的**基底色**要跟着主题走：
  // 浅色 #AEAEB2、深色白。写死一个的话，深色下调出来的 alpha 会配错基底色。
  test('Liquid Glass 调试页：导出代码带对药丸基底色', () {
    final controller = GlassDebugController.instance..reset();

    String pillLine(Brightness brightness) {
      // 药丸填充色是唯一以 `color: Color.fromRGBO` 开头的行
      // （rest 里那层 appearance 以 `appearance:` 开头）
      return controller
          .exportCode(brightness: brightness)
          .split("\n")
          .lastWhere((line) => line.trimLeft().startsWith("color: Color.fromRGBO"));
    }

    expect(pillLine(Brightness.light), contains("174, 174, 178"));
    expect(pillLine(Brightness.dark), contains("255, 255, 255"));
  });

  // 运行时 buildPillStyle 在圆角 > 0 时会补一层 rest，导出必须跟上 ——
  // 否则页面上拖出来的圆角一贴回去就静默丢了。
  test('Liquid Glass 调试页：导出代码带上药丸圆角 rest', () {
    final controller = GlassDebugController.instance..reset();

    // 默认圆角 0 = 自适应，不该出现 rest
    expect(
      controller.exportCode(brightness: Brightness.light),
      isNot(contains("rest:")),
    );

    controller.pillCornerRadius.value = 12;
    final code = controller.exportCode(brightness: Brightness.light);
    expect(code, contains("rest: glass.LiquidGlassStyle("));
    expect(code, contains("cornerRadius: 12.0"));
    // rest 的填充色要和药丸本体一致
    final pillColor = controller.buildPillStyle(Brightness.light).color;
    expect(pillColor, LiquidGlassNavDefaults.pillColor(Brightness.light, 110));
    expect(code, contains("174, 174, 178, 0.431"));
  });
}
