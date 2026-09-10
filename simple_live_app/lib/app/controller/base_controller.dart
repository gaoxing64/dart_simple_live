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
  int pageSize = 24;
  var canLoadMore = false.obs;
  var list = <T>[].obs;

  /// 是否正在加载下一页（用于列表底部骨架占位）
  var loadingMore = false.obs;

  /// 上一次加载是否失败。
  ///
  /// 失败时 `canLoadMore` 仍为 true 且页码未推进，若继续自动加载会
  /// "请求失败 → 骨架消失、内容收缩 → 尺寸变化又触发加载"无限重试，
  /// 因此自动加载用它做门闩：需要用户离开底部后重新触底、下拉刷新，
  /// 或点击"加载更多"才会重试。
  bool loadFailed = false;

  /// 进行中的加载（用于让并发调用共享同一次请求）
  Future<void>? _currentLoad;

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

  Future<void> _doLoad() async {
    loadding = true;
    loadingMore.value = currentPage > 1;
    try {
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = currentPage == 1;

      var result = await getData(currentPage, pageSize);
      loadFailed = false;
      //是否可以加载更多
      if (result.isNotEmpty) {
        currentPage++;
        canLoadMore.value = true;
        pageEmpty.value = false;
      } else {
        canLoadMore.value = false;
        if (currentPage == 1) {
          pageEmpty.value = true;
        }
      }
      // 赋值数据
      if (currentPage == 1) {
        list.value = result;
      } else {
        list.addAll(result);
      }
    } catch (e) {
      loadFailed = true;
      handleError(e, showPageError: currentPage == 1);
    } finally {
      loadding = false;
      loadingMore.value = false;
      pageLoadding.value = false;
      _currentLoad = null;
    }
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
