import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';

import 'package:simple_live_app/app/log.dart';

class NetImage extends StatefulWidget {
  /// 图片加载耗时采样开关。
  ///
  /// 默认关闭：宽屏首屏有几十张封面，逐张打点会产生大量日志。排查「列表数据
  /// 明明已经回来了，卡片却还在一张张冒出来」时打开它，用来区分到底是接口慢
  /// 还是图片慢——两者表现很像，但改法完全不同。
  static bool telemetryEnabled = false;

  final String picUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final double borderRadius;
  const NetImage(this.picUrl, {this.width, this.height, this.fit = BoxFit.cover, this.borderRadius = 0, super.key});

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  /// 本次加载的计时器；未开启采样时为 null。
  Stopwatch? _stopwatch;

  /// 本次加载是否已经打过点。
  ///
  /// 必须有这个标志：`loadStateChanged` 在图片已加载完成后**每次 build 都会
  /// 回调一次** `LoadState.completed`，而列表滚动会让卡片频繁重建。没有它的话
  /// 每张已加载的封面都会被反复打上 `0ms` 的日志，采到的数据不再是「首次加载
  /// 耗时」，而是被重建次数放大的噪声。
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _restartTelemetry();
  }

  @override
  void didUpdateWidget(covariant NetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了图要重新计时，否则会拿上一张的耗时去报新图。
    if (oldWidget.picUrl != widget.picUrl) {
      _restartTelemetry();
    }
  }

  void _restartTelemetry() {
    _logged = false;
    _stopwatch = NetImage.telemetryEnabled ? (Stopwatch()..start()) : null;
  }

  void _logOnce(String url) {
    final stopwatch = _stopwatch;
    if (_logged || stopwatch == null) {
      return;
    }
    _logged = true;
    stopwatch.stop();
    // 尺寸只能原样可读化，不能 toInt()：封面用的就是 `width: double.infinity`
    // （见 LiveRoomCard），而 Dart 的 `num.toInt()` 对无穷大直接抛
    // UnsupportedError——一打开采样就会在 build 里炸掉，采样反而不可用。
    final message = '[image] ${stopwatch.elapsedMilliseconds}ms '
        '${_sizeLabel(widget.width)}x${_sizeLabel(widget.height)} $url';
    // 不能在这里直接写日志：loadStateChanged 是 ExtendedImage 在 **build 阶段**
    // 同步回调的，而 Log.d → addDebugLog 会往 RxList 插入一条日志，Log 页在树上
    // 时会立刻 markNeedsBuild，抛 "setState() or markNeedsBuild() called during
    // build"。挪到帧外，顺带也让采样本身不干扰被观测的那一帧。
    WidgetsBinding.instance.addPostFrameCallback((_) => Log.d(message));
  }

  /// 尺寸的可读化：无穷大（占满可用宽度）打印成 `∞`，不参与取整。
  static String _sizeLabel(double? value) {
    if (value == null) {
      return '?';
    }
    return value.isFinite ? value.toInt().toString() : '∞';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.picUrl.isEmpty) {
      return Image.asset(
        'assets/images/logo.png',
        width: widget.width,
        height: widget.height,
      );
    }
    var pic = widget.picUrl;
    if (pic.startsWith("//")) {
      pic = 'https:$pic';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: ExtendedImage.network(
        pic,
        fit: widget.fit,
        height: widget.height,
        width: widget.width,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        loadStateChanged: (e) {
          if (e.extendedImageLoadState == LoadState.completed) {
            _logOnce(pic);
          }
          // 加载中/失败时保持原有尺寸（封面 110 高），
          // 否则卡片会缩成一个小图标、行高参差、布局错乱
          final icon = switch (e.extendedImageLoadState) {
            LoadState.loading => Icons.image,
            LoadState.failed => Icons.broken_image,
            _ => null,
          };
          if (icon == null) {
            return null;
          }
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Icon(
              icon,
              color: Colors.grey,
              size: 24,
            ),
          );
        },
      ),
    );
  }
}
