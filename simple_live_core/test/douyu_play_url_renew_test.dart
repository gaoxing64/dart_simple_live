// 回归测试：斗鱼必须为每条 flv 线路提供「续流回调」，且续流与首取共用同一条
// `expire=0` 海外兜底规则。
//
// 背景：斗鱼下发给第三方的 flv 直链固定 300 秒寿命，到点 CDN 主动 EOF；
// 游客模式（未配置 cookie）只能拿到这种短效直链，播放约 5 分钟即断流。
// App 层的续流中转（simple_live_app 的 StreamRelayService）依赖 core 提供
// `LivePlayUrl.renewers` 才能重新取流；漏掉某条线路或漏做兜底都会表现为
// 「续流拿回的直链又是 5 分钟寿命」。
//
// 本用例通过注入 HttpClientAdapter 喂固定响应，**不依赖网络**。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
// 同包内引用 src 是允许的（lint 只限制跨包 implementation_imports）
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

/// 按 URL 路径分派响应的适配器；`getH5PlayV1` 每次调用返回不同的 `wsAuth`，
/// 用来证明「续流确实重新取了一次流」。
///
/// [liveUrl] 按调用序号（从 1 开始）生成 `rtmp_live`。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter({required this.liveUrl});

  final String Function(int call) liveUrl;
  int playCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String body;
    if (options.uri.path.contains("getEncryption")) {
      body = jsonEncode({
        "error": 0,
        "data": {
          "rand_str": "rand",
          "enc_time": 1,
          "is_special": 0,
          "key": "key",
          "enc_data": "enc",
        },
      });
    } else {
      playCalls += 1;
      body = jsonEncode({
        "error": 0,
        "data": {
          "rtmp_url": "https://cdn.example.com/live",
          "rtmp_live": liveUrl(playCalls),
        },
      });
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LiveRoomDetail _detail() => LiveRoomDetail(
      cover: '',
      online: 0,
      roomId: '252140',
      status: true,
      title: '',
      url: '',
      userAvatar: '',
      userName: '',
    );

void main() {
  late void Function() restore;

  tearDown(() {
    restore();
  });

  void useAdapter(HttpClientAdapter adapter) {
    final dio = HttpClient.instance.dio;
    final original = dio.httpClientAdapter;
    dio.httpClientAdapter = adapter;
    restore = () => dio.httpClientAdapter = original;
  }

  test('每条 flv 线路都有续流回调，续流会重新取流并保持 expire 兜底', () async {
    // 奇数调用给「海外 ws 线路」（带 expire=300 & fcdn=ws），偶数给普通线路，
    // 用来同时覆盖两条分支。
    final adapter = _RoutingAdapter(
      liveUrl: (call) => call.isOdd
          ? "252140rabc_900.flv?wsAuth=ws$call&expire=300&fcdn=ws"
          : "252140rabc_900.flv?wsAuth=plain$call",
    );
    useAdapter(adapter);

    final site = DouyuSite();
    final playUrl = await site.getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(
        quality: '高清',
        data: DouyuPlayData(900, ['hw-h5', 'scdn-aaa']),
      ),
    );

    // 两条线路都要有续流回调。
    expect(playUrl.urls.length, 2);
    expect(playUrl.renewers, isNotNull);
    expect(playUrl.renewers!.length, 2);
    expect(playUrl.renewers!.every((r) => r != null), isTrue);

    // 首取：ws 线路追加 expire=0（海外临时兜底），普通线路保持原样。
    expect(playUrl.urls[0], contains('wsAuth=ws1'));
    expect(playUrl.urls[0], endsWith('&expire=0'));
    expect(playUrl.urls[1], contains('wsAuth=plain2'));
    expect(playUrl.urls[1], isNot(contains('expire=0')));

    // 续流：真的重新调了一次取流接口（wsAuth 递增），且兜底规则依然生效。
    final renewed = await playUrl.renewers![0]!();
    expect(renewed, contains('wsAuth=ws3'));
    expect(renewed, endsWith('&expire=0'));
  });

  test('非 flv 线路不提供续流回调（无法在 tag 边界上接续）', () async {
    useAdapter(_RoutingAdapter(liveUrl: (call) => "252140rabc.m3u8?wsAuth=hls"));

    final site = DouyuSite();
    final playUrl = await site.getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(
        quality: '高清',
        data: DouyuPlayData(900, ['hw-h5']),
      ),
    );

    expect(playUrl.urls.length, 1);
    // 唯一线路不是 flv → 全为 null 时整体置 null（播放层按直连处理）。
    expect(playUrl.renewers, isNull);
  });
}
