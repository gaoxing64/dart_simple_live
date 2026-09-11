// 回归测试：抖音推荐流「首屏 feed 扇出 + 续接分区真分页」的供给契约。
//
// 背景（2026-09 实测，见 douyin_site.dart 注释）：
//   * `webcast/feed/` **不是分页接口**：count / offset / cursor / max_time /
//     page / pull_type / search_offset 全被忽略，连响应里 extra.max_time
//     回传也无效（6 页链式请求并集只有 47/120）；反复轮询的累计去重收益
//     同样会枯竭（6 轮并集 65 条）。所以它只够做首屏。
//   * 首屏之后必须换到官方 `partition/detail/room/v2/`：offset 真偏移
//     （0/15/30/45/60 零重复），单分区约 120 条深度，7 个分区合起来约
//     840 条，才撑得起"无限滚动"。
//
// 这些用例守护五件事：
//   1. 首屏确实扇出 kMinFeedFanout 路、**且是并发的**，并声明 hasMore=true
//      （否则 App 层首屏就判到底，又退回"只加载一次"）；
//   2. 路数有上限兜底，不会被异常大的 pageSize 放大；
//   3. 切片之间的重叠被合并去重，个别切片失败不拖垮整页；
//   4. 第 2 页起改走分区接口，页号 → (分区, offset) 的映射稳定可重放；
//   5. 某分区翻到底时顺延到下一个分区，一圈全空才声明到底。
//
// 通过注入 HttpClientAdapter 喂合成响应，**不依赖网络**。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
// 同包内引用 src 是允许的（lint 只限制跨包 implementation_imports）
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

/// 一路切片的处理时长，用于区分「并发」与「串行」。
const Duration kSliceLatency = Duration(milliseconds: 100);

/// 合成 adapter：`webcast/feed/` 每次 +1 计数并按序号生成不同房间；
/// `partition/detail/room/v2/` 记录 (partition, offset, count) 并按参数
/// 生成房间。可用 [emptyPartitions] 模拟某个分区已翻到底。
class _DouyinAdapter implements HttpClientAdapter {
  _DouyinAdapter({
    this.failIndexes = const <int>{},
    this.repeatFirstSlice = false,
    this.emptySlices = false,
    this.emptyPartitions = const <String>{},
  });

  /// 这些序号的 feed 请求会抛异常（模拟个别切片失败）。
  final Set<int> failIndexes;

  /// 为 true 时所有切片返回同一批房间（模拟切片完全重叠）。
  final bool repeatFirstSlice;

  /// 为 true 时所有切片返回空数据。
  final bool emptySlices;

  /// 这些 partition 一律返回空页（模拟该分区已翻到底）。
  final Set<String> emptyPartitions;

  final List<String> counts = [];
  int feedRequests = 0;
  int _inFlight = 0;
  int maxInFlight = 0;

  /// 分区接口收到的每次请求：(partition, offset, count)。
  final List<(String, String, String)> partitionRequests = [];

