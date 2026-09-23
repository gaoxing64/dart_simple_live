import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/convert_helper.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/platforms/douyin/douyin_utils.dart';
import 'douyin_request_params.dart';

class DouyinSite implements LiveSite {
  @override
  String id = "douyin";

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();

  bool hlsFirst = false;

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  Map<String, dynamic> headers = {
    "Authority": kDefaultAuthority,
    "Referer": kDefaultReferer,
    "User-Agent": DouyinRequestParams.kDefaultUserAgent,
  };

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      final existCookies = headers['cookie'] ?? '';
      if (existCookies.contains('ttwid')) {
        return headers;
      }
      var head = await HttpClient.instance
          .head("https://live.douyin.com", header: headers);
      head.headers["set-cookie"]?.forEach((element) {
        var cookie = element.split(";")[0];
        if (cookie.contains("ttwid")) {
          final newCookie = '$cookie; $existCookies';
          headers['cookie'] = newCookie;
        }
      });
      return headers;
    } catch (e) {
      CoreLog.error(e);
      return headers;
    }
  }

  /// 通过 Cookie 获取当前登录用户信息
  /// 成功返回 data(Map)，失败返回空 Map
  Future<Map<String, dynamic>> getUserInfoByCookie(String cookie) async {
    try {
      final url = "https://live.douyin.com/webcast/user/me/";
      final result = await HttpClient.instance.getJson(
        url,
        queryParameters: {
          "aid": DouyinRequestParams.aidValue,
        },
        header: {
          "user-agent": DouyinRequestParams.kDefaultUserAgent,
          'accept': 'application/json, text/plain, */*',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          "Cookie": cookie,
        },
      );
      if (result is Map<String, dynamic>) {
        final data = result["data"];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {};
    } catch (e) {
      CoreLog.error(e);
    }
    return {};
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {},
      header: await getRequestHeaders(),
    );

    var renderData = RegExp(r'\{\\"pathname\\":\\"\/\\",\\"categoryData.*?\],')
            .firstMatch(result)
            ?.group(0) ??
        "";
    var renderDataJson = json.decode(renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll('],', ""));

    for (var item in renderDataJson["categoryData"]) {
      List<LiveSubCategory> subs = [];
      var id = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      for (var subItem in item["sub_partition"]) {
        var subCategory = LiveSubCategory(
          id: '${subItem["partition"]["id_str"]},${subItem["partition"]["type"]}',
          name: asT<String?>(subItem["partition"]["title"]) ?? "",
          parentId: id,
          pic: "",
        );
        subs.add(subCategory);
      }

      var category = LiveCategory(
        children: subs,
        id: id,
        name: asT<String?>(item["partition"]["title"]) ?? "",
      );
      subs.insert(
          0,
          LiveSubCategory(
            id: category.id,
            name: category.name,
            parentId: category.id,
            pic: "",
          ));
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1, int? pageSize}) async {
    // 该接口用 count + offset 翻页：count ≤ 20 时服务端严格返回 count 条，
    // 调大反而只给 20 条，"本页条数 < count"会被误判成没有更多，分类页就
    // 只剩一页。既然无法保证服务端接受自定义条数，这里维持 15，
    // 忽略 [pageSize]。
    const count = 15;
    final result = await _fetchPartitionPage(
      await getRequestHeaders(),
      partition: category.id,
      offset: (page - 1) * count,
      count: count,
    );
    // hasMore 用服务端原始条数判：畸形条目被跳过不该影响「本页满不满」。
    return LiveCategoryResult(
      hasMore: result.rawCount >= count,
      items: result.items,
    );
  }

  /// 拉取某个分区的一页房间（分类页与推荐流续接页共用）。
  ///
  /// [partition] 是 `"id,type"` 形式（如 `"106,4"`），与 [LiveSubCategory.id]
  /// 同构。[offset] 是真偏移量——实测 offset 0/15/30/45/60 零重复，
  /// 单分区约 120 条深度。
  ///
  /// 返回 `(items, rawCount)`：[rawCount] 是服务端这一页实际给了多少条，
  /// 用于判 `hasMore`——不能拿 [items] 的长度判，因为畸形条目会被跳过，
  /// 会让「本页满不满」的判断失真、提前把列表判成到底。
  Future<({List<LiveRoomItem> items, int rawCount})> _fetchPartitionPage(
    Map<String, dynamic> header, {
    required String partition,
    required int offset,
    int count = kPartitionPageSize,
  }) async {
    // count 超过 kPartitionPageSize 时服务端只返回 20 条，
    // `rawCount >= count` 会恒为 false，整条列表被误判成已到底。
    //
    // 这里用真实守卫而不是 assert：assert 在 release 里会被整体剥离，而
    // 「本页满不满」的判据在调用方手里、方法内 clamp 救不了——一旦将来新增
    // 调用方传了更大的 count，线上表现是「列表莫名其妙只剩一页」，没有任何
    // 报错可查。宁可让写错的调用点直接炸出来。
    if (count <= 0 || count > kPartitionPageSize) {
      throw ArgumentError.value(
        count,
        'count',
        '必须落在 1..$kPartitionPageSize：再大服务端也只返回 20 条，'
            '会让 rawCount >= count 恒为 false，列表被误判成已到底',
      );
    }
    final ids = partition.split(',');
    final targetUrl = DouyinUtils.buildRequestUrl(
      "https://live.douyin.com/webcast/web/partition/detail/room/v2/",
      {
        "aid": '6383',
        "app_name": "douyin_web",
        "live_id": '1',
        "device_platform": "web",
        "language": "zh-CN",
        "enter_from": "link_share",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "count": count.toString(),
        "offset": offset.toString(),
        "partition": ids[0],
        "partition_type": ids.length > 1 ? ids[1] : '4',
        "req_from": '2'
      },
    );
    final result = await HttpClient.instance.getJson(
      targetUrl,
      header: header,
    );

    // 翻到底时服务端返回空数组（而不是报错），所以这里要降级成空页。
    // 注意不能只判 null：`result["data"]` 完全可能是 List（例如错误响应
    // `{"data": []}`），那时再取 `["data"]` 会抛 TypeError，整页失败。
    final data = result is Map ? result['data'] : null;
    final dataList = (data is Map && data['data'] is List)
        ? data['data'] as List
        : const <dynamic>[];
    return (
      items: dataList.map(_roomItemOf).whereType<LiveRoomItem>().toList(),
      rawCount: dataList.length,
    );
  }

  /// 把分区接口返回的一条 room 数据转成 [LiveRoomItem]；数据畸形时返回 null。
  ///
  /// 逐字段判空而不是链式取值：分区流里混进一两条缺字段的数据是常态，
  /// 单条畸形不该拖垮整页（调用方用 `whereType` 跳过 null）。
  LiveRoomItem? _roomItemOf(dynamic item) {
    if (item is! Map) {
      return null;
    }
    final room = item['room'];
    if (room is! Map) {
      return null;
    }
    // 没有房间号就没法去重也没法进房，直接跳过。
    final webRid = item['web_rid'];
    if (webRid == null) {
      return null;
    }
    final owner = room['owner'];
    final cover = room['cover'];
    final coverList = cover is Map ? cover['url_list'] : null;
    final stats = room['room_view_stats'];
    return LiveRoomItem(
      roomId: webRid.toString(),
      title: room['title']?.toString() ?? '',
      cover: (coverList is List && coverList.isNotEmpty)
          ? coverList.first.toString()
          : '',
      userName: owner is Map ? (owner['nickname']?.toString() ?? '') : '',
      online:
          int.tryParse(stats is Map ? '${stats['display_value']}' : '') ?? 0,
    );
  }

  /// 一次 `webcast/feed/` 请求返回的条数。
  ///
  /// 服务端固定给 20 条：count / offset / cursor / max_time 等参数实测全部被
  /// 忽略（`extra.offset` 恒为 0、`extra.total` 恒为 20），改大 count 只是把
  /// 同样 20 条的另一份样本换来。
  static const int kFeedSliceSize = 20;

  /// 单次推荐请求内部并发拉取的路数下限。
  ///
  /// 这个接口不是分页，而是「从热门池里随机抽 20 个房间」：同一组参数连续
  /// 调用 3 次，结果两两交集只有 5~15 个；反复轮询的累计收益会枯竭
  /// （实测 6 轮并集 65 条、再往后基本零新增）。并发 N 路的去重收益同样迅速
  /// 饱和（2 / 3 / 4 / 6 路分别只有 31 / 34 / 43 / 46 条），再往上加只是白送请求。
  ///
  /// 取 4 是想让**首页一次就拿到池里绝大部分内容**（约 33~43 条，够铺满桌面
  /// 宽窗口的 6 列 × 5 行），不必像串行那样连拉好几轮才填满。
  static const int kMinFeedFanout = 4;

  /// 路数上限：兜住 pageSize 异常大的情况，避免一次扇出几十路请求。
  static const int kMaxFeedFanout = 6;

  /// 「推荐」翻到第 2 页之后的续接源：官方顶级分区，按序轮转。
  ///
  /// 为什么必须换接口：`webcast/feed/` 实测**完全没有翻页能力**——
  /// count / offset / cursor / max_time / page / pull_type / search_offset
  /// 全部被忽略；连响应里 `extra.max_time` 这个"疑似游标"回传也无效
  /// （6 页链式请求并集只有 47/120）。所以首屏之后必须换到真分页的接口，
  /// 否则就是「只加载一次，之后只能靠下拉刷新」。
  ///
  /// 官方 `partition/detail/room/v2/` 才是真分页：offset 0/15/30/45/60 实测
  /// 零重复，每个分区约 120 条深度（offset 100 仍有 20 条、200 已空）。
  /// 它与首屏 feed 的内容几乎不重叠（实测每页只重 0~1 条），衔接自然。
  ///
  /// 顺序按实测人气中位数从高到低排（文化 > 游戏 > 聊天 > 音乐 > 运动 >
  /// 二次元 > 舞蹈）。生活（107,4）因为中位人气为 0（整页都是 0 人直播间）
  /// 被剔除。
  ///
  /// 轮转而非固定单分区，是为了让「推荐」保持跨品类的观感：7 个分区各约
  /// 120 条，合起来约 840 条可翻。
  static const List<String> kRecommendPartitions = [
    '106,4', // 文化
    '103,4', // 游戏
    '101,4', // 聊天
    '102,4', // 音乐
    '108,4', // 运动
    '104,4', // 二次元
    '105,4', // 舞蹈
  ];

  /// 分区接口的单页条数。
  ///
  /// 实测 count ≤ 20 时服务端严格返回 count 条，count ≥ 25 时只返回 20 条：
  /// 后者会让 `本页条数 >= count` 的判据恒为 false，把列表误判成已到底。
  /// 所以取服务端能严格兑现的上限 20。
  static const int kPartitionPageSize = 20;

  @override
  Future<LiveCategoryResult> getRecommendRooms(
      {int page = 1, int? pageSize}) async {
    // 第 1 页用真实推荐流；第 2 页起换成能翻页的分区接口（见
    // [kRecommendPartitions]）。两者内容几乎不重叠，衔接是自然的。
    if (page <= 1) {
      return _fetchRecommendFeed(pageSize: pageSize);
    }
    return _fetchRecommendContinuation(page);
  }

  /// 首屏：`webcast/feed/` 一轮并发扇出。
  ///
  /// 该接口没有翻页能力，一次只吐 20 个随机房间，逐轮串行拉就表现为
  /// 「每页多一两条、内容一个一个往外蹦」。这里改成一轮并发拉多份切片：
  /// 并发是把热门池在**一次等待**里尽量收齐，而不是「靠多等几轮让池自己
  /// 转出新东西」，所以墙钟耗时≈单次请求。
  Future<LiveCategoryResult> _fetchRecommendFeed({int? pageSize}) async {
    // 第 1 页 = 新一轮推荐（首次进入或下拉刷新），续接页的游标归零，
    // 让第 2 页重新从第 1 个分区的 offset 0 开始。
    _lastServedSlot = -1;
    // headers 只取一次：下面所有切片共用，避免并发里重复发 HEAD 换 cookie。
    final header = await getRequestHeaders();
    final fanout = _recommendFanout(pageSize);

    // 先全部起飞，再逐个收，任何一路失败都不影响其余切片。
    //
    // 起飞的同时每路都挂一个"只消费错误"的监听器：收结果是串行的，后面几路
    // 往往在被 await 之前就已完成，而 Future 若在完成时还没有任何错误监听器，
    // Dart 会把它当作未处理的异步错误上报给 zone（Flutter 下是一条莫名其妙
    // 的错误日志，测试里直接判该用例失败），即便之后 await 时又正常捕获到了。
    // 真正的处理仍在下面的 try/catch 里按切片做，这里只是先认领下来。
    final futures = List<Future<List<LiveRoomItem>>>.generate(fanout, (i) {
      final future = _fetchFeedSlice(header, sliceIndex: i);
      // 用 unawaited 明确表达「这里只是先认领错误、不等它」；
      // 注意不要把 catchError 的结果回填进 futures，否则异常会被吞掉，
      // 下面「一路都没成功才上抛」的分支就失效了。
      unawaited(future.catchError((Object _) => <LiveRoomItem>[]));
      return future;
    });

    final items = <LiveRoomItem>[];
    final seen = <String>{};
    var succeeded = 0;
    Object? firstError;
    for (final future in futures) {
      try {
        final slice = await future;
        succeeded++;
        for (final item in slice) {
          // 切片之间的重叠随并发数上升而变多（与 App 层的跨页去重同源），
          // 这里先合并去重，避免同一批数据因为顺序不同重复占位。
          if (seen.add(item.roomId)) {
            items.add(item);
          }
        }
      } catch (e) {
        // 部分失败容忍：推荐流缺几路并不影响首屏，全部失败才上抛。
        CoreLog.error(e);
        firstError ??= e;
      }
    }

    // 只有一路都没成功才上抛。不能写成 `items.isEmpty && firstError != null`：
    // 「一路失败 + 其余切片恰好返回空」（服务端限流、池子空）是完全可能的，
    // 那种情况该展示空页而不是错误页。
    if (succeeded == 0 && firstError != null) {
      throw CoreError("获取抖音直播推荐失败：$firstError");
    }

    // 首屏只负责"把当前热门池收得尽量满"，继续翻页交给下面的分区接口，
    // 所以这里声明 hasMore=true；真的一无所获时才让 App 停下。
    return LiveCategoryResult(hasMore: items.isNotEmpty, items: items);
  }

  /// 上一次真正命中过的 slot（`-1` 表示本实例刚开始翻）。
  ///
  /// 为什么必须记住它：顺延时同一个 slot 会被相邻的两个页号依次命中——
  /// 第 N 页从 slot N-2 起扫，扫到 slot k 才有内容；第 N+1 页从 slot N-1 起扫，
  /// 若 N-1 也是空的，就又扫到同一个 slot k，于是同一份内容被连续两页原样返回。
  /// 而 App 层 `BasePageController` 判「到底」的依据正是**连续 2 页零新增**，
  /// 于是列表会提前收尾，把后面几个分区在这个 offset 上还取得到的内容整段丢掉
  /// ——恰好是这次改动想修掉的「列表提前停住」。
  ///
  /// 下一页从命中位置之后接着扫，slot 就严格递增，同一个 (分区, offset) 只会被
  /// 消费一次。刷新（第 1 页）时重置，见 [_fetchRecommendFeed]。
  int _lastServedSlot = -1;

  /// 第 2 页起：官方分区接口真分页。
  ///
  /// 把「页号」映射成一条虚拟的无限序列：第 2 页对应 slot 0、第 3 页对应
  /// slot 1……slot 决定用哪个分区（循环轮转），每转完一圈 offset 前进一页。
  /// 起点是页号的纯函数，只有上一页顺延过时才会额外向后推进一档
  /// （见 [_lastServedSlot]），因此同一页重放不会漂移。
  Future<LiveCategoryResult> _fetchRecommendContinuation(int page) async {
    final header = await getRequestHeaders();
    final slots = kRecommendPartitions.length;
    // 起点取「页号对应的 slot」与「上次实际命中的下一个 slot」中的较大者。
    // 正常情况下二者相等（上一页命中 slot p-3，下一页从 p-2 起），只有上一页
    // 顺延过时后者更大——不然相邻页号会重复命中同一个 slot，见 [_lastServedSlot]。
    var slot = max(page - 2, _lastServedSlot + 1);
    // 某个分区翻到底时顺延到下一个分区，避免一个先耗尽的分区把整条列表卡死。
    for (var attempt = 0; attempt < slots; attempt++, slot++) {
      final result = await _fetchPartitionPage(
        header,
        partition: kRecommendPartitions[slot % slots],
        offset: (slot ~/ slots) * kPartitionPageSize,
      );
      if (result.items.isNotEmpty) {
        _lastServedSlot = slot;
        // 只要还有分区没翻完就声明"还有更多"；真正的到底由「一圈分区全空」
        // 判定（各分区深度都在 120 条上下，会在同一圈一起耗尽）。
        return LiveCategoryResult(hasMore: true, items: result.items);
      }
    }
    return LiveCategoryResult(hasMore: false, items: []);
  }

  /// 按期望条数换算并发路数。
  ///
  /// [pageSize] 在这里不当服务端的 count 参数用（服务端不认），而是「这一页
  /// 大概要给多少条」的期望值。因为切片之间约有 1/3 重叠，要拿到 N 条得
  /// 拉不止 N / 20 路，所以给下限 [kMinFeedFanout] 兜底：App 层为了让首屏
  /// 填满视口传的 30，换算出来刚好取到下限 4 路 ≈ 43 条。
  int _recommendFanout(int? pageSize) {
    final target = pageSize ?? kFeedSliceSize;
    if (target <= 0) {
      return kMinFeedFanout;
    }
    return (target / kFeedSliceSize).ceil().clamp(
          kMinFeedFanout,
          kMaxFeedFanout,
        );
  }

  /// 拉取一份推荐切片（一次 `webcast/feed/` 请求）。
  ///
  /// [sliceIndex] 只用来让每份切片的查询串彼此不同：服务端会忽略 count
  /// （传 10 / 30 / 40 / 50 / 60 都还是返回 20 条），但**参数不同的并发请求**
  /// 抽到的房间重叠更少——同一时刻 6 路实测，全部用相同参数只有 32 条去重，
  /// 每路换一个 count 则有 38 条。请求数没变，白得百分之十几。
  Future<List<LiveRoomItem>> _fetchFeedSlice(
    Map<String, dynamic> header, {
    required int sliceIndex,
  }) async {
    final result = await HttpClient.instance.getJson(
      "https://live.douyin.com/webcast/feed/",
      queryParameters: {
        "aid": "6383",
        "app_name": "douyin_web",
        "need_map": "1",
        "is_draw": "1",
        "inner_from_drawer": "0",
        "enter_source": "web_homepage_hot_web_live_card",
        "source_key": "web_homepage_hot_web_live_card",
        "count": (kFeedSliceSize * (sliceIndex + 1)).toString(),
      },
      header: header,
    );

    // 与分区接口同一套降级口径：形状不对就当空切片，交给上层按「一路失败」
    // 处理，而不是在这里抛 TypeError 把整路丢掉。
    final dataList = result is Map ? result['data'] : null;
    if (dataList is! List) {
      return const <LiveRoomItem>[];
    }
    return dataList.map(_feedRoomItemOf).whereType<LiveRoomItem>().toList();
  }

  /// 把 feed 切片里的一条数据转成 [LiveRoomItem]；数据畸形时返回 null。
  ///
  /// 与 [_roomItemOf] 是同一种「逐字段判空、脏条目跳过」的口径，只是字段布局
  /// 不同（feed 的房间挂在 `item['data']`，分区接口挂在 `item['room']`）。
  /// 这条路径是首屏必走的：一条脏数据只该让这一路切片少一条，不该让整路失败；
  /// 若形状变化是系统性的，几路一起失败就会走到 `throw CoreError`，
  /// 用户看到的是整页错误而不是「跳过脏条目」后的可用列表。
  LiveRoomItem? _feedRoomItemOf(dynamic item) {
    final data = item is Map ? item['data'] : null;
    if (data is! Map) {
      return null;
    }
    final owner = data['owner'];
    // 没有房间号就没法去重也没法进房，直接跳过。
    final webRid = owner is Map ? owner['web_rid'] : null;
    if (webRid == null) {
      return null;
    }
    final cover = data['cover'];
    final coverList = cover is Map ? cover['url_list'] : null;
    final stats = data['room_view_stats'];
    return LiveRoomItem(
      roomId: webRid.toString(),
      title: data['title']?.toString() ?? '',
      cover: (coverList is List && coverList.isNotEmpty)
          ? coverList.first.toString()
          : '',
      userName: owner is Map ? (owner['nickname']?.toString() ?? '') : '',
      online:
          int.tryParse(stats is Map ? '${stats['display_value']}' : '') ?? 0,
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    // 有两种roomId，一种是webRid，一种是roomId
    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // roomId一般长度为19位，例如：7376429659866598196
    // webRid是固定的，用户每次开播都是同一个webRid
    // webRid一般长度为11-12位，例如：416144012050
    // 这里简单进行判断，如果roomId长度小于15，则认为是webRid
    if (roomId.length <= 16) {
      return await getRoomDetailByWebRid(roomId);
    }

    // 19 位 roomId（分享链接解出来的就是这种）要先按 roomId 查 reflow/info。
    //
    // 不能先转成 webRid 再走 web/enter：对连麦、多人连线一类的房间，web/enter
    // 会返回「降级房间」——只剩 22 个字段的骨架，status 不是 2、也没有
    // stream_url，于是 detail.data 变成空 Map，后面取画质时直接抛
    // NoSuchMethodError: The method '[]' was called on null，直播间根本进不去。
    // 同一个房间用 reflow/info 查则能正常拿到 stream_url 与画质列表。
    //
    // getRoomDetailByRoomId 内部保留了「status == 4 时回退 webRid」的逻辑，
    // 所以一次性 roomId 失效（主播重开播换了房间）时行为不变。
    try {
      return await getRoomDetailByRoomId(roomId);
    } catch (e) {
      // 只把「网络抖动 / 反爬拦截」这类意外兜底到 webRid 链路。
      // CoreError 是内部刻意抛出的（房间数据异常 / 未返回房间数据），
      // 直接往上抛给用户看，不要再多打 2~3 次重复请求——
      // _getWebRid 失败时会返回原 19 位 roomId，拿它当 webRid 去请求
      // web/enter 也必然无效。
      if (e is CoreError) {
        rethrow;
      }
      CoreLog.error(e);
    }

    var webRid = await _getWebRid(roomId);
    return await getRoomDetailByWebRid(webRid);
  }

  /// 非webRid转webRid
  Future<String> _getWebRid(String roomId) async {
    var baseUrl = "https://webcast.amemv.com/douyin/webcast/reflow/";
    try {
      var response = await HttpClient.instance.getText(
        "$baseUrl$roomId",
      );
      final reg = RegExp(
          r'mysteryMan\\":1,\\\"webRid\\\":\\\"([^\\"]+)\\\",\\\"desensitizedNickname');
      var webRid = reg.firstMatch(response)?.group(1) ?? "";
      return webRid.isEmpty ? roomId : webRid;
    } catch (e) {
      CoreLog.error(e);
      return roomId;
    }
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByRoomId(String roomId) async {
    // 读取房间信息
    var roomData = await _getRoomDataByRoomId(roomId);

    // reflow/info 在房间已下播时只给骨架，任何一层都可能缺，逐层判空
    var room = _asMap(_asMap(roomData)?["data"])?["room"];
    if (room is! Map || room.isEmpty) {
      throw CoreError("抖音直播间数据异常，未能获取房间信息");
    }

    // 通过房间信息获取WebRid
    var owner = _asMap(room["owner"]) ?? const {};
    var webRid = owner["web_rid"]?.toString() ?? "";

    var status = asT<int?>(room["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4) {
      if (webRid.isEmpty) {
        throw CoreError("抖音直播间数据异常，未能获取主播 webRid");
      }
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return _buildDetailFromReflowRoom(
      room: room,
      roomId: roomId,
      headers: headers,
    );
  }

  /// 用 reflow/info 的 room 数据组装 [LiveRoomDetail]。
  ///
  /// [getRoomDetailByRoomId]（19 位 roomId 直连）与 [_getDetailByWebRidApi]
  /// 里的降级补救共用这一段，保证两条链路出来的字段口径一致。
  LiveRoomDetail _buildDetailFromReflowRoom({
    required Map room,
    required String roomId,
    required Map<String, dynamic> headers,
  }) {
    var owner = _asMap(room["owner"]) ?? const {};
    var webRid = owner["web_rid"]?.toString() ?? "";
    var roomStatus = (asT<int?>(room["status"]) ?? 0) == 2;

    return LiveRoomDetail(
      roomId: webRid.isEmpty ? roomId : webRid,
      title: room["title"]?.toString() ?? "",
      cover: roomStatus ? _firstUrl(room["cover"]) : "",
      userName: owner["nickname"]?.toString() ?? "",
      userAvatar: _firstUrl(owner["avatar_thumb"]),
      online: roomStatus
          ? asT<int?>(_asMap(room["room_view_stats"])?["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: generateRandomNumber(12).toString(),
        // getRequestHeaders 拿不到 ttwid 时 cookie 键不存在，
        // 这里给空串兜底：DouyinDanmakuArgs.cookie 是非空 String，
        // 传 null 会抛 type 'Null' is not a subtype of type 'String'
        cookie: headers["cookie"] ?? "",
      ),
      data: roomStatus ? (_asMap(room["stream_url"]) ?? const {}) : const {},
    );
  }

  /// 通过WebRid获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByWebRid(String webRid) async {
    try {
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      CoreLog.error(e);
    }
    return await _getRoomDetailByWebRidHtml(webRid);
  }

  /// 通过WebRid访问直播间API，从API中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidApi(String webRid) async {
    // 读取房间信息
    var data = await _getRoomDataByApi(webRid);

    // 被风控拦下时整个 data 会缺字段，直接交给网页版兜底，
    // 不能让它带着 null 往下走（否则报 NoSuchMethodError，用户看不懂）
    var roomList = _asMap(data)?["data"];
    if (roomList is! List || roomList.isEmpty || roomList.first is! Map) {
      throw CoreError("抖音进房接口未返回房间数据");
    }
    var roomData = roomList.first as Map;
    var userData = _asMap(_asMap(data)?["user"]) ?? const {};
    var roomId = roomData["id_str"]?.toString() ?? "";

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid) ;
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = _asMap(roomData["owner"]) ?? const {};

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    var streamData = _asMap(roomData["stream_url"]) ?? const {};

    // web/enter 对连麦 / 多人连线房间会返回「降级骨架」：room 数据在，
    // 但 status 不是 2、也没有 stream_url。首页 / 推荐 / 关注列表下发的
    // roomId 都是 webRid，全都走这条链路，所以这里必须补救，否则这些入口
    // 进连麦房间会被判成「未开播」（本次修复的目标就落空了）。
    //
    // 用 enter 返回的 roomId 再查一次 reflow/info 并**整体采信**它的结果
    // （那里能拿到 status / stream_url / 画质列表）。不能图省事调
    // getRoomDetailByRoomId：它在 status==4 时会回调 getRoomDetailByWebRid，
    // 这里又在 getRoomDetailByWebRid 里，会形成无限递归。
    if (streamData.isEmpty && roomId.isNotEmpty) {
      final reflowRoom = await _getReflowRoom(roomId);
      final reflowStream = _asMap(reflowRoom?["stream_url"]) ?? const {};
      if (reflowRoom != null && reflowStream.isNotEmpty) {
        // 主要是为了获取cookie,用于弹幕websocket连接
        var headers = await getRequestHeaders();
        return _buildDetailFromReflowRoom(
          room: reflowRoom,
          roomId: roomId,
          headers: headers,
        );
      }
    }

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();
    return LiveRoomDetail(
      roomId: webRid,
      title: roomData["title"]?.toString() ?? "",
      cover: roomStatus ? _firstUrl(roomData["cover"]) : "",
      userName: roomStatus
          ? owner["nickname"]?.toString() ?? ""
          : userData["nickname"]?.toString() ?? "",
      userAvatar: roomStatus
          ? _firstUrl(owner["avatar_thumb"])
          : _firstUrl(userData["avatar_thumb"]),
      online: roomStatus
          ? asT<int?>(_asMap(roomData["room_view_stats"])?["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        // getRequestHeaders 拿不到 ttwid 时 cookie 键不存在，
        // 这里给空串兜底：DouyinDanmakuArgs.cookie 是非空 String，
        // 传 null 会抛 type 'Null' is not a subtype of type 'String'
        cookie: headers["cookie"] ?? "",
      ),
      data: roomStatus ? streamData : const {},
    );
  }

  /// 按 roomId 从 reflow/info 取房间数据，取不到（下播骨架 / 风控）返回 null。
  ///
  /// web/enter 对连麦 / 多人连线房间会返回降级骨架，同一个房间用
  /// reflow/info 则能拿到完整数据（status / stream_url / 画质列表）。
  Future<Map?> _getReflowRoom(String roomId) async {
    try {
      var roomData = await _getRoomDataByRoomId(roomId);
      var room = _asMap(_asMap(roomData)?["data"])?["room"];
      if (room is! Map || room.isEmpty) {
        return null;
      }
      return room;
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidHtml(String webRid) async {
    var roomData = await _getRoomDataByHtml(webRid);

    // 房间已下播/不存在时网页版只有骨架，roomInfo.room 是空的，
    // 以前这里会抛 NoSuchMethodError，现在给一句能看懂的提示
    var roomInfo = _asMap(_asMap(roomData["roomStore"])?["roomInfo"]) ?? const {};
    var room = _asMap(roomInfo["room"]);
    if (room == null || room.isEmpty) {
      throw CoreError("抖音直播间数据异常，未能获取房间信息"
          "${_errorPrompt(roomData).isEmpty ? "" : "（${_errorPrompt(roomData)}）"}");
    }

    var roomId = room["id_str"]?.toString() ?? "";
    var userUniqueId = _asMap(_asMap(roomData["userStore"])?["odin"])
            ?["user_unique_id"]
            ?.toString() ??
        generateRandomNumber(12).toString();

    var owner = _asMap(room["owner"]) ?? const {};
    var anchor = _asMap(roomInfo["anchor"]) ?? const {};
    var roomStatus = (asT<int?>(room["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: room["title"]?.toString() ?? "",
      cover: roomStatus ? _firstUrl(room["cover"]) : "",
      userName: roomStatus
          ? owner["nickname"]?.toString() ?? ""
          : anchor["nickname"]?.toString() ?? "",
      userAvatar: roomStatus
          ? _firstUrl(owner["avatar_thumb"])
          : _firstUrl(anchor["avatar_thumb"]),
      online: roomStatus
          ? asT<int?>(_asMap(room["room_view_stats"])?["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        // getRequestHeaders 拿不到 ttwid 时 cookie 键不存在，
        // 这里给空串兜底：DouyinDanmakuArgs.cookie 是非空 String，
        // 传 null 会抛 type 'Null' is not a subtype of type 'String'
        cookie: headers["cookie"] ?? "",
      ),
      data: roomStatus ? (_asMap(room["stream_url"]) ?? const {}) : const {},
    );
  }

  /// 安全地把动态值当成 Map 用，不是 Map 一律返回 null
  Map? _asMap(dynamic value) => value is Map ? value : null;

  /// 解析 JSON 字符串，解析失败返回 null（不抛 [FormatException]）。
  ///
  /// 抖音的 `stream_data` 等字段可能被风控截断成半截 JSON，一旦在这里抛
  /// FormatException 就会逃出 `getPlayQualites`，直播间被判成「加载失败」。
  dynamic _safeJsonDecode(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    try {
      return json.decode(source);
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 取网页版错误信息（`detailExtra.errorPrompts`），取不到返回空串。
  ///
  /// 该字段常见形态是**字符串数组**而不是 Map，以前用 `_asMap(...).toString()`
  /// 取值恒为 null，那段「（提示）」拼接是死代码。
  String _errorPrompt(dynamic roomData) {
    final extra = _asMap(_asMap(roomData)?["detailExtra"]);
    final raw = extra?["errorPrompts"];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    if (raw is List && raw.isNotEmpty) {
      return raw.first?.toString() ?? "";
    }
    return "";
  }

  /// 取 `{"url_list": ["..."]}` 结构里的第一个地址，取不到返回空串
  String _firstUrl(dynamic value) {
    final list = _asMap(value)?["url_list"];
    if (list is List && list.isNotEmpty) {
      return list.first?.toString() ?? "";
    }
    return "";
  }

  /// 读取用户的唯一ID
  /// - [webRid] 直播间RID
  // ignore: unused_element
  Future<String> _getUserUniqueId(String webRid) async {
    try {
      var webInfo = await _getRoomDataByHtml(webRid);
      return webInfo["userStore"]["odin"]["user_unique_id"].toString();
    } catch (e) {
      return generateRandomNumber(12).toString();
    }
  }

  /// 进入直播间前需要先获取cookie
  /// - [webRid] 直播间RID
  Future<String> _getWebCookie(String webRid) async {
    var headResp = await HttpClient.instance.head(
      "https://live.douyin.com/$webRid",
      header: headers,
    );
    var dyCookie = "";
    headResp.headers["set-cookie"]?.forEach((element) {
      var cookie = element.split(";")[0];
      if (cookie.contains("ttwid")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("__ac_nonce")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("msToken")) {
        dyCookie += "$cookie;";
      }
    });
    return dyCookie;
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByHtml(String webRid) async {
    var dyCookie = await _getWebCookie(webRid);
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "Authority": kDefaultAuthority,
        "Referer": kDefaultReferer,
        "Cookie": dyCookie,
        "User-Agent": DouyinRequestParams.kDefaultUserAgent,
      },
    );

    var renderData = RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n')
            .firstMatch(result)
            ?.group(0) ??
        "";
    var str = renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll(']\\n', "");
    var renderDataJson = json.decode(str);
    return renderDataJson["state"];
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByApi(String webRid) async {
    var requestHeader = await getRequestHeaders();
    var queryParams = {
      'app_name': 'douyin_web',
      'enter_from': 'web_live',
      'live_id': '1',
      'web_rid': webRid,
      'is_need_double_stream': "false"
    };
    var targetUrl = DouyinUtils.buildRequestUrl(
        "https://live.douyin.com/webcast/room/web/enter/", queryParams);
    CoreLog.d("targetUrl: $targetUrl");
    var result = await HttpClient.instance.getJson(
      targetUrl,
      header: requestHeader,
    );
    return result["data"];
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  Future<Map> _getRoomDataByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    return result;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    List<LivePlayQuality> qualities = [];

    // 房间已下播、或进房接口被降级时 detail.data 是空 Map / 缺字段，
    // 这里必须能安全返回空列表。以前直接下标取 live_core_sdk_data，
    // 连麦等房间会抛 NoSuchMethodError: The method '[]' was called on null，
    // 整个直播间直接判成「加载失败」。
    final data = _asMap(detail.data);
    if (data == null || data.isEmpty) {
      return qualities;
    }

    final pullData = _asMap(_asMap(data["live_core_sdk_data"])?["pull_data"]);
    final qulityList = _asMap(pullData?["options"])?["qualities"];
    var streamData = pullData?["stream_data"]?.toString() ?? "";

    if (qulityList is! List || qulityList.isEmpty) {
      // 连画质列表都没有（只有 flv/hls 地址表）：直接用地址表拼，
      // 键名当画质名，顺序即档位高低
      final flvMap = _asMap(data["flv_pull_url"]) ?? const {};
      final hlsMap = _asMap(data["hls_pull_url_map"]) ?? const {};
      final keys = <dynamic>[
        ...flvMap.keys,
        ...hlsMap.keys.where((k) => !flvMap.containsKey(k)),
      ];
      var level = keys.length;
      for (final key in keys) {
        final flv = flvMap[key]?.toString() ?? "";
        final hls = hlsMap[key]?.toString() ?? "";
        List<String> urls = [];
        if (hlsFirst) {
          if (hls.isNotEmpty) urls.add(hls);
          if (flv.isNotEmpty) urls.add(flv);
        } else {
          if (flv.isNotEmpty) urls.add(flv);
          if (hls.isNotEmpty) urls.add(hls);
        }
        if (urls.isNotEmpty) {
          qualities.add(LivePlayQuality(
            quality: key.toString(),
            sort: level,
            data: urls,
          ));
        }
        level--;
      }
      qualities.sort((a, b) => b.sort.compareTo(a.sort));
      return qualities;
    }

    if (!streamData.startsWith('{')) {
      var flvList = (_asMap(data["flv_pull_url"])?.values ?? const Iterable.empty())
          .map((e) => e?.toString() ?? "")
          .where((e) => e.isNotEmpty)
          .toList();
      var hlsList =
          (_asMap(data["hls_pull_url_map"])?.values ?? const Iterable.empty())
              .map((e) => e?.toString() ?? "")
              .where((e) => e.isNotEmpty)
              .toList();
      for (var quality in qulityList) {
        if (quality is! Map) {
          continue;
        }
        int level = asT<int?>(quality["level"]) ?? 0;
        List<String> urls = [];
        var flvIndex = flvList.length - level;
        if (flvIndex >= 0 && flvIndex < flvList.length) {
          urls.add(flvList[flvIndex]);
        }
        var hlsIndex = hlsList.length - level;
        if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
          urls.add(hlsList[hlsIndex]);
        }
        var qualityItem = LivePlayQuality(
          quality: quality["name"]?.toString() ?? "",
          sort: level,
          data: urls,
        );
        if (urls.isNotEmpty) {
          qualities.add(qualityItem);
        }
      }
    } else {
      var qualityData = _asMap(_asMap(_safeJsonDecode(streamData))?["data"]);
      for (var quality in qulityList) {
        if (quality is! Map) {
          continue;
        }
        List<String> urls = [];
        final qualityItemData = _asMap(qualityData?[quality["sdk_key"]]);
        final mainData = _asMap(qualityItemData?["main"]);
        var flvUrl = mainData?["flv"]?.toString();

        if (flvUrl != null && flvUrl.isNotEmpty) {
          urls.add(flvUrl);
        }
        var hlsUrl = mainData?["hls"]?.toString();
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          if (hlsFirst) {
            urls.insert(0, hlsUrl);
          } else {
            urls.add(hlsUrl);
          }
        }
        var qualityItem = LivePlayQuality(
          quality: quality["name"]?.toString() ?? "",
          sort: asT<int?>(quality["level"]) ?? 0,
          data: urls,
        );
        if (urls.isNotEmpty) {
          qualities.add(qualityItem);
        }
      }

      //   // 真原画 media_kit 不支持 hvc1编码
      //   try{
      //     String realOriginStream =  (qualityData['ao']['main']['flv'] as String).replaceAll('&only_audio=1','');
      //     List<String> urls = [realOriginStream];
      //     var realQualityItem = LivePlayQuality(
      //       quality: "真原画",
      //       sort: 10,
      //       data: urls,
      //     );
      //     qualities.add(realQualityItem);
      //   }catch(e){
      //     CoreLog.error("未找到 ao 流 $e");
      //   }
    }
    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    return LivePlayUrl(urls: quality.data);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var uri = Uri.parse(serverUrl)
        .replace(scheme: "https", port: 443, queryParameters: {
      "device_platform": "webapp",
      "aid": "6383",
      "channel": "channel_pc_web",
      "search_channel": "aweme_live",
      "keyword": keyword,
      "search_source": "switch_tab",
      "query_correct_type": "1",
      "is_filter_search": "0",
      "from_group_id": "",
      "offset": ((page - 1) * 10).toString(),
      "count": "10",
      "pc_client_type": "1",
      "version_code": "170400",
      "version_name": "17.4.0",
      "cookie_enabled": "true",
      "screen_width": "1980",
      "screen_height": "1080",
      "browser_language": "zh-CN",
      "browser_platform": "Win32",
      "browser_name": "Edge",
      "browser_version": "125.0.0.0",
      "browser_online": "true",
      "engine_name": "Blink",
      "engine_version": "125.0.0.0",
      "os_name": "Windows",
      "os_version": "10",
      "cpu_core_num": "12",
      "device_memory": "8",
      "platform": "PC",
      "downlink": "10",
      "effective_type": "4g",
      "round_trip_time": "100",
      "webid": "7382872326016435738",
    });
    var requlestUrl = uri.toString();
    var headResp = await getRequestHeaders();
    var dyCookie = headResp['cookie'];
    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Authority": 'www.douyin.com',
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'cookie': dyCookie,
        'priority': 'u=1, i',
        'referer':
            'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
        'sec-ch-ua':
            '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': DouyinRequestParams.kDefaultUserAgent,
      },
    );
    if (result == "" || result == 'blocked') {
      throw Exception("抖音直播搜索被限制，请稍后再试");
    }
    var items = <LiveRoomItem>[];
    for (var item in result["data"] ?? []) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomItem = LiveRoomItem(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        userName: itemData["owner"]["nickname"].toString(),
        online: int.tryParse(itemData["stats"]["total_user"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: items.length >= 10, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    throw Exception("抖音暂不支持搜索主播，请直接搜索直播间");
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var result = await getRoomDetail(roomId: roomId);
    return result.status;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    return Future.value(<LiveSuperChatMessage>[]);
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  // 生成随机的数字
  int generateRandomNumber(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(10));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item);
    }
    return int.tryParse(stringBuffer.toString()) ??
        Random().nextInt(1000000000);
  }

  /// 读取A-Bogus签名后的URL
  /// - [url] 原始URL
  /// - 返回签名后的URL
  ///
  /// 服务端代码：https://github.com/dengmin/a-bogus，请自行部署后使用
  Future<String> getAbogusUrl(String url) async {
    try {
      var signResult = await HttpClient.instance.postJson(
        "https://dy.nsapps.cn/abogus",
        queryParameters: {},
        header: {"Content-Type": "application/json"},
        data: {"url": url, "userAgent": DouyinRequestParams.kDefaultUserAgent},
      );
      return signResult["data"]["url"];
    } catch (e) {
      CoreLog.error(e);
      return url;
    }
  }

  @override
  void setSiteAttrs(Map<String, dynamic> data) {
    if (data.containsKey('cookie')) {
      final cookie = data['cookie'] as String;
      if (cookie.isEmpty) {
        headers.remove('cookie');
      } else {
        headers['cookie'] = cookie;
      }
    }
    if (data.containsKey('hlsFirst')) {
      hlsFirst = data['hlsFirst'] as bool;
    }
  }
}
