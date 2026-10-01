// 多开播放的性能探针 —— 一次性脚本，验证完就删（不要合入）。
//
// 运行：
//   cd simple_live_app
//   SLIVE_SPIKE_URLS="url1,url2,url3,url4" ../.fvm/flutter_sdk/bin/flutter.bat run \
//     -t lib/spike/multi_player_spike.dart -d windows
//   （Linux 把 -d windows 换成 -d linux）
//
// 它只做一件事：在没有 GetX / 没有平台 API / 没有弹幕的前提下，把 N 路直播同时
// 跑起来，并把 mpv 的丢帧/缓存/硬解属性每秒打一遍，用来回答「四路到底跑不跑得动」。
//
// 快捷键：1~4 切聚焦格，A 加一路，R 减一路，C 切换「非聚焦格降渲染尺寸」，P 手动重贴一次尺寸。
//
// 要看的两件事：
// 1) 丢帧与资源：先看 4 路同时跑时各路的 frame-drop-count 是否持续增长；
//    再用任务管理器 / `top -H` 看整机 CPU、逐线程 CPU、GPU 的 Video Decode 占用。
//    单渲染线程（Windows 的 ThreadPool(1)、Linux 的 GLRenderThread）会体现在
//    「CPU 不高但丢帧」或「某个线程吃满」上。
// 2) setSize 这个杠杆：C 打开后对非聚焦格调 VideoController.setSize 把渲染目标
//    从源码分辨率降下来。media_kit 的注释明说小尺寸可能有显著性能提升，但注意
//    NativeVideoController 在每次 videoParams 事件里都会按**源码分辨率**重设一次
//    （本脚本会把这类事件次数打在日志里），所以要看「打开后 GPU 占用/丢帧是否
//    下降」，而不是看某个可读属性。
//
// 音量：总音量滑块 × 非聚焦比例，就是主方案里 ducking 的算法（走 mpv 的 volume，
// 而不是 af 链）。这里可以顺手对着耳朵验一遍「压低而不是静音」，以及把非聚焦比例
// 拉到 0 附近是不是渐弱。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 兜底地址：优先读环境变量 `SLIVE_SPIKE_URLS`（英文逗号分隔），读不到才用这里。
///
/// 之所以用环境变量：改一行字符串对「跑一次探针」来说太重，而且这里最好填
/// 不同平台、不同分辨率（4K / 1080p / 码率高低各一）的直链，才看得出瓶颈。
const List<String> kFallbackUrls = [
  //
];

void main() {
  MediaKit.ensureInitialized();
  runApp(const _SpikeApp());
}

List<String> _resolveUrls() {
  final raw = Platform.environment['SLIVE_SPIKE_URLS'] ?? '';
  final fromEnv = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (fromEnv.isNotEmpty) {
    return fromEnv;
  }
  return kFallbackUrls.where((e) => e.trim().isNotEmpty).toList();
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _SpikePage(),
    );
  }
}

/// 一路播放器 + 它的渲染控制器 + 统计。
class _SpikePlayer {
  _SpikePlayer(this.index, this.url)
      : player = Player(
          configuration: PlayerConfiguration(
            title: "spike #${index + 1}",
            bufferSize: 16 * 1024 * 1024,
            logLevel: MPVLogLevel.error,
          ),
        ) {
    videoController = VideoController(player);
    videoParamsSubscription = player.stream.videoParams.listen((_) => videoParamsEvents++);
  }

  final int index;
  final String url;
  final Player player;
  late final VideoController videoController;
  StreamSubscription? videoParamsSubscription;

  /// 源码分辨率重设渲染目标的次数：用来判断 setSize 的封顶会不会被冲掉。
  int videoParamsEvents = 0;
  String stats = '';

  Future<String> getProperty(String name) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return '<非原生>';
    }
    return platform.getProperty(name);
  }

  Future<void> dispose() async {
    await videoParamsSubscription?.cancel();
    await player.dispose();
  }
}

class _SpikePage extends StatefulWidget {
  const _SpikePage();

  @override
  State<_SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<_SpikePage> {
  final List<_SpikePlayer> _players = [];
  final List<String> _urls = [];
  int _focused = 0;
  double _master = 100;
  double _duckRatio = 0.3;
  bool _capNonFocusedSize = false;
  Timer? _statsTimer;

  /// 每秒回读的属性：丢帧看前三个，缓存/硬解看后几个。
  static const List<String> _props = [
    'frame-drop-count',
    'decoder-frame-drop-count',
    'vo-delayed-frame-count',
    'cache-buffering-state',
    'paused-for-cache',
    'hwdec-current',
    'estimated-vf-fps',
    'video-params/w',
    'video-params/h',
    'demuxer-max-bytes',
    'volume',
  ];

  @override
  void initState() {
    super.initState();
    _urls.addAll(_resolveUrls());
    for (var i = 0; i < _urls.length && i < 4; i++) {
      _add();
    }
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _collectStats());
    WidgetsBinding.instance.addPostFrameCallback((_) => _applySizes());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    for (final p in _players) {
      p.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_players.length >= 4 || _players.length >= _urls.length) {
      return;
    }
    final index = _players.length;
    final spike = _SpikePlayer(index, _urls[index]);
    _players.add(spike);
    setState(() {});
    // dart:io 的 stdout 在桌面端 flutter run 里能直接看到
    stdout.writeln('[spike] 起播 #${index + 1} ${spike.url}');
    spike.player.open(Media(spike.url), play: true).then((_) {
      stdout.writeln('[spike] #${index + 1} open 完成');
      _applyVolumes();
    });
  }