  /// 取出请求的查询参数。
  ///
  /// feed 切片是把参数交给 `getJson(queryParameters:)`；分区接口则用
  /// `buildRequestUrl` 把参数连同 abogus 签名拼成一整串 URL 传进去，
  /// 此时 Dio 的 `queryParameters` 是空的，只能从 path 里解析。
  Map<String, String> _queryOf(RequestOptions options) {
    if (options.queryParameters.isNotEmpty) {
      return options.queryParameters
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return Uri.parse(options.path).queryParameters;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('partition/detail/room/v2')) {
      final q = _queryOf(options);
      final partition = '${q['partition']},${q['partition_type']}';
      final offset = q['offset'] ?? '';
      final count = q['count'] ?? '';
      partitionRequests.add((partition, offset, count));
      if (emptyPartitions.contains(partition)) {
        return _ok({
          'data': {'data': <dynamic>[]}
        });
      }
      // 每个分区各自的房间号前缀，便于断言内容来源。
      return _ok({
        'data': {
          'data': List.generate(
            int.tryParse(count) ?? DouyinSite.kPartitionPageSize,
            (i) => _room('$partition@$offset#$i'),
          ),
        },
      });
    }

    if (!options.path.contains('webcast/feed')) {
      // 其它请求（例如换取 ttwid 的 HEAD）立刻返回。
      return _ok(<String, dynamic>{});
    }

    final index = feedRequests++;
    counts.add(_queryOf(options)['count'] ?? '');
    _inFlight++;
    if (_inFlight > maxInFlight) {
      maxInFlight = _inFlight;
    }
    try {
      await Future<void>.delayed(kSliceLatency);
      if (failIndexes.contains(index)) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          message: 'slice $index failed',
        );
      }
      return _ok(_sliceBody(index));
    } finally {
      _inFlight--;
    }
  }

  Map<String, dynamic> _room(String rid) => {
        'web_rid': rid,
        'room': {
          'title': '房间 $rid',
          'cover': {
            'url_list': ['https://example.com/$rid.jpg'],
          },
          'owner': {'nickname': '主播 $rid'},
          'room_view_stats': {'display_value': 1000},
        },
      };

  Map<String, dynamic> _sliceBody(int index) {
    final slice = repeatFirstSlice ? 0 : index;
    final count = emptySlices ? 0 : DouyinSite.kFeedSliceSize;
    return {
      'data': List.generate(count, (i) {
        final rid = '${slice}_$i';
        return {
          'data': {
            'title': '房间 $rid',
            'cover': {
              'url_list': ['https://example.com/$rid.jpg'],
            },
            'owner': {'web_rid': rid, 'nickname': '主播 $rid'},
            'room_view_stats': {'display_value': 1000 + i},
          },
        };
      }),
    };
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

/// 把 [adapter] 挂到全局 HttpClient 上，返回还原函数。
void Function() _install(_DouyinAdapter adapter) {
  final dio = HttpClient.instance.dio;
  final original = dio.httpClientAdapter;
  dio.httpClientAdapter = adapter;
  return () => dio.httpClientAdapter = original;
}

/// 构造站点实例：cookie 里预置 ttwid，`getRequestHeaders` 就不会再发 HEAD。
DouyinSite _site() {
  final site = DouyinSite();
  site.headers['cookie'] = 'ttwid=test-cookie';
  return site;
}

void main() {
  // 初始化为空实现而不是 `late`：若某用例在 _install 之前就失败，
  // tearDown 里的 LateInitializationError 会盖掉真正的失败原因。
  void Function() restore = () {};

  tearDown(() {
    restore();
  });

  group('首屏（第 1 页，webcast/feed 扇出）', () {
    test('pageSize=30 时按下限扇出 4 路，且是并发起飞的', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 30);

      expect(
        adapter.feedRequests,
        DouyinSite.kMinFeedFanout,
        reason: '热门池一次只见约 45~65 个房间，拉满一次最划算',
      );
      expect(result.items, hasLength(20 * DouyinSite.kMinFeedFanout));
      // 并发由 maxInFlight 精确断言：4 路同时在场，总耗时必然≈单次请求，
      // 串行则只会同时有 1 路。不再额外断言墙钟耗时——那条在 CI 负载高时
      // 会变成 flaky 来源，而它想证明的事情已经被这条覆盖。
      expect(
        adapter.maxInFlight,
        DouyinSite.kMinFeedFanout,
        reason: '切片必须并发起飞，否则耗时等于串行累加，宽窗口填不满',
      );
      expect(adapter.partitionRequests, isEmpty, reason: '首屏不该碰分区接口');
    });

    test('首屏声明 hasMore=true，否则 App 层首屏就判到底', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 30);

      // 这是"只加载一次"问题的直接回归点：feed 自己翻不了页，但首屏必须
      // 声明"还有更多"，App 层才会在第 2 页改用分区接口继续。
      expect(result.hasMore, isTrue);
    });

    test('pageSize 大到离谱时按上限封顶', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 500);

      expect(adapter.feedRequests, DouyinSite.kMaxFeedFanout);
      expect(result.items, hasLength(20 * DouyinSite.kMaxFeedFanout));
    });

    test('每份切片用不同查询串，避免并发请求被当成同一份去重', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      await _site().getRecommendRooms(page: 1, pageSize: 30);

      expect(
        adapter.counts.toSet(),
        hasLength(adapter.counts.length),
        reason: '并发切片参数相同的话，服务端大概率返回重叠的同一批房间',
      );
    });

    test('未指定 pageSize 时也按下限扇出，不让调用方退化成单路', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final result = await _site().getRecommendRooms();

      expect(adapter.feedRequests, DouyinSite.kMinFeedFanout);
      expect(result.items, hasLength(20 * DouyinSite.kMinFeedFanout));
    });

    test('切片之间重叠时按 roomId 去重，重复项不占位', () async {
      final adapter = _DouyinAdapter(repeatFirstSlice: true);
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 60);

      expect(adapter.feedRequests, DouyinSite.kMinFeedFanout);
      expect(
        result.items,
        hasLength(DouyinSite.kFeedSliceSize),
        reason: '完全相同的几份切片只应保留一份',
      );
    });

    test('个别切片失败不影响整页，其余切片照常返回', () async {
      final adapter = _DouyinAdapter(failIndexes: {1});
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 60);

      expect(adapter.feedRequests, DouyinSite.kMinFeedFanout);
      expect(
        result.items,
        hasLength(20 * (DouyinSite.kMinFeedFanout - 1)),
        reason: '失败的那一路缺席，另外几路仍要返回',
      );
      expect(result.hasMore, isTrue);
    });

    test('全部切片失败时上抛异常（而不是静默返回空列表）', () async {
      final adapter = _DouyinAdapter(failIndexes: {0, 1, 2, 3, 4, 5});
      restore = _install(adapter);

      await expectLater(
        () => _site().getRecommendRooms(page: 1, pageSize: 60),
        throwsA(isA<CoreError>()),
      );
    });

    test('所有切片都为空时按空页处理，不抛异常', () async {
      final adapter = _DouyinAdapter(emptySlices: true);
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 60);

      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse, reason: '一无所获时才允许让 App 停下');
    });

    test('一路失败 + 其余切片都为空时按空页处理，不上抛错误页', () async {
      // 「部分失败 + 其余切片恰好返回空」（服务端限流、池子空）完全可能出现。
      // 上抛条件必须看「有没有任何一路成功」，而不是「items 是否为空」，
      // 否则用户看到的是错误页而不是空页。
      final adapter = _DouyinAdapter(failIndexes: {0}, emptySlices: true);
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 1, pageSize: 60);

      expect(adapter.feedRequests, DouyinSite.kMinFeedFanout);
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });
  });

  group('续接页（第 2 页起，partition 真分页）', () {
    test('第 2 页走分区接口的第 1 个分区、offset=0、count=20', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 2);

      expect(adapter.partitionRequests, hasLength(1));
      expect(adapter.partitionRequests.single.$1,
          DouyinSite.kRecommendPartitions.first);
      expect(adapter.partitionRequests.single.$2, '0');
      expect(
        adapter.partitionRequests.single.$3,
        DouyinSite.kPartitionPageSize.toString(),
        reason: 'count 超过 20 服务端只给 20，会让"本页条数 >= count"恒 false',
      );
      expect(result.items, hasLength(DouyinSite.kPartitionPageSize));
      expect(result.hasMore, isTrue);
    });

    test('第 3 页换下一个分区，offset 仍是 0', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      await _site().getRecommendRooms(page: 3);

      expect(
        adapter.partitionRequests.single.$1,
        DouyinSite.kRecommendPartitions[1],
      );
      expect(adapter.partitionRequests.single.$2, '0');
    });

    test('转完一圈回到第 1 个分区，且 offset 前进一页', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      final slots = DouyinSite.kRecommendPartitions.length;
      // 第 2 页是 slot 0，转完 slots 页后回到 slot 0 的下一圈。
      await _site().getRecommendRooms(page: 2 + slots);

      expect(
        adapter.partitionRequests.single.$1,
        DouyinSite.kRecommendPartitions.first,
      );
      expect(
        adapter.partitionRequests.single.$2,
        DouyinSite.kPartitionPageSize.toString(),
        reason: '每转完一圈 offset 前进一页，映射是页号的纯函数',
      );
    });

    test('页号 → 分区的映射可重放：同一页重复请求参数一致', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      await _site().getRecommendRooms(page: 5);
      await _site().getRecommendRooms(page: 5);

      expect(adapter.partitionRequests, hasLength(2));
      expect(adapter.partitionRequests[0], adapter.partitionRequests[1]);
    });

    test('某个分区翻到底时顺延到下一个分区，而不是直接判到底', () async {
      final adapter = _DouyinAdapter(
        emptyPartitions: {DouyinSite.kRecommendPartitions.first},
      );
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 2);

      expect(
        adapter.partitionRequests.map((e) => e.$1).toList(),
        [
          DouyinSite.kRecommendPartitions[0],
          DouyinSite.kRecommendPartitions[1],
        ],
        reason: '第 1 个分区已耗尽，应顺延到第 2 个',
      );
      expect(result.items, isNotEmpty);
      expect(result.hasMore, isTrue);
    });

    test('一圈分区全部翻空才声明到底', () async {
      final adapter = _DouyinAdapter(
        emptyPartitions: DouyinSite.kRecommendPartitions.toSet(),
      );
      restore = _install(adapter);

      final result = await _site().getRecommendRooms(page: 2);

      expect(
        adapter.partitionRequests,
        hasLength(DouyinSite.kRecommendPartitions.length),
        reason: '要探完整整一圈才能确认没有更多了',
      );
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test('续接页不碰 feed 接口', () async {
      final adapter = _DouyinAdapter();
      restore = _install(adapter);

      await _site().getRecommendRooms(page: 4);

      expect(adapter.feedRequests, 0);
    });

    test('顺延过的下一页不会把上一页的内容再返回一遍', () async {
      // 第 1 个分区翻空 → 第 2 页顺延到第 2 个分区。此时第 3 页必须继续往下走，
      // 而不是从第 2 个分区再读一遍：App 层以「连续两页零新增」判到底，
      // 重复一页就会让它提前收尾，把后面几个分区还取得到的内容整段丢掉。
      final adapter = _DouyinAdapter(
        emptyPartitions: {DouyinSite.kRecommendPartitions.first},
      );
      restore = _install(adapter);

      final site = _site();
      final page2 = await site.getRecommendRooms(page: 2);
      final page3 = await site.getRecommendRooms(page: 3);

      expect(page2.items, isNotEmpty);
      expect(page3.items, isNotEmpty);
      expect(
        page3.items
            .map((e) => e.roomId)
            .toSet()
            .intersection(page2.items.map((e) => e.roomId).toSet()),
        isEmpty,
        reason: '同一个 (分区, offset) 只该被消费一次',
      );
    });

    test('连续多个分区翻空时，后续每一页仍拿到没消费过的内容', () async {
      // 尾部各分区深度接近，很容易出现「同一 offset 上连着几个分区都空了」。
      // 顺延若只看页号、不记住命中位置，第 2~4 页会连着返回同一份内容。
      final adapter = _DouyinAdapter(
        emptyPartitions: {
          DouyinSite.kRecommendPartitions[0],
          DouyinSite.kRecommendPartitions[1],
          DouyinSite.kRecommendPartitions[2],
        },
      );
      restore = _install(adapter);

      final site = _site();
      final seen = <String>{};
      for (final page in <int>[2, 3, 4]) {
        final result = await site.getRecommendRooms(page: page);

        expect(result.items, isNotEmpty, reason: '还有分区没翻完就不该判到底');
        final ids = result.items.map((e) => e.roomId).toSet();
        expect(ids.intersection(seen), isEmpty, reason: '第 $page 页重复了已消费的内容');
        seen.addAll(ids);
      }
    });

    test('第 1 页（新一轮推荐）把续接游标重置，第 2 页重新从第 1 个分区开始', () async {
      final adapter = _DouyinAdapter(
        emptyPartitions: {DouyinSite.kRecommendPartitions.first},
      );
      restore = _install(adapter);

      final site = _site();
      // 先翻两页把游标推到 slot 2 之后
      await site.getRecommendRooms(page: 2);
      await site.getRecommendRooms(page: 3);
      adapter.partitionRequests.clear();

      // 下拉刷新：第 1 页重新走 feed，续接游标归零
      await site.getRecommendRooms(page: 1, pageSize: 30);
      await site.getRecommendRooms(page: 2);

      expect(
        adapter.partitionRequests.first.$1,
        DouyinSite.kRecommendPartitions.first,
        reason: '刷新后第 2 页要从第 1 个分区重新开始',
      );
      expect(adapter.partitionRequests.first.$2, '0');
    });
  });
}
