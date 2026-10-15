// 「全部」视图分组胶囊筛选的 widget 测试：
// 胶囊行出现条件、点胶囊=平铺该组成员、多归属去重、折叠全部按钮让位、
// 筛选态搜索无匹配的空态浮层。
import 'package:flutter/material.dart' show Icons, Key, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
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
}
