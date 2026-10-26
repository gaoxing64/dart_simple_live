import 'package:flutter_test/flutter_test.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/m3e_loading_indicator.dart';

/// M3 Expressive loading 指示器的回归测试。
///
/// 盯三件事：
/// 1. 形状序列本身可用 —— 多边形几何没退化、相邻形状之间能变形出非空路径；
/// 2. 无限动画能被停下 —— 系统「减弱动态效果」与 `TickerMode` 关闭时都必须
///    不再出帧（列表页三态常驻 `Offstage` 时靠这条避免空转烧 CPU/GPU）；
/// 3. 连续跑完一整轮变形不抛异常。
void main() {
  // 直接引用组件的默认序列与比例常量：序列一改，这些用例要跟着改，
  // 硬编码一份就测不到「默认序列被换掉」这件事了。
  final polygons = M3ELoadingIndicator.defaultPolygons;

  test('7 个默认形状都能生成尺寸合理的闭合路径', () {
    expect(polygons.length, 7,
        reason: '默认形状序列改了数量，这里与下面的 38/48 绘制比例要同步');

    for (var i = 0; i < polygons.length; i++) {
      final bounds = polygons[i].toPath().getBounds();
      expect(bounds.isEmpty, isFalse, reason: '第 $i 个形状路径为空');
      expect(bounds.width, greaterThan(0.1), reason: '第 $i 个形状过窄');
      expect(bounds.height, greaterThan(0.1), reason: '第 $i 个形状过矮');
      // 归一化形状应落在 1×1 附近，避免缩放系数算错导致图形溢出容器
      expect(bounds.width, lessThanOrEqualTo(1.5), reason: '第 $i 个形状过宽');
      expect(bounds.height, lessThanOrEqualTo(1.5), reason: '第 $i 个形状过高');
    }
  });

  test('相邻形状可变形（含首尾相接），0/0.5/1 进度都有路径', () {
    for (var i = 0; i < polygons.length; i++) {
      final morph = Morph(polygons[i], polygons[(i + 1) % polygons.length]);
      for (final progress in [0.0, 0.5, 1.0]) {
        final bounds = morph.toPath(progress: progress).getBounds();
        expect(
          bounds.isEmpty,
          isFalse,
          reason: '第 $i 段 progress=$progress 变形后路径为空',
        );
      }
    }
  });

  test('缩放系数保证图形不溢出容器', () {
    final factor = M3ELoadingIndicator.scaleFactorFor(polygons);
    // 38/48 = 活动尺寸比（AOSP 规范），与组件里的 _activeSizeRatio 同值；
    // 它是私有常量，这里只能照抄一份，改其中一个时另一个要同步。
    const activeSizeRatio = 38 / 48;

    expect(factor, lessThanOrEqualTo(1.0));
    expect(factor, greaterThan(0.3), reason: '系数过小会让图形缩得看不见');

    // 绘制尺寸 = 静态包围盒 × 系数 × 活动尺寸比，必须落在容器（1.0）之内
    for (var i = 0; i < polygons.length; i++) {
      final bounds = polygons[i].calculateBounds();
      expect(
        (bounds[2] - bounds[0]) * factor * activeSizeRatio,
        lessThanOrEqualTo(1.0),
        reason: '第 $i 个形状会横向溢出',
      );
      expect(
        (bounds[3] - bounds[1]) * factor * activeSizeRatio,
        lessThanOrEqualTo(1.0),
        reason: '第 $i 个形状会纵向溢出',
      );
    }
  });

  testWidgets('连续跑完一整轮变形不抛异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: M3ELoadingIndicator())),
      ),
    );

    // 正向断言：动画确实在跑（_start() 若变成空实现，下面这行会挂）。
    // 「禁用」的两个用例只验证不出帧，无法区分「停了」和「没开始」。
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    // 一轮 = 7 个形状 × 650ms，这里跑到两轮以上
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(M3ELoadingIndicator), findsOneWidget);
  });

  testWidgets('系统开启减弱动态效果时不出帧', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: M3ELoadingIndicator()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('TickerMode 关闭时不出帧', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(
          enabled: false,
          child: Center(child: M3ELoadingIndicator()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('运行期换形状序列能生效', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: M3ELoadingIndicator(polygons: _twoShapes)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 换成另一组序列：didUpdateWidget 必须重建形状对，
    // 否则继续用旧序列渲染（甚至下标越界）。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: M3ELoadingIndicator(polygons: _otherTwoShapes),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(M3ELoadingIndicator), findsOneWidget);
  });

  test('空序列 / 单元素序列被构造期断言拦下', () {
    // 构造期的 assert(polygons.length > 1) 是第一道闸门：在 debug 构建（含
    // 测试）里就拦住。release 构建会剥离它，运行期 _setupPolygons 再兜底
    // 回默认序列 —— 两道闸门对着同一个边界条件，改其中一个时另一个也要看。
    //
    // ⚠️ 断言在**构造函数**里抛，必须用闭包接住：写成
    // `pumpWidget(MaterialApp(child: M3ELoadingIndicator(polygons: bad)))`
    // 的话构造发生在测试体里（pumpWidget 的实参先求值），异常直接冒出去
    // 让整个用例失败，`takeException` 根本轮不到。
    expect(
      () => M3ELoadingIndicator(polygons: const <RoundedPolygon>[]),
      throwsAssertionError,
    );
    expect(
      () => M3ELoadingIndicator(polygons: [MaterialShapes.oval]),
      throwsAssertionError,
    );
    // 两个是下限，不拦
    expect(() => M3ELoadingIndicator(polygons: _twoShapes), returnsNormally);
  });

  testWidgets('默认序列不可变：外部修改不会污染正在显示的实例',
      (tester) async {
    // 组件内部按引用持有序列，可变列表被外部 add 会污染渲染。
    expect(() => M3ELoadingIndicator.defaultPolygons.add(MaterialShapes.oval),
        throwsUnsupportedError);
  });
}

// 形状不是 const（MaterialShapes 里是 static final），这里不能写 const 列表
final _twoShapes = [MaterialShapes.pill, MaterialShapes.oval];
final _otherTwoShapes = [MaterialShapes.sunny, MaterialShapes.cookie4Sided];
