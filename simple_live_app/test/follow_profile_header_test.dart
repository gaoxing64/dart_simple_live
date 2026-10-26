import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/follow_profile_header.dart';

FollowUser _follow() => FollowUser(
      id: 'huya_123456',
      roomId: '123456',
      siteId: 'huya',
      userName: '测试主播',
      face: '',
      addTime: DateTime(2026, 10, 20),
    )..liveStatus.value = 2;

Future<void> _pumpHeader(
  WidgetTester tester, {
  bool isFollowed = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FollowProfileHeader(
            follow: _follow(),
            site: Sites.allSites['huya']!,
            isFollowed: isFollowed,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('点击主播 ID 复制并在底部提示', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpHeader(tester);
    await tester.tap(find.byKey(const ValueKey('copy-anchor-id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, '测试主播');
    expect(find.text('已复制主播 ID'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('点击房间号复制并在底部提示', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpHeader(tester);
    await tester.tap(find.byKey(const ValueKey('copy-room-id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, '123456');
    expect(find.text('已复制房间号'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('点击头像打开预览并可关闭', (tester) async {
    await _pumpHeader(tester);
    await tester.tap(find.byKey(const ValueKey('follow-avatar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const ValueKey('avatar-preview')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭头像预览'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const ValueKey('avatar-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
