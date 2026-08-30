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
//   * 开启 [FloatingNavigationBar.liquidGlass] 后，胶囊背景会换成透明折射玻璃；
//   * 布局、指示器、交互仍然全部走本文件（悬浮胶囊）的实现。

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:material_ui/material_ui.dart';

const double _kMaxLabelTextScaleFactor = 1.3;

/// 胶囊高度（不含底部安全区与 [FloatingNavigationBar.bottomPadding]）
const double kFloatingNavBarHeight = 64.0;

/// 胶囊与屏幕底部的默认间距（叠加在安全区之上）
const double kFloatingNavBarBottomPadding = 8.0;

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

/// Liquid Glass 背景形状：与胶囊圆角一致
const glass.LiquidShape _kLiquidGlassShape = glass.LiquidRoundedSuperellipse(
  borderRadius: kFloatingNavBarHeight / 2,
);

/// 默认玻璃参数，与旧版 [glass.GlassTabBar.bottom] 的 kBottomBarGlassDefaults 保持一致
const glass.LiquidGlassSettings _kDefaultLiquidGlassSettings =
    glass.LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  glassColor: Color(0x3DFFFFFF),
);

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
    this.liquidGlassSettings,
    this.liquidGlassQuality = glass.GlassQuality.premium,
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

  /// 是否把胶囊背景换成 Liquid Glass 透明折射效果（实验性）
  ///
  /// 布局、指示器与交互不受影响，始终使用悬浮胶囊自身的实现。
  final bool liquidGlass;

  /// Liquid Glass 参数；为空时使用 [_kDefaultLiquidGlassSettings]
  final glass.LiquidGlassSettings? liquidGlassSettings;

  /// Liquid Glass 渲染质量；默认 [glass.GlassQuality.premium]，
  /// 与旧版悬浮玻璃导航栏保持一致（非 Impeller 平台会自动降级）
  final glass.GlassQuality liquidGlassQuality;

  VoidCallback _handleTap(int index) {
    return onDestinationSelected != null
        ? () => onDestinationSelected!(index)
        : () {};
  }

  /// 解析实际使用的玻璃质量：遵循上层 [glass.GlassAdaptiveScope] 的降级上限
  glass.GlassQuality _resolveLiquidGlassQuality(BuildContext context) {
    final ceiling =
        glass.GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    if (ceiling == null) {
      return liquidGlassQuality;
    }
    int rank(glass.GlassQuality quality) => switch (quality) {
          glass.GlassQuality.minimal => 0,
          glass.GlassQuality.standard => 1,
          glass.GlassQuality.premium => 2,
        };
    return rank(liquidGlassQuality) <= rank(ceiling)
        ? liquidGlassQuality
        : ceiling;
  }

  @override
  Widget build(BuildContext context) {
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

    // 玻璃模式只替换背景，胶囊的布局/指示器/交互保持不变
    final Widget surface = liquidGlass
        ? glass.AdaptiveGlass(
            shape: _kLiquidGlassShape,
            settings: liquidGlassSettings ?? _kDefaultLiquidGlassSettings,
            quality: _resolveLiquidGlassQuality(context),
            child: content,
          )
        : DecoratedBox(
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
        bottomPadding + padding.bottom,
      ),
      child: SizedBox(
        height: kFloatingNavBarHeight,
        width: destinations.length * _kIndicatorWidth,
        child: surface,
      ),
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
