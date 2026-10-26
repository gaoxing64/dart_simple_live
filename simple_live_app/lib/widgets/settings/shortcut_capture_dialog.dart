/// 快捷键录制对话框：按下组合键即录入，支持「恢复默认」与「不设置」。
///
/// 形态对齐参考图：标题＝动作名，中间一块深色区显示已录的组合键 chips，
/// 下面两个文字按钮（↺ 恢复默认 / × 不设置），底部「取消 / 保存」。
///
/// 这个对话框**必须吞掉所有按键**（`onKeyEvent` 一律返回 handled）：
/// - 不吞空格，用户想录「空格」却先把后面的视频暂停了；
/// - 不吞 Esc，而 Esc 恰恰是默认要绑的那个键——它同时是对话框的关闭键，
///   两者在这里天然冲突，只能选「录进去」，关闭交给「取消」按钮。
/// 吞掉也就阻断了向 `main.dart` 那条全局链的冒泡（`Focus` 消费后不再上抛）。
///
/// ⚠️ 里面所有按钮都包了 [Focus](`canRequestFocus: false`)：按钮一旦拿到焦点，
/// Space/Enter 会被它自己的「激活」快捷键先消费掉（焦点树里子节点先于父节点），
/// 于是「录一个空格」变成「点了取消」。鼠标点击不经过焦点链，所以按钮照常可点；
/// 代价是这几个按钮不能用 Tab 走到——录制框本来就是一个「按下键即完成」的界面。
library;

import 'package:flutter/services.dart'
    show
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        HardwareKeyboard;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 用户的四种落点。用一个类而不是 `ShortcutBinding?` + 布尔，是为了让调用方
/// 无法把「取消」与「不设置」混成同一个 null——那两者语义相反（一个不改，一个禁用）。
class ShortcutEditResult {
  const ShortcutEditResult.saved(ShortcutBinding b)
    : binding = b,
      toDefault = false,
      unset = false;

  const ShortcutEditResult.toDefault()
    : binding = null,
      toDefault = true,
      unset = false;

  const ShortcutEditResult.unset()
    : binding = null,
      toDefault = false,
      unset = true;

  const ShortcutEditResult.cancelled()
    : binding = null,
      toDefault = false,
      unset = false;

  /// 只有 [ShortcutEditResult.saved] 才非空。
  final ShortcutBinding? binding;
  final bool toDefault;
  final bool unset;

  bool get isCancelled => binding == null && !toDefault && !unset;
}

