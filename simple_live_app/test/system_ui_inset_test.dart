import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: FloatingNavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            FloatingNavigationDestination(icon: Icon(Icons.home), label: "首页"),
            FloatingNavigationDestination(icon: Icon(Icons.star), label: "关注"),
          ],
        ),
      ),
    );
  }
}

const Size _portrait = Size(390, 844);
const Size _landscape = Size(844, 390);

void main() {
  setUp(SystemUiBottomInset.reset);
  tearDown(SystemUiBottomInset.reset);

  test('平台正常上报时采信上报值并记忆', () {
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _portrait),
        24);
    expect(SystemUiBottomInset.remembered, 24);
    // 上报值变化时跟随平台（例如三键导航 48）
    expect(SystemUiBottomInset.resolve(48, systemBar: 48, viewSize: _portrait),
        48);
    expect(SystemUiBottomInset.remembered, 48);
  });

  test('全屏隐藏系统栏期间上报 0 属正常，横屏不会串用竖屏记忆值', () {
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _portrait),
        24);
    SystemUiBottomInset.markHidden();
    // 进全屏后旋转到横屏：横屏本来就没有底部系统栏，不该套用竖屏的 24
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _landscape),
        0);
    // 全屏中平台上报了系统栏高度时仍然采信平台
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _landscape),
        24);
  });

  test('退出全屏后平台漏报 inset 时用记忆值兜底，恢复上报后回到平台值', () {
    // 竖屏进全屏前记下底部高度
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _portrait),
        24);
    SystemUiBottomInset.markHidden();
    // 横屏全屏
    SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _landscape);
    // 退出全屏回到竖屏，平台一直没有重新上报
    SystemUiBottomInset.markRestoring();
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _portrait),
        24);
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _portrait),
        24);
    // 平台恢复上报：立刻回到平台值，记忆值不再生效
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _portrait),
        24);
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _portrait),
        0);
  });

  test('键盘遮挡（系统栏仍在上报）时不兜底，也不多留白', () {
    expect(SystemUiBottomInset.resolve(24, systemBar: 24, viewSize: _portrait),
        24);
    SystemUiBottomInset.markRestoring();
    // 键盘弹出：padding.bottom 收缩为 0，但 viewPadding.bottom 仍是 24
    expect(SystemUiBottomInset.resolve(0, systemBar: 24, viewSize: _portrait),
        0);
    expect(SystemUiBottomInset.remembered, 24);
  });

  test('横屏三键导航（系统栏在侧边）退出全屏后不多留白', () {
    SystemUiBottomInset.markRestoring();
    expect(
        SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _landscape), 0);
  });

  test('从未上报过底部 inset 的设备保持 0', () {
    SystemUiBottomInset.markHidden();
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _portrait),
        0);
    SystemUiBottomInset.markRestoring();
    expect(SystemUiBottomInset.resolve(0, systemBar: 0, viewSize: _portrait),
        0);
  });

  testWidgets('悬浮胶囊导航栏：退出全屏后 inset 丢失仍避让小白条', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    // 系统栏可见：底部 24dp（手势小白条）
    tester.view.viewPadding = const FakeViewPadding(bottom: 72);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final barFinder = find.byType(FloatingNavigationBar);
    final double expected =
        kFloatingNavBarHeight + kFloatingNavBarBottomPadding + 24;
    expect(tester.getSize(barFinder).height, expected);

    // 进全屏 → 系统栏隐藏；退出全屏 → 平台不再上报恢复后的 inset
    SystemUiBottomInset.markHidden();
    tester.view.viewPadding = FakeViewPadding.zero;
    SystemUiBottomInset.markRestoring();
    await tester.pumpAndSettle();

    // 仍然按进全屏前的高度避让
    expect(tester.getSize(barFinder).height, expected);
    expect(tester.takeException(), isNull);
  });
}
