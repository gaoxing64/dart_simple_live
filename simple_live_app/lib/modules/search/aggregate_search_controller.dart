import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 聚合搜索结果。原始 Core 模型不带平台信息，这里保留来源以便正确跳转。
class AggregateSearchItem {
  final Site site;
  final bool isAnchor;
  final LiveRoomItem? room;
  final LiveAnchorItem? anchor;

  const AggregateSearchItem.room(this.site, this.room)
      : isAnchor = false,
        anchor = null;

  const AggregateSearchItem.anchor(this.site, this.anchor)
      : isAnchor = true,
        room = null;
}

class _SourceState {
  _SourceState(this.site, {required this.hasMore});

  final Site site;
  int nextPage = 1;
  bool hasMore;
  int duplicatePages = 0;

  /// 本来源**连续**失败次数，成功一轮即清零。
  ///
  /// 达到 [AggregateSearchController._maxConsecutiveSourceFailures] 后置
  /// [hasMore]=false：永久坏掉的源（鉴权失效、接口改版）不该让「加载更多」
  /// 永远挂着、被用户无限重试。
  int failedPages = 0;
}

class _SourceResponse {
  _SourceResponse.success(this.state, this.items, this.hasMore) : error = null;
  _SourceResponse.failure(this.state, this.error)
      : items = const [],
        hasMore = true;

  final _SourceState state;
  final List<AggregateSearchItem> items;
  final bool hasMore;
  final Object? error;
}

/// 一次查询所有支持平台的搜索控制器。
class AggregateSearchController extends BasePageController<AggregateSearchItem> {
  static const String tag = "aggregate-search";

  /// 单来源连续失败上限：达到后该源退役（`hasMore=false`），不再参与重试。
  /// 3 次给瞬断与临时限流留了两次重试机会，又不至于让坏源永远吊着列表。
  static const int _maxConsecutiveSourceFailures = 3;

  AggregateSearchController({List<Site>? sites})
      : _sites = sites ?? Sites.supportSites;

  final List<Site> _sites;
  final RxInt searchMode = 0.obs;

  String _keyword = '';
  int _generation = 0;

  /// 用户最后一次点选、但尚未生效的模式。
  ///
  /// 生效点必须在 [_awaitPendingLoad] 之后（旧查询还在跑时改模式，新几何会套在旧
  /// 条目上）。可在那之前「房间/主播」已经被点掉了，所以这里单独记一份意图，
  /// 等真正能生效的那一刻再应用；期间界面显示的始终是 [searchMode]（列表实际内容），
  /// 不会出现「标签写着主播、下面还是房间卡片」。
  int _requestedMode = 0;
  bool _closed = false;
  Future<void>? _activeLoad;
  List<_SourceState> _states = [];
  Set<String> _seen = {};

  /// 本轮加载中失败的来源平台名，供底部重试条点名「是谁失败了」。
  ///
  /// 合并列表后用户看不出少了哪个平台，只会读成「那个平台就是没内容」；
  /// 每次 [getData] 完整跑完后整体覆写（成功轮为空），陈旧查询在
  /// `_generation` 守卫处提前返回、不会触碰它。
  final List<String> _failedSourceNames = [];

  Future<void> startSearch({
    required String keyword,
    required int searchMode,
  }) async {
    _requestedMode = searchMode;
    _invalidateInflightLoad();
    await _awaitPendingLoad();
    _keyword = keyword;
    this.searchMode.value = searchMode;
    if (_keyword.isEmpty) {
      _beginQuery();
      return;
    }
    await refreshData();
  }

