// 回归测试：抖音分类页（`partition/detail/room/v2/` 的 count + offset 分页）。
//
// 为什么单独守护：推荐流续接页复用了同一个接口与同一个 `_fetchPartitionPage`，
// 所以这条路径一旦被改坏，会同时打断分类页和推荐流的翻页。这里的用例锁住
// 三件事：
//   1. 请求参数（partition / partition_type / offset / count）确实按页推进；
//   2. `hasMore` 采信「本页是否满」而不是「本页是否非空」；
//   3. 服务端翻到底返回空、或响应结构异常时按空页处理，不抛异常；
//   4. 单条房间数据畸形时只跳过该条，不拖垮整页。
//
// 通过注入 HttpClientAdapter 喂合成响应，**不依赖网络**。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

/// 分区接口的单页条数（分类页固定 15，见 `getCategoryRooms`）。
const int kCategoryPageSize = 15;

/// 合成 adapter：记录每次分区请求的参数，并按配置返回数据。
class _CategoryAdapter implements HttpClientAdapter {
  _CategoryAdapter({
    this.returnedCount,
    this.malformed = false,
    this.dataIsList = false,
    this.brokenItemIndexes = const {},
  });

  /// 实际返回条数；null 表示按请求的 count 返回（即"满页"）。
  final int? returnedCount;

  /// 为 true 时返回结构异常的响应（`data` 为 null），用于验证不崩溃。
  final bool malformed;

  /// 为 true 时返回 `data` 本身是 List 的响应（错误响应形态 `{"data": []}`）。
  ///
  /// 旧代码在这里直接取 `result["data"]["data"]`，会抛 TypeError 把整页带崩；
  /// 这是与 [malformed] 不同的另一种异常形状，必须单独覆盖。
  final bool dataIsList;

  /// 这些下标的条目会被替换成畸形结构（缺 `room` / 缺 `web_rid`）。
  final Set<int> brokenItemIndexes;

  /// 每次请求的 (partition, partition_type, offset, count)。
  final List<(String, String, String, String)> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.path.contains('partition/detail/room/v2')) {
      // 换取 ttwid 之类的其它请求直接放行。
      return _ok(<String, dynamic>{});
    }

    // 分区接口的 URL 由 buildRequestUrl 拼好并签名，query 在 path 里，
    // Dio 的 queryParameters 是空的。
    final q = Uri.parse(options.path).queryParameters;
    requests.add((
      q['partition'] ?? '',
      q['partition_type'] ?? '',
      q['offset'] ?? '',
      q['count'] ?? '',
    ));

    if (malformed) {
      return _ok({'data': null});
    }

    if (dataIsList) {
      // 错误响应形态：data 本身是 List，再往里取 ["data"] 就是 TypeError
      return _ok({'data': <dynamic>[]});
    }

    final count = int.tryParse(q['count'] ?? '') ?? kCategoryPageSize;
    final actual = returnedCount ?? count;
    return _ok({
      'data': {
        'data': List.generate(actual, (i) {
          if (brokenItemIndexes.contains(i)) {
            // 半路杀出的脏数据：既可能整个 item 不是 Map，也可能缺 room/web_rid。
            return i.isEven ? null : {'room': null};
          }
          return {
            'web_rid': 'r${q['offset']}_$i',
            'room': {
              'title': '房间 ${q['offset']}_$i',
              'cover': {
                'url_list': ['https://example.com/r${q['offset']}_$i.jpg'],
              },
              'owner': {'nickname': '主播 ${q['offset']}_$i'},
              'room_view_stats': {'display_value': 1234},
            },
          };
        }),
      },
    });
  }

  ResponseBody _ok(Map<String, dynamic> body) => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void Function() _install(_CategoryAdapter adapter) {
  final dio = HttpClient.instance.dio;
  final original = dio.httpClientAdapter;
  dio.httpClientAdapter = adapter;
  return () => dio.httpClientAdapter = original;
}

/// cookie 里预置 ttwid，`getRequestHeaders` 就不会再发 HEAD。
DouyinSite _site() {
  final site = DouyinSite();
  site.headers['cookie'] = 'ttwid=test-cookie';
  return site;
}

