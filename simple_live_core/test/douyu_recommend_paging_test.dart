// 回归测试：斗鱼推荐流的 hasMore 不能依赖服务端的 `pgcnt` 字段。
//
// 2026-09 实测：`allpage/6/{page}` 的响应里 `pgcnt` 键还在但**值恒为 0**，
// 原来的 `page < pgcnt` 会得到 hasMore == false。App 层 `canLoadMore` 随之为
// false，`fillViewportIfNeeded` 第一关就 return，表现为：
//   * 内容不满一屏却不再加载
//   * 滚轮 / 拖拽都触发不了下一页
//   * 刷新只是重拉同一页，看起来「刷新无效、页面卡住」
//
// 该接口实际是一份按热度降序、页间零交集的无限榜单（40 条/页），
// 所以判据改为「本页非空即还有更多」。
//
// 本用例通过注入 HttpClientAdapter 喂固定响应，**不依赖网络**。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
// 同包内引用 src 是允许的（lint 只限制跨包 implementation_imports）
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

/// 固定返回同一份 JSON 的适配器，不发出任何真实请求。
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

/// 一条斗鱼推荐流房间数据（[type] 非 1 表示广告位）。
Map<String, dynamic> _room(String rid, {int type = 1}) => {
      'type': type,
      'rid': rid,
      'rn': '房间 $rid',
      'nn': '主播 $rid',
      'rs16': 'https://example.com/$rid.jpg',
      'ol': 12345,
    };

/// 把一份响应挂到全局 HttpClient 上，返回还原函数。
void Function() _useResponse(Map<String, dynamic> json) {
  final dio = HttpClient.instance.dio;
  final original = dio.httpClientAdapter;
  dio.httpClientAdapter = _CannedAdapter(jsonEncode(json));
  return () => dio.httpClientAdapter = original;
}

void main() {
  late void Function() restore;

  tearDown(() {
    restore();
  });

  test('pgcnt 为 0 时，非空页仍须判为「还有更多」', () async {
    restore = _useResponse({
      'data': {
        'pgcnt': 0, // ← 服务端已不填这个字段
        'rl': List.generate(40, (i) => _room('r$i')),
      },
    });

    final result = await DouyuSite().getRecommendRooms(page: 1);

    expect(result.items, hasLength(40));
    expect(
      result.hasMore,
      isTrue,
      reason: 'pgcnt 失效时把第一页判成最后一页，会让 App 停在第一页且刷新无效',
    );
  });

  test('服务端返回空页时才判为「没有更多」', () async {
    restore = _useResponse({
      'data': {'pgcnt': 0, 'rl': <dynamic>[]},
    });

    final result = await DouyuSite().getRecommendRooms(page: 9);

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('广告位（type != 1）被过滤，且不影响「还有更多」判定', () async {
    restore = _useResponse({
      'data': {
        'pgcnt': 0,
        'rl': [_room('ad1', type: 3), _room('ad2', type: 4), _room('real1')],
      },
    });

    final result = await DouyuSite().getRecommendRooms(page: 1);

    expect(result.items, hasLength(1));
    expect(result.items.single.roomId, 'real1');
    expect(result.hasMore, isTrue);
  });

  test('响应缺少 rl 字段时按空页处理，不抛异常', () async {
    restore = _useResponse({
      'data': {'pgcnt': 0},
    });

    final result = await DouyuSite().getRecommendRooms(page: 1);

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });
}
