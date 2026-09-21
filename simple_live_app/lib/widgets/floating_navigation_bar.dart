// 悬浮胶囊导航栏（Floating Navigation Bar）
//
// 移植自 PiliPlus / PiliNara 的 lib/common/widgets/floating_navigation_bar.dart，
// 该文件本身 fork 自 Flutter 的 NavigationBar（BSD-3-Clause, The Flutter Authors）。
//
// 与原版的差异：
//   * 去掉 PiliPlus 的 theme_ext 依赖，深浅色判断改用 ColorScheme.brightness；
//   * 按本项目风格书写（显式枚举/常量、包内 import 顺序）。
//
// 它自身不占布局空间（Padding + SizedBox），并按内容宽度自适应：
// 调用方用 Scaffold.bottomNavigationBar 或 Stack/Positioned 把它叠在内容之上，
// 但要保证宽度约束是松的（例如外面套 Center(heightFactor: 1)），
// 否则在 Scaffold 底栏槽位的紧约束下会被拉伸成整屏宽度，
// 用法见 modules/indexed/indexed_page.dart。
//
// Liquid Glass（实验性）：
//   * 开启 [FloatingNavigationBar.liquidGlass] 后，整条底栏（胶囊背景 + 图标 +
//     文字 + 选中指示器）交给 liquid_glass_easy 的包内组件绘制，
//     本文件的悬浮胶囊实现不再参与布局；
//   * 因此下面的 `_NavigationBarDefaultsM3` / `NavigationIndicator` / 布局
//     delegate 那一整套只在非玻璃分支生效。

import 'package:flutter/material.dart' as material show Theme, ThemeData;
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as glass;
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';
import 'package:simple_live_app/widgets/liquid_glass_nav_defaults.dart';

const double _kMaxLabelTextScaleFactor = 1.3;

/// 胶囊高度（不含底部安全区与 [FloatingNavigationBar.bottomPadding]）
const double kFloatingNavBarHeight = 64.0;

/// 胶囊与屏幕底部的默认间距（叠加在安全区之上）
const double kFloatingNavBarBottomPadding = 8.0;

/// Liquid Glass 版胶囊的默认内边距。
///
/// 6 是 liquid_glass_easy 自己调校的默认值（药丸高度 / 胶囊高度 ≈ 0.81），
/// 与参考图的观感基本一致。取值本身在 [LiquidGlassNavDefaults.itemPadding]。
const double kFloatingNavBarLiquidGlassItemPadding =
    LiquidGlassNavDefaults.itemPadding;

const double _kIndicatorPaddingInt = 4.0;
const double _kIndicatorHeight =
    kFloatingNavBarHeight - 2 * _kIndicatorPaddingInt;
const double _kIndicatorWidth = 86.0;
const EdgeInsets _kIndicatorPadding = EdgeInsets.all(_kIndicatorPaddingInt);
const BorderRadius _kBorderRadius = BorderRadius.all(
  Radius.circular(kFloatingNavBarHeight / 2),
);
const ShapeBorder _kNavigationShape = RoundedSuperellipseBorder(
  borderRadius: _kBorderRadius,
);

// ── 玻璃参数默认值 ───────────────────────────────────────────────
//
// 数值本身只有一份，收在 [LiquidGlassNavDefaults] 里（调试页参数表的 `initial`
// 读的也是同一个地方），本文件只负责把它们取出来当默认样式用 ——
// 所以「调试页重置」与「线上渲染」不会再各存一份数字而静默漂移。

/// 取出 [Icon] 的 [IconData]；不是 [Icon]（或为 null）时返回 null。
IconData? _iconDataOf(Widget? widget) => widget is Icon ? widget.icon : null;

