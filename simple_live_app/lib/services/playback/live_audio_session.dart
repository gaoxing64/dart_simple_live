import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:simple_live_app/app/log.dart';

/// 「后台播放」要用的系统音频会话。
///
/// **为什么必须自己接这一层**（2026-10-08 直接核过 audio_service 0.18.19 的包源码）：
/// * 它从不调用 `AudioSession.configure()`，只在**已废弃**的 `onStop()` 里
///   `setActive(false)`（我们走新 API 覆写 `stop()`，那条路不会被触发）；
/// * 整个包里没有任何 `requestAudioFocus`。
///
/// 也就是说 iOS 的 `AVAudioSession` 类别、Android 的音频焦点与中断，
/// audio_service 不管，media_kit/libmpv 也不管，只有这里管。
///
/// * **iOS**：类别必须是 `playback`（`AudioSessionConfiguration.music()` 给的正是
///   `AVAudioSessionCategory.playback`）。`Info.plist` 里的 `UIBackgroundModes: audio`
///   只声明「系统允许你在后台出声」，真正把会话维持在后台、且拨静音键也不静音的，
///   是这个类别加上 `setActive(true)`。
/// * **Android**：`setActive(true)` 内部走 `requestAudioFocus`。没拿到焦点时，进程
///   虽然被前台服务保住，但别的 app 一出声就会跟我们混音。
///
/// 只在开启「后台播放」并真的进入播放态时激活；摘除/停止时释放。
class LiveAudioSession {
  LiveAudioSession._();

  static final LiveAudioSession instance = LiveAudioSession._();

  // 转发而不是直接暴露 AudioSession 的流：会话是异步拿到的，而订阅方（handler）
  // 在构造期就要挂上监听，这里先给出一条恒在的广播流把两段隔开。
  final _interruptionController =
      StreamController<AudioInterruptionEvent>.broadcast();
  final _becomingNoisyController = StreamController<void>.broadcast();

  /// 系统级中断（来电、别的 app 抢焦点）。原样转发，**由订阅方决定**要不要暂停：
  /// `duck` 只是提示「让出音量」（导航播报就是这档），据此暂停直播会莫名其妙。
  Stream<AudioInterruptionEvent> get interruptions =>
      _interruptionController.stream;

  /// 拔出有线耳机 / 断开蓝牙音频。
  ///
  /// 两个平台都有：Android 走 `ACTION_AUDIO_BECOMING_NOISY`，iOS 走
  /// `AVAudioSessionRouteChangeReason.oldDeviceUnavailable`（已核 0.2.4 源码）。
  Stream<void> get becomingNoisy => _becomingNoisyController.stream;

  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;

  /// 已经 configure 过、监听也挂好了。
  ///
  /// 与「焦点是否批下来」**分开记**：`activate()` 是跟着播放态的边沿调用的，若把
  /// 「已配置」和「已授权」合成一个位，焦点被拒时就会每次都重跑一遍 `configure()`
  /// （iOS 侧重复设类别、Android 侧重复申请焦点属性）。
  bool _configured = false;

  /// 正在激活中：进入播放态与用户按播放可能同时进来，别把 configure 跑两遍。
  bool _activating = false;

  /// 每次进入播放态都调一次。`setActive(true)` 本身在已激活时是廉价的重复调用，
  /// 而我们**必须**重复调它：iOS 在一轮中断（电话）结束后会话被系统停掉，
  /// 不重新 `setActive(true)` 就拿不回出声。真正昂贵的 `configure()` 走 `_configured`。
  Future<void> activate() async {
    if (_activating || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    _activating = true;
    try {
      final session = await AudioSession.instance;
      if (!_configured) {
        await session.configure(const AudioSessionConfiguration.music());
        _session = session;
        // 只订阅一次：中断与拔耳机是进程级的事，跟具体哪一路直播间无关。
        _interruptionSubscription ??=
            session.interruptionEventStream.listen((event) {
          Log.d('后台播放：系统中断 begin=${event.begin} type=${event.type}');
          if (event.begin) {
            _interruptionController.add(event);
          }
        });
        _becomingNoisySubscription ??=
            session.becomingNoisyEventStream.listen((_) {
          Log.d('后台播放：音频输出设备已断开');
          _becomingNoisyController.add(null);
        });
        _configured = true;
      }
      final granted = await session.setActive(true);
      if (!granted) {
        // 焦点没批下来也照常播：前台服务还在，声音不会断，只是可能被别的 app 压掉。
        Log.d('后台播放：音频焦点未获批准，继续播放但不保证不被压低');
      }
    } catch (e) {
      Log.e('后台播放：音频会话激活失败 ($e)', StackTrace.current);
    } finally {
      _activating = false;
    }
  }

  /// 让出焦点与会话。
  ///
  /// `notifyOthersOnDeactivation`：让我们被打断的那个 app（音乐、播客）立刻接着播，
  /// 而不是干等系统超时。
  Future<void> deactivate() async {
    if (!_configured) {
      return;
    }
    // 注意不动 `_configured`：类别与监听是进程级的，一次配好就行；这里只让出会话。
    try {
      await _session?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (e) {
      Log.e('后台播放：音频会话释放失败 ($e)', StackTrace.current);
    }
  }
}
