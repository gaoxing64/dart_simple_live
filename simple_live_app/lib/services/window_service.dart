import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

class WindowService extends GetxService implements WindowListener {
  static WindowService get instance => Get.find<WindowService>();

  bool isPIP = false;

  WindowService() {
    windowManager.addListener(this);
    if (Platform.isWindows) {
      WidgetsBinding.instance.addObserver(_BrightnessObserver(this));
      ever(AppSettingsController.instance.themeMode, (_) {
        _applyTitleBarTheme();
      });
    }
  }

  Future<void> init() async {
    // app setting controller has init before windows_service, so these codes ugly
    // but lazy-safe was good
    final startMaximized = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowStartMaximized, false);
    final isMaximized = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowIsMaximized, false);

    await resize();
    WindowOptions windowOptions = WindowOptions(
      minimumSize: Size(280, 280),
      center: false,
      title: "Slive",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMaximized && isMaximized) {
        await windowManager.maximize();
      }
      if (Platform.isWindows) {
        _applyTitleBarTheme();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Windows 原生标题栏只在窗口创建时读取系统深浅色，
  /// 运行时不会跟随主题切换，需要手动设置 DWM 属性
  void _applyTitleBarTheme() {
    final mode =
        ThemeMode.values[AppSettingsController.instance.themeMode.value];
    final platformDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final isDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };
    _setImmersiveDarkMode(isDark);
  }

  void _setImmersiveDarkMode(bool dark) {
    final hwnd = win32.FindWindow(
        win32.TEXT('FLUTTER_RUNNER_WIN32_WINDOW'), nullptr);
    if (hwnd == 0) {
      return;
    }
    final Pointer<Int32> value = calloc.allocate<Int32>(sizeOf<Int32>());
    value.value = dark ? 1 : 0;
    try {
      win32.DwmSetWindowAttribute(
          hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, value, sizeOf<Int32>());
      // 触发非客户区重绘，让标题栏立即刷新
      win32.SetWindowPos(hwnd, 0, 0, 0, 0, 0,
          win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
    } finally {
      calloc.free(value);
    }
  }

  Future<void> resize() async {
    // 初始分辨率默认 1920×1080
    final width = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowWidth, 1280.0);
    final height = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowHeight, 720.0);
    final x = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowX, 320.0);
    final y = LocalStorageService.instance
        .getValue(LocalStorageService.kWindowY, 180.0);
    windowManager.setBounds(Rect.fromLTWH(x, y, width, height));
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowClose() {
    if (Platform.isLinux) {
      exit(0);
    }
  }

  @override
  void onWindowDocked() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowMaximize() {
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowIsMaximized, true);
  }

  @override
  void onWindowMinimize() {}

  @override
  Future<void> onWindowMove() async {}

  @override
  Future<void> onWindowMoved() async {
    if (!isPIP) {
      final isMaximized = await windowManager.isMaximized();
      if (!isMaximized) {
        final bounds = await windowManager.getBounds();
        _saveBounds(bounds);
      }
    }
  }

  @override
  Future<void> onWindowResize() async {}

  @override
  Future<void> onWindowResized() async {
    if (!isPIP) {
      final isMaximized = await windowManager.isMaximized();
      if (!isMaximized) {
        final bounds = await windowManager.getBounds();
        _saveBounds(bounds);
      }
    }
  }

  @override
  void onWindowRestore() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowUnmaximize() {
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowIsMaximized, false);
  }

  void _saveBounds(Rect bounds) {
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowX, bounds.left);
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowY, bounds.top);
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowWidth, bounds.width);
    LocalStorageService.instance
        .setValue(LocalStorageService.kWindowHeight, bounds.height);
  }
}

class _BrightnessObserver with WidgetsBindingObserver {
  _BrightnessObserver(this.service);

  final WindowService service;

  @override
  void didChangePlatformBrightness() {
    service._applyTitleBarTheme();
  }
}
