import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';

class AppSearchController extends GetxController
    with GetSingleTickerProviderStateMixin {
  /// 打开搜索页时默认选中的平台 id。
  ///
  /// 由首页把「当前正在看的平台」带过来（见 `HomeController.toSearch`），这样在
  /// 虎牙看直播时点搜索，搜索页也停在虎牙，而不是每次都弹回列表第一个。
  /// 直接访问 `/search`（没带参数）、或平台已被移除时为 null，回落到第一个。
  final String? initialSiteId;

  /// 当前选中的平台在 [Sites.supportSites] 里的下标。
  ///
  /// 首页与搜索页的 tab 都取自同一个 [Sites.supportSites]，顺序一致，下标可以直接
  /// 对应；但传参用的是 **id 而不是下标**——下标会随「网站排序」设置变化，id 不会。
  int index = 0;

  late TabController tabController;

  var searchMode = 0.obs;

  AppSearchController({this.initialSiteId}) {
    // 必须把 index 一起对齐：TabController 带 initialIndex 时不会走切换动画，
    // 下面那个 animation 监听器也就不会触发，index 会停在 0。而 index 是
    // doSearch() 决定「搜哪个平台」的依据，不同步的话界面停在虎牙、
    // 搜索却打到哔哩哔哩。
    index = _resolveInitialIndex(initialSiteId);
    tabController = TabController(
      length: Sites.supportSites.length,
      initialIndex: index,
      vsync: this,
    );
    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (index == currentIndex) {
        return;
      }

      index = currentIndex;
      // if (Sites.supportSites[index].id == Constant.kDouyin) {
      //   return;
      // }

      var controller =
          Get.find<SearchListController>(tag: Sites.supportSites[index].id);

      if (controller.list.isEmpty &&
          !controller.pageEmpty.value &&
          controller.keyword.isNotEmpty) {
        controller.refreshData();
      }
    });
  }

  /// 把平台 id 解析成 [Sites.supportSites] 的下标；找不到（含没传）时用第一个。
  static int _resolveInitialIndex(String? siteId) {
    if (siteId == null) {
      return 0;
    }
    final found = Sites.supportSites.indexWhere((e) => e.id == siteId);
    return found >= 0 ? found : 0;
  }

  StreamSubscription<dynamic>? streamSubscription;

  TextEditingController searchController = TextEditingController();

  @override
  void onInit() {
    for (var site in Sites.supportSites) {
      // if (site.id == Constant.kDouyin) {
      //   Get.put(DouyinSearchController(site));
      // } else {
      Get.put(
        SearchListController(site),
        tag: site.id,
      );
      //}
    }

    super.onInit();
  }

  void doSearch() {
    if (searchController.text.isEmpty) {
      return;
    }
    for (var site in Sites.supportSites) {
      // if (site.id == Constant.kDouyin) {
      //   var controller = Get.find<DouyinSearchController>();
      //   controller.keyword = searchController.text;
      //   controller.searchMode.value = searchMode.value;
      //   controller.reloadWebView();
      // } else {
      var controller = Get.find<SearchListController>(tag: site.id);
      controller.clear();
      controller.keyword = searchController.text;
      controller.searchMode.value = searchMode.value;
      //}
    }
    // if (Sites.supportSites[index].id != Constant.kDouyin) {
    var controller =
        Get.find<SearchListController>(tag: Sites.supportSites[index].id);
    controller.refreshData();
    //}
  }

  @override
  void onClose() {
    streamSubscription?.cancel();
    super.onClose();
  }
}
