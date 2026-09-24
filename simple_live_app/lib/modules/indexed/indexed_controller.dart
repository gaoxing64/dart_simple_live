import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
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
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';

class IndexedController extends GetxController
    with GetSingleTickerProviderStateMixin {
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
    // 同步：跟随手指拖动距离，惯性滚动不驱动。
    // 例外：桌面端鼠标滚轮走的是 animateTo，通知里同样没有 dragDetails，
    // 但它是指令式滚动而不是惯性 —— 不驱动的话顶栏永远不收起，
    // 列表底部一个 toolbar 高度会被内容槽位的溢出裁掉（滚到底少一行）。
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null &&
          !SmoothWheelScrollPosition.isWheelAnimating) {
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

  /// 兜底滚轮动画的累加目标与起点（同步模式用）。
  ///
  /// 累加目标而不是每格从 `barOffset.value` 起算：连续几格滚轮时动画还在跑、
  /// 当前值已经变了，逐格相加会「吃掉」上一格的距离 —— 与
  /// `SmoothWheelScrollPosition._wheelTarget` 同一套思路。
  double? _wheelBarTarget;
  double _wheelBarFrom = 0;

  /// 本动画上一帧推进到的位置。
  ///
  /// 每帧只把**增量**交给 [`_updateBarOffset`]：贴边那一格「没被列表吃掉」的
  /// 部分走这条兜底，而「被吃掉」的部分仍由滚动通知按增量写 `barOffset` ——
  /// 这里按绝对值覆盖的话会把通知那边累加出来的位移擦掉（实测少走一截）。
  double _wheelBarWritten = 0;

  /// 兜底滚轮的过渡动画（同步模式）。
  ///
  /// 时长与曲线跟滚轮滚列表那套一致，两种情形手感才相同：
  /// 「列表在滚、栏位跟着走」与「列表滚不动、栏位自己走」。
  late final AnimationController _wheelBarAnim = AnimationController(
    vsync: this,
    duration: SmoothWheelScrollPosition.wheelStepDuration,
  )
    ..addListener(_onWheelBarTick)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 跑完就清掉累加目标，免得下次从一个过期的目标起算（拖动期间
        // barOffset 会变，不清就会从旧目标接着算）。
        _wheelBarTarget = null;
      }
    });

  void _onWheelBarTick() {
    final target = _wheelBarTarget;
    if (target == null) {
      return;
    }
    final progress = Curves.easeOutCubic.transform(_wheelBarAnim.value);
    final next = _wheelBarFrom + (target - _wheelBarFrom) * progress;
    final delta = next - _wheelBarWritten;
    _wheelBarWritten = next;
    _updateBarOffset(delta);
  }

  /// 列表滚不动时（贴边 / 内容不足一屏）没被消费掉的滚轮增量。
  ///
  /// 两个来源：`indexed_page.dart` 的 `_WheelBarFallback`（`Scrollable` 直接
  /// 弃权、连 `pointerScroll` 都不调用那种），以及
  /// `SmoothWheelScrollPosition` 里贴边那格被 clamp 掉的余量。两条路都不会派发
  /// 滚动通知，栏位收不到驱动 —— 表现为「页面留白 / 分组全折叠后，滚轮拉不出
  /// 被隐藏的顶栏」。开关与模式判断照走，不会绕过用户的设置。
  void onWheelUnconsumed(double delta) {
    var settings = AppSettingsController.instance;
    if (!settings.hideTopBar.value && !settings.hideBottomBar.value) {
      return;
    }
    // 静态回调是全局的：压在首页壳之上的整屏路由（搜索 / 分类详情 / 历史）里
    // 也用的是 SmoothWheel 列表，滚到贴边同样会回调到这里 —— 那会把**看不见的**
    // 栏位收起来，返回首页时停在那儿。`_WheelBarFallback` 靠命中测试天然只在壳
    // 可见时生效，两条路的作用域要一致。
    if (Get.currentRoute != RoutePath.kIndex) {
      return;
    }
    if (settings.barHideType.value == 0) {
      // 即时模式只认方向：向上滚（内容下移）展开、向下滚收起。列表能滚时这一步
      // 由 `pointerScroll` 的 updateUserScrollDirection 发 UserScrollNotification
      // 完成；滚不动时那条通知不会来，这里补上。显隐自己的过渡动画在
      // `CollapsibleTopBarScaffold` 里（TweenAnimationBuilder），这里不用管。
      final show = delta < 0;
      showTopBar.value = show;
      showBottomBar.value = show;
      return;
    }
    // 同步模式按距离走，并且必须自己补过渡 —— 列表能滚时栏位是搭着滚轮那 180ms
    // 的滚动动画逐帧走的，直接写值会「一帧跳过去」。
    final base = _wheelBarTarget ?? barOffset.value;
    var target = base + delta;
    if (target < 0) target = 0;
    if (target > maxBarOffset) target = maxBarOffset;
    _wheelBarTarget = target;
    if (barOffset.value == target) {
      // 已经到位（栏位早就夹紧了）：不必再起一次动画。
      return;
    }
    _wheelBarFrom = barOffset.value;
    _wheelBarWritten = barOffset.value;
    _wheelBarAnim.forward(from: 0);
  }

  /// 恢复顶/底栏展开状态
  void resetBars() {
    // 兜底动画（`_wheelBarAnim`）是唯一会异步写 barOffset 的写入者：不先停掉，
    // 下一帧它就把复位覆盖回去，切 Tab / 改设置时的复位会静默失效。
    _wheelBarAnim.stop();
    _wheelBarTarget = null;
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
    // 滚轮贴边处没吃干净的余量也走同一条路径（`SmoothWheelScrollPosition` 里
    // 被 clamp 掉的那部分）。注销在 onClose 里做。
    SmoothWheelScrollPosition.onWheelUnconsumed = onWheelUnconsumed;
    setIndex(0);
    super.onInit();
  }

  @override
  void onClose() {
    pageController.dispose();
    // 静态入口持有的是本实例的 bound method：不清会留悬空引用（实例无法回收），
    // 销毁后再触发滚轮还会对已 dispose 的 AnimationController 调 forward()。
    // 只在仍指向本实例时才清，免得页面重建时把新实例刚挂上的回调抹掉。
    if (SmoothWheelScrollPosition.onWheelUnconsumed == onWheelUnconsumed) {
      SmoothWheelScrollPosition.onWheelUnconsumed = null;
    }
    _wheelBarAnim.dispose();
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
