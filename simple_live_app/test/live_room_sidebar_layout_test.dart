import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/sidebar_layout.dart';

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
}
