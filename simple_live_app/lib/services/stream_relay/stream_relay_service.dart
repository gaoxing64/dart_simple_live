import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/stream_relay/flv_demuxer.dart';
import 'package:uuid/uuid.dart';

/// 本地「续流中转」服务。
///
/// 把带时效的直播直链包成一条本地 HTTP 流下发给播放器；在旧直链到期
/// （CDN 主动断开）之前，用同一条线路重新取流，并新流在 FLV tag 边界上
/// 接续到已转发的字节流里，对播放器表现为一条不中断的流。
///
/// 背景：斗鱼下发给第三方的 FLV 直链固定 300 秒寿命，到点 CDN 直接 EOF，
/// 与网络、线路、清晰度无关。未登录（游客模式）时取流接口只会下发这种
/// 短效直链，不处理的话播放约 5 分钟就会停在最后一帧。斗鱼官方网页端的
/// 做法就是每 ~300 秒重新调一次取流接口续签，这里做的是同一件事。
/// 参考 DTV 项目的 flv_relay 实现（commit ae4b425f）。
///
/// 续流来源与 DTV 同构：上层只登记 [StreamRenewContext]（房间 / 清晰度 / 线路
/// + 取流入口），到期时由中转自己重取直链。不依赖 core 下发 renewer 回调——
/// Rust 化后 `LivePlayUrl.renewers` 已无人产出（O-7）。
///
/// 接续之所以成立：斗鱼 flv tag 用推流会话的绝对时间戳，重新取流后时间轴
/// 延续而非归零，因此不需要改写时间戳，只要丢掉新流的文件头与初始化 tag，
/// 并从第一个未落后于已转发位置的关键帧接上即可（见 [FlvDemuxer]）。
class StreamRelayService extends GetxService {
  static StreamRelayService get instance => Get.find<StreamRelayService>();

  /// 直播直链的寿命。斗鱼实测各线路误差 < 0.5s（部分线路 URL 甚至不带
  /// expire 参数但同样准时断开，是服务端策略）。测试里会调短。
  Duration streamTtl = const Duration(seconds: 300);

  /// 提前多久预取下一条流。实测取流 ~650ms + 首个关键帧 ~220ms，
  /// 留过长会让预取连接在切换前积压过多数据。
  Duration renewLead = const Duration(seconds: 5);

  /// 预取连接挂着不用的上限：超过仍未用上，说明这条直链寿命明显长于
  /// [streamTtl]，放弃预取，避免白白挂一条连接。
  Duration prefetchHold = const Duration(seconds: 30);

  /// 上游静默多久视为卡死，按「旧流结束」处理并尝试续流。
  Duration readTimeout = const Duration(seconds: 15);

  /// 建立上游连接的超时。
  Duration openTimeout = const Duration(seconds: 20);

  /// 旧流结束后，连续续流失败多少次放弃（交回给上层重试）。
  int maxRenewFailures = 5;

  /// 续流失败后的重试间隔。
  Duration renewRetryDelay = const Duration(milliseconds: 500);

  /// 接续段等待「首个未落后于旧流位置的关键帧」的上限。超时放弃本次接续，
  /// 关闭响应交给上层重试（覆盖主播重开播导致时间轴重置等场景）。
  Duration keyframeWaitTimeout = const Duration(seconds: 10);

  /// 给 CDN 的默认 UA。与 DTV 保持一致：浏览器 UA 对防盗链最稳妥。
  static const String defaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  HttpServer? _server;
  int _port = 0;
  final Map<String, _RelaySession> _sessions = {};

  /// 中转地址前缀，用于判断一个播放地址是否由本服务下发。
  bool isRelayUrl(String url) => url.startsWith("http://127.0.0.1:$_port/s/");

  /// 登记一条直链的续流会话，返回应下发给播放器的本地地址。
  ///
  /// [renew] 为空时退化为纯转发（上游结束即结束），行为与直连一致。
  Future<String> register({
    required String url,
    StreamRenewContext? renew,
    Map<String, String>? headers,
  }) async {
    await _ensureServer();
    final token = const Uuid().v4().replaceAll("-", "");
    _sessions[token] = _RelaySession(this, token, url, renew, headers);
    return "http://127.0.0.1:$_port/s/$token.flv";
  }

