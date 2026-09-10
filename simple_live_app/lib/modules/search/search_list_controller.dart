import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';

class SearchListController extends BasePageController {
  String keyword = "";

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  SearchListController(
    this.site,
  );

  @override
  Future refreshData() async {
    if (keyword.isEmpty) {
      return;
    }
    return await super.refreshData();
  }

  @override
  Future<List> getData(int page, int pageSize) async {
    if (keyword.isEmpty) {
      return [];
    }
    if (searchMode.value == 1) {
      // 搜索主播
      var result = await site.liveSite.searchAnchors(keyword, page: page);
      return result.items;
    }
    var result = await site.liveSite.searchRooms(keyword, page: page);

    return result.items;
  }

  void clear() {
    pageEmpty.value = false;
    // 旁路清空 list，分页状态同步复位（与 follow 页同理）。
    // loadFailed 必须一并清除：它是普通字段（非响应式），只会被
    // refreshData / autoLoadIfNeeded 复位，而本方法直接把 list 清空，
    // 若不清门闩，后续触底补页会被静默挡住。
    loadFailed = false;
    loadMoreFailed.value = false;
    list.clear();
  }
}
