// 回归测试：图片加载失败时 NetImage 保持封面尺寸（卡片高度不塌陷）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/widgets/net_image.dart';

void main() {
  testWidgets('NetImage 加载失败时保持封面高度', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: NetImage(
              'https://example.com/not-exist.png',
              height: 110,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 测试环境下网络图片拿不到数据，会停留在 loading（或 failed）占位分支；
    // 两个分支都必须保持封面尺寸，且只渲染一个占位图标
    final box = tester.renderObject<RenderBox>(
      find.byType(NetImage),
    );
    expect(box.size.height, 110, reason: '封面区域应保持 110 高');
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && (w.icon == Icons.image || w.icon == Icons.broken_image),
      ),
      findsOneWidget,
      reason: '加载中/失败时应显示占位图标且不改变封面尺寸',
    );
  });
}
