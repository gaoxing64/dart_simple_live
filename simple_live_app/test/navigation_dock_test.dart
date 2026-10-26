import 'dart:ui' show SemanticsFlag;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/navigation_dock.dart';

const List<NavigationDockDestination> _kDestinations = [
  NavigationDockDestination(icon: Icons.home, label: "首页"),
  NavigationDockDestination(icon: Icons.star, label: "关注"),
  NavigationDockDestination(icon: Icons.category, label: "分类"),
  NavigationDockDestination(icon: Icons.person, label: "我的"),
];

void _noop(int _) {}

/// 第 [index] 格中心相对 dock 几何中心的横向偏移。
///
/// 不能想当然地按「总宽 ÷ 格数」算：胶囊内部有 [_kBarPadding] 的四周内边距，
/// 实际每格宽是 `(width - 2 * padding) / count`，第 0 格中心落在
/// `padding + 每格宽/2` 处，不是 `每格宽/2`。这里按实现同样的口径算，
/// 少算一格就会点错地方。
double _offsetOf(WidgetTester tester, Finder dock, int index) {
  final total = tester.getSize(dock).width;
  final extent = (total - 2 * _barPadding) / _kDestinations.length;
  final centerOfIndex = _barPadding + extent * index + extent / 2;
  return centerOfIndex - total / 2;
}

/// 与 [_offsetOf] 同一个口径的内边距值。
const double _barPadding = 4;

/// 把 dock 放进底栏槽位（与 [IndexedPage] 的接法一致：`Center(heightFactor: 1)`）。
Widget _host({
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: NavigationDock(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: _kDestinations,
        ),
      ),
    ),
  );
}

