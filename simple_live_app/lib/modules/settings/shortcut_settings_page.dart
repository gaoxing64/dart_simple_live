/// 「播放器快捷键」设置页：每个动作一行，可改键、可单独恢复默认、可「不设置」。
///
/// 布局对齐参考图：一个分组卡，表头是标题 + 副标题 + ↺（全部恢复默认）+ 折叠箭头，
/// 下面是动作行（动作名 + 当前按键 + ✏️）。
///
/// 页内不写任何键位规则：默认值、匹配、冲突判定、编解码全在 `shortcut_binding.dart`，
/// 读写走 `AppSettingsController`。这一层只负责「显示当前生效的那份」与「把用户
/// 的意图转成一次 setter 调用」。
library;

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/settings/shortcut_capture_dialog.dart';

class ShortcutSettingsPage extends StatelessWidget {
  const ShortcutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("播放器快捷键"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Obx(
            () => SettingsSwitch(
              title: "启用键盘快捷键",
              subtitle:
                  "关闭后视频区不再响应任何按键（Esc 的关弹窗/退全屏不受影响）",
              value: AppSettingsController.instance.keyboardControl.value,
              onChanged: AppSettingsController.instance.setKeyboardControl,
            ),
          ),
          AppStyle.divider,
          const _ShortcutListCard(),
        ],
      ),
    );
  }
}

/// 那张分组卡：表头 + 可折叠的动作行列表。
class _ShortcutListCard extends StatefulWidget {
  const _ShortcutListCard();

  @override
  State<_ShortcutListCard> createState() => _ShortcutListCardState();
}

class _ShortcutListCardState extends State<_ShortcutListCard> {
  /// 折叠状态是会话内的，不落盘：它不是用户偏好，只是这一次浏览的临时姿态。
  bool _collapsed = false;

  Future<void> _edit(PlayerShortcut action) async {
    final settings = AppSettingsController.instance;
    final result = await showShortcutCaptureDialog(
      title: shortcutActionTitle(action),
      current: settings.bindingFor(action),
      defaultBinding: kDefaultShortcuts[action],
    );
    if (result.isCancelled) {
      return;
    }
    if (result.toDefault) {
      settings.resetShortcut(action);
      return;
    }
    if (result.unset) {
      settings.setShortcut(action, null);
      return;
    }
    final binding = result.binding!;
    // 冲突要在这里挡：让两个动作共用一个键，按下时 matchShortcut 只会命中
    // resolveEffectiveShortcuts 里靠前的那个，另一个静默失效——用户看到的就是
    // 「我明明配了却没反应」。
    final conflict = conflictShortcut(
      settings.effectiveShortcuts,
      binding,
      action,
    );
    if (conflict != null) {
      SmartDialog.showToast(
        "已被「${shortcutActionTitle(conflict)}」占用，请先修改那一项",
      );
      return;
    }
    settings.setShortcut(action, binding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 表头：标题 + 副标题 + ↺ + 折叠箭头。整行可点，点一下折叠/展开。
          InkWell(
            borderRadius: AppStyle.radius8,
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  AppStyle.hGap8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("播放器快捷键", style: theme.textTheme.titleSmall),
                        Text(
                          "直播画面获得焦点时生效",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ↺ 单独吃掉点击：它就在可折叠行的正中间，不挡住就会「重置顺带折叠」。
                  IconButton(
                    tooltip: "全部恢复默认",
                    onPressed: () {
                      final settings = AppSettingsController.instance;
                      if (settings.shortcutOverrides.value.isEmpty) {
                        SmartDialog.showToast("已经是默认键位了");
                        return;
                      }
                      settings.resetAllShortcuts();
                      SmartDialog.showToast("已恢复默认键位");
                    },
                    icon: const Icon(Icons.restore),
                  ),
                  AnimatedRotation(
                    turns: _collapsed ? 0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity)
                : Obx(() {
                    // 订阅覆盖表：改完一行，整张表（含别的行上可能出现的冲突态）
                    // 跟着重建。读 effectiveShortcuts 必须在这个 Obx 里面。
                    final effective = AppSettingsController
                        .instance
                        .effectiveShortcuts;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, action) in kShortcutOrder.indexed) ...[
                          if (i > 0) AppStyle.divider,
                          _buildRow(context, action, effective[action]),
                        ],
                      ],
                    );
                  }),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    PlayerShortcut action,
    ShortcutBinding? binding,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 8),
      title: Text(
        shortcutActionTitle(action),
        style: theme.textTheme.bodyLarge?.copyWith(
          // 被「不设置」禁用的动作灰一档：它现在真的按不出来，不该看着和别的行一样。
          color: binding == null ? theme.disabledColor : null,
        ),
      ),
      subtitle: Text(
        binding == null ? "未设置" : shortcutBindingLabel(binding),
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
      trailing: IconButton(
        tooltip: "修改按键",
        onPressed: () => _edit(action),
        icon: const Icon(Icons.edit_outlined),
      ),
      onTap: () => _edit(action),
    );
  }
}
