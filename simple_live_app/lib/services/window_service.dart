import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc, Utf16;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

class WindowService extends GetxService implements WindowListener {
  static WindowService get instance => Get.find<WindowService>();

  bool isPIP = false;

  /// Flutter Windows runner 的窗口类名，用于定位窗口句柄
  /// （窗口标题可能被修改，按类名查找更可靠）
  static const String _windowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

  /// DWMWA_USE_IMMERSIVE_DARK_MODE 在 Windows 10 20H1 之前的值
  static const int _dwmwaUseImmersiveDarkModeLegacy = 19;

  static Pointer<Utf16>? _windowClassNamePtr;

  _BrightnessObserver? _brightnessObserver;

  /// 主题变化订阅（[onClose] 时释放）
  Worker? _themeModeWorker;

  WindowService() {
    windowManager.addListener(this);
  }

  @override
  void onInit() {
    super.onInit();
    if (Platform.isWindows) {
      // 应用内切换主题时立即刷新标题栏，不必等 Flutter 主题动画走完
      _themeModeWorker = ever(AppSettingsController.instance.themeMode, (_) {
        _applyTitleBarTheme();
      });
      // 系统深浅色变化
      final observer = _BrightnessObserver(this);
      _brightnessObserver = observer;
      WidgetsBinding.instance.addObserver(observer);
    }
  }

  @override
  void onClose() {
    _themeModeWorker?.dispose();
    _themeModeWorker = null;
    final observer = _brightnessObserver;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
      _brightnessObserver = null;
    }
    windowManager.removeListener(this);
    super.onClose();
  }

  Future<void> init() async {
    await resize();
    WindowOptions windowOptions = WindowOptions(
      minimumSize: Size(280, 280),
      center: false,
      title: "Slive",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (Platform.isWindows) {
        _applyTitleBarTheme();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Windows 原生标题栏只在窗口创建时读取系统深浅色，
  /// 运行时不会跟随主题切换，需要手动设置 DWM 属性
  ///
  /// 深浅色判定统一交给 [AppSettingsController.shouldUseDarkTheme]
  /// （与 MaterialApp 的解析规则一致），因此不会出现读取到主题动画中间态
  /// 而反复写入的问题。
  void _applyTitleBarTheme() {
    final platformDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    _setImmersiveDarkMode(
      AppSettingsController.instance.shouldUseDarkTheme(
        platformDark: platformDark,
      ),
    );
  }

  void _setImmersiveDarkMode(bool dark) {
    final hwnd = _findWindowHandle();
    if (hwnd == 0) {
      return;
    }
    // 读回真实值再决定：DWMWA_USE_IMMERSIVE_DARK_MODE 是标题栏渲染的唯一依据，
    // 属性一致就说明标题栏已是目标颜色；本服务每次写入都会跟着强制重绘，
    // 因此一致时无需重复写入与重绘
    if (_readImmersiveDarkMode(hwnd) == dark) {
      return;
    }
    final Pointer<Int32> value = calloc<Int32>();
    value.value = dark ? 1 : 0;
    try {
      // 20 对应 Windows 10 20H1 及以上，失败时回退到旧版本的 19
      var result = win32.DwmSetWindowAttribute(
          hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, value, sizeOf<Int32>());
      if (result != 0) {
        result = win32.DwmSetWindowAttribute(
            hwnd, _dwmwaUseImmersiveDarkModeLegacy, value, sizeOf<Int32>());
      }
      if (result != 0) {
        return;
      }
      // 触发非客户区重绘，让标题栏立即刷新
      win32.SetWindowPos(hwnd, 0, 0, 0, 0, 0,
          win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
    } finally {
      calloc.free(value);
    }
  }

  /// 读取标题栏当前的深浅色，系统过旧（不支持该属性）时返回 null
  static bool? _readImmersiveDarkMode(int hwnd) {
    final Pointer<Int32> value = calloc<Int32>();
    try {
      var result = win32.DwmGetWindowAttribute(
          hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, value, sizeOf<Int32>());
      if (result != 0) {
        result = win32.DwmGetWindowAttribute(
            hwnd, _dwmwaUseImmersiveDarkModeLegacy, value, sizeOf<Int32>());
      }
      if (result != 0) {
        return null;
      }
      return value.value != 0;
    } finally {
      calloc.free(value);
    }
  }

  /// 窗口类名指针只分配一次，进程存活期间复用
  static int _findWindowHandle() {
    _windowClassNamePtr ??= win32.TEXT(_windowClassName);
    return win32.FindWindow(_windowClassNamePtr!, nullptr);
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
  void onWindowFocus() {
    // 窗口重新获得焦点时校准一次：Explorer/DWM 重启等情况下窗口属性会丢失，
    // 而那时不一定有主题变化事件可依赖（属性一致时不会产生任何写入）
    if (Platform.isWindows) {
      _applyTitleBarTheme();
    }
  }

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  Future<void> onWindowMove() async {}

  @override
  Future<void> onWindowMoved() async {
    if (!isPIP) {
      final bounds = await windowManager.getBounds();
      _saveBounds(bounds);
    }
  }

  @override
  Future<void> onWindowResize() async {}

  @override
  Future<void> onWindowResized() async {
    if (!isPIP) {
      final bounds = await windowManager.getBounds();
      _saveBounds(bounds);
    }
  }

  @override
  void onWindowRestore() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowUnmaximize() {}

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

/// 系统深浅色变化时同步标题栏。
/// 系统深浅色变化时 Windows 只会按系统设置刷新标题栏，因此这里要按
/// 应用内设置重新校正一次（应用内固定了浅色/深色时尤其需要）。
/// 引擎会监听 AppsUseLightTheme 注册表变化并回调 Dart，所以该回调可靠。
class _BrightnessObserver with WidgetsBindingObserver {
  _BrightnessObserver(this.service);

  final WindowService service;

  @override
  void didChangePlatformBrightness() {
    service._applyTitleBarTheme();
  }
}