  Future<void> _remove() async {
    if (_players.isEmpty) {
      return;
    }
    final spike = _players.removeLast();
    if (_focused >= _players.length) {
      _focused = _players.isEmpty ? 0 : _players.length - 1;
    }
    setState(() {});
    await spike.dispose();
    stdout.writeln('[spike] 已移除 #${spike.index + 1}，剩 ${_players.length} 路');
    _applyVolumes();
  }

  void _focus(int index) {
    if (index < 0 || index >= _players.length) {
      return;
    }
    setState(() => _focused = index);
    _applyVolumes();
    _applySizes();
  }

  void _applyVolumes() {
    for (var i = 0; i < _players.length; i++) {
      final target = i == _focused ? _master : _master * _duckRatio;
      _players[i].player.setVolume(target);
    }
  }

  /// 对非聚焦格把渲染目标降下来。
  ///
  /// 注意 `setSize` 只在「与当前记录的尺寸不同」时才真的下发，而 videoParams 事件
  /// 是绕过这个记录的，所以重贴同一个尺寸可能是空操作——这一点正是探针要观察的：
  /// 打开 C 之后看 videoParamsEvents 是否还在涨、以及 GPU 占用有没有掉。
  void _applySizes() {
    if (!_capNonFocusedSize) {
      return;
    }
    final ratio = MediaQuery.of(context).devicePixelRatio;
    final size = MediaQuery.of(context).size;
    final cols = _players.length <= 1 ? 1 : 2;
    final rows = _players.length <= 2 ? 1 : 2;
    final cellW = (size.width / cols * ratio).round();
    final cellH = (size.height / rows * ratio).round();
    for (var i = 0; i < _players.length; i++) {
      if (i == _focused) {
        continue;
      }
      _players[i].videoController.setSize(width: cellW, height: cellH);
    }
    stdout.writeln('[spike] 已重贴非聚焦格渲染尺寸 ${cellW}x$cellH（物理像素）');
  }

  Future<void> _collectStats() async {
    for (final spike in _players) {
      final buffer = StringBuffer('[spike] #${spike.index + 1} ');
      for (final name in _props) {
        String value;
        try {
          value = await spike.getProperty(name);
        } catch (e) {
          value = '<err>';
        }
        buffer.write('$name=$value ');
      }
      buffer.write('videoParamsEvents=${spike.videoParamsEvents}');
      spike.stats = buffer.toString();
      stdout.writeln(buffer.toString());
    }
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit1) {
      _focus(0);
    } else if (key == LogicalKeyboardKey.digit2) {
      _focus(1);
    } else if (key == LogicalKeyboardKey.digit3) {
      _focus(2);
    } else if (key == LogicalKeyboardKey.digit4) {
      _focus(3);
    } else if (key == LogicalKeyboardKey.keyA) {
      _add();
    } else if (key == LogicalKeyboardKey.keyR) {
      _remove();
    } else if (key == LogicalKeyboardKey.keyC) {
      setState(() => _capNonFocusedSize = !_capNonFocusedSize);
      stdout.writeln('[spike] 非聚焦格降渲染尺寸：$_capNonFocusedSize');
      _applySizes();
    } else if (key == LogicalKeyboardKey.keyP) {
      _applySizes();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final missing = _urls.isEmpty;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(
              child: missing
                  ? const Center(
                      child: Text(
                        '没有可用的地址。\n用 SLIVE_SPIKE_URLS="url1,url2,..." 跑，\n'
                        '或把地址填进 kFallbackUrls。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            for (var i = 0; i < _players.length; i++)
                              _tile(i, constraints),
                          ],
                        );
                      },
                    ),
            ),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _tile(int index, BoxConstraints constraints) {
    final count = _players.length;
    final cols = count <= 1 ? 1 : 2;
    final rows = (count / cols).ceil();
    final width = constraints.maxWidth / cols;
    final height = constraints.maxHeight / rows;
    final focused = index == _focused;
    return Positioned(
      left: (index % cols) * width,
      top: (index ~/ cols) * height,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: focused ? Colors.blueAccent : Colors.white24,
            width: focused ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: _players[index].videoController,
                fit: BoxFit.contain,
                wakelock: false,
                controls: (state) => const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Text(
                '#${index + 1}${focused ? " 聚焦" : ""}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Text(
                _players[index].stats,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _focus(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Text('总音量', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: Slider(
              value: _master,
              max: 130,
              onChanged: (v) {
                setState(() => _master = v);
                _applyVolumes();
              },
            ),
          ),
          const Text('非聚焦比例', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: Slider(
              value: _duckRatio,
              max: 1,
              divisions: 20,
              label: _duckRatio.toStringAsFixed(2),
              onChanged: (v) {
                setState(() => _duckRatio = v);
                _applyVolumes();
              },
            ),
          ),
          Text(
            '1-4 切焦点 / A 加 / R 减 / C 降尺寸(${_capNonFocusedSize ? "开" : "关"}) / P 重贴',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}