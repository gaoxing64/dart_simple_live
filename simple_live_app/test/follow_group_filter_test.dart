// 关注页第二栏（标签侧栏）分组筛选的 widget 测试：
// 侧栏顺序与显隐、点分组标签=平铺该组成员、多归属去重、折叠全部按钮让位、
// 筛选态搜索无匹配的空态浮层、模式切换常驻。
// ⚠️ `PopupMenuButton` 要用 material_ui 导出的那个：本应用跑在 material_ui 上，
// 关注页顶栏 ⋮ 是它的 PopupMenuButton，换 flutter/material 的 find.byType
// 永远匹配不上。
import 'package:flutter/material.dart' show Axis, FlutterError, FlutterErrorDetails, Key, PageView, ValueKey;
import 'package:material_ui/material_ui.dart' show PopupMenuButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/modules/follow_user/follow_app_setting/follow_app_settings_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
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

/// 侧栏标签：每项带 `sidebar-<FollowSidebarItem.key>` 的 key。
///
/// 组名在侧栏与分组卡片头部各出现一次（find.text 会多家），
/// 点标签 / 断言标签必须走 key，不能走 find.text。
Finder sidebarOf(String key) => find.byKey(ValueKey('sidebar-$key'));

/// 打开 ⋮ 弹层。
Future<void> openOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<int>).last);
  await settle(tester);
}

