import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/aggregate_search_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

typedef _RoomProvider = Future<LiveSearchRoomResult> Function(String keyword, int page);
typedef _AnchorProvider = Future<LiveSearchAnchorResult> Function(String keyword, int page);

class _FakeLiveSite extends LiveSite {
  _FakeLiveSite(String siteId) {
    id = siteId;
    name = siteId;
  }

  final List<int> roomPages = [];
  final List<int> anchorPages = [];
  final List<String> roomKeywords = [];
  final List<String> anchorKeywords = [];
  _RoomProvider? roomProvider;
  _AnchorProvider? anchorProvider;

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    roomKeywords.add(keyword);
    roomPages.add(page);
    return await roomProvider?.call(keyword, page) ??
        LiveSearchRoomResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    anchorKeywords.add(keyword);
    anchorPages.add(page);
    return await anchorProvider?.call(keyword, page) ??
        LiveSearchAnchorResult(hasMore: false, items: []);
  }
}

Site _site(_FakeLiveSite liveSite) => Site(
      id: liveSite.id,
      name: liveSite.name,
      logo: '',
      iconData: Icons.live_tv,
      liveSite: liveSite,
    );

LiveRoomItem _room(String id) => LiveRoomItem(
      roomId: id,
      title: 'title-$id',
      cover: '',
      userName: 'user-$id',
    );

LiveAnchorItem _anchor(String id) => LiveAnchorItem(
      roomId: id,
      avatar: '',
      userName: 'user-$id',
      liveStatus: true,
    );

LiveSearchRoomResult _rooms(
  List<LiveRoomItem> items, {
  bool hasMore = true,
}) =>
    LiveSearchRoomResult(items: items, hasMore: hasMore);

LiveSearchAnchorResult _anchors(
  List<LiveAnchorItem> items, {
  bool hasMore = true,
}) =>
    LiveSearchAnchorResult(items: items, hasMore: hasMore);

