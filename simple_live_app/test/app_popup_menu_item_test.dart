import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';

/// M3 Expressive 弹出菜单项的回归测试。
///
/// 两件事：
/// 1. **交互不能回归** —— 它是 `PopupMenuItem` 的重写版，点选后必须照样
///    `pop` 回传 value、触发 `onSelected`；
/// 2. **hover 规格锁死** —— 内缩 8dp + 圆角 16dp + 状态层色值与圆形图标按钮
///    同一套（`AppStyle.iconButtonStyle`）。这几项是实现里唯一"自己定"的常量，
///    改坏了肉眼不一定立刻发现，所以用断言钉住。
void main() {
  Widget buildMenu({required ValueChanged<int> onSelected}) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            PopupMenuButton<int>(
              itemBuilder: (context) => const [
                AppPopupMenuItem(
                  value: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.star), AppStyle.hGap12, Text("赛事订阅")],
                  ),
                ),
                AppPopupMenuItem(
                  value: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.sort), AppStyle.hGap12, Text("按序排列")],
                  ),
                ),
              ],
              onSelected: onSelected,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('点选后仍然回传 value 并触发 onSelected', (tester) async {
    int? selected;
    await tester.pumpWidget(buildMenu(onSelected: (value) => selected = value));

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    expect(find.text("赛事订阅"), findsOneWidget);

    await tester.tap(find.text("按序排列"));
    await tester.pumpAndSettle();

    expect(selected, 2);
    // 菜单已关闭
    expect(find.text("赛事订阅"), findsNothing);
  });

  testWidgets('hover 高亮是内缩 + 大圆角，且状态层色值与图标按钮一致', (tester) async {
    await tester.pumpWidget(buildMenu(onSelected: (_) {}));
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.text("赛事订阅"))).colorScheme;

    // 每一项的高亮块都必须是内缩 8 + 圆角 16
    final items = find.byType(AppPopupMenuItem<int>);
    expect(items, findsNWidgets(2));

    for (final item in [items.first, items.last]) {
      final inset = tester.widget<Padding>(
        find.descendant(of: item, matching: find.byType(Padding)).first,
      );
      expect(inset.padding, const EdgeInsets.symmetric(horizontal: 8));

      final inkWell = tester.widget<InkWell>(
        find.descendant(of: item, matching: find.byType(InkWell)).first,
      );
      expect(inkWell.borderRadius, AppStyle.radius16);
      expect(inkWell.hoverColor, scheme.onSurfaceVariant.withValues(alpha: 0.08));
      expect(
        inkWell.highlightColor,
        scheme.onSurfaceVariant.withValues(alpha: 0.1),
      );
    }
  });

  testWidgets('禁用项不可点选也不弹菜单回调', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              PopupMenuButton<int>(
                itemBuilder: (context) => const [
                  AppPopupMenuItem(
                    value: 0,
                    child: Text("不可用"),
                  ),
                  AppPopupMenuItem(
                    value: 1,
                    enabled: false,
                    child: Text("被禁用"),
                  ),
                ],
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();

    // 禁用项：InkWell 没有 onTap
    final disabledItem = find.ancestor(
      of: find.text("被禁用"),
      matching: find.byType(AppPopupMenuItem<int>),
    );
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: disabledItem, matching: find.byType(InkWell)).first,
    );
    expect(inkWell.onTap, isNull);

    // 点它不会关闭菜单、也不回传
    await tester.tap(find.text("被禁用"));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text("被禁用"), findsOneWidget);
  });
}
