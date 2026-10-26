import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';

class ShadowCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Function()? onTap;
  final Function()? onLongPress;
  const ShadowCard({
    required this.child,
    this.radius = 8.0,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  blurRadius: 4,
                  color: Colors.grey.withAlpha(50),
                )
              ],
      ),
      child: Material(
        // ⚠️ 深色模式下 `Theme.cardColor` 和页面底色**是同一个值**
        // （2026-09-15 实测：卡片正文区和页面底色都是 `#141218`），
        // 而 `boxShadow` 在深色下又被上面关掉了（深色压深色本来就看不见），
        // 于是卡片完全糊在背景里 —— 只有在 hover 时（InkWell 高亮比背景亮）
        // 才看得出轮廓。用户报过这个。
        //
        // 所以深色改用**比 surface 高一档的容器色**，靠明度差分层，
        // 而不是靠阴影。浅色保持原样：白卡 + 外阴影在浅底上本来就分得开。
        color: isDark ? theme.colorScheme.surfaceContainerHigh : theme.cardColor,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onLongPress: onLongPress,
          // 桌面端右键 = 移动端长按，复用同一个回调（见 SecondaryTapRegion 的说明）。
          // InkWell 自带次要点击支持，无需再包一层 GestureDetector。
          onSecondaryTap: onLongPress,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppStyle.radius8,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
