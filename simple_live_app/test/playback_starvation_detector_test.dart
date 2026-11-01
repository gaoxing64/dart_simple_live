import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/playback_starvation_detector.dart';

void main() {
  PlaybackHealthSample sample({
    bool paused = false,
    bool pausedForCache = false,
    double inputMbps = 10,
    double videoMbps = 10,
    double cacheSeconds = 2,
    double bufferingState = 100,
  }) {
    return PlaybackHealthSample(
      paused: paused,
      pausedForCache: pausedForCache,
      inputBitsPerSecond: inputMbps * 1000000,
      videoBitsPerSecond: videoMbps * 1000000,
      cacheSeconds: cacheSeconds,
      cacheBufferingState: bufferingState,
    );
  }

  test('mpv cache-speed 按 B/s 换算、video-bitrate 按 bit/s 读取', () {
    final parsed = PlaybackHealthSample.fromMpvProperties({
      'pause': 'no',
      'paused-for-cache': 'yes',
      'cache-speed': '1250000',
      'video-bitrate': '10000000',
      'demuxer-cache-duration': '0.25',
      'cache-buffering-state': '35',
    });
    expect(parsed.paused, isFalse);
    expect(parsed.pausedForCache, isTrue);
    expect(parsed.inputBitsPerSecond, 10000000);
    expect(parsed.videoBitsPerSecond, 10000000);
    expect(parsed.cacheSeconds, 0.25);
    expect(parsed.cacheBufferingState, 35);
  });

  test('连续两次 paused-for-cache 立即确认饥饿', () {
    final detector = PlaybackStarvationDetector();
    final starved = sample(
      pausedForCache: true,
      cacheSeconds: 0,
      bufferingState: 0,
    );
    expect(detector.add(starved), isFalse);
    expect(detector.add(starved), isTrue);
  });

  test('稳态输入约等于视频码率时不误判', () {
    final detector = PlaybackStarvationDetector();
    final normal = sample(
      inputMbps: 10.1,
      videoMbps: 10,
      cacheSeconds: 0.2,
      bufferingState: 40,
    );
    for (var i = 0; i < 5; i++) {
      expect(detector.add(normal), isFalse);
    }
  });

  test('稳态输入明显低于视频码率且缓存见底，4 次命中后确认', () {
    final detector = PlaybackStarvationDetector();
    final starving = sample(
      inputMbps: 8.5,
      videoMbps: 10,
      cacheSeconds: 0.1,
      bufferingState: 30,
    );
    expect(detector.add(starving), isFalse);
    expect(detector.add(starving), isFalse);
    expect(detector.add(starving), isFalse);
    expect(detector.add(starving), isTrue);
  });

  test('缓存水位健康或视频码率过低时，不按输入比例误判', () {
    final detector = PlaybackStarvationDetector();
    final cacheHealthy = sample(
      inputMbps: 1,
      videoMbps: 10,
      cacheSeconds: 3,
      bufferingState: 100,
    );
    for (var i = 0; i < 5; i++) {
      expect(detector.add(cacheHealthy), isFalse);
    }

    detector.reset();
    final lowBitrate = sample(
      inputMbps: 0.2,
      videoMbps: 1.2,
      cacheSeconds: 0.1,
      bufferingState: 20,
    );
    for (var i = 0; i < 5; i++) {
      expect(detector.add(lowBitrate), isFalse);
    }
  });

  test('用户主动暂停会清空窗口，不触发换线', () {
    final detector = PlaybackStarvationDetector();
    final starved = sample(
      pausedForCache: true,
      cacheSeconds: 0,
      bufferingState: 0,
    );
    expect(detector.add(starved), isFalse);
    expect(detector.add(sample(paused: true)), isFalse);
    expect(detector.add(starved), isFalse);
  });

  test('强/弱信号交替时，5 次窗口内 3 次命中仍能确认', () {
    final detector = PlaybackStarvationDetector();
    final strong = sample(
      pausedForCache: true,
      cacheSeconds: 0,
      bufferingState: 0,
    );
    final weak = sample(
      inputMbps: 8.5,
      videoMbps: 10,
      cacheSeconds: 0.1,
      bufferingState: 30,
    );
    final healthy = sample(
      inputMbps: 10,
      videoMbps: 10,
      cacheSeconds: 2,
      bufferingState: 100,
    );
    expect(detector.add(strong), isFalse);
    expect(detector.add(healthy), isFalse);
    expect(detector.add(weak), isFalse);
    expect(detector.add(healthy), isFalse);
    expect(detector.add(weak), isTrue);
  });
}
