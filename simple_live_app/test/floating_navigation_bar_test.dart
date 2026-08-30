import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';

class _Host extends StatefulWidget {
  const _Host({this.liquidGlass = false});

  final bool liquidGlass;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: Center(
        // 与 indexed_page 用法一致：保持胶囊按内容宽度居中
        heightFactor: 1,
        child: FloatingNavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          liquidGlass: widget.liquidGlass,
          // 测试环境用 standard，避免依赖 Impeller 多 pass 着色器
          liquidGlassQuality: glass.GlassQuality.standard,
          destinations: const [
            FloatingNavigationDestination(icon: Icon(Icons.home), label: "首页"),
            FloatingNavigationDestination(icon: Icon(Icons.star), label: "关注"),
            FloatingNavigationDestination(icon: Icon(Icons.apps), label: "分类"),
            FloatingNavigationDestination(
              icon: Icon(Icons.person),
              label: "我的",
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('悬浮胶囊导航栏：渲染、尺寸、切换', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final barFinder = find.byType(FloatingNavigationBar);
    expect(barFinder, findsOneWidget);
    expect(tester.takeException(), isNull);

    // 高度 = 胶囊高度 + 底栏自身下边距（测试环境无安全区）
    expect(
      tester.getSize(barFinder).height,
      kFloatingNavBarHeight + kFloatingNavBarBottomPadding,
    );
    // 胶囊宽度 = 入口数 * 单项宽度，不铺满屏幕
    expect(tester.getSize(barFinder).width, 4 * 86.0);

    // 点击「关注」切换选中项
    await tester.tap(find.text("关注"));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬浮胶囊导航栏：Liquid Glass 背景开关', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host(liquidGlass: true)));
    await tester.pumpAndSettle();

    final barFinder = find.byType(FloatingNavigationBar);
    expect(barFinder, findsOneWidget);
    expect(tester.takeException(), isNull);

    // 玻璃只替换背景：AdaptiveGlass 参与渲染，胶囊本体仍然存在
    expect(find.byType(glass.AdaptiveGlass), findsOneWidget);

    // 尺寸与交互仍沿用悬浮胶囊自身实现
    expect(
      tester.getSize(barFinder).height,
      kFloatingNavBarHeight + kFloatingNavBarBottomPadding,
    );
    expect(tester.getSize(barFinder).width, 4 * 86.0);

    await tester.tap(find.text("关注"));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
