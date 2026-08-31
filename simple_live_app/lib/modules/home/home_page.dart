import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_view.dart';
import 'package:simple_live_app/widgets/collapse_slot.dart';

class HomePage extends GetView<HomeController> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var settings = AppSettingsController.instance;
      if (!settings.hideTopBar.value) {
        return _buildNormal(context);
      }
      var indexed = Get.find<IndexedController>();
      if (settings.barHideType.value == 0) {
        // 即时：跟随滑动方向动画收起/展开
        var show = indexed.showTopBar.value;
        return _buildCollapsible(
          context,
          AnimatedOpacity(
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
              child: _buildAppBar(primary: false),
            ),
          ),
        );
      }
      // 同步：跟随手指拖动距离收起/展开
      return _buildCollapsible(
        context,
        Obx(
          () => CollapseSlot(
            factor:
                1 - indexed.barOffset.value / IndexedController.maxBarOffset,
            alignment: Alignment.bottomCenter,
            child: _buildAppBar(primary: false),
          ),
        ),
      );
    });
  }

  /// 原始结构（顶栏收起关闭时）
  Widget _buildNormal(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  /// 收起结构：状态栏空条 + 可收起顶栏 + 内容
  Widget _buildCollapsible(BuildContext context, Widget topBar) {
    return Scaffold(
      body: Column(
        children: [
          // 保留状态栏高度，收起后内容不会顶进状态栏
          SizedBox(height: MediaQuery.paddingOf(context).top),
          topBar,
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar({bool primary = true}) {
    return AppBar(
      primary: primary,
      toolbarHeight: 56,
      titleSpacing: 8,
      title: TabBar(
        controller: controller.tabController,
        labelPadding: AppStyle.edgeInsetsH20,
        isScrollable: true,
        indicatorSize: TabBarIndicatorSize.label,
        tabAlignment: TabAlignment.center,
        tabs: Sites.supportSites
            .map(
              (e) => Tab(
                //text: e.name,

                child: Row(
                  children: [
                    Image.asset(
                      e.logo,
                      width: 24,
                    ),
                    AppStyle.hGap8,
                    Text(e.name),
                  ],
                ),
              ),
            )
            .toList(),
      ),
      actions: [
        IconButton(
          onPressed: controller.toSearch,
          icon: const Icon(Icons.search),
        )
      ],
    );
  }

  Widget _buildBody() {
    return TabBarView(
      controller: controller.tabController,
      children: Sites.supportSites
          .map(
            (e) => HomeListView(
              e.id,
            ),
          )
          .toList(),
    );
  }
}
