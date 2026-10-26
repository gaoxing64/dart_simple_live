import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HomeListController extends BasePageController<LiveRoomItem> {
  final Site site;
  HomeListController(this.site);

  /// 同一房间可能跨页重复出现（抖音推荐流不真正支持翻页），按房间号去重。
  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    var result = await site.liveSite
        .getRecommendRooms(page: page, pageSize: pageSize);
    // 采信服务端的 hasMore：抖音等平台的推荐流用"本页是否非空"判断会导致
    // canLoadMore 永远为 true，"加载更多"一直堆重复数据。
    serverHasMore = result.hasMore;
    return result.items;
  }
}
