import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_osd_widgets.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';

/// Flutter 自绘的「Modern MPV Inspector」统计面板。
///
/// * 数据来源不变：`controller.player.state`（media_kit `PlayerState`）+ 少量
///   `NativePlayer.getProperty` 标量属性 + 直播间 Controller 的既有状态；
/// * 不依赖 mpv 的 `stats.lua` / Lua 脚本，因此在未编译 Lua 的 libmpv 构建下同样可用；
/// * 视觉与交互实现在 [OsdPanel] / [OsdSection] / [OsdStatGrid] / [OsdAdvanced] 中，
///   本文件只负责「取数 + 格式化 + 组装页面」。
class PlayerOsdOverlay extends StatefulWidget {
  const PlayerOsdOverlay({
    super.key,
    required this.controller,
    this.onClose,
  });

  final LiveRoomController controller;
  final VoidCallback? onClose;

  @override
  State<PlayerOsdOverlay> createState() => _PlayerOsdOverlayState();
}

class _PlayerOsdOverlayState extends State<PlayerOsdOverlay> {
  /// 页签：保留原 1..5 的功能，但以分段控件呈现。
  static const List<String> _tabs = [
    'Overview',
    'Frame',
    'Cache',
    'Tracks',
    'Audio',
  ];

  /// 需要从 mpv 读取的标量属性（读不到的显示 —）。
  static const List<String> _propNames = [
    'video-codec',
    'audio-codec',
    'file-format',
    'hwdec-current',
    'vo',
    'display-fps',
    'estimated-vf-fps',
    'container-fps',
    'frame-drop-count',
    'mistimed-frame-count',
    'demuxer-cache-duration',
    // 卡顿诊断：这三项决定了「是不是在等数据」
    'demuxer-cache-time',
    'cache-buffering-state',
    'paused-for-cache',
  ];

  int _page = 0;
  Timer? _refresh;
  bool _loadingProps = false;
  final Map<String, String> _props = <String, String>{};

