import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/collapse_slot.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({super.key});

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

  /// 底栏收起容器（即时=动画，同步=跟随偏移）
  Widget _buildBottomBar(Widget nav) {
    var settings = AppSettingsController.instance;
    return Obx(() {
      if (!settings.hideBottomBar.value) {
        return nav;
      }
      if (settings.barHideType.value == 0) {
        // 即时
        var show = controller.showBottomBar.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: show ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubicEmphasized,
          builder: (_, factor, child) => CollapseSlot(
            factor: factor,
            alignment: Alignment.topCenter,
            child: child!,
          ),
          child: nav,
        );
      }
      // 同步
      var factor =
          1 - controller.barOffset.value / IndexedController.maxBarOffset;
      return CollapseSlot(
        factor: factor,
        alignment: Alignment.topCenter,
        child: nav,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: controller.onScrollNotification,
            child: Row(
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
          ),
          bottomNavigationBar: orientation == Orientation.portrait
              ? _buildBottomBar(_buildDefaultNavBar())
              : null,
        );
      },
    );
  }
}
