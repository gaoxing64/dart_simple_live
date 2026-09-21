import 'package:flutter/material.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as glass;
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';

/// 测试用字体族名。测试环境不会真的加载字形，只要样式里带着这个名字就够了。
const String _kTestFontFamily = "SliveTestFont";

/// 单项宽度，与 floating_navigation_bar 里的 `_kIndicatorWidth` 一致。
/// 断言里的宽度都由它和入口数派生，增删入口时不用改断言。
const double _kIndicatorWidth = 86.0;

/// 默认的 4 个入口。
const List<FloatingNavigationDestination> _kDestinations = [
  FloatingNavigationDestination(icon: Icon(Icons.home), label: "首页"),
  FloatingNavigationDestination(icon: Icon(Icons.star), label: "关注"),
  FloatingNavigationDestination(icon: Icon(Icons.apps), label: "分类"),
  FloatingNavigationDestination(icon: Icon(Icons.person), label: "我的"),
];

/// 第 2 个入口禁用：glass 分支必须和非玻璃分支一样忽略它的点击。
const List<FloatingNavigationDestination> _kDisabledSecond = [
  FloatingNavigationDestination(icon: Icon(Icons.home), label: "首页"),
  FloatingNavigationDestination(
    icon: Icon(Icons.star),
    label: "关注",
    enabled: false,
  ),
  FloatingNavigationDestination(icon: Icon(Icons.apps), label: "分类"),
];

/// 自绘图标（非 [Icon]）走 iconBuilder 路径：选中态要换成 selectedIcon。
const Key _kSecondUnselectedArt = Key("art-2-unselected");
const Key _kSecondSelectedArt = Key("art-2-selected");

const List<FloatingNavigationDestination> _kCustomIconDestinations = [
  FloatingNavigationDestination(icon: Icon(Icons.home), label: "首页"),
  FloatingNavigationDestination(
    icon: SizedBox(key: _kSecondUnselectedArt, width: 24, height: 24),
    selectedIcon: SizedBox(key: _kSecondSelectedArt, width: 24, height: 24),
    label: "关注",
  ),
];

class _Host extends StatefulWidget {
  const _Host({this.liquidGlass = false, this.destinations = _kDestinations});

  final bool liquidGlass;
  final List<FloatingNavigationDestination> destinations;

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
          destinations: widget.destinations,
        ),
      ),
    );
  }
}

