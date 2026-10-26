import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

void main() {
  late Directory tempDir;

  // 只初始化一次 Hive：在 testWidgets 里写入 Hive 后调用 Hive.close()
  // 会等待 fake-async 区里那个永不完成的写盘 Future，导致测试挂死。
  // 临时目录留给系统回收即可。
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('slive_theme_mode_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    Get.testMode = true;
    await Get.put(LocalStorageService()).init();
  });

  tearDown(() {
    Get.reset();
  });

  group('theme mode 索引', () {
    test('normalizeThemeModeIndex 越界回退到跟随系统', () {
      expect(AppSettingsController.normalizeThemeModeIndex(-1), 0);
      expect(AppSettingsController.normalizeThemeModeIndex(0), 0);
      expect(AppSettingsController.normalizeThemeModeIndex(1), 1);
      expect(AppSettingsController.normalizeThemeModeIndex(2), 2);
      expect(AppSettingsController.normalizeThemeModeIndex(3), 0);
      expect(AppSettingsController.normalizeThemeModeIndex(100), 0);
    });

    test('resolveThemeMode 返回对应的 ThemeMode', () {
      expect(AppSettingsController.resolveThemeMode(0), ThemeMode.system);
      expect(AppSettingsController.resolveThemeMode(1), ThemeMode.light);
      expect(AppSettingsController.resolveThemeMode(2), ThemeMode.dark);
      expect(AppSettingsController.resolveThemeMode(9), ThemeMode.system);
    });

    test('shouldUseDarkTheme 跟随系统时取系统深浅色', () {
      final controller = AppSettingsController();

      controller.themeMode.value = 0; // 跟随系统
      expect(controller.shouldUseDarkTheme(platformDark: true), isTrue);
      expect(controller.shouldUseDarkTheme(platformDark: false), isFalse);

      controller.themeMode.value = 1; // 浅色
      expect(controller.shouldUseDarkTheme(platformDark: true), isFalse);
      expect(controller.shouldUseDarkTheme(platformDark: false), isFalse);

      controller.themeMode.value = 2; // 深色
      expect(controller.shouldUseDarkTheme(platformDark: true), isTrue);
      expect(controller.shouldUseDarkTheme(platformDark: false), isTrue);
    });

    test('setThemeMode 归一化后落盘', () async {
      final controller = Get.put(AppSettingsController());

      controller.setThemeMode(99);
      await Future<void>.delayed(Duration.zero);

      expect(controller.themeModeIndex, 0);
      expect(
        LocalStorageService.instance
            .getValue(LocalStorageService.kThemeMode, -1),
        0,
      );

      controller.setThemeMode(2);
      await Future<void>.delayed(Duration.zero);

      expect(controller.themeModeIndex, 2);
      expect(
        LocalStorageService.instance
            .getValue(LocalStorageService.kThemeMode, -1),
        2,
      );
    });

    test('onInit 读到越界值时回退到跟随系统', () async {
      await LocalStorageService.instance
          .setValue(LocalStorageService.kThemeMode, 42);

      final controller = Get.put(AppSettingsController());

      expect(controller.themeModeIndex, 0);
      expect(controller.shouldUseDarkTheme(platformDark: true), isTrue);
    });

    // main.dart 用 Obx 包住 GetMaterialApp 并把 themeModeIndex 传给 themeMode，
    // 这条链路是删除 Get.changeThemeMode 之后主题刷新的唯一依赖
    testWidgets('setThemeMode 会驱动 MaterialApp 切换主题', (tester) async {
      final controller = Get.put(AppSettingsController());

      await tester.pumpWidget(
        Obx(
          () => GetMaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
            ),
            themeMode: AppSettingsController.resolveThemeMode(
              controller.themeModeIndex,
            ),
            home: Builder(
              builder: (context) =>
                  Text('brightness=${Theme.of(context).brightness.name}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('brightness=light'), findsOneWidget);

      controller.setThemeMode(2);
      await tester.pumpAndSettle();
      expect(find.text('brightness=dark'), findsOneWidget);

      controller.setThemeMode(1);
      await tester.pumpAndSettle();
      expect(find.text('brightness=light'), findsOneWidget);
    });
  });
}
