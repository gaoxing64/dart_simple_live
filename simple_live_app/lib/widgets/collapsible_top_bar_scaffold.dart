import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/widgets/bar_collapse.dart';

/// 顶栏可收起的 [Scaffold]。
///
/// 「滑动收起顶栏」原本只在首页（[HomePage]）实现：当
/// [AppSettingsController.hideTopBar] 关闭时退化为普通 [Scaffold]；开启时按
/// [AppSettingsController.barHideType] 走「即时」（动画收起）或「同步」（跟随
/// 手指拖动距离）两种收起。底栏收起在 [IndexedPage] 顶层统一处理，所有 Tab
/// 都生效；顶栏收起需要在每个 Tab 自己的 build 里实现，关注页 / 分类页
/// 之前直接用 `Scaffold(appBar: ...)`，顶栏固定，滑动时只有底栏收起。
///
/// 这里把 [HomePage] 已验证过的逻辑抽出来，让 [HomePage] / [FollowUserPage]
/// / [CategoryPage] 共用一份，避免散落各处的副本。
///
/// ## 收起过程为什么必须「纯绘制」
///
/// 旧实现用 `Align(heightFactor:)` 真实压缩顶栏高度，父级 `Column` 的
/// `Expanded` 随之变高 —— 也就是**每一帧都改布局**：页面（搜索框 / 标签 / 网格）
/// 重排、列表视口尺寸变化、顶栏内部 `Material` 的高度与阴影跟着重算。
/// 同步模式下手指每移动一点就要走一遍，安卓上表现为明显掉帧。
///
/// 现在收起不参与布局：
/// * 顶栏放在一个**高度恒定**的 `Positioned` 槽位里，靠 [BarCollapse] 上下平移；
/// * 内容区（[body]）的槽位尺寸同样恒定（比可见区高一个顶栏高度，底部溢出被裁掉），
///   靠 `Transform.translate` 整体上移 —— 「顶栏让出多少空间、内容就上移多少」的
///   视觉效果与旧实现一致，但**不触发任何重排**，每帧只是一次矩阵更新。
///
/// 顶栏高度取 [PreferredSizeWidget.preferredSize]，所以调用方**不要显式传**
/// `primary: false`：收起模式下本组件会用 [MediaQuery.removePadding] 去掉
/// [AppBar] 自己读到的顶部 padding（等价于 `primary: false`），状态栏高度由
/// 外层槽位单独保留 —— 这与 [HomePage] 原来的写法行为一致。
class CollapsibleTopBarScaffold extends StatelessWidget {
  const CollapsibleTopBarScaffold({
    super.key,
    required this.appBar,
    required this.body,
  });

  /// 顶栏。普通模式下作为 [Scaffold.appBar] 直接使用（默认 `primary: true`，
  /// [AppBar] 自带状态栏 padding）；收起模式下被 [MediaQuery.removePadding]
  /// 包裹，等价于 `primary: false`。
  ///
  /// 高度必须等于 [IndexedController.maxBarOffset]（默认 56，即 Material 的
  /// 默认 toolbar 高度）：同步模式用它把 `barOffset` 换算成收起比例。
  final PreferredSizeWidget appBar;

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var settings = AppSettingsController.instance;
      if (!settings.hideTopBar.value) {
        return Scaffold(appBar: appBar, body: body);
      }
      var indexed = Get.find<IndexedController>();
      if (settings.barHideType.value == 0) {
        // 即时：方向一变就动画收起/展开
        return TweenAnimationBuilder<double>(
          tween: Tween(end: indexed.showTopBar.value ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubicEmphasized,
          builder: (_, factor, __) => _CollapsibleLayout(
            factor: factor,
            appBar: appBar,
            body: body,
            barOpacity: indexed.showTopBar.value ? 1.0 : 0.0,
          ),
        );
      }
      // 同步：跟随手指拖动距离。Obx 只包住两个图层 —— Scaffold 本身不参与
      // 每帧重建（`appBar` / `body` 实例由调用方传入，子树因此可以复用）。
      return Obx(
        () => _CollapsibleLayout(
          factor:
              1 - indexed.barOffset.value / IndexedController.maxBarOffset,
          appBar: appBar,
          body: body,
        ),
      );
    });
  }
}

/// 收起模式下的两个图层：定高的顶栏槽位 + 定高的内容槽位，都只做绘制位移。
///
/// 两者的布局尺寸都是常量，所以 [factor] 变化不会引起任何重排。
class _CollapsibleLayout extends StatelessWidget {
  const _CollapsibleLayout({
    required this.factor,
    required this.appBar,
    required this.body,
    this.barOpacity,
  });

  /// `1` = 完全展开，`0` = 完全收起。
  final double factor;

  final PreferredSizeWidget appBar;
  final Widget body;

  /// 即时模式下的顶栏透明度（`null` 表示不透明，同步模式用）。
  final double? barOpacity;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final barHeight = appBar.preferredSize.height;
    assert(
      barHeight == IndexedController.maxBarOffset,
      '顶栏高度($barHeight)必须等于 IndexedController.maxBarOffset'
      '(${IndexedController.maxBarOffset})，否则同步模式的收起比例算不准',
    );

    // 内容区：左上角固定在「状态栏 + 顶栏」下方，高度比可见区多一个顶栏高度，
    // 多出来的部分滑到屏幕外被裁掉 —— 这样顶栏完全收起时内容正好铺到屏幕底部，
    // 不会在底部露出空白。
    final content = Positioned(
      left: 0,
      right: 0,
      top: statusBarHeight + barHeight,
      bottom: -barHeight,
      child: Transform.translate(
        offset: Offset(0, -(1 - factor) * barHeight),
        child: body,
      ),
    );

    // 顶栏：定高槽位 + 平移，滑出的部分被 [BarCollapse] 裁掉。
    Widget bar = _StripPrimary(appBar);
    if (barOpacity != null) {
      bar = AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: barOpacity!,
        child: bar,
      );
    }
    final topBar = Positioned(
      left: 0,
      right: 0,
      top: statusBarHeight,
      height: barHeight,
      child: BarCollapse(
        factor: factor,
        fromTop: true,
        child: bar,
      ),
    );

    return Scaffold(
      body: Stack(
        // 内容区底部溢出的一个顶栏高度在这里裁掉（裁剪矩形是 Stack 自身尺寸，
        // 与 factor 无关，因此不会随收起变化而废弃光栅缓存）。
        clipBehavior: Clip.hardEdge,
        children: [content, topBar],
      ),
    );
  }
}

/// 把 [AppBar] 包成「不加状态栏 padding」的等价形态。
///
/// [AppBar] 的 `primary` 参数决定是否在顶部加状态栏高度的 padding。原来的
/// [HomePage] 在收起模式下显式传 `primary: false`，但那样要求调用方准备两份
/// AppBar；这里改用 [MediaQuery.removePadding] 让 AppBar 自己读不到顶部
/// padding，效果与 `primary: false` 一致。普通模式仍走 [Scaffold.appBar]
/// 槽位，[AppBar] 默认 `primary: true`，状态栏 padding 由它自己处理。
class _StripPrimary extends StatelessWidget {
  const _StripPrimary(this.appBar);

  final PreferredSizeWidget appBar;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: appBar,
    );
  }
}
