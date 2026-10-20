import 'dart:async';
import 'dart:io';
import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:floating/floating.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';
import 'package:simple_live_app/services/window_service.dart';
import 'package:simple_live_app/modules/live_room/player/pip_aspect.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/custom_throttle.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/player/danmaku_emoticon.dart';
import 'package:simple_live_app/modules/live_room/player/player_fit.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

/// 音量均衡（loudnorm / EBU R128 响度标准化）的 mpv 音频滤波链，目标响度取设置项。
///
/// 直播流没有内嵌 ReplayGain 元数据，mpv 的 `--replaygain=track` 对直播是空操作
/// （它只认文件标签）。曾用 dynaudnorm，但它是**峰值**归一化：抖音等平台的转码
/// 普遍挂限幅器，各主播流的峰值都贴着 0dBFS，目标 0.95 算出的增益趋近 1，
/// 等于没效果；听感上的响度差异来自综合响度（LUFS），所以改用 loudnorm：
/// - I=<设置项>  目标综合响度（默认 -16 LUFS，移动端流媒体惯例，可调 -14/-12 更响）
/// - TP=-1.5     真峰值上限 -1.5 dBTP，防止增益后削波
/// - LRA=11      响度范围 11 LU（默认值），限制压动态的程度
///
/// 注意：loudnorm 动态模式约 3s 一个测量窗，刚进直播间响度要一两个窗才稳定；
/// 内部按 192kHz 处理并强制输出该采样率，mpv 会在链尾自动插 aresample 回设备
/// 采样率，无需手动补偿。
///
/// ⚠️ 依赖播放内核编译了 loudnorm 滤镜。Predidit 官方的 libmpv 构建（ffmpeg
/// `--disable-filters` 只留 overlay/equalizer）没有它，挂载会导致 af 链初始化失败、
/// mpv 直接禁用音频轨道（静音）。本项目使用 fork 构建（feat/audio-filters，已含
/// dynaudnorm/loudnorm），运行时仍保留日志自愈，详见 volume-normalize-notes.md。
String volumeNormalizeAF() => 'lavfi=[loudnorm='
    'I=${AppSettingsController.instance.volumeNormalizeTargetLufs.value}:'
    'TP=-1.5:LRA=11]';

/// 本次会话已探测到播放内核缺少音频滤镜。
/// 滤镜有无是编译期属性，会话内不会变；置位后不再挂载，避免每次进直播间都静音一次。
bool _volumeNormalizeUnsupported = false;

/// 音量均衡滤波链已挂载、正在等起播结果（用于匹配失败日志，避免误伤其他日志）。
bool _volumeNormalizePending = false;

/// 本次会话的播放内核是否编入了 Lua（决定 mpv 内置 OSD 是否可用）。
/// Lua 有无是编译期属性，会话内不会变；首次探测后缓存。
bool? _mpvLuaSupported;

/// `initializePlayer()` 里通过 `setProperty` 设置的配置项，用于回读校验。
///
/// media_kit 的 `NativePlayer.setProperty()` 直接调用 `mpv_set_property_string()`
/// 并**丢弃返回值**（见 media_kit `real.dart`），因此属性名写错、值非法或平台不支持时
/// 既不抛异常也不打日志，只能通过 `getProperty` 回读来确认「设置到底有没有生效」。
///
/// 这里只放「设置类」属性。运行时诊断属性（cache-buffering-state、paused-for-cache、
/// frame-drop-count 等）不在此列：它们只在起播后才有值，播放期间请直接看 OSD 浮层的
/// Cache / Frame 页。
const List<String> _kPlayerConfigProps = [
  // 本项目通过 setProperty 设置的配置项
  'ao',
  'volume-max',
  'vf',
  'af',
  'hwdec',
  'force-seekable',
  'cache',
  'cache-secs',
  'cache-on-disk',
  'demuxer-max-back-bytes',
  'demuxer-seekable-cache',
  'demuxer-donate-buffer',
  'demuxer-cache-dir',
  // 不由本项目设置，但决定实际延迟 / 内存上限，一并回读便于对照
  'demuxer-readahead-secs',
  'demuxer-max-bytes',
  'hr-seek',
];

