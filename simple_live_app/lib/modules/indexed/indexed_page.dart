import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({super.key});

  /// 悬浮玻璃导航栏（Liquid Glass，iOS 26 风格）
  Widget _buildGlassNavBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      // heightFactor: 1 防止 Center 占满 Scaffold 底栏槽位高度，导致胶囊垂直居中
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Obx(
            () => glass.GlassTabBar.bottom(
              selectedIndex: controller.index.value,
              onTabSelected: controller.setIndex,
              verticalPadding: 12,
              selectedIconColor: colorScheme.onSurface,
              unselectedIconColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.secondaryContainer,
              tabs: controller.items
                  .map(
                    (item) => glass.GlassTab(
                      icon: Icon(item.iconData),
                      activeIcon: Icon(item.iconData),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultNavBar() {
    return Obx(
      () => NavigationBar(
        selectedIndex: controller.index.value,
        onDestinationSelected: controller.setIndex,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: controller.items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.iconData),
                label: item.title,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final useGlassNavBar =
          AppSettingsController.instance.floatingGlassNavBar.value;
      return OrientationBuilder(
        builder: (context, orientation) {
          return Scaffold(
            extendBody: orientation == Orientation.portrait && useGlassNavBar,
            body: Row(
              children: [
                Visibility(
                  visible: orientation == Orientation.landscape,
                  child: Obx(
                    () => NavigationRail(
                      selectedIndex: controller.index.value,
                      onDestinationSelected: controller.setIndex,
                      labelType: NavigationRailLabelType.none,
                      destinations: controller.items
                          .map(
                            (item) => NavigationRailDestination(
                              icon: Icon(item.iconData),
                              label: Text(item.title),
                              padding: AppStyle.edgeInsetsV8,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                Expanded(
                  child: Obx(
                    () => Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: orientation == Orientation.landscape
                              ? BorderSide(
                                  color: Colors.grey.withAlpha(50),
                                  width: 1,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      child: IndexedStack(
                        index: controller.index.value,
                        children: controller.pages,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: orientation == Orientation.portrait
                ? (useGlassNavBar
                    ? _buildGlassNavBar(context)
                    : _buildDefaultNavBar())
                : null,
          );
        },
      );
    });
  }
}
