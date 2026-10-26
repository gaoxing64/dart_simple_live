import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class CategoryDetailController extends BasePageController<LiveRoomItem> {
  final Site site;
  final LiveSubCategory subCategory;
  CategoryDetailController({
    required this.site,
    required this.subCategory,
  });

  /// 同一房间可能跨页重复出现，按房间号去重。
  @override
  String? itemKey(LiveRoomItem item) => item.roomId;

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    var result = await site.liveSite
        .getCategoryRooms(subCategory, page: page, pageSize: pageSize);
    serverHasMore = result.hasMore;
    return result.items;
  }
}
