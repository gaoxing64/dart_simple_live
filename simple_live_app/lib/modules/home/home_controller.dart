import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';

/// 首页 tab 下标对应的平台 id；下标越界时返回 null。
///
/// 抽成顶层纯函数是为了能直接单测——它是「首页把当前平台带给搜索页」这条链路上
/// 唯一的映射点，写错了表现就是搜索页停在了别的平台。
String? siteIdAtHomeTab(int tabIndex) {
  final sites = Sites.supportSites;
  if (tabIndex < 0 || tabIndex >= sites.length) {
    return null;
  }
  return sites[tabIndex].id;
}

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;
  HomeController() {
    tabController =
        TabController(length: Sites.supportSites.length, vsync: this);
  }

  StreamSubscription<dynamic>? streamSubscription;

  @override
  void onInit() {
    streamSubscription = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 0) {
          refreshOrScrollTop();
        }
      },
    );
    for (var site in Sites.supportSites) {
      Get.put(HomeListController(site), tag: site.id);
    }

    super.onInit();
  }

  void refreshOrScrollTop() {
    var tabIndex = tabController.index;
    // 复用 siteIdAtHomeTab：它是这条链路上唯一的映射点，这里再手写一份
    // 不但与文档描述不符，还少了对越界的保护。
    final siteId = siteIdAtHomeTab(tabIndex);
    if (siteId == null) {
      return;
    }
    BasePageController controller;
    controller = Get.find<HomeListController>(tag: siteId);
    controller.scrollToTopOrRefresh();
  }

  void toSearch() {
    // 把首页当前正在看的平台带给搜索页，否则搜索页每次都从列表第一个开始。
    // 传 id 而不是下标：下标会随「网站排序」设置变化，id 不会。
    Get.toNamed(
      RoutePath.kSearch,
      arguments: siteIdAtHomeTab(tabController.index),
    );
  }

  @override
  void onClose() {
    streamSubscription?.cancel();
    super.onClose();
  }
}