/// 按入口序号点玻璃底栏里的第 [index] 个标签。
///
/// 不用 find.text + tap：开着滑动指示器时每个标签的文字会画两层（药丸内 /
/// 药丸外），find.text 会命中 2 个；且文字画在玻璃底下、本身不吃点击。
Future<void> _tapGlassTab(WidgetTester tester, Finder barFinder, int index) async {
  final barRect = tester.getRect(barFinder);
  final count = tester
      .widget<FloatingNavigationBar>(barFinder)
      .destinations
      .length;
  await tester.tapAt(
    Offset(
      barRect.left + barRect.width * (index + 0.5) / count,
      barRect.top + kFloatingNavBarHeight / 2,
    ),
  );
  await tester.pumpAndSettle();
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
    expect(tester.getSize(barFinder).width, _kDestinations.length * _kIndicatorWidth);

    // 点击「关注」切换选中项
    await tester.tap(find.text("关注"));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬浮胶囊导航栏：Liquid Glass 底栏开关', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host(liquidGlass: true)));
    await tester.pumpAndSettle();

    final barFinder = find.byType(FloatingNavigationBar);
    expect(barFinder, findsOneWidget);
    expect(tester.takeException(), isNull);

    // 玻璃模式整条底栏换成 liquid_glass_easy 的组件
    // （胶囊背景 + 图标文字 + 选中药丸都由它绘制）
    expect(find.byType(glass.LiquidGlassTabBar), findsOneWidget);

    // 尺寸口径与非玻璃分支一致：高度 = 胶囊 + 底栏下边距，宽度 = 入口数 * 单项宽度
    expect(
      tester.getSize(barFinder).height,
      kFloatingNavBarHeight + kFloatingNavBarBottomPadding,
    );
    expect(tester.getSize(barFinder).width, _kDestinations.length * _kIndicatorWidth);

    // 交互由 LiquidGlassTabBar 自己接，回调仍然回到 onDestinationSelected。
    await _tapGlassTab(tester, barFinder, 1);
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  // 回归：玻璃底栏的 tap 层是包内 flutter/material 的 InkWell（每标签一个，
  // 画在图标层**上面**）。本项目 UI 走 material_ui，两套 Theme 是不同类型 ——
  // 不加约束时它读不到深色主题，退回亮色兜底主题并解析出 40% 浅灰的
  // highlight / splash，于是"选中药丸 + 一块浅灰高亮"同时存在。
  // 这里锁住三个 ink 颜色都是透明，保证整条底栏只有一个指示器。
  testWidgets('悬浮胶囊导航栏：Liquid Glass 底栏不画 ink 高亮', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host(liquidGlass: true)));
    await tester.pumpAndSettle();

    // 必须从 InkWell 自己的 context 取 Theme：那才是它解析 ink 的地方。
    // 从 FloatingNavigationBar 的 element 取会落在套上去的 Theme **外面**，
    // 拿到的还是亮色兜底主题。
    expect(find.byType(fm.InkWell), findsNWidgets(_kDestinations.length));
    final inkCtx = tester.element(find.byType(fm.InkWell).first);
    final theme = fm.Theme.of(inkCtx);
    expect(theme.highlightColor, fm.Colors.transparent);
    expect(theme.splashColor, fm.Colors.transparent);
    expect(theme.hoverColor, fm.Colors.transparent);
    // 亮色主题下注入的 ThemeData 也应当是亮色
    expect(theme.brightness, fm.Brightness.light);
  });

  // 回归：注入的 ThemeData 必须带上真实亮度。兜底主题恒为亮色，而包里取兜底亮度
  // 的地方（liquidGlassFallbackBrightness）读的就是 Theme.of(context).brightness ——
  // 不带进去的话，深色模式下包内一切按亮度取值的默认项都会走亮色档。
  testWidgets('悬浮胶囊导航栏：Liquid Glass 底栏跟随主题亮度', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const _Host(liquidGlass: true),
      ),
    );
    await tester.pumpAndSettle();

    final inkCtx = tester.element(find.byType(fm.InkWell).first);
    expect(
      fm.Theme.of(inkCtx).brightness,
      fm.Brightness.dark,
      reason: "深色主题下包内读到的兜底主题也必须是深色",
    );
  });

  // 外观设置里选的字体挂在 material_ui 的 ThemeData 上，而底栏文字跑在包内的
  // flutter/material 兜底主题下（本项目两套 Theme 不是同一个类型）——
  // 不显式把 fontFamily 带过去，标签就会掉回系统默认字体。
  testWidgets('悬浮胶囊导航栏：Liquid Glass 底栏跟随外观里选的字体', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: _kTestFontFamily),
        home: const _Host(liquidGlass: true),
      ),
    );
    await tester.pumpAndSettle();

    // 开滑动指示器时标签会画两层（药丸内/外），取第一个即可
    final labelCtx = tester.element(find.text("首页").first);
    expect(
      fm.DefaultTextStyle.of(labelCtx).style.fontFamily,
      _kTestFontFamily,
      reason: "底栏标签应跟随外观里选的字体",
    );
  });

  // 回归：玻璃分支曾经无条件回调 onDestinationSelected，把 destination 的
  // enabled 语义丢了 —— 非玻璃分支靠 _NavigationDestinationBuilder 的
  // `onTap: enabled ? ... : null` 兜住，两边的行为必须一致。
  testWidgets('悬浮胶囊导航栏：Liquid Glass 底栏尊重 destination 的 enabled', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: _Host(liquidGlass: true, destinations: _kDisabledSecond),
      ),
    );
    await tester.pumpAndSettle();

    final barFinder = find.byType(FloatingNavigationBar);

    // 点被禁用的第 2 个入口：不该选中
    await _tapGlassTab(tester, barFinder, 1);
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      0,
      reason: "enabled: false 的入口在玻璃模式下也不该可选中",
    );

    // 未禁用的第 3 个入口仍然正常切换（证明上面不是因为整个点击都失效）
    await _tapGlassTab(tester, barFinder, 2);
    expect(
      tester.widget<FloatingNavigationBar>(barFinder).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  // 回归：自绘图标（非 Icon → iconBuilder 路径）曾经永远只画 icon，selectedIcon
  // 被静默丢弃，于是「描边 / 实心两版图标」的入口在玻璃模式下选中态永远停在
  // 未选中那版。
  //
  // 不靠真实底栏的 widget 树来验：包会把每个 cell 在选中/未选中两种状态下都
  // 预先建好多层（供药丸滑动时的揭示用），两种图同时存在，数不出「换了图」。
  // 这里直接把 iconBuilder 的输出渲染出来，分别喂 glyph.selected 的两种取值。
  testWidgets('悬浮胶囊导航栏：Liquid Glass 自绘图标按选中态切换', (tester) async {
    final item =
        FloatingNavigationBar.liquidGlassItemFor(_kCustomIconDestinations[1]);
    final builder = item.iconBuilder;
    expect(builder, isNotNull, reason: "非 Icon 图标应走 iconBuilder 路径");

    const glyphColor = Color(0xFF000000);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              builder!(
                context,
                const glass.LiquidGlassGlyph(color: glyphColor, size: 24),
              ),
              builder(
                context,
                const glass.LiquidGlassGlyph(
                  color: glyphColor,
                  size: 24,
                  selected: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 两层各自画对：未选中层用 icon，选中层用 selectedIcon。
    // 若实现退化成「永远画 icon」，第一条会变成 2 个、第二条会变成 0 个。
    expect(find.byKey(_kSecondUnselectedArt), findsOneWidget);
    expect(find.byKey(_kSecondSelectedArt), findsOneWidget);
  });
}
