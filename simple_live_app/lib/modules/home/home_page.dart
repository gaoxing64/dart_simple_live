import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_view.dart';
import 'package:simple_live_app/widgets/collapsible_top_bar_scaffold.dart';

class HomePage extends GetView<HomeController> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CollapsibleTopBarScaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      // 不要传 primary: false —— 收起模式下 CollapsibleTopBarScaffold 会
      // 用 MediaQuery.removePadding 包成等价于 primary: false 的形态。
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
          tooltip: "搜索",
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
