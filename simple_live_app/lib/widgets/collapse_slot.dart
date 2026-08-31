import 'package:material_ui/material_ui.dart';

/// 顶/底栏收起容器：按 [factor]（1=完全展开，0=完全收起）裁剪显示内容，
/// 内容始终按自然高度布局，超出部分被裁剪掉。
///
/// [alignment] 决定保留哪一侧：
/// * 顶栏收起用 [Alignment.bottomCenter]（内容向上滑出）
/// * 底栏收起用 [Alignment.topCenter]（内容向下滑出）
class CollapseSlot extends StatelessWidget {
  final double factor;
  final Alignment alignment;
  final Widget child;

  const CollapseSlot({
    required this.factor,
    required this.alignment,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var f = factor;
    if (f < 0) f = 0;
    if (f > 1) f = 1;
    return ClipRect(
      child: Align(
        alignment: alignment,
        heightFactor: f,
        child: child,
      ),
    );
  }
}