  /// 释放 [register] 返回的地址对应的会话：断开其上游连接，后续请求返回 404。
  void release(String localUrl) {
    final marker = "/s/";
    final start = localUrl.indexOf(marker);
    if (start < 0) {
      return;
    }
    var token = localUrl.substring(start + marker.length);
    if (token.endsWith(".flv")) {
      token = token.substring(0, token.length - 4);
    }
    _sessions.remove(token)?.dispose();
  }

  /// 关闭中转服务并释放全部会话（用于测试与重启）。
  Future<void> shutdown() async {
    for (final session in _sessions.values.toList()) {
      session.dispose();
    }
    _sessions.clear();
    final server = _server;
    _server = null;
    _port = 0;
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) {
      return existing;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      _handleRequest,
      onError: (Object e) => Log.d("[relay] 中转服务异常: $e"),
    );
    _server = server;
    _port = server.port;
    Log.i("[relay] 续流中转服务已启动: http://127.0.0.1:$_port");
    return server;
  }

  void _handleRequest(HttpRequest request) async {
    if (request.method != "GET") {
      // 只服务拉流；播放器（mpv/ffmpeg）只会发 GET，其他方法一律拒绝，
      // 避免为一次探测就白开一条上游连接。
      await _reject(request, HttpStatus.methodNotAllowed);
      return;
    }
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != "s") {
      await _reject(request, HttpStatus.notFound);
      return;
    }
    var token = segments[1];
    if (token.endsWith(".flv")) {
      token = token.substring(0, token.length - 4);
    }
    final session = _sessions[token];
    if (session == null || session.disposed) {
      await _reject(request, HttpStatus.notFound);
      return;
    }
    await session.serve(request);
  }

  Future<void> _reject(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      await request.response.close();
    } catch (_) {
      // 客户端可能已经断开，忽略。
    }
  }
}

/// 续流上下文：中转在旧流到期前据此重新取一条直链。
///
/// 与 DTV 的 `StreamRenewContext` 同构——上层只登记「重取需要什么」（房间、
/// 清晰度、线路）和取流入口，由中转自己调用；core 不再需要下发 renewer。
class StreamRenewContext {
  StreamRenewContext({
    required this.roomId,
    required this.quality,
    required this.line,
    required Future<List<String>> Function() fetchUrls,
  }) : _fetchUrls = fetchUrls;

  /// 房间号（日志用）。
  final String roomId;

  /// 清晰度名（日志用）。
  final String quality;

  /// 线路下标，与注册时 `urls` 的顺序一致。
  final int line;

  /// 重新取流的入口：返回该清晰度下的全部线路地址。
  final Future<List<String>> Function() _fetchUrls;

  /// 取回本线路的新直链。
  ///
  /// 线路顺序由 core 按同一份 cdns 稳定排序，正常情况下下标一一对应；
  /// 线路数变少时退回第一条，至少保证拿到同清晰度的可用直链。
  Future<String> resolve() async {
    final urls = await _fetchUrls();
    if (urls.isEmpty) {
      throw StateError("续流失败：取流接口没有返回播放地址（房间 $roomId）");
    }
    return urls[line < urls.length ? line : 0];
  }

  @override
  String toString() => "StreamRenewContext(room: $roomId, quality: $quality, line: $line)";
}

/// 一条直链的续流会话：保存重新取流所需的信息，派发并发的中转请求。
///
/// 会话本身不持有连接；每个 HTTP 请求对应一个独立的 [_RelayPipe]，
/// 与直连时播放器对同一 URL 建多条连接的行为一致。
class _RelaySession {
  _RelaySession(this.service, this.token, this.initialUrl, this.renew, this.headers);

  final StreamRelayService service;
  final String token;

  /// 取流接口刚下发的直链。首个请求优先使用它（省一次接口调用，
  /// 进入房间的等待不变），之后一律重新取流，避免拿到过期直链。
  final String initialUrl;

