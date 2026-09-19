import 'package:material_ui/material_ui.dart';

/// 顶/底栏「滑动收起」的**纯绘制**实现：按 [factor] 把 [child] 整体平移出视野。
///
/// [factor]：`1` = 完全展开（不位移），`0` = 完全收起（平移自身高度）。
///
/// 要点是**只改绘制、不改布局**：
/// * 位移用 [FractionalTranslation]（相对自身尺寸的比例，所以调用方不必知道栏有多高），
///   盒子尺寸始终等于子节点尺寸 —— 父级（`Scaffold.bottomNavigationBar` 槽位、
///   页面 `Stack`）**不会**因为收起动画而重新布局，滚动列表也不会被重排。
/// * [ClipRect] 负责裁掉滑出视野的部分，它的裁剪矩形就是自身尺寸（常量），
///   与 [factor] 无关，因此每帧只有一次矩阵更新。
///
/// 为什么不用「真实改变高度」的写法（原来的 `CollapseSlot` 用
/// `Align(heightFactor:)`）：那会让每个滚动帧都发生一次真实布局 —— 父级重排、
/// 列表视口变化、栏内 `Material` 的高度/阴影/指示器跟着变。同步模式是**每一帧**
/// 都在改这个值，在安卓上表现为明显的掉帧；改成平移后同样的跟手效果只剩一次
/// 绘制矩阵更新。
class BarCollapse extends StatelessWidget {
  const BarCollapse({
    super.key,
    required this.factor,
    required this.fromTop,
    required this.child,
  });

  /// `1` = 完全展开，`0` = 完全收起。超出范围会被夹紧。
  final double factor;

  /// 顶栏（向上滑出）传 `true`，底栏（向下滑出）传 `false`。
  final bool fromTop;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = factor.clamp(0.0, 1.0);
    // 取自身尺寸的比例：顶栏收起时向上（负值），底栏收起时向下（正值）。
    final dy = fromTop ? f - 1 : 1 - f;
    return ClipRect(
      child: FractionalTranslation(
        translation: Offset(0, dy),
        child: child,
      ),
    );
  }
}
