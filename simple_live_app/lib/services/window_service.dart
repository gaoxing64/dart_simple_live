import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc, Utf16;
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

class WindowService extends GetxService implements WindowListener {
  static WindowService get instance => Get.find<WindowService>();

  bool isPIP = false;
  bool isMaxAuto = false;
  bool isMaxState = false;

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
    // 必须排在 resize() 之前：setBounds / show / focus 都会触发 WM_SIZE
    // 或 WM_ACTIVATEAPP，而插件那时仍处于 auto reset 开启状态，每次都会
    // 白白做一轮 ~55ms 的 DDC/CI 亮度读写（启动期共约 3 次）。
    if (Platform.isWindows) {
      await _disableScreenBrightnessAutoReset();
    }
    await resize();
    isMaxAuto = AppSettingsController.instance.windowMaxAuto.value;
    isMaxState = AppSettingsController.instance.windowMaxState.value;
    final width = LocalStorageService.instance.getValue(LocalStorageService.kWindowWidth, 1280.0);
    final height = LocalStorageService.instance.getValue(LocalStorageService.kWindowHeight, 720.0);
    final x = LocalStorageService.instance.getValue(LocalStorageService.kWindowX, 320.0);
    final y = LocalStorageService.instance.getValue(LocalStorageService.kWindowY, 180.0);

    AppSettingsController.instance.danmakuFontResize = await danmakuFontClamped();
    await windowManager.setPosition(Offset(x, y));
    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      minimumSize: Size(320, 280), // 防止无脑小窗导致界面报错
      center: false,
      title: "Slive",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (Platform.isWindows) {
        _applyTitleBarTheme();
      }
      await windowManager.show();
      // 最大化在显示之后 防止卡白屏
      if (isMaxAuto && isMaxState) {
        await WidgetsBinding.instance.endOfFrame;
        await windowManager.maximize();
      }
      await windowManager.focus();
    });
  }

  ///
  /// 该插件默认开启 auto reset，其 Windows 实现会在窗口过程的 `WM_SIZE`
  /// （`SIZE_RESTORED`/`SIZE_MAXIMIZED`）里调用 `OnApplicationResume()`，
  /// 同步读回显示器亮度：走的是 DDC/CI
  /// （`GetNumberOfPhysicalMonitorsFromHMONITOR` + `GetMonitorBrightness`，
  /// 必要时还会 `SetMonitorBrightness` 写回）。实测单次约 55ms，而且发生在
  /// **平台线程**上——拖动窗口边框时鼠标每移动一次就来一条 `WM_SIZE`，
  /// 消息循环于是被反复堵住，表现就是窗口严重滞后于鼠标。
  ///
  /// 本应用在 Windows 上并不依赖这个特性：`resetSystem()` 已明确跳过桌面
  /// 平台的亮度重置，播放器也没有用到 auto reset 的语义。关掉之后插件的窗口
  /// 过程对 `WM_SIZE` 立即返回，拖动窗口不再触发任何 DDC/CI 调用。
  Future<void> _disableScreenBrightnessAutoReset() async {
    try {
      await ScreenBrightness.instance.setAutoReset(false);
    } catch (e) {
      // 关闭失败不影响功能，只是会保留插件的默认行为
      Log.logPrint(e);
    }
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
  Future<void> onWindowEnterFullScreen() async {
    // https://github.com/leanflutter/window_manager/issues/560
    // https://github.com/leanflutter/window_manager/pull/531
    await danmakuFontClamped();
  }

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
  Future<void> onWindowLeaveFullScreen() async {
    // issues 同上
    await danmakuFontClamped();
  }

  @override
  Future<void> onWindowMaximize() async {
    if(AppSettingsController.instance.windowMaxAuto.value){
      AppSettingsController.instance.setWindowMaxState(true);
    }
    await danmakuFontClamped();
  }

  @override
  void onWindowMinimize() {}

  @override
  Future<void> onWindowMove() async {}

  @override
  Future<void> onWindowMoved() async {
    await windowStateChanged();
  }

  @override
  Future<void> onWindowResize() async {}

  @override
  Future<void> onWindowResized() async {
    await windowStateChanged();
  }

  @override
  void onWindowRestore() {}

  @override
  void onWindowUndocked() {}

  @override
  Future<void> onWindowUnmaximize() async {
    AppSettingsController.instance.setWindowMaxState(false);
    await danmakuFontClamped();
  }

  Future<void> windowStateChanged() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    if (!isPIP) {
      await danmakuFontClamped();
      _saveSizeAndPositon(size, position);
    } else {
      _savePipSizeAndPositon(size, position);
    }
  }

  void _saveSizeAndPositon(Size s, Offset position) {
    LocalStorageService.instance.setValue(LocalStorageService.kWindowX, position.dx);
    LocalStorageService.instance.setValue(LocalStorageService.kWindowY, position.dy);
    LocalStorageService.instance.setValue(LocalStorageService.kWindowWidth, s.width);
    LocalStorageService.instance.setValue(LocalStorageService.kWindowHeight, s.height);
  }

  void _savePipSizeAndPositon(Size s, Offset position) {
    AppSettingsController.instance.setWindowPipX(position.dx);
    AppSettingsController.instance.setWindowPipY(position.dy);
    AppSettingsController.instance.setWindowPipWidth(s.width);
    AppSettingsController.instance.setWindowPipHeight(s.height);
  }

  // 启用后，当 Resized/Maximize/full -> re 后调整
  // 通过service 通知 live_controller 更新 danmaku_option
  // 因为media_kit的 w/h 均为 null, 所以只能从外部window_manager设计
  Future<double> danmakuFontClamped() async {
    // 应该更进一步判断用户是否在直播间界面, 小窗模式恢复默认弹幕尺寸
    if (AppSettingsController.instance.danmakuFontClamped.value && !isPIP) {
      final size = await windowManager.getSize();
      var windowH = size.height;
      Log.i('player_danmaku_size_h: $windowH');
      // 窗口设计分辨率默认 1280x720
      var reSizeFont =  Utils.scaleValue(
        value: AppSettingsController.instance.danmuSize.value,
        playerH: windowH,
        designH: 720.0,
        upSens: AppSettingsController.instance.danmakuFontClampUpSens.value / 10,
        downSens: AppSettingsController.instance.danmakuFontClampDownSens.value / 10,
        minSize: 8,
        maxSize: 48,
      );
      EventBus.instance.emit(Constant.kUpdateDanmaku, reSizeFont);
      Log.i('player_danmaku_size: $reSizeFont');
      return reSizeFont;
    } else {
      // 防御性，反复测试功能过程中弹幕
      EventBus.instance.emit(Constant.kUpdateDanmaku, AppSettingsController.instance.danmuSize.value);
      return AppSettingsController.instance.danmuSize.value;
    }
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