String _itemLabel(AggregateSearchItem item) {
  final id = item.room?.roomId ?? item.anchor?.roomId ?? '';
  return '${item.site.id}:$id';
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  test('房间结果并发查询各平台并按平台顺序交错', () async {
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstResponse = Completer<LiveSearchRoomResult>();
    final secondResponse = Completer<LiveSearchRoomResult>();
    final first = _FakeLiveSite(Constant.kBiliBili)
      ..roomProvider = (_, __) {
        firstStarted.complete();
        return firstResponse.future;
      };
    final second = _FakeLiveSite(Constant.kDouyu)
      ..roomProvider = (_, __) {
        secondStarted.complete();
        return secondResponse.future;
      };
    final controller = AggregateSearchController(
      sites: [_site(first), _site(second)],
    );

    final loading = controller.startSearch(keyword: 'test', searchMode: 0);
    await Future<void>.delayed(Duration.zero);

    expect(firstStarted.isCompleted, isTrue);
    expect(secondStarted.isCompleted, isTrue);

    secondResponse.complete(_rooms([_room('d1'), _room('d2')]));
    firstResponse.complete(_rooms([_room('b1'), _room('b2')]));
    await loading;

    expect(first.roomPages, [1]);
    expect(second.roomPages, [1]);
    expect(controller.list.map(_itemLabel).toList(), [
      '${Constant.kBiliBili}:b1',
      '${Constant.kDouyu}:d1',
      '${Constant.kBiliBili}:b2',
      '${Constant.kDouyu}:d2',
    ]);
    expect(controller.canLoadMore.value, isTrue);
  });

  test('主播结果保留来源平台且按平台顺序交错', () async {
    final bilibili = _FakeLiveSite(Constant.kBiliBili)
      ..anchorProvider = (_, __) async => _anchors([
            _anchor('b1'),
            _anchor('b2'),
          ]);
    final douyu = _FakeLiveSite(Constant.kDouyu)
      ..anchorProvider = (_, __) async => _anchors([_anchor('d1')]);
    final controller = AggregateSearchController(
      sites: [_site(bilibili), _site(douyu)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 1);

    expect(controller.list.map(_itemLabel).toList(), [
      '${Constant.kBiliBili}:b1',
      '${Constant.kDouyu}:d1',
      '${Constant.kBiliBili}:b2',
    ]);
    expect(controller.list.first.anchor, isNotNull);
  });

  test('单平台失败保留其他结果，并从失败页和成功平台的下一页重试', () async {
    final working = _FakeLiveSite('working')
      ..roomProvider = (_, page) async => page == 1
          ? _rooms([_room('w1')], hasMore: true)
          : _rooms([_room('w2')], hasMore: false);
    var flakyCalls = 0;
    final flaky = _FakeLiveSite('flaky')
      ..roomProvider = (_, page) async {
        flakyCalls++;
        if (page == 1 && flakyCalls == 1) {
          throw Exception('first page failed');
        }
        return _rooms([_room('f1')], hasMore: false);
      };
    final controller = AggregateSearchController(
      sites: [_site(working), _site(flaky)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 0);

    expect(working.roomPages, [1]);
    expect(flaky.roomPages, [1]);
    expect(controller.list.length, 1);
    expect(controller.loadMoreFailed.value, isTrue);
    expect(controller.canLoadMore.value, isTrue);

    await controller.retryLoadMore();

    expect(working.roomPages, [1, 2]);
    expect(flaky.roomPages, [1, 1]);
    expect(controller.list.map(_itemLabel).toList(), [
      'working:w1',
      'working:w2',
      'flaky:f1',
    ]);
    expect(controller.loadMoreFailed.value, isFalse);
  });

  test('所有适用平台均失败且没有结果时进入整页错误', () async {
    final first = _FakeLiveSite('first')
      ..roomProvider = (_, __) async => throw Exception('network down');
    final second = _FakeLiveSite('second')
      ..roomProvider = (_, __) async => throw Exception('rate limited');
    final controller = AggregateSearchController(
      sites: [_site(first), _site(second)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 0);

    expect(controller.pageError.value, isTrue);
    expect(controller.list, isEmpty);
  });

  test('所有平台均无下一页时停止加载且不显示空页', () async {
    final first = _FakeLiveSite('first')
      ..roomProvider = (_, __) async => _rooms([_room('a1')], hasMore: false);
    final second = _FakeLiveSite('second')
      ..roomProvider = (_, __) async => _rooms([_room('b1')], hasMore: false);
    final controller = AggregateSearchController(
      sites: [_site(first), _site(second)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 0);

    expect(controller.list.length, 2);
    expect(controller.canLoadMore.value, isFalse);
    expect(controller.pageEmpty.value, isFalse);
    expect(controller.showEndBar, isTrue);
  });

  test('整页错误刷新成功后清除错误状态', () async {
    var shouldFail = true;
    final site = _FakeLiveSite('retry')
      ..roomProvider = (_, __) async {
        if (shouldFail) {
          throw Exception('temporary failure');
        }
        return _rooms([_room('recovered')], hasMore: false);
      };
    final controller = AggregateSearchController(sites: [_site(site)]);

    await controller.startSearch(keyword: 'test', searchMode: 0);
    expect(controller.pageError.value, isTrue);

    shouldFail = false;
    await controller.refreshData();

    expect(controller.pageError.value, isFalse);
    expect(controller.list.map(_itemLabel).toList(), ['retry:recovered']);
  });

  test('关键词为空时刷新不发起请求也不显示空页', () async {
    final site = _FakeLiveSite('empty-refresh');
    final controller = AggregateSearchController(sites: [_site(site)]);

    await controller.refreshData();

    expect(site.roomPages, isEmpty);
    expect(controller.pageEmpty.value, isFalse);
  });

  test('新关键词查询完成后旧慢响应不得覆盖结果', () async {
    final oldResponse = Completer<LiveSearchRoomResult>();
    final newResponse = Completer<LiveSearchRoomResult>();
    final site = _FakeLiveSite('keyword')
      ..roomProvider = (keyword, __) async =>
          keyword == 'old' ? oldResponse.future : newResponse.future;
    final controller = AggregateSearchController(sites: [_site(site)]);

    final oldSearch = controller.startSearch(keyword: 'old', searchMode: 0);
    await Future<void>.delayed(Duration.zero);
    final newSearch = controller.startSearch(keyword: 'new', searchMode: 0);
    await Future<void>.delayed(Duration.zero);

    oldResponse.complete(_rooms([_room('old-result')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    expect(site.roomKeywords, ['old', 'new']);

    newResponse.complete(_rooms([_room('new-result')], hasMore: false));
    await oldSearch;
    await newSearch;

    expect(controller.list.map(_itemLabel).toList(), ['keyword:new-result']);
  });

  test('旧结果加载期间切换主播类型不会留下房间结果', () async {
    final oldResponse = Completer<LiveSearchRoomResult>();
    final newResponse = Completer<LiveSearchAnchorResult>();
    final site = _FakeLiveSite('mode-race');
    site.roomProvider = (_, __) => oldResponse.future;
    site.anchorProvider = (_, __) => newResponse.future;
    final controller = AggregateSearchController(sites: [_site(site)]);

    final oldSearch = controller.startSearch(keyword: 'test', searchMode: 0);
    await Future<void>.delayed(Duration.zero);
    final modeChange = controller.updateSearchMode(1);
    await Future<void>.delayed(Duration.zero);

    oldResponse.complete(_rooms([_room('old-room')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    expect(site.anchorPages, [1]);
    expect(controller.list, isEmpty);

    newResponse.complete(_anchors([], hasMore: false));
    await modeChange;
    await oldSearch;

    expect(controller.searchMode.value, 1);
    expect(controller.list, isEmpty);
  });

  test('主播模式排除不支持搜索主播的抖音且不触发错误', () async {
    final douyin = _FakeLiveSite(Constant.kDouyin);
    final huya = _FakeLiveSite(Constant.kHuya)
      ..anchorProvider = (_, __) async => _anchors([_anchor('h1')]);
    final controller = AggregateSearchController(
      sites: [_site(douyin), _site(huya)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 1);

    expect(douyin.anchorPages, isEmpty);
    expect(huya.anchorPages, [1]);
    expect(controller.pageError.value, isFalse);
    expect(controller.loadMoreFailed.value, isFalse);
    expect(controller.list.map(_itemLabel).toList(), ['${Constant.kHuya}:h1']);
  });

  test('房间模式仍搜索抖音', () async {
    final douyin = _FakeLiveSite(Constant.kDouyin)
      ..roomProvider = (_, __) async => _rooms([_room('d1')], hasMore: false);
    final controller = AggregateSearchController(sites: [_site(douyin)]);

    await controller.startSearch(keyword: 'test', searchMode: 0);

    expect(douyin.roomPages, [1]);
    expect(controller.list.map(_itemLabel).toList(), [
      '${Constant.kDouyin}:d1',
    ]);
  });

  test('跨平台相同房间号均保留，同平台重复项移除', () async {
    final first = _FakeLiveSite('first')
      ..roomProvider = (_, __) async => _rooms([_room('same')]);
    final second = _FakeLiveSite('second')
      ..roomProvider = (_, __) async => _rooms([_room('same')]);
    final third = _FakeLiveSite('third')
      ..roomProvider = (_, __) async => _rooms([_room('same'), _room('other')]);
    final controller = AggregateSearchController(
      sites: [_site(first), _site(second), _site(third)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 0);

    expect(controller.list.map(_itemLabel).toList(), [
      'first:same',
      'second:same',
      'third:same',
      'third:other',
    ]);
  });

  test('平台连续两页全部重复后停止该平台且不重复追加', () async {
    final repeating = _FakeLiveSite('repeating')
      ..roomProvider = (_, __) async => _rooms([_room('same')]);
    final controller = AggregateSearchController(
      sites: [_site(repeating)],
    );

    await controller.startSearch(keyword: 'test', searchMode: 0);
    await controller.loadData();

    expect(repeating.roomPages, [1, 2, 3]);
    expect(controller.list.length, 1);
    expect(controller.canLoadMore.value, isFalse);
  });

  test('页面关闭后迟到响应不得更新结果', () async {
    final completion = Completer<LiveSearchRoomResult>();
    final slow = _FakeLiveSite('slow')
      ..roomProvider = (_, __) => completion.future;
    final controller = AggregateSearchController(sites: [_site(slow)]);

    final loading = controller.startSearch(keyword: 'test', searchMode: 0);
    await Future<void>.delayed(Duration.zero);
    controller.onClose();
    completion.complete(_rooms([_room('late')]));
    await loading;

    expect(controller.list, isEmpty);
  });
}
