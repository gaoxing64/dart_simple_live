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

  testWidgets('弹幕设置本体带屏蔽入口：先收起当前层，再开这一格的屏蔽面板',
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
}
