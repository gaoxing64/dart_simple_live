import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_osd_widgets.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';

/// Flutter 自绘的 mpv 风格播放统计面板（单页，无分页选择）。
///
/// * 数据来源不变：`controller.player.state`（media_kit `PlayerState`）+ 少量
///   `NativePlayer.getProperty` 标量属性 + 直播间 Controller 的既有状态；
/// * 不依赖 mpv 的 `stats.lua` / Lua 脚本，因此在未编译 Lua 的 libmpv 构建下同样可用；
/// * 内容对齐 mpv stats 的「第一页」：Display / Video / Audio / Stream / Cache
///   五个核心分节一屏滚动看完，偏诊断用的原始属性值收进 Advanced 折叠区；
/// * 视觉与交互实现在 [OsdPanel] / [OsdStatTile] / [OsdGroup] / [OsdRow] /
///   [OsdChip] / [OsdAdvanced] 中，本文件只负责「取数 + 格式化 + 组装页面」；
/// * 版式：顶部四个核心数字做成指标卡当视觉锚点，其余分组一律行式
///   （Label 左 / Value 右、共享一条右对齐线），短状态值用 Chip 挂在标题右侧；
/// * 小屏（<600dp，安卓竖屏）自动切底部表单形态：通栏贴底、顶部 28dp 大圆角、
///   指标卡排成一行四个、次要行隐藏、滚动条常显 —— 因为此时 OSD 被 16:9
///   视频区限制在 ~220dp 高，左上角浮层那套布局在这个高度里没法用。
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

  Timer? _refresh;
  bool _loadingProps = false;
  final Map<String, String> _props = <String, String>{};

  /// 显式持有滚动控制器：触屏上要常显滚动条（否则看不出内容还能往下滚），
  /// 而 [Scrollbar] 只有在和滚动视图共用同一个 controller 时才生效。
  final ScrollController _scroll = ScrollController();

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
    _scroll.dispose();
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

  /// 指标卡里只放数字，单位另起小字 —— 「60 FPS」挤在一行会在窄屏换行。
  String _fpsNum(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return '—';
    return _trimDouble(v);
  }

  String _bitrateNum(double? bps) {
    if (bps == null || bps <= 0) return '—';
    if (bps >= 1000000) return (bps / 1000000).toStringAsFixed(2);
    return (bps / 1000).toStringAsFixed(0);
  }

  /// 值为 — 时不返回单位，免得卡片上孤零零挂一个 "kbps"。
  String? _bitrateUnit(double? bps) {
    if (bps == null || bps <= 0) return null;
    return bps >= 1000000 ? 'Mbps' : 'kbps';
  }

  /// 帧率同理：读不到时不要在卡片上留一个孤零零的 "FPS"。
  String? _fpsUnit(String? raw) => _fpsNum(raw) == '—' ? null : 'FPS';

  String _bufferSeconds(Duration d) =>
      (d.inMilliseconds / 1000).toStringAsFixed(1);

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

  OsdChipTone _streamStatusTone() {
    final d = widget.controller.detail.value;
    if (d == null) return OsdChipTone.neutral;
    if (d.isRecord) return OsdChipTone.warn;
    return d.status ? OsdChipTone.ok : OsdChipTone.neutral;
  }

  /// 丢帧 > 0 才把指标卡染成警示色；0 帧时保持中性，否则面板永远一片高亮。
  OsdChipTone _dropTone() {
    final v = int.tryParse((_props['frame-drop-count'] ?? '').trim()) ?? 0;
    return v > 0 ? OsdChipTone.warn : OsdChipTone.neutral;
  }

  /// 只有确实有值时才挂 Chip，避免出现一个内容就是「—」的空令牌。
  bool _has(String? v) => _dash(v) != '—';

  // ---------------------------------------------------------------------------
  // 单页内容（对齐 mpv stats 的第一页）
  // ---------------------------------------------------------------------------

  /// 一屏滚动看完全部核心指标：Display / Video / Audio / Stream / Cache。
  ///
  /// 原来拆成 5 个页签只是为了塞进 mpv 的 `stats.lua` 分页模型，
  /// 但面板本身已经是可滚动容器，分页只增加了一次点击成本，
  /// 因此合并为单页；只有偏诊断用的原始属性值收进 Advanced 折叠区。
  Widget _body() {
    final s = _state;
    final vp = s.videoParams;
    final ap = s.audioParams;
    final c = widget.controller;
    // 帧率 / 流格式 / 直播状态都可能读不到（属性不可用、detail 未加载完），
    // 统一先算一次，让 value 与 unit / chip 的判定取自同一个值。
    final String? fpsRaw =
        _props['estimated-vf-fps'] ?? _props['container-fps'];
    final String streamFormat = _streamFormat();
    final String streamStatus = _streamStatus();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 核心四指标：面板里唯一的「卡片」层级，大字号做视觉锚点，
        // 让人第一眼就知道帧率 / 码率 / 丢帧 / 缓冲这四个数。
        OsdStatTileGrid(
          tiles: [
            OsdStatTile(
              label: 'Frame Rate',
              value: _fpsNum(fpsRaw),
              unit: _fpsUnit(fpsRaw),
            ),
            OsdStatTile(
              label: 'Bitrate',
              value: _bitrateNum(s.videoBitrate),
              unit: _bitrateUnit(s.videoBitrate),
            ),
            OsdStatTile(
              label: 'Dropped',
              value: _dash(_props['frame-drop-count']),
              tone: _dropTone(),
            ),
            OsdStatTile(
              label: 'Buffer',
              value: _bufferSeconds(s.buffer),
              unit: 's',
            ),
          ],
        ),
        OsdGroup(
          title: 'Display',
          child: OsdRowList(
            rows: [
              OsdRow(
                label: 'Display Resolution',
                value: _fmtRes(s.width ?? vp.w, s.height ?? vp.h),
              ),
              OsdRow(
                label: 'Refresh Rate',
                value: _fmtHz(_props['display-fps']),
              ),
              OsdRow(label: 'Video Output', value: _dash(_props['vo'])),
              OsdRow(
                label: 'Decoder',
                value: _fmtHwdec(),
                tone: _hardwareDecoding ? OsdChipTone.ok : OsdChipTone.neutral,
              ),
            ],
          ),
        ),
        OsdGroup(
          title: 'Video',
          child: OsdRowList(
            rows: [
              OsdRow(label: 'Codec', value: _fmtCodec(_props['video-codec'])),
              OsdRow(label: 'Source Resolution', value: _fmtRes(vp.w, vp.h)),
              OsdRow(
                label: 'Pixel Format',
                value: _dash(vp.pixelformat),
                secondary: true,
              ),
              OsdRow(
                label: 'Color Matrix',
                value: _fmtColor(vp.colormatrix),
                secondary: true,
              ),
            ],
          ),
        ),
        OsdGroup(
          title: 'Stream',
          chips: [
            // 三个 chip 用同一套「有值才挂」的判定，避免出现内容就是「—」的空令牌
            if (_has(streamFormat))
              OsdChip(label: streamFormat, tone: OsdChipTone.primary),
            if (_has(c.currentQualityInfo.value))
              OsdChip(label: _dash(c.currentQualityInfo.value)),
            if (_has(streamStatus))
              OsdChip(label: streamStatus, tone: _streamStatusTone()),
          ],
          child: OsdRowList(
            rows: [
              OsdRow(label: 'Platform', value: c.site.name),
              OsdRow(label: 'Line', value: _dash(c.currentLineInfo.value)),
              OsdRow(label: 'Viewers', value: _fmtCount(c.online.value)),
            ],
          ),
        ),
        OsdGroup(
          title: 'Audio',
          child: OsdRowList(
            rows: [
              OsdRow(label: 'Codec', value: _fmtCodec(_props['audio-codec'])),
              OsdRow(
                label: 'Sample Rate',
                value: ap.sampleRate != null ? '${ap.sampleRate} Hz' : '—',
              ),
              OsdRow(label: 'Channels', value: _dash(ap.channels)),
              OsdRow(
                // 采样格式（fltp / s16 …）：重构前 Tracks 与 Audio 两页各有
                // 一项，收进单页时漏了，这里按次要行补回，不再丢失诊断信息。
                label: 'Format',
                value: _dash(ap.format),
                secondary: true,
              ),
              OsdRow(
                label: 'Layout',
                value: _dash(ap.hrChannels),
                secondary: true,
              ),
              OsdRow(label: 'Bitrate', value: _fmtBitrate(s.audioBitrate)),
              OsdRow(label: 'Speed', value: '${s.rate.toStringAsFixed(2)}×'),
            ],
          ),
        ),
        OsdGroup(
          title: 'Cache',
          child: OsdRowList(
            rows: [
              OsdRow(
                label: 'Buffering',
                value: '${s.bufferingPercentage.toStringAsFixed(0)}%',
              ),
              // 下面三项用于判断「卡顿是不是在等数据」：
              // cache=no 时 demuxer cache 被关闭，这些值会恒为 0/—。
              OsdRow(
                label: 'Buffer State',
                value: _fmtPercent(_props['cache-buffering-state']),
              ),
              OsdRow(
                label: 'Demuxer Cache',
                value: _fmtSeconds(_props['demuxer-cache-duration']),
              ),
              OsdRow(
                label: 'Paused for Cache',
                value: _fmtFlag(_props['paused-for-cache']),
              ),
              // demuxer-cache-time 是「缓存已读到的流时间戳」，不是缓存长度。
              OsdRow(
                label: 'Cache End',
                value: _fmtSeconds(_props['demuxer-cache-time']),
              ),
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
              // 原本单独占一页的帧时序与播放状态，收进折叠区。
              OsdDetailRow(
                label: 'Frame Rate (estimated)',
                value: _fmtFps(_props['estimated-vf-fps']),
              ),
              OsdDetailRow(
                label: 'Frame Rate (container)',
                value: _fmtFps(_props['container-fps']),
              ),
              OsdDetailRow(
                label: 'Mistimed Frames',
                value: _dash(_props['mistimed-frame-count']),
              ),
              OsdDetailRow(
                label: 'Playback',
                value: '${s.playing ? 'Playing' : 'Paused'} · '
                    '${s.volume.toStringAsFixed(0)}% · '
                    '${s.rate.toStringAsFixed(2)}×',
              ),
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
                value: vp.aspect != null ? vp.aspect!.toStringAsFixed(3) : '—',
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

  // ---------------------------------------------------------------------------
  // 外壳
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 触控尺寸按平台判定（而不是按宽度），避免小屏上把点击区域压到点不中。
    final bool touch = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return LayoutBuilder(
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

        return Align(
          // 窄屏（安卓竖屏）走底部表单：通栏贴底，宽度与高度都吃满视频区，
          // 且落在拇指可达范围；宽屏仍是左上角浮层，不挡画面中心。
          alignment:
              metrics.isSheet ? Alignment.bottomCenter : Alignment.topLeft,
          child: Padding(
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
                radius: metrics.panelRadius,
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
                            OsdHeader(
                              title: 'Video Information',
                              onClose: widget.onClose,
                            ),
                            SizedBox(height: metrics.contentGap),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: metrics.bodyMaxHeight,
                              ),
                              child: Scrollbar(
                                controller: _scroll,
                                // 触屏上常显滚动条：面板只有一屏高时，
                                // 不常显就看不出下面还有内容。
                                thumbVisibility: touch,
                                thickness: metrics.isSheet ? 3 : 4,
                                radius: const Radius.circular(2),
                                child: SingleChildScrollView(
                                  controller: _scroll,
                                  padding: EdgeInsets.fromLTRB(
                                    metrics.contentPadding,
                                    0,
                                    metrics.contentPadding,
                                    metrics.contentPadding,
                                  ),
                                  child: _body(),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
