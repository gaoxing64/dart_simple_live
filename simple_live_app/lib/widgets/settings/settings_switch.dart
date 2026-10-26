import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';

/// 设置页通用开关。
///
/// 外观对齐 Material 3：关闭时轨道描边 + 浅色底，开启时主色轨道 + 滑块上的对勾。
/// [locked] 为真时滑块换成锁图标、取值不可更改（点击给出 [lockedHint] 提示），
/// 用于表达「该选项被其它设置绑定」。
class SettingsSwitch extends StatelessWidget {
  final bool value;
  final String title;
  final String? subtitle;

  /// 标题样式，默认取 `bodyLarge`；底部弹窗里沿用 `titleMedium` 时传入
  final TextStyle? titleStyle;
  final Function(bool) onChanged;

  /// 锁定：滑块显示锁图标，点击不会改变取值
  final bool locked;

  /// 锁定原因，同时用于悬浮提示与点击提示
  final String? lockedHint;

  const SettingsSwitch({
    required this.value,
    required this.title,
    this.subtitle,
    this.titleStyle,
    required this.onChanged,
    this.locked = false,
    this.lockedHint,
    super.key,
  });

  void _onLockedTap(BuildContext context) {
    final hint = lockedHint;
    if (hint == null || hint.isEmpty) {
      // locked 与 lockedHint 必须成对使用，否则这一行是「能点但毫无反馈」
      // 的静默失败。debug 下直接喊出来，让调用方马上发现。
      assert(false, 'SettingsSwitch: locked 时必须提供 lockedHint，否则点击没有任何反馈');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      Get.snackbar(title, hint, duration: const Duration(seconds: 2));
      return;
    }
    // 用悬浮 SnackBar 而不是 Get.snackbar：后者固定在屏幕顶部，会盖住 AppBar
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(hint),
          behavior: SnackBarBehavior.floating,
          // 固定 420 在窄屏 / 小窗口（可用宽度 < 420）会被压缩成近似全宽，
          // 和「悬浮」的观感不一致；按可用宽度夹一下，长文案也能自适应。
          width: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 420.0),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tile = SwitchListTile(
      title: Text(
        title,
        style: titleStyle ?? theme.textTheme.bodyLarge,
      ),
      contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 8),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: theme.textTheme.bodySmall!.copyWith(color: Colors.grey),
            )
          : null,
      value: value,
      // 锁定时不置空 onChanged：否则整行进入 disabled 语义、点击毫无反馈。
      // 这里只把回调换成提示，取值由外部控制，所以开关不会真的被拨动。
      onChanged: locked ? (_) => _onLockedTap(context) : onChanged,
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
        if (locked) {
          return Icon(
            Icons.lock,
            size: 16,
            color: value ? scheme.primary : scheme.surface,
          );
        }
        if (states.contains(WidgetState.selected)) {
          return Icon(Icons.check, size: 16, color: scheme.primary);
        }
        return null;
      }),
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (locked) {
          return value
              ? scheme.onPrimary
              : scheme.outline.withValues(alpha: 0.55);
        }
        if (states.contains(WidgetState.selected)) {
          return scheme.onPrimary;
        }
        return scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (locked) {
          // 保留「开/关」的色相，只压低饱和与对比度，避免误读成可切换状态
          return value
              ? scheme.primary.withValues(alpha: 0.38)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6);
        }
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return locked
            ? scheme.outline.withValues(alpha: 0.38)
            : scheme.outline;
      }),
    );
    if (locked && lockedHint != null && lockedHint!.isNotEmpty) {
      return Tooltip(
        message: lockedHint!,
        child: tile,
      );
    }
    return tile;
  }
}