/// 底栏子树用的 `flutter/material` 主题（带缓存）。
///
/// 三个作用，根因是同一个：**本项目 UI 走 `material_ui`，包内走
/// `flutter/material`，两套 `Theme` / `ThemeData` 不是同一个类型** ——
/// 包内 `Theme.of` 找不到祖先，会退回**亮色**兜底主题。
///
/// 1. **把 InkWell 的 ink 清成透明**：否则包内 tap 层会在深色玻璃上画出
///    一块 40% 浅灰的圆角块，压在选中药丸**之上**，看着像两个指示器。
/// 2. **把外观设置里选的字体带进去**：包内 `Material` 提供的
///    `DefaultTextStyle` 用的是兜底主题（`fontFamily = null`），
///    于是底栏文字掉回系统默认字体；包内 `LiquidGlassLabel.textStyle` 没有
///    `inherit: false`，所以只要这里的字体对了，标签就会跟着对。
/// 3. **把真实亮度带进去**：兜底主题恒为亮色，而包里取兜底亮度的地方
///    （`liquidGlassFallbackBrightness` 就是读 `Theme.of(context).brightness`）
///    会因此永远按亮色档走 —— 深色模式下包内一切未被显式覆盖的按亮度取值的
///    默认项都会错档。补上亮度后，包内自建的 ColorScheme 也跟着对。
///
/// [fontFamily] 取自调用方自己的主题（`AppStyle.light/darkTheme(fontFamily:)`
/// 用的是 `fontFamily` 参数与 `textTheme.apply(fontFamily:)` 两种写法，
/// 读 `bodyMedium.fontFamily` 两种都能覆盖到）。
///
/// 按 (fontFamily, brightness) 缓存：`ThemeData` 构造不便宜，底栏却会被频繁重建。
material.ThemeData? _cachedBarThemeData;
String? _cachedBarFontFamily;
Brightness? _cachedBarBrightness;

material.ThemeData _barThemeData(String? fontFamily, Brightness brightness) {
  if (_cachedBarThemeData != null &&
      _cachedBarFontFamily == fontFamily &&
      _cachedBarBrightness == brightness) {
    return _cachedBarThemeData!;
  }
  _cachedBarFontFamily = fontFamily;
  _cachedBarBrightness = brightness;
  return _cachedBarThemeData = material.ThemeData(
    brightness: brightness,
    hoverColor: Colors.transparent,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    fontFamily: fontFamily,
  );
}

