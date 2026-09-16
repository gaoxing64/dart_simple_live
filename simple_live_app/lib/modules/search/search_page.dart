import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';

class SearchPage extends GetView<AppSearchController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: controller.searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "搜点什么吧",
            border: OutlineInputBorder(
              borderRadius: AppStyle.radius24,
            ),
            contentPadding: AppStyle.edgeInsetsH12,
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "返回",
                  onPressed: Get.back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Obx(
                  () => DropdownButton<int>(
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text("房间"),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text("主播"),
                      ),
                    ],
                    value: controller.searchMode.value,
                    onChanged: (e) {
                      controller.searchMode.value = e ?? 0;
                      controller.doSearch();
                    },
                  ),
                ),
                AppStyle.hGap8,
              ],
            ),
            suffixIcon: IconButton(
              tooltip: "搜索",
              onPressed: controller.doSearch,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (e) {
            controller.doSearch();
          },
        ),
        bottom: TabBar(
          controller: controller.tabController,
          padding: EdgeInsets.zero,
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
          labelPadding: AppStyle.edgeInsetsH20,
          isScrollable: true,
          indicatorSize: TabBarIndicatorSize.label,
        ),
      ),
      body: TabBarView(
        // 允许左右滑动切换平台，与首页 / 分类页保持一致。
        // 这里曾经是 NeverScrollableScrollPhysics：当时抖音搜索用 WebView
        // （DouyinSearchView），WebView 会吞掉横向拖动、与切页冲突；后来抖音搜索
        // 改回普通列表（commit e95a792），这个限制就成了遗留，现移除。
        // 桌面端能否用鼠标左右拖，由全局 AppScrollBehavior 决定（见 main.dart）。
        controller: controller.tabController,
        children: Sites.supportSites
            .map((e) => SearchListView(
                  e.id,
                ))
            .toList(),
      ),
    );
  }
}
