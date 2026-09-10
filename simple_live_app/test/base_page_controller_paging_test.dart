// 回归测试：分页判定应采信服务端的 hasMore，并在接口不支持翻页时停止加载。
//
// 背景：core 层各平台都已算好 LiveCategoryResult.hasMore，但 App 层过去
// 只用「本页是否非空」判断 canLoadMore，导致抖音这类返回固定条数、又忽略
// 翻页参数的接口"加载更多"永远为真，一路堆重复卡片。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

LiveRoomItem _room(int id) => LiveRoomItem(
      roomId: 'r$id',
      title: 'room $id',
      cover: '',
      userName: 'user$id',
    );

/// 模拟真实平台接口：支持翻页，并由服务端给出 hasMore。
class PagedRoomController extends BasePageController<LiveRoomItem> {
  PagedRoomController({
    required this.serverHasMoreFlag,
    this.ignorePaging = false,
  });

  /// 服务端返回的 hasMore
  final bool serverHasMoreFlag;

  /// true 表示接口忽略了翻页参数，每页都返回同一批数据
  /// （抖音推荐流修复前的行为）
  final bool ignorePaging;

  final List<int> requestedPages = [];
  final List<int> requestedPageSizes = [];

  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    requestedPageSizes.add(pageSize);
    serverHasMore = serverHasMoreFlag;
    if (ignorePaging) {
      return List.generate(pageSize, _room);
    }
    final start = (page - 1) * pageSize;
    return List.generate(pageSize, (i) => _room(start + i));
  }
}

/// 未实现 [itemKey] 的子类：应保持"不去重"的旧行为（本地数据源）。
class NoKeyRoomController extends BasePageController<LiveRoomItem> {
  final List<int> requestedPages = [];

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    return List.generate(pageSize, _room);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单页条数取 30，且会透传给 getData', () async {
    final controller = PagedRoomController(serverHasMoreFlag: true);
    expect(controller.pageSize, 30);

    await controller.refreshData();
    expect(controller.requestedPageSizes.single, 30);
  });

  test('服务端 hasMore=false 时第一页后即停止加载', () async {
    final controller = PagedRoomController(serverHasMoreFlag: false);
    await controller.refreshData();

    expect(controller.list.length, 30);
    expect(controller.canLoadMore.value, isFalse,
        reason: '服务端说没有更多，就不该再让自动补页继续请求');
    expect(controller.pageEmpty.value, isFalse);
  });

  test('服务端 hasMore=true 时可继续加载，且跨页无重复', () async {
    final controller = PagedRoomController(serverHasMoreFlag: true);
    await controller.refreshData();

    expect(controller.canLoadMore.value, isTrue);
    await controller.loadData();

    expect(controller.requestedPages, [1, 2]);
    expect(controller.list.length, 60);
    expect(controller.list.map((e) => e.roomId).toSet().length, 60,
        reason: '两页房间号应互不相同');
  });

  test('接口忽略翻页参数时，连续多页零新增才停止且不产生重复卡片', () async {
    final controller = PagedRoomController(
      serverHasMoreFlag: true,
      ignorePaging: true,
    );
    await controller.refreshData();
    expect(controller.list.length, 30);

    await controller.loadData(); // 第 2 页：全为重复项，累计 1 页
    expect(controller.list.length, 30, reason: '全为重复项，不应追加');
    expect(controller.canLoadMore.value, isTrue,
        reason: '单页零新增不判死——榜单类接口页间会重排，'
            '某一页恰好全重复属正常波动，判死会造成静默死路');

    await controller.loadData(); // 第 3 页：仍全为重复项，累计 2 页 → 停
    expect(controller.requestedPages, [1, 2, 3]);
    expect(controller.list.length, 30, reason: '全为重复项，不应追加');
    expect(controller.canLoadMore.value, isFalse,
        reason: '连续两页零新增必须停下，否则自动补页会无限空转');
  });

  test('未实现 itemKey 的子类保持旧行为（不去重、非空即可加载更多）', () async {
    final controller = NoKeyRoomController();
    await controller.refreshData();
    await controller.loadData();

    expect(controller.list.length, 60, reason: '未去重，重复项照常追加');
    expect(controller.canLoadMore.value, isTrue);
    expect(controller.serverHasMore, isNull);
  });

  test('接口返回空页时停止加载，且第一页为空标记 pageEmpty', () async {
    final controller = PagedRoomController(serverHasMoreFlag: true);
    controller.currentPage = 1;
    await controller.refreshData();
    expect(controller.list.length, 30);

    // 直接跳到"空页"场景
    final emptyController = _EmptyFirstPageController();
    await emptyController.refreshData();
    expect(emptyController.list, isEmpty);
    expect(emptyController.pageEmpty.value, isTrue);
    expect(emptyController.canLoadMore.value, isFalse);
  });

  test('非首页失败时置起可观察重试标记，且失败页不自增', () async {
    final controller = _FailOnceSecondPageController();
    await controller.refreshData();

    expect(controller.loadMoreFailed.value, isFalse,
        reason: '第一页成功，不该出现重试条');

    await controller.loadData(); // 第 2 页失败
    expect(controller.loadFailed, isTrue);
    expect(controller.loadMoreFailed.value, isTrue,
        reason: '界面需要可观察标记才能渲染重试条（loadFailed 是普通 bool，不触发重建）');
    expect(controller.showLoadMoreFailedBar, isTrue);
    expect(controller.requestedPages, [1, 2]);
    expect(controller.currentPage, 2, reason: '失败页不自增，重试才能续上同一页');
    expect(controller.list.length, 30, reason: '已到手的数据不受影响');

    // 注意：门闩只挡 autoLoadIfNeeded 这条自动路径，不挡 loadData()。
    // 「失败后不会无限自动重试」由 page_view_auto_load_test.dart 的
    // 控件级用例覆盖（那里才走得到 autoLoadIfNeeded）。
  });

  test('retryLoadMore 解除门闩并成功续上下一页', () async {
    final controller = _FailOnceSecondPageController();
    await controller.refreshData();
    await controller.loadData();
    expect(controller.loadMoreFailed.value, isTrue);

    await controller.retryLoadMore();

    expect(controller.loadFailed, isFalse, reason: '重试前必须先解闩');
    expect(controller.loadMoreFailed.value, isFalse, reason: '成功后重试条应消失');
    expect(controller.showLoadMoreFailedBar, isFalse);
    expect(controller.requestedPages, [1, 2, 2],
        reason: '重试的是失败的同一页，不应跳过它');
    expect(controller.list.length, 60);
  });

  _aliasingRegressionTests();
}

