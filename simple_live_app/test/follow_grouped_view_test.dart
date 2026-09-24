// 「全部」分组文件夹视图的 widget 测试：
// 分组卡片渲染 / 计数 pill / 折叠，拖头像换组，拖头部把手调序，视图切换。
//
// 假数据源用 `follow_test_harness.dart` 的 FakeFollowService：
// setFollowTag / reorderFollowTag 是内存实现（真实现经 DBService 写 Hive，
// widget test 里没注册 DBService）。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart'
    show Icons, Key, MediaQuery, SingleChildScrollView;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_group_card.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_quick_group_sheet.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, {String tag = '全部', int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
      tag: tag,
    )..liveStatus.value = live;

Future<FakeFollowService> seedGrouped(WidgetTester tester) async {
  final svc = FakeFollowService(
    users: [
      _u('甲', tag: 'CS解说', live: 2),
      _u('乙', tag: 'CS解说'),
      _u('丙', tag: 'LOL解说'),
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

Finder cardOf(String tag) =>
    find.ancestor(of: find.text(tag), matching: find.byType(FollowGroupCard));

Finder rowOf(String name) => find
    .ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('每个标签一张卡片：直播/总数文案 + 成员行；未分组列在下方', (tester) async {
    await seedGrouped(tester);

    expect(find.byType(FollowGroupCard), findsNWidgets(2));
    expect(find.descendant(of: cardOf('CS解说'), matching: find.text('甲')),
        findsOneWidget);
    expect(find.descendant(of: cardOf('CS解说'), matching: find.text('乙')),
        findsOneWidget);
    // CS解说 = `● 1/2 在播`；LOL解说 无人直播 = `0/1 在播`（不带圆点）
    expect(
        find.descendant(
            of: cardOf('CS解说'), matching: find.textContaining('1/2 在播')),
        findsOneWidget);
    expect(
        find.descendant(
            of: cardOf('CS解说'), matching: find.textContaining('●')),
        findsOneWidget);
    expect(
        find.descendant(
            of: cardOf('LOL解说'), matching: find.textContaining('●')),
        findsNothing);
    expect(
        find.descendant(
            of: cardOf('LOL解说'), matching: find.textContaining('0/1 在播')),
        findsOneWidget);
    // 未分组段：丁 + 右对齐的拖出提示
    expect(rowOf('丁'), findsOneWidget);
    expect(find.textContaining('拖到这里移出分组'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('点卡片头部折叠/展开：成员隐藏、头像堆叠出现、折叠态记在控制器', (tester) async {
    await seedGrouped(tester);
    final c = Get.find<FollowUserController>();

    await tester.tap(find.text('CS解说'));
    await settle(tester);
    expect(c.collapsedGroups.contains('a0'), isTrue);
    expect(
        find.descendant(of: cardOf('CS解说'), matching: find.text('甲')),
        findsNothing);
    // 折叠态不再在组名后摆成员头像堆叠（三枚圆片会把组名挤成省略号）
    expect(
        find.descendant(of: cardOf('CS解说'), matching: find.byType(NetImage)),
        findsNothing);
    // 另一张卡片不受影响
    expect(
        find.descendant(of: cardOf('LOL解说'), matching: find.text('丙')),
        findsOneWidget);

    await tester.tap(find.text('CS解说'));
    await settle(tester);
    expect(c.collapsedGroups.contains('a0'), isFalse);
    expect(
        find.descendant(of: cardOf('CS解说'), matching: find.text('甲')),
        findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('卡片头部：去掉 ⋮ 菜单，改右侧拖拽把手 + 右键重命名', (tester) async {
    await seedGrouped(tester);

    // ⋮「分组操作」菜单已移除（重命名走右键/长按，删除与分组管理走右上角）
    expect(
        find.descendant(
            of: cardOf('CS解说'), matching: find.byIcon(Icons.more_vert)),
        findsNothing);
    // 右侧出现专用拖拽把手（与「主页排序」同款）
    expect(
        find.descendant(
            of: cardOf('CS解说'), matching: find.byIcon(Icons.drag_handle)),
        findsOneWidget);

    // 桌面端右键头部 = 重命名对话框
    await tester.tap(find.text('CS解说'), buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text('重命名分组'), findsOneWidget);
    await tester.tap(find.text('否'));
    await settle(tester);
    await settleEnd(tester);
  });

  testWidgets('键盘抬起时弹重命名：面板不被键盘高度撑大', (tester) async {
    // `Get.dialog` 的路由已经把 AlertDialog 摆在键盘上方，弹窗内容里若再垫一次
    // `viewInsets.bottom`，搜索态（键盘抬起）下长按分组弹重命名时面板会被撑到
    // 几乎占满键盘上方整屏（移动端实测）。
    await seedGrouped(tester);
    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    tester.view.viewInsets =
        FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await settle(tester);

    await tester.longPress(find.text('CS解说'));
    await settle(tester);

    expect(find.text('重命名分组'), findsOneWidget);
    // 弹窗标题在滚动容器里，从它往上找容器（不依赖 AlertDialog 的具体类型，
    // material_ui 有自己的实现）。
    final scroll = find
        .ancestor(
            of: find.text('重命名分组'),
            matching: find.byType(SingleChildScrollView))
        .first;
    // 内容本身约 120 高；把键盘高度算两遍的话这里会是 ~420
    expect(tester.getSize(scroll).height, lessThan(200));
    tester.view.viewInsets = FakeViewPadding.zero;
    await settleEnd(tester);
  });

  testWidgets('未分组段头可折叠，折叠后成员行隐藏', (tester) async {
    await seedGrouped(tester);
    final c = Get.find<FollowUserController>();

    await tester.tap(find.text('未分组'));
    await settle(tester);
    expect(c.collapsedGroups.contains('ungrouped'), isTrue);
    expect(rowOf('丁'), findsNothing);

    await tester.tap(find.text('未分组'));
    await settle(tester);
    expect(c.collapsedGroups.contains('ungrouped'), isFalse);
    expect(rowOf('丁'), findsOneWidget);
    await settleEnd(tester);
  });

  testWidgets('长按头像拖到别的分组卡片 = 换组；行体长按菜单不误弹', (tester) async {
    final svc = await seedGrouped(tester);

    // 未分组行贴着页面底部，会被悬浮底栏盖住 —— 先滚进视口中部再拖
    //（真实用户同理：拖之前先滚到看得见的位置）。起点选在卡片主体
    // （GridView 不滚、pan 会传给外层列表），不能选 PageGridView 中心
    // 或行本身 —— 前者可能压在卡片头部调序把手上，后者在底栏下面。
    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);

    final avatar =
        find.descendant(of: rowOf('丁'), matching: find.byType(NetImage));
    final gesture = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // > kLongPressTimeout
    await gesture.moveTo(tester.getCenter(cardOf('LOL解说')));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    final user = svc.followList.firstWhere((u) => u.userName == '丁');
    expect(user.tag, 'LOL解说');
    expect(
        find.descendant(of: cardOf('LOL解说'), matching: find.text('丁')),
        findsOneWidget);
    // 未分组清空后，段头仍在（它还是「拖出分组」的落点）
    expect(find.textContaining('拖到这里移出分组'), findsOneWidget);
    // 拖拽没有顺带弹出长按菜单（设置分组）
    expect(find.text('设置分组'), findsNothing);
    await settleEnd(tester);
  });

  testWidgets('把成员从分组拖到未分组的行上 = 移出分组（整块都是落点）',
      (tester) async {
    final svc = await seedGrouped(tester);

    // 滚到未分组行进入视口（贴近底部会被悬浮底栏挡住，同换组用例的理由）
    await tester.dragFrom(const Offset(200, 560), const Offset(0, -160));
    await settle(tester);

    // 丙 在 LOL解说 卡片里，长按其头像拖到未分组的「丁」行上（不是段头）
    final srcAvatar =
        find.descendant(of: rowOf('丙'), matching: find.byType(NetImage));
    final gesture = await tester.startGesture(tester.getCenter(srcAvatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // > kLongPressTimeout
    await gesture.moveTo(tester.getCenter(rowOf('丁')));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(svc.followList.firstWhere((u) => u.userName == '丙').tag, '全部',
        reason: '拖到未分组成员行上也要能移出分组（落点应覆盖整块，不只是段头）');
    await settleEnd(tester);
  });

  testWidgets('拖右侧把手调序分组卡片（onReorderItem 的索引已校正，不再 -1）', (tester) async {
    await seedGrouped(tester);
    final c = Get.find<FollowUserController>();
    expect(c.customTags.map((t) => t.tag), ['CS解说', 'LOL解说']);

    // 把手 = 头部右侧的拖拽图标（整条头部不再可拖，避免与滑动抢手势）
    final start = tester.getCenter(find.descendant(
        of: cardOf('CS解说'), matching: find.byIcon(Icons.drag_handle)));
    final h0 = tester.getSize(cardOf('CS解说')).height;
    final h1 = tester.getSize(cardOf('LOL解说')).height;
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30)); // 超过 slop，进入拖拽
    await tester.pump();
    // 拖过第二张卡片的下半部分，插入索引才会落到它后面
    await gesture.moveBy(Offset(0, h0 + h1));
    await tester.pump();
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(c.customTags.map((t) => t.tag), ['LOL解说', 'CS解说']);
    await settleEnd(tester);
  });

  testWidgets('勾选→编辑：顶栏选择态 + 新建分组批量移入', (tester) async {
    final svc = await seedGrouped(tester);
    final c = Get.find<FollowUserController>();

    // 滚进视口中部（同拖拽换组用例的理由）
    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);

    // 勾选丁（未分组）→ 顶栏进入选择态
    await tester.tap(
        find.descendant(of: rowOf('丁'), matching: find.byType(NetImage)));
    await settle(tester);
    expect(c.selectedIds.contains('huya_丁'), isTrue);
    expect(find.text('已选择 1 位'), findsOneWidget);
    // 未分组段头追加已选数（`· 已选 X`）
    expect(find.textContaining('在播 · 已选 1'), findsOneWidget);
    // 「点击头像勾选」讲解条已删：勾选态一看便知，不值得占一条横幅
    expect(find.textContaining('点击头像勾选主播'), findsNothing);

    // 再勾选乙（CS解说组内）→ 跨组累积
    await tester.tap(
        find.descendant(of: rowOf('乙'), matching: find.byType(NetImage)));
    await settle(tester);
    expect(find.text('已选择 2 位'), findsOneWidget);
    expect(find.textContaining('在播 · 已选 1'), findsNWidgets(2));

    // 滚回顶部让收起的顶栏展开，再点「编辑」
    await tester.dragFrom(const Offset(200, 400), const Offset(0, 300));
    await settle(tester);
    // 编辑 → 弹窗填名字 → 创建分组
    await tester.tap(find.text('编辑'));
    await settle(tester);
    expect(find.text('分组名称'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('quick-group-name-field')),
      '新观赛组',
    );
    await tester.tap(find.text('创建分组'));
    await settle(tester);

    expect(svc.followList.firstWhere((u) => u.userName == '丁').tag, '新观赛组');
    expect(svc.followList.firstWhere((u) => u.userName == '乙').tag, '新观赛组');
    expect(c.selectedIds, isEmpty);
    expect(find.text('已选择 1 位'), findsNothing);
    expect(find.text('新观赛组'), findsOneWidget);
    await settleEnd(tester);
    // 排干 SmartDialog toast 的计时器
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('编辑弹窗：移入已有分组', (tester) async {
    final svc = await seedGrouped(tester);

    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);
    await tester.tap(
        find.descendant(of: rowOf('丁'), matching: find.byType(NetImage)));
    await settle(tester);
    // 滚回顶部让收起的顶栏展开
    await tester.dragFrom(const Offset(200, 400), const Offset(0, 300));
    await settle(tester);
    await tester.tap(find.text('编辑'));
    await settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(FollowQuickGroupSheet), matching: find.text('LOL解说')));
    await settle(tester);

    expect(svc.followList.firstWhere((u) => u.userName == '丁').tag, 'LOL解说');
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('编辑弹窗：键盘弹起不得把表单挤出 sheet 可见区', (tester) async {
    // `Get.bottomSheet` 的路由自己就按 `viewInsets.bottom` 把 sheet 抬起来了，
    // 表单里不能再抬一次；再叠上 get 默认那条 9/16 高度硬夹，移动端一点输入法
    // 整张表单就被裁到盒子外面（用户实测：只剩一块空白面板）。
    await seedGrouped(tester);
    await tester.dragFrom(const Offset(200, 560), const Offset(0, -200));
    await settle(tester);
    await tester.tap(
        find.descendant(of: rowOf('丁'), matching: find.byType(NetImage)));
    await settle(tester);
    await tester.dragFrom(const Offset(200, 400), const Offset(0, 300));
    await settle(tester);
    await tester.tap(find.text('编辑'));
    await settle(tester);

    tester.view.viewInsets =
        FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await settle(tester);

    final sheet = find.byType(FollowQuickGroupSheet);
    final box = tester.getRect(sheet);
    final createBtn = tester.getRect(find.descendant(
        of: sheet, matching: find.text('创建分组')));
    expect(box.bottom, closeTo(500, 1),
        reason: 'sheet 底边应正好贴在键盘上沿（800 视口 - 300 键盘）');
    expect(createBtn.bottom, lessThanOrEqualTo(box.bottom),
        reason: '表单尾部必须留在 sheet 盒子内，否则会被圆角 Material 裁掉');
    expect(tester.takeException(), isNull);

    // 更极端的键盘（400/800）+ 分组多到换行：表单要能滚、操作行必须还够得着
    tester.view.viewInsets =
        FakeViewPadding(bottom: 400 * tester.view.devicePixelRatio);
    await settle(tester);
    final box2 = tester.getRect(sheet);
    final createBtn2 = tester.getRect(find.descendant(
        of: sheet, matching: find.text('创建分组')));
    expect(createBtn2.bottom, lessThanOrEqualTo(box2.bottom),
        reason: '极端挤压下「创建分组」被挤出去就再也点不到了');
    expect(tester.getSize(find.ancestor(
            of: find.text('分组名称'),
            matching: find.byType(SingleChildScrollView)).first).height,
        lessThan(313),
        reason: '表单本体应为了让出空间而收缩（可滚），不是把盒子撑爆');
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await settleEnd(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('鼠标滚轮：悬停在分组卡片上也必须能滚动外层列表', (tester) async {
    // 内容要足够长才能滚：3 张卡片 + 一批未分组行，模拟真实关注量
    final svc = FakeFollowService(
      users: [
        for (var g = 0; g < 3; g++) ...[
          _u('组$g·甲', tag: '组$g', live: 2),
          _u('组$g·乙', tag: '组$g'),
        ],
        for (var i = 0; i < 12; i++) _u('散人$i'),
      ],
      tags: [
        FollowUserTag(id: 'a0', tag: '组0', userId: []),
        FollowUserTag(id: 'a1', tag: '组1', userId: []),
        FollowUserTag(id: 'a2', tag: '组2', userId: []),
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    final c = Get.find<FollowUserController>();
    await settle(tester);
    expect(c.scrollController.position.maxScrollExtent, greaterThan(100),
        reason: '内容应足够长、可滚动');

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
    final onCard = await wheelAt(tester.getCenter(find.text('组1')), jumpTo: 0);
    c.scrollController.position.jumpTo(0);
    await settle(tester);
    final onMember = await wheelAt(tester.getCenter(rowOf('组0·乙')));

    // 底部附近（未到底）：滚轮悬停在未分组行上应继续推进。
    // 留 450px 余量：两格各 200px 都必须真实推进，而不是撞到 max 被钳制。
    final pos = c.scrollController.position;
    pos.jumpTo(pos.maxScrollExtent - 450);
    await settle(tester);
    // 懒加载下取当前「已构建且中心在视口内」的最靠下的未分组行
    String? bottomRow;
    Offset? bottomAt;
    final viewH = pos.viewportDimension;
    for (var i = 11; i >= 0; i--) {
      final row = rowOf('散人$i');
      if (row.evaluate().isEmpty) continue;
      final center = tester.getCenter(row);
      if (center.dy > 0 && center.dy < viewH) {
        bottomRow = '散人$i';
        bottomAt = center;
        break;
      }
    }
    expect(bottomRow, isNotNull, reason: '接近底部时应能看到未分组行');
    final onUngrouped = await wheelAt(bottomAt!);
    expect(onCard, greaterThan(0), reason: '滚轮悬停在分组卡片头部不得失效');
    expect(onMember, greaterThan(0), reason: '滚轮悬停在卡片成员行上不得失效');
    expect(onUngrouped, greaterThan(0), reason: '滚轮在未分组区应滚动');
    await settleEnd(tester);
  });

  testWidgets('移动端：分组卡片底部不被底栏安全区撑出空白', (tester) async {
    // 悬浮底栏的高度由 Scaffold 记进 MediaQuery.padding.bottom。卡片里的成员
    // GridView 若不显式给 padding，`ScrollView` 会拿它当默认内边距（ListView /
    // GridView 的自动安全区行为），整张卡片底部就凭空多出一截。
    await seedGrouped(tester);
    final card = cardOf('CS解说');
    final mq = MediaQuery.of(tester.element(card.first));
    expect(mq.padding.bottom, greaterThan(0),
        reason: '前提：本用例要跑在「有底栏安全区」的移动端口径下');

    final cardBottom = tester.getRect(card.first).bottom;
    final lastRowBottom = tester
        .getRect(find.descendant(
            of: card, matching: find.byType(FollowMemberRow)).last)
        .bottom;
    // 成员行之下只剩卡片自己的 8 底部内边距 + 1.5 描边（拖拽高亮框）。
    expect(cardBottom - lastRowBottom, lessThanOrEqualTo(10));
    await settleEnd(tester);
  });

  testWidgets('tab 变视图切换：直播中=卡片网格，未开播=紧凑行', (tester) async {
    await seedGrouped(tester);

    expect(find.byType(FollowGroupCard), findsNWidgets(2));
    expect(find.text('直播中 1'), findsOneWidget);
    expect(find.text('未开播 3'), findsOneWidget);

    await tester.tap(find.text('直播中 1'));
    await settle(tester);
    expect(find.byType(LiveRoomCard), findsOneWidget);
    expect(find.byType(FollowGroupCard), findsNothing);

    await tester.tap(find.text('未开播 3'));
    await settle(tester);
    expect(find.byType(LiveRoomCard), findsNothing);
    expect(rowOf('丙'), findsOneWidget);

    await tester.tap(find.text('全部 4'));
    await settle(tester);
    expect(find.byType(FollowGroupCard), findsNWidgets(2));
    await settleEnd(tester);
  });
}
