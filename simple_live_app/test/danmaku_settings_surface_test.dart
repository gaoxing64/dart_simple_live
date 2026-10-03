// 桌面「弹幕设置」抽屉丢掉关键词屏蔽入口的回归。
//
// 9936e941 把桌面清单类弹层统一成右侧抽屉时，抽屉自己抄了一份 `DanmuSettingsView`，
// 少抄的正是 `onTapDanmuShield`：桌面从条带／⋮ 进弹幕设置后，再也点不到这一路的
// 屏蔽面板（移动端底部抽屉有、桌面没有）。本体收进
// `LiveRoomController.buildDanmuSettingsBody` 之后，抽屉和底部抽屉渲染的是同一份，
// 所以这里钉的就是「本体这一份」——它同时是两个容器的内容。
//
// 不给底部抽屉另搭 harness：`Utils.showBottomSheet` 要 `Get.context` 与路由栈，搭起来
// 测的是容器形态而不是这条入口，而入口会不会再丢只取决于本体有没有那一份。
//
// 补一条反向的（`d1b02d45` 的复审）：本体收拢时桌面补回了入口，移动端横屏全屏那层却
// 被顺手一起改了——它改前没接 `onTapDanmuShield`，点「关键词屏蔽」落的是全局屏蔽设置页。
// 于是入口改成按 surface 选入（`perStreamerShield`），这里两条用例就是这一对：桌面开着、
// 移动端关着。只钉正向的那条的话，「把移动端也统一掉」这种改法不会再留下任何证据。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用）。
/// `DanmuSettingsView` 是 `GetView<AppSettingsController>`，build 时逐项读设置值。
class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 被测的那一格：空掉两处真依赖——下发音量给 mpv，以及屏蔽面板本身（它要
/// `followUserBlock` 与底部抽屉路由）。记录调用次数就是本用例的断言目标：
/// 面板必须开在**这一格**上，即那条 action 的 `target`，而不是页面主格。
class _FakeTile extends LiveRoomController {
  _FakeTile()
      : super(
          pSite: Sites.allSites.values.first,
          pRoomId: "r1",
          isSecondaryTile: true,
          tileSlot: 1,
        ) {
    // `danmakuController` 是 `late` 字段，真机由播放器建好弹幕视图时回填；
    // 本体只把它转交给 `DanmuSettingsView`，测试里给一个已赋值的 null 就够。
    danmakuController = null;
  }

  int shieldCalls = 0;

  @override
  void showFollowBlockShield({bool blockWords = true}) {
    shieldCalls++;
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('桌面那层带屏蔽入口：先收起当前层，再开这一格的屏蔽面板',
      (tester) async {
    final tile = _FakeTile();
    var dismissCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 本体是一份长清单，滚动容器只为避免测试画布上的 RenderFlex 溢出，
          // 屏蔽那颗在清单最上方，本来就在视口内。
          body: SingleChildScrollView(
            child: tile.buildDanmuSettingsBody(
              onDismiss: () => dismissCalls++,
              // 桌面 surface 的调用形态（`invokePlayerAction` 那条臂就是这么传的）
              perStreamerShield: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text("关键词屏蔽"),
      findsOneWidget,
      reason: '桌面抽屉丢掉的就是这条入口',
    );

    await tester.tap(find.text("关键词屏蔽"));
    await tester.pump();

    expect(
      dismissCalls,
      1,
      reason: '进了屏蔽面板却把上一层弹幕设置留着，两层叠着挡画面',
    );
    expect(
      tile.shieldCalls,
      1,
      reason: '屏蔽面板没开在这条 action 的 target（这一格）上',
    );
  });

  // 同一个本体、同一个「关键词屏蔽」，移动端那层（`showDanmakuSettings` 的默认，
  // 也就是横屏全屏底栏进来的右侧弹层）**不开**这条按主播的入口：它落的是
  // `DanmuSettingsView` 自己的默认 `Get.toNamed(kSettingsDanmuShield)`，即全局屏蔽
  // 设置页——本体收拢（d1b02d45）之前移动端一直就是这个行为。
  // WHY 要单独钉：共享本体很容易顺手把移动端一起「统一」成新行为，而本项目的硬约束是
  // 移动端不进这套模型、移动端路径逐位不变。这条断言与上一条是一对：把
  // `buildDanmuSettingsBody` 的 `perStreamerShield` 默认改成 true，或让移动端调用点
  // 补上 true，这一条就红。
  testWidgets('移动端那层没有按主播的屏蔽入口：这一格的面板不被打开', (tester) async {
    final tile = _FakeTile();
    var dismissCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            // 移动端 surface 的调用形态：只给怎么收这层，不给屏蔽入口（默认关）。
            child: tile.buildDanmuSettingsBody(
              onDismiss: () => dismissCalls++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text("关键词屏蔽"));
    await tester.pump();

    // 走的是全局那条路由，本 harness 里没有 `kSettingsDanmuShield` 这个命名路由，
    // 报错/空返回都只说明「没开这一格的面板」；先把它 drain 掉，别算成用例失败。
    tester.takeException();

    expect(
      tile.shieldCalls,
      0,
      reason: '移动端 surface 冒出了按主播的屏蔽入口，行为与改造前不再一致',
    );
    expect(
      dismissCalls,
      0,
      reason: '同上：入口没接线就不该先把上一层收掉',
    );
  });
}
