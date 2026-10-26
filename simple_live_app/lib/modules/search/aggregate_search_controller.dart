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

  AggregateSearchController({List<Site>? sites})
      : _sites = sites ?? Sites.supportSites;

  final List<Site> _sites;
  final RxInt searchMode = 0.obs;

  String _keyword = '';
  int _generation = 0;
  bool _closed = false;
  Future<void>? _activeLoad;
  List<_SourceState> _states = [];
  Set<String> _seen = {};

  Future<void> startSearch({
    required String keyword,
    required int searchMode,
  }) async {
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
    if (searchMode.value == mode) {
      return;
    }
    await _awaitPendingLoad();
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
          freshBatches.add(const []);
          continue;
        }

        final state = response.state;
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

    serverHasMore = _states.any((state) => state.hasMore) || firstError != null;
    final error = firstError;
    if (error != null) {
      loadMoreFailed.value = true;
      if (output.isEmpty) {
        throw error;
      }
    }
    return output;
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
