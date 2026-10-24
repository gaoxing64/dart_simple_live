import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/watch_year_selector.dart';

void main() {
  testWidgets('年份选择使用圆角菜单并可切换', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WatchYearSelector(
              years: const [2026, 2025],
              value: 2026,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButton<int>), findsNothing);
    final button = tester.widget<PopupMenuButton<int>>(
      find.byKey(const ValueKey('watch-year-menu')),
    );
    final shape = button.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, AppStyle.radius16);
    expect(button.position, PopupMenuPosition.under);

    await tester.tap(find.byKey(const ValueKey('watch-year-menu')));
    await tester.pumpAndSettle();
    expect(find.text('2025 年'), findsOneWidget);
    await tester.tap(find.text('2025 年'));
    await tester.pumpAndSettle();
    expect(selected, 2025);
  });
}
