import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class IndexedSettingsPage extends GetView<IndexedSettingsController> {
  const IndexedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("主页设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "顶/底栏收起",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () {
                var settings = AppSettingsController.instance;
                var anyOn =
                    settings.hideTopBar.value || settings.hideBottomBar.value;
                return Column(
                  children: [
                    SettingsSwitch(
                      value: settings.hideTopBar.value,
                      title: "首页顶栏收起",
                      subtitle: "首页列表滑动时，收起顶栏",
                      onChanged: (e) {
                        settings.setHideTopBar(e);
                      },
                    ),
                    AppStyle.divider,
                    SettingsSwitch(
                      value: settings.hideBottomBar.value,
                      title: "首页底栏收起",
                      subtitle: "首页列表滑动时，收起底栏",
                      onChanged: (e) {
                        settings.setHideBottomBar(e);
                      },
                    ),
                    if (anyOn) ...[
                      AppStyle.divider,
                      SettingsMenu<int>(
                        title: "顶/底栏收起类型",
                        value: settings.barHideType.value,
                        valueMap: const {0: "即时", 1: "同步"},
                        onChanged: (e) {
                          settings.setBarHideType(e);
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "主页排序 (长按拖动排序，重启后生效)",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: controller.updateHomeSort,
                children: controller.homeSort.map(
                  (key) {
                    var e = Constant.allHomePages[key]!;
                    return ListTile(
                      key: ValueKey(e.title),
                      title: Text(e.title),
                      visualDensity: VisualDensity.compact,
                      leading: Icon(e.iconData),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ).toList(),
              ),
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "平台排序 (长按拖动排序，重启后生效)",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: controller.updateSiteSort,
                children: controller.siteSort
                    .where((key) => Sites.allSites[key]?.name != 'Twitch')
                    .map(
                  (key) {
                    var e = Sites.allSites[key]!;
                    return ListTile(
                      key: ValueKey(e.id),
                      visualDensity: VisualDensity.compact,
                      title: Text(e.name),
                      leading: Image.asset(
                        e.logo,
                        width: 24,
                        height: 24,
                      ),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