/// ref [NavigationBar]
class FloatingNavigationBar extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  FloatingNavigationBar({
    super.key,
    this.animationDuration = const Duration(milliseconds: 500),
    this.selectedIndex = 0,
    required this.destinations,
    this.onDestinationSelected,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.indicatorColor,
    this.indicatorShape,
    this.labelBehavior,
    this.overlayColor,
    this.labelTextStyle,
    this.labelPadding,
    this.bottomPadding = kFloatingNavBarBottomPadding,
    this.liquidGlass = false,
    this.liquidGlassStyle,
    this.liquidGlassItemStyle,
    this.liquidGlassPillStyle,
    this.liquidGlassItemPadding = kFloatingNavBarLiquidGlassItemPadding,
  })  : assert(destinations.length >= 2),
        assert(0 <= selectedIndex && selectedIndex < destinations.length);

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Color? indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;

  /// 是否把整条底栏换成 Liquid Glass 透明折射效果（实验性）
  ///
  /// 开启后胶囊背景、图标文字、选中指示器（药丸）全部由
  /// `liquid_glass_easy` 的 [glass.LiquidGlassTabBar] 绘制，
  /// 本文件下面那套悬浮胶囊实现不再参与布局；
  /// 下面的 `backgroundColor` / `elevation` / `indicatorColor` /
  /// `labelBehavior` / `labelTextStyle` … 在玻璃模式下**不会生效**。
  final bool liquidGlass;

  /// 胶囊本体的玻璃外观（形状 + 填充/模糊 + 折射）。
  ///
  /// 为空时用 [LiquidGlassNavDefaults.defaultBarStyle]
  /// （以 [glass.LiquidGlassTabBar.defaultStyle] 为底再补一层接触阴影，
  /// 形状留空 —— 包会按胶囊高度自适应出完整胶囊轮廓）。
  final glass.LiquidGlassStyle? liquidGlassStyle;

  /// 图标与文字的样式（颜色、字号、间距）。
  ///
  /// 为空时用 [defaultLiquidGlassItemStyle]：颜色按当前 [ColorScheme] 推导
  /// （选中取 `primary`，未选中取 `onSurfaceVariant`），尺寸与间距取
  /// [LiquidGlassNavDefaults]。
  final glass.LiquidGlassTabItemStyle? liquidGlassItemStyle;

  /// 选中指示器（药丸）的样式：填充色、是否滑动、滑动时长与曲线。
  ///
  /// 为空时用 [defaultLiquidGlassPillStyle]：按当前主题亮度取基底色
  /// （浅色 [#AEAEB2]，深色白），并开启滑动动画。
  final glass.LiquidGlassTabPillStyle? liquidGlassPillStyle;

  /// 胶囊内边距：胶囊轮廓与图标行之间的距离。
  ///
  /// 它是「药丸高度 / 胶囊高度」这个比例的主控 —— 调小药丸更满，调大更松，
  /// 是照着参考图对齐观感时最直接的一个旋钮。
  final double liquidGlassItemPadding;

  // ── 玻璃模式的默认样式 ─────────────────────────────────────────
  //
  // 默认值本身只有一份（[LiquidGlassNavDefaults]），调试页的参数表读的也是那里，
  // 并用同一段 build* 代码构造样式 —— 所以这几个 getter 与调试页在默认值下
  // 必然一致，test/glass_debug_page_test.dart 有用例锁住这点。

  /// 未传 [liquidGlassStyle] 时用的胶囊玻璃外观。
  static glass.LiquidGlassStyle get defaultLiquidGlassBarStyle =>
      LiquidGlassNavDefaults.defaultBarStyle;

  /// 未传 [liquidGlassItemStyle] 时用的图标文字样式。
  static glass.LiquidGlassTabItemStyle defaultLiquidGlassItemStyle({
    required Color selectedColor,
    required Color unselectedColor,
  }) =>
      LiquidGlassNavDefaults.defaultItemStyle(
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
      );

  /// 未传 [liquidGlassPillStyle] 时用的选中药丸样式。
  static glass.LiquidGlassTabPillStyle defaultLiquidGlassPillStyle(
    Brightness brightness,
  ) =>
      LiquidGlassNavDefaults.defaultPillStyle(brightness);

  VoidCallback _handleTap(int index) {
    return onDestinationSelected != null
        ? () => onDestinationSelected!(index)
        : () {};
  }

  @override
  Widget build(BuildContext context) {
    // 玻璃模式：整条底栏由 LiquidGlassTabBar 自己绘制，提前返回
    if (liquidGlass) {
      return _buildLiquidGlassBar(context);
    }

    final defaults = _NavigationBarDefaultsM3(context);

    final navigationBarTheme = NavigationBarTheme.of(context);
    final effectiveLabelBehavior = labelBehavior ??
        navigationBarTheme.labelBehavior ??
        defaults.labelBehavior!;

    final padding = MediaQuery.viewPaddingOf(context);

    final Widget content = Padding(
      padding: _kIndicatorPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < destinations.length; i++)
            Expanded(
              child: _SelectableAnimatedBuilder(
                duration: animationDuration,
                isSelected: i == selectedIndex,
                builder: (context, animation) {
                  return _NavigationDestinationInfo(
                    index: i,
                    selectedIndex: selectedIndex,
                    totalNumberOfDestinations: destinations.length,
                    selectedAnimation: animation,
                    labelBehavior: effectiveLabelBehavior,
                    indicatorColor: indicatorColor,
                    indicatorShape: indicatorShape,
                    overlayColor: overlayColor,
                    onTap: _handleTap(i),
                    labelTextStyle: labelTextStyle,
                    labelPadding: labelPadding,
                    child: destinations[i],
                  );
                },
              ),
            ),
        ],
      ),
    );

    final Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        color: ElevationOverlay.applySurfaceTint(
          backgroundColor ??
              navigationBarTheme.backgroundColor ??
              defaults.backgroundColor!,
          surfaceTintColor ??
              navigationBarTheme.surfaceTintColor ??
              defaults.surfaceTintColor,
          elevation ??
              navigationBarTheme.elevation ??
              defaults.elevation!,
        ),
        shape: RoundedSuperellipseBorder(
          side: defaults.borderSide,
          borderRadius: _kBorderRadius,
        ),
      ),
      child: content,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        // 退出全屏后部分设备不再上报恢复后的系统栏高度，交给 SystemUiBottomInset 兜底
        bottomPadding +
            SystemUiBottomInset.resolve(
              padding.bottom,
              viewSize: MediaQuery.sizeOf(context),
            ),
      ),
      child: SizedBox(
        height: kFloatingNavBarHeight,
        width: destinations.length * _kIndicatorWidth,
        child: surface,
      ),
    );
  }

  /// Liquid Glass 分支：底栏整体交给 liquid_glass_easy 的
  /// [glass.LiquidGlassTabBar]。
  ///
  /// 这里刻意用**不带** `withImpeller` 的那个构造。它返回的是个普通盒子
  /// （`SizedBox` 包 `LiquidGlassLens`），可以直接待在
  /// `Scaffold.bottomNavigationBar` 槽位里，也就还能继续被 `BarCollapse`
  /// 平移 + 裁剪（见 [IndexedPage]）。`withImpeller` 变体是铺满全屏的透明浮层，
  /// 要求自己当 `Stack` 的最后一个孩子，与本页「底栏进槽位 + 收起动画」的
  /// 架构不兼容。
  ///
  /// 渲染差异：Impeller（Android / iOS）上独立摆放的 lens 直接采样实时背景，
  /// 折射照常生效；Skia（Windows / Linux / Web）没有实时背景可采，包内部会自行
  /// 退化成磨砂（真实模糊 + 染色 + 描边），不会崩也不会画出黑块。
  Widget _buildLiquidGlassBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);
    final width = destinations.length * _kIndicatorWidth;
    // 外观里选的字体挂在 material_ui 的主题上，包内读不到 —— 取出来带进去
    // （见 [_barThemeData]）
    final fontFamily = theme.textTheme.bodyMedium?.fontFamily;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        // 退出全屏后部分设备不再上报恢复后的系统栏高度，交给 SystemUiBottomInset 兜底
        bottomPadding +
            SystemUiBottomInset.resolve(
              padding.bottom,
              viewSize: MediaQuery.sizeOf(context),
            ),
      ),
      child: SizedBox(
        height: kFloatingNavBarHeight,
        width: width,
        // 见 [_barThemeData]：清掉 ink + 带上外观里选的字体与主题亮度
        child: material.Theme(
          data: _barThemeData(fontFamily, colors.brightness),
          child: glass.LiquidGlassTabBar(
            items: [
              for (final destination in destinations)
                liquidGlassItemFor(destination),
            ],
            selectedIndex: selectedIndex,
            // 玻璃模式同样尊重 destination 的 enabled：非玻璃分支靠
            // _NavigationDestinationBuilder 的 `onTap: enabled ? ... : null`
            // 让禁用的入口点不动，这里得自己过滤，否则两个分支行为分歧。
            onChanged: (index) {
              final destination = destinations[index];
              if (destination is FloatingNavigationDestination &&
                  !destination.enabled) {
                return;
              }
              onDestinationSelected?.call(index);
            },
            width: width,
            height: kFloatingNavBarHeight,
            itemPadding: liquidGlassItemPadding,
            style: liquidGlassStyle ?? defaultLiquidGlassBarStyle,
            itemStyle: liquidGlassItemStyle ??
                defaultLiquidGlassItemStyle(
                  selectedColor: colors.primary,
                  unselectedColor: colors.onSurfaceVariant,
                ),
            pillStyle: liquidGlassPillStyle ??
                defaultLiquidGlassPillStyle(colors.brightness),
          ),
        ),
      ),
    );
  }

  /// 把悬浮胶囊的 destination 翻译成 Liquid Glass 底栏的标签项。
  ///
  /// 图标是 [Icon]（本项目的常态，见 [IndexedPage]）时取它的 [IconData] 走包的
  /// 原生图标路径，白拿「选中态换图标 / 换色」；其它自绘 widget
  /// （SVG / 图片 / CustomPaint）交给 `iconBuilder` —— 包的
  /// [glass.LiquidGlassGlyph] 会给出 `selected`，所以自绘图标也按它切
  /// `selectedIcon`，规则与包自己的原生路径（`selected ? selectedIcon ?? icon : icon`）
  /// 一致，否则与非玻璃分支（`selectedIcon ?? icon`）观感不一致。
  ///
  /// 公开（而不是私有实例方法）是为了让测试能直接验这条转换：包的底栏会把每个
  /// cell 在选中/未选中两种状态下都预先建好多层，靠 widget 树数不出「选中态换了图」。
  static glass.LiquidGlassTabBarItem liquidGlassItemFor(Widget destination) {
    if (destination is! FloatingNavigationDestination) {
      return glass.LiquidGlassTabBarItem(
        iconBuilder: (context, glyph) => IconTheme.merge(
          data: IconThemeData(color: glyph.color, size: glyph.size),
          child: destination,
        ),
      );
    }
    final iconData = _iconDataOf(destination.icon);
    if (iconData == null) {
      final icon = destination.icon;
      final selectedIcon = destination.selectedIcon;
      return glass.LiquidGlassTabBarItem(
        label: destination.label,
        iconBuilder: (context, glyph) => IconTheme.merge(
          data: IconThemeData(color: glyph.color, size: glyph.size),
          child: glyph.selected ? (selectedIcon ?? icon) : icon,
        ),
      );
    }
    return glass.LiquidGlassTabBarItem(
      icon: iconData,
      selectedIcon: _iconDataOf(destination.selectedIcon),
      label: destination.label,
    );
  }
}

