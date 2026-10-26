import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_controller.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_page.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

/// 保留真实 onInit 的启动链路，只隔离 Windows/桌面测试不可用的路径插件。
class _TestSettingsController extends AppSettingsController {
  @override
  Future<void> initDataPath() async {}
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('slive_aggregate_search_settings');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    Get.testMode = true;
    final storage = Get.put(LocalStorageService());
    await storage.init();
    await storage.removeValue(LocalStorageService.kAggregateSearchEnabled);
    Get.put<AppSettingsController>(_TestSettingsController());
  });

  tearDown(() {
    Get.reset();
  });

  test('聚合搜索默认关闭且设置后会持久化', () async {
    final controller = Get.find<AppSettingsController>();
    expect(controller.aggregateSearchEnabled.value, isFalse);

    controller.setAggregateSearchEnabled(true);
    await LocalStorageService.instance.flush();

    expect(
      LocalStorageService.instance.getValue(
        LocalStorageService.kAggregateSearchEnabled,
        false,
      ),
      isTrue,
    );

    Get.delete<AppSettingsController>();
    final restored = Get.put<AppSettingsController>(_TestSettingsController());
    expect(restored.aggregateSearchEnabled.value, isTrue);
  });

  testWidgets('主页设置页提供聚合搜索开关', (tester) async {
    final settings = Get.find<AppSettingsController>();
    Get.put(IndexedSettingsController());

    await tester.pumpWidget(
      GetMaterialApp(
        home: const IndexedSettingsPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final title = find.text('聚合搜索');
    await tester.ensureVisible(title);
    expect(title, findsOneWidget);

    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 200));

    final switchWidget = tester.widget<SettingsSwitch>(
      find.ancestor(of: title, matching: find.byType(SettingsSwitch)),
    );
    expect(settings.aggregateSearchEnabled.value, isTrue);
    expect(switchWidget.value, isTrue);
  });
}
