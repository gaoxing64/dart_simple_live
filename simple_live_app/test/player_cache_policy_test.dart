import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

void main() {
  test('Twitch 普通和双重缓存模式都预读 10 秒', () {
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kTwitch]!,
      pRoomId: 'room',
    );

    for (final doubleBuffering in [false, true]) {
      expect(
        controller.resolvePlayerCacheSecs(doubleBuffering),
        10,
        reason: 'doubleBuffering=$doubleBuffering',
      );
    }
  });

  test('其他平台保持原有预读时长', () {
    final controller = LiveRoomController(
      pSite: Sites.allSites.values.firstWhere(
        (site) => site.id != Constant.kTwitch,
      ),
      pRoomId: 'room',
    );

    expect(controller.resolvePlayerCacheSecs(false), 1);
    expect(controller.resolvePlayerCacheSecs(true), 3);
  });
}