  /// 续流上下文；为空时退化为纯转发。
  final StreamRenewContext? renew;

  /// 转发给上游的请求头。
  final Map<String, String>? headers;

  final Set<_RelayPipe> _pipes = {};
  bool _initialUrlAvailable = true;
  bool disposed = false;

  Future<void> serve(HttpRequest request) async {
    if (disposed) {
      try {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (_) {}
      return;
    }
    final pipe = _RelayPipe(this);
    _pipes.add(pipe);
    try {
      await pipe.run(request.response);
    } catch (e) {
      Log.d("[relay] 会话 $token 中转异常: $e");
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      _pipes.remove(pipe);
    }
  }

  /// 解析一条可用于连接的上游直链。
  Future<String> resolveUrl() async {
    if (_initialUrlAvailable) {
      _initialUrlAvailable = false;
      return initialUrl;
    }
    final renew = this.renew;
    if (renew == null) {
      return initialUrl;
    }
    return await renew.resolve();
  }

  void dispose() {
    disposed = true;
    for (final pipe in _pipes.toList()) {
      pipe.abort();
    }
    _pipes.clear();
  }
}

/// 一次中转请求（一个 HTTP 响应）的执行体。
class _RelayPipe {
  _RelayPipe(this.session);

  final _RelaySession session;

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  HttpResponse? _response;
  _Segment? _segment;
  final FlvTimeline _timeline = FlvTimeline();
  _Prefetch? _prefetch;

  /// 首段能否按 FLV 解析（不能就放弃维护时间轴，避免浪费）。
  bool _trackTimeline = true;

  bool _finished = false;

  bool get _renewable => session.renew != null;

