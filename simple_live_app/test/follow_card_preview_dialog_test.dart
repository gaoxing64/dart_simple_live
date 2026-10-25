import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_card_preview_dialog.dart';

void main() {
  setUp(() => Get.testMode = true);

  testWidgets('预览卡片展示标题和主播名，操作收在右下角', (tester) async {
    final item = FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播名',
      face: '',
      addTime: DateTime(2026),
    )..title.value = '直播标题';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FollowCardPreviewDialog(
              item: item,
              onSetGroup: () {},
              onViewDetail: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('直播标题'), findsOneWidget);
    expect(find.text('主播名'), findsOneWidget);
    expect(find.byTooltip('设置分组'), findsOneWidget);
    expect(find.byTooltip('查看详情'), findsOneWidget);

    // 操作按钮与主播名同一行，卡片底部只保留设计内的 8dp 内边距；
    // 防止再退回「标题下再挂一整行空白操作栏」的布局。
    final cardRect = tester.getRect(find.byKey(const ValueKey('follow-preview-card')));
    final nameRect = tester.getRect(find.text('主播名'));
    final actionRect = tester.getRect(find.byTooltip('查看详情'));
    expect((actionRect.center.dy - nameRect.center.dy).abs(), lessThan(6));
    expect(cardRect.bottom - actionRect.bottom, inInclusiveRange(0, 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('中间页完整展示全部标签，未分组有占位', (tester) async {
    final item = FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播名',
      face: '',
      addTime: DateTime(2026),
    )..title.value = '直播标题';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FollowCardPreviewDialog(
              item: item,
              groupNames: const ['CS解说', 'LOL解说', '单机', '手游'],
              onSetGroup: () {},
              onViewDetail: () {},
            ),
          ),
        ),
      ),
    );

    for (final tag in ['CS解说', 'LOL解说', '单机', '手游']) {
      expect(find.text(tag), findsOneWidget);
    }
    expect(find.text('+1'), findsNothing);
    // 标签胶囊不搭配文件夹图标。
    expect(find.byIcon(Remix.folder_3_line), findsNothing);
    // 标签与平台 / 直播状态同一行，不再单独占一行。
    final statusCenter = tester.getCenter(find.text('未开播'));
    final tagCenter = tester.getCenter(find.text('CS解说'));
    expect((tagCenter.dy - statusCenter.dy).abs(), lessThan(6));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FollowCardPreviewDialog(
              item: item,
              onSetGroup: () {},
              onViewDetail: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('未分组'), findsOneWidget);
  });

  testWidgets('桌面弹卡随窗口放大，窄屏保持窗口减边距', (tester) async {
    final item = FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播名',
      face: '',
      addTime: DateTime(2026),
    )..title.value = '直播标题';

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FollowCardPreviewDialog(
                item: item,
                onSetGroup: () {},
                onViewDetail: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(1400);
    expect(tester.getSize(find.byKey(const ValueKey('follow-preview-card'))).width, closeTo(760, 1));

    await pumpAt(360);
    expect(tester.getSize(find.byKey(const ValueKey('follow-preview-card'))).width, closeTo(312, 1));
  });

  testWidgets('打开和关闭都有淡入淡出过渡', (tester) async {
    final item = FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播名',
      face: '',
      addTime: DateTime(2026),
    )..title.value = '直播标题';

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showFollowCardPreviewDialog(
                  item: item,
                  groupNames: const [],
                  onSetGroup: () {},
                  onViewDetail: () {},
                ),
                child: const Text('打开预览'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开预览'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(FollowCardPreviewDialog), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(FollowCardPreviewDialog)));
    expect(route?.transitionDuration, const Duration(milliseconds: 220));

    await tester.pump(const Duration(milliseconds: 110));
    final scale = tester.widget<ScaleTransition>(find.byType(ScaleTransition).first);
    expect(scale.scale.value, lessThan(1));

    await tester.pump(const Duration(milliseconds: 150));
    Get.back();
    await tester.pump();
    expect(find.byType(FollowCardPreviewDialog), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(FollowCardPreviewDialog), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FollowCardPreviewDialog), findsNothing);
  });

  testWidgets('点设置分组只触发设置分组，不触发查看详情', (tester) async {
    var groupTaps = 0;
    var detailTaps = 0;
    final item = FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '主播名',
      face: '',
      addTime: DateTime(2026),
    )..title.value = '直播标题';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FollowCardPreviewDialog(
              item: item,
              onSetGroup: () => groupTaps++,
              onViewDetail: () => detailTaps++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('设置分组'));
    await tester.pump();
    expect(groupTaps, 1);
    expect(detailTaps, 0);
    expect(tester.takeException(), isNull);
  });
}
