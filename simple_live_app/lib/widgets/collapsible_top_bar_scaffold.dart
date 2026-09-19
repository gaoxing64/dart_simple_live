import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/widgets/collapse_slot.dart';

/// 顶栏可收起的 [Scaffold]。
///
/// 「滑动收起顶栏」原本只在首页（[HomePage]）实现：当
/// [AppSettingsController.hideTopBar] 关闭时退化为普通 [Scaffold]；开启时按
/// [AppSettingsController.barHideType] 走「即时」（动画收起）或「同步」（跟随
/// 手指拖动距离）两种收起。底栏收起在 [IndexedPage] 顶层统一处理，所有 Tab
/// 都生效；但顶栏收起需要在每个 Tab 自己的 build 里实现，关注页 / 分类页
/// 之前直接用 `Scaffold(appBar: ...)`，顶栏固定，滑动时只有底栏收起。
///
/// 这里把 [HomePage] 已验证过的逻辑抽出来，让 [HomePage] / [FollowUserPage]
/// / [CategoryPage] 共用一份，避免散落各处的副本。
///
/// [appBar] 由调用方提供，**不要显式传 `primary: false`**：本组件在收起模式
/// 下会包一层 [MediaQuery.removePadding]，让 [AppBar] 看不到顶部 padding，
/// 等价于 `primary: false`，再由外层 [SizedBox] 单独保留状态栏高度——这与
/// [HomePage] 原来的写法行为一致。
class CollapsibleTopBarScaffold extends StatelessWidget {
  const CollapsibleTopBarScaffold({
    super.key,
    required this.appBar,
    required this.body,
  });

  /// 顶栏。普通模式下作为 [Scaffold.appBar] 直接使用（默认 `primary: true`，
  /// [AppBar] 自带状态栏 padding）；收起模式下被 [MediaQuery.removePadding]
  /// 包裹，等价于 `primary: false`。
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
        // 即时：跟随滑动方向动画收起/展开
        var show = indexed.showTopBar.value;
        return _CollapsibleBody(
          topBar: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: show ? 1 : 0,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: show ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubicEmphasized,
              builder: (_, factor, child) => CollapseSlot(
                factor: factor,
                alignment: Alignment.bottomCenter,
                child: child!,
              ),
              child: _StripPrimary(appBar),
            ),
          ),
          body: body,
        );
      }
      // 同步：跟随手指拖动距离收起/展开
      return _CollapsibleBody(
        topBar: Obx(
          () => CollapseSlot(
            factor: 1 -
                indexed.barOffset.value / IndexedController.maxBarOffset,
            alignment: Alignment.bottomCenter,
            child: _StripPrimary(appBar),
          ),
        ),
        body: body,
      );
    });
  }
}

/// 收起模式的容器：状态栏留白 + 可收起顶栏 + 内容。
///
/// 状态栏高度用 [SizedBox] 显式保留，避免收起后内容顶进状态栏。
class _CollapsibleBody extends StatelessWidget {
  const _CollapsibleBody({required this.topBar, required this.body});

  final Widget topBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          topBar,
          Expanded(child: body),
        ],
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
