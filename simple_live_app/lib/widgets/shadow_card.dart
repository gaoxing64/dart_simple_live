import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Get.isDarkMode
            ? []
            : [
                BoxShadow(
                  blurRadius: 4,
                  color: Colors.grey.withAlpha(50),
                )
              ],
      ),
      child: Material(
        color: Theme.of(context).cardColor,
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