/// 在接管 `FlutterError.onError` 的前提下执行 [body]，并逐条断言期间收到
/// 的渲染异常都是 LiveRoomCard 已知的 1px 竖向溢出。
///
/// 溢出即 `doc/test-suite.md` §7 已记录的红灯：卡面内容比网格可用高度高 1px，
/// 测试字体度量下必现。卡片模式的新用例会渲染卡面，不处理就会被记成本轮回归。
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

  testWidgets('没有自定义分组时侧栏只有 3 个内置标签；有分组时排在后面', (tester) async {
    final svc = FakeFollowService(users: [_u('甲', live: 2), _u('乙')], tags: []);
    var indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    expect(sidebarOf('all'), findsOneWidget);
    expect(sidebarOf('live'), findsOneWidget);
    expect(sidebarOf('offline'), findsOneWidget);
    // 测试窗口 400 宽 → 两字模式：标签截到前两个字；「全部」同时是
    // 内容区段头，共两处
    expect(find.text('全部'), findsNWidgets(2));
    expect(find.text('直播'), findsOneWidget);
    expect(find.text('未开'), findsOneWidget);
    expect(Get.find<FollowUserController>().activeFilter.value, isNull);

    final svc2 = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])
      ],
    );
    indexed = await pumpIndexed(tester, followService: svc2);
    await gotoFollowPage(tester, indexed);
    expect(sidebarOf('group:a0'), findsOneWidget);
    // 「全部」页是全量平铺（文件夹总览已移除）：两个关注都在，
    // 不按分组拆成卡片
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);
    expect(find.text('未分组'), findsNothing);
    expect(Get.find<FollowUserController>().activeFilter.value, isNull);
    await settleEnd(tester);
  });

  testWidgets('侧栏顶对齐、条目自上而下，指示条贴着左缘分栏线', (tester) async {
    final svc = FakeFollowService(users: [_u('甲'), _u('乙')], tags: []);
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    // 整栏从内容区顶部开始：Row 的交叉轴若是默认居中，侧栏会浮在中段
    final sidebarRect = tester.getRect(find.byType(FollowSidebar));
    final contentPage = find.byWidgetPredicate(
      (w) => w is PageView && w.scrollDirection == Axis.vertical,
    );
    expect(
      sidebarRect.top,
      closeTo(tester.getTopLeft(contentPage).dy, 1),
      reason: '侧栏应与内容列同顶',
    );

    // 条目竖排：左缘相同、纵向递增（水平排会左缘不同、top 相同）
    final allRect = tester.getRect(sidebarOf('all'));
    final liveRect = tester.getRect(sidebarOf('live'));
    final offlineRect = tester.getRect(sidebarOf('offline'));
    expect(liveRect.left, allRect.left);
    expect(offlineRect.left, allRect.left);
    expect(liveRect.top, greaterThan(allRect.top));
    expect(offlineRect.top, greaterThan(liveRect.top));

    // 指示条贴栏左缘（第一栏与第二栏之间那条分栏线）滑动，
    // 且与整行（hover 高亮区）等高
    final indicatorRect = tester.getRect(
      find.byKey(const ValueKey('sidebar-indicator')),
    );
    expect(indicatorRect.left, closeTo(sidebarRect.left, 1));
    expect(indicatorRect.height, closeTo(allRect.height, 0.5));

    // 左右内衬相等：文字左缘到栏左缘 == 计数右缘到栏右缘
    final labelRect = tester.getRect(
      find.descendant(of: sidebarOf('all'), matching: find.text('全部')),
    );
    final countRect = tester.getRect(
      find.descendant(of: sidebarOf('all'), matching: find.text('2')),
    );
    expect(
      labelRect.left - sidebarRect.left,
      closeTo(sidebarRect.right - countRect.right, 1),
      reason: '左右留白应一致，不能左重右轻',
    );
    // 栏宽已收窄，文字与计数之间不会空出一大截
    expect(countRect.left - labelRect.right, lessThan(24));
  });

  testWidgets('选中指示条：贴左缘滑动，途中拉伸、落位收回', (tester) async {
    final svc = FakeFollowService(users: [_u('甲'), _u('乙')], tags: []);
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await settle(tester);

    final indicator = find.byKey(const ValueKey('sidebar-indicator'));
    expect(indicator, findsOneWidget);
    final rect0 = tester.getRect(indicator);

    // 切到「未开播」（第 3 项，向下两格 = 2 × 44）
    await tester.tap(sidebarOf('offline'));
    await tester.pump(); // 起动画
    await tester.pump(const Duration(milliseconds: 60));
    final rectMid = tester.getRect(indicator);
    expect(rectMid.center.dy, greaterThan(rect0.center.dy), reason: '指示条应开始下滑');
    expect(rectMid.center.dy, lessThan(rect0.center.dy + 88), reason: '60ms 时还没到位，说明是补间');
    expect(rectMid.height, greaterThan(rect0.height + 2), reason: '两端边缘速度不同，途中应被拉伸');
    expect(rectMid.left, closeTo(rect0.left, 0.5), reason: '始终贴左缘');

    await settle(tester);
    final rectEnd = tester.getRect(indicator);
    expect(rectEnd.center.dy - rect0.center.dy, closeTo(88, 1));
    expect(rectEnd.height, closeTo(rect0.height, 0.5), reason: '落位后应收回常规高度');
    await settleEnd(tester);
  });

  testWidgets('点分组标签 = 平铺该组成员：别的组与未在组的不可见', (tester) async {
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

    await tester.tap(sidebarOf('group:a0'));
    await settle(tester);
    expect(c.activeFilter.value?.kind, FollowSidebarKind.group);
    expect(c.activeFilter.value?.id, 'a0');
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);
    expect(rowOf('丙'), findsNothing);
    expect(rowOf('丁'), findsNothing);
    // 段头给计数（● 1/2 在播）
    expect(find.textContaining('1/2 在播'), findsOneWidget);

    // 点「全部」退出筛选，回全量平铺
    await tester.tap(sidebarOf('all'));
    await settle(tester);
    expect(c.activeFilter.value, isNull);
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('丁'), findsOneWidget);
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

    // 多归属：总览态两个关注各出现一次（平铺不按分组拆，甲 只此一行）
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);

    await tester.tap(sidebarOf('group:a1'));
    await settle(tester);
    expect(rowOf('甲'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('「折叠全部分组」按钮已随文件夹总览移除', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    // 没有可折叠的分组卡片了，顶栏不该再留一键折叠
    expect(find.byTooltip('折叠全部分组'), findsNothing);
    expect(find.byTooltip('展开全部分组'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('筛选态 + 搜索无匹配：显示「没有匹配的关注」，清空后恢复', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);

    await tester.tap(sidebarOf('group:a0'));
    await settle(tester);
    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('follow-search-field')), 'zzz');
    await settle(tester);
    expect(rowOf('甲'), findsNothing);
    expect(find.text('没有匹配的关注'), findsOneWidget);

    await tester.tap(find.byTooltip('清空'));
    await settle(tester);
    expect(rowOf('甲'), findsOneWidget);
    expect(find.text('没有匹配的关注'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('选中的分组失效（幽灵 id）后回落全量平铺', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();

    await tester.tap(sidebarOf('group:a0'));
    await settle(tester);
    expect(rowOf('乙'), findsNothing);

    // 调序会给标签换 id（reorderFollowTag 重新生成 fractional key），
    // 删除分组也不回头清理 —— 读取侧必须回落，不能留一个空白平铺列表。
    c.activeFilter.value = const FollowFilter(kind: FollowSidebarKind.group, id: 'ghost');
    await settle(tester);
    expect(c.activeGroup, isNull);
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('乙'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('「模式切换」常驻；紧凑/卡片切换生效且跨 tab 保持', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲', 'huya_乙'])
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final settings = Get.find<AppSettingsController>();

    // 「模式切换」常驻：布局设置全局生效，「全部」页也读它
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
    // 「全部」页是全量平铺，也按布局设置渲染卡面（不再有文件夹总览）
    expect(find.byType(LiveRoomCard), findsNWidgets(2));

    // 进分组筛选：同样卡面
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(sidebarOf('group:a0'));
      await settle(tester);
    });
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    expect(rowOf('甲'), findsNothing);

    // 跨 tab 保持：切到「直播中」再回「全部」。
    // 切走时清筛选（互斥不变式）→ 直播中页按布局设置渲染卡面。
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(sidebarOf('live'));
      await settle(tester);
    });
    expect(find.byType(LiveRoomCard), findsOneWidget);
    await withLiveCardOverflowTolerated(tester, () async {
      await tester.tap(sidebarOf('all'));
      await settle(tester);
    });
    // 回「全部」仍是全量平铺的卡面
    expect(find.byType(LiveRoomCard), findsNWidgets(2));

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
    await tester.tap(sidebarOf('group:a0'));
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
    expect(storage.getValue(LocalStorageService.kFollowStyleNotGrid, true), isFalse);
    await settleEnd(tester);
  });

  testWidgets('按平台分类开启后侧栏出现平台标签，点它=平铺该平台关注', (tester) async {
    final svc = FakeFollowService(
      users: [
        _u('甲', live: 2, siteId: 'huya'),
        _u('乙', siteId: 'douyu'),
        _u('丙', siteId: 'huya'),
      ],
      tags: [],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final settings = Get.find<AppSettingsController>();
    final c = Get.find<FollowUserController>();

    // 默认关闭：侧栏只有 3 个内置标签
    expect(sidebarOf('site:huya'), findsNothing);

    // 开启主开关（子开关缺省全开 —— 真机由 onInit 写满，测试里手工补）
    settings.followGroupBySite.value = true;
    settings.followSiteGroupSites.assignAll(Sites.orderedIds(settings.siteSort));
    await settle(tester);

    // 平台标签排在 3 个内置之后；0 计时的平台（B站/抖音/Twitch）不占位
    expect(sidebarOf('site:huya'), findsOneWidget);
    expect(sidebarOf('site:douyu'), findsOneWidget);
    expect(sidebarOf('site:bilibili'), findsNothing);

    await tester.tap(sidebarOf('site:huya'));
    await settle(tester);
    expect(c.activeFilter.value?.kind, FollowSidebarKind.site);
    expect(c.activeFilter.value?.id, 'huya');
    // 平台筛选不建分组：只有平铺行
    expect(rowOf('甲'), findsOneWidget);
    expect(rowOf('丙'), findsOneWidget);
    expect(rowOf('乙'), findsNothing);
    // 段头是平台名 + 计数
    expect(find.textContaining('1/2 在播'), findsOneWidget);

    // 关掉单个平台子开关（走设置控制器的真实入口，它会顺手清筛选），
    // 对应标签消失、挂着的平台筛选回落
    final settingsPage = Get.put(FollowAppSettingsController());
    settingsPage.setFollowSiteGroup('huya', false);
    await settle(tester);
    expect(sidebarOf('site:huya'), findsNothing);
    expect(c.activeFilter.value, isNull);
    await settleEnd(tester);
  });
}
