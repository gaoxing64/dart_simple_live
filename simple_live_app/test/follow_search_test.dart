// 关注页顶栏搜索：图标 → 原位展开胶囊 → ← 收起并清空关键词。
//
// 搜索入口原来是常驻在 tab 上方的一整行胶囊，改成了「点顶栏 🔍 才展开」。
// 这里盯住三件事：折叠态不再占那一行高度、展开即拿到焦点、收起必须把关键词
// 一起清掉（否则输入框没了却还在过滤，用户没有取消的地方）。
import 'package:flutter/material.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// ⚠️ 本应用跑在 material_ui 上，它有自己的 `TextField` 实现 —— 这里必须用它，
// 换成 `package:flutter/material.dart` 的 TextField，`find.byType` 永远匹配不上，
// 断言会「沉默地恒真」。
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
    );

Future<void> seedSearch(WidgetTester tester) async {
  final svc = FakeFollowService(
    users: [_u('甲'), _u('乙'), _u('丙')],
    tags: [],
  );
  final indexed = await pumpIndexed(tester, followService: svc);
  await gotoFollowPage(tester, indexed);
  await settle(tester);
}

Finder searchField = find.byKey(const Key('follow-search-field'));

/// 成员行里的名字。搜索框里有字时 `find.text(名字)` 会连输入框一起命中，
/// 所以一律限定在 [FollowMemberRow] 里找。
Finder rowText(String name) => find.descendant(
    of: find.byType(FollowMemberRow), matching: find.text(name));

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('折叠态：顶栏只有搜索图标，页面里没有常驻输入框', (tester) async {
    await seedSearch(tester);

    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(searchField, findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(rowText('甲'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('点搜索图标：原位展开胶囊并拿到焦点', (tester) async {
    await seedSearch(tester);

    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);

    expect(searchField, findsOneWidget);
    // 正向对照：确认 byType 用的确实是 material_ui 的 TextField 类型
    //（否则上面/下面那两条 findsNothing 会恒真）
    expect(find.byType(TextField), findsOneWidget);
    // `autofocus` 生效 = 输入法已经拉起（点图标就是要直接打字，不再多点一下框）
    expect(tester.testTextInput.isVisible, isTrue);
    // 展开时右侧整排图标让位，只留 ← 与输入框
    expect(find.byTooltip('收起搜索'), findsOneWidget);
    expect(find.byTooltip('排序方式'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('输入即过滤；点 ← 收起并把关键词一起清掉', (tester) async {
    await seedSearch(tester);
    final c = Get.find<FollowUserController>();

    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    await tester.enterText(searchField, '甲');
    await settle(tester);

    expect(c.searchQuery.value, '甲');
    expect(rowText('甲'), findsOneWidget);
    expect(rowText('乙'), findsNothing);

    await tester.tap(find.byTooltip('收起搜索'));
    await settle(tester);

    expect(searchField, findsNothing);
    expect(c.searchExpanded.value, isFalse);
    expect(c.searchQuery.value, isEmpty);
    // 列表回到全量
    expect(rowText('乙'), findsOneWidget);
    expect(rowText('丙'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('胶囊右侧 ✕ 只清字、不收起', (tester) async {
    await seedSearch(tester);
    final c = Get.find<FollowUserController>();

    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    await tester.enterText(searchField, '甲');
    await settle(tester);

    await tester.tap(find.byTooltip('清空'));
    await settle(tester);

    expect(c.searchExpanded.value, isTrue);
    expect(c.searchQuery.value, isEmpty);
    expect(rowText('乙'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('选择态不给搜索入口（leading 已是退出选择的 ✕）',
      (tester) async {
    await seedSearch(tester);

    await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('甲'), matching: find.byType(FollowMemberRow)),
        matching: find.byType(NetImage)));
    await settle(tester);

    expect(find.text('已选择 1 位'), findsOneWidget);
    expect(find.byTooltip('搜索'), findsNothing);
    await settleEnd(tester);
  });
}
