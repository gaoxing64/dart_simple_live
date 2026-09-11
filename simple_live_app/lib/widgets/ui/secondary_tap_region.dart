import 'package:material_ui/material_ui.dart';

/// 给子树补一个「鼠标右键」入口，用于在桌面端唤出上下文操作。
///
/// 移动端靠长按唤出操作菜单；桌面端虽然也能按住左键 500ms 触发，但这既不符合
/// 桌面习惯、也不容易发现。这里把同一个回调同时挂到次要点击上：
/// - 触摸设备：无次要点击，行为不变；
/// - 鼠标：右键即可唤出，长按仍然可用。
///
/// 只注册次要点击，**不碰**主点击与长按：子树自己的 `InkWell` / `ListTile`
/// 继续按原样处理点按与长按，因此不会和它们抢手势。
///
/// 命中测试用 `translucent` 而不是 `deferToChild`：后者只在子树自身命中时才
/// 参与，包着带空隙的 `Row` / `Column` / 只有一小段文字的 `GestureDetector` 时，
/// 空隙处的右键会漏下去，右键热区小于视觉范围。`translucent` 让本层在子树
/// 未命中时仍能收到事件，同时不会像 `opaque` 那样挡住 Stack 里的兄弟节点。
///
/// [onSecondaryTap] 为 null 时直接返回 [child]，不产生多余节点。
class SecondaryTapRegion extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSecondaryTap;

  const SecondaryTapRegion({
    required this.child,
    this.onSecondaryTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final callback = onSecondaryTap;
    if (callback == null) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTap: callback,
      child: child,
    );
  }
}
