import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/widgets/app_popup_menu_item.dart';

/// 观看历史年份选择：与关注页顶栏菜单同一套 M3 圆角样式。
class WatchYearSelector extends StatelessWidget {
  final List<int> years;
  final int value;
  final ValueChanged<int> onChanged;

  /// 触发器胶囊圆角。必须同时传给 `PopupMenuButton.borderRadius`：
  /// 否则 hover / splash 由内部 InkWell 按矩形区域绘制，会在胶囊外露出一块方角。
  static const BorderRadius _kTriggerRadius = BorderRadius.all(Radius.circular(20));

  const WatchYearSelector({
    super.key,
    required this.years,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<int>(
        key: const ValueKey('watch-year-menu'),
        tooltip: '选择年份',
        // 不传 initialValue：material_ui 会把代表初始值的菜单项包一层
        // 满宽 `Theme.highlightColor`，和 AppPopupMenuItem 的圆角 hover
        // 叠成“外层直角 + 内层圆角”。当前年份已经由触发器文案表达。
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        borderRadius: _kTriggerRadius,
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final year in years)
            AppPopupMenuItem<int>(
              value: year,
              child: Text('$year 年'),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: _kTriggerRadius,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value 年'),
              AppStyle.hGap4,
              Icon(Remix.arrow_down_s_line, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
