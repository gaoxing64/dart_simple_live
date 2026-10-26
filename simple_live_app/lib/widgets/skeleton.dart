import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';

/// 骨架屏呼吸动画：0.06 ~ 0.14 的不透明度
const Duration _kPulseDuration = Duration(milliseconds: 900);
const double _kPulseMin = 0.06;
const double _kPulseMax = 0.14;

/// 骨架基色（不透明度由 [_SkeletonPulse] 统一控制）
///
/// 必须走本地的 `Theme.of(context)`：`Get.isDarkMode` 只读当前主题、不建立
/// InheritedWidget 依赖，主题切换后骨架屏不会重建，会一直停在旧配色上。
Color _skeletonBaseColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// 骨架块
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final Color color;
  const SkeletonBox({
    required this.height,
    required this.color,
    this.width,
    this.radius = 4,
    this.borderRadius,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius ?? BorderRadius.circular(radius),
      ),
    );
  }
}

/// 骨架呼吸动画容器：每帧只改变 [child] 的不透明度。
///
/// [child] 只构建一次（交给 `AnimatedBuilder` 的 child 缓存），
/// 因此加载时不会每帧重建整棵骨架子树。
class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kPulseDuration,
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(
    begin: _kPulseMin,
    end: _kPulseMax,
  ).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: child,
      ),
    );
  }
}

/// 直播间卡片骨架，形状与 [LiveRoomCard] 一致（封面 + 标题 + 用户名）
class LiveRoomCardSkeleton extends StatelessWidget {
  const LiveRoomCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = _skeletonBaseColor(context);
    // 脉冲放在卡片壳内部：卡片底色不参与呼吸动画
    return ShadowCard(
      child: _SkeletonPulse(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（与 LiveRoomCard 一致：仅上侧圆角）
            SkeletonBox(
              height: 110,
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            Padding(
              padding: AppStyle.edgeInsetsH8.copyWith(top: 8, bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14, color: color),
                  const SizedBox(height: 8),
                  SkeletonBox(height: 12, width: 96, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表行骨架（缩略图 + 两行文字），用于行高较矮的列表样式条目
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = _skeletonBaseColor(context);
    return ShadowCard(
      child: _SkeletonPulse(
        child: Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Row(
            children: [
              SkeletonBox(height: 48, width: 48, radius: 8, color: color),
              AppStyle.hGap12,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 14, color: color),
                    const SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 120, color: color),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
