import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

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
      // 必须回写服务端的 hasMore：否则分页永远认为还有下一页。
      serverHasMore = result.hasMore;
      return result.items;
    }
    var result = await site.liveSite.searchRooms(keyword, page: page);
    // 必须回写服务端的 hasMore：否则分页永远认为还有下一页。
    // 虎牙搜索对 start=0/20/40 都返回同一批结果（numFound 可能小于 20），
    // 不回写会一直翻页并堆出重复卡片。
    serverHasMore = result.hasMore;

    return result.items;
  }

  /// 搜索结果的稳定去重键：跨页重复（接口忽略翻页参数或页间重叠）时跳过。
  ///
  /// 房间/主播 ID 为空时返回 null，不参与去重，避免把不同的空 ID 项误合并。
  @override
  String? itemKey(dynamic item) {
    if (item is LiveRoomItem) {
      return item.roomId.isEmpty ? null : 'room:${item.roomId}';
    }
    if (item is LiveAnchorItem) {
      return item.roomId.isEmpty ? null : 'anchor:${item.roomId}';
    }
    return null;
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
