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
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';

class IndexedController extends GetxController {
  RxList<HomePageItem> items = RxList<HomePageItem>([]);

  var index = 0.obs;

  /// 首页各 Tab 的页面，未访问过的位置是 [SizedBox] 占位，首次切换时才实例化。
  ///
  /// 元素外面套一层 [KeepAliveWrapper]：`PageView` 是惰性视口，滚出视口的页面
  /// 会被移出 childList，不套保活就会连 Element 一起销毁、丢失滚动位置与刷新
  /// 状态；套上之后只挂在 `_keepAliveBucket` 里，**状态保留但不参与布局**。
  RxList<Widget> pages = RxList<Widget>([]);

  /// 已经实例化过页面的位置。
  ///
  /// 用显式集合而不是 `pages[i] is SizedBox` 判断「是否首次访问」——后者把占位
  /// 类型当成隐式契约，占位一换、或将来某个真实页面碰巧是 `SizedBox`，判断就
  /// 静默失效。
  ///
  /// ⚠️ 它与 [pages] 是两份需要手工同步的状态：目前只有 [onInit] 会重建 [pages]，
  /// 将来要是加了运行期重建 [pages] 的路径（比如改首页排序），必须同步
  /// `_instantiated.clear()`，否则重建后这些位置会被当成已实例化而一直空着。
  final _instantiated = <int>{};

  /// 承载 [pages] 的 [PageView] 控制器。
  ///
  /// 这里用 [PageView] 而不是 [IndexedStack]，是因为 `RenderIndexedStack`
  /// 只省绘制、不省布局——其源码注释原文：
  /// "Although only one child is displayed, the cost of the layout algorithm
  /// is still O(N), like an ordinary stack."
  /// 切过几个 Tab 之后所有页面常驻，每次改窗口尺寸都要 build + layout 全部
  /// 页面（实测固定开销约 28ms），拖动窗口就会明显变卡且不会自愈。
  /// [PageView] 走 `SliverFillViewport`，默认 `allowImplicitScrolling: false`
  /// 时缓存范围为 0 个视口，只 inflate / 布局当前页。
  ///
  /// 换轴（`PageView.scrollDirection` 随屏幕方向切）**不需要额外校正页码**：
  /// `_PagePosition.applyViewportDimension`（`page_view.dart:468-495`）会先用
  /// **旧** viewport 反算 page、再用**新** viewport 重算像素。实测 index 0/1/3
  /// 各切一轮，post-frame 读到的 `page` 都精确等于 [index]。
  final pageController = PageController();

  /// 页面切换动画：时长取 Material 3 motion 规范的 300ms（medium2），
  /// 曲线与底栏收起共用同一条 emphasized 曲线，切换节奏保持一致。
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Curve pageTransitionCurve = Curves.easeInOutCubicEmphasized;

  /// 跳切过渡：跨多个 Tab 的切换（如「首页 → 分类」）。
  ///
  /// 顺序切换靠 [PageView] 整页平移；跳切不能照搬：[PageController.animateToPage]
  /// 是逐页平移，中间那些还没实例化的位置是 `SizedBox` 占位，平移过程就是一片
  /// 空白闪过（间隔越大空白越多）。所以跳切改用 [PageController.jumpToPage]
  /// 瞬时定位，再由界面侧补一次短距离的「滑入 + 淡入」（`IndexedPage` 的
  /// `_JumpTransition`），位移量与顺序切换的视差同量级，动感保持一致。
  ///
  /// 控制器这边只负责发信号，不碰动画：每次跳切把 [jumpTick] 加一，
  /// 方向写进 [jumpDirection]。
  final jumpTick = 0.obs;

  /// 跳切方向：+1 = 目标在当前页之后（内容自右/下方滑入），-1 = 反向。
  final jumpDirection = 1.obs;

