/// 播放器按钮 Tooltip 的「内联键帽」渲染器。
///
/// 目的：把「这个按钮对应哪个快捷键」直接印在 tooltip 上（参考三方播放器
/// 「进入全屏 [H]」那种），用户不必进设置翻快捷键表。键帽显示的是**当前生效
/// 绑定**（跟着用户改键 / 禁用 / 关闭自定义走），不是写死的默认值。
///
/// 为什么用外部 Tooltip 而不是 `IconButton.tooltip`：后者是 `String?`，画不了
/// 键帽。`material_ui` 的 `Tooltip.richMessage`（`InlineSpan`）可以塞 `WidgetSpan`，
/// 且 `_TooltipBox` 用 `Text.rich(richMessage, style: textStyle)` 渲染——纯文字
/// 继承 tooltip 的浅色，键帽自带底色，互不干扰。
///
/// 约定：**凡经 [shortcutTooltip] 的按钮，内层 `tooltip:` 必须传 null**，否则
/// 会叠两层 tooltip。本函数外面永远包着同一个 widget（[Obx]），里面有键帽走
/// `richMessage`、无键帽走 `message`，所以未绑定动作的观感与改前逐字一致。
library;

import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 播放器动作 → 它对应的快捷键枚举；没有快捷键的动作返回 null。
///
/// 这是「按钮」与「快捷键」两套枚举之间**唯一**的桥。之所以放这儿而不是塞进
/// `PlayerActionId` 或 `PlayerShortcut`：两边各自独立演化（动作清单按宿主裁剪、
/// 快捷键按用户可配），硬把映射写进任一枚举都会让另一侧的改动波及自己。
///
/// 音量颗映射到 [PlayerShortcut.mute]：桌面点音量＝静音（见
/// `player_action_bar.dart` 的 volume 臂 → `VolumeActionWidget` 的 `toggleMute`）。
/// 触屏点音量是弹滑条、静音另有 `muteTile`，所以**调用方**在触屏下不传这个映射
/// （见 `player_volume_action.dart`），不在表里判平台。
PlayerShortcut? shortcutForAction(PlayerActionId id) => switch (id) {
      PlayerActionId.refresh => PlayerShortcut.refresh,
      PlayerActionId.danmakuToggle => PlayerShortcut.danmakuToggle,
      PlayerActionId.smallWindow => PlayerShortcut.smallWindow,
      PlayerActionId.screenshot => PlayerShortcut.screenshot,
      PlayerActionId.pick => PlayerShortcut.pick,
      PlayerActionId.fullscreenToggle => PlayerShortcut.fullscreen,
      PlayerActionId.quality => PlayerShortcut.quality,
      PlayerActionId.volume => PlayerShortcut.mute,
      _ => null,
    };

/// 把 [child] 包成一个带（或不带）键帽的 Tooltip。
///
/// - [shortcut] 为 null，或该动作被「不设置」禁用（`bindingFor` 返回 null）→
///   纯 [label] 文案，等价于改前的 `tooltip: label`。
/// - 键盘控制总开关关着 → 同样只给纯 [label]：画面上根本没有键可按，
///   还留一颗键帽等于教用户去按一个不会响应的键。
/// - 否则 → 「label + 键帽」，键帽文字是 [shortcutBindingLabel]（如 `F`、`Ctrl + F`）。
///
/// 外面那层 [Obx] 不是顺手加的：设置页是**独立路由**，压在上面改键/关开关再返回时，
/// 底下这排按钮并不会自己重建（它们不持有任何订阅），于是键帽会停在一个已经失效的
/// 键上。订阅放在这一层，开关一动键帽立刻跟着走。
///
/// [child] 必须是**没有自带 tooltip** 的按钮（内层 `tooltip:` 传 null）。
Widget shortcutTooltip({
  required String label,
  required PlayerShortcut? shortcut,
  required Widget child,
}) {
  // 先判空再进 Obx：Obx 里一个 observable 都没读会被 GetX 判成滥用。
  if (shortcut == null) {
    return Tooltip(message: label, child: child);
  }
  final action = shortcut;
  return Obx(() {
    final settings = AppSettingsController.instance;
    final binding =
        settings.keyboardControl.value ? settings.bindingFor(action) : null;
    if (binding == null) {
      return Tooltip(message: label, child: child);
    }
    return Tooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(text: label),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _ShortcutKeyCap(shortcutBindingLabel(binding)),
          ),
        ],
      ),
      child: child,
    );
  });
}

/// 键帽：白底黑字的小圆角块，压在深色 tooltip 上（对齐参考图）。
///
/// 自带左边距，所以调用方不必再排间隔。颜色写死而非取主题：tooltip 的
/// `DefaultTextStyle` 是浅色（黑底白字），键帽要的是反过来的「浅底深字」才像
/// 一颗物理按键；跟随主题会让键帽和它所在的 tooltip 同色系而糊掉。
class _ShortcutKeyCap extends StatelessWidget {
  const _ShortcutKeyCap(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
