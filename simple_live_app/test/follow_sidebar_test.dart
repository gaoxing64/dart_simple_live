// 关注页第二栏（标签侧栏）与「按平台分类」设置的测试：
// 侧栏内容驱动宽度（随标签长短 / 系统字号增长、窄窗两字模式、超长封顶）、
// 标签两端对齐、平台标签显隐与顺序、同名分组静默清理、布局设置读法。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_app_setting/follow_app_settings_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_sidebar.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'follow_test_harness.dart';

FollowSidebarItem _item(FollowSidebarKind kind, String label, int count, {Site? site}) =>
    FollowSidebarItem(
      // 内置项的 key 只取 kind 名；分组 / 平台用 label 当稳定 id。
      kind: kind,
      id: label,
      label: label,
      count: count,
      site: site,
    );

/// 泵一个独立侧栏。测试字体是 Ahem（每个字符宽 = 字号），所以栏宽断言只看
/// 相对变化与上下限，不锚具体像素。
Future<void> _pumpSidebar(
  WidgetTester tester, {
  required List<FollowSidebarItem> items,
  double availableWidth = 1000,
  bool compact = false,
  double textScale = 1,
  String? selectedKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FollowSidebar(
                items: items,
                selectedKey: selectedKey ?? items.first.key,
                onSelect: (_) {},
                availableWidth: availableWidth,
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    // 每个用例后清空注册表：否则后一个用例的 Get.put 会复用前一个用例的
    // 控制器实例（它捕获的是上一个 FakeFollowService），清理就落到错的数据上。
    Get.reset();
  });

  group('FollowSidebar 内容驱动宽度', () {
    final builtins = [
      _item(FollowSidebarKind.all, '全部', 3),
      _item(FollowSidebarKind.live, '直播中', 2),
      _item(FollowSidebarKind.offline, '未开播', 1),
    ];

    testWidgets('常规栏宽由最长标签决定，标签变长时增长', (tester) async {
      await _pumpSidebar(tester, items: builtins);
      final shortWidth = tester.getSize(find.byType(FollowSidebar)).width;
      // 不再是固定的 140：短标签明显更窄
      expect(shortWidth, lessThan(140));
      expect(shortWidth, greaterThan(60));

      final longer = [
        ...builtins,
        _item(FollowSidebarKind.group, 'CS解说', 5),
      ];
      await _pumpSidebar(tester, items: longer);
      final longWidth = tester.getSize(find.byType(FollowSidebar)).width;
      expect(longWidth, greaterThan(shortWidth));
    });

    testWidgets('系统字号变大时栏宽跟着增长', (tester) async {
      await _pumpSidebar(tester, items: builtins);
      final normal = tester.getSize(find.byType(FollowSidebar)).width;
      await _pumpSidebar(tester, items: builtins, textScale: 2);
      final scaled = tester.getSize(find.byType(FollowSidebar)).width;
      expect(scaled, greaterThan(normal));
    });

    testWidgets('窄窗两字模式：栏宽只按两字内容算，平台 icon 与计数都隐藏', (tester) async {
      final items = [
        ...builtins,
        _item(FollowSidebarKind.site, '哔哩哔哩', 4, site: Sites.allSites['bilibili']),
      ];

      await _pumpSidebar(tester, items: items, availableWidth: 400, compact: true);
      final compactWidth = tester.getSize(find.byType(FollowSidebar)).width;
      final siteLabel = find.byKey(const ValueKey('sidebar-label-site:哔哩哔哩'));
      expect(siteLabel, findsOneWidget);
      expect(find.descendant(of: siteLabel, matching: find.text('哔')), findsOneWidget);
      expect(find.descendant(of: siteLabel, matching: find.text('哩')), findsOneWidget);
      expect(find.byIcon(Sites.allSites['bilibili']!.iconData), findsNothing);
      // 计数也收起：只按两字标签量宽
      expect(find.text('4'), findsNothing);
      expect(compactWidth, lessThan(75));

      // 两字标签有完整名提示；恰好两字的「全部」不需要
      final tooltipFinder = find.ancestor(of: siteLabel, matching: find.byType(Tooltip));
      expect(tooltipFinder, findsOneWidget);
      expect(tester.widget<Tooltip>(tooltipFinder).message, '哔哩哔哩');
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('sidebar-label-all')),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );

      // 手机端长按确实能看到完整名
      await tester.longPress(find.byKey(const ValueKey('sidebar-site:哔哩哔哩')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('哔哩哔哩'), findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pump();

      // 读屏也读完整名，而不是「哔哩」。直接检查标签节点里的 Semantics
      // 属性：Tooltip overlay 里也有同名文本，不能拿全局 finder 去数。
      final labelSemantics = find.descendant(
        of: find.byKey(const ValueKey('sidebar-label-site:哔哩哔哩')),
        matching: find.byType(Semantics),
      );
      expect(labelSemantics, findsOneWidget);
      expect(tester.widget<Semantics>(labelSemantics).properties.label, '哔哩哔哩');

      await _pumpSidebar(tester, items: items, availableWidth: 800);
      final normalWidth = tester.getSize(find.byType(FollowSidebar)).width;
      expect(normalWidth, greaterThan(compactWidth));
      expect(find.byIcon(Sites.allSites['bilibili']!.iconData), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('sidebar-label-site:哔哩哔哩')),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
    });

    testWidgets('超长分组名封顶，且给内容列留出最小宽度', (tester) async {
      final long = [
        ...builtins,
        _item(FollowSidebarKind.group, '这是一个非常非常长的分组名称用来测试封顶行为', 1),
      ];
      await _pumpSidebar(tester, items: long);
      expect(
        tester.getSize(find.byType(FollowSidebar)).width,
        closeTo(FollowSidebar.maxWidth, 0.01),
      );

      // 窗口本身很窄时，封顶线让路给内容列
      await _pumpSidebar(tester, items: long, availableWidth: 300);
      expect(
        tester.getSize(find.byType(FollowSidebar)).width,
        closeTo(300 - FollowSidebar.minContentWidth, 0.01),
      );
    });

    testWidgets('左右内衬相等；短标签逐字符撑满标签列（两端对齐）', (tester) async {
      final items = [
        _item(FollowSidebarKind.all, '全部', 3),
        _item(FollowSidebarKind.group, 'CS解说', 5),
      ];
      await _pumpSidebar(tester, items: items);
      final sidebar = tester.getRect(find.byType(FollowSidebar));
      final shortLabel = tester.getRect(find.byKey(const ValueKey('sidebar-label-all')));
      final longLabel = tester.getRect(find.byKey(const ValueKey('sidebar-label-group:CS解说')));
      final firstChar = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('sidebar-all')), matching: find.text('全')),
      );
      final lastChar = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('sidebar-all')), matching: find.text('部')),
      );
      final count = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('sidebar-all')), matching: find.text('3')),
      );

      expect(shortLabel.left - sidebar.left, closeTo(12, 0.01));
      expect(sidebar.right - count.right, closeTo(12, 0.01));
      // 标签列等宽，右缘也对齐
      expect(shortLabel.right, closeTo(longLabel.right, 0.01));
      expect(shortLabel.width, closeTo(longLabel.width, 0.01));
      // 两个字分别贴住标签列左右缘
      expect(firstChar.left, closeTo(shortLabel.left, 0.01));
      expect(lastChar.right, closeTo(shortLabel.right, 0.01));
    });

    testWidgets('极窄窗下栏宽也给内容列留够空间', (tester) async {
      await _pumpSidebar(tester, items: builtins, availableWidth: 360, compact: true);
      final width = tester.getSize(find.byType(FollowSidebar)).width;
      expect(360 - width, greaterThanOrEqualTo(FollowSidebar.minContentWidth));
    });

    test('compactLabel：只留前两个字（按字符簇）', () {
      expect(FollowSidebar.compactLabel('全部'), '全部');
      expect(FollowSidebar.compactLabel('直播中'), '直播');
      expect(FollowSidebar.compactLabel('哔哩哔哩'), '哔哩');
      expect(FollowSidebar.compactLabel('Twitch'), 'Tw');
      // emoji 不拆代理对 / 组合字符
      expect(FollowSidebar.compactLabel('🐱🐶🐭'), '🐱🐶');
    });

    test('窄屏阈值：480 起回到常规模式', () {
      expect(FollowSidebar.isCompact(400), isTrue);
      expect(FollowSidebar.isCompact(360), isTrue);
      expect(FollowSidebar.isCompact(430), isTrue);
      expect(FollowSidebar.isCompact(480), isFalse);
    });
  });

  group('sidebarItems 平台标签', () {
    test('主开关关闭时没有平台项', () {
      final settings = Get.put<AppSettingsController>(FakeSettings());
      Get.put<FollowService>(FakeFollowService(users: [], tags: []));
      final c = FollowUserController();
      c.onInit();
      addTearDown(c.onClose);
      c.list.assignAll([]);

      settings.followGroupBySite.value = false;
      expect(c.sidebarItems.where((i) => i.kind == FollowSidebarKind.site), isEmpty);
    });

    test('开启后按 siteSort 出平台项，0 计数隐藏、关掉的平台隐藏', () {
      final settings = Get.put<AppSettingsController>(FakeSettings());
      final svc = FakeFollowService(
        users: [
          FollowUser(
            id: 'huya_甲',
            roomId: 'r',
            siteId: 'huya',
            userName: '甲',
            face: '',
            addTime: DateTime(2024),
          )..liveStatus.value = 2,
          FollowUser(
            id: 'douyu_乙',
            roomId: 'r',
            siteId: 'douyu',
            userName: '乙',
            face: '',
            addTime: DateTime(2024),
          ),
        ],
        tags: [],
      );
      Get.put<FollowService>(svc);
      final c = FollowUserController();
      c.onInit();
      addTearDown(c.onClose);
      c.list.assignAll(List.of(svc.followList));

      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(Sites.orderedIds(settings.siteSort));
      final siteItems = c.sidebarItems.where((i) => i.kind == FollowSidebarKind.site).toList();
      // B站 / 抖音 / Twitch 没有关注 → 不占位
      expect(siteItems.map((i) => i.label), ['斗鱼直播', '虎牙直播']);

      // 关掉斗鱼 → 对应项消失
      settings.followSiteGroupSites.remove('douyu');
      expect(
        c.sidebarItems.where((i) => i.kind == FollowSidebarKind.site).map((i) => i.label),
        ['虎牙直播'],
      );
    });
  });

  group('cleanupPlatformNamedTags 同名分组清理', () {
    test('只删名称与平台显示名相同的分组，关注不丢', () async {
      final settings = Get.put<AppSettingsController>(FakeSettings());
      settings.followGroupBySite.value = true;
      settings.followSiteGroupSites.assignAll(Sites.orderedIds(settings.siteSort));
      final svc = FakeFollowService(
        users: [
          FollowUser(
            id: 'huya_甲',
            roomId: 'r',
            siteId: 'huya',
            userName: '甲',
            face: '',
            addTime: DateTime(2024),
          ),
        ],
        tags: [
          FollowUserTag(id: 'a0', tag: '虎牙直播', userId: ['huya_甲']),
          FollowUserTag(id: 'a1', tag: '我的喜爱', userId: ['huya_甲']),
        ],
      );
      Get.put<FollowService>(svc);
      final settingsPage = Get.put(FollowAppSettingsController());

      await settingsPage.cleanupPlatformNamedTags();

      // 同名分组没了，自定义分组还在；关注本体一条不丢
      expect(
        svc.followTagList.map((t) => t.tag),
        ['我的喜爱'],
      );
      expect(svc.followList.length, 1);
    });

    test('平台没开（不在子开关里）时不删它的同名分组', () async {
      final settings = Get.put<AppSettingsController>(FakeSettings());
      settings.followGroupBySite.value = true;
      // 只开虎牙：斗鱼 / B站等的同名分组不该被动
      settings.followSiteGroupSites.assignAll(['huya']);
      final svc = FakeFollowService(
        users: [],
        tags: [
          FollowUserTag(id: 'a0', tag: '斗鱼直播', userId: []),
          FollowUserTag(id: 'a1', tag: '虎牙直播', userId: []),
        ],
      );
      Get.put<FollowService>(svc);
      final settingsPage = Get.put(FollowAppSettingsController());

      await settingsPage.cleanupPlatformNamedTags();

      expect(svc.followTagList.map((t) => t.tag), ['斗鱼直播']);
    });
  });
}
