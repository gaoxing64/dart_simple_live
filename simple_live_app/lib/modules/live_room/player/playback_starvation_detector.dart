/// 一次播放器运行时采样。
///
/// `cache-speed` 的单位是 B/s，`video-bitrate` 的单位是 bit/s；这里统一换算成
/// bit/s，避免拿两套单位直接比较。
class PlaybackHealthSample {
  const PlaybackHealthSample({
    required this.paused,
    required this.pausedForCache,
    required this.inputBitsPerSecond,
    required this.videoBitsPerSecond,
    required this.cacheSeconds,
    required this.cacheBufferingState,
  });

  final bool paused;
  final bool pausedForCache;
  final double inputBitsPerSecond;
  final double videoBitsPerSecond;
  final double cacheSeconds;
  final double cacheBufferingState;

  factory PlaybackHealthSample.fromMpvProperties(Map<String, String> props) {
    final cacheSpeedBytesPerSecond = _number(props['cache-speed']);
    return PlaybackHealthSample(
      paused: _boolean(props['pause']),
      pausedForCache: _boolean(props['paused-for-cache']),
      inputBitsPerSecond: cacheSpeedBytesPerSecond * 8,
      videoBitsPerSecond: _number(props['video-bitrate']),
      cacheSeconds: _number(props['demuxer-cache-duration']),
      cacheBufferingState: _number(
        props['cache-buffering-state'],
        fallback: 100,
      ),
    );
  }
}

/// 连续/滑动窗口内的播放饥饿判定。
///
/// 强信号是 mpv 的 `paused-for-cache`。弱信号用于识别“还没正式暂停，但输入码率
/// 已经追不上视频码率、缓存也见底”的前兆。两者都不能只看一次采样：
/// - 连续两次强信号立即确认；
/// - 最近 5 次里出现 3 次饥饿信号且至少一次是强信号；
/// - 如果只有弱信号，则要求最近 5 次里 4 次命中，避免把偶发 VBR 波动误判成慢节点。
///
/// 这样既能在硬卡顿时 2 秒左右触发，也不会被一次 seek/起播抖动误判。
class PlaybackStarvationDetector {
  PlaybackStarvationDetector({
    this.windowSize = 5,
    this.minHitsInWindow = 3,
  }) : assert(windowSize >= minHitsInWindow);

  /// 只对有一定码率的视频做“输入追不上”判断。低码率静态画面天然读得慢，
  /// 不能据此换线。
  static const double minVideoBitsPerSecondForRatio = 2 * 1000 * 1000;

  /// 直播追平直播点后，CDN 的稳态输入速率本来就会回落到约等于视频码率，
  /// 不能要求 1.25x 余量。只有明显低于视频码率才算“追不上”。
  ///
  /// 实测 16 个健康样本的稳态输入/视频码率中位数为 1.013；取 0.90 作为弱信号
  /// 阈值，留出 VBR 短时波动空间，避免把正常播放误判成慢节点。
  static const double inputHeadroom = 0.90;

  /// 缓存低于这个水位时，“输入不足”才真正可能马上变成暂停。
  static const double lowCacheSeconds = 0.35;

  final int windowSize;
  final int minHitsInWindow;

  final List<_Verdict> _window = <_Verdict>[];
  int _lastHitCount = 0;
  double _lastInputRatio = 1;

  /// 最近一次滚动窗口内的命中数，供日志/诊断读取。
  int get windowHitCount => _lastHitCount;

  /// 最近一次输入码率 / 视频码率；视频码率未知时为 1。
  double get lastInputRatio => _lastInputRatio;

  void reset() {
    _window.clear();
    _lastHitCount = 0;
    _lastInputRatio = 1;
  }

  /// 喂入一次采样；返回 true 表示已达自动换线阈值。
  bool add(PlaybackHealthSample sample) {
    // 用户主动暂停不是网络饥饿。
    if (sample.paused) {
      reset();
      return false;
    }

    final ratioKnown = sample.videoBitsPerSecond >= minVideoBitsPerSecondForRatio;
    final ratio =
        ratioKnown && sample.videoBitsPerSecond > 0 ? sample.inputBitsPerSecond / sample.videoBitsPerSecond : 1.0;
    _lastInputRatio = ratio;

    final inputStarved = ratioKnown &&
        sample.cacheSeconds <= lowCacheSeconds &&
        sample.cacheBufferingState < 50 &&
        ratio < inputHeadroom;
    final hit = sample.pausedForCache || inputStarved;

    _window.add(
      _Verdict(
        hit: hit,
        strong: sample.pausedForCache,
      ),
    );
    while (_window.length > windowSize) {
      _window.removeAt(0);
    }
    _lastHitCount = _window.where((verdict) => verdict.hit).length;

    final lastTwoStrong =
        _window.length >= 2 && _window[_window.length - 1].strong && _window[_window.length - 2].strong;
    final strongHits = _window.where((verdict) => verdict.strong).length;
    final mixedHits =
        _window.length >= minHitsInWindow && _lastHitCount >= minHitsInWindow && strongHits >= 1 && _window.last.hit;
    final lastFourHits = _window.length >= 4 && _window.skip(_window.length - 4).every((verdict) => verdict.hit);
    final weakOnly = (_window.length >= windowSize && _lastHitCount >= 4 && _window.last.hit) || lastFourHits;
    return lastTwoStrong || mixedHits || weakOnly;
  }
}

class _Verdict {
  const _Verdict({required this.hit, required this.strong});

  final bool hit;
  final bool strong;
}

bool _boolean(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'yes':
    case 'true':
    case '1':
      return true;
    default:
      return false;
  }
}

double _number(String? raw, {double fallback = 0}) {
  if (raw == null) {
    return fallback;
  }
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite || value < 0) {
    return fallback;
  }
  return value;
}
