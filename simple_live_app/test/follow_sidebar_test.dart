// 关注页第二栏（标签侧栏）与「按平台分类」设置的测试：
// 侧栏宽度（两字模式 80 / 常规固定 140）、平台标签显隐与顺序、同名分组静默清理、布局设置读法。
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

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    // 每个用例后清空注册表：否则后一个用例的 Get.put 会复用前一个用例的
    // 控制器实例（它捕获的是上一个 FakeFollowService），清理就落到错的数据上。
    Get.reset();
  });

  group('FollowSidebar.widthFor 侧栏宽度', () {
    test('常规模式固定 140：不随窗口变宽而放大', () {
      expect(FollowSidebar.normalWidth, 140.0);
      expect(FollowSidebar.widthFor(480), 140.0);
      expect(FollowSidebar.widthFor(600), 140.0);
      expect(FollowSidebar.widthFor(1000), 140.0);
      expect(FollowSidebar.widthFor(4000), 140.0);
    });

    test('窄窗（手机竖屏）进两字模式：栏宽压到 80', () {
      expect(FollowSidebar.isCompact(400), isTrue);
      expect(FollowSidebar.widthFor(400), FollowSidebar.compactWidth);
      expect(FollowSidebar.widthFor(360), FollowSidebar.compactWidth);
      expect(FollowSidebar.widthFor(430), FollowSidebar.compactWidth);
      // 阈值边界：480 起回到常规宽度
      expect(FollowSidebar.isCompact(480), isFalse);
    });

    test('两字模式给内容列腾出足够空间（紧凑行最小约 152）', () {
      // 最窄的合理手机宽度 360：侧栏 80 → 内容 280，远够一行
      expect(360 - FollowSidebar.widthFor(360), greaterThanOrEqualTo(152));
      expect(400 - FollowSidebar.widthFor(400), greaterThanOrEqualTo(152));
    });

    test('compactLabel：只留前两个字（按字符簇）', () {
      expect(FollowSidebar.compactLabel('全部'), '全部');
      expect(FollowSidebar.compactLabel('直播中'), '直播');
      expect(FollowSidebar.compactLabel('哔哩哔哩'), '哔哩');
      expect(FollowSidebar.compactLabel('Twitch'), 'Tw');
      // emoji 不拆代理对 / 组合字符
      expect(FollowSidebar.compactLabel('🐱🐶🐭'), '🐱🐶');
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
