import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class AppStyleSettingPage extends GetView<AppStyleSettingController> {
  const AppStyleSettingPage({super.key});

  Widget trailingBuild({required Widget widget}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: "重置为默认字体",
          child: IconButton(
            onPressed: controller.fontReset,
            icon: Icon(Icons.settings_backup_restore_outlined),
          ),
        ),
        AppStyle.hGap4,
        Visibility(
          visible: controller.fontState.value == DownloadState.downloaded,
          child: Tooltip(
            message: "删除字体",
            child: IconButton(
              onPressed: controller.fontDelete,
              icon: Icon(Icons.delete_outline_outlined),
            ),
          ),
        ),
        Visibility(
          visible: controller.fontState.value == DownloadState.downloaded,
          child: AppStyle.hGap4,
        ),
        widget,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("外观设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "显示主题",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => RadioGroup<int>(
                groupValue: AppSettingsController.instance.themeModeIndex,
                onChanged: (e) {
                  controller.setTheme(e ?? 0);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      title: const Text(
                        "跟随系统",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 0,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: const Text(
                        "浅色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 1,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: const Text(
                        "深色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 2,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppStyle.vGap12,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "底部导航",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(() {
              final settings = AppSettingsController.instance;
              final useFloating = settings.navBarStyle.value == 1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSwitch(
                    title: "悬浮胶囊导航栏",
                    subtitle: "开启后导航栏浮在内容之上（仅竖屏生效）",
                    value: useFloating,
                    onChanged: (e) => settings.setNavBarStyle(e ? 1 : 0),
                  ),
                  AppStyle.divider,
                  SettingsSwitch(
                    title: "Liquid Glass 效果（实验性）",
                    subtitle: useFloating
                        ? "为悬浮胶囊叠加透明折射玻璃效果，可能与部分设备/主题不兼容"
                        : "该效果依附于悬浮胶囊，开启上方开关后可用",
                    value: settings.liquidGlassEffect.value,
                    // 与悬浮胶囊强绑定：样式为「标准」时锁定，避免出现
                    // 「开了玻璃却看不到任何变化」的困惑
                    locked: !useFloating,
                    lockedHint: "Liquid Glass 只能叠加在悬浮胶囊上，请先开启「悬浮胶囊导航栏」",
                    onChanged: settings.setLiquidGlassEffect,
                  ),
                ],
              );
            }),
          ),
          if (kDebugMode) ...[
            AppStyle.vGap12,
            Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Text(
                "开发者选项",
                style: context.textTheme.titleSmall,
              ),
            ),
            SettingsCard(
              child: ListTile(
                title: const Text("Liquid Glass 调试"),
                subtitle: const Text("滑动调节玻璃参数，实时预览浅色模式可读性"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.toNamed(RoutePath.kLiquidGlassDebug),
              ),
            ),
          ],
          AppStyle.vGap12,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "主题颜色",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSwitch(
                    value: controller.isDynamic.value,
                    title: "动态取色",
                    onChanged: (e) {
                      controller.setIsDynamic(e);
                      Get.forceAppUpdate();
                    },
                  ),
                  if (!controller.isDynamic.value) AppStyle.divider,
                  if (!controller.isDynamic.value)
                    Padding(
                      padding: AppStyle.edgeInsetsA12,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Color>[
                          const Color(0xffEF5350),
                          const Color(0xff3498db),
                          const Color(0xffF06292),
                          const Color(0xff9575CD),
                          const Color(0xff26C6DA),
                          const Color(0xff26A69A),
                          const Color(0xffFFF176),
                          const Color(0xffFF9800),
                        ]
                            .map(
                              (e) => Tooltip(
                                message: "使用此主题色",
                                child: GestureDetector(
                                  onTap: () {
                                    controller.setStyleColor(e.v);
                                    Get.forceAppUpdate();
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: e,
                                      borderRadius: AppStyle.radius4,
                                      border: Border.all(
                                        color: Colors.grey.withAlpha(50),
                                        width: 1,
                                      ),
                                    ),
                                    child: Obx(
                                      () => Center(
                                        child: Icon(
                                          Icons.check,
                                          color: controller.styleColor.value ==
                                                  e.v
                                              ? Colors.white
                                              : Colors.transparent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AppStyle.vGap12,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "字体设置",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => SettingsMenu(
                title: controller.curFontModel.value!.name,
                value: controller.curFontModel.value!,
                valueMap: controller.fontMap,
                onChanged: (e) {
                  controller.onFontSelected(e);
                },
                trailing: Obx(() {
                  switch (controller.fontState.value) {
                    case DownloadState.notDownloaded:
                      return trailingBuild(
                        widget: Tooltip(
                          message: "下载字体",
                          child: IconButton(
                            icon: const Icon(Icons.download_outlined),
                            onPressed: () => controller.downloadFont(),
                          ),
                        ),
                      );

                    case DownloadState.downloading:
                      return trailingBuild(
                        widget: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    case DownloadState.downloaded:
                      return trailingBuild(
                        widget: Tooltip(
                          message: "应用字体",
                          child: IconButton(
                            icon:
                                const Icon(Icons.check_circle_outline_outlined),
                            onPressed: () => controller.changeFontFamily(),
                          ),
                        ),
                      );
                  }
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension ColorExt on Color {
  static int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  int get v =>
      _floatToInt8(a) << 24 |
      _floatToInt8(r) << 16 |
      _floatToInt8(g) << 8 |
      _floatToInt8(b) << 0;
}
