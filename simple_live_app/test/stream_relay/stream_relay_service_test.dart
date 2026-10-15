import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/stream_relay/flv_demuxer.dart';
import 'package:simple_live_app/services/stream_relay/stream_relay_service.dart';

/// 拼出一个最小 FLV tag（11 字节头 + data + 4 字节 PreviousTagSize）。
Uint8List _makeTag(int tagType, int timestamp, List<int> data) {
  final out = BytesBuilder();
  out.addByte(tagType);
  final size = data.length;
  out.add([(size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff]);
  out.add([
    (timestamp >> 16) & 0xff,
    (timestamp >> 8) & 0xff,
    timestamp & 0xff,
    (timestamp >> 24) & 0xff,
  ]);
  out.add([0, 0, 0]);
  out.add(data);
  final prev = 11 + size;
  out.add([(prev >> 24) & 0xff, (prev >> 16) & 0xff, (prev >> 8) & 0xff, prev & 0xff]);
  return out.toBytes();
}

Uint8List _flvHeader() {
  final out = BytesBuilder();
  out.add([0x46, 0x4C, 0x56, 0x01, 0x05]);
  out.add([0, 0, 0, 9]);
  out.add([0, 0, 0, 0]);
  return out.toBytes();
}

/// 假的斗鱼 CDN，模拟真实行为的三个关键点：
///
/// 1. **会话绝对时间戳**：tag 时间戳按会话时钟（墙钟）生成，跨连接延续、
///    不归零——这是断点接续能成立的前提（与真实推流一致）；
/// 2. **直链到期主动断开**：每条连接活满 [segmentLifetime] 后 EOF，
///    模拟斗鱼直链 300 秒到点被 CDN 掐断；
/// 3. **重连回吐**：第 2 条起的连接先回吐一段旧 GOP（时间戳倒退），
///    模拟 CDN 缓冲回放，中继必须去重。
class _FakeCdn {
  _FakeCdn({
    required this.segmentLifetime,
    this.resetTimelineOnReconnect = false,
  });

  final Duration segmentLifetime;

  /// 为 true 时，重连后的流从 0 重新计时，模拟主播中途重开播导致推流会话
  /// 时间轴重置（接续对它无解，中继应放弃本次接续并交回上层）。
  final bool resetTimelineOnReconnect;

  /// 每个 tick 的间隔（同时是时间戳步长）。
  final Duration tagInterval = const Duration(milliseconds: 20);

  /// 每个 tag 的负载大小。按真实直播流的量级来（~100KB/s），
  /// 太小的合成流会在测试机的 socket 缓冲里积压，量不出真实行为。
  final int tagPayload = 1024;

  /// 每多少个视频 tag 出一个关键帧。
  final int keyframeEvery = 4;

  /// 重连时回吐多少个旧 tag。
  final int replayTags = 3;

  late HttpServer _server;
  late DateTime _sessionEpoch;

  /// 已接受的连接数（含中继的预取）。
  int connections = 0;

  /// 会话时钟起点（毫秒），用绝对量级模拟真实推流时间戳。
  static const int _epochBaseMs = 3600 * 1000;

  String get url => "http://127.0.0.1:${_server.port}/live.flv";

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _sessionEpoch = DateTime.now();
    _server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  int _nowMs() => _epochBaseMs + DateTime.now().difference(_sessionEpoch).inMilliseconds;

  void _handle(HttpRequest request) async {
    final response = request.response;
    response.statusCode = 200;
    response.headers.contentType = ContentType("video", "x-flv");
    connections += 1;
    final index = connections;

    // 时间轴重置模式：重连后的连接从 0 重新计时。
    final resetBase = resetTimelineOnReconnect && index > 1;
    final connStarted = DateTime.now();
    int nowMs() => resetBase
        ? DateTime.now().difference(connStarted).inMilliseconds
        : _nowMs();

    List<int> videoPayload(bool keyframe) =>
        [keyframe ? 0x17 : 0x27, 0x01, ...List<int>.filled(tagPayload, 0)];
    List<int> audioPayload() => [0xaf, 0x01, ...List<int>.filled(tagPayload, 0)];

    Future<void> write(List<int> bytes) async {
      response.add(bytes);
      await response.flush();
    }

    try {
      await write(_flvHeader());
      // 初始化 tag：AVC / AAC sequence header。
      await write(_makeTag(kFlvTagTypeVideo, 0, [0x17, 0x00, 0x00, 0x00]));
      await write(_makeTag(kFlvTagTypeAudio, 0, [0xaf, 0x00, 0x11]));

      // 重连回吐：一个旧 GOP，时间戳整体倒退回过去。
      if (index > 1 && !resetBase) {
        final replayAt = nowMs() - replayTags * 100;
        for (var i = 0; i < replayTags; i++) {
          final ts = replayAt + i * 100;
          await write(_makeTag(kFlvTagTypeVideo, ts, videoPayload(i == 0)));
          await write(_makeTag(kFlvTagTypeAudio, ts, audioPayload()));
        }
      }

      final started = DateTime.now();
      var tick = 0;
      while (DateTime.now().difference(started) < segmentLifetime) {
        await Future<void>.delayed(tagInterval);
        final ts = nowMs();
        final keyframe = tick % keyframeEvery == 0;
        tick += 1;
        await write(_makeTag(kFlvTagTypeVideo, ts, videoPayload(keyframe)));
        await write(_makeTag(kFlvTagTypeAudio, ts, audioPayload()));
      }
    } catch (_) {
      // 客户端已断开。
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

class _Collected {
  _Collected(this.statusCode, this.bytes, this.ended);

  final int statusCode;
  final Uint8List bytes;

  /// 收集窗口结束时客户端侧是否已经收到流结束。
  final bool ended;
}

/// 连上中转地址收 [window] 时间的数据。
Future<_Collected> _collect(String url, Duration window) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  final builder = BytesBuilder();
  var ended = false;
  response.listen(
    builder.add,
    onDone: () => ended = true,
    onError: (Object _) => ended = true,
    cancelOnError: false,
  );
  await Future<void>.delayed(window);
  final result = _Collected(response.statusCode, builder.takeBytes(), ended);
  client.close(force: true);
  return result;
}

Future<void> _waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError("等待条件超时");
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('直链到期后自动续流：对播放器表现为一条连续的 FLV', () async {
    final cdn = _FakeCdn(segmentLifetime: const Duration(milliseconds: 700));
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService()
      ..streamTtl = const Duration(milliseconds: 600)
      ..renewLead = const Duration(milliseconds: 200)
      ..prefetchHold = const Duration(seconds: 3)
      ..readTimeout = const Duration(seconds: 5)
      ..keyframeWaitTimeout = const Duration(seconds: 5);
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(url: cdn.url, renewer: () async => cdn.url);
    final collected = await _collect(relayUrl, const Duration(milliseconds: 2400));

    expect(collected.statusCode, 200);
    // 收集窗口内应该跨过了多条上游连接（模拟直链多次到期）。
    expect(cdn.connections, greaterThanOrEqualTo(3));
    // 客户端侧流不应结束：续流把断点接上了。
    expect(collected.ended, isFalse);
    expect(collected.bytes.length, greaterThan(0));

    // 整条输出应当是一条合法且连续的 FLV：一个文件头、初始化 tag 只在
    // 开头出现一次、音视频时间戳都严格递增（无重复/倒退的 tag）。
    final demuxer = FlvDemuxer();
    demuxer.push(collected.bytes);
    expect(demuxer.takeHeader(), isNotNull, reason: "输出应以 FLV 文件头开头");

    final videoTs = <int>[];
    final audioTs = <int>[];
    var sequenceHeaders = 0;
    while (true) {
      final tag = demuxer.nextTag();
      if (tag == null) {
        break;
      }
      if (tag.isSequenceHeader) {
        sequenceHeaders += 1;
      }
      if (tag.tagType == kFlvTagTypeVideo) {
        videoTs.add(tag.timestamp);
      } else if (tag.tagType == kFlvTagTypeAudio) {
        audioTs.add(tag.timestamp);
      }
    }

    expect(sequenceHeaders, 2, reason: "接续段的初始化 tag 必须被丢弃");
    expect(videoTs.length, greaterThan(50), reason: "输出应覆盖多段上游流");
    for (var i = 1; i < videoTs.length; i++) {
      expect(videoTs[i], greaterThan(videoTs[i - 1]), reason: "视频时间戳必须严格递增");
    }
    for (var i = 1; i < audioTs.length; i++) {
      expect(audioTs[i], greaterThan(audioTs[i - 1]), reason: "音频时间戳必须严格递增");
    }
  });

  test('上游结束但没有续流能力时：上游结束即结束（行为与直连一致）', () async {
    final cdn = _FakeCdn(segmentLifetime: const Duration(milliseconds: 300));
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService();
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(url: cdn.url);
    final collected = await _collect(relayUrl, const Duration(milliseconds: 1200));

    expect(collected.statusCode, 200);
    expect(collected.ended, isTrue);
    expect(cdn.connections, 1, reason: "没有续流能力就不应重开上游连接");

    final demuxer = FlvDemuxer();
    demuxer.push(collected.bytes);
    expect(demuxer.takeHeader(), isNotNull);
  });

  test('续流连续失败达到上限后结束本次中转，交回上层重试', () async {
    final cdn = _FakeCdn(segmentLifetime: const Duration(milliseconds: 300));
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService()
      ..streamTtl = const Duration(seconds: 30) // 不预取，走“旧流结束后同步续流”路径
      ..maxRenewFailures = 2
      ..renewRetryDelay = const Duration(milliseconds: 10)
      ..readTimeout = const Duration(seconds: 3);
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(
      url: cdn.url,
      renewer: () async => throw StateError("取流接口挂了"),
    );
    final collected = await _collect(relayUrl, const Duration(milliseconds: 1500));

    expect(collected.statusCode, 200);
    expect(collected.ended, isTrue, reason: "续流放弃后应关闭响应，让播放层走重试");
    expect(cdn.connections, 1);
    expect(collected.bytes.length, greaterThan(0), reason: "放弃前已转发的数据仍然有效");
  });

  test('直链寿命明显长于 TTL 时：放弃这次预取，不再白挂连接', () async {
    // 直链一直不断（寿命比 TTL 长），预取挂满 prefetchHold 后应被放弃。
    final cdn = _FakeCdn(segmentLifetime: const Duration(seconds: 5));
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService()
      ..streamTtl = const Duration(milliseconds: 300)
      ..renewLead = const Duration(milliseconds: 100)
      ..prefetchHold = const Duration(milliseconds: 500)
      ..readTimeout = const Duration(seconds: 5);
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(url: cdn.url, renewer: () async => cdn.url);
    final collected = await _collect(relayUrl, const Duration(milliseconds: 1500));

    expect(collected.statusCode, 200);
    expect(collected.bytes.length, greaterThan(0));
    // 首连 + 一次预取；放弃后本段不应再重开连接。
    expect(cdn.connections, 2);
    expect(collected.ended, isFalse);
  });

  test('重连后时间轴重置（主播重开播）时：放弃接续并交回上层重试', () async {
    final cdn = _FakeCdn(
      segmentLifetime: const Duration(milliseconds: 700),
      resetTimelineOnReconnect: true,
    );
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService()
      ..streamTtl = const Duration(milliseconds: 600)
      ..renewLead = const Duration(milliseconds: 200)
      ..prefetchHold = const Duration(seconds: 3)
      ..readTimeout = const Duration(seconds: 5)
      ..keyframeWaitTimeout = const Duration(milliseconds: 500);
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(url: cdn.url, renewer: () async => cdn.url);
    final collected = await _collect(relayUrl, const Duration(milliseconds: 2000));

    expect(collected.statusCode, 200);
    expect(collected.bytes.length, greaterThan(0), reason: "首段数据仍应转发");
    // 接续段等不到越过旧位置的关键帧（时间轴重置），应超时放弃、关闭响应。
    expect(collected.ended, isTrue);
  });

  test('释放会话后：正在播放的中断，新请求 404', () async {
    final cdn = _FakeCdn(segmentLifetime: const Duration(seconds: 30));
    await cdn.start();
    addTearDown(cdn.stop);

    final relay = StreamRelayService()..readTimeout = const Duration(seconds: 5);
    addTearDown(relay.shutdown);

    final relayUrl = await relay.register(url: cdn.url, renewer: () async => cdn.url);

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(relayUrl));
    final response = await request.close();
    var received = 0;
    final ended = Completer<void>();
    response.listen(
      (chunk) => received += chunk.length,
      onDone: ended.complete,
      onError: (Object _) => ended.complete(),
      cancelOnError: false,
    );
    await _waitFor(() => received > 0);

    relay.release(relayUrl);
    await ended.future.timeout(const Duration(seconds: 2), onTimeout: () {});

    final again = await client.getUrl(Uri.parse(relayUrl));
    final second = await again.close();
    expect(second.statusCode, HttpStatus.notFound);
    await second.drain<void>();
    client.close(force: true);
  });
}