  @override
  void initState() {
    super.initState();
    // 面板可见期间 2Hz 刷新一个 ~60 widget 的子树，不涉及逐帧 rebuild。
    //
    // 注意：`player.state` 由 media_kit 的事件循环更新，setState 就能拿到新值；
    // 但 `getProperty` 读到的标量属性（缓存时长/丢帧/帧率等）必须重新读取，
    // 否则这些数字会一直停在打开面板那一刻的旧值上。
    _refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) async {
        // 先等属性读回来再重建，否则 getProperty 读到的标量值永远滞后一个周期。
        await _loadProps();
        if (mounted) setState(() {});
      },
    );
    // 首帧同理：属性读回来后再刷一次，避免刚打开面板时满屏 —。
    _loadProps().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadProps() async {
    if (_loadingProps) return;
    final player = widget.controller.player;
    if (player.platform is! NativePlayer) return;
    _loadingProps = true;
    try {
      final np = player.platform as NativePlayer;
      for (final name in _propNames) {
        try {
          final v = await np.getProperty(name);
          if (!mounted) return;
          // 读不到就写成空串，避免把上一轮的旧值一直留在面板上。
          _props[name] = v;
        } catch (_) {
          // 属性在部分构建中不存在或不可读，忽略，UI 显示为 —。
        }
      }
    } finally {
      _loadingProps = false;
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 基础访问
  // ---------------------------------------------------------------------------

  PlayerState get _state => widget.controller.player.state;

  /// 应用当前字体（null 表示系统默认），与 main.dart 主题里的 fontFamily 一致。
  String? get _fontFamily =>
      AppStyleSettingController.instance.curFontName.value;

  bool get _hardwareDecoding {
    final v = (_props['hwdec-current'] ?? '').trim().toLowerCase();
    return v.isNotEmpty && v != 'no' && v != 'none';
  }

  // ---------------------------------------------------------------------------
  // 格式化（只影响展示，不改动底层数据）
  // ---------------------------------------------------------------------------

  String _dash(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty || s.toLowerCase() == 'unknown' || s.toLowerCase() == 'no') {
      return '—';
    }
    return s;
  }

  /// mpv 的浮点属性常返回 "60.000000"，这里收敛成 "60" / "60.5"。
  String _trimDouble(double v, {int decimals = 1}) {
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 0.05) return rounded.toStringAsFixed(0);
    return v.toStringAsFixed(decimals);
  }

  String _fmtFps(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return '—';
    return '${_trimDouble(v)} FPS';
  }

  String _fmtHz(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return '—';
    return '${_trimDouble(v)} Hz';
  }

  String _fmtSeconds(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null) return '—';
    return '${v.toStringAsFixed(1)} s';
  }

  String _fmtPercent(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null) return '—';
    return '${v.toStringAsFixed(0)}%';
  }

  /// mpv 的 flag 属性字符串形式为 yes / no。
  String _fmtFlag(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == 'yes') return 'Yes';
    if (v == 'no') return 'No';
    return '—';
  }

  /// mpv 的 video-bitrate / audio-bitrate 原始值为 bit/s。
  String _fmtBitrate(double? bps) {
    if (bps == null || bps <= 0) return '—';
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(2)} Mbps';
    return '${(bps / 1000).toStringAsFixed(0)} kbps';
  }

  String _fmtRes(int? w, int? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return '—';
    return '$w × $h';
  }

  String _fmtCount(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static const Map<String, String> _codecNames = {
    'h264': 'H.264',
    'avc1': 'H.264',
    'hevc': 'H.265',
    'h265': 'H.265',
    'av1': 'AV1',
    'vp9': 'VP9',
    'vp8': 'VP8',
    'mpeg4': 'MPEG-4',
    'mpeg2video': 'MPEG-2',
    'vc1': 'VC-1',
    'wmv3': 'WMV3',
    'prores': 'ProRes',
    'theora': 'Theora',
    'mjpeg': 'MJPEG',
    'aac': 'AAC',
    'opus': 'Opus',
    'mp3': 'MP3',
    'ac3': 'AC-3',
    'eac3': 'E-AC-3',
    'flac': 'FLAC',
    'vorbis': 'Vorbis',
  };

  /// mpv 的 `video-codec`/`audio-codec` 是 `codec-desc`（通常等于
  /// AVCodecDescriptor.long_name），例如 `H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10`
  /// 或 `AAC (Advanced Audio Coding)`；老版本可能只给短名 `h264`。
  /// 这里统一收敛成 `H.264` / `AAC` 这样的短标签。
  String _fmtCodec(String? raw) {
    final c = (raw ?? '').trim();
    if (c.isEmpty) return '—';
    // 先去掉括号里的别名串，再取 ' / ' 的第一段。
    final int paren = c.indexOf(' (');
    final String head =
        (paren > 0 ? c.substring(0, paren) : c.split(' / ').first).trim();
    if (head.isEmpty) return '—';
    return _codecNames[head.toLowerCase()] ?? head;
  }

  String _fmtColor(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty || v.toLowerCase() == 'unknown') return '—';
    return v.toUpperCase();
  }

  String _fmtHwdec() {
    final v = (_props['hwdec-current'] ?? '').trim();
    if (v.isEmpty || v.toLowerCase() == 'no') return 'Software';
    return v.toUpperCase();
  }

  String _streamFormat() {
    final urls = widget.controller.playUrls;
    final i = widget.controller.currentLineIndex;
    if (i >= 0 && i < urls.length) {
      final u = urls[i].toLowerCase();
      if (u.contains('.flv')) return 'FLV';
      if (u.contains('.m3u8')) return 'HLS';
    }
    final f = (_props['file-format'] ?? '').trim().toUpperCase();
    return f.isEmpty ? '—' : f;
  }

  String _streamUrl() {
    final urls = widget.controller.playUrls;
    final i = widget.controller.currentLineIndex;
    if (i >= 0 && i < urls.length) return urls[i];
    return widget.controller.detail.value?.url ?? '—';
  }

  String _streamStatus() {
    final d = widget.controller.detail.value;
    if (d == null) return '—';
    if (d.isRecord) return '轮播';
    return d.status ? '直播中' : '未开播';
  }

  Color? _streamStatusColor() {
    final d = widget.controller.detail.value;
    if (d == null) return null;
    if (d.isRecord) return OsdStyle.warn;
    return d.status ? OsdStyle.ok : null;
  }

  // ---------------------------------------------------------------------------
  // 页面组装
  // ---------------------------------------------------------------------------

  Widget _buildPage() {
    switch (_page) {
      case 1:
        return _framePage();
      case 2:
        return _cachePage();
      case 3:
        return _tracksPage();
      case 4:
        return _audioPage();
      default:
        return _overviewPage();
    }
  }

  Widget _overviewPage() {
    final s = _state;
    final vp = s.videoParams;
    final c = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OsdSection(
          title: 'Display',
          child: OsdStatGrid(
            stats: [
              OsdStat('Resolution', _fmtRes(s.width ?? vp.w, s.height ?? vp.h)),
              OsdStat('Refresh Rate', _fmtHz(_props['display-fps'])),
              OsdStat('Output', _dash(_props['vo'])),
              OsdStat(
                'Decoder',
                _fmtHwdec(),
                accent: _hardwareDecoding ? OsdStyle.ok : null,
              ),
            ],
          ),
        ),
        OsdSection(
          title: 'Video',
          child: OsdStatGrid(
            stats: [
              OsdStat('Codec', _fmtCodec(_props['video-codec'])),
              OsdStat(
                'Frame Rate',
                _fmtFps(_props['estimated-vf-fps'] ?? _props['container-fps']),
              ),
              OsdStat('Resolution', _fmtRes(vp.w, vp.h)),
              OsdStat('Bitrate', _fmtBitrate(s.videoBitrate)),
              OsdStat('Format', _dash(vp.pixelformat), secondary: true),
              OsdStat('Color', _fmtColor(vp.colormatrix), secondary: true),
            ],
          ),
        ),
        OsdSection(
          title: 'Stream',
          child: OsdStatGrid(
            stats: [
              OsdStat('Platform', c.site.name),
              OsdStat('Format', _streamFormat()),
              OsdStat('Quality', _dash(c.currentQualityInfo.value)),
              OsdStat('Line', _dash(c.currentLineInfo.value)),
              OsdStat('Status', _streamStatus(), accent: _streamStatusColor()),
              OsdStat('Viewers', _fmtCount(c.online.value)),
            ],
          ),
        ),
        OsdAdvanced(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OsdUrlBlock(
                url: _streamUrl(),
                onCopy: () => Utils.copyToClipboard(_streamUrl()),
              ),
              const SizedBox(height: 10),
              OsdDetailRow(
                label: 'File Format',
                value: _dash(_props['file-format']),
              ),
              OsdDetailRow(
                label: 'Video Codec',
                value: _dash(_props['video-codec']),
              ),
              OsdDetailRow(
                label: 'Audio Codec',
                value: _dash(_props['audio-codec']),
              ),
              OsdDetailRow(
                label: 'Pixel Format',
                value: _dash(vp.pixelformat),
              ),
              OsdDetailRow(
                label: 'HW Pixel Format',
                value: _dash(vp.hwPixelformat),
              ),
              OsdDetailRow(
                label: 'Color Matrix',
                value: _dash(vp.colormatrix),
              ),
              OsdDetailRow(label: 'Primaries', value: _dash(vp.primaries)),
              OsdDetailRow(label: 'Transfer', value: _dash(vp.gamma)),
              OsdDetailRow(
                label: 'Color Levels',
                value: _dash(vp.colorlevels),
              ),
              OsdDetailRow(
                label: 'Chroma Location',
                value: _dash(vp.chromaLocation),
              ),
              OsdDetailRow(
                label: 'Aspect Ratio',
                value: vp.aspect != null
                    ? vp.aspect!.toStringAsFixed(3)
                    : '—',
              ),
              OsdDetailRow(
                label: 'Rotation',
                value: vp.rotate != null ? '${vp.rotate}°' : '—',
              ),
              OsdDetailRow(
                label: 'HW Decoder (raw)',
                value: _dash(_props['hwdec-current']),
              ),
              OsdDetailRow(
                label: 'Video Output (raw)',
                value: _dash(_props['vo']),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _framePage() {
    final vp = _state.videoParams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OsdSection(
          title: 'Frame Timings',
          child: OsdStatGrid(
            stats: [
              OsdStat('Estimated FPS', _fmtFps(_props['estimated-vf-fps'])),
              OsdStat('Container FPS', _fmtFps(_props['container-fps'])),
              OsdStat('Display FPS', _fmtFps(_props['display-fps'])),
              OsdStat('Video Size', _fmtRes(vp.w, vp.h)),
              OsdStat('Dropped Frames', _dash(_props['frame-drop-count'])),
              OsdStat('Mistimed Frames', _dash(_props['mistimed-frame-count'])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cachePage() {
    final s = _state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OsdSection(
          title: 'Cache',
          child: OsdStatGrid(
            stats: [
              OsdStat('Buffer', _fmtDuration(s.buffer)),
              OsdStat('Buffering', '${s.bufferingPercentage.toStringAsFixed(0)}%'),
              // 下面三项用于判断「卡顿是不是在等数据」：
              // cache=no 时 demuxer cache 被关闭，这些值会恒为 0/—。
              OsdStat('Buffer State', _fmtPercent(_props['cache-buffering-state'])),
              OsdStat('Paused for Cache', _fmtFlag(_props['paused-for-cache'])),
              OsdStat(
                'Demuxer Cache',
                _fmtSeconds(_props['demuxer-cache-duration']),
              ),
              // demuxer-cache-time 是「缓存已读到的流时间戳」，不是缓存长度。
              OsdStat('Cache End', _fmtSeconds(_props['demuxer-cache-time'])),
              OsdStat('Video Bitrate', _fmtBitrate(s.videoBitrate)),
              OsdStat('Audio Bitrate', _fmtBitrate(s.audioBitrate)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tracksPage() {
    final s = _state;
    final vp = s.videoParams;
    final ap = s.audioParams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OsdSection(
          title: 'Video Track',
          child: OsdStatGrid(
            stats: [
              OsdStat('Codec', _fmtCodec(_props['video-codec'])),
              OsdStat(
                'Decoder',
                _fmtHwdec(),
                accent: _hardwareDecoding ? OsdStyle.ok : null,
              ),
              OsdStat('Resolution', _fmtRes(vp.w, vp.h)),
              OsdStat('Bitrate', _fmtBitrate(s.videoBitrate)),
              OsdStat('Pixel Format', _dash(vp.pixelformat)),
              OsdStat('Color', _fmtColor(vp.colormatrix)),
            ],
          ),
        ),
        OsdSection(
          title: 'Audio Track',
          child: OsdStatGrid(
            stats: [
              OsdStat('Codec', _fmtCodec(_props['audio-codec'])),
              OsdStat(
                'Sample Rate',
                ap.sampleRate != null ? '${ap.sampleRate} Hz' : '—',
              ),
              OsdStat('Format', _dash(ap.format)),
              OsdStat('Channels', _dash(ap.channels)),
              OsdStat('Bitrate', _fmtBitrate(s.audioBitrate)),
              OsdStat('Layout', _dash(ap.hrChannels)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _audioPage() {
    final s = _state;
    final ap = s.audioParams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OsdSection(
          title: 'Audio',
          child: OsdStatGrid(
            stats: [
              OsdStat('Codec', _fmtCodec(_props['audio-codec'])),
              OsdStat(
                'Sample Rate',
                ap.sampleRate != null ? '${ap.sampleRate} Hz' : '—',
              ),
              OsdStat('Format', _dash(ap.format)),
              OsdStat('Channels', _dash(ap.channels)),
              OsdStat('Layout', _dash(ap.hrChannels)),
              OsdStat('Bitrate', _fmtBitrate(s.audioBitrate)),
            ],
          ),
        ),
        OsdSection(
          title: 'Playback',
          child: OsdStatGrid(
            stats: [
              OsdStat('Volume', '${s.volume.toStringAsFixed(0)}%'),
              OsdStat('Speed', '${s.rate.toStringAsFixed(2)}×'),
              OsdStat('Buffer', _fmtDuration(s.buffer)),
              OsdStat('State', s.playing ? 'Playing' : 'Paused'),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 外壳
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 触控尺寸按平台判定（而不是按宽度），避免小屏上把点击区域压到点不中。
    final bool touch = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Align(
      alignment: Alignment.topLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 非全屏时 OSD 落在 16:9 视频区里，本身已在安全区内，再扣一次会白白内缩；
          // 只有接近铺满屏幕（全屏）时才需要避开刘海 / 状态栏 / 手势区。
          final double screenHeight = MediaQuery.sizeOf(context).height;
          final bool coversScreen = !constraints.maxHeight.isFinite ||
              constraints.maxHeight >= screenHeight * 0.8;
          final EdgeInsets safePadding =
              coversScreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;

          // 尺寸表由「可用空间 + 安全区 + 是否触控」决定；桌面参数与重构前逐值一致。
          final metrics = OsdMetrics.resolve(
            constraints: constraints,
            safePadding: safePadding,
            touch: touch,
          );

          return Padding(
            padding: EdgeInsets.only(
              left: safePadding.left + metrics.horizontalMargin,
              top: safePadding.top + metrics.verticalMargin,
              right: safePadding.right + metrics.horizontalMargin,
              bottom: safePadding.bottom + metrics.verticalMargin,
            ),
            child: OsdMetricsScope(
              metrics: metrics,
              child: OsdPanel(
                maxWidth: metrics.panelMaxWidth,
                maxHeight: metrics.panelMaxHeight,
                child: DefaultTextStyle(
                  style: TextStyle(fontFamily: _fontFamily),
                  child: metrics.minimal
                      ? OsdHeader(
                          title: 'Video Information',
                          onClose: widget.onClose,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!metrics.inlineHeader)
                              OsdHeader(
                                title: 'Video Information',
                                onClose: widget.onClose,
                              ),
                            OsdSegmentedTabs(
                              labels: _tabs,
                              index: _page,
                              onChanged: (i) => setState(() => _page = i),
                              trailing:
                                  metrics.inlineHeader && widget.onClose != null
                                      ? Padding(
                                          padding:
                                              const EdgeInsets.only(left: 2),
                                          child: OsdIconButton(
                                            icon: Icons.close_rounded,
                                            tooltip: '关闭',
                                            onTap: widget.onClose!,
                                          ),
                                        )
                                      : null,
                            ),
                            SizedBox(height: metrics.contentGap),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: metrics.bodyMaxHeight,
                              ),
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  metrics.contentPadding,
                                  0,
                                  metrics.contentPadding,
                                  metrics.contentPadding,
                                ),
                                child: _buildPage(),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