/// 第 2 页失败一次，之后恢复正常（用于验证重试路径真的能续上）。
class _FailOnceSecondPageController extends BasePageController<LiveRoomItem> {
  final List<int> requestedPages = [];
  bool _failed = false;

  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    requestedPages.add(page);
    serverHasMore = true;
    if (page == 2 && !_failed) {
      _failed = true;
      throw Exception('network down');
    }
    final start = (page - 1) * pageSize;
    return List.generate(pageSize, (i) => _room(start + i));
  }

  // 错误提示会走到 SmartDialog，测试环境不加载它
  @override
  void handleError(Object exception, {bool showPageError = false}) {}
}

class _EmptyFirstPageController extends BasePageController<LiveRoomItem> {
  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async => [];
}

/// 返回数据源内部 List（不拷贝）的子类。
///
/// 复刻 FollowUserController 的写法：getData 直接把服务层持有的那个 List
/// 交出去，用于验证基类不会让页面列表与数据源共享同一个 List 对象。
class _SharedSourceController extends BasePageController<LiveRoomItem> {
  _SharedSourceController(this.source);

  final List<LiveRoomItem> source;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    if (page > 1) {
      return [];
    }
    return source;
  }
}

void _aliasingRegressionTests() {
  // 回归：关注页刷新完成后变空。
  //
  // FollowUserController.getData 返回 FollowService.followList.value（同一
  // 个 List 对象），基类若直接 list.value = result，页面列表就与数据源共享
  // 底层 List；之后 filterData() 的 list.assignAll(数据源) 会自我清空
  // （get 的 assignAll = clear() + addAll(items)），关注页内容整片消失。
  test('getData 返回外部 List 时不得与之共享引用', () async {
    final source = <LiveRoomItem>[_room(1), _room(2), _room(3)];
    final controller = _SharedSourceController(source);

    await controller.refreshData();
    expect(controller.list.length, 3);

    source.removeLast();
    expect(controller.list.length, 3,
        reason: '页面列表必须是独立副本，外部改动不应穿透进来');
  });

  test('对数据源自赋值不会清空页面列表', () async {
    final source = <LiveRoomItem>[_room(1), _room(2)];
    final controller = _SharedSourceController(source);
    await controller.refreshData();

    // filterData() 的行为：list.assignAll(数据源)
    controller.list.assignAll(source);

    expect(controller.list.length, 2, reason: '自赋值不得把列表清空');
    expect(source.length, 2, reason: '数据源必须原封不动');
  });

  test('retainWhere 不会删改数据源', () async {
    final source = <LiveRoomItem>[_room(1), _room(2)];
    final controller = _SharedSourceController(source);
    await controller.refreshData();

    // filterData() 在开启「隐藏未开播」时的行为
    controller.list.retainWhere((item) => item.roomId == 'r1');

    expect(controller.list.length, 1);
    expect(source.length, 2, reason: '数据源不应被页面列表的过滤连带删掉');
  });
}
