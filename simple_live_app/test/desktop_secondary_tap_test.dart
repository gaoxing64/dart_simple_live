// 回归测试：桌面端「鼠标右键」应能触发移动端「长按」的那套操作。
//
// 移动端靠长按唤出上下文菜单；桌面端按住左键 500ms 也能触发，但不符合桌面习惯
// 也不好发现。SecondaryTapRegion（以及 ShadowCard 里 InkWell.onSecondaryTap）
// 把同一个回调挂到次要点击上。本测试锁住这个行为，并确认主点击不受影响。
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';
import 'package:simple_live_app/widgets/ui/secondary_tap_region.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('SecondaryTapRegion：右键触发回调，主点击不触发', (tester) async {
    var secondary = 0;
    var primary = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SecondaryTapRegion(
            onSecondaryTap: () => secondary++,
            child: ListTile(
              title: const Text('row'),
              onTap: () => primary++,
            ),
          ),
        ),
      ),
    );

    // 主点击仍走 ListTile 自己的 onTap
    await tester.tap(find.text('row'));
    await tester.pump();
    expect(primary, 1);
    expect(secondary, 0, reason: '主点击不应触发右键回调');

    // 右键触发次要回调，且不串到主点击
    await tester.tap(find.text('row'), buttons: kSecondaryButton);
    await tester.pump();
    expect(secondary, 1, reason: '鼠标右键应触发长按那套操作');
    expect(primary, 1, reason: '右键不应触发主点击');
  });

  testWidgets('SecondaryTapRegion：回调为 null 时右键是空操作，主点击不受影响', (tester) async {
    var primary = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SecondaryTapRegion(
            child: ListTile(
              title: const Text('row'),
              onTap: () => primary++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('row'), buttons: kSecondaryButton);
    await tester.pump();
    expect(primary, 0, reason: '右键不应触发主点击');

    await tester.tap(find.text('row'));
    await tester.pump();
    expect(primary, 1, reason: '主点击仍应正常');
  });

  testWidgets('ShadowCard：右键等同长按', (tester) async {
    var longPressed = 0;
    var tapped = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: ShadowCard(
            onTap: () => tapped++,
            onLongPress: () => longPressed++,
            child: const SizedBox(
              width: 120,
              height: 60,
              child: Text('card'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('card'), buttons: kSecondaryButton);
    await tester.pump();
    expect(longPressed, 1, reason: '桌面端右键应等同长按');
    expect(tapped, 0, reason: '右键不应触发主点击');
  });
}