  /// 跳切过渡时长。位移只有顺序切换的十几分之一，用同样的 300ms 会显得拖沓。
  static const Duration jumpTransitionDuration = Duration(milliseconds: 220);

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
    // 过滤页面内部的水平滑动（TabBarView / TabBar 拖动）。
    // 注意：横屏时 PageView 是垂直的，它自己的滚动通知**不在**这行的过滤范围内，
    // 那一路由下面两条兜住——`animateToPage` 是程序化滚动，不发
    // UserScrollNotification，且它的 ScrollUpdateNotification.dragDetails 为 null。
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
    // 走到头之后手指还在动：值不变就别写 Rx —— 写入会唤醒两个 Obx，
    // 白白多做一轮重建（夹紧后这种情况在快速滑到底时很常见）。
    if (value == barOffset.value) {
      return;
    }
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
    if (!_instantiated.contains(i)) {
      switch (items[i].index) {
        case 0:
          Get.put(HomeController());
          pages[i] = const KeepAliveWrapper(child: HomePage());
          break;
        case 1:
          Get.put(FollowUserController());
          pages[i] = const KeepAliveWrapper(child: FollowUserPage());
          break;
        case 2:
          Get.put(CategoryController());
          pages[i] = const KeepAliveWrapper(child: CategoryPage());
          break;
        case 3:
          pages[i] = const KeepAliveWrapper(child: MinePage());
          break;
        default:
          // Constant.allHomePages 只有这 4 项，走到这里说明 items 混进了未知
          // 类型。debug 下断言，release 下断言会被剥离，所以下面还给了
          // 一个可见的占位，别让 PageView 静默显示一页空白。
          assert(false, '未知的首页类型: ${items[i].index}');
          pages[i] = const KeepAliveWrapper(
            child: Center(child: Text('未知的首页类型')),
          );
      }
      // 标记必须在赋值成功之后：万一 case 里的 Get.put / 页面构造抛异常，
      // 或命中了 default，下次点击还能再试一次，不会变成永久空白页。
      _instantiated.add(i);
    } else if (index.value == i) {
      EventBus.instance
          .emit<int>(EventBus.kBottomNavigationBarClicked, items[i].index);
    }

    index.value = i;
    // 首次调用时 PageView 尚未 attach（onInit 里的 setIndex(0)），
    // 此时 PageController 没有 clients，交给 initialPage 决定即可。
    // 切换走 animateToPage：PageView 的整页平移本身就是 Material 的 slide
    // 过渡，方向由 PageView.scrollDirection 决定（竖屏水平 / 横屏垂直）；
    // physics 仍是 NeverScrollableScrollPhysics，手势不参与，避免和页面内
    // 部的 TabBarView、列表滚动抢同一根轴。
    if (pageController.hasClients) {
      // 跨多个 Tab 时直接跳：animateToPage 会逐页平移，中间那些还没实例化
      // 的占位页（SizedBox）会以空白形式闪过。动静由界面侧的跳切过渡补上，
      // 见 [jumpTick] 的说明。
      final current = pageController.page?.round() ?? i;
      if ((current - i).abs() > 1) {
        // 先写方向再发 tick：监听方读到的方向一定是本次跳切的
        jumpDirection.value = i > current ? 1 : -1;
        pageController.jumpToPage(i);
        jumpTick.value++;
      } else {
        pageController.animateToPage(
          i,
          duration: pageTransitionDuration,
          curve: pageTransitionCurve,
        );
      }
    }
  }

  @override
  void onInit() {
    Future.delayed(Duration.zero, showFirstRun);
    items.value = AppSettingsController.instance.homeSort
        .map((key) => Constant.allHomePages[key]!)
        .toList();
    // 占位数量跟随 items：PageView 的子项数必须与导航项一一对应，
    // 否则 jumpToPage 会越界
    pages.value = List<Widget>.generate(items.length, (_) => const SizedBox());
    // 收起相关设置变化时恢复展开状态
    ever(AppSettingsController.instance.hideTopBar, (_) => resetBars());
    ever(AppSettingsController.instance.hideBottomBar, (_) => resetBars());
    ever(AppSettingsController.instance.barHideType, (_) => resetBars());
    setIndex(0);
    super.onInit();
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
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