  Future<void> updateSearchMode(int mode) async {
    _requestedMode = mode;
    // 点的就是当前生效模式（连点两下点回原样）：在途查询依然有效，
    // 这里既不作废也不重启，省掉一轮全平台请求。
    if (searchMode.value == mode) {
      return;
    }
    _invalidateInflightLoad();
    final invalidated = _generation;
    await _awaitPendingLoad();
    // 连点两次以最后一次为准：更早的那次点选在这里发现已有新意图就让路出去。
    if (_requestedMode != mode || searchMode.value == mode) {
      // 让路之前得确认「有人接手」。可能没人接手：新意图若等于当前生效模式，
      // 它在 await 之前就被上面那条 guard 直接挡回去了，于是本次作废的在途轮次
      // 无人重启 —— 首页被取消会留下 _doLoad 置起的 pageEmpty，翻页被取消会留下
      // canLoadMore=false 的假「已到底」。这里补一次兜底重启。
      // `_generation == invalidated` 保证期间没人开启新查询（_beginQuery /
      // refreshData 都会再递增），免得连点同一模式时把别人刚起好的查询又清一遍。
      // 必须走本类的 refreshData：只有 _beginQuery 会清 _seen，直接调 super 会把
      // 重启后的条目全判成重复项。
      if (_generation == invalidated &&
          _requestedMode == searchMode.value &&
          _keyword.isNotEmpty) {
        await refreshData();
      }
      return;
    }
    searchMode.value = mode;
    _beginQuery();
    if (_keyword.isNotEmpty) {
      await super.refreshData();
    }
  }

  @override
  Future<void> loadData() async {
    Future<void>? pending;
    while ((pending = _activeLoad) != null) {
      await pending;
    }
    final future = super.loadData();
    _activeLoad = future;
    future.whenComplete(() {
      if (identical(_activeLoad, future)) {
        _activeLoad = null;
      }
    });
    return future;
  }

  @override
  Future refreshData() async {
    if (_keyword.isEmpty) {
      return;
    }
    // 先作废再等：下拉刷新与「空/错误态的重试」都走这里，等在途查询跑完再递增
    // 等于让它把剩下的轮次全打完（详见 [_invalidateInflightLoad]）。
    _invalidateInflightLoad();
    await _awaitPendingLoad();
    _beginQuery();
    await super.refreshData();
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    super.onClose();
  }

  @override
  String? itemKey(AggregateSearchItem item) {
    final roomId = item.room?.roomId ?? item.anchor?.roomId;
    if (roomId == null || roomId.isEmpty) {
      return null;
    }
    return '${item.isAnchor ? "anchor" : "room"}:${item.site.id}:$roomId';
  }

  @override
  String get loadMoreFailedText {
    if (_failedSourceNames.isEmpty) {
      return super.loadMoreFailedText;
    }
    final names = _failedSourceNames.length <= 3
        ? _failedSourceNames.join('、')
        : '${_failedSourceNames.take(3).join('、')}等';
    return '$names 加载失败，点击重试';
  }

  @override
  Future<List<AggregateSearchItem>> getData(
    int page,
    int pageSize,
  ) async {
    final generation = _generation;
    final keyword = _keyword;
    final anchorSearch = searchMode.value == 1;
    if (keyword.isEmpty || _closed) {
      serverHasMore = false;
      return [];
    }

    if (_states.isEmpty) {
      _initSources();
    }

    final active = _states.where((state) => state.hasMore).toList();
    final output = <AggregateSearchItem>[];
    final failedNames = <String>[];
    Object? firstError;

    while (active.isNotEmpty) {
      final responses = await Future.wait(
        active.map((state) => _loadSource(state, keyword, anchorSearch)),
      );
      if (_closed || generation != _generation) {
        return [];
      }

      final freshBatches = <List<AggregateSearchItem>>[];
      for (final response in responses) {
        final error = response.error;
        if (error != null) {
          firstError ??= error;
          final state = response.state;
          final siteName = state.site.name;
          if (!failedNames.contains(siteName)) {
            failedNames.add(siteName);
          }
          state.failedPages++;
          if (state.failedPages >= _maxConsecutiveSourceFailures) {
            state.hasMore = false;
          }
          freshBatches.add(const []);
          continue;
        }

        final state = response.state;
        state.failedPages = 0;
        final fresh = _takeFreshItems(response.items);
        if (response.items.isEmpty) {
          state.hasMore = false;
        } else {
          state.nextPage++;
        }

        if (response.items.isNotEmpty && fresh.isEmpty) {
          state.duplicatePages++;
          if (state.duplicatePages >= 2) {
            state.hasMore = false;
          }
        } else {
          state.duplicatePages = 0;
        }

        if (!response.hasMore) {
          state.hasMore = false;
        }
        freshBatches.add(fresh);
      }

      final roundItems = _interleave(freshBatches);
      output.addAll(roundItems);
      active.removeWhere((state) => !state.hasMore);
      if (roundItems.isNotEmpty || firstError != null) {
        break;
      }
    }

    // 不再因 firstError 强制 true：失败源的重试寿命由
    // [_maxConsecutiveSourceFailures] 决定，触顶即 hasMore=false 退役；
    // 未触顶时它本身仍是 hasMore，`any` 已经为 true。
    serverHasMore = _states.any((state) => state.hasMore);
    _failedSourceNames
      ..clear()
      ..addAll(failedNames);
    final error = firstError;
    if (error != null) {
      loadMoreFailed.value = true;
      if (output.isEmpty) {
        throw error;
      }
    }
    return output;
  }