mixin PlayerMixin {
  GlobalKey<VideoState> globalPlayerKey = GlobalKey<VideoState>();
  GlobalKey globalDanmuKey = GlobalKey();

  /// 播放器实例
  late final player = Player(
    configuration: PlayerConfiguration(
      title: playerTitle,
      bufferSize: playerBufferSize,
      logLevel: AppSettingsController.instance.logEnable.value ? MPVLogLevel.debug : MPVLogLevel.error,
    ),
  );

  /// 本实例的 mpv 缓存上限（字节）。
  ///
  /// media_kit 默认 32MiB，会写进 mpv 的 `demuxer-max-bytes`；四路同时跑就是 128MiB 起，
  /// 所以副格走设置项压低（`LiveRoomController` 覆写），主格保持默认不动。
  int get playerBufferSize => 32 * 1024 * 1024;

  /// 播放器标题：多开时每格带槽位，便于在 mpv 日志里区分是哪一路。
  ///
  /// 注意它们同在一个进程里，Windows 音量合成器按进程分会话，所以标题**不会**
  /// 拆出四条音量滑块——真正的按格音量靠 [resolveTargetVolume]。
  String get playerTitle => "Slive Player";

  /// 本实例此刻该用的 mpv 音量（百分比）。
  ///
  /// 单开路径就是全局总音量；多开时 `LiveRoomController` 覆写成「聚焦格用总音量、
  /// 其余格开了压低才按设置压低」。
  double resolveTargetVolume() => AppSettingsController.instance.playerVolume.value;

  /// 把 [resolveTargetVolume] 的结果下发给 mpv。
  Future<void> applyTargetVolume() async {
    if (player.platform is! NativePlayer) {
      return;
    }
    await player.setVolume(resolveTargetVolume());
  }

  /// 是否允许做窗口级操作（全屏 / 小窗 / PiP / 自动全屏）。
  ///
  /// 多开时窗口只有一个，只有页面主格能碰，副格一律 false。
  bool get allowsWindowOps => true;

  /// 是否处于多开播放中（含聚集态与折叠态）。小窗等在多开下整体禁用。
  bool get multiPlayActive => false;

  /// 切到后台时**这一路**该不该被暂停——两个设置的生效值，不是设置项本身。
  ///
  /// 交给 `Video` 的 `pauseUponEnteringBackgroundMode` / `resumeUponEnteringForegroundMode`
  /// 之前必须过这一道：media_kit_video 那两个开关是绑在 widget 生命周期上的，开着自动
  /// 暂停时，切后台那一刻就把播放停掉了，「后台播放」整个名存实亡。
  ///
  /// 读的是 Rx 的 `.value`，所以调用点必须在 `Obx` 里面——设置页是压在直播间之上的路由，
  /// 回来的时候若不重建 `Video`，这两个初始参数就还带着旧值。
  bool get pauseOnBackground {
    final settings = AppSettingsController.instance;
    return settings.playerAutoPause.value && !settings.backgroundPlay.value;
  }

  /// 初始化播放器并设置 ao 参数
  Future<void> initializePlayer() async {
    var pp = player.platform as NativePlayer;
    // 设置音频输出驱动
    if (AppSettingsController.instance.customPlayerOutput.value) {
      await pp.setProperty(
        'ao',
        AppSettingsController.instance.audioOutputDriver.value,
      );
    } else if (Platform.isLinux) {
      await pp.setProperty('ao', 'alsa');
    }
    // 音量上限：mpv 默认 130，这里以设置项为准（100 即不放大）
    await pp.setProperty(
      'volume-max',
      AppSettingsController.instance.playerMaxVolume.value.toString(),
    );
    // media_kit 仓库更新导致的问题，临时解决办法
    if (Platform.isAndroid) {
      // 通过错误参数强制media_kit不seek, 解决了加载-pause-seek 在直播流上的开屏问题
      await pp.setProperty('force-seekable', 'yes');
    }
    // 直播缓存策略
    //
    // 根据：https://mpv.io/manual/stable/#cache
    // --cache=<yes|no|auto>          流缓存（前向预读）
    // --cache-secs=<seconds>         预读秒数，直接决定直播延迟
    // --demuxer-max-back-bytes       回退缓存，直播不 seek → 0 省内存
    // --demuxer-seekable-cache=<yes|no|auto>
    // --demuxer-donate-buffer==<yes|no>
    //
    // 注意：`cache` 控制的是前向预读，不是「回放缓存」。设成 no 省不了多少内存，
    // 却会让预读退回 --demuxer-readahead-secs（约 1s），且 mpv 不再上报
    // cache-buffering-state / paused-for-cache，网络抖动时只能硬卡。
    // 内存上限由 media_kit 的 PlayerConfiguration.bufferSize（默认 32MiB）
    // 写入 demuxer-max-bytes 来封顶。
    // hls流/令牌流/.. 根据mdk-sdk作者回复, rtsp 在 ffmpeg存在内存泄露, 这意味着我们只能等待修复
    // temporary fix of android platform
    if (!Platform.isAndroid) {
      await pp.setProperty('cache', 'yes');
      // 低延迟优先：只留 1s 前向预读来吸收抖动，尽量不放大与弹幕的错位。
      await pp.setProperty('cache-secs', '1');
      // media_kit 默认 cache-on-disk=yes，会把流缓存写到磁盘，直播没必要。
      await pp.setProperty('cache-on-disk', 'no');
      // 直播不往回看 → 不要回退缓存
      await pp.setProperty('demuxer-max-back-bytes', '0');
      await pp.setProperty('demuxer-seekable-cache', 'no');
    }
    // 双重缓冲：加大前向预读 + 保留回退缓存（抗抖动 + 允许小幅回看）
    //
    // 注意 `demuxer-max-back-bytes` 缓存的是**已播放**的数据，作用只是允许往回 seek，
    // 本身不会让画面更流畅；抗抖动靠的是上面的 `cache-secs`。
    if (AppSettingsController.instance.videoDoubleBuffering.value) {
      await pp.setProperty('cache', 'yes');
      await pp.setProperty('cache-secs', '3');
      // 上一段已把回退缓存压到 0，这里必须复位，否则「双重缓冲」名不副实。
      await pp.setProperty('demuxer-max-back-bytes', '16777216');
      await pp.setProperty('demuxer-seekable-cache', 'yes');
      await pp.setProperty('demuxer-donate-buffer', 'yes');
      // 不设 demuxer-cache-dir：mpv 文档明确该选项只对 cache-on-disk 生效，而基础分支
      // 已把 cache-on-disk 关掉（磁盘缓存文件是 append-only，直播越久占用越大）。
      // 缓存上限仍由 media_kit 的 bufferSize 写入 demuxer-max-bytes 封顶。
    }
    // bili/douyin流存在时间戳跳变问题
    // 真机建议-空间换内存-暂时不需要
    //  windows:
    //  icc-cache-dir = "~~/cache/icc";
    //  gpu-shader-cache-dir = "~~/cache/shader"
    //  watch-later-dir = "~~/cache/watch_later"
    // NVIDIA RTX VSR 支持 (Windows 平台)
    if (Platform.isWindows &&
        AppSettingsController.instance.enableRtxVsr.value) {
      await pp.setProperty('hwdec', 'd3d11va');
      await pp.setProperty('vf', 'd3d11vpp=scale=2:scaling-mode=nvidia');
    }
    await applyVolumeNormalize();
    if (AppSettingsController.instance.logEnable.value) {
      await logPlayerProperties();
    }
  }

  /// 按设置开关当前播放器的音量均衡滤波链。
  ///
  /// `af` 属性支持运行时修改，mpv 会自动重建音频滤波链，直播中即时生效。
  /// 关闭时写入空串清空滤波链（mpv 自身的软音量不走用户 af 链，不受影响）。
  Future<void> applyVolumeNormalize() async {
    if (player.platform is! NativePlayer) {
      return;
    }
    final pp = player.platform as NativePlayer;
    if (!AppSettingsController.instance.volumeNormalize.value) {
      _volumeNormalizePending = false;
      await pp.setProperty('af', '');
      return;
    }
    // 内核缺滤镜时不再尝试：挂上去必然 af 链初始化失败 → 音频轨道被禁用（静音）。
    if (_volumeNormalizeUnsupported) {
      return;
    }
    _volumeNormalizePending = true;
    await pp.setProperty('af', volumeNormalizeAF());
  }

  /// 把设置里的最大音量下发给播放器的 volume-max，播放中即时生效。
  ///
  /// mpv 对越界的 volume 是拒绝写入而不是夹紧，且调低 volume-max 不会把已有的
  /// volume 拉回来（实测：上限降到 100 后 volume 仍读作 130）。所以下完上限要补写
  /// 一次当前音量——设置侧的 setPlayerMaxVolume 已把它夹进新上限。
  Future<void> applyPlayerMaxVolume() async {
    if (player.platform is! NativePlayer) {
      return;
    }
    final pp = player.platform as NativePlayer;
    await pp.setProperty(
      'volume-max',
      AppSettingsController.instance.playerMaxVolume.value.toString(),
    );
    // 必须走 applyTargetVolume 而不是直接写全局音量：多开时非聚焦格若开了压低，
    // 要按比例压低，直写总音量会把 ducking 冲掉。
    await applyTargetVolume();
  }

  /// 匹配播放器日志，自愈「内核缺滤镜」的情况。
  ///
  /// mpv 挂了不存在的滤镜时，af 链初始化失败会走 error_on_track 直接禁用音频轨道
  /// （player/audio.c 的 "Audio filter initialized failed!"），没有"跳过滤波器继续播"
  /// 的回退，表现就是无声。这里清掉滤波链、标记本会话不再尝试，并让宿主重连恢复声音。
  void checkVolumeNormalizeFailed(PlayerLog event) {
    if (!_volumeNormalizePending ||
        !event.text.contains('Audio filter initialized failed')) {
      return;
    }
    _volumeNormalizePending = false;
    _volumeNormalizeUnsupported = true;
    // 让设置页开关如实反映不可用（只改内存不落盘，换回有滤镜的内核后重启即恢复）。
    AppSettingsController.instance.volumeNormalize.value = false;
    Log.d('音量均衡：内核缺少音频滤镜（af 链初始化失败），自动关闭');
    Future(() async {
      if (player.platform is NativePlayer) {
        await (player.platform as NativePlayer).setProperty('af', '');
      }
      SmartDialog.showToast('音量均衡不可用：播放内核未编译音频滤镜，已自动关闭并重连');
      onVolumeNormalizeUnavailable();
    });
  }

  /// 音量均衡滤波链初始化失败且已清理后的回调。
  ///
  /// af 链失败时 mpv 已通过 error_on_track 禁用音频轨道，仅清掉 `af` 不会自动恢复
  /// 出声，宿主需要重连当前线路（重新拉流）。
  void onVolumeNormalizeUnavailable() {}

  /// 回读 mpv 属性并写入日志（仅在「日志」开关打开时调用）。
  ///
  /// 用途：确认 [initializePlayer] 里的 `setProperty` 是否真的生效——由于
  /// media_kit 丢弃了 mpv 的返回码，设置失败是静默的。输出的每一行格式为
  /// `属性名 = 实际值`，`<空>` 表示 mpv 不认识该属性或当前取不到值。
  ///
  /// 只在起播前采集一次：此时 mpv 还没打开媒体，运行时统计类属性本来就没有值，
  /// 那些数字请看 OSD 浮层。
  Future<void> logPlayerProperties() async {
    if (player.platform is! NativePlayer) {
      return;
    }
    final pp = player.platform as NativePlayer;
    final lines = <String>[
      'mpv 属性回读 platform=${Platform.operatingSystem} '
          'doubleBuffering=${AppSettingsController.instance.videoDoubleBuffering.value}',
    ];
    for (final name in _kPlayerConfigProps) {
      var value = '';
      try {
        value = await pp.getProperty(name);
      } catch (e) {
        value = '<读取异常: $e>';
      }
      lines.add('  $name = ${value.isEmpty ? '<空>' : value}');
    }
    Log.d(lines.join('\n'));
  }

  /// 视频控制器
  late final videoController = VideoController(
    player,
    configuration: AppSettingsController.instance.customPlayerOutput.value
        ? VideoControllerConfiguration(
            vo: AppSettingsController.instance.videoOutputDriver.value,
            hwdec: AppSettingsController.instance.videoHardwareDecoder.value,
          )
        : AppSettingsController.instance.playerCompatMode.value
            ? const VideoControllerConfiguration(
                vo: 'mediacodec_embed',
                hwdec: 'mediacodec',
              )
            : VideoControllerConfiguration(
                enableHardwareAcceleration: AppSettingsController.instance.hardwareDecode.value,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
  );
}
mixin PlayerStateMixin on PlayerMixin {
  ///音量控制条计时器
  Timer? hidevolumeTimer;

  /// 是否进入桌面端小窗
  RxBool smallWindowState = false.obs;

  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;

  /// 是否处于窗口最大化状态
  RxBool windowMaxState = false.obs;

  /// 显示手势Tip
  RxBool showGestureTip = false.obs;

  /// 手势Tip文本
  RxString gestureTipText = "".obs;

  /// 显示提示底部Tip
  RxBool showBottomTip = false.obs;

  /// 是否显示OSD统计信息（应用自绘浮层）
  RxBool showOSDStats = false.obs;

  /// mpv 内置 OSD（stats.lua）是否已开
  RxBool showMPVOSDStats = false.obs;

  /// Stats 覆盖层当前是否可见（按设置里的后端解释，供播放信息里的开关显示）
  bool get osdStatsVisible =>
      AppSettingsController.instance.osdBackend.value == "mpv"
          ? showMPVOSDStats.value
          : showOSDStats.value;

  /// 提示底部Tip文本
  RxString bottomTipText = "".obs;

  /// 自动隐藏控制器计时器
  Timer? hideControlsTimer;

  /// 自动隐藏提示计时器
  Timer? hideSeekTipTimer;

  /// 是否为竖屏直播间
  var isVertical = false.obs;

  Widget? danmakuView;

  var showQualites = false.obs;
  var showLines = false.obs;

  /// 隐藏控制器
  void hideControls() {
    showControlsState.value = false;
    hideControlsTimer?.cancel();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    resetHideControlsTimer();
  }

  /// 开始隐藏控制器计时
  /// - 当点击控制器上时功能时需要重新计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();

    hideControlsTimer = Timer(
      const Duration(
        seconds: 5,
      ),
      hideControls,
    );
  }

  void updateScaleMode() {
    final resolved = resolvePlayerFit(effectiveScaleModeForFit());
    // update() 的 aspectRatio 是 copyWith 语义：null 表示「维持旧值」而不是「解锁」。
    // 从 16:9/4:3/自定义 切回 适应/拉伸/铺满 时必须把流原始比例传回去才能顶掉锁定
    // （与原内联实现一致；null 只在 Video 构造参数那一路才等于自动比例）。
    final aspectRatio = resolved.aspectRatio ??
        (player.state.width != null && player.state.height != null
            ? player.state.width! / player.state.height!
            : null);
    globalPlayerKey.currentState?.update(
      aspectRatio: aspectRatio,
      fit: resolved.fit,
    );
  }

  /// 本实例该用哪个 scaleMode 算 fit：`LiveRoomController` 覆写成「按格覆盖优先」。
  /// 基类（非直播间控制器）就读全局。
  int effectiveScaleModeForFit() => AppSettingsController.instance.scaleMode.value;
}
mixin PlayerDanmakuMixin on PlayerStateMixin {
  /// 弹幕控制器
  late DanmakuController? danmakuController;

  /// 强制指定的弹幕字号（逻辑像素）。
  ///
  /// 单开时为 null：`buildDanmuView` 沿用「按整窗高度缩放」那套口径
  /// （`danmakuFontClamped` / `danmakuFontResize` / `danmuSize`）。
  /// 多开时每格高度都不同，整窗口径对不上格子，由 `MultiPlaySession`
  /// 按格子实际高度算好写进来。
  double? danmakuFontSizeOverride;

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
  }

  /// 设置按格字号并即时生效（弹幕控制器还没建时只记下 override，建的时候会用到）。
  void applyDanmakuFontSize(double fontSize) {
    if (danmakuFontSizeOverride == fontSize) {
      return;
    }
    danmakuFontSizeOverride = fontSize;
    final option = danmakuController?.option;
    if (option != null) {
      updateDanmuOption(option.copyWith(fontSize: fontSize));
    }
  }

  /// 「按整窗高度缩放」那套字号口径。
  ///
  /// 单开时 `buildDanmuView` 用它，`WindowService.danmakuFontClamped` 广播的
  /// `kUpdateDanmaku` 也是这个值；多开时被 [danmakuFontSizeOverride] 顶掉。
  double resolveWindowScaledDanmakuFontSize() {
    final settings = AppSettingsController.instance;
    return settings.danmakuFontClamped.value
        ? settings.danmakuFontResize
        : settings.danmuSize.value;
  }

  /// 清掉按格字号，回到整窗口径（退出多开时用）。
  void clearDanmakuFontSizeOverride() {
    if (danmakuFontSizeOverride == null) {
      return;
    }
    danmakuFontSizeOverride = null;
    final option = danmakuController?.option;
    if (option != null) {
      updateDanmuOption(option.copyWith(fontSize: resolveWindowScaledDanmakuFontSize()));
    }
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (option == null) return;
    danmakuController?.updateOption(option);
  }

  void disposeDanmakuController() {
    danmakuController?.clear();
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value) {
      return;
    }
    for (var item in items) {
      danmakuController?.addDanmaku(item);
      _applyDanmakuEmoticon(item);
    }
  }

  /// 表情包弹幕的渲染接管。
  ///
  /// 弹幕库只认纯文本，这里用它公开的 [DanmakuController] 接口做后置替换：
  /// 先让库按占位符文本入轨，等图片取回后再把该条的位图换成「文本 + 表情」的
  /// 行内混排版本，并把该 [DanmakuItem] 的宽高改写成位图尺寸。
  ///
  /// 已知限制：库的滚动轨道是等高网格、排轨只看入轨时的文本宽高，改写尺寸后
  /// 不会重排。行内小表情与占位符文本尺寸接近、看不出来；大表情
  /// （[LiveMessageEmoticon.large]）比占位符文本宽高都大，会与同轨 / 相邻轨的
  /// 弹幕重叠——这是接受了的取舍，真要让位得改 canvas_danmaku 的排轨。
  ///
  /// 取图失败 / 弹幕已过期时直接放弃替换 —— 库渲染的占位符文本就是兜底表现，
  /// 不会出现空白弹幕。
  void _applyDanmakuEmoticon(DanmakuContentItem item) {
    final extra = item.extra;
    if (!DanmakuEmoticonRenderer.canRender(extra)) {
      return;
    }
    final controller = danmakuController;
    if (controller == null) {
      return;
    }
    unawaited(DanmakuEmoticonRenderer.apply(
      controller: controller,
      content: item,
      emoticons: extra as List<LiveMessageEmoticon>,
    ));
  }
}
mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  final VolumeController volumeController = VolumeController.instance;
  final pip = Floating();
  StreamSubscription<PiPStatus>? _pipSubscription;

  /// 初始化一些系统状态
  void initSystem() async {
    if (Platform.isAndroid || Platform.isIOS) {
      volumeController.showSystemUI = false;
    }

    // 屏幕常亮不在这里开：它跟着「这一路在不在播」走，由直播间的
    // ScreenAwakeService 按路持有（多开引用计数），播放器只负责出声画。

    // 开始隐藏计时
    resetHideControlsTimer();
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    _pipSubscription?.cancel();
    //pip.dispose();
    // 若此前处于全屏（系统栏被隐藏），恢复显示时同样需要等待平台重新上报
    if (fullScreenState.value) {
      SystemUiBottomInset.markRestoring();
    }
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    await setPortraitOrientation();
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // 亮度重置,桌面平台可能会报错,暂时不处理桌面平台的亮度
      try {
        await ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (e) {
        Log.logPrint(e);
      }
    }
  }

  /// 进入全屏
  void enterFullScreen() async {
    fullScreenState.value = true;
    if (Platform.isAndroid || Platform.isIOS) {
      //全屏
      SystemUiBottomInset.markHidden();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      if (!isVertical.value) {
        //横屏
        setLandscapeOrientation();
      }
    } else {
      // todo: animation isn't smooth...
      // fix: pip->full->normal bug
      // 不再考虑从什么状态切换，逻辑混乱，而是确定窗口状态直接设置属性
      // 记忆进入全屏前的状态（几何 + 最大化标记），退出全屏时消费。
      // 此刻窗口仍在窗口态，采到的才是「退出全屏要落回去的那个」尺寸；
      // 小窗→全屏这条路径上离开窗口态那一刻已经采过，这里不会重复覆盖。
      await _captureNormalGeometry();
      smallWindowState.value = false; // no pip
      WindowService.instance.isPIP = smallWindowState.value;
      // 小窗→全屏：先释放纵横比约束，后全屏（次序铁律）
      if (WindowService.instance.pipAspectLocked) {
        await WindowService.instance.releasePipAspect();
      }
      await WindowService.instance.restoreNormalMinimumSize();
      _unbindPipAspectListener();
      await windowManager.setFullScreen(true); // in full
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden); // no title
      await WindowService.instance.danmakuFontClamped();
      await windowManager.setAlwaysOnTop(false);
    }
    //danmakuController?.clear();
  }

  /// 退出全屏
  void exitFull() async {
    // todo: 还应该关闭所有的dialog
    SmartDialog.dismiss();
    // 小窗态下 fullScreenState 同样为 true，双击/ESC/返回键都会汇入本方法。
    // 小窗清理（置顶、纵横比锁定、最小尺寸、isPIP）只在 exitSmallWindow 里，
    // 直接走下面的全屏分支会把这些状态残留下来，故此处整单转交。
    if (smallWindowState.value) {
      await exitSmallWindow();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      // 系统栏即将恢复：若设备不再上报恢复后的 inset，用进全屏前的高度兜底
      SystemUiBottomInset.markRestoring();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values);
      setPortraitOrientation();
    } else {
      // 退回原来的大小
      if (windowMaxState.value) {
        // 最大化这条臂的次序与改造前逐字一致（maximize → 不 await 的退全屏）：
        // C++ 的退全屏在 IsZoomed 为真时只刷新边框、按 g_maximized_before_fullscreen
        // 补一次 SC_MAXIMIZE，不回弹摆放，所以没有下面那条竞态。
        await windowManager.maximize();
        windowManager.setFullScreen(false);
      } else {
        // 退 OS 全屏必须排在还原**之前**（原先是反的，正是「小窗→全屏→双击退出」
        // 掉进一块小窗尺寸的窗口态、既不在小窗也不在全屏的原因）：
        //
        // window_manager 0.5.2 的 Windows 实现里，`setFullScreen(false)` 自己就会把
        // 窗口摆回「进全屏那一刻」的外框（C++ 的 `g_frame_before_fullscreen`）。而
        // 从小窗进全屏时 OS 窗口一直停在小窗外框——`enterFullScreen` 只把 Dart 侧的
        // `smallWindowState` 翻成 false，没碰几何——所以那份「全屏前外框」就是小窗
        // 矩形。还原点若抢在它前面落，就被这次回弹整个顶掉：两个旗标都已是 false
        // （UI 已经是窗口化），窗口却停在几百 px 的小框里。
        //
        // 这里必须 await：不 await 它就排到后面几笔之后才落地，等于什么都没改。
        await windowManager.setFullScreen(false);
        // 只在非最大化时显式还原（进全屏前若是最大化态，上面那条臂才是正解，
        // 那时紧跟 setSize 反而会把最大化顶掉）。
        //
        // 落在这段时 OS 已退出全屏，setSize/setPosition 是本臂最后一笔摆窗，不
        // 会被谁顶掉。口径也对得上：`getSize`/`setPosition` 走 GetWindowRect、
        // `setSize` 走 SetWindowPos，两边都是**外框**，所以还原点原样落回；
        // 随后 setTitleBarStyle(normal) 只带 SWP_NOSIZE|SWP_FRAMECHANGED，外框
        // 不变、让出去的是客户区，与「没进过小窗的正常窗口态」完全一致。
        // （反过来把退全屏放后面就是原来的 bug：那笔不 await 的回弹排在还原之后
        // 落地，外框被改回小窗矩形。）
        if (_lastWindowSize != null) {
          await windowManager.setSize(_lastWindowSize!);
        }
        if (_lastWindowPosition != null) {
          await windowManager.setPosition(_lastWindowPosition!);
        }
      }
      Log.d('last_window_size:${_lastWindowSize?.width}__${_lastWindowSize?.height}');
      Log.d('last_window_position:${_lastWindowPosition?.dx}__${_lastWindowPosition?.dy}');
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
      _consumeNormalGeometry();
      await WindowService.instance.danmakuFontClamped();
    }
    fullScreenState.value = false;
    //danmakuController?.clear();
  }

  Size? _lastWindowSize;
  Offset? _lastWindowPosition;

  /// 采还原点时窗口是否处于最大化（`_lastWindowSize/_lastWindowPosition` 存的是它的
  /// 「还原态」矩形，见 `_captureNormalGeometry`）。退出小窗据此重新最大化；不能读
  /// `windowMaxState` 那个 Rx——进小窗时的 `unmaximize()` 会经 `onWindowUnmaximize`
  /// 把它清掉。
  bool _lastWindowMaximized = false;

  /// 窗口态（非全屏、非小窗）的几何，用于退出全屏/小窗时还原。
  ///
  /// 「谁先离开窗口态谁捕获」：原先只有 `enterSmallWindow` 写这两个字段，
  /// 于是从全屏进小窗时记下来的是满屏几何，退出小窗后窗口停在满屏大小——
  /// 这就是全屏里那颗「小窗播放」按钮原来不敢放的原因。
  bool _normalGeometryCaptured = false;

  Future<void> _captureNormalGeometry() async {
    // 只有「控制器认为自己已经回到窗口态」时才允许重采。
    // 这道守卫仍是必要的：OS 侧还有一条不经过本控制器的退全屏（用户在窗口管理器
    // 层面退掉，或系统栏/任务栏那类外部动作），那时标志与 fullScreenState 都停在
    // true——暴露的是**一代过期**：ghost 全屏期间若改过窗口大小，下一次进全屏的
    // re-capture 会被这道守卫挡掉，还原点仍是改大小之前那份。
    // 不会永久卡死：exitFull 与 exitSmallWindow 两个消费点都会把标志清回 false，
    // 走过任意一条正常退出路径后重采就恢复。
    // （鼠标第四键原先正是这条绕过路径；现已与 Esc 同源，补发 kEscapePressed 交回
    // exitFull，见 main.dart。）
    if (_normalGeometryCaptured &&
        (fullScreenState.value || smallWindowState.value)) {
      return;
    }
    // 先抢占标志、后 await 赋值：标志若在三段 await 之后才置 true，
    // 快速连点两次转换会双双越过守卫，把满屏矩形当成还原点采进去。
    _normalGeometryCaptured = true;
    final maximized = await windowManager.isMaximized();
    // 还原点必须是「窗口化态」的几何。Windows 最大化态下 getSize()/getPosition()
    // 返回的是铺满工作区的最大化矩形（边还伸到屏外），拿它当还原点，退出小窗/全屏的
    // setSize/setPosition 会把窗口顶成越屏大窗；改用 rcNormalPosition（还原态矩形）。
    final normal = maximized ? WindowService.instance.normalBounds() : null;
    if (normal != null) {
      _lastWindowSize = normal.size;
      _lastWindowPosition = normal.topLeft;
    } else {
      _lastWindowSize = await windowManager.getSize();
      _lastWindowPosition = await windowManager.getPosition();
    }
    _lastWindowMaximized = maximized;
    windowMaxState.value = maximized;
  }

  /// 退出到窗口态时消费还原点，下一次进全屏重新采。
  void _consumeNormalGeometry() {
    _normalGeometryCaptured = false;
    _lastWindowMaximized = false;
  }

  /// 当前应锁定的「widget 实际显示比例」（与 buildMediaPlayer 的 scaleMode 语义一致）。
  ///
  /// 走 `effectiveScaleModeForFit()` 而不是直读全局：PiP 锁定的必须正是画面上
  /// 在播的比例；`LiveRoomController` 会把它覆写成「按格覆盖优先」，读全局时
  /// 带着按格覆盖进小窗会锁错外框（与 `tileAspect()`/`updateScaleMode` 同一口径）。
  double _currentDisplayAspect() => PipAspectCalculator.resolveDisplayAspect(
        scaleMode: effectiveScaleModeForFit(),
        aspectByUser: AppSettingsController.instance.aspectByUser.value,
        videoWidth: player.state.width?.toDouble(),
        videoHeight: player.state.height?.toDouble(),
      );

  /// 视频尺寸监听（换线路/清晰度导致比例变化）
  StreamSubscription<int?>? _pipWidthSub;
  StreamSubscription<int?>? _pipHeightSub;
  Timer? _pipDebounce;

  void _bindPipAspectListener() {
    _unbindPipAspectListener();
    _pipWidthSub = player.stream.width.listen((_) => _onVideoSizeChanged());
    _pipHeightSub = player.stream.height.listen((_) => _onVideoSizeChanged());
  }

  void _unbindPipAspectListener() {
    _pipWidthSub?.cancel();
    _pipHeightSub?.cancel();
    _pipWidthSub = null;
    _pipHeightSub = null;
    _pipDebounce?.cancel();
    _pipDebounce = null;
  }

  /// 视频比例变化：300ms 去抖后重新施加锁定（保持当前外框宽，按新比例重算外框高）。
  void _onVideoSizeChanged() {
    if (!WindowService.instance.pipAspectLocked) return;
    _pipDebounce?.cancel();
    _pipDebounce = Timer(const Duration(milliseconds: 300), () {
      WindowService.instance.reapplyPipAspect(_currentDisplayAspect());
    });
  }

  ///小窗模式()
  void enterSmallWindow() async {
    if (multiPlayActive) {
      // 多路没有单一宽高比可锁，小窗语义不成立；四格同时改窗口尺寸/置顶只会互相打架。
      SmartDialog.showToast("多开播放中不支持小窗，请先关掉其余几路");
      return;
    }
    if (!(Platform.isAndroid || Platform.isIOS)) {
      final wasFullScreen = fullScreenState.value;
      // 还原点在离开窗口态那一刻采（全屏或小窗），退出时消费。
      await _captureNormalGeometry();
      fullScreenState.value = true;
      smallWindowState.value = true;
      // 进入小窗会自动恢复默认弹幕大小
      // 从 OS 全屏进小窗必须先退全屏：`setFullScreen(true)` 期间 setSize 会被
      // 全屏的窗口样式吃掉，收不成小窗；最大化态同理会顶住目标尺寸。
      if (wasFullScreen) {
        await windowManager.setFullScreen(false);
      }
      // 判据取采集到的 windowMaxState 而不是 wasFullScreen：
      // 「最大化 → 直接进小窗」全程没经过全屏，但最大化窗口同样会被工作区顶住
      // 目标尺寸，setSize 收不成小窗。
      // 必须排在退 OS 全屏之后：Windows 上 setFullScreen(false) 会自行回弹到进全屏前
      // 的摆放（可能就是最大化态），先 unmaximize 会被它再顶回去。
      if (windowMaxState.value) {
        await windowManager.unmaximize();
      }
      // WHY：isPIP 要晚于上面两次 OS 窗口操作再置位。退全屏 / 取消最大化会派发
      // onWindowResized/onWindowMoved，WindowService.windowStateChanged 只要看到
      // isPIP 为真，就把那一刻「回落中的窗口外框」（典型 1280×720）连同位置写进
      // 小窗记忆偏好 windowPipWidth/Height/X/Y；而本次真正读这几项是在下面
      // setTitleBarStyle / applyPipAspect 的 await 之后，竞速结果多半是偏好已被写脏，
      // 于是小窗按窗口尺寸开成 oversized，且脏值持久化，之后不经全屏进小窗也会开大。
      // 反过来，从这里开始的 setTitleBarStyle(hidden)/applyPipAspect/setSize 期间
      // isPIP 必须为真——那几次落盘的才是真正该记的小窗几何。
      WindowService.instance.isPIP = smallWindowState.value;
      Log.d('last_window_size:${_lastWindowSize?.width}__${_lastWindowSize?.height}');
      Log.d('last_window_position:${_lastWindowPosition?.dx}__${_lastWindowPosition?.dy}');
      // 翻转 Q5：必须先 await 让平台侧「隐藏标题栏」样式就绪，随后 measureFrameInsets
      // 才能采到隐藏态的真实客户区（win32 读平台实时状态，与视图 metrics 解耦）。
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      var px = AppSettingsController.instance.windowPipX.value;
      var py = AppSettingsController.instance.windowPipY.value;

      if (WindowService.instance.pipAspectWanted) {
        // 小窗锁定画面比例：先施加约束（含归一化尺寸），后设位置。
        // 次序铁律：先约束、后设尺寸（applyPipAspect 内部完成）。
        await WindowService.instance.applyPipAspect(_currentDisplayAspect());
        windowManager.setPosition(Offset(px, py));
        _bindPipAspectListener();
      } else {
        // 旧逻辑：按记忆小窗尺寸（保持横/竖屏对调）
        // 与锁定分支同理「先降下限、后设尺寸」，普通态 436 下限会顶大记忆尺寸
        await WindowService.instance.setPipFloorMinimumSize();
        var width = player.state.width ?? 16;
        var height = player.state.height ?? 9;
        var pWidth = AppSettingsController.instance.windowPipWidth.value;
        var pHeight = AppSettingsController.instance.windowPipHeight.value;
        // 横屏还是竖屏
        if (height < width) {
          windowManager.setSize(Size(pWidth, pHeight));
        } else {
          windowManager.setSize(Size(pHeight, pWidth));
        }
        windowManager.setPosition(Offset(px, py));
      }

      windowManager.setAlwaysOnTop(true);
    }
  }

  ///退出小窗模式()
  Future<void> exitSmallWindow() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      fullScreenState.value = false;
      smallWindowState.value = false;
      WindowService.instance.isPIP = smallWindowState.value;
      // 先释放约束，后恢复尺寸/位置（次序铁律）
      if (WindowService.instance.pipAspectLocked) {
        await WindowService.instance.releasePipAspect();
      }
      await WindowService.instance.restoreNormalMinimumSize();
      _unbindPipAspectListener();
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
      if (_lastWindowSize != null) {
        windowManager.setSize(_lastWindowSize!);
      }
      if (_lastWindowPosition != null) {
        windowManager.setPosition(_lastWindowPosition!);
      }
      // 进小窗前是最大化：先铺回还原态矩形、再重新最大化（与 exitFull 的最大化臂同一
      // 口径）。次序不能反——SC_MAXIMIZE 会把当前矩形记成系统的还原记忆，直接从 PiP
      // 小尺寸最大化的话，下次取消最大化会落回小窗尺寸。
      if (_lastWindowMaximized) {
        await windowManager.maximize();
      }
      windowManager.setAlwaysOnTop(false);
      _consumeNormalGeometry();
      //windowManager.setAlignment(Alignment.center);
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    if (await beforeIOS16()) {
      AutoOrientation.landscapeAutoMode();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    if (await beforeIOS16()) {
      AutoOrientation.portraitAutoMode();
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// 是否是IOS16以下
  Future<bool> beforeIOS16() async {
    if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      var version = info.systemVersion;
      var versionInt = int.tryParse(version.split('.').first) ?? 0;
      return versionInt < 16;
    } else {
      return false;
    }
  }

  Future saveScreenshot() async {
    final imageSaver = ImageGallerySaver();
    try {
      SmartDialog.showLoading(msg: "正在保存截图");
      //检查相册权限,仅iOS需要
      var permission = await Utils.checkPhotoPermission();
      if (!permission) {
        SmartDialog.showToast("没有相册权限");
        SmartDialog.dismiss(status: SmartStatus.loading);
        return;
      }

      var imageData = await player.screenshot();
      if (imageData == null) {
        SmartDialog.showToast("截图失败,数据为空");
        SmartDialog.dismiss(status: SmartStatus.loading);
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        await imageSaver.saveImage(
          imageData,
        );
        SmartDialog.showToast("已保存截图至相册");
      } else {
        //全屏下先退出全屏，避免原生文件对话框被全屏窗口遮挡
        if (fullScreenState.value) {
          exitFull();
        }
        //选择保存文件夹
        var path = await FilePicker.saveFile(
          allowedExtensions: ["jpg"],
          type: FileType.image,
          fileName: "${DateTime.now().millisecondsSinceEpoch}.jpg",
        );
        if (path == null) {
          SmartDialog.showToast("取消保存");
          SmartDialog.dismiss(status: SmartStatus.loading);
          return;
        }
        var file = File(path);
        await file.writeAsBytes(imageData);
        SmartDialog.showToast("已保存截图至${file.path}");
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("截图失败");
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  /// 开启小窗播放前弹幕状态
  bool danmakuStateBeforePIP = false;

  Future enablePIP() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (multiPlayActive) {
      // Android 的 PiP 只认一路纹理（`live_room_page.dart` 的 `PiPSwitcher`
      // 在启用态直接换成单画面 `buildMediaPlayer()`），多开下进 PiP 等于把另外
      // 几路悄悄扔掉却还在解码出声。与桌面 `enterSmallWindow` 同一口径拒绝。
      SmartDialog.showToast("多开播放中不支持小窗，请先关掉其余几路");
      return;
    }
    if (await pip.isPipAvailable == false) {
      SmartDialog.showToast("设备不支持小窗播放");
      return;
    }
    danmakuStateBeforePIP = showDanmakuState.value;
    //关闭并清除弹幕
    if (AppSettingsController.instance.pipHideDanmu.value && danmakuStateBeforePIP) {
      showDanmakuState.value = false;
    }
    danmakuController?.clear();
    //关闭控制器
    showControlsState.value = false;

    //监听事件
    var width = player.state.width ?? 0;
    var height = player.state.height ?? 0;
    Rational ratio = const Rational.landscape();
    if (height > width) {
      ratio = const Rational.vertical();
    } else {
      ratio = const Rational.landscape();
    }
    await pip.enable(
      ImmediatePiP(
        aspectRatio: ratio,
      ),
    );

    _pipSubscription ??= pip.pipStatusStream.listen((event) {
      if (event == PiPStatus.disabled) {
        // 返回前台时恢复弹幕
        danmakuController?.resume();
        showDanmakuState.value = danmakuStateBeforePIP;
      }
      Log.w(event.toString());
    });
  }
}
mixin PlayerGestureControlMixin on PlayerStateMixin, PlayerMixin, PlayerSystemMixin {
  /// 单击显示/隐藏控制器
  void onTap() {
    if (showControlsState.value) {
      hideControls();
    } else {
      showControls();
    }
  }

  //桌面端操控
  void onEnter(PointerEnterEvent event) {
    if (!showControlsState.value) {
      showControls();
    }
  }

  void onExit(PointerExitEvent event) {
    if (showControlsState.value) {
      hideControls();
    }
  }

  void onHover(PointerHoverEvent event, BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final targetPosition = screenHeight * 0.25; // 计算屏幕顶部25%的位置
    if (event.position.dy <= targetPosition || event.position.dy >= targetPosition * 3) {
      if (!showControlsState.value) {
        showControls();
      }
    }
  }

  /// 双击全屏/退出全屏
  void onDoubleTap(TapDownDetails details) {
    if (lockControlsState.value) {
      return;
    }
    if (fullScreenState.value) {
      exitFull();
    } else {
      enterFullScreen();
    }
  }

  bool verticalDragging = false;
  bool leftVerticalDrag = false;
  var _currentVolume = 0.0;
  var _currentBrightness = 1.0;
  var verStartPosition = 0.0;

  DelayedThrottle? throttle;

  /// 竖向手势开始
  void onVerticalDragStart(DragStartDetails details) async {
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    if (AppSettingsController.instance.verticalDragLock.value) {
      return;
    }
    final dy = details.globalPosition.dy;
    // 开始位置必须是中间2/4的位置
    if (dy < Get.height * 0.25 || dy > Get.height * 0.75) {
      return;
    }

    verStartPosition = dy;
    leftVerticalDrag = details.globalPosition.dx < Get.width / 2;

    throttle = DelayedThrottle(200);

    verticalDragging = true;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      showGestureTip.value = true;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _currentVolume = await volumeController.getVolume();
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _currentBrightness = await ScreenBrightnessPlatform.instance.application;
    }
  }

  /// 竖向手势更新
  void onVerticalDragUpdate(DragUpdateDetails e) async {
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    // todo: lockControls 可以临时解锁，滑动结束后再次上锁，让ai来做这些简单的工作
    if (AppSettingsController.instance.verticalDragLock.value) {
      return;
    }
    if (verticalDragging == false) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    //String text = "";
    //double value = 0.0;

    Log.logPrint("$verStartPosition/${e.globalPosition.dy}");

    if (leftVerticalDrag) {
      setGestureBrightness(e.globalPosition.dy);
    } else {
      setGestureVolume(e.globalPosition.dy);
    }
  }

  int lastVolume = -1; // it's ok to be -1

  void setGestureVolume(double dy) {
    double value = 0.0;
    double seek;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      seek = _currentVolume - value;
      if (seek < 0) {
        seek = 0;
      }
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      seek = value.abs() + _currentVolume;
      if (seek > 1) {
        seek = 1;
      }
    }
    int volume = _convertVolume((seek * 100).round());
    if (volume == lastVolume) {
      return;
    }
    lastVolume = volume;
    // update UI outside throttle to make it more fluent
    gestureTipText.value = "音量 $volume%";
    throttle?.invoke(() async => await _realSetVolume(volume));
  }

  // 0 to 100, 5 step each
  int _convertVolume(int volume) {
    return (volume / 5).round() * 5;
  }

  Future _realSetVolume(int volume) async {
    Log.logPrint(volume);
    volumeController.setVolume(volume / 100);
  }

  void setGestureBrightness(double dy) {
    double value = 0.0;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      var seek = _currentBrightness - value;
      if (seek < 0) {
        seek = 0;
      }
      ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(seek);

      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
      Log.logPrint(value);
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      var seek = value.abs() + _currentBrightness;
      if (seek > 1) {
        seek = 1;
      }

      ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(seek);
      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
      Log.logPrint(value);
    }
  }

  /// 竖向手势完成
  void onVerticalDragEnd(DragEndDetails details) async {
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    if (AppSettingsController.instance.verticalDragLock.value) {
      return;
    }
    throttle = null;
    verticalDragging = false;
    leftVerticalDrag = false;
    showGestureTip.value = false;
  }
}

