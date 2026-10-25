// 关注页分组胶囊：GroupBadge 本身 + 卡面 / 紧凑行的接线与手势透传。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/widgets/group_badge.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, {int live = 1, String siteId = 'huya'}) => FollowUser(
      id: '${siteId}_$name',
      roomId: 'r-$name',
      siteId: siteId,
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = live;

Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

/// 放行 LiveRoomCard 在固定 168dp 网格里已知的 1px 竖向溢出；其他异常照常炸。
Future<void> _withCardOverflowTolerated(Future<void> Function() body) async {
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

Future<void> _pumpBadge(
  WidgetTester tester,
  Widget badge, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(child: badge),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => Get.testMode = true);

  group('GroupBadge', () {
    testWidgets('单组只显示组名，没有 +N', (tester) async {
      await _pumpBadge(tester, const GroupBadge(names: ['CS解说']));
      expect(find.text('CS解说'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      // 胶囊内不再搭配文件夹等图标。
      expect(
        find.descendant(of: find.byType(GroupBadge), matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('多组显示第一个 + 剩余数量', (tester) async {
      await _pumpBadge(tester, const GroupBadge(names: ['CS解说', 'LOL解说', '手游']));
      expect(find.text('CS解说'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('空表 / 全空白名不渲染内容', (tester) async {
      await _pumpBadge(tester, const GroupBadge(names: []));
      expect(tester.getSize(find.byType(GroupBadge)).width, 0);
      await _pumpBadge(tester, const GroupBadge(names: [' ', '  ']));
      expect(tester.getSize(find.byType(GroupBadge)).width, 0);
    });

    testWidgets('长组名省略，但 +N 始终留在胶囊里', (tester) async {
      await _pumpBadge(
        tester,
        const SizedBox(
          width: 96,
          child: GroupBadge(names: ['这是一个非常非常长的分组名称', 'LOL解说'], maxWidth: 96),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('+1'), findsOneWidget);
      expect(tester.getSize(find.text('这是一个非常非常长的分组名称')).width, lessThan(96));

      // 2× 字号下仍不撑破 96dp
      await _pumpBadge(
        tester,
        const SizedBox(
          width: 96,
          child: GroupBadge(names: ['这是一个非常非常长的分组名称', 'LOL解说'], maxWidth: 96),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('胶囊内没有点击 / 长按识别器', (tester) async {
      await _pumpBadge(tester, const GroupBadge(names: ['CS解说']));
      final badge = find.byType(GroupBadge);
      expect(find.descendant(of: badge, matching: find.byType(InkWell)), findsNothing);
      expect(find.descendant(of: badge, matching: find.byType(GestureDetector)), findsNothing);
      expect(find.descendant(of: badge, matching: find.byType(Tooltip)), findsNothing);
    });
  });

  group('关注页内容项分组胶囊', () {
    FakeFollowService seed() => FakeFollowService(
          users: [_u('甲', live: 2), _u('乙'), _u('丁')],
          tags: [
            FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙']),
            FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['huya_甲']),
          ],
        );

    testWidgets('紧凑行：进入选择态后全部展示分组；首个分组 +N；长按仍透传', (tester) async {
      final indexed = await pumpIndexed(tester, followService: seed());
      await gotoFollowPage(tester, indexed);
      await settle(tester);

      // 普通浏览态不显示任何分组胶囊。
      expect(find.byType(GroupBadge), findsNothing);

      final c = Get.find<FollowUserController>();
      // 只选中甲：乙本身未被选中，但已进入选择态，也要显示自己的分组。
      c.toggleSelected('huya_甲');
      await settle(tester);

      final jiaBadge = find.descendant(of: rowOf('甲'), matching: find.byType(GroupBadge));
      expect(jiaBadge, findsOneWidget);
      expect(find.descendant(of: jiaBadge, matching: find.text('CS解说')), findsOneWidget);
      expect(find.descendant(of: jiaBadge, matching: find.text('+1')), findsOneWidget);
      // 主播名仍在，且胶囊紧跟在名字右侧（不是被推到行尾）
      final nameRect = tester.getRect(
        find.descendant(of: rowOf('甲'), matching: find.text('甲')),
      );
      expect(find.descendant(of: rowOf('甲'), matching: find.text('甲')), findsOneWidget);
      expect(tester.getRect(jiaBadge).left, closeTo(nameRect.right + 8, 1.5));

      final yiBadge = find.descendant(of: rowOf('乙'), matching: find.byType(GroupBadge));
      expect(yiBadge, findsOneWidget);
      expect(find.descendant(of: yiBadge, matching: find.text('CS解说')), findsOneWidget);
      expect(find.descendant(of: yiBadge, matching: find.text('+1')), findsNothing);
      expect(
        find.descendant(of: rowOf('丁'), matching: find.byType(GroupBadge)),
        findsNothing,
      );

      // 直播中行同样提供快速取关，不能只在未开播行出现。
      expect(
        find.descendant(of: rowOf('甲'), matching: find.byTooltip('取消关注')),
        findsOneWidget,
      );

      // 胶囊在取消关注按钮左侧（乙是未开播行，有行尾按钮）
      final remove = find.descendant(of: rowOf('乙'), matching: find.byTooltip('取消关注'));
      expect(remove, findsOneWidget);
      expect(tester.getRect(yiBadge).right, lessThan(tester.getRect(remove).left));

      // 长按胶囊所在位置 = 长按整行（胶囊是 IgnorePointer），底部菜单照常出现
      await tester.longPressAt(tester.getCenter(jiaBadge));
      await settle(tester);
      expect(find.byTooltip('设置分组'), findsOneWidget);
      Get.back();
      await settle(tester);
      await settleEnd(tester);
    });

    testWidgets('卡片模式：进入选择态后全部展示封面左上角胶囊', (tester) async {
      final indexed = await pumpIndexed(tester, followService: seed());
      Get.find<AppSettingsController>().setFollowStyleNotGrid(false);
      await _withCardOverflowTolerated(() async {
        await gotoFollowPage(tester, indexed);
        await settle(tester);
      });

      final cardFinder = find.byType(LiveRoomCard);
      var cards = tester.widgetList<LiveRoomCard>(cardFinder).toList();
      expect(cards, hasLength(3));
      // 普通浏览态：所有卡片都不传分组，避免遮挡封面。
      expect(cards.every((card) => card.groupNames.isEmpty), isTrue);
      expect(find.byType(GroupBadge), findsNothing);

      Get.find<FollowUserController>().toggleSelected('huya_甲');
      await settle(tester);

      cards = tester.widgetList<LiveRoomCard>(cardFinder).toList();
      final jiaIndex = cards.indexWhere((c) => c.item.userName == '甲');
      final yiIndex = cards.indexWhere((c) => c.item.userName == '乙');
      final dingIndex = cards.indexWhere((c) => c.item.userName == '丁');
      expect(cards[jiaIndex].groupNames, ['CS解说', 'LOL解说']);
      // 乙未被选中，但选择态下也要显示自己的分组，供批量比较。
      expect(cards[yiIndex].groupNames, ['CS解说']);
      expect(cards[dingIndex].groupNames, isEmpty);

      final jiaCard = cardFinder.at(jiaIndex);
      final jiaBadge = find.descendant(of: jiaCard, matching: find.byType(GroupBadge));
      expect(jiaBadge, findsOneWidget);
      final cardRect = tester.getRect(jiaCard);
      final badgeRect = tester.getRect(jiaBadge);
      // Stack 内偏移 6；卡片外框自身有约 2dp 内缩，相对外框落在 4~10 之间。
      expect(badgeRect.left - cardRect.left, inInclusiveRange(4, 10));
      expect(badgeRect.top - cardRect.top, inInclusiveRange(4, 10));
      expect(badgeRect.bottom, lessThan(cardRect.top + 110));
      expect(cardRect.height, closeTo(PageGridView.kDefaultItemExtent, 0.5));
      expect(
        find.descendant(of: cardFinder.at(yiIndex), matching: find.byType(GroupBadge)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cardFinder.at(dingIndex), matching: find.byType(GroupBadge)),
        findsNothing,
      );
      await settleEnd(tester);
    });

    testWidgets('成员 / 改名变化后胶囊跟着更新', (tester) async {
      final svc = seed();
      final indexed = await pumpIndexed(tester, followService: svc);
      await gotoFollowPage(tester, indexed);
      await settle(tester);
      final c = Get.find<FollowUserController>();
      c.toggleSelected('huya_丁');
      c.toggleSelected('huya_甲');
      await settle(tester);

      expect(
        find.descendant(of: rowOf('丁'), matching: find.byType(GroupBadge)),
        findsNothing,
      );
      final ding = svc.followList.firstWhere((u) => u.userName == '丁');
      await svc.addUserToTag(ding, 'CS解说');
      c.updateTagList();
      c.filterData();
      await settle(tester);
      expect(
        find.descendant(of: rowOf('丁'), matching: find.byType(GroupBadge)),
        findsOneWidget,
      );

      svc.followTagList[0] = svc.followTagList[0].copyWith(tag: '改名组');
      c.updateTagList();
      c.filterData();
      await settle(tester);
      final dingBadge = find.descendant(of: rowOf('丁'), matching: find.byType(GroupBadge));
      expect(find.descendant(of: dingBadge, matching: find.text('改名组')), findsOneWidget);

      final jia = svc.followList.firstWhere((u) => u.userName == '甲');
      await svc.removeUserFromTag(jia, '改名组');
      c.updateTagList();
      c.filterData();
      await settle(tester);
      final jiaBadge = find.descendant(of: rowOf('甲'), matching: find.byType(GroupBadge));
      expect(find.descendant(of: jiaBadge, matching: find.text('LOL解说')), findsOneWidget);
      expect(find.descendant(of: jiaBadge, matching: find.text('+1')), findsNothing);
      await settleEnd(tester);
    });
  });
}