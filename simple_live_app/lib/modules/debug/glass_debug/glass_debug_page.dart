import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/debug/glass_debug/glass_debug_controller.dart';
import 'package:simple_live_app/widgets/floating_navigation_bar.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

/// Liquid Glass 参数调试页（仅 Debug 构建可进入）。
///
/// 参数实时作用于真实的底部悬浮胶囊背景（见 indexed_page），
/// 请切换到首页对照实际内容背景调节浅色模式可读性。
class GlassDebugPage extends GetView<GlassDebugController> {
  const GlassDebugPage({super.key});

  Widget _slider(
    String title,
    Rx<double> value, {
    required double min,
    required double max,
    int? precision,
  }) {
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsH12.copyWith(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Get.textTheme.bodyMedium),
                Text(
                  value.value.toStringAsFixed(precision ?? 2),
                  style: Get.textTheme.bodySmall!.copyWith(
                    color: Colors.grey,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Slider(
            value: value.value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / 0.01).round().clamp(10, 600),
            label: value.value.toStringAsFixed(precision ?? 2),
            onChanged: (e) => value.value = e,
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(bottom: 0),
          child: Text(title, style: Get.textTheme.titleSmall),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ],
    );
  }

  /// 预览：彩色背景上叠加同参数的玻璃导航栏
  Widget _preview(BuildContext context) {
    return Obx(
      () => Container(
        margin: AppStyle.edgeInsetsA12,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: AppStyle.radius12,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Colors.white,
              Theme.of(context).colorScheme.tertiaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Center(
              child: Text(
                "浅色可读性预览区",
                style: Get.textTheme.titleMedium,
              ),
            ),
            SafeArea(
              top: false,
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: FloatingNavigationBar(
                    selectedIndex: controller.previewIndex.value,
                    onDestinationSelected: (i) =>
                        controller.previewIndex.value = i,
                    liquidGlass: true,
                    liquidGlassSettings: controller.buildSettings(),
                    destinations: const [
                      FloatingNavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        label: "首页",
                      ),
                      FloatingNavigationDestination(
                        icon: Icon(Icons.live_tv_outlined),
                        label: "直播",
                      ),
                      FloatingNavigationDestination(
                        icon: Icon(Icons.person_outline),
                        label: "我的",
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Liquid Glass 调试"),
        actions: [
          IconButton(
            tooltip: "重置为默认值",
            onPressed: controller.reset,
            icon: const Icon(Icons.settings_backup_restore_outlined),
          ),
          IconButton(
            tooltip: "复制参数代码",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: controller.exportCode()));
              Get.snackbar("Liquid Glass 调试", "参数代码已复制到剪贴板");
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsV12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsH24,
            child: Text(
              "参数实时作用于底部悬浮胶囊背景，可切到首页对照真实内容背景调节浅色模式可读性。",
              style: Get.textTheme.bodySmall!.copyWith(color: Colors.grey),
            ),
          ),
          _preview(context),
          _section("玻璃材质", [
            _slider("glassColor 白色不透明度", controller.glassColorAlpha,
                min: 0, max: 255, precision: 0),
            _slider("blur 模糊", controller.blur, min: 0, max: 30),
            _slider("thickness 厚度", controller.thickness, min: 0, max: 60),
            _slider("visibility 可见度", controller.visibility, min: 0, max: 1),
            _slider("saturation 饱和度", controller.saturation, min: 0, max: 3),
            _slider("whitenStrength 白化强度", controller.whitenStrength,
                min: 0, max: 1),
            _slider("standardOpacityMultiplier 透明度倍率",
                controller.standardOpacityMultiplier,
                min: 0, max: 2),
          ]),
          _section("光照与折射", [
            _slider("lightIntensity 光照强度", controller.lightIntensity,
                min: 0, max: 1),
            _slider("ambientStrength 环境光", controller.ambientStrength,
                min: 0, max: 1),
            _slider("ambientRim 边缘环境光", controller.ambientRim, min: 0, max: 1),
            _slider("fresnelStrength 菲涅尔", controller.fresnelStrength,
                min: 0, max: 2),
            _slider("refractiveIndex 折射率", controller.refractiveIndex,
                min: 1, max: 2),
            _slider("glowIntensity 辉光强度", controller.glowIntensity,
                min: 0, max: 1),
          ]),
        ],
      ),
    );
  }
}
