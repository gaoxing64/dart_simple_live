import 'dart:async';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class BaseController extends GetxController {
  /// 加载中，更新页面
  var pageLoadding = false.obs;

  /// 加载中,不会更新页面
  var loadding = false;

  /// 空白页面
  var pageEmpty = false.obs;

  /// 页面错误
  var pageError = false.obs;

  /// 未登录
  var notLogin = false.obs;

  /// 错误信息
  var errorMsg = "".obs;

  /// 显示错误
  /// * [msg] 错误信息
  /// * [showPageError] 显示页面错误
  /// * 只在第一页加载错误时showPageError=true，后续页加载错误时使用Toast弹出通知
  void handleError(Object exception, {bool showPageError = false}) {
    Log.e(exception.toString(), StackTrace.current);
    var msg = exceptionToString(exception);

    if (showPageError) {
      pageError.value = true;
      errorMsg.value = msg;
    } else {
      SmartDialog.showToast(exceptionToString(msg));
    }
  }

  String exceptionToString(Object exception) {
    return exception.toString().replaceAll("Exception:", "");
  }

  void onLogin() {}
  void onLogout() {}
}

class BasePageController<T> extends BaseController {
  final ScrollController scrollController = ScrollController();
  final EasyRefreshController easyRefreshController = EasyRefreshController();
  int currentPage = 1;
  int count = 0;
  int maxPage = 0;

  /// 请求的单页条数。
  ///
  /// 由 [getData] 的实现转交给 core 层（`getRecommendRooms` /
  /// `getCategoryRooms` 的 `pageSize`），接口支持按此调整返回量。
  /// 取 30 是为了在宽窗口（约 6 列，每行 180px）下第一页就能铺满
  /// 一屏，避免"内容不足一屏 ⇒ 列表不可滚动 ⇒ 滚轮触发不了加载"。
  int pageSize = 30;

  var canLoadMore = false.obs;
  var list = <T>[].obs;

  /// 服务端返回的"是否还有更多"。
  ///
  /// 子类在 [getData] 内把 core 层算好的 `hasMore` 写进来，分页判定就会
  /// 采信服务端的结论；保持 null 则退回"本页有数据就认为还有更多"的旧行为
  /// （本地数据源如历史记录、分类列表依赖这个兜底）。
  /// 每次加载前会被重置，避免上一页的结果影响本页。
  bool? serverHasMore;

  /// 是否正在加载下一页（用于列表底部骨架占位）
  var loadingMore = false.obs;

  /// 上一次加载是否失败。
  ///
  /// 失败时 `canLoadMore` 仍为 true 且页码未推进，若继续自动加载会
  /// "请求失败 → 骨架消失、内容收缩 → 尺寸变化又触发加载"无限重试，
  /// 因此自动加载用它做门闩：需要用户离开底部后重新触底、下拉刷新，
  /// 或点击"加载更多"才会重试。
  bool loadFailed = false;

  /// 非首页加载失败的可观察镜像，供界面渲染"加载失败，点击重试"。
  ///
  /// 为什么不直接用 [loadFailed]：它是普通字段（同步门闩，供
  /// `autoLoadIfNeeded` 在滚动通知回调里读），**不会触发重建**，
  /// 直接拿到 Obx 里渲染是无效的。两者的写入点必须成对维护，
  /// 分散在 [_doLoad]（开头置 false / catch 置 `!isFirstPage`）与
  /// `autoLoadIfNeeded`（离开底部时一并清除）。
  var loadMoreFailed = false.obs;

  /// 是否展示列表底部的「加载更多失败」重试条。
  ///
  /// 带上 [canLoadMore] 是安全网：关注页 / 搜索页会绕过 [_doLoad] 直接写
  /// [list] 并把 canLoadMore 置 false，此时即使残留 loadMoreFailed
  /// 也不该显示一个点了没用的重试条。
  bool get showLoadMoreFailedBar =>
      loadMoreFailed.value && canLoadMore.value && !loadingMore.value;

  /// 进行中的加载（用于让并发调用共享同一次请求）
  Future<void>? _currentLoad;

  /// 连续「本页数据全部重复」的页数。
  ///
  /// 单页零新增不足以判定到头：榜单类接口（bilibili `sort=online`、
  /// 虎牙按热度排）页间会重排，某一页恰好全是已展示项属于正常波动，
  /// 判死会让分页在没有可见原因的情况下永久停住。
  int _duplicatePageStreak = 0;

  /// 允许的连续重复页上限，子类可覆写。
  ///
  /// 取 2 是权衡：比「见一页重复就停」多一次请求，换来消除静默死路。
  int get maxDuplicatePages => 2;

  Future refreshData() async {
    // 若有进行中的加载，先等它结束再刷新：否则刷新会被守卫直接丢弃，
    // 且在途请求返回后会把"第二页数据当成第一页"写进刚清空的列表，
    // 导致页码与内容错位（跳过第一页）。
    final pending = _currentLoad;
    if (pending != null) {
      await pending;
    }
    currentPage = 1;
    list.value = [];
    loadFailed = false;
    // 与 loadFailed 成对复位：刷新期间列表是空的，残留的 loadMoreFailed
    // 会让重试条在 `await pending` 的异步间隙里闪现一帧。
    loadMoreFailed.value = false;
    _duplicatePageStreak = 0;
    await loadData();
  }