/// 弹出录制框。[current] 是该动作此刻的**生效**绑定（用于初始显示与「恢复默认」
/// 的可点性），[defaultBinding] 是它的默认键位。
Future<ShortcutEditResult> showShortcutCaptureDialog({
  required String title,
  required ShortcutBinding? current,
  required ShortcutBinding? defaultBinding,
}) async {
  final result = await Get.dialog<ShortcutEditResult>(
    _ShortcutCaptureDialog(
      title: title,
      current: current,
      defaultBinding: defaultBinding,
    ),
    // 点遮罩不算「取消」而是干脆不响应：误点一下遮罩就把录了一半的组合键丢掉，
    // 比误点关闭更让人恼火。显式按钮才是唯一的出口。
    barrierDismissible: false,
  );
  // 系统返回键等不走 Get.back(result:) 的路径关掉的，一律按取消处理：
  // 没有结果就等于用户没确认，绝不能误判成「不设置」。
  return result ?? const ShortcutEditResult.cancelled();
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({
    required this.title,
    required this.current,
    required this.defaultBinding,
  });

  final String title;
  final ShortcutBinding? current;
  final ShortcutBinding? defaultBinding;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  /// 已经录下的组合键；null＝还没按过任何主键（此时「保存」不可用）。
  ShortcutBinding? _recorded;

  /// 当前按住的修饰键，只用于「正在按 Shift+…」的即时反馈。
  bool _shift = false, _ctrl = false, _alt = false, _meta = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _recorded = widget.current;
  }

  /// 按下的键是否就是默认组合（决定「恢复默认」要不要置灰）。
  bool get _alreadyDefault {
    final def = widget.defaultBinding;
    // 「不设置」状态下默认键位并没有在用着，恢复默认仍然是有意义的动作。
    return def != null && _recorded != null && _recorded == def;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 抬起与重复都吞掉但不处理：不吞的话会冒到全局链上真的去关弹窗/退全屏。
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      _syncModifiers();
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (isModifierKey(key)) {
      // 裸修饰键不落定：用户要的是「Shift + 某键」，此刻主键还没来。
      _syncModifiers();
      return KeyEventResult.handled;
    }

    if (isForbiddenShortcutKey(key)) {
      setState(() {
        _error = '这个键不能绑定（会破坏界面的键盘导航）';
      });
      return KeyEventResult.handled;
    }

    final hk = HardwareKeyboard.instance;
    setState(() {
      _recorded = ShortcutBinding(
        key,
        shift: hk.isShiftPressed,
        ctrl: hk.isControlPressed,
        alt: hk.isAltPressed,
        meta: hk.isMetaPressed,
      );
      _error = null;
    });
    return KeyEventResult.handled;
  }

  /// 只按住了修饰键时刷新一次 chips 区的即时反馈。
  void _syncModifiers() {
    final hk = HardwareKeyboard.instance;
    final next = (
      hk.isShiftPressed,
      hk.isControlPressed,
      hk.isAltPressed,
      hk.isMetaPressed,
    );
    if (next.$1 == _shift &&
        next.$2 == _ctrl &&
        next.$3 == _alt &&
        next.$4 == _meta) {
      return;
    }
    setState(() {
      _shift = next.$1;
      _ctrl = next.$2;
      _alt = next.$3;
      _meta = next.$4;
    });
  }

  /// 按钮的公共包装：不吃键盘焦点，见文件头的 ⚠️。
  Widget _button(Widget child) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 深色录入区：chips 摆在中间，没按键时给一句提示。
            Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: AppStyle.edgeInsetsA12,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: AppStyle.radius8,
              ),
              child: Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._chips(theme),
                    if (_recorded == null && !_previewing)
                      Text(
                        '请按下组合键',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              AppStyle.vGap8,
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            AppStyle.vGap12,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _button(
                  TextButton.icon(
                    onPressed: _alreadyDefault
                        ? null
                        : () => Get.back(
                            result: const ShortcutEditResult.toDefault(),
                          ),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('恢复默认'),
                  ),
                ),
                AppStyle.hGap8,
                _button(
                  TextButton.icon(
                    onPressed: _recorded == null
                        ? null
                        : () => Get.back(
                            result: const ShortcutEditResult.unset(),
                          ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('不设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _button(
            TextButton(
              onPressed: () =>
                  Get.back(result: const ShortcutEditResult.cancelled()),
              child: const Text('取消'),
            ),
          ),
          _button(
            FilledButton(
              // 「保存」只在真有录到的组合键时可点：没按过任何键的「保存」等于
              // 一次无意义的写入，而用户此刻大概率是想取消。
              onPressed: _recorded == null ? null : _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final recorded = _recorded;
    if (recorded == null) {
      return;
    }
    Get.back(result: ShortcutEditResult.saved(recorded));
  }

  /// 有已录组合键时不显示「正在按住」的预览，避免两套 chips 打架。
  bool get _previewing => _shift || _ctrl || _alt || _meta;

  /// chips：已录的组合键；没录但正按住修饰键时，显示那几个修饰键作为即时反馈。
  List<Widget> _chips(ThemeData theme) {
    final names = <String>[];
    final recorded = _recorded;
    if (recorded != null) {
      if (recorded.shift) names.add('Shift');
      if (recorded.ctrl) names.add('Ctrl');
      if (recorded.alt) names.add('Alt');
      if (recorded.meta) names.add('Meta');
      names.add(shortcutKeyLabel(recorded.key));
    } else if (_previewing) {
      if (_shift) names.add('Shift');
      if (_ctrl) names.add('Ctrl');
      if (_alt) names.add('Alt');
      if (_meta) names.add('Meta');
    }
    return [
      for (final name in names)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: AppStyle.radius8,
          ),
          child: Text(
            name,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ];
  }
}