  /// 作废当前在途查询：让它在**当前轮**请求回来之后就收手。
  ///
  /// 必须在 `await _awaitPendingLoad()` **之前**递增。[getData] 只在每轮
  /// `Future.wait` 返回后核对代际，等旧查询跑完再递增等于放它把剩下的轮次全打完
  /// —— 聚合搜索一次并发打满全平台，遇到连续重复页还会自行续轮，新查询就得排在
  /// 这串请求后面，用户点一下要空等好几秒。提前递增，旧查询当前轮结束即止损。
  ///
  /// 代价与边界：被取消的那轮返回空列表，`BasePageController._doLoad` 会把「首页
  /// 空结果」判成没有数据并置起 `pageEmpty`。**不会闪出空态** —— 调用方紧接着就
  /// 走 [_beginQuery] 把它复位，两步之间只有微任务、没有帧边界，界面拿不到中间帧
  /// （`updateSearchMode` 让路给新意图的那条分支是唯一可能没人接手的路径，
  /// 那里有显式重启兜底）。
  void _invalidateInflightLoad() {
    _generation++;
  }

  void _beginQuery() {
    _generation++;
    _seen = {};
    list.clear();
    pageEmpty.value = false;
    pageError.value = false;
    errorMsg.value = '';
    loadFailed = false;
    loadMoreFailed.value = false;
    _failedSourceNames.clear();
    _initSources();
  }

  Future<void> _awaitPendingLoad() async {
    Future<void>? pending;
    while ((pending = _activeLoad) != null) {
      await pending;
    }
  }

  void _initSources() {
    _states = _sites
        .map(
          (site) => _SourceState(
            site,
            hasMore: _supports(site),
          ),
        )
        .toList();
  }

  bool _supports(Site site) {
    return !(searchMode.value == 1 && site.id == Constant.kDouyin);
  }

  Future<_SourceResponse> _loadSource(
    _SourceState state,
    String keyword,
    bool anchorSearch,
  ) async {
    try {
      if (anchorSearch) {
        final result = await state.site.liveSite.searchAnchors(
          keyword,
          page: state.nextPage,
        );
        return _SourceResponse.success(
          state,
          result.items.map((item) => AggregateSearchItem.anchor(state.site, item)).toList(),
          result.hasMore,
        );
      }
      final result = await state.site.liveSite.searchRooms(
        keyword,
        page: state.nextPage,
      );
      return _SourceResponse.success(
        state,
        result.items.map((item) => AggregateSearchItem.room(state.site, item)).toList(),
        result.hasMore,
      );
    } catch (e, s) {
      Log.e(
        '聚合搜索失败：site=${state.site.id} page=${state.nextPage} keyword=$keyword',
        s,
        false,
      );
      return _SourceResponse.failure(state, e);
    }
  }

  List<AggregateSearchItem> _takeFreshItems(
    List<AggregateSearchItem> items,
  ) {
    final fresh = <AggregateSearchItem>[];
    for (final item in items) {
      final key = itemKey(item);
      if (key != null && !_seen.add(key)) {
        continue;
      }
      fresh.add(item);
    }
    return fresh;
  }

  List<AggregateSearchItem> _interleave(
    List<List<AggregateSearchItem>> batches,
  ) {
    final result = <AggregateSearchItem>[];
    var index = 0;
    var hasMore = true;
    while (hasMore) {
      hasMore = false;
      for (final batch in batches) {
        if (index < batch.length) {
          result.add(batch[index]);
          hasMore = true;
        }
      }
      index++;
    }
    return result;
  }
}
