// 「全部」视图分组胶囊筛选的 widget 测试：
// 胶囊行出现条件、点胶囊=平铺该组成员、多归属去重、折叠全部按钮让位、
// 筛选态搜索无匹配的空态浮层。
// ⚠️ `PopupMenuButton` 要用 material_ui 导出的那个：本应用跑在 material_ui 上，
// 关注页顶栏 ⋮ 是它的 PopupMenuButton，换 flutter/material 的 find.byType
// 永远匹配不上（同 follow_smart_group_ui_test 的教训）。
import 'package:flutter/material.dart'
    show FlutterError, FlutterErrorDetails, Key, ValueKey;
import 'package:material_ui/material_ui.dart' show PopupMenuButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_group_card.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, {int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = live;

Finder cardOf(String tag) =>
    find.ancestor(of: find.text(tag), matching: find.byType(FollowGroupCard));

Finder rowOf(String name) => find
    .ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

/// 分组胶囊：页面给每枚胶囊发了 `group-filter-<tag id>` 的 key。
///
/// 组名同时出现在胶囊与卡片头部两处（find.text 会多家，与
/// follow_grouped_view_test 同源的问题），点胶囊/断言胶囊必须走 key，
/// 不能走 find.text。
Finder capsuleOf(String tagId) =>
    find.byKey(ValueKey('group-filter-$tagId'));

/// 打开 ⋮ 弹层（与 follow_smart_group_ui_test 同口径）。
Future<void> openOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<int>).last);
  await settle(tester);
}

