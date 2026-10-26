import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

/// 这里钉的是**真正下发给 mpv 的键值表**（[buildLiveCacheProperties] 的产物），
/// 而不是 `resolvePlayerCacheSecs` 的返回值：以前只测返回值时，把
/// initializePlayer 里的接线改回字面量甚至删掉写入，测试照样全绿。
/// 表由「平台 × 双重缓冲 × 站点解析值」三要素组成，站点解析值现算现传，
/// 所以这条链路上任何一环被改坏（含 Twitch 覆写失效）都会在这里炸。
void main() {
  LiveRoomController controllerFor({required bool twitch}) => LiveRoomController(
        pSite: Sites.allSites.values.firstWhere(
          (site) => twitch ? site.id == Constant.kTwitch : site.id != Constant.kTwitch,
        ),
        pRoomId: 'room',
      );

  /// 与 initializePlayer 完全相同的组表方式。
  Map<String, String> tableOf(
    LiveRoomController controller, {
    required bool isAndroid,
    required bool doubleBuffering,
  }) =>
      buildLiveCacheProperties(
        isAndroid: isAndroid,
        doubleBuffering: doubleBuffering,
        cacheSecs: controller.resolvePlayerCacheSecs(doubleBuffering),
      );

  test('Twitch 桌面端写入 cache-secs=10，双重缓冲开合都是 10', () {
    final controller = controllerFor(twitch: true);
    for (final doubleBuffering in [false, true]) {
      final props =
          tableOf(controller, isAndroid: false, doubleBuffering: doubleBuffering);
      expect(
        props['cache-secs'],
        '10',
        reason: 'doubleBuffering=$doubleBuffering',
      );
      // 基础段恒在：直播必须开前向缓存、不落盘。
      expect(props['cache'], 'yes');
      expect(props['cache-on-disk'], 'no');
    }
  });

  test('非 Twitch 桌面端保持 1s / 双重缓冲 3s 且回退缓存形态正确', () {
    final controller = controllerFor(twitch: false);

    final plain = tableOf(controller, isAndroid: false, doubleBuffering: false);
    expect(plain, {
      'cache': 'yes',
      'cache-on-disk': 'no',
      'demuxer-max-back-bytes': '0',
      'demuxer-seekable-cache': 'no',
      'cache-secs': '1',
    });

    final doubled = tableOf(controller, isAndroid: false, doubleBuffering: true);
    expect(doubled, {
      'cache': 'yes',
      'cache-on-disk': 'no',
      // 基础段先把回退缓存压 0，双重缓冲段必须复位，否则「双重缓冲」名不副实。
      'demuxer-max-back-bytes': '16777216',
      'demuxer-seekable-cache': 'yes',
      'demuxer-donate-buffer': 'yes',
      'cache-secs': '3',
    });
  });

  test('Android + 关双重缓冲：不写任何缓存键（留在 mpv 默认，改前既有行为）', () {
    final props = tableOf(
      controllerFor(twitch: false),
      isAndroid: true,
      doubleBuffering: false,
    );
    expect(props, isEmpty);

    // Twitch 在 Android 关双重缓冲时同样一格不写：覆写只改「写什么值」，
    // 不改变「写不写」的平台门闩。
    final twitchProps = tableOf(
      controllerFor(twitch: true),
      isAndroid: true,
      doubleBuffering: false,
    );
    expect(twitchProps, isEmpty);
  });

  test('Android + 开双重缓冲：cache-secs 用站点解析值，Twitch 在手机上也是 10', () {
    final props = tableOf(
      controllerFor(twitch: true),
      isAndroid: true,
      doubleBuffering: true,
    );
    expect(props, {
      'cache': 'yes',
      'cache-secs': '10',
      'demuxer-max-back-bytes': '16777216',
      'demuxer-seekable-cache': 'yes',
      'demuxer-donate-buffer': 'yes',
    });
  });
}
