// 回归测试：PageGridView 的分段（sections）渲染路径。
//
// 关注页用它渲染「正在直播 / 未开播」两段，每段有自己的列数、行高与条目数。
// 这条路径以前没有任何测试，新增的构造期断言（itemBuilder 与 sections 至少
// 给一个）也在这里钉住。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';

/// 一次性全量数据的控制器：分段场景没有下一页，list 直接给满。
class FixedController extends BasePageController<String> {
  FixedController(List<String> data) {
    list.assignAll(data);
  }

  int loadCalls = 0;

  @override
  Future<List<String>> getData(int page, int pageSize) async {
    loadCalls++;
    return [];
  }
}

void main() {
  Widget host(BasePageController<String> controller,
      {required List<GridSection> sections}) {
    return GetMaterialApp(
      home: Scaffold(
        body: PageGridView(
          pageController: controller,
          firstRefresh: false,
          sections: sections,
        ),
      ),
    );
  }

  tearDown(Get.reset);

  testWidgets('两段各自渲染，列数/行高互不影响', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = FixedController(List.generate(6, (i) => '卡 $i'));
    await tester.pumpWidget(host(
      controller,
      sections: [
        GridSection(
          header: const Text('正在直播'),
          crossAxisCount: 2,
          itemExtent: 160,
          itemCount: 4,
          itemBuilder: (_, i) => SizedBox(
            height: 160,
            child: Text('live-$i'),
          ),
        ),
        GridSection(
          header: const Text('未开播'),
          crossAxisCount: 1,
          itemExtent: 80,
          itemCount: 2,
          itemBuilder: (_, i) => SizedBox(
            height: 80,
            child: Text('offline-$i'),
          ),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('正在直播'), findsOneWidget);
    expect(find.text('未开播'), findsOneWidget);
    expect(find.text('live-0'), findsOneWidget);
    expect(find.text('live-3'), findsOneWidget);
    expect(find.text('offline-0'), findsOneWidget);
    expect(find.text('offline-1'), findsOneWidget);
    // 分段模式的数据由各段自己给，不应再走分页加载
    expect(controller.loadCalls, 0);
  });

  testWidgets('空段整段跳过，不留光杆段头', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = FixedController(const []);
    await tester.pumpWidget(host(
      controller,
      sections: [
        GridSection(
          header: const Text('正在直播'),
          crossAxisCount: 2,
          itemExtent: 160,
          itemCount: 2,
          itemBuilder: (_, i) => SizedBox(height: 160, child: Text('live-$i')),
        ),
        // 「未开播」过滤后是空的：段头也不能出现
        GridSection(
          header: const Text('未开播'),
          crossAxisCount: 1,
          itemExtent: 80,
          itemCount: 0,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('offline-$i')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('正在直播'), findsOneWidget);
    expect(find.text('未开播'), findsNothing,
        reason: '条目为 0 的段要连同段头一起跳过');
  });

  test('itemBuilder 与 sections 都不传时构造期就拒绝', () {
    final controller = FixedController(const []);
    expect(
      () => PageGridView(pageController: controller),
      throwsA(isA<AssertionError>()),
      reason: '两个都为空时单段分支会强解包 itemBuilder!，'
          '把误用提前到构造期暴露才合理',
    );
  });
}
