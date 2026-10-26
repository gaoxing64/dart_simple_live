// 回归测试：SmoothWheelScrollController 把鼠标滚轮的「瞬时跳」改成过渡动画。
//
// 全局作用于首页 / 分类 / 搜索 / 关注等所有走 BasePageController 的列表，
// 出问题会全局表现，所以这里把三件事钉死：
//   1. 滚一轮不是一帧到位，而是 180ms 过渡；
//   2. 连续滚动累加目标位置（否则快速滚动会越滚越慢）；
//   3. 滚轮与手指拖动给出的 userScrollDirection 必须一致 ——
//      indexed_controller 的顶/底栏显隐、live_room_controller 的自动滚动
//      都读这个方向，两套手势给出相反方向就是 bug。
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
// ScrollDirection 在 rendering 里定义，material_ui 没有转出来
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';

Widget host(ScrollController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 300,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => SizedBox(
                  height: 50,
                  child: Text('item $i'),
                ),
                childCount: 200,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 派发一次鼠标滚轮事件。
///
/// 用 [WidgetTester.handlePointerEvent] 而不是 `startGesture` 那套：
/// 滚轮走的是 PointerSignal 通道（`Listener.onPointerSignal` →
/// `Scrollable._handlePointerScroll` → `position.pointerScroll`），
/// 普通手势模拟不出来。
void wheel(WidgetTester tester, double dy) {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(CustomScrollView)),
      scrollDelta: Offset(0, dy),
      device: 1,
    ),
  );
}

/// 派发一次「取消滚动惯性」事件。
///
/// ⚠️ 不能用 `PointerScrollEvent(scrollDelta: Offset.zero)` 代替：`Scrollable`
/// 在 `_receivedPointerSignal` 里判 `delta != 0.0` 才会注册指针信号，零位移的
/// 滚轮事件被直接丢掉，根本到不了 `position.pointerScroll(0)`。框架自己的取消
/// 路径是 [PointerScrollInertiaCancelEvent]，走的是 `pointerScroll(0)`。
void cancelInertia(WidgetTester tester) {
  tester.binding.handlePointerEvent(
    PointerScrollInertiaCancelEvent(
      position: tester.getCenter(find.byType(CustomScrollView)),
      device: 1,
    ),
  );
}

void main() {
  testWidgets('滚轮走过渡动画，不是一帧到位', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 0);

    // 滚轮下滚 120px
    wheel(tester, 120);
    // ⚠️ 第一帧只是动画的**起算帧**：ticker 在这一帧才拿到 startTime，
    // 进度仍是 0，位置不会动。所以要多走一帧才看得到位移。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 动画进行中：既离开了起点、又还没到目标，说明走的是 animateTo
    // 而不是 forcePixels（框架默认实现一帧就到 120）。
    expect(controller.position.pixels, greaterThan(0),
        reason: '滚轮必须走过渡动画，一帧到位等于没改');
    expect(controller.position.pixels, lessThan(120));

    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(120, 0.5));
  });

  testWidgets('连续滚动累加目标位置，不会越滚越慢', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    // 连续 3 格，每格 120px：动画还没跑完就来下一格
    for (var i = 0; i < 3; i++) {
      wheel(tester, 120);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    // 目标是累加的 360：如果每格都从当前 pixels 起算，
    // 上一格的距离会被「吃掉」，最终落点会明显小于 360
    expect(controller.position.pixels, closeTo(360, 1.0));
  });

  testWidgets('滚轮与拖动给出的滚动方向一致（内容上移 = reverse）', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    // 手指上移 100：内容上移、offset 增大。
    // ⚠️ 必须在**手势还按着**的时候读方向：松手后速度若为 0，
    // `goBallistic` 会直接 `goIdle`，而 `beginActivity` 会把
    // userScrollDirection 复位成 idle（见框架
    // `scroll_position_with_single_context.dart` 的 beginActivity）。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    final dragDirection = controller.position.userScrollDirection;
    expect(
      dragDirection,
      ScrollDirection.reverse,
      reason: '前置断言：拖动路径上报 reverse（内容上移）',
    );
    await gesture.up();

    // 滚轮下滚：同样是内容上移、offset 增大
    // ⚠️ 这里的符号必须与框架 ScrollPositionWithSingleContext.pointerScroll
    // 的默认实现一致（-delta > 0 ? forward : reverse），改成 delta > 0
    // 会让滚轮与拖动给出相反方向，顶/底栏显隐会反。
    await tester.pumpAndSettle();
    wheel(tester, 120);
    await tester.pump();

    expect(
      controller.position.userScrollDirection,
      dragDirection,
      reason: '同一次「内容上移」的滚动，滚轮与拖动必须给出同一个方向',
    );
  });

  testWidgets('delta == 0（取消惯性）时停住动画并清掉累加目标', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    // 先滚一格，动画还在跑。第一帧只是起算帧、看不到位移，要多走一帧。
    wheel(tester, 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final midScroll = controller.position.pixels;
    expect(midScroll, greaterThan(0));
    expect(midScroll, lessThan(120));

    // 取消惯性：必须原样交给父类 goBallistic 停住，
    // 同时清掉 _wheelTarget，否则下一格会从一个过期的目标起算。
    cancelInertia(tester);
    await tester.pumpAndSettle();

    // 停在收到取消信号时的位置附近（goBallistic(0) 会就地停住），
    // 不会继续把剩下的 120 - midScroll 跑完
    expect(controller.position.pixels, lessThan(120));

    // 之后再滚一格，从停住的地方起算，而不是接着旧目标
    wheel(tester, 120);
    await tester.pumpAndSettle();

    expect(
      controller.position.pixels,
      closeTo(midScroll + 120, 2.0),
      reason: '_wheelTarget 没被清掉时，这一格会回到上一格的旧目标 240',
    );
  });
}
