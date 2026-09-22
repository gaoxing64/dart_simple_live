import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// 应用级滚动行为：让桌面端也能用鼠标左键直接拖动滚动内容。
///
/// Flutter 默认的 [ScrollBehavior.dragDevices] 只包含「触摸类」设备
/// （touch / stylus / invertedStylus / trackpad / unknown），**鼠标被排除在外**，
/// 因此在 Windows / macOS / Linux 上按住鼠标左键拖动不会滚动 [Scrollable]，
/// 只能靠滚轮或滚动条。移动端没有这条限制，于是同一个页面在两端手感不一致：
/// 手机上能左右滑动切换平台标签、上下拖动列表，桌面上却只能点标签、拖滚动条。
///
/// 注意范围（别把它当成「全局都拖不动」的根据）：easy_refresh 会把自己的子树
/// 再包一层 `ERScrollBehavior`，那个 behavior 本来就把 dragDevices 放开为全部
/// 指针设备，所以 [PageGridView] / [PageListView] 这类被 EasyRefresh 包住的列表
/// 在引入本类之前就已经能用鼠标拖。本类真正补齐的是：
/// - TabBarView / PageView（平台标签左右切页）——它们不在 EasyRefresh 里；
/// - 其它未被 EasyRefresh 包住的滚动区，例如直播间的聊天列表。
///
/// 顺带保证两端一致：
/// - 上下拖动：列表跟随鼠标滚动（与 easy_refresh 内部 ERScrollBehavior 的行为对齐）；
/// - 左右拖动：TabBarView / PageView 跟随鼠标切换平台。
///
/// 放开范围仅限 [Scrollable] 自身的拖动识别器，不受影响的有：
/// - 使用自带手势的控件（ReorderableListView 的拖拽排序、Slider、播放器手势区等）
///   不依赖 [dragDevices]；
/// - 声明了 `NeverScrollableScrollPhysics` 的列表本就不可拖动，不会被放开。
///
/// 已知取舍：鼠标进入 dragDevices 后，可滚动区域内的 `SelectableText` 拖选会与
/// 列表的拖动识别器同场竞争（Flutter 默认把鼠标排除在外，正是为了保住纯鼠标
/// 拖选）。移动端不受影响。若后续在桌面端确认「聊天区拖选文字」被抢，需要把
/// 放开范围收窄到横向翻页场景，而不是继续全局放开。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// 全部指针设备。用集合缓存，避免每次 `get dragDevices` 都重新分配。
  ///
  /// 取不可变视图：这是进程级共享实例，而 `dragDevices` 的契约是「只读」，
  /// 万一有调用方对它 add / remove，污染的是所有 [Scrollable]。
  static final Set<PointerDeviceKind> _allDragDevices =
      Set.unmodifiable(PointerDeviceKind.values);

  @override
  Set<PointerDeviceKind> get dragDevices => _allDragDevices;
}

/// 让**滚轮**滚动也带过渡动画的 [ScrollController]。
///
/// Flutter 默认的滚轮是**瞬时跳转**：`ScrollPositionWithSingleContext.pointerScroll`
/// 直接 `forcePixels` 到目标位置，一帧到位，观感是「一格一格地跳」；
/// 而按住鼠标左键拖动走的是真实手势 + 惯性，是平滑的 —— 同一个列表两种手感。
///
/// 官方给的钩子就在这里：`Scrollable` 的 position 由
/// `ScrollController.createScrollPosition` 创建（见 `ScrollableState._updatePosition`
/// 的注释），所以换掉 position 就能换掉滚轮行为。**不要去 `Listener.onPointerSignal`
/// 里抢事件** —— 滚轮走 `GestureBinding.pointerSignalResolver`，只认最先注册的那个，
/// 而事件派发是「从叶子往根」，外层的 Listener 抢不过 Scrollable 内部的。
///
/// 作用范围：凡是把 `BasePageController.scrollController` 交给列表的页面
/// （`PageGridView` / `PageListView`：首页 / 分类 / 搜索 / 关注）都会生效。
class SmoothWheelScrollController extends ScrollController {
  SmoothWheelScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothWheelScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      // 父类的实现会把这两个参数透传给 position，这里之前漏掉了，
      // 导致 initialScrollOffset 被静默忽略、keepScrollOffset=false 也不生效。
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
    );
  }
}

/// 把滚轮的「瞬时跳」改成「动画滚」。
///
/// 公开给 [IndexedController]：同步模式的顶/底栏收起靠
/// `ScrollUpdateNotification.dragDetails != null` 区分「手指拖动」与
/// 「惯性滚动」，但滚轮走 `animateTo`，通知的 dragDetails 同样是 null，
/// 会被一并过滤掉（桌面端滚轮滚到底顶栏也不收起，底部一行永远被裁掉
/// 一个 toolbar 高度）。滚轮驱动的动画期间 [isWheelAnimating] 为真，
/// 用它把滚轮从「惯性」里豁免出来。
class SmoothWheelScrollPosition extends ScrollPositionWithSingleContext {
  SmoothWheelScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
  });

  /// 连续滚动时累加的目标位置。
  ///
  /// 不能每一格都从 `pixels` 起算：动画还在跑时又来一格，起点已经变了，
  /// 逐格相加会「吃掉」上一格的距离，快速滚动会越滚越慢。这里记住一个目标值，
  /// 每格都往它上面加。
  double? _wheelTarget;

  /// 全局「正在被鼠标滚轮驱动」的滚动区数量（>0 即有滚轮动画在跑）。
  ///
  /// 同步模式的顶/底栏收起靠 `ScrollUpdateNotification.dragDetails != null`
  /// 区分「手指拖动」与「惯性滚动」，但滚轮走 `animateTo`，通知里同样没有
  /// dragDetails，会被一并过滤掉 —— 桌面端滚轮滚到底顶栏也不收起，底部一行
  /// 永远被裁掉一个 toolbar 高度。滚轮无法从通知里认出来（`notification.context`
  /// 指向的是内部 RawGestureDetector，`notification.metrics` 又是 position 的
  /// 快照拷贝），所以在这里记一个全局计数：只有滚轮会走 [pointerScroll]，
  /// 移动端触摸惯性不会，用它把滚轮从「惯性」里豁免出来正合适。
  static int _wheelAnimatingCount = 0;
  static bool get isWheelAnimating => _wheelAnimatingCount > 0;

  /// 一格滚轮的过渡时长。太短看着还是跳，太长会有「拖泥带水」的滞后感。
  static const Duration _duration = Duration(milliseconds: 180);

  @override
  void pointerScroll(double delta) {
    // delta == 0 是「取消滚动惯性」的信号（PointerScrollInertiaCancelEvent），
    // 必须原样交给父类去 goBallistic 停住。
    if (delta == 0) {
      _wheelTarget = null;
      super.pointerScroll(delta);
      return;
    }

    final double base = _wheelTarget ?? pixels;
    final double target = clampDouble(
      base + delta,
      minScrollExtent,
      maxScrollExtent,
    );
    if (target == pixels) {
      return;
    }
    _wheelTarget = target;
    // 和默认实现保持一致：先更新滚动方向，靠它判断方向的监听者（EasyRefresh 等）
    // 才拿得到正确值。
    updateUserScrollDirection(
      -delta > 0.0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    _wheelAnimatingCount++;
    animateTo(target, duration: _duration, curve: Curves.easeOutCubic)
        .whenComplete(() {
      _wheelAnimatingCount--;
      // 动画结束且期间没有新目标就清掉，免得下次从一个过期的目标起算。
      if (_wheelTarget == target) {
        _wheelTarget = null;
      }
    });
  }
}
