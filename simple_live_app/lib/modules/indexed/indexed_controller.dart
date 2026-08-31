import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';
import 'package:simple_live_app/modules/category/category_page.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_page.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/modules/mine/mine_page.dart';

class IndexedController extends GetxController {
  RxList<HomePageItem> items = RxList<HomePageItem>([]);

  var index = 0.obs;
  RxList<Widget> pages = RxList<Widget>([
    const SizedBox(),
    const SizedBox(),
    const SizedBox(),
    const SizedBox(),
  ]);

  /// 顶/底栏收起：同步模式的累计偏移（0=展开，[maxBarOffset]=收起）
  final barOffset = 0.0.obs;

  /// 顶/底栏收起：即时模式的顶/底栏显隐
  final showTopBar = true.obs;
  final showBottomBar = true.obs;

  /// 顶栏收起行程（AppBar 工具栏高度）
  static const double maxBarOffset = 56;

  /// 首页列表滚动通知，驱动顶/底栏收起（即时/同步）
  bool onScrollNotification(ScrollNotification notification) {
    var settings = AppSettingsController.instance;
    if (!settings.hideTopBar.value && !settings.hideBottomBar.value) {
      return false;
    }
    // 过滤水平滑动（TabBarView / TabBar 拖动）
    if (notification.metrics.axis == Axis.horizontal) {
      return false;
    }
    if (settings.barHideType.value == 0) {
      // 即时：跟随滑动方向翻转显隐
      if (notification is UserScrollNotification) {
        switch (notification.direction) {
          case ScrollDirection.forward:
            showTopBar.value = true;
            showBottomBar.value = true;
          case ScrollDirection.reverse:
            showTopBar.value = false;
            showBottomBar.value = false;
          default:
            break;
        }
      }
      return false;
    }
    // 同步：跟随手指拖动距离，惯性滚动不驱动
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) {
        return false;
      }
      var pixels = notification.metrics.pixels;
      var delta = notification.scrollDelta ?? 0;
      if (pixels < 0 && delta > 0) {
        // 顶部 overscroll，保持与列表位置一致
        return false;
      }
      _updateBarOffset(delta);
    } else if (notification is OverscrollNotification) {
      _updateBarOffset(notification.overscroll);
    }
    return false;
  }

  void _updateBarOffset(double delta) {
    var value = barOffset.value + delta;
    if (value < 0) value = 0;
    if (value > maxBarOffset) value = maxBarOffset;
    barOffset.value = value;
  }

  /// 恢复顶/底栏展开状态
  void resetBars() {
    barOffset.value = 0;
    showTopBar.value = true;
    showBottomBar.value = true;
  }

  void setIndex(int i) {
    resetBars();
    if (pages[i] is SizedBox) {
      switch (items[i].index) {
        case 0:
          Get.put(HomeController());
          pages[i] = const HomePage();
          break;
        case 1:
          Get.put(FollowUserController());
          pages[i] = const FollowUserPage();
          break;
        case 2:
          Get.put(CategoryController());
          pages[i] = const CategoryPage();
          break;
        case 3:
          pages[i] = const MinePage();
          break;
        default:
      }
    } else {
      if (index.value == i) {
        EventBus.instance
            .emit<int>(EventBus.kBottomNavigationBarClicked, items[i].index);
      }
    }

    index.value = i;
  }

  @override
  void onInit() {
    Future.delayed(Duration.zero, showFirstRun);
    items.value = AppSettingsController.instance.homeSort
        .map((key) => Constant.allHomePages[key]!)
        .toList();
    // 收起相关设置变化时恢复展开状态
    ever(AppSettingsController.instance.hideTopBar, (_) => resetBars());
    ever(AppSettingsController.instance.hideBottomBar, (_) => resetBars());
    ever(AppSettingsController.instance.barHideType, (_) => resetBars());
    setIndex(0);
    super.onInit();
  }

  void showFirstRun() async {
    var settingsController = Get.find<AppSettingsController>();
    if (settingsController.firstRun) {
      settingsController.setNoFirstRun();
      await Utils.showStatement();
      Utils.checkUpdate();
    }
  }
}