  /// 加载当前页。
  ///
  /// 并发调用（自动加载 / easy_refresh footer）不会重复请求，而是共享
  /// 同一个 Future；守卫不能放在 try/finally 内，否则提前 return 会走进
  /// finally 把进行中加载的状态清掉。
  Future<void> loadData() {
    if (loadding) {
      return _currentLoad ?? Future<void>.value();
    }
    final future = _doLoad();
    _currentLoad = future;
    return future;
  }

  /// 手动重试当前页（供列表底部的失败重试条调用）。
  ///
  /// 自动加载被 [loadFailed] 门闩挡住时，这是用户唯一能主动恢复的入口。
  /// 必须先解闩再加载，否则重试成功后 `autoLoadIfNeeded` 仍被挡住，
  /// 而重试条又已消失，用户会以为"点了没反应"。
  ///
  /// [loadData] 自带并发守卫（loadding 时复用 `_currentLoad`），无需重复判断。
  Future<void> retryLoadMore() {
    loadFailed = false;
    loadMoreFailed.value = false;
    return loadData();
  }

  Future<void> _doLoad() async {
    loadding = true;
    loadingMore.value = currentPage > 1;
    // 每次加载前重置，避免上一页写入的 hasMore 影响本页判定
    serverHasMore = null;
    // 提前取出：catch 里判断「是否首页失败」也要用它
    final isFirstPage = currentPage == 1;
    try {
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = isFirstPage;
      // 新一次尝试开始，先收掉上一次留下的重试条
      loadMoreFailed.value = false;

      var result = await getData(currentPage, pageSize);
      loadFailed = false;

      // 跨页去重：接口不支持翻页时会重复返回同一批数据，原样追加会堆出
      // 大量重复卡片（抖音推荐流原实现即如此）。
      final added = isFirstPage ? result : _appendDistinct(result);
      if (result.isNotEmpty) {
        currentPage++;
      }

      // 是否可以加载更多：
      // 1. 本页没返回任何数据 → 停；
      // 2. 服务端明确说没有更多（core 的 hasMore）→ 停；
      // 3. 连续 [maxDuplicatePages] 页数据全是重复的（接口忽略了翻页参数）
      //    → 停，否则自动补页会在"补页 → 零新增 → 再补页"之间空转。
      //    不取「单页零新增即停」：榜单类接口页间会重排，某一页恰好全重复
      //    属于正常波动，判死会让分页在无可见原因的情况下永久停住。
      final duplicated = !isFirstPage && result.isNotEmpty && added.isEmpty;
      _duplicatePageStreak = duplicated ? _duplicatePageStreak + 1 : 0;
      final serverMore = serverHasMore ?? true;
      final noMoreHere = _duplicatePageStreak >= maxDuplicatePages;
      canLoadMore.value = result.isNotEmpty && serverMore && !noMoreHere;
      if (isFirstPage && result.isEmpty) {
        pageEmpty.value = true;
      }

      // 赋值数据。
      //
      // 第一页必须拷贝一份：getData 有可能直接返回数据源内部的 List
      // （例如关注页返回 FollowService.followList.value），而 RxList 的
      // value setter 是直接赋值、不做拷贝。一旦 list 与数据源共享同一个
      // List 对象，后续 list.assignAll(源) 就会自我清空（get 的 assignAll
      // 实现为 clear() + addAll(items)），list.retainWhere 也会连带删掉
      // 数据源里的数据。
      if (isFirstPage) {
        list.value = List<T>.from(added);
      } else {
        list.addAll(added);
      }
    } catch (e) {
      loadFailed = true;
      // 只有非首页失败才需要常驻的重试入口：首页失败走整页错误态
      loadMoreFailed.value = !isFirstPage;
      handleError(e, showPageError: isFirstPage);
    } finally {
      loadding = false;
      loadingMore.value = false;
      pageLoadding.value = false;
      _currentLoad = null;
    }
  }

  /// 列表项的去重键；返回 null 表示该项不参与跨页去重。
  ///
  /// 默认返回 null（即不去重），需要去重的子类返回稳定标识即可，
  /// 例如直播间的 `roomId`。
  String? itemKey(T item) => null;

  /// 过滤掉已被 [list] 收录、或本页内自身重复的项。
  ///
  /// [itemKey] 返回 null 的项一律保留（等同不去重）。
  List<T> _appendDistinct(List<T> incoming) {
    final seen = <String>{};
    for (final item in list) {
      final key = itemKey(item);
      if (key != null) {
        seen.add(key);
      }
    }
    final fresh = <T>[];
    for (final item in incoming) {
      final key = itemKey(item);
      // add 返回 false 表示已存在，跳过该重复项
      if (key != null && !seen.add(key)) {
        continue;
      }
      fresh.add(item);
    }
    return fresh;
  }

  Future<List<T>> getData(int page, int pageSize) async {
    return [];
  }

  void scrollToTopOrRefresh() {
    if (scrollController.offset > 0) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    } else {
      easyRefreshController.callRefresh();
    }
  }
}
