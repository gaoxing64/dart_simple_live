import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:audio_session/audio_session.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/playback/live_audio_session.dart';
import 'package:simple_live_app/services/playback/live_playback_target.dart';

/// 把「当前直播间这一路」投影到系统媒体控制面上：
///
/// | 平台 | 系统面 | 由谁实现 |
/// | --- | --- | --- |
/// | Android | MediaSession + 媒体通知 + 耳机/蓝牙媒体键 | audio_service 自带 |
/// | iOS / macOS | Now Playing（锁屏 / 控制中心 / 媒体键） | audio_service 自带 darwin |
/// | Windows | SMTC（媒体浮层 / 键盘媒体键） | audio_service_win（SMTC） |
/// | Linux | MPRIS（D-Bus，桌面媒体控件） | audio_service_mpris |
///
/// 背后出声的仍然是 media_kit 的 libmpv 播放器，这里**不拥有**播放：
/// * 状态与元数据由挂载进来的 [LivePlaybackTarget]（直播间控制器）供给，单向发布；
/// * 远程指令（播放/暂停/停止）反向转给它。
///
/// audio_service 的 handler 跑在**主 isolate**（已核 0.18.19 源码），所以这里能直接
/// 持有并操作那个播放器；换成隔离子实现的版本就做不到这一点。
///
/// 桌面端与移动端只有一处实现差异：移动端多一层前台服务与音频会话（通知权限、
/// 音频焦点、中断/拔耳机），桌面端没有。开关是同一个「系统媒体控制」（默认开）。
class LivePlaybackAudioHandler extends BaseAudioHandler {
  static LivePlaybackAudioHandler? _instance;

  /// 未初始化（初始化失败、或平台不支持）时为 null——调用方据此整体空转，不抛。
  static LivePlaybackAudioHandler? get maybeInstance => _instance;

  /// 五个系统都有系统媒体控制；TV 是另一个 app（simple_live_tv_app），不在这里。
  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isWindows;

  LivePlaybackAudioHandler() {
    // 焦点与设备插拔只能由我们自己接（原因见 LiveAudioSession 的类注释）。
    LiveAudioSession.instance.interruptions.listen(_onInterruption);
    LiveAudioSession.instance.becomingNoisy.listen((_) => _pauseBySystem());
  }

  LivePlaybackTarget? _target;

  /// 当前挂载的直播间；未挂载时为 null。
  LivePlaybackTarget? get target => _target;

  /// App 此刻是否在前台，由直播间控制器的 `didChangeAppLifecycleState` 推进来。
  ///
  /// 之所以不在这里读 `WidgetsBinding.instance.lifecycleState`：一来 handler 应当
  /// 能在没有 binding 的环境里被构造出来，二来直播间那边本来就是这个事件的权威源。
  ///
  /// 用途是挡 Android 12+ 的 `ForegroundServiceStartNotAllowedException`：后台起前台
  /// 服务会抛，而 `AudioService.enterPlayingState()` 里那句 `startForegroundService`
  /// **没有** try/catch（已核源码）。现实中起播总发生在前台，这道闸只在「点进房间
  /// 立刻按 Home、流才刚连上」那种时序里才拦得住。
  bool appInForeground = true;

  /// 是否已经进过一次播放态（前台服务已经拉起过）。
  bool _enteredPlayingState = false;

  /// [refresh] 的去重缓存：上一次真的推给系统的元数据/状态的键。
  /// null 表示「下一条必须发出去」（初次挂载、摘除之后、或换了另一路）。
  String? _lastItemKey;
  String? _lastStateKey;

  // ---------------------------------------------------------------- 挂载 / 摘除

  /// 幂等：同一个 target 重复挂载只等价于一次 [refresh]。
  ///
  /// 这里**不**去激活音频会话——挂载只代表「这一路是当前直播间」，不代表在出声。
  /// 抢焦点只在 [refresh] 真的推出 playing=true 时做，否则 attach 是跟着 mpv 的
  /// 事件率跑的（弱网时 buffering 一跳一回），会把 requestAudioFocus 打成连发。
  void attach(LivePlaybackTarget target) {
    final changed = !identical(_target, target);
    _target = target;
    if (changed) {
      // 换了另一路（换房间、或另一个直播间实例）：去重缓存必须作废，
      // 否则新路的元数据若与旧路的键相同就会被当成「没变化」而不发出去。
      _lastItemKey = null;
      _lastStateKey = null;
      Log.d('系统媒体控制：挂载 ${target.playbackMediaId}');
    }
    refresh();
  }