void main() {
  group('尺寸与布局', () {
    testWidgets('高度 = 阴影预留 + 胶囊高 + 间距 + 安全区', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.viewPadding = const FakeViewPadding(bottom: 72); // 24dp
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: _noop));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(NavigationDock)).height,
        kNavigationDockShadowRoom +
            kNavigationDockHeight +
            kNavigationDockBottomPadding +
            24,
      );
    });

    testWidgets('宽度按 itemExtent × 项数固定，不被槽位拉成整屏宽', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: _noop));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(NavigationDock)).width,
        kNavigationDockItemExtent * _kDestinations.length,
      );
      // 整屏宽 390，dock 宽 4×72=288 —— 确认没被拉满
      expect(
        tester.getSize(find.byType(NavigationDock)).width,
        lessThan(390),
      );
    });

    testWidgets('四个 destination 全部渲染，且带无障碍标签', (tester) async {
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: _noop));
      await tester.pumpAndSettle();

      for (final destination in _kDestinations) {
        expect(find.text(destination.label), findsOneWidget);
      }
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel("首页"), findsOneWidget);
      expect(find.bySemanticsLabel("我的"), findsOneWidget);
      handle.dispose();
    });

    testWidgets('selectedIcon 非空时选中项换图标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: NavigationDock(
              selectedIndex: 0,
              onDestinationSelected: _noop,
              destinations: const [
                NavigationDockDestination(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: "首页",
                ),
                NavigationDockDestination(
                  icon: Icons.star_outline,
                  label: "关注",
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.star_outline), findsOneWidget);
    });
  });

  group('点击切换', () {
    testWidgets('点击其它格触发对应索引', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      await tester.tapAt(tester.getCenter(dock) + Offset(_offsetOf(tester, dock, 2), 0));
      await tester.pumpAndSettle();

      expect(log, [2]);
    });

    testWidgets('点击同一格不触发回调', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      await tester.tapAt(tester.getCenter(dock) + Offset(_offsetOf(tester, dock, 0), 0));
      await tester.pumpAndSettle();

      expect(log, isEmpty);
    });

    testWidgets('语义标记跟随选中项', (tester) async {
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: _noop));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();

      // 直接读语义节点，不用 matchesSemantics：后者在遍历合并后的 label 时
      // 会对未标注类型的节点做 String 转换，撞上非字符串抛 TypeError。
      final selected = tester.getSemantics(find.bySemanticsLabel("首页"));
      final unselected = tester.getSemantics(find.bySemanticsLabel("分类"));

      expect(selected.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue);
      expect(
        selected.getSemanticsData().hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );
      expect(
        unselected.getSemanticsData().hasFlag(SemanticsFlag.isSelected),
        isFalse,
      );
      handle.dispose();
    });
  });

  group('拖动透镜', () {
    testWidgets('横向拖过相邻格就提交到那一格', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      final center = tester.getCenter(dock);
      final from = _offsetOf(tester, dock, 0);
      final to = _offsetOf(tester, dock, 2);

      // 从索引 0 拖到索引 2
      final gesture = await tester.startGesture(center + Offset(from, 0));
      await gesture.moveBy(Offset(to - from, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(log, [2]);
    });

    testWidgets('拖动后被取消（pointer cancel）不提交', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      final center = tester.getCenter(dock);
      final from = _offsetOf(tester, dock, 0);
      final to = _offsetOf(tester, dock, 1);

      final gesture = await tester.startGesture(center + Offset(from, 0));
      await gesture.moveBy(Offset(to - from, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(log, isEmpty);
    });

    testWidgets('拖出左端有橡皮筋，不崩溃、透镜仍可用', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      final center = tester.getCenter(dock);

      final gesture = await tester.startGesture(center + Offset(-150, 0));
      await gesture.moveBy(const Offset(-500, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationDock), findsOneWidget);
      // 越界拖动不会跳到不存在的格
      expect(log.every((i) => i >= 0 && i < _kDestinations.length), isTrue);
    });

    testWidgets('甩动最多越过手指所在格一格', (tester) async {
      final log = <int>[];
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: log.add));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      final center = tester.getCenter(dock);
      final from = _offsetOf(tester, dock, 0);
      final to = _offsetOf(tester, dock, 1);

      // 快速拖到第 1 格就松手，甩动预判不得把选中推到很远
      final gesture = await tester.startGesture(center + Offset(from, 0));
      await gesture.moveBy(Offset(to - from, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(log.length, 1);
      // 从 0 起手，最多落到 2（手指所在格 1 + 1 格甩动余量）
      expect(log.single, lessThanOrEqualTo(2));
    });
  });

  group('参数校验', () {
    test('少于两个 destination 会断言失败', () {
      expect(
        () => NavigationDock(
          destinations: const [
            NavigationDockDestination(icon: Icons.home, label: "首页"),
          ],
          selectedIndex: 0,
          onDestinationSelected: _noop,
        ),
        throwsAssertionError,
      );
    });

    test('selectedIndex 越界会断言失败', () {
      expect(
        () => NavigationDock(
          destinations: _kDestinations,
          selectedIndex: 99,
          onDestinationSelected: _noop,
        ),
        throwsAssertionError,
      );
      expect(
        () => NavigationDock(
          destinations: _kDestinations,
          selectedIndex: -1,
          onDestinationSelected: _noop,
        ),
        throwsAssertionError,
      );
    });
  });

  group('几何纯函数', () {
    test('透镜静止时宽度恰为 extent（lift=0）', () {
      final rect = lensRectFor(
        position: 1.5,
        velocity: 0,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 0,
      );
      expect(rect.width, kNavigationDockItemExtent);
      // 竖直居中
      expect(rect.top, (kNavigationDockHeight - rect.height) / 2);
    });

    test('抬起透镜会放大', () {
      final rest = lensRectFor(
        position: 0,
        velocity: 0,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 0,
      );
      final lifted = lensRectFor(
        position: 0,
        velocity: 0,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 1,
      );
      expect(lifted.width, greaterThan(rest.width));
      expect(lifted.height, greaterThan(rest.height));
      // 放大是四周对称的，仍保持居中
      expect(lifted.top, (kNavigationDockHeight - lifted.height) / 2);
    });

    test('速度越快，透镜越宽越扁（jelly）', () {
      final fast = lensRectFor(
        position: 0,
        velocity: 40,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 1,
      );
      final slow = lensRectFor(
        position: 0,
        velocity: 0,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 1,
      );
      expect(fast.width, greaterThan(slow.width));
      expect(fast.height, lessThan(slow.height));
    });

    test('速度上限被夹住：再快也不会无限拉长', () {
      final absurd = lensRectFor(
        position: 0,
        velocity: 100000,
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 0,
      );
      final capped = lensRectFor(
        position: 0,
        velocity: 8, // _kJellySpeed
        extent: kNavigationDockItemExtent,
        height: kNavigationDockHeight,
        lift: 0,
      );
      expect(absurd.width, capped.width);
    });

    test('橡皮筋阻尼单调递增且不超过 limit', () {
      const limit = 0.35;
      var previous = 0.0;
      for (final overshoot in [0.1, 0.5, 1.0, 5.0, 50.0]) {
        final result = rubberBandOffset(overshoot, limit);
        expect(result, greaterThan(previous));
        expect(result, lessThan(limit));
        previous = result;
      }
    });

    test('橡皮筋方向相反', () {
      expect(
        rubberBandOffset(-1.0, 0.35),
        -rubberBandOffset(1.0, 0.35),
      );
      expect(rubberBandOffset(0.0, 0.35), 0.0);
    });

    test('局部坐标换算：格中心对应整数位置', () {
      const barWidth = 288.0;
      const padding = 4.0;
      // 内层可用宽 288-8=280，每格 70；第 0 格中心在 4+35=39
      expect(
        dockPositionAt(
          dx: 39,
          barWidth: barWidth,
          padding: padding,
          count: 4,
          textDirection: TextDirection.ltr,
        ),
        closeTo(0, 1e-9),
      );
      // 第 2 格中心 = 4 + 70*2 + 35 = 179
      expect(
        dockPositionAt(
          dx: 179,
          barWidth: barWidth,
          padding: padding,
          count: 4,
          textDirection: TextDirection.ltr,
        ),
        closeTo(2, 1e-9),
      );
    });

    test('越界坐标被橡皮筋夹住，不返回巨大值', () {
      final left = dockPositionAt(
        dx: -100000,
        barWidth: 288,
        padding: 4,
        count: 4,
        textDirection: TextDirection.ltr,
      );
      expect(left, greaterThan(-0.35));
      expect(left, lessThan(0));

      final right = dockPositionAt(
        dx: 100000,
        barWidth: 288,
        padding: 4,
        count: 4,
        textDirection: TextDirection.ltr,
      );
      expect(right, greaterThan(3));
      expect(right, lessThan(3 + 0.35));
    });

    test('RTL 下镜像：靠右的第一格是位置 0', () {
      final rtl = dockPositionAt(
        dx: 249, // 288-39
        barWidth: 288,
        padding: 4,
        count: 4,
        textDirection: TextDirection.rtl,
      );
      expect(rtl, closeTo(0, 1e-9));
    });

    test('count=0 时返回 0 而不除零', () {
      expect(
        dockPositionAt(
          dx: 10,
          barWidth: 288,
          padding: 4,
          count: 0,
          textDirection: TextDirection.ltr,
        ),
        0,
      );
    });
  });

  group('鼠标悬停（桌面端）', () {
    testWidgets('hover 进出会画/收高亮，且不残留', (tester) async {
      await tester.pumpWidget(_host(selectedIndex: 0, onSelected: _noop));
      await tester.pumpAndSettle();

      final dock = find.byType(NavigationDock);
      final center = tester.getCenter(dock);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(200, 100));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(center);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await mouse.moveTo(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
