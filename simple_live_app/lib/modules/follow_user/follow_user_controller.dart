// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser> {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 0:全部 1:直播中 2:未直播
  var filterMode = FollowUserTag(id: "0", tag: "全部", userId: []).obs;

  /// 3 个内置标签。**它们是滚动锚点，不是筛选条件**（见 [filterData]）。
  static const builtinTags = ["全部", "直播中", "未开播"];

  /// 3 个内置标签的 id（写死在 [tagList] 的前三项）。
  ///
  /// 自定义标签的 id 由 `FractionalIndexing.generateKeyBetween` 生成，
  /// 形如 `a0` / `a1`（至少两位、字母开头），**不可能**是这里的单个数字，
  /// 所以按 id 判定比按名字判定稳：用户建一个叫「直播中」的自定义标签，
  /// 不会再被误当成内置锚点，导致点它没反应。
  static const builtinTagIds = ["0", "1", "2"];

  static bool isBuiltinTag(FollowUserTag tag) => builtinTagIds.contains(tag.id);

  /// 名字是内置标签的保留字时拒绝占用（add / rename 都会调到）。
  ///
  /// 配合 [isBuiltinTag] 的 id 判定：id 不会撞，名字也不让撞，
  /// 同步导入的旧备份里万一有同名标签，最多是显示重名，不会让筛选失效。
  static bool isReservedTagName(String name) =>
      builtinTags.contains(name.trim());

  /// 顶部锚点 tab 当前高亮的那一项（0=全部 1=直播中 2=未开播）。
  ///
  /// 既跟着点击走，也由页面 `_AnchorTabBar` 的滚动监听按 `_sectionTop`
  /// 的几何反推当前落在哪一段（偏移公式与 `PageGridView` 的段布局常量耦合）。
  final activeTab = 0.obs;

  /// 顶部搜索框的内容，空串表示不过滤。
  ///
  /// 过滤在页面层做（`_visibleList`），**不放进 [filterData]** —— 后者会被
  /// `super.refreshData()` 的加载结果覆盖掉，搜索词会被冲掉。
  final searchQuery = "".obs;

  /// 搜索框的文本控制器。
  ///
  /// 页面里那个 `TextField` 必须用它，清空按钮才能真的把**输入框里的字**清掉
  /// —— 只改 [searchQuery] 的话输入框内容还在，看起来像没生效。
  final searchController = TextEditingController();

  /// 当前要展示的两段数据。
  ///
  /// 在播的（`liveStatus == 2`）在上、走卡片；其余（未开播 + 读取中）在下、
  /// 走紧凑行。**不能直接用 `FollowService.liveList` / `notLiveList`** ——
  /// 那两个都不含「读取中」(status 0) 的房间，直接用会让它们凭空消失。
  /// 读取中的房间归到下面那段，至少还看得见。
  ///
  /// 必须在 `Obx` 里读：内部会读 `list`（RxList）与每项的 `liveStatus`，
  /// 状态一回来两段会自己重切。
  List<FollowUser> get liveSection =>
      visibleList.where((u) => u.liveStatus.value == 2).toList();

  List<FollowUser> get offlineSection =>
      visibleList.where((u) => u.liveStatus.value != 2).toList();

  /// [list] 再叠一层搜索过滤。搜索词为空时就是原样返回。
  List<FollowUser> get visibleList {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) {
      return list;
    }
    return list.where((u) {
      final name = u.remark?.isNotEmpty == true ? u.remark! : u.userName;
      return name.toLowerCase().contains(q) ||
          u.userName.toLowerCase().contains(q) ||
          u.title.value.toLowerCase().contains(q);
    }).toList();
  }
  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "直播中", userId: []),
    FollowUserTag(id: "2", tag: "未开播", userId: []),
  ].obs;

  // 用户自定义标签
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  // 用户自定义显示顺序 - default：watchDuration
  Rx<SortMethod> sortMethod = SortMethod.watchDuration.obs;

  // 排序方式
  var sortMap = {
    SortMethod.watchDuration: "观看时长",
    SortMethod.siteId: "直播平台",
    SortMethod.recently: "最近添加",
    SortMethod.userNameASC: "用户名A-Z",
    SortMethod.userNameDESC: "用户名Z-A",
    SortMethod.tag: "自定义标签",
  };

  @override
  void onInit() {
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream = FollowService.instance.updatedListStream.listen(
      (event) {
        updateTagList();
        filterData();
      },
    );

    sortMethod = AppSettingsController.instance.followSortMethod;
    super.onInit();
  }

  @override
  Future refreshData() async {
    await FollowService.instance.loadData();
    updateTagList();
    // 必须 await：super.refreshData 才是真正拉数据的那一次加载，
    // 不等待会让 easy_refresh 的刷新指示器提前收起。
    await super.refreshData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    if (page > 1) {
      return Future.value([]);
    }
    // 一律返回副本：这些 List 是 FollowService 的数据源，直接交出去会与
    // 页面列表共享同一个 List 对象，filterData 的 assignAll / retainWhere
    // 会反过来清空或删改数据源。
    // 3 个内置标签是滚动锚点、不过滤，所以和「全部」一样给完整列表。
    if (isBuiltinTag(filterMode.value)) {
      return List.of(FollowService.instance.followList.value);
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      return List.of(FollowService.instance.curTagFollowList.value);
    }
  }

  void updateTagList() {
    userTagList.assignAll(FollowService.instance.followTagList);
    tagList.value = tagList.take(3).toList();
    for (var i in userTagList) {
      if (!tagList.contains(i)) {
        tagList.add(i);
      }
    }
  }

  // 数据清洗：不关心中间 data_flow，最终由filterData决定显示数据
  //
  // 注意：本方法绕过 BasePageController._doLoad 直接写 list，因此必须自己
  // 同步分页状态。否则上一次加载留下的 pageEmpty=true 会继续用空态浮层
  // 盖住列表，表现为「切换 tag 没有任何作用」。
  void filterData() {
    bool hideOffline = AppSettingsController.instance.hideOfflineFollow.value;

    // 「全部 / 直播中 / 未开播」三个内置标签**不再是筛选条件**，而是页面顶部的
    // 滚动锚点（点一下滚到对应那一段）。所以它们一律给完整列表，由页面按
    // liveStatus 切成「正在直播」和「未开播」两段。
    if (isBuiltinTag(filterMode.value)) {
      list.assignAll(FollowService.instance.followList.value);
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      list.assignAll(FollowService.instance.curTagFollowList.value);
    }

    // 「隐藏离线关注」直接把未开播那一段砍掉。原来这里对「未开播」筛选留了个
    // 例外（`tag != "未开播"`），现在它成了锚点、不再是筛选条件，例外已无意义。
    if (hideOffline) {
      list.retainWhere((user) => user.liveStatus.value == 2);
    }

    // 关注列表是本地单页数据源，getData 对 page>1 恒返回空，没有下一页可加载
    canLoadMore.value = false;
    pageEmpty.value = list.isEmpty;
    // 本方法绕过 _doLoad 直接写 list，错误态也要自己清理，
    // 否则上一次加载失败的错误浮层会继续盖住刚切出来的内容
    pageError.value = false;
    // 失败标记同样成对清除。目前 canLoadMore 恒为 false 使门闩读不到，
    // 但状态不一致本身就是隐患：一旦将来关注页接上真实分页，
    // 残留的 loadFailed 会让补页在无可见原因的情况下被挡住。
    loadFailed = false;
    loadMoreFailed.value = false;
  }

  // 用户自定义顺序dialog
  Future<void> showSortDialog() async {
    var res = await Utils.showMapOptionDialog(sortMap, sortMethod.value,
        title: "排序方式");
    if (res != null) {
      sortMethod.value = res;
      AppSettingsController.instance.setFollowSortMethod(sortMethod.value);
      // 排序作用于整个关注列表，两段各自继承（未开播那段也就跟着排了）。
      FollowService.instance.liveListSort();
      filterData();
    }
  }

  void setFilterMode(FollowUserTag tag) {
    filterMode.value = tag;
    filterData();
  }

  void removeFollow(FollowUser follow) async {
    var result = await Utils.showAlertDialog("确定要取消关注${follow.userName}吗?",
        title: "取消关注");
    if (!result) {
      return;
    }
    // 取消关注同时删除标签内的 userId
    if (follow.tag != "全部") {
      var tag = tagList.firstWhereOrNull((tag) => tag.tag == follow.tag);
      if (tag != null) {
        tag.userId.remove(follow.id);
        updateTag(tag);
      }
    }
    await FollowService.instance.removeFollowUser(follow.id);
    filterData();
  }

  Future<void> updateFollow(FollowUser follow) async {
    await FollowService.instance.addFollow(follow);
  }

  void setFollowTag(FollowUser follow, FollowUserTag targetTag) {
    FollowService.instance.setFollowTag(follow, targetTag);
    filterData();
  }

  Future<void> updateTag(FollowUserTag followUserTag) async {
    await FollowService.instance.updateFollowUserTag(followUserTag);
  }

  // 弹出底部菜单栏
  void showBottomMenu(FollowUser item) {
    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Remix.price_tag_3_line),
              title: const Text('设置标签'),
              onTap: () {
                Get.back();
                setFollowTagDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Remix.information_line),
              title: const Text('查看详情'),
              onTap: () {
                Get.back();
                AppNavigator.toFollowInfo(item);
              },
            ),
          ],
        ),
      ),
      backgroundColor: Get.theme.cardColor,
    );
  }

  void setFollowTagDialog(FollowUser follow) {
    /// 控制单选ui
    List<FollowUserTag> copiedList = [
      tagList.first,
      ...tagList.skip(3),
    ];
    Rx<FollowUserTag> checkTag = tagList.indexOf(filterMode.value) < 3
        ? copiedList.first.obs
        : filterMode.value.obs;
    final ScrollController scrollController = ScrollController();
    Get.dialog(
      AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '设置标签',
                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  tooltip: "保存",
                  icon: const Icon(
                    Icons.check,
                  ),
                  onPressed: () {
                    setFollowTag(follow, checkTag.value);
                    Get.back();
                  },
                ),
              ],
            ),
            const Divider(),
            Obx(
              () {
                int selectedIndex = copiedList.indexOf(checkTag.value);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (selectedIndex >= 0) {
                    scrollController.animateTo(
                      selectedIndex * 60.0, // 假设每项高度为 60
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                });
                return SizedBox(
                  height: 300,
                  width: 300,
                  child: RadioGroup<FollowUserTag>(
                    groupValue: checkTag.value,
                    onChanged: (value) {
                      checkTag.value = value!;
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: copiedList.length,
                      itemBuilder: (context, index) {
                        var tagItem = copiedList[index];
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey.shade300, width: 1.0),
                            ),
                          ),
                          child: RadioListTile<FollowUserTag>(
                            title: Text(tagItem.tag),
                            value: tagItem,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void onClose() {
    searchController.dispose();
    onUpdatedIndexedStream?.cancel();
    onUpdatedListStream?.cancel();
    super.onClose();
  }
}
