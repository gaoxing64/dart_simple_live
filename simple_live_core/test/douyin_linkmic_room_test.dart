// 回归测试：抖音「连麦/多人连线」房间进不去（NoSuchMethodError）。
//
// 2026-09 实测：由分享链接解出来的 19 位 roomId 走的是
// `webcast.amemv.com/douyin/webcast/reflow/<roomId>` → webRid → 再请求
// `live.douyin.com/webcast/room/web/enter/`。对连麦类房间，web/enter 会返回
// **降级房间**：只剩 22 个字段的骨架，`status != 2`、没有 `stream_url`，
// 于是 `detail.data` 变成空 Map，紧接着 `getPlayQualites` 里
// `detail.data["live_core_sdk_data"]["pull_data"]` 抛
// `NoSuchMethodError: The method '[]' was called on null`，直播间直接「加载失败」。
// 网页兜底路径同样会炸在 `roomStore.roomInfo.room["id_str"]`。
//
// 同一房间用 `webcast.amemv.com/webcast/room/reflow/info/?room_id=<roomId>`
// 查则能拿到完整房间（status=2 + stream_url + 画质列表）。
//
// 因此现在的策略是：
//   1. 19 位 roomId 先走 reflow/info（不再无条件转 webRid 走 web/enter）；
//   2. 进房接口「说在播却没有拉流数据」时，用 reflow/info 补 stream_url；
//   3. 所有取数路径判空，拿不到就给 CoreError/空画质，绝不抛空指针。
//
// 本用例通过注入 HttpClientAdapter 喂固定响应，**不依赖网络**。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
// 同包内引用 src 是允许的（lint 只限制跨包 implementation_imports）
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

const kLongRoomId = '7685673385436744454';
const kWebRid = '332149493172';

ResponseBody _json(String body) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _html(String body) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );

