// 桌面端 / 触摸「左右横拖切页」的回归：
// 首页平台 TabBarView 与关注页视图 TabBarView 都必须能用鼠标左键横拖切页
// （AppScrollBehavior 把 mouse 放进了 dragDevices，见 app_scroll_behavior.dart）。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_group_card.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'follow_test_harness.dart';

/// 用鼠标左键按住从 [fromX] 拖到 [toX]（同一水平线），模拟桌面端横拖翻页。
Future<void> mouseSwipe(WidgetTester tester,
    {required double fromX, required double toX, double y = 400}) async {
  final pointer = TestPointer(99, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(Offset(fromX, y)));
  await tester.pump();
  await tester.sendEventToBinding(pointer.down(Offset(fromX, y)));
  const steps = 10;
  for (var i = 1; i <= steps; i++) {
    await tester.sendEventToBinding(
        pointer.move(Offset(fromX + (toX - fromX) * i / steps, y)));
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

  testWidgets('关注页：鼠标左键横拖切换视图 Tab（全部→直播中）', (tester) async {
    final svc = FakeFollowService(
      users: [
        _u('甲', tag: 'CS解说', live: 2),
        _u('乙', tag: 'CS解说'),
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
    expect(c.tabController.index, 0);
    expect(find.byType(FollowGroupCard), findsOneWidget);

    // 在未分组行下方的空白处起拖，避开卡片头部（那是调序把手）
    await mouseSwipe(tester, fromX: 360, toX: 40, y: 600);
    expect(c.tabController.index, 1, reason: '向左拖应切到「直播中」');
    expect(c.activeTab.value, 1, reason: 'activeTab 应随翻页同步');
    expect(find.byType(FollowGroupCard), findsNothing);
    // 直播中页：甲 + 丙 两个在播 → 两张卡片
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    await settleEnd(tester);
  });
}

FollowUser _u(String name, {String tag = '全部', int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
      tag: tag,
    )..liveStatus.value = live;
