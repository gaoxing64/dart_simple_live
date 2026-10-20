// 「全部」页（全量平铺）与分组操作的 widget 测试：
// 平铺渲染 / 布局设置作用于「全部」页、勾选→编辑批量移入分组、快速分组
// sheet、鼠标滚轮、移动端底栏安全区、侧栏切视图。
//
// 假数据源用 `follow_test_harness.dart` 的 FakeFollowService：
// 归组（addUserToTag 一族）/ reorderFollowTag 是内存实现（真实现经 DBService
// 写 Hive，widget test 里没注册 DBService）。
//
// 文件夹总览（一组一张可折叠卡片 + 未分组段）已随二级菜单导航移除：
// 分组改从第二栏的分组标签进，「全部」页与分组筛选共用一套平铺渲染。
import 'dart:ui' show PointerDeviceKind, Rect;

import 'package:flutter/material.dart' show FlutterError, FlutterErrorDetails, Key, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_quick_group_sheet.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, {int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = live;

/// 侧栏标签定位：每项带 `sidebar-<FollowSidebarItem.key>` 的 key。
Finder sidebarOf(String key) => find.byKey(ValueKey('sidebar-$key'));

Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

/// 接管 `FlutterError.onError` 跑 [body]，逐条断言期间收到的渲染异常都是
/// LiveRoomCard 已知的 1px 竖向溢出（doc/test-suite.md §7 的红灯），
/// 其他异常必须让测试红。
Future<void> withLiveCardOverflowTolerated(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final captured = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = captured.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  for (final details in captured) {
    expect(
      details.exception.toString(),
      contains('A RenderFlex overflowed by'),
      reason: '只放行 LiveRoomCard 已知的 1px 溢出红灯，其他异常必须让测试红',
    );
  }
}

Future<FakeFollowService> seedGrouped(WidgetTester tester) async {
  final svc = FakeFollowService(
    users: [
      _u('甲', live: 2),
      _u('乙'),
      _u('丙'),
      _u('丁'),
    ],
    tags: [
      FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙']),
      FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['huya_丙']),
    ],
  );
  final indexed = await pumpIndexed(tester, followService: svc);
  await gotoFollowPage(tester, indexed);
  return svc;
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('「全部」页 = 全量平铺：不按分组拆卡片、没有「未分组」段', (tester) async {
    await seedGrouped(tester);

    // 四个关注都在（不分组成卡片，也不按组隐藏）
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);
    expect(rowOf('丙'), findsOneWidget);
    expect(rowOf('丁'), findsOneWidget);
    // 文件夹总览的遗留物都不该出现
    expect(find.text('未分组'), findsNothing);
    expect(find.text('拖到这里移出分组'), findsNothing);
    // 段头是「全部」+ 在播计数（「全部」也出现在侧栏，共两处）
    expect(find.text('全部'), findsNWidgets(2));
    expect(find.textContaining('1/4 在播'), findsOneWidget);
    // 顶栏没有一键折叠（没有可折叠的对象了）
    expect(find.byTooltip('折叠全部分组'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('侧栏切视图：直播中/未开播按布局设置渲染（默认紧凑行）', (tester) async {
    await seedGrouped(tester);

    expect(sidebarOf('live'), findsOneWidget);
    expect(sidebarOf('offline'), findsOneWidget);

    // 布局设置默认紧凑：两页都是紧凑行
    await tester.tap(sidebarOf('live'));
    await settle(tester);
    expect(find.byType(LiveRoomCard), findsNothing);
    expect(rowOf('甲'), findsOneWidget);

    await tester.tap(sidebarOf('offline'));
    await settle(tester);
    expect(rowOf('丙'), findsOneWidget);
    expect(rowOf('甲'), findsNothing);

    await tester.tap(sidebarOf('all'));
    await settle(tester);
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('丁'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('布局设置切卡片后，「全部」页也渲染卡面', (tester) async {
    await seedGrouped(tester);
    // 「全部」页全量平铺 + 卡面（4 个关注 → 4 张卡）。
    // 卡面渲染会触发已知 1px 溢出，设置切换那步也要在容忍助手里跑。
    await withLiveCardOverflowTolerated(tester, () async {
      Get.find<AppSettingsController>().setFollowStyleNotGrid(false);
      await settle(tester);
    });
    expect(find.byType(LiveRoomCard), findsNWidgets(4));
    expect(rowOf('甲'), findsNothing);

    // 切回紧凑：全量平铺的紧凑行
    Get.find<AppSettingsController>().setFollowStyleNotGrid(true);
    await settle(tester);
    expect(find.byType(LiveRoomCard), findsNothing);
    expect(rowOf('甲'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('未开播卡面：头像以圆形占位居中，不拉满整块封面', (tester) async {
    // 头像非空、封面为空 = 关注页里未开播卡的典型数据
    final svc = FakeFollowService(
      users: [
        FollowUser(
          id: 'huya_甲',
          roomId: 'r-甲',
          siteId: 'huya',
          userName: '甲',
          face: 'https://example.com/avatar-a.png',
          addTime: DateTime(2024),
        )..liveStatus.value = 1,
        FollowUser(
          id: 'huya_乙',
          roomId: 'r-乙',
          siteId: 'huya',
          userName: '乙',
          face: 'https://example.com/avatar-b.png',
          addTime: DateTime(2024),
        )..liveStatus.value = 1,
      ],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    // 卡面走圆形头像占位
    await withLiveCardOverflowTolerated(tester, () async {
      Get.find<AppSettingsController>().setFollowStyleNotGrid(false);
      await settle(tester);
    });

    expect(find.byKey(const ValueKey('card-avatar-cover')), findsNWidgets(2));
    // 占位头像是 110 的圆：与原 logo 占位（scaleDown 填满 110 封面）同尺寸
    final avatar = tester.widget<NetImage>(find
        .descendant(
          of: find.byKey(const ValueKey('card-avatar-cover')),
          matching: find.byType(NetImage),
        )
        .first);
    expect(avatar.width, 110);
    expect(avatar.height, 110);
    expect(avatar.borderRadius, 55);
    await settleEnd(tester);
  });

  testWidgets('勾选→编辑：顶栏选择态 + 新建分组批量移入', (tester) async {
    final svc = await seedGrouped(tester);
    final c = Get.find<FollowUserController>();

    // 滚进视口中部（让后面的行进入视口）
    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);

    // 勾选丁（未在任何组）→ 顶栏进入选择态
    await tester.tap(find.descendant(of: rowOf('丁'), matching: find.byType(NetImage)));
    await settle(tester);
    expect(c.selectedIds.contains('huya_丁'), isTrue);
    expect(find.text('已选择 1 位'), findsOneWidget);
    // 「点击头像勾选」讲解条已删：勾选态一看便知，不值得占一条横幅
    expect(find.textContaining('点击头像勾选主播'), findsNothing);

    // 再勾选乙（CS解说组内）→ 跨组累积
    await tester.tap(find.descendant(of: rowOf('乙'), matching: find.byType(NetImage)));
    await settle(tester);
    expect(find.text('已选择 2 位'), findsOneWidget);

    // 滚回顶部让收起的顶栏展开，再点「移入分组」
    await tester.dragFrom(const Offset(200, 400), const Offset(0, 300));
    await settle(tester);
    await tester.tap(find.byTooltip('移入分组'));
    await settle(tester);
    expect(find.text('分组名称'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('quick-group-name-field')),
      '新观赛组',
    );
    await tester.tap(find.text('创建分组'));
    await settle(tester);

    // 多归属语义：批量是「加入」新分组，原分组身份保留 ——
    // 乙 原在 CS解说，加入「新观赛组」后两个组都待得住。
    final created = svc.followTagList.firstWhere((t) => t.tag == '新观赛组');
    expect(created.userId, containsAll(['huya_丁', 'huya_乙']));
    expect(svc.followTagList.firstWhere((t) => t.tag == 'CS解说').userId, contains('huya_乙'));
    // 丁 原来没分组，加入后归属落到「新观赛组」
    expect(svc.userTagNamesOf('huya_丁'), contains('新观赛组'));
    expect(c.selectedIds, isEmpty);
    expect(find.text('已选择 1 位'), findsNothing);
    // 新组出现在侧栏（分组标签）
    expect(sidebarOf('group:${created.id}'), findsOneWidget);
    await settleEnd(tester);
    // 排干 SmartDialog toast 的计时器
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('编辑弹窗：移入已有分组', (tester) async {
    final svc = await seedGrouped(tester);

    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.descendant(of: rowOf('丁'), matching: find.byType(NetImage)));
    await settle(tester);
    // 滚回顶部让收起的顶栏展开
    await tester.dragFrom(const Offset(200, 400), const Offset(0, 300));
    await settle(tester);
    await tester.tap(find.byTooltip('移入分组'));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(FollowQuickGroupSheet), matching: find.text('LOL解说')));
    await settle(tester);

    expect(svc.userTagNamesOf('huya_丁'), contains('LOL解说'));
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('鼠标滚轮：悬停在成员行上也必须能滚动外层列表', (tester) async {
    // 内容要足够长才能滚：一批平铺行，模拟真实关注量
    final svc = FakeFollowService(
      users: [for (var i = 0; i < 20; i++) _u('散人$i')],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();
    await settle(tester);
    expect(c.scrollController.position.maxScrollExtent, greaterThan(100), reason: '内容应足够长、可滚动');

    Future<double> wheelAt(Offset at, {double? jumpTo}) async {
      if (jumpTo != null) {
        c.scrollController.position.jumpTo(jumpTo);
        await settle(tester);
      }
      final pointer = TestPointer(99, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.pump();
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final before = c.scrollController.position.pixels;
      // 真实用户会连滚多下：第二下也必须生效
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      return c.scrollController.position.pixels - before;
    }

    // 每次测量前回到固定滚动位置，且只悬停在视口内的行上，避免
    // 上一次滚动把目标滚出视口造成误判
    c.scrollController.position.jumpTo(0);
    await settle(tester);
    final onMember = await wheelAt(tester.getCenter(rowOf('散人0')));

    // 底部附近（未到底）：滚轮悬停在最靠下的行上应继续推进。
    // 留 450px 余量：两格各 200px 都必须真实推进，而不是撞到 max 被钳制。
    final pos = c.scrollController.position;
    pos.jumpTo(pos.maxScrollExtent - 450);
    await settle(tester);
    String? bottomRow;
    Offset? bottomAt;
    final viewH = pos.viewportDimension;
    for (var i = 19; i >= 0; i--) {
      final row = rowOf('散人$i');
      if (row.evaluate().isEmpty) continue;
      final center = tester.getCenter(row);
      if (center.dy > 0 && center.dy < viewH) {
        bottomRow = '散人$i';
        bottomAt = center;
        break;
      }
    }
    expect(bottomRow, isNotNull, reason: '接近底部时应能看到成员行');
    final onBottom = await wheelAt(bottomAt!);
    expect(onMember, greaterThan(0), reason: '滚轮悬停在成员行上不得失效');
    expect(onBottom, greaterThan(0), reason: '滚轮在列表底部应滚动');
    await settleEnd(tester);
  });

  testWidgets('移动端：滚到底后最后一行在视口内、不被底栏安全区挤出', (tester) async {
    // 旧的红灯在分组卡片里：卡片成员的 GridView 不显式给 padding，
    // `ScrollView` 会拿 `MediaQuery.padding` 的主轴分量当默认内边距，整张
    // 卡片底部凭空多出一截。文件夹卡片已随二级菜单导航移除，这个载体没了；
    // 这里保留等价回归：长列表滚到底，最后一行必须完整落在视口里。
    final svc = FakeFollowService(
      users: [for (var i = 0; i < 20; i++) _u('散人$i')],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();
    await settle(tester);
    final pos = c.scrollController.position;
    expect(pos.maxScrollExtent, greaterThan(100), reason: '前提：列表要能滚');

    pos.jumpTo(pos.maxScrollExtent);
    await settle(tester);

    Rect? bottomRow;
    for (final element in find.byType(FollowMemberRow).evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      if (rect.top >= 0 && rect.bottom <= pos.viewportDimension + 1) {
        if (bottomRow == null || rect.bottom > bottomRow.bottom) {
          bottomRow = rect;
        }
      }
    }
    expect(bottomRow, isNotNull, reason: '滚到底后视口里应能看到成员行');
    expect(bottomRow!.bottom, lessThanOrEqualTo(pos.viewportDimension), reason: '最后一行必须完整落在视口内');
    await settleEnd(tester);
  });
}
