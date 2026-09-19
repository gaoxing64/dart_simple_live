import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';

/// M3 Expressive 风格的弹出菜单项（`PopupMenuItem` 的替代品）。
///
/// **为什么需要自己写**：官方 `PopupMenuItem` 内部是裸 `InkWell`
/// （`material_ui/src/popup_menu.dart:461`，没有任何形状参数），所以高亮永远是
/// 贴着菜单容器边的**满宽矩形**。M3 Expressive 的菜单项要求「左右内缩 +
/// 大圆角高亮」（9to5Google 2025-11 的垂直菜单改版：圆角容器、分隔线与选中态
/// 不再占满容器宽度），Flutter 目前只有 baseline 实现，只能自己拼。
///
/// **怎么做**：继承官方的 [PopupMenuItemState] —— `buildChild()` / `handleTap()`
/// 就是官方留给子类的扩展点（`CheckedPopupMenuItem` 走的是同一条路），只重写
/// `build()`。因此交互（点选后 `Navigator.pop` 回传 value、鼠标指针、
/// 语义角色 menuItem、禁用态置灰与透明度）**全部与官方一致**，只把最外层那层
/// `InkWell` 换成内缩 + 圆角版本。
///
/// 规格（状态层色值与 [AppStyle.iconButtonStyle] 同一套口径，保证鼠标划过
/// 菜单项 / 圆形图标按钮时反馈深浅一致）：
/// - 高亮块左右各内缩 8dp（Expressive 的菜单项不贴容器边）
/// - 圆角 [AppStyle.radius16]（形状刻度 large，与菜单容器同一个刻度）
/// - 项高 48dp、内容水平 padding 16dp（对齐官方 M3 的 `menuItemPadding`）
/// - hover 8% / pressed·focused 10%（`onSurfaceVariant`）
///
/// 参数与官方 `PopupMenuItem` 对齐（`value` / `onTap` / `enabled` / `height` /
/// `mouseCursor` / `labelTextStyle` / `child`）；`padding`、`alignment`、
/// `textStyle`（M2 遗留）没有转发 —— 内缩量与对齐是实现的一部分，需要额外
/// 间距请包在 `child` 里。
class AppPopupMenuItem<T> extends PopupMenuItem<T> {
  const AppPopupMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled = true,
    super.height = kMinInteractiveDimension,
    super.mouseCursor,
    super.labelTextStyle,
    required super.child,
  });

  @override
  PopupMenuItemState<T, AppPopupMenuItem<T>> createState() =>
      _AppPopupMenuItemState<T>();
}

class _AppPopupMenuItemState<T>
    extends PopupMenuItemState<T, AppPopupMenuItem<T>> {
  /// 高亮块左右内缩量。
  static const double _kInset = 8;

  /// 内容水平 padding，与官方 M3 的 `_PopupMenuDefaultsM3.menuItemPadding` 一致。
  static const double _kContentPadding = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final popupMenuTheme = PopupMenuTheme.of(context);
    final states = <WidgetState>{if (!widget.enabled) WidgetState.disabled};

    // 与官方 `PopupMenuItemState.build`（`popup_menu.dart:424-428`）同一套三级
    // 回退；末级拿不到私有的 `_PopupMenuDefaultsM3`，直接用 M3 的默认值
    // `TextTheme.labelLarge`（见该字段的文档注释）。
    final labelStyle = widget.labelTextStyle?.resolve(states) ??
        popupMenuTheme.labelTextStyle?.resolve(states) ??
        theme.textTheme.labelLarge ??
        const TextStyle();

    Widget item = AnimatedDefaultTextStyle(
      style: labelStyle,
      duration: kThemeChangeDuration,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kContentPadding),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: buildChild(),
          ),
        ),
      ),
    );

    if (!widget.enabled) {
      item = IconTheme.merge(
        data: IconThemeData(
          opacity: theme.brightness == Brightness.dark ? 0.5 : 0.38,
        ),
        child: item,
      );
    }

    return MergeSemantics(
      child: buildSemantics(
        child: Padding(
          // 内缩：高亮块不贴菜单容器边，这是与 baseline 菜单项最直观的区别。
          padding: const EdgeInsets.symmetric(horizontal: _kInset),
          child: InkWell(
            onTap: widget.enabled ? handleTap : null,
            canRequestFocus: widget.enabled,
            mouseCursor: widget.mouseCursor ??
                popupMenuTheme.mouseCursor?.resolve(states),
            borderRadius: AppStyle.radius16,
            hoverColor: scheme.onSurfaceVariant.withValues(alpha: 0.08),
            highlightColor: scheme.onSurfaceVariant.withValues(alpha: 0.1),
            focusColor: scheme.onSurfaceVariant.withValues(alpha: 0.1),
            child: ListTileTheme.merge(
              contentPadding: EdgeInsets.zero,
              titleTextStyle: labelStyle,
              child: item,
            ),
          ),
        ),
      ),
    );
  }
}
