import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
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
          pRoomId: 'anchor-detail-test',
        );

  int detailTaps = 0;

  @override
  LiveRoomController get focused => this;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {}

  @override
  void showAnchorDetail() {
    detailTaps++;
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(Get.reset);

  testWidgets('直播间主播展示条头像可进入详情', (tester) async {
    final room = Get.put<LiveRoomController>(_FakeRoom()) as _FakeRoom;
    room.detail.value = LiveRoomDetail(
      roomId: 'anchor-detail-test',
      title: '测试直播',
      cover: '',
      userName: '测试主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'https://example.com/live',
    );

    const page = LiveRoomPage();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: page.buildUserProfile),
        ),
      ),
    );

    expect(find.byTooltip('查看主播详情'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-room-anchor-avatar')));
    await tester.pump();

    expect(room.detailTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