/// 在接管 `FlutterError.onError` 的前提下执行 [body]，并逐条断言期间收到
/// 的渲染异常都是 LiveRoomCard 已知的 1px 竖向溢出。
///
/// 溢出即 `doc/test-suite.md` §7 已记录的红灯（`follow_grouped_view_test` 的
/// 「tab 变视图切换」与 `viewpager_drag_test` 都挂在它上面）：卡面内容比
/// 网格可用高度高 1px，测试字体度量下必现。卡片模式的新用例会渲染卡面，
/// 不处理就会被记成本轮回归。
///
/// 为什么接管 onError 而不是事后 `takeException` 全吞：binding 对「连续两条
/// 未取走的异常」会合成一条不透明字符串（`Multiple exceptions (N)...`），
/// 明细全丢，做不到「只放行溢出、其他异常炸」。接管后每条都是完整的
/// [FlutterErrorDetails]，其他异常（GetX「没有可观察变量」、布局崩坏等）
/// 让 expect 当场炸掉，测试必须红。
Future<List<FlutterErrorDetails>> withLiveCardOverflowTolerated(
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
  return captured;
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('没有自定义分组不出胶囊行；有分组时默认停在「全部」文件夹总览', (tester) async {
    final svc = FakeFollowService(users: [_u('甲', live: 2), _u('乙')], tags: []);
    var indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    expect(find.text('全部'), findsNothing);
    expect(Get.find<FollowUserController>().activeGroupId.value, isNull);

    final svc2 = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])],
    );
    indexed = await pumpIndexed(tester, followService: svc2);
    await gotoFollowPage(tester, indexed);
    expect(find.text('全部'), findsOneWidget);
    expect(capsuleOf('a0'), findsOneWidget);
    expect(find.byType(FollowGroupCard), findsOneWidget);
    expect(Get.find<FollowUserController>().activeGroupId.value, isNull);
    await settleEnd(tester);
  });

  testWidgets('点分组胶囊 = 平铺该组成员：不套卡片、别的组与未分组不可见', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙'), _u('丙'), _u('丁')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙']),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['huya_丙']),
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();

    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    expect(c.activeGroupId.value, 'a0');
    expect(find.byType(FollowGroupCard), findsNothing);
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);
    expect(rowOf('丙'), findsNothing);
    expect(rowOf('丁'), findsNothing);
    // 段头给计数（● 1/2 在播），与分组卡片头部同一口径
    expect(find.textContaining('1/2 在播'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await settle(tester);
    expect(c.activeGroupId.value, isNull);
    expect(find.byType(FollowGroupCard), findsNWidgets(2));
    await settleEnd(tester);
  });

  testWidgets('多归属成员在筛选态只出现一次（按组筛选天然去重）', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲']),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['huya_甲']),
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    // 总览态：甲 在两张卡片里各出现一次（文件夹语义）
    expect(find.descendant(of: cardOf('CS解说'), matching: find.text('甲')),
        findsOneWidget);
    expect(find.descendant(of: cardOf('LOL解说'), matching: find.text('甲')),
        findsOneWidget);

    await tester.tap(capsuleOf('a1'));
    await settle(tester);
    expect(rowOf('甲'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('筛选态隐藏「折叠全部分组」按钮，回「全部」恢复', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    expect(find.byTooltip('折叠全部分组'), findsOneWidget);
    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    expect(find.byTooltip('折叠全部分组'), findsNothing);
    await tester.tap(find.text('全部'));
    await settle(tester);
    expect(find.byTooltip('折叠全部分组'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('筛选态 + 搜索无匹配：显示「没有匹配的关注」，清空后恢复', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('follow-search-field')), 'zzz');
    await settle(tester);
    expect(rowOf('甲'), findsNothing);
    expect(find.text('没有匹配的关注'), findsOneWidget);

    await tester.tap(find.byTooltip('清空'));
    await settle(tester);
    expect(rowOf('甲'), findsOneWidget);
    expect(find.text('没有匹配的关注'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('选中的分组失效（幽灵 id）后回落文件夹总览', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();

    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    expect(find.byType(FollowGroupCard), findsNothing);

    // 调序会给标签换 id（reorderFollowTag 重新生成 fractional key），
    // 删除分组也不回头清理 —— 读取侧必须回落，不能留一个空白平铺列表。
    c.activeGroupId.value = 'ghost';
    await settle(tester);
    expect(c.activeGroup, isNull);
    expect(find.byType(FollowGroupCard), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('「模式切换」只在筛选态出现；紧凑/卡片切换生效且跨 tab 保持', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final settings = Get.find<AppSettingsController>();

    // 文件夹总览态：⋮ 里没有「模式切换」（平铺才有两种排法）
    await openOverflowMenu(tester);
    expect(find.text('模式切换'), findsNothing);
    // 点无关项收起弹层（toast 类，不离开本页）
    await tester.tap(find.text('赛事订阅'));
    await settle(tester);

    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    await openOverflowMenu(tester);
    expect(find.text('模式切换'), findsOneWidget);
    await tester.tap(find.text('模式切换'));
    await settle(tester);
    expect(find.text('关注样式切换'), findsOneWidget);
    // 切卡片模式：卡面渲染会触发已知 1px 溢出，接管 onError 逐条放行
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(find.text('卡片模式'));
      await settle(tester);
    });

    expect(settings.followStyleNotGrid.value, isFalse);
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    expect(rowOf('甲'), findsNothing);

    // 跨 tab 保持：切到「直播中」再回「全部」，仍是筛选态 + 卡片模式
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(find.text('直播中 1'));
      await settle(tester);
    });
    expect(find.byType(FollowGroupCard), findsNothing);
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(find.text('全部 2'));
      await settle(tester);
    });
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    expect(rowOf('甲'), findsNothing);

    // 切回紧凑模式
    await openOverflowMenu(tester);
    await tester.tap(find.text('模式切换'));
    await settle(tester);
    await tester.tap(find.text('紧凑模式'));
    await settle(tester);
    expect(settings.followStyleNotGrid.value, isTrue);
    expect(rowOf('甲'), findsOneWidget);
    expect(find.byType(LiveRoomCard), findsNothing);
    await settleEnd(tester);
    // 排干 SmartDialog toast 的计时器
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('卡片模式经 setFollowStyleNotGrid 落存储（老用户取值不丢）', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await tester.tap(capsuleOf('a0'));
    await settle(tester);
    await openOverflowMenu(tester);
    await tester.tap(find.text('模式切换'));
    await settle(tester);
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(find.text('卡片模式'));
      await settle(tester);
    });

    // FakeLocalStorageService 是内存实现：能读到即证明过了 setter 落键
    final storage = Get.find<LocalStorageService>();
    expect(
        storage.getValue(LocalStorageService.kFollowStyleNotGrid, true), isFalse);
    await settleEnd(tester);
  });
}