class FloatingNavigationDestination extends StatelessWidget {
  const FloatingNavigationDestination({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.enabled = true,
  });

  final Widget icon;

  final Widget? selectedIcon;

  final String label;

  final String? tooltip;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final info = _NavigationDestinationInfo.of(context);
    const selectedState = <WidgetState>{WidgetState.selected};
    const unselectedState = <WidgetState>{};
    const disabledState = <WidgetState>{WidgetState.disabled};

    final navigationBarTheme = NavigationBarTheme.of(context);
    final defaults = _NavigationBarDefaultsM3(context);
    final animation = info.selectedAnimation;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        NavigationIndicator(
          animation: animation,
          color: info.indicatorColor ??
              navigationBarTheme.indicatorColor ??
              defaults.indicatorColor!,
        ),
        _NavigationDestinationBuilder(
          label: label,
          tooltip: tooltip,
          enabled: enabled,
          buildIcon: (context) {
            final IconThemeData selectedIconTheme =
                navigationBarTheme.iconTheme?.resolve(selectedState) ??
                    defaults.iconTheme!.resolve(selectedState)!;
            final IconThemeData unselectedIconTheme =
                navigationBarTheme.iconTheme?.resolve(unselectedState) ??
                    defaults.iconTheme!.resolve(unselectedState)!;
            final IconThemeData disabledIconTheme =
                navigationBarTheme.iconTheme?.resolve(disabledState) ??
                    defaults.iconTheme!.resolve(disabledState)!;

            final Widget selectedIconWidget = IconTheme.merge(
              data: enabled ? selectedIconTheme : disabledIconTheme,
              child: selectedIcon ?? icon,
            );
            final Widget unselectedIconWidget = IconTheme.merge(
              data: enabled ? unselectedIconTheme : disabledIconTheme,
              child: icon,
            );
            return _StatusTransitionWidgetBuilder(
              animation: animation,
              builder: (context, child) {
                return animation.isForwardOrCompleted
                    ? selectedIconWidget
                    : unselectedIconWidget;
              },
            );
          },
          buildLabel: (context) {
            final TextStyle? effectiveSelectedLabelTextStyle =
                info.labelTextStyle?.resolve(selectedState) ??
                    navigationBarTheme.labelTextStyle?.resolve(selectedState) ??
                    defaults.labelTextStyle!.resolve(selectedState);
            final TextStyle? effectiveUnselectedLabelTextStyle = info
                    .labelTextStyle
                    ?.resolve(unselectedState) ??
                navigationBarTheme.labelTextStyle?.resolve(unselectedState) ??
                defaults.labelTextStyle!.resolve(unselectedState);
            final TextStyle? effectiveDisabledLabelTextStyle =
                info.labelTextStyle?.resolve(disabledState) ??
                    navigationBarTheme.labelTextStyle?.resolve(disabledState) ??
                    defaults.labelTextStyle!.resolve(disabledState);
            final EdgeInsetsGeometry labelPadding = info.labelPadding ??
                navigationBarTheme.labelPadding ??
                defaults.labelPadding!;

            final textStyle = enabled
                ? animation.isForwardOrCompleted
                    ? effectiveSelectedLabelTextStyle
                    : effectiveUnselectedLabelTextStyle
                : effectiveDisabledLabelTextStyle;

            return Padding(
              padding: labelPadding,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _kMaxLabelTextScaleFactor,
                child: Text(label, style: textStyle),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NavigationDestinationBuilder extends StatefulWidget {
  const _NavigationDestinationBuilder({
    required this.buildIcon,
    required this.buildLabel,
    required this.label,
    this.tooltip,
    this.enabled = true,
  });

  final WidgetBuilder buildIcon;

  final WidgetBuilder buildLabel;

  final String label;

  final String? tooltip;

  final bool enabled;

  @override
  State<_NavigationDestinationBuilder> createState() =>
      _NavigationDestinationBuilderState();
}

class _NavigationDestinationBuilderState
    extends State<_NavigationDestinationBuilder> {
  final GlobalKey iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final info = _NavigationDestinationInfo.of(context);

    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? info.onTap : null,
      child: _NavigationBarDestinationLayout(
        icon: widget.buildIcon(context),
        iconKey: iconKey,
        label: widget.buildLabel(context),
      ),
    );
    if (info.labelBehavior == NavigationDestinationLabelBehavior.alwaysShow) {
      return child;
    }
    return _NavigationBarDestinationTooltip(
      message: widget.tooltip ?? widget.label,
      child: child,
    );
  }
}

class _NavigationDestinationInfo extends InheritedWidget {
  const _NavigationDestinationInfo({
    required this.index,
    required this.selectedIndex,
    required this.totalNumberOfDestinations,
    required this.selectedAnimation,
    required this.labelBehavior,
    required this.indicatorColor,
    required this.indicatorShape,
    required this.overlayColor,
    required this.onTap,
    this.labelTextStyle,
    this.labelPadding,
    required super.child,
  });

  final int index;

  final int selectedIndex;

  final int totalNumberOfDestinations;

  final Animation<double> selectedAnimation;

  final NavigationDestinationLabelBehavior labelBehavior;

  final Color? indicatorColor;

  final ShapeBorder? indicatorShape;

  final WidgetStateProperty<Color?>? overlayColor;

  final VoidCallback onTap;

  final WidgetStateProperty<TextStyle?>? labelTextStyle;

  final EdgeInsetsGeometry? labelPadding;

  static _NavigationDestinationInfo of(BuildContext context) {
    final _NavigationDestinationInfo? result = context
        .dependOnInheritedWidgetOfExactType<_NavigationDestinationInfo>();
    assert(
      result != null,
      'Navigation destinations need a _NavigationDestinationInfo parent, '
      'which is usually provided by FloatingNavigationBar.',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(_NavigationDestinationInfo oldWidget) {
    return index != oldWidget.index ||
        totalNumberOfDestinations != oldWidget.totalNumberOfDestinations ||
        selectedAnimation != oldWidget.selectedAnimation ||
        labelBehavior != oldWidget.labelBehavior ||
        onTap != oldWidget.onTap;
  }
}

class NavigationIndicator extends StatelessWidget {
  const NavigationIndicator({
    super.key,
    required this.animation,
    this.color,
    this.width = _kIndicatorWidth,
    this.height = _kIndicatorHeight,
  });

  final Animation<double> animation;

  final Color? color;

  final double width;

  final double height;

  static final _anim = Tween<double>(
    begin: 0.5,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.easeInOutCubicEmphasized));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double scale =
            animation.isDismissed ? 0.0 : _anim.evaluate(animation);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(scale, 1.0, 1.0),
          child: child,
        );
      },
      child: _StatusTransitionWidgetBuilder(
        animation: animation,
        builder: (context, child) {
          return _SelectableAnimatedBuilder(
            isSelected: animation.isForwardOrCompleted,
            duration: const Duration(milliseconds: 100),
            alwaysDoFullAnimation: true,
            builder: (context, fadeAnimation) {
              return FadeTransition(
                opacity: fadeAnimation,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: _kNavigationShape,
                    color: color ?? Theme.of(context).colorScheme.secondary,
                  ),
                  child: const SizedBox(
                    width: _kIndicatorWidth,
                    height: _kIndicatorHeight,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NavigationBarDestinationLayout extends StatelessWidget {
  const _NavigationBarDestinationLayout({
    required this.icon,
    required this.iconKey,
    required this.label,
  });

  final Widget icon;

  final GlobalKey iconKey;

  final Widget label;

  @override
  Widget build(BuildContext context) {
    return _DestinationLayoutAnimationBuilder(
      builder: (context, animation) {
        return CustomMultiChildLayout(
          delegate: _NavigationDestinationLayoutDelegate(animation: animation),
          children: <Widget>[
            LayoutId(
              id: _NavigationDestinationLayoutDelegate.iconId,
              child: KeyedSubtree(key: iconKey, child: icon),
            ),
            LayoutId(
              id: _NavigationDestinationLayoutDelegate.labelId,
              child: FadeTransition(
                alwaysIncludeSemantics: true,
                opacity: animation,
                child: label,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DestinationLayoutAnimationBuilder extends StatelessWidget {
  const _DestinationLayoutAnimationBuilder({required this.builder});

  final Widget Function(BuildContext, Animation<double>) builder;

  @override
  Widget build(BuildContext context) {
    final info = _NavigationDestinationInfo.of(context);
    switch (info.labelBehavior) {
      case NavigationDestinationLabelBehavior.alwaysShow:
        return builder(context, kAlwaysCompleteAnimation);
      case NavigationDestinationLabelBehavior.alwaysHide:
        return builder(context, kAlwaysDismissedAnimation);
      case NavigationDestinationLabelBehavior.onlyShowSelected:
        return _CurvedAnimationBuilder(
          animation: info.selectedAnimation,
          curve: Curves.easeInOutCubicEmphasized,
          reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
          builder: builder,
        );
    }
  }
}

class _NavigationBarDestinationTooltip extends StatelessWidget {
  const _NavigationBarDestinationTooltip({
    required this.message,
    required this.child,
  });

  final String message;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      verticalOffset: 34,
      excludeFromSemantics: true,
      preferBelow: false,
      child: child,
    );
  }
}

class _NavigationDestinationLayoutDelegate extends MultiChildLayoutDelegate {
  _NavigationDestinationLayoutDelegate({required this.animation})
      : super(relayout: animation);

  final Animation<double> animation;

  static const int iconId = 1;

  static const int labelId = 2;

  @override
  void performLayout(Size size) {
    double halfWidth(Size size) => size.width / 2;
    double halfHeight(Size size) => size.height / 2;

    final Size iconSize = layoutChild(iconId, BoxConstraints.loose(size));
    final Size labelSize = layoutChild(labelId, BoxConstraints.loose(size));

    final double yPositionOffset = Tween<double>(
      begin: halfHeight(iconSize),
      end: halfHeight(iconSize) + halfHeight(labelSize),
    ).transform(animation.value);
    final double iconYPosition = halfHeight(size) - yPositionOffset;

    positionChild(
      iconId,
      Offset(
        halfWidth(size) - halfWidth(iconSize),
        iconYPosition,
      ),
    );

    positionChild(
      labelId,
      Offset(
        halfWidth(size) - halfWidth(labelSize),
        iconYPosition + iconSize.height,
      ),
    );
  }

  @override
  bool shouldRelayout(_NavigationDestinationLayoutDelegate oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

class _StatusTransitionWidgetBuilder extends StatusTransitionWidget {
  const _StatusTransitionWidgetBuilder({
    required super.animation,
    required this.builder,
    // ignore: unused_element_parameter
    this.child,
  });

  final TransitionBuilder builder;

  final Widget? child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}

class _SelectableAnimatedBuilder extends StatefulWidget {
  const _SelectableAnimatedBuilder({
    required this.isSelected,
    this.duration = const Duration(milliseconds: 200),
    this.alwaysDoFullAnimation = false,
    required this.builder,
  });

  final bool isSelected;

  final Duration duration;

  final bool alwaysDoFullAnimation;

  final Widget Function(BuildContext, Animation<double>) builder;

  @override
  _SelectableAnimatedBuilderState createState() =>
      _SelectableAnimatedBuilderState();
}

class _SelectableAnimatedBuilderState extends State<_SelectableAnimatedBuilder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.duration = widget.duration;
    _controller.value = widget.isSelected ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(_SelectableAnimatedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        _controller.forward(from: widget.alwaysDoFullAnimation ? 0 : null);
      } else {
        _controller.reverse(from: widget.alwaysDoFullAnimation ? 1 : null);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}

class _CurvedAnimationBuilder extends StatefulWidget {
  const _CurvedAnimationBuilder({
    required this.animation,
    required this.curve,
    required this.reverseCurve,
    required this.builder,
  });

  final Animation<double> animation;
  final Curve curve;
  final Curve reverseCurve;
  final Widget Function(BuildContext, Animation<double>) builder;

  @override
  _CurvedAnimationBuilderState createState() => _CurvedAnimationBuilderState();
}

class _CurvedAnimationBuilderState extends State<_CurvedAnimationBuilder> {
  late AnimationStatus _animationDirection;
  AnimationStatus? _preservedDirection;

  @override
  void initState() {
    super.initState();
    _animationDirection = widget.animation.status;
    _updateStatus(widget.animation.status);
    widget.animation.addStatusListener(_updateStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_updateStatus);
    super.dispose();
  }

  void _updateStatus(AnimationStatus status) {
    if (_animationDirection != status) {
      setState(() {
        _animationDirection = status;
      });
    }
    switch (status) {
      case AnimationStatus.forward || AnimationStatus.reverse
          when _preservedDirection != null:
        break;
      case AnimationStatus.forward || AnimationStatus.reverse:
        setState(() {
          _preservedDirection = status;
        });
      case AnimationStatus.completed || AnimationStatus.dismissed:
        setState(() {
          _preservedDirection = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shouldUseForwardCurve =
        (_preservedDirection ?? _animationDirection) != AnimationStatus.reverse;

    final Animation<double> curvedAnimation = CurveTween(
      curve: shouldUseForwardCurve ? widget.curve : widget.reverseCurve,
    ).animate(widget.animation);

    return widget.builder(context, curvedAnimation);
  }
}

const _indicatorDark = Color(0x15FFFFFF);
const _indicatorLight = Color(0x10000000);

class _NavigationBarDefaultsM3 extends NavigationBarThemeData {
  _NavigationBarDefaultsM3(this.context)
      : super(
          height: kFloatingNavBarHeight,
          elevation: 3.0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        );

  final BuildContext context;
  late final _colors = Theme.of(context).colorScheme;
  late final _textTheme = Theme.of(context).textTheme;

  bool get _isDark => _colors.brightness == Brightness.dark;

  BorderSide get borderSide => _isDark
      ? const BorderSide(color: Color(0x08FFFFFF))
      : const BorderSide(color: Color(0x08000000));

  @override
  Color? get backgroundColor => _colors.surfaceContainer;

  @override
  Color? get shadowColor => Colors.transparent;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  WidgetStateProperty<IconThemeData?>? get iconTheme {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return IconThemeData(
        size: 24.0,
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.withValues(alpha: 0.38)
            : states.contains(WidgetState.selected)
                ? _colors.onSecondaryContainer
                : _colors.onSurfaceVariant,
      );
    });
  }

  @override
  Color? get indicatorColor => _isDark ? _indicatorDark : _indicatorLight;

  @override
  ShapeBorder? get indicatorShape => const StadiumBorder();

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final TextStyle style = _textTheme.labelMedium!;
      return style.apply(
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.withValues(alpha: 0.38)
            : states.contains(WidgetState.selected)
                ? _colors.onSurface
                : _colors.onSurfaceVariant,
      );
    });
  }

  @override
  EdgeInsetsGeometry? get labelPadding => const EdgeInsets.only(top: 2);
}
