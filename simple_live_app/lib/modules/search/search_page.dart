import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';
import 'package:simple_live_app/modules/search/aggregate_search_view.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';

class _SearchModeSelector extends StatelessWidget {
  static const BorderRadius _kTriggerRadius =
      BorderRadius.all(Radius.circular(20));
  static const List<int> _modeValues = [0, 1];
  static const List<String> _modeLabels = ["房间", "主播"];

  final int value;
  final ValueChanged<int> onChanged;

  const _SearchModeSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<int>(
        tooltip: "选择搜索类型",
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        borderRadius: _kTriggerRadius,
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
        onSelected: onChanged,
        itemBuilder: (context) => List.generate(
          _modeValues.length,
          (index) => AppPopupMenuItem<int>(
            value: _modeValues[index],
            child: Text(_modeLabels[index]),
          ),
        ),
        child: Container(
          // 传了 `child` 时 material_ui 的 PopupMenuButton 走 shrinkWrap，不给
          // kMinInteractiveDimension 下限（旧 DropdownButton 本来自带 48dp）。
          // 这里自己把可点区撑到 48：同一行的前后缀都是 IconButton，字段本来就有
          // 48dp 高，所以只有点击区变大，胶囊视觉仍是内容高度。
          height: 48,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: _kTriggerRadius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_modeLabels[_modeValues.indexOf(value)]),
                AppStyle.hGap4,
                Icon(
                  Remix.arrow_down_s_line,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SearchPage extends GetView<AppSearchController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final aggregateEnabled =
          AppSettingsController.instance.aggregateSearchEnabled.value;
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
                  // 模式只有一份真值：聚合时读聚合控制器（布局与请求都跟着它走），
                  // 按平台时读本页这一份。点下去不再先改标签再等业务生效。
                  Obx(
                    () => _SearchModeSelector(
                      value: aggregateEnabled
                          ? controller.aggregateController.searchMode.value
                          : controller.searchMode.value,
                      onChanged: controller.onSearchModeChanged,
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
          bottom: aggregateEnabled
              ? null
              : TabBar(
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
        body: aggregateEnabled
            ? const AggregateSearchView()
            : TabBarView(
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
    });
  }
}