  /// 摘除。带身份校验：换台之后旧控制器再来摘，不能把新那一路顶掉。
  Future<void> detach(LivePlaybackTarget target) async {
    if (!identical(_target, target)) {
      return;
    }
    _target = null;
    _enteredPlayingState = false;
    _publishIdle();
    await LiveAudioSession.instance.deactivate();
    Log.d('系统媒体控制：摘除');
  }

  /// 落回 idle：通知撤下、前台服务停。
  ///
  /// 不直接用父类的 `AudioHandler.stop()`——它只把 `processingState` 改成 idle、
  /// **不动** `playing`（audio_service.dart:3113-3119），通知会停在「正在播放」的假象上，
  /// 而 idle 之后没有任何东西再把它改回来。
  void _publishIdle() {
    _lastItemKey = null;
    _lastStateKey = null;
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
      ),
    );
  }

  /// 唯一的发布入口：状态或元数据有**实际**变化时整体重推一遍。
  ///
  /// 整体重推而不是增量 copyWith，是为了让「通知里此刻有什么」永远等于
  /// 「target 现在的样子」，不会出现线路切了、标题还是上一路的。
  ///
  /// 去重是必需的：`refresh()` 挂在 mpv 的 playing/buffering/completed 上，弱网时
  /// 一秒能跳好几回，而每一回都会走到 Java 的 `setMetadata` → `notify()` →
  /// `removeCallbacksAndMessages(null)`（AudioService.java:786-806）。
  /// 不能用 `PlaybackState ==` 去重：它的 `==` 里含 `updateTime`，而构造时默认取
  /// `DateTime.now()`，两次内容完全一样的状态永远不相等，所以自己按会变的字段组键。
  void refresh() {
    final t = _target;
    if (t == null) {
      return;
    }
    // 从没进过播放态、又正处在后台：先按未播发布，回前台后的下一次再补（原因见
    // appInForeground）。这道网只为 Android 12+ 的前台服务异常而设，别的平台
    // 没有它，不能被它压住（桌面窗口失焦时 lifecycle 也会离开 resumed）。
    final safePlaying = t.playbackPlaying &&
        (!Platform.isAndroid || _enteredPlayingState || appInForeground);
    if (safePlaying) {
      _enteredPlayingState = true;
    }

    final item = _buildMediaItem(t);
    final state = _buildPlaybackState(t, safePlaying: safePlaying);
    final itemKey = _itemKey(item);
    final stateKey = _stateKey(state);
    if (itemKey == _lastItemKey && stateKey == _lastStateKey) {
      return;
    }
    _lastItemKey = itemKey;
    _lastStateKey = stateKey;
    mediaItem.add(item);
    playbackState.add(state);
    if (safePlaying) {
      unawaited(LiveAudioSession.instance.activate());
    }
  }

  String _itemKey(MediaItem m) =>
      '${m.id}|${m.title}|${m.artist}|${m.album}|${m.artUri}|${m.isLive}';

  String _stateKey(PlaybackState s) =>
      '${s.playing}|${s.processingState.name}|${s.updatePosition.inMilliseconds}';

  // ---------------------------------------------------------------- 远程指令

  @override
  Future<void> play() async {
    final t = _target;
    if (t == null) {
      return;
    }
    await t.playbackPlay();
    // 会话激活不用在这里单独做一次：refresh 推出 playing=true 那条边沿时就会激活。
    refresh();
  }

  @override
  Future<void> pause() async {
    final t = _target;
    if (t == null) {
      return;
    }
    await t.playbackPause();
    refresh();
    // 暂停**不**让出焦点：媒体 app 的惯例是暂停期间仍占着，免得别的 app 顺势起播,
    // 也免得用户在锁屏上按一下播放要重新去抢（iOS 那边挂起久了甚至会抢不回来）。
    // 焦点只在 detach/stop 时释放——那时这一路真的结束了。
  }

  @override
  Future<void> stop() async {
    final t = _target;
    if (t == null) {
      _publishIdle();
      return;
    }
    await t.playbackStop();
    await detach(t);
  }

  /// 从最近任务里划掉 app：停止播放并撤通知（产品决定）。
  ///
  /// 划掉任务是「我不用了」的明确手势。留着前台服务继续出声的话，用户面对的是
  /// 一个已经不存在的 app 在说话，且唯一的止损入口只剩通知里那颗停止。
  @override
  Future<void> onTaskRemoved() => stop();

  /// 通知被划掉：同样当作停止，免得「通知没了、声音还在」。
  ///
  /// 在当前配置（`androidNotificationOngoing: true`）下这条路**走不到**：Java 侧
  /// `buildNotification()` 只看这个配置位就 `builder.setOngoing(true)`，不区分播放/暂停
  /// （AudioService.java:646-650），所以通知任何时候都划不掉。真正的退出入口是同一处
  /// 配上去的那颗取消键（`setShowCancelButton(true)` + `ACTION_STOP` 的 PendingIntent），
  /// 它会落到 [stop]。这里保留覆写，是给通知确实可被划掉的机型/未来配置兜底。
  @override
  Future<void> onNotificationDeleted() => stop();

  // ---------------------------------------------------------------- 发布内容

  MediaItem _buildMediaItem(LivePlaybackTarget t) => MediaItem(
        id: t.playbackMediaId,
        title: t.playbackTitle,
        artist: t.playbackArtist,
        album: t.playbackAlbum,
        artUri: t.playbackArtUri,
        isLive: t.playbackIsLive,
        // 刻意不发布 duration。一旦给了 duration，Android 与 iOS 都会画出可拖的进度条，
        // 而我们不推 `updatePosition`（v1 不做进度），那条就会永远冻在 0:00 ——
        // 一个「看得见、拖着没反应」的控件比没有控件更糟。
        // 轮播录像（isRecord）真要做进度，得同时接上 player.stream.position。
      );

  PlaybackState _buildPlaybackState(
    LivePlaybackTarget t, {
    required bool safePlaying,
  }) {
    return PlaybackState(
      // 只发暂停/播放与停止。seek、上一首/下一首、快进/快退一个都不发：直播没有可拖的
      // 时间轴，也没有「下一集」；而 audio_service 没有「置灰」这个概念，发出去的键
      // 就是一个按得动却毫无反应的键。
      controls: [
        safePlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.stop},
      processingState: t.playbackBuffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: safePlaying,
      // 直播不推进进度；录像的进度也等真要做时再补（要订阅 position 流）。
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    );
  }

  /// 系统中断：来电、别家抢焦点。`duck` 不算——那只是导航播报这类「让出音量」的请求，
  /// 为它暂停一路直播会很怪。
  void _onInterruption(AudioInterruptionEvent event) {
    if (event.type == AudioInterruptionType.duck) {
      return;
    }
    _pauseBySystem();
  }

  /// 中断/拔耳机带来的暂停：由系统发起，所以不再去动焦点（我们已经被迫让出），
  /// 只把状态同步回通知，免得通知还显示着「正在播放」。
  void _pauseBySystem() {
    final t = _target;
    if (t == null) {
      return;
    }
    unawaited(t.playbackPause().then((_) => refresh()));
  }
}