/// 按 URL 分发的适配器，同时记录所有请求过的地址。
class _RoutedAdapter implements HttpClientAdapter {
  _RoutedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 完整的 stream_url（含 live_core_sdk_data），与线上在播房间同构
Map<String, dynamic> _streamUrl() => {
      'flv_pull_url': {'FULL_HD1': 'http://flv/uhd', 'SD1': 'http://flv/ld'},
      'hls_pull_url_map': {
        'FULL_HD1': 'http://hls/uhd',
        'SD1': 'http://hls/ld'
      },
      'live_core_sdk_data': {
        'pull_data': {
          'options': {
            'qualities': [
              {'name': '标清', 'sdk_key': 'ld', 'level': 1},
              {'name': '超清', 'sdk_key': 'hd', 'level': 3},
            ],
          },
          'stream_data': jsonEncode({
            'data': {
              'ld': {
                'main': {'flv': 'http://flv/ld', 'hls': 'http://hls/ld'}
              },
              'hd': {
                'main': {'flv': 'http://flv/hd', 'hls': 'http://hls/hd'}
              },
            },
          }),
        },
      },
    };

/// web/enter 的降级骨架：没有 stream_url / owner，status 也不是 2
Map<String, dynamic> _degradedEnter() => {
      'data': {
        'data': [
          {'id_str': kLongRoomId, 'status': 4, 'title': '房间标题'},
        ],
        'user': {'nickname': '主播'},
      },
    };

/// 网页版在「已下播/不存在」时的 state：只有 roomInfo.web_rid，没有 room
String _endedHtml() {
  const escaped =
      '{\\"state\\":{\\"appStore\\":{},\\"roomStore\\":{\\"roomInfo\\":'
      '{\\"web_rid\\":\\"$kWebRid\\"}}}}]\\n';
  return '<script>self.__pace_f.push([1,"d:$escaped"])</script>';
}

void Function() _useAdapter(_RoutedAdapter adapter) {
  final dio = HttpClient.instance.dio;
  final original = dio.httpClientAdapter;
  dio.httpClientAdapter = adapter;
  return () => dio.httpClientAdapter = original;
}

void main() {
  // 给默认空实现：用例在赋值之前失败时，tearDown 调 restore() 会抛
  // LateInitializationError，把真正的失败原因盖掉。
  void Function() restore = () {};

  tearDown(() {
    restore();
  });

  test('长 roomId 直接查 reflow/info，且正常拿到画质', () async {
    late _RoutedAdapter adapter;
    adapter = _RoutedAdapter((options) {
      if (options.uri.path.contains('/webcast/room/reflow/info/')) {
        return _json(jsonEncode({
          'data': {
            'room': {
              'id_str': kLongRoomId,
              'status': 2,
              'title': '黑白-（一字斩）正在直播',
              'owner': {'web_rid': kWebRid, 'nickname': '主播'},
              'stream_url': _streamUrl(),
            },
          },
        }));
      }
      return _json('{}');
    });
    restore = _useAdapter(adapter);

    final site = DouyinSite();
    final detail = await site.getRoomDetail(roomId: kLongRoomId);

    expect(detail.status, isTrue);
    expect(detail.roomId, kWebRid);
    expect(detail.title, '黑白-（一字斩）正在直播');

    final qualities = await site.getPlayQualites(detail: detail);
    expect(qualities.length, 2);
    // 画质按档位从高到低
    expect(qualities.first.quality, '超清');
    expect(qualities.first.data, contains('http://flv/hd'));

    // 关键：长 roomId 不再走 web/enter
    expect(
      adapter.requests.where((u) => u.contains('/webcast/room/web/enter/')),
      isEmpty,
    );
    expect(
      adapter.requests.where((u) => u.contains('/webcast/room/reflow/info/')),
      isNotEmpty,
    );
  });

  test('降级房间不再抛 NoSuchMethodError，画质安全返回空', () async {
    late _RoutedAdapter adapter;
    adapter = _RoutedAdapter((options) {
      if (options.uri.path.contains('/webcast/room/reflow/info/')) {
        return _json(jsonEncode({
          'data': {
            'room': {
              'id_str': kLongRoomId,
              'status': 4,
              'owner': {'web_rid': kWebRid},
            },
          },
        }));
      }
      if (options.uri.path.contains('/webcast/room/web/enter/')) {
        return _json(jsonEncode(_degradedEnter()));
      }
      return _html(_endedHtml());
    });
    restore = _useAdapter(adapter);

    final site = DouyinSite();
    final detail = await site.getRoomDetail(roomId: kLongRoomId);

    // 拿不到在播状态就是 false，不能崩
    expect(detail.status, isFalse);
    expect(detail.data, isA<Map>());
    expect(await site.getPlayQualites(detail: detail), isEmpty);
  });

  test('进房接口被风控拦下且网页兜底也拿不到房间时抛 CoreError', () async {
    late _RoutedAdapter adapter;
    adapter = _RoutedAdapter((options) {
      if (options.uri.path.contains('/webcast/room/web/enter/')) {
        // 风控：data.data 列表整个没有 → _getDetailByWebRidApi 抛 CoreError
        return _json(jsonEncode({'data': {}}));
      }
      // 网页版也只有「已下播」骨架，roomInfo.room 是空的
      return _html(_endedHtml());
    });
    restore = _useAdapter(adapter);

    final site = DouyinSite();
    // 两条路都拿不到房间时必须抛 CoreError（用户看得懂的那句），
    // 不能是 NoSuchMethodError 这种让人摸不着头脑的崩溃。
    await expectLater(
      site.getRoomDetail(roomId: kWebRid),
      throwsA(isA<CoreError>()),
    );
  });

  test('web/enter 返回在播但缺 stream_url 时，按 roomId 补查 reflow/info',
      () async {
    late _RoutedAdapter adapter;
    adapter = _RoutedAdapter((options) {
      // 首页 / 推荐 / 关注下发的都是 webRid，走的是 web/enter：
      // 在播骨架（status=2）但没有 stream_url（连麦房间的降级响应）
      if (options.uri.path.contains('/webcast/room/web/enter/')) {
        return _json(jsonEncode({
          'data': {
            'data': [
              {'id_str': kLongRoomId, 'status': 2, 'title': '连麦房间'},
            ],
            'user': {'nickname': '主播'},
          },
        }));
      }
      // 用 enter 返回的 roomId 再查 reflow/info，能拿到完整房间
      if (options.uri.path.contains('/webcast/room/reflow/info/')) {
        return _json(jsonEncode({
          'data': {
            'room': {
              'id_str': kLongRoomId,
              'status': 2,
              'title': '连麦房间',
              'owner': {'web_rid': kWebRid, 'nickname': '主播'},
              'stream_url': _streamUrl(),
            },
          },
        }));
      }
      return _json('{}');
    });
    restore = _useAdapter(adapter);

    final site = DouyinSite();
    final detail = await site.getRoomDetail(roomId: kWebRid);

    // 补救生效：不是被判成「未开播」，而是拿到了真实状态与拉流数据
    expect(detail.status, isTrue);
    expect(detail.title, '连麦房间');
    expect(detail.roomId, kWebRid);
    final qualities = await site.getPlayQualites(detail: detail);
    expect(qualities.length, 2);
    expect(qualities.first.quality, '超清');
    expect(
      adapter.requests.where((u) => u.contains('/webcast/room/reflow/info/')),
      isNotEmpty,
    );
  });

  test('只有 flv/hls 地址表时也能拼出画质', () async {
    restore = _useAdapter(_RoutedAdapter((options) => _json('{}')));

    final site = DouyinSite();
    final detail = LiveRoomDetail(
      roomId: kWebRid,
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
      data: {
        'flv_pull_url': {
          'FULL_HD1': 'http://flv/uhd',
          'HD1': 'http://flv/hd',
          'SD1': 'http://flv/ld',
        },
        'hls_pull_url_map': {
          'FULL_HD1': 'http://hls/uhd',
          'HD1': 'http://hls/hd',
          'SD1': 'http://hls/ld',
        },
      },
    );

    final qualities = await site.getPlayQualites(detail: detail);
    expect(qualities.length, 3);
    expect(qualities.first.quality, 'FULL_HD1');
    expect(qualities.first.data, contains('http://flv/uhd'));
    expect(qualities.last.quality, 'SD1');
  });

  test('data 为空 Map / null 时取画质不抛异常', () async {
    restore = _useAdapter(_RoutedAdapter((options) => _json('{}')));

    final site = DouyinSite();
    for (final dynamic data in [null, <String, dynamic>{}, 'not-a-map']) {
      final detail = LiveRoomDetail(
        roomId: kWebRid,
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: false,
        url: '',
        data: data,
      );
      expect(await site.getPlayQualites(detail: detail), isEmpty);
    }
  });
}
