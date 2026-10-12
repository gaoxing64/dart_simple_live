// 智能分组入口：关注页顶栏 ⋮ / 关注设置页 →「按平台智能分组」→ 预览确认 → 真的归组。
//
// ⚠️ `pumpIndexed` 内部会 `Get.reset()`，所以 `SmartGroupService` 必须在它之后注册。
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// ⚠️ 本应用跑在 material_ui 上，`PopupMenuButton` 要用它导出的那个，
// 换成 flutter/material 的 `find.byType` 永远匹配不上（同 follow_search_test.dart 的教训）。
import 'package:material_ui/material_ui.dart' show PopupMenuButton;
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_app_setting/follow_app_settings_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_app_setting/follow_app_settings_page.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/smart_group_preview_sheet.dart';
import 'package:simple_live_app/services/smart_group_service.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, String siteId) => FollowUser(
      id: '${siteId}_$name',
      roomId: 'r-$name',
      siteId: siteId,
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = 1;

/// 注册智能分组服务（必须在 pumpIndexed 之后）。
///
/// ⚠️ 别写成 `void useSmartGroup() => Get.put(SmartGroupService());`：
/// 箭头函数的返回类型 `void` 会把泛型 `S` 推成 `void`，实例注册到 "void"
/// 这个 key 上，`Get.find<SmartGroupService>()` 就找不到（实测 reg=false）。
/// 显式写 `<SmartGroupService>` 最稳。
void useSmartGroup() {
  Get.put<SmartGroupService>(SmartGroupService());
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('⋮ 菜单里有「按平台智能分组」，点开预览并确认后完成归组', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya'), _u('乙', 'huya'), _u('丙', 'douyu')],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    // 打开 ⋮ 弹层
    await tester.tap(find.byType(PopupMenuButton<int>).last);
    await settle(tester);
    expect(find.text('按平台智能分组'), findsOneWidget);

    await tester.tap(find.text('按平台智能分组'));
    await settle(tester);

    // 预览弹窗：一行一个平台，组名 + 人数都摊在确认之前
    expect(find.byType(SmartGroupPreviewSheet), findsOneWidget);
    expect(find.textContaining('虎牙直播'), findsWidgets);
    expect(find.textContaining('斗鱼直播'), findsWidgets);

    await tester.tap(find.text('开始分组'));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_甲'), contains('虎牙直播'));
    expect(svc.userTagNamesOf('huya_乙'), contains('虎牙直播'));
    expect(svc.userTagNamesOf('douyu_丙'), contains('斗鱼直播'));
    expect(find.byType(SmartGroupPreviewSheet), findsNothing);

    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3)); // 排干 toast 计时器
  });

  testWidgets('全部关注都已在对应平台分组里时，只 toast 不弹空表', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya')],
      tags: [FollowUserTag(id: 'a0', tag: '虎牙直播', userId: ['huya_甲'])],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    await Get.find<FollowUserController>().runSmartGrouping();
    await settle(tester);

    expect(find.byType(SmartGroupPreviewSheet), findsNothing);
    expect(find.text('开始分组'), findsNothing);
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('关注设置页入口：点「按平台智能分组」弹预览，确认后归组', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', 'huya')],
      tags: [],
    );
    await pumpIndexed(tester, followService: svc);
    useSmartGroup();
    // 关注设置页整页当 home 泵出来：**全程不进关注页**，也就不会建
    // `FollowUserController`（它 onInit 要 vsync 建 TabController，误建一份
    // 空壳实例有风险 —— 计划「已知风险」第 1 条）。这条用例把退路钉住。
    Get.put(FollowAppSettingsController());
    await tester.pumpWidget(GetMaterialApp(
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(),
      home: const FollowSettingsPage(),
    ));
    await settle(tester);
    expect(Get.isRegistered<FollowUserController>(), isFalse);

    await tester.tap(find.widgetWithText(SettingsAction, '按平台智能分组'));
    await settle(tester);

    expect(find.byType(SmartGroupPreviewSheet), findsOneWidget);
    expect(find.textContaining('虎牙直播'), findsWidgets);

    await tester.tap(find.text('开始分组'));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_甲'), contains('虎牙直播'));
    expect(find.byType(SmartGroupPreviewSheet), findsNothing);
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });
}
