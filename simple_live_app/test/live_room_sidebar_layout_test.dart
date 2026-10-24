import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_app/modules/live_room/sidebar_layout.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _FakeSettings extends AppSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

class _FakeRoom extends LiveRoomController {
  _FakeRoom()
      : super(
          pSite: Sites.allSites.values.first,
          pRoomId: 'chat-tab-test',
        );

  @override
  LiveRoomController get focused => this;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {}
}

void main() {
  group('侧栏宽度夹取', () {
    test('窗口足够宽时原样返回期望值', () {
      expect(
        resolveLiveRoomSidebarWidth(desired: 360, availableWidth: 1200),
        360,
      );
    });

    test('低于下限按下限处理', () {
      expect(
        resolveLiveRoomSidebarWidth(desired: 100, availableWidth: 1200),
        kLiveRoomSidebarMinWidth,
      );
    });

    test('高于上限按上限处理', () {
      expect(
        resolveLiveRoomSidebarWidth(desired: 900, availableWidth: 1600),
        kLiveRoomSidebarMaxWidth,
      );
    });

    test('窗口不够宽时优先给视频区留够宽度', () {
      // 820 - 320 = 500，小于侧栏上限 560，侧栏让到 500。
      expect(
        resolveLiveRoomSidebarWidth(desired: 560, availableWidth: 820),
        500,
      );
    });

    test('窄到最小侧栏与视频区都放不下时仍保住侧栏下限', () {
      // 500 - 320 = 180 < 240：视频区继续缩，侧栏不破下限。
      expect(
        resolveLiveRoomSidebarWidth(desired: 400, availableWidth: 500),
        kLiveRoomSidebarMinWidth,
      );
    });
  });

  group('聊天页签保活', () {
    setUp(() {
      Get.testMode = true;
      Get.put<AppSettingsController>(_FakeSettings());
    });

    tearDown(Get.reset);

    testWidgets('切到 SC 再返回时复用聊天列表 State', (tester) async {
      final room = Get.put<LiveRoomController>(_FakeRoom());
      room.messages.addAll(
        List.generate(
          30,
          (index) => LiveMessage(
            type: LiveMessageType.chat,
            userName: '用户$index',
            message: '消息$index',
            color: LiveMessageColor.white,
          ),
        ),
      );
      const page = LiveRoomPage();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(builder: page.buildMessageArea),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final before = tester.element(find.byType(ListView));

      await tester.tap(find.text('SC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();

      final after = tester.element(find.byType(ListView).first);
      expect(
        identical(before, after),
        isTrue,
        reason: '切回聊天不应重新挂载整棵消息列表',
      );
    });
  });
}