  Future<void> run(HttpResponse response) async {
    _response = response;

    final _Upstream first;
    try {
      first = await _acquire();
    } catch (e) {
      Log.d("[relay] 打开上游失败: $e");
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      // 复用统一的收尾：关闭响应与 HttpClient。
      await _finish();
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType("video", "x-flv");
    response.headers.set(HttpHeaders.cacheControlHeader, "no-store");
    _segment = _Segment(first, continuation: false);

    await _pump();
  }

  Future<void> _pump() async {
    while (!_finished) {
      _schedulePrefetch();

      List<int>? chunk;
      var ended = false;
      try {
        final segment = _segment!;
        final hasNext = await segment.iterator.moveNext().timeout(session.service.readTimeout);
        if (hasNext) {
          chunk = segment.iterator.current;
        } else {
          ended = true;
        }
      } catch (e) {
        if (!_finished) {
          Log.d("[relay] 上游读取结束/异常: $e");
        }
        ended = true;
      }
      if (_finished) {
        break;
      }

      if (ended) {
        final next = await _acquireNext();
        if (_finished) {
          break;
        }
        if (next == null) {
          break;
        }
        // 旧连接已结束（或已判死），顺手放掉它的迭代器。
        final previous = _segment;
        if (previous != null) {
          unawaited(previous.upstream.close());
        }
        _segment = _Segment(next, continuation: true);
        continue;
      }

      if (_segment!.continuation) {
        if (!await _forwardContinuation(chunk!)) {
          break;
        }
      } else {
        if (!await _send(chunk!)) {
          break;
        }
        _trackFirstSegment(chunk);
      }
    }

    await _finish();
  }

  // ------------------------------------------------------------------ 预取与续流

  /// 旧流临近到期时提前取好下一条；挂太久没用上则放弃（直链寿命明显更长）。
  void _schedulePrefetch() {
    if (!_renewable) {
      return;
    }
    final segment = _segment!;
    if (segment.prefetchDisabled) {
      return;
    }
    final now = DateTime.now();
    final prefetch = _prefetch;
    if (prefetch != null) {
      if (now.difference(prefetch.createdAt) > session.service.prefetchHold) {
        prefetch.abandon();
        _prefetch = null;
        segment.prefetchDisabled = true;
        Log.d("[relay] 预取长时间未用上，本段起停止预取");
      }
      return;
    }
    if (now.difference(segment.startedAt) + session.service.renewLead >=
        session.service.streamTtl) {
      _prefetch = _Prefetch(_acquire(), createdAt: now);
    }
  }

  /// 旧流结束（EOF / 错误 / 静默超时）后取接续段：优先用预取，失败则同步补取。
  Future<_Upstream?> _acquireNext() async {
    if (!_renewable) {
      return null;
    }

    final prefetch = _prefetch;
    _prefetch = null;
    if (prefetch != null) {
      final upstream = await prefetch.take();
      if (upstream != null) {
        Log.d("[relay] 旧流结束，使用预取的新流接续");
        return upstream;
      }
    }

    for (var i = 0; i < session.service.maxRenewFailures; i++) {
      try {
        final upstream = await _acquire();
        Log.d("[relay] 已重新取流接续（第 ${i + 1} 次尝试）");
        return upstream;
      } catch (e) {
        Log.d("[relay] 续流失败 ${i + 1}/${session.service.maxRenewFailures}: $e");
        if (i < session.service.maxRenewFailures - 1) {
          await Future<void>.delayed(session.service.renewRetryDelay);
        }
      }
      if (_finished) {
        return null;
      }
    }
    Log.d("[relay] 续流放弃，本次中转结束（由播放层重试）");
    return null;
  }

  Future<_Upstream> _acquire() async {
    final url = await session.resolveUrl();
    final request = await _client.getUrl(Uri.parse(url)).timeout(session.service.openTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, StreamRelayService.defaultUserAgent);
    session.headers?.forEach((key, value) {
      request.headers.set(key, value);
    });
    final response = await request.close().timeout(session.service.openTimeout);
    if (response.statusCode != HttpStatus.ok) {
      final status = response.statusCode;
      await response.drain<void>().catchError((Object _) {});
      throw HttpException("上游返回 $status", uri: Uri.parse(url));
    }
    return _Upstream(StreamIterator<List<int>>(response));
  }

  // ------------------------------------------------------------------ 数据转发

  /// 首段：原样转发上游字节块，写入粒度与上游一致（逐 tag 转发会把一次写
  /// 放大成几十次，反而拖累播放流畅度）。同时旁路解析，记录时间轴位置。
  void _trackFirstSegment(List<int> chunk) {
    if (!_renewable || !_trackTimeline) {
      return;
    }
    final demuxer = _segment!.demuxer;
    demuxer.push(chunk);
    // 文件头已随原始字节发出，这里仅消费掉。
    demuxer.takeHeader();
    while (true) {
      final tag = demuxer.nextTag(keepRaw: false);
      if (tag == null) {
        break;
      }
      _timeline.observe(tag);
    }
    if (demuxer.isDesynced) {
      // 不是可解析的 FLV，放弃维护时间轴，退化为纯转发。
      Log.d("[relay] 上游不是可解析的 FLV，停止时间轴跟踪");
      _trackTimeline = false;
      demuxer.reset();
    }
  }

  /// 接续段：丢弃文件头与初始化 tag，从第一个未落后于旧流位置的关键帧接上，
  /// 并丢掉 CDN 回吐的重复 GOP。返回 false 表示应当结束本次中转。
  Future<bool> _forwardContinuation(List<int> chunk) async {
    final segment = _segment!;
    final demuxer = segment.demuxer;
    demuxer.push(chunk);
    // 接续段的文件头必须丢弃，播放器只认首段那一个。
    demuxer.takeHeader();

    final out = BytesBuilder(copy: false);
    var aborted = false;
    while (true) {
      final tag = demuxer.nextTag();
      if (tag == null) {
        break;
      }
      if (segment.waitingForKeyframe) {
        // 丢掉元数据与初始化 tag，播放器已经初始化过了。
        if (tag.tagType == kFlvTagTypeScript || tag.isSequenceHeader) {
          continue;
        }
        // 从第一个未落后于旧流位置的关键帧开始接。
        final usable = tag.tagType == kFlvTagTypeVideo &&
            tag.isKeyframe &&
            _timeline.isNotBehind(tag);
        if (!usable) {
          // 一直等不到合适的关键帧（主播重开播导致时间轴重置等）：
          // 放弃本次接续，关闭响应交给播放层的重试逻辑。
          if (DateTime.now().difference(segment.startedAt) >
              session.service.keyframeWaitTimeout) {
            Log.d("[relay] 等待接续关键帧超时，放弃");
            aborted = true;
            break;
          }
          continue;
        }
        segment.waitingForKeyframe = false;
        Log.d("[relay] 已对齐到接续关键帧 ts=${tag.timestamp}");
      } else if (tag.tagType != kFlvTagTypeScript && !_timeline.isNotBehind(tag)) {
        // CDN 会回吐一个 GOP 的缓冲，重复部分直接丢弃。
        continue;
      }

      _timeline.observe(tag);
      out.add(tag.raw);
    }

    // 聚合后一次发出，保持与首段相近的写入粒度。
    if (out.length > 0 && !await _send(out.takeBytes())) {
      return false;
    }
    return !aborted;
  }

  Future<bool> _send(List<int> bytes) async {
    final response = _response;
    if (response == null || _finished) {
      return false;
    }
    try {
      response.add(bytes);
      await response.flush();
      return true;
    } catch (e) {
      Log.d("[relay] 客户端已断开: $e");
      return false;
    }
  }

  // ------------------------------------------------------------------ 收尾

  /// 由会话在释放时调用：中断上游读取并关闭响应，播放器会看到流结束。
  void abort() {
    if (_finished) {
      return;
    }
    unawaited(_finish());
  }

  Future<void> _finish() async {
    if (_finished) {
      return;
    }
    _finished = true;
    _prefetch?.abandon();
    _prefetch = null;
    try {
      await _segment?.upstream.close();
    } catch (_) {}
    _client.close(force: true);
    try {
      await _response?.close();
    } catch (_) {}
  }
}

/// 一条上游流的读取状态。
class _Segment {
  _Segment(this.upstream, {required this.continuation})
      : demuxer = FlvDemuxer(),
        startedAt = DateTime.now(),
        waitingForKeyframe = continuation;

