import 'package:material_ui/material_ui.dart';

/// [Offstage] + [TickerMode] 的组合：隐藏时同时停掉子树里的动画。
///
/// 单独使用 [Offstage] 只是「不绘制」，子树里的 `AnimationController`
/// 依旧会按显示刷新率每帧回调——Flutter 官方文档在 [Offstage.offstage]
/// 上写得很明确：
///
/// > Animations continue to run in offstage children, and therefore use
/// > battery and CPU time, regardless of whether the animations end up
/// > being visible.
///
/// 列表页把「空数据 / 加载中 / 出错」三个状态都常驻在 `Offstage` 里，
/// 其中加载态的 `CupertinoActivityIndicator` 是一个无限循环动画。于是即使
/// 页面已经加载完成、没有任何可见动画，应用也会一直按刷新率出帧
/// （实测空闲时约 150+ fps），白白占用 CPU/GPU，并且让窗口 resize 这类
/// 需要「等一帧」的操作一直排队，表现为拖动窗口边框时窗口跟不上鼠标。
///
/// 本组件把「隐藏」与「停动画」绑定在一起，避免上述问题。
class TickerOffstage extends StatelessWidget {
  const TickerOffstage({
    super.key,
    required this.offstage,
    required this.child,
  });

  /// 为 true 时隐藏子树，并停掉其中的所有 ticker。
  final bool offstage;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: offstage,
      // 必须放在 Offstage 内部：Offstage 自己不会停 ticker
      child: TickerMode(enabled: !offstage, child: child),
    );
  }
}