/// 分类树里的「聊天」顶级分区。
LiveSubCategory _category() => LiveSubCategory(
      id: '101,4',
      name: '聊天',
      parentId: '101,4',
      pic: '',
    );

void main() {
  void Function() restore = () {};

  tearDown(() {
    restore();
  });

  test('第 1 页按分类 id 拆出 partition / partition_type，offset 从 0 起', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.$1, '101');
    expect(adapter.requests.single.$2, '4');
    expect(adapter.requests.single.$3, '0');
    expect(
      adapter.requests.single.$4,
      kCategoryPageSize.toString(),
      reason: 'count 超过 20 服务端只给 20，会让"本页条数 >= count"恒 false',
    );
    expect(result.items, hasLength(kCategoryPageSize));
  });

  test('第 2 页 offset 前进一页', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    await _site().getCategoryRooms(_category(), page: 2);

    expect(adapter.requests.single.$3, kCategoryPageSize.toString());
  });

  test('满页时判为「还有更多」', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(result.hasMore, isTrue);
  });

  test('不满一页时判为「没有更多」', () async {
    // 服务端只剩 3 条，说明后面没有了
    final adapter = _CategoryAdapter(returnedCount: 3);
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(result.items, hasLength(3));
    expect(
      result.hasMore,
      isFalse,
      reason: '判据必须是"本页是否满"而不是"本页是否非空"',
    );
  });

  test('服务端返回空页时判为「没有更多」，且不抛异常', () async {
    final adapter = _CategoryAdapter(returnedCount: 0);
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 99);

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('响应结构异常时按空页处理，而不是崩溃', () async {
    final adapter = _CategoryAdapter(malformed: true);
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('data 本身是 List 时同样降级成空页（而不是抛 TypeError）', () async {
    // 错误响应 `{"data": []}`：旧代码取 result["data"]["data"] 会直接抛
    final adapter = _CategoryAdapter(dataIsList: true);
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('房间字段被完整映射', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);
    final first = result.items.first;

    expect(first.roomId, 'r0_0');
    expect(first.title, '房间 0_0');
    expect(first.cover, 'https://example.com/r0_0.jpg');
    expect(first.userName, '主播 0_0');
    expect(first.online, 1234);
  });

  test('单条房间数据畸形时只跳过该条，不拖垮整页', () async {
    // 偶数下标是 null、奇数下标缺 room —— 都是线上真实出现过的脏数据形状
    final adapter = _CategoryAdapter(brokenItemIndexes: {0, 1, 2, 3});
    restore = _install(adapter);

    final result = await _site().getCategoryRooms(_category(), page: 1);

    expect(result.items, hasLength(kCategoryPageSize - 4));
    expect(
      result.hasMore,
      isTrue,
      reason: 'hasMore 看的是原始条数，不能被"解析后少了几条"带偏',
    );
  });

  test('分类页与推荐流续接页共用同一套 offset 约定', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    await _site().getCategoryRooms(_category(), page: 1);
    await _site().getRecommendRooms(page: 2);

    expect(adapter.requests, hasLength(2));
    expect(
      adapter.requests[0].$3,
      adapter.requests[1].$3,
      reason: '两条路径的 offset 都从 0 起',
    );
  });

  test('两条路径的 count 都不超过服务端能严格兑现的上限 20', () async {
    final adapter = _CategoryAdapter();
    restore = _install(adapter);

    await _site().getCategoryRooms(_category(), page: 1);
    await _site().getRecommendRooms(page: 2);

    // 单页条数刻意不同（分类页沿用历史的 15，推荐流续接页用上限 20），
    // 但都必须 ≤ 20：count 给到 25 以上时服务端只返回 20 条，
    // `本页条数 >= count` 会恒为 false，整条列表被误判成已到底。
    for (final request in adapter.requests) {
      expect(
        int.parse(request.$4),
        lessThanOrEqualTo(DouyinSite.kPartitionPageSize),
        reason: 'count 超过上限会让 hasMore 判据失效',
      );
    }
  });
}