  final _Upstream upstream;
  StreamIterator<List<int>> get iterator => upstream.iterator;
  final FlvDemuxer demuxer;
  final DateTime startedAt;

  /// 是否为接续段。首段原样转发上游字节块；接续段需要在 tag 边界上裁剪。
  final bool continuation;

  /// 接续段在遇到第一个可用关键帧之前不转发任何内容。
  bool waitingForKeyframe;

  /// 预取长时间用不上后置位：本段不再尝试预取。
  bool prefetchDisabled = false;
}

class _Upstream {
  _Upstream(this.iterator);

  final StreamIterator<List<int>> iterator;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await iterator.cancel();
  }
}

/// 一次「提前取好的下一条流」。连接已建立（响应头已到），但先不读响应体：
/// 等旧流结束再消费，避免预取的数据大量堆在内存里。
class _Prefetch {
  _Prefetch(Future<_Upstream> future, {required this.createdAt}) {
    future.then(
      (upstream) {
        if (_abandoned) {
          unawaited(upstream.close());
        } else {
          _upstream = upstream;
        }
        _done.complete();
      },
      onError: (Object e) {
        _error = e;
        _done.complete();
      },
    );
  }

  final DateTime createdAt;
  final Completer<void> _done = Completer<void>();
  _Upstream? _upstream;
  Object? _error;
  bool _abandoned = false;

  /// 放弃：已就绪则立刻断开，未就绪则等它返回后断开。
  void abandon() {
    _abandoned = true;
    final upstream = _upstream;
    _upstream = null;
    if (upstream != null) {
      unawaited(upstream.close());
    }
  }

  /// 取结果；已被放弃或失败时返回 null。
  Future<_Upstream?> take() async {
    await _done.future;
    if (_abandoned) {
      return null;
    }
    final error = _error;
    if (error != null) {
      Log.d("[relay] 预取失败: $error");
      return null;
    }
    final upstream = _upstream;
    _upstream = null;
    return upstream;
  }
}