/// 必须在 `runApp` 之前调用。
///
/// 失败不往上抛：初始化挂了只等于「没有系统媒体控制」，播放本身不依赖它，
/// 不该因此挡住 app 启动。
Future<void> initLivePlaybackAudioHandler() async {
  if (!LivePlaybackAudioHandler.isSupported) {
    return;
  }
  try {
    if (Platform.isLinux) {
      // MPRIS 的 Identity / DesktopEntry / 能力位只能在 configure 之前给：
      // audio_service 的 config 里没有这些字段，必须由平台实现自己接（见包文档）。
      // CanGoNext/CanGoPrevious 恒为 false——直播没有「下一集」，一个按得动却
      // 没反应的键比没有更糟（与 PlaybackState 里只发 play/pause/stop 同一取舍）。
      AudioServiceMpris.init(
        dBusName: 'slive',
        identity: 'Slive',
        desktopEntry: 'io.github.SlotSun.Slive',
        canControl: true,
        canPlay: true,
        canPause: true,
        supportedUriSchemes: const ['http', 'https'],
      );
    }
    final handler = await AudioService.init(
      builder: () => LivePlaybackAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.slotsun.slive.playback',
        androidNotificationChannelName: '直播播放',
        androidNotificationChannelDescription: '锁屏或切到后台时控制直播播放',
        // 必须是纯白单色图标；默认值 mipmap/ic_launcher 是彩色的，在状态栏里会糊成
        // 一坨白块。见 android/app/src/main/res/drawable/ic_stat_slive.xml。
        androidNotificationIcon: 'drawable/ic_stat_slive',
        // 播放中通知不可划掉。这个 assert 要求它必须与
        // androidStopForegroundOnPause=true 同时使用（已核源码）。
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // 封面按 512 封顶降采样：直播封面普遍偏大，四路多开时内存不值这个钱。
        artDownscaleWidth: 512,
        artDownscaleHeight: 512,
      ),
    );
    LivePlaybackAudioHandler._instance = handler;
  } catch (e) {
    Log.e('系统媒体控制：audio_service 初始化失败 ($e)', StackTrace.current);
  }
}
