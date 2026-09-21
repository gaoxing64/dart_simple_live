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

  /// 单项重置按钮。
  ///
  /// 没改动过时置灰：既避免"点了没反应"的困惑，也顺带把改过的参数标出来。
  Widget _resetButton({
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: "重置该项",
      iconSize: 16,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.settings_backup_restore_outlined),
    );
  }

  /// 一根滑杆 + 右侧的单项重置按钮。
  /// 标签/范围/默认值全部来自 [GlassParam]，页面这层不再重复写一遍。
  Widget _paramSlider(BuildContext context, GlassParam param) {
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsH12.copyWith(top: 8),
            child: Row(
              children: [
                // Expanded：参数名可能很长（如 animationDuration 滑动时长(ms)），
                // 加上大字号/长标题时不能让这一行撑爆
                Expanded(
                  child: Text(
                    param.label,
                    style: context.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  param.display,
                  style: context.textTheme.bodySmall!.copyWith(
                    color: Colors.grey,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                _resetButton(
                  enabled: param.isModified,
                  onPressed: param.reset,
                ),
              ],
            ),
          ),
          Slider(
            value: param.value.value.clamp(param.min, param.max),
            min: param.min,
            max: param.max,
            // 与 GlassParam.isModified 的容差共用同一个档位数，否则「拖回默认位置
            // 按钮还亮着」的判定会与实际滑动行为对不上
            divisions: param.divisions,
            label: param.display,
            onChanged: (e) => param.value.value = e,
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(bottom: 0),
          child: Text(title, style: context.textTheme.titleSmall),
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

  /// 药丸滑动开关行。
  ///
  /// 它不是滑杆，但同样带单项重置 —— 按钮位置和滑杆行对齐（都在最右），
  /// 顺着往下点的时候手感一致。
  ///
  /// padding 必须套在**整行**外面（和 [_paramSlider] 一样）：套在行内的 `Text`
  /// 上只会内缩文字，行本身仍然铺满卡片，重置按钮就比滑杆行靠外 12px，
  /// 与上面那句「都在最右」对不上。
  Widget _pillAnimatedSwitch(BuildContext context) {
    return Obx(
      () => Padding(
        padding: AppStyle.edgeInsetsH12.copyWith(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "animated 滑动切换",
                style: context.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: controller.pillAnimated.value,
              onChanged: (v) => controller.pillAnimated.value = v,
            ),
            _resetButton(
              enabled: controller.pillAnimatedModified,
              onPressed: controller.resetPillAnimated,
            ),
          ],
        ),
      ),
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
                style: context.textTheme.titleMedium,
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
                    liquidGlassItemPadding: controller.itemPadding.value,
                    liquidGlassStyle: controller.buildBarStyle(),
                    liquidGlassItemStyle: controller.buildItemStyle(
                      selectedColor: Theme.of(context).colorScheme.primary,
                      unselectedColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    liquidGlassPillStyle: controller.buildPillStyle(
                      Theme.of(context).brightness,
                    ),
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
              // 药丸基底色分浅/深两档，导出必须带上当前主题亮度，
              // 否则深色下调出来的 alpha 会配错基底色
              final code = controller.exportCode(
                brightness: Theme.of(context).brightness,
              );
              Clipboard.setData(ClipboardData(text: code));
              Get.snackbar("Liquid Glass 调试", "参数代码已复制到剪贴板");
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      // 置顶区：说明 + 预览。
      //
      // 参数列表在它下面独立滚动 —— 否则往下拖滑块时预览会跟着一起卷走，
      // 就没法"边调边看"了。
      body: Column(
        children: [
          Padding(
            padding: AppStyle.edgeInsetsH24.copyWith(top: 12),
            child: Text(
              "参数实时作用于整条 Liquid Glass 底栏（胶囊 + 图标文字 + 选中药丸），"
              "可切到首页对照真实内容背景调节浅色模式可读性。",
              style: context.textTheme.bodySmall!.copyWith(color: Colors.grey),
            ),
          ),
          _preview(context),
          AppStyle.divider,
          Expanded(
            child: ListView(
              padding: AppStyle.edgeInsetsV12,
              children: [
                // 分组内容全部由控制器的参数表派生：
                // 新增一个参数只需要在控制器里加一行，页面、重置都自动跟上
                _section(context, "胶囊本体", [
                  for (final param in controller.capsuleParams)
                    _paramSlider(context, param),
                ]),
                _section(context, "折射", [
                  for (final param in controller.refractionParams)
                    _paramSlider(context, param),
                ]),
                _section(context, "选中药丸", [
                  for (final param in controller.pillParams)
                    _paramSlider(context, param),
                  _pillAnimatedSwitch(context),
                ]),
                _section(context, "图标与文字", [
                  for (final param in controller.itemParams)
                    _paramSlider(context, param),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
