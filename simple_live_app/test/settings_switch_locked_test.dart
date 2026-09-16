// 回归测试：SettingsSwitch 的「锁定」分支。
//
// locked 时开关不可被拨动（取值由外部控制），点击给出 lockedHint 提示。
// 之前 locked=true 但没传 lockedHint 时，这一行是「能点但毫无反馈」的
// 静默失败——现在 debug 下会断言，这里把两条路径都钉住。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

void main() {
  Widget host({
    required bool value,
    required bool locked,
    String? lockedHint,
    required ValueChanged<bool> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsSwitch(
          title: '测试开关',
          value: value,
          locked: locked,
          lockedHint: lockedHint,
          onChanged: onChanged,
        ),
      ),
    );
  }

  testWidgets('未锁定时点击翻转取值', (tester) async {
    var value = false;
    await tester.pumpWidget(host(
      value: value,
      locked: false,
      onChanged: (v) => value = v,
    ));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(value, isTrue);
  });

  testWidgets('锁定时点击不改变取值，只弹提示', (tester) async {
    var value = false;
    var changed = 0;
    await tester.pumpWidget(host(
      value: value,
      locked: true,
      lockedHint: '已被其它设置锁定',
      onChanged: (v) {
        changed++;
        value = v;
      },
    ));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // 取值没被改，onChanged 也没被调
    expect(value, isFalse);
    expect(changed, 0);
    // 提示真的弹出来了
    expect(find.text('已被其它设置锁定'), findsOneWidget);
  });

  testWidgets('锁定时滑块上是锁图标', (tester) async {
    await tester.pumpWidget(host(
      value: true,
      locked: true,
      lockedHint: '已被锁定',
      onChanged: (_) {},
    ));

    // ⚠️ 不能用 find.byIcon：M3 Switch 的 thumbIcon 是画家用 TextPainter
    // 按 `String.fromCharCode(iconData.codePoint)` 画出来的
    // （见 material_ui 的 switch.dart），树里**没有** Icon widget，
    // byIcon 永远是 0 个。这里直接断言传下去的 thumbIcon 解析结果。
    Icon? resolveThumbIcon() => tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .thumbIcon
        ?.resolve(<WidgetState>{WidgetState.selected});

    expect(
      resolveThumbIcon()?.icon,
      Icons.lock,
      reason: '锁定时滑块必须是锁图标，否则用户看不出这一项不可改',
    );

    // 未锁定时不给锁图标（走默认的对勾）
    await tester.pumpWidget(host(
      value: true,
      locked: false,
      onChanged: (_) {},
    ));
    expect(resolveThumbIcon()?.icon, Icons.check);
  });

  testWidgets('锁定但没给 lockedHint 时断言（静默失败要能在 debug 看到）',
      (tester) async {
    await tester.pumpWidget(host(
      value: false,
      locked: true,
      onChanged: (_) {},
    ));

    // debug 下 assert(false) 会冒出来；release 构建这条断言被剥离，
    // 点击退化为无反馈——这就是为什么构造期也必须成对传 lockedHint。
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(tester.takeException(), isAssertionError);
  });
}