class PlayerController extends BaseController
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin, PlayerGestureControlMixin {
  @override
  void onInit() {
    initSystem();
    initStream();
    //设置音量
    applyTargetVolume();
    super.onInit();
  }

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _escSubscription;
  StreamSubscription? _volumeNormalizeSubscription;
  StreamSubscription? _playerMaxVolumeSubscription;
  StreamSubscription? _osdBackendSubscription;

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.d("播放器错误：$event");
      // 跳过无音频输出的错误
      // Could not open/initialize audio device -> no sound.
      if (event.contains('no sound.')) {
        return;
      }
      //SmartDialog.showToast(event);
      mediaError(event);
    });

    _playingSubscription = player.stream.playing.listen((event) {
      if (event) {
        // 起播成功说明本次挂载的 af 链存活，结束「等待挂载结果」窗口。
        // 否则 pending 永久为 true，之后任何一条 af 失败日志（如流中途
        // 重建滤波链失败）都会被误判成内核缺滤镜而永久禁用均衡。
        _volumeNormalizePending = false;
        // 屏幕常亮由直播间控制器的 ScreenAwakeService 持有，播放器不直接碰。
        Log.d("Playing");
      }
    });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        mediaEnd();
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      Log.d("播放器日志：$event");
      checkVolumeNormalizeFailed(event);
    });
    _widthSubscription = player.stream.width.listen((event) {
      Log.d('width:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      if (player.state.width == null) {
        return;
      } else {
        // 可获取直播流size时且不为全屏模式时判断是否进入全屏模式
        isVertical.value = player.state.height! > player.state.width!;
        if (allowsWindowOps && AppSettingsController.instance.autoFullScreen.value && !fullScreenState.value) {
          enterFullScreen();
        }
      }
    });
    _heightSubscription = player.stream.height.listen((event) {
      Log.d('height:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      isVertical.value = (player.state.height ?? 9) > (player.state.width ?? 16);
    });
    // Esc 是窗口级操作：多开时四路都订阅会让一次 Esc 在每一格上都退一次全屏
    if (allowsWindowOps) {
      _escSubscription = EventBus.instance.listen(EventBus.kEscapePressed, (event) {
        exitFull();
      });
    }
    _volumeNormalizeSubscription = EventBus.instance.listen(
      EventBus.kVolumeNormalizeChanged,
      (event) {
        applyVolumeNormalize();
      },
    );
    _playerMaxVolumeSubscription = EventBus.instance.listen(
      EventBus.kPlayerMaxVolumeChanged,
      (event) {
        applyPlayerMaxVolume();
      },
    );
    // OSD 是页面级的东西，只有主格需要收尾；多开时四格都订阅会让一次切换
// 触发 4 次探测（缺 Lua 时还会弹 4 条回退提示）。
    if (allowsWindowOps) {
      _osdBackendSubscription = EventBus.instance.listen(
        EventBus.kOSDBackendChanged,
        (event) async {
          // 换后端时给旧的收尾：切到 mpv 先关掉自绘浮层（内核缺 Lua 则回退并提示）；
          // 切回自绘则关掉 mpv 的 OSD。
          if (AppSettingsController.instance.osdBackend.value == "mpv") {
            showOSDStats.value = false;
            if (!await mpvOSDAvailable()) {
              fallbackToAppOSD(showStats: false);
            }
            return;
          }
          if (showMPVOSDStats.value) {
            showMPVOSDStats.value = false;
            if (player.platform is NativePlayer) {
              unawaited(
                (player.platform as NativePlayer).command(
                  ["script-binding", "stats/display-page-1-toggle"],
                ),
              );
            }
          }
        },
      );
    }
  }

  void disposeStream() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _logSubscription?.cancel();
    _pipSubscription?.cancel();
    _playingSubscription?.cancel();
    _escSubscription?.cancel();
    _volumeNormalizeSubscription?.cancel();
    _playerMaxVolumeSubscription?.cancel();
    _osdBackendSubscription?.cancel();
  }

  /// 播放结束（EOS）钩子。宿主（直播间控制器）覆写它做断线自愈。
  ///
  /// 这里**不**碰屏幕常亮：EOS 之后往往还有重连/换线路，旧实现在这里 disable
  /// 会把常亮灭在自愈的空窗里（弱网时足以让系统熄屏）。常亮归直播间的
  /// [ScreenAwakeService] 按路持有，断线不释放、终态才释放。
  void mediaEnd() {}

  void mediaError(String error) {
    // 播放失败只做弱网提示与自愈（宿主 mediaError 覆写）；屏幕常亮不在此处释放，
    // 重试/换线路期间用户还在看着这一路（见 ScreenAwakeService）。
  }

  /// 探测播放内核能否跑 mpv 内置 OSD（stats.lua 需要内核编入 Lua）。
  ///
  /// media_kit 的 `command()`/`setProperty()` 都丢弃 mpv 返回值，没法靠报错判断
  /// binding 是否存在；改用只读属性 `mpv-configuration`（mpv 的编译配置串）探测：
  /// 出现 `lua=disabled`（或读不到）即视为不可用。Lua 有无是编译期属性，缓存结果。
  Future<bool> mpvOSDAvailable() async {
    if (_mpvLuaSupported != null) {
      return _mpvLuaSupported!;
    }
    if (player.platform is! NativePlayer) {
      return false;
    }
    final config = await (player.platform as NativePlayer).getProperty('mpv-configuration');
    _mpvLuaSupported = config.isNotEmpty && !config.contains('lua=disabled');
    return _mpvLuaSupported!;
  }

  /// mpv 内置 OSD 不可用时回退到应用自绘。
  /// 与音量均衡自愈一致：只改内存不落盘，换回带 Lua 的内核后重启即恢复。
  void fallbackToAppOSD({required bool showStats}) {
    showMPVOSDStats.value = false;
    AppSettingsController.instance.osdBackend.value = "app";
    Log.d('Stats 覆盖层：内核未编入 Lua，mpv 内置 OSD 不可用，已回退应用自绘');
    SmartDialog.showToast('mpv 内置 OSD 不可用：内核未编入 Lua，已改用应用自绘');
    if (showStats) {
      showOSDStats.value = true;
    }
  }

  /// 切换 OSD 统计浮层。
  /// 后端由设置决定：应用自绘（Flutter 浮层，默认）或 mpv 内置 OSD（stats.lua）。
  void toggleOSDStats() {
    if (AppSettingsController.instance.osdBackend.value == "mpv") {
      unawaited(toggleMPVOSDStats());
      return;
    }
    showOSDStats.value = !showOSDStats.value;
  }

  Future<void> toggleMPVOSDStats() async {
    if (!await mpvOSDAvailable()) {
      fallbackToAppOSD(showStats: true);
      return;
    }
    showMPVOSDStats.value = !showMPVOSDStats.value;
    showOSDStats.value = false;
    if (player.platform is NativePlayer) {
      unawaited(
        (player.platform as NativePlayer).command(
          ["script-binding", "stats/display-page-1-toggle"],
        ),
      );
    }
  }

  void showDebugInfo() {
    Utils.showBottomSheet(
      title: "播放信息",
      child: ListView(
        children: [
          Obx(() => SettingsSwitch(
              title: "OSD 显示",
              value: osdStatsVisible,
              onChanged: (value) => toggleOSDStats())),
          ListTile(
            title: const Text("Resolution"),
            subtitle: Text('${player.state.width}x${player.state.height}'),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "Resolution\n${player.state.width}x${player.state.height}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoParams"),
            subtitle: Text(player.state.videoParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "VideoParams\n${player.state.videoParams}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioParams"),
            subtitle: Text(player.state.audioParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioParams\n${player.state.audioParams}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Media"),
            subtitle: Text(player.state.playlist.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "Media\n${player.state.playlist}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioTrack"),
            subtitle: Text(player.state.track.audio.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioTrack\n${player.state.track.audio}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoTrack"),
            subtitle: Text(player.state.track.video.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "VideoTrack\n${player.state.track.audio}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioBitrate"),
            subtitle: Text(player.state.audioBitrate.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioBitrate\n${player.state.audioBitrate}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Volume"),
            subtitle: Text(player.state.volume.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "Volume\n${player.state.volume}",
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void onClose() async {
    Log.w("播放器关闭");
    if (smallWindowState.value) {
      await exitSmallWindow();
    }
    _unbindPipAspectListener();
    disposeStream();
    disposeDanmakuController();
    await resetSystem();
    // todo: https://github.com/media-kit/media-kit/issues/1443
    // only in debug mode
    await player.dispose();
    super.onClose();
  }
}
