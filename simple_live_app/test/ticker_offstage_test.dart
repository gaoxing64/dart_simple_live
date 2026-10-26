// 回归测试：被 Offstage 隐藏的子树不应继续跑动画。
//
// 列表页把「空数据 / 加载中 / 出错」三个状态层常驻在 Stack 里，靠 Offstage
// 切换显隐。Flutter 的 Offstage 只负责「不绘制」，子树里的 AnimationController
// 依旧按刷新率每帧回调（官方文档在 Offstage.offstage 上明确写了这点）。
// 加载层的 CupertinoActivityIndicator 是无限循环动画，于是页面加载完成后
// 应用仍会一直出帧，窗口 resize 这类需要「等一帧」的操作被持续排队，
// 表现为拖动窗口边框时窗口跟不上鼠标。
//
// TickerOffstage 把「隐藏」与「停 ticker」绑定，本测试锁定该行为：
//   1. 隐藏时 TickerMode.of 为 false，显示时为 true；
//   2. 隐藏时子树里的 repeat() 动画不再排队出帧；
//   3. 显示时持续出帧（对照），切回隐藏后停帧。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/ticker_offstage.dart';

/// 一个持续循环动画的子树，模拟 AppLoaddingWidget 里的
/// CupertinoActivityIndicator（无限旋转）。
class _RepeatingAnimation extends StatefulWidget {
  const _RepeatingAnimation();

  @override
  State<_RepeatingAnimation> createState() => _RepeatingAnimationState();
}

class _RepeatingAnimationState extends State<_RepeatingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    // 必须在 initState 里创建：late final 是懒初始化，若只声明不读取，
    // controller 永远不会被实例化，动画也就无从谈起。
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 读取子树内部真实的 TickerMode 状态。
class _TickerModeProbe extends StatelessWidget {
  const _TickerModeProbe();

  @override
  Widget build(BuildContext context) =>
      Text('${TickerMode.valuesOf(context).enabled}');
}

Widget _host({required bool offstage, required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: TickerOffstage(offstage: offstage, child: child),
    ),
  );
}

void main() {
  group('TickerOffstage', () {
    testWidgets('隐藏时子树 ticker 被停掉，显示时恢复', (tester) async {
      await tester.pumpWidget(
        _host(offstage: true, child: const _TickerModeProbe()),
      );
      // 被 Offstage 隐藏的子树需显式带上 skipOffstage: false 才能找到。
      expect(find.text('false', skipOffstage: false), findsOneWidget);

      await tester.pumpWidget(
        _host(offstage: false, child: const _TickerModeProbe()),
      );
      expect(find.text('true'), findsOneWidget);
    });

    testWidgets('隐藏时无限动画不再排队出帧', (tester) async {
      await tester.pumpWidget(
        _host(offstage: true, child: const _RepeatingAnimation()),
      );
      // 初始帧与状态稳定帧各 pump 一次后，不应再有排队的帧。
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('显示时无限动画持续出帧（对照）', (tester) async {
      await tester.pumpWidget(
        _host(offstage: false, child: const _RepeatingAnimation()),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);

      // 收尾：停掉动画，避免测试结束时仍有活跃 ticker。
      tester
          .state<_RepeatingAnimationState>(find.byType(_RepeatingAnimation))
          .controller
          .stop();
      await tester.pump();
    });

    testWidgets('切换为隐藏后，正在跑的动画会停下来', (tester) async {
      await tester.pumpWidget(
        _host(offstage: false, child: const _RepeatingAnimation()),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);

      // 模拟列表加载完成、加载层被隐藏。
      await tester.pumpWidget(
        _host(offstage: true, child: const _RepeatingAnimation()),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
