// 桌面端 / 触摸切页的回归：
// * 首页平台 TabBarView：鼠标左键横拖切页（AppScrollBehavior 把 mouse 放进了
//   dragDevices，见 app_scroll_behavior.dart）；
// * 关注页三视图：导航在左侧第二栏，翻页走纵轴且手势不参与（侧栏是唯一入口）。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' show Axis, NeverScrollableScrollPhysics, PageView, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'follow_test_harness.dart';

/// 紧凑成员行定位（默认布局 = 紧凑，直播中页渲染的是行不是卡）。
Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

/// 用鼠标左键按住从 [fromX] 拖到 [toX]（同一水平线），模拟桌面端横拖翻页。
Future<void> mouseSwipe(WidgetTester tester, {required double fromX, required double toX, double y = 400}) async {
  final pointer = TestPointer(99, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(Offset(fromX, y)));
  await tester.pump();
  await tester.sendEventToBinding(pointer.down(Offset(fromX, y)));
  const steps = 10;
  for (var i = 1; i <= steps; i++) {
    await tester.sendEventToBinding(pointer.move(Offset(fromX + (toX - fromX) * i / steps, y)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.sendEventToBinding(pointer.up());
  // 落定动画 + 相邻页构建
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => Get.testMode = true);

  testWidgets('首页：鼠标左键横拖切换平台 Tab', (tester) async {
    await pumpIndexed(tester); // 停在首页
    final home = Get.find<HomeController>();
    expect(home.tabController.index, 0);

    await mouseSwipe(tester, fromX: 360, toX: 40, y: 400);
    expect(home.tabController.index, 1, reason: '向左拖应切到下一个平台');

    await mouseSwipe(tester, fromX: 40, toX: 360, y: 400);
    expect(home.tabController.index, 0, reason: '向右拖应切回上一个平台');
    await settleEnd(tester);
  });

  testWidgets('关注页：翻页走纵轴、手势不参与；侧栏切换生效', (tester) async {
    final svc = FakeFollowService(
      users: [
        _u('甲', live: 2),
        _u('乙'),
        _u('丙', live: 2),
      ],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙']),
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await settle(tester);
    final c = Get.find<FollowUserController>();
    expect(c.activeTab.value, 0);
    // 「全部」页是全量平铺（文件夹总览已移除）
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);

    // 侧栏在左 → 翻页沿 Y 轴，且手势不参与（页内是竖向列表，不能抢轴）。
    // 壳里还有一个 Section PageView，必须限定在关注页内找。
    final followPageView = tester.widget<PageView>(find.descendant(
      of: find.byType(FollowUserPage),
      matching: find.byType(PageView),
    ));
    expect(followPageView.scrollDirection, Axis.vertical);
    expect(followPageView.physics, isA<NeverScrollableScrollPhysics>());

    // 鼠标横拖不再切页（旧行为已移除）
    await mouseSwipe(tester, fromX: 360, toX: 40, y: 600);
    expect(c.activeTab.value, 0, reason: '横拖不应再按 X 轴切页');
    expect(rowOf('甲'), findsOneWidget);

    // 唯一切换入口：左侧第二栏。切过去后 activeTab 同步、内容跟上
    await tester.tap(find.byKey(const ValueKey('sidebar-live')));
    await settle(tester);
    expect(c.activeTab.value, 1);
    expect(c.activeSidebarKey, 'live');
    // 直播中页：甲 + 丙 两个在播。布局设置默认紧凑 → 紧凑行
    // （「直播中恒卡片」的自动逻辑已移除，卡片要用户自己切）。
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('丙'), findsOneWidget);
    expect(rowOf('乙'), findsNothing);
    await settleEnd(tester);
  });
}

FollowUser _u(String name, {int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = live;
