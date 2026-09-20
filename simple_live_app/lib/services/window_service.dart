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
import 'package:simple_live_app/modules/live_room/player/pip_aspect.dart';

class WindowService extends GetxService implements WindowListener {
  static WindowService get instance => Get.find<WindowService>();

  bool isPIP = false;
  bool isMaxAuto = false;
  bool isMaxState = false;

  // —— 小窗锁定纵横比（纯 Dart 方案，三平台统一入口）——
  double? _pipActiveAspect; // null=未锁定；非空=当前锁定比例（守卫第一判据）
  FrameInsets _pipInsets = FrameInsets.zero;
  Size? _pipPendingOuter; // 我们自己 setSize 的目标尺寸（回声匹配用）
  int _pipStallCount = 0; // 连续「有偏差但仍未收敛」的纠正次数（熔断用）
  static const double _pipEpsPx = 1.0; // 合规容差（逻辑像素）
  static const int _pipMaxStall = 5; // 熔断阈值
  static const Size _normalMinimumSize =
      Size(320, 280); // 与 init() 中 WindowOptions 一致
  bool get pipAspectLocked => _pipActiveAspect != null;

  /// 是否应当施加锁定（设置项开启）。
  bool get pipAspectWanted =>
      AppSettingsController.instance.pipLockAspect.value;

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
      // 最小尺寸单位 = Flutter 逻辑像素（window_manager 在 Windows 上
      // 换算成物理像素写入 MINMAXINFO.ptMinTrackSize）。
      //
      // 宽度 436 逻辑像素 = 「保证至少 2 列完整卡面」的下限：
      //   左 padding 12 + 卡1 200 + 列距 12 + 卡2 200 + 右 padding 12 = 436
      //（卡宽 kMinCardWidth=200、列距 kCardSpacing=12、padding edgeInsetsA12=12，
      // 均为逻辑像素）。在 DPR=2.0（200% 缩放）下 = 872 物理像素；DPR=1.0
      //（100% 缩放）下 = 436 物理像素——跨缩放下「至少 2 列」语义一致。
      minimumSize: const Size(436, 280), // 防止无脑小窗导致界面报错
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
  Future<void> onWindowResize() async {
    if (!pipAspectLocked) return;
    // Linux 由 GDK 原生提示保比，无需 Dart 侧逐帧纠正
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (Platform.isWindows) {
      // 拖动中每步按当前外框宽重算外框比例 R（setAspectRatio 只写值、不触发回声）
      await retuneAspectDuringResize(_pipActiveAspect!);
    } else if (Platform.isMacOS) {
      // §5.1 macOS 方案 B：纯 Dart 拉回比例，带死循环守卫
      if (_pipActiveAspect == null) return; // 第一判据：未锁定直接忽略
      final cur = await windowManager.getSize();
      // 回声匹配：若观察到的尺寸恰是我们自己 setSize 的目标，视为回声，清标记返回
      if (_pipPendingOuter != null &&
          (cur.width - _pipPendingOuter!.width).abs() <= _pipEpsPx &&
          (cur.height - _pipPendingOuter!.height).abs() <= _pipEpsPx) {
        _pipPendingOuter = null;
        _pipStallCount = 0;
        return;
      }
      if (PipAspectCalculator.matchesAspect(
        outer: cur,
        aspect: _pipActiveAspect!,
        insets: _pipInsets,
        epsPx: _pipEpsPx,
      )) {
        // 已合规：可能是用户拖到位，也可能是自己 setSize 的回声
        _pipPendingOuter = null; // 回声落地，清标记
        _pipStallCount = 0; // 有进展 → 复位熔断
        return;
      }
      if (_pipStallCount >= _pipMaxStall) return; // 熔断：放弃本次手势，防死循环
      final target = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: cur.width,
        aspect: _pipActiveAspect!,
        insets: _pipInsets,
      );
      _pipPendingOuter = target;
      _pipStallCount++;
      try {
        await windowManager.setSize(target);
      } catch (e) {
        Log.logPrint(e);
        _pipActiveAspect = null;
      }
    }
  }

  @override
  Future<void> onWindowResized() async {
    // 先精确对齐（Windows/macOS），再落盘已纠正后的尺寸
    if (pipAspectLocked && (Platform.isWindows || Platform.isMacOS)) {
      await snapToAspect(_pipActiveAspect!);
    }
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

  // —— 小窗锁定纵横比：薄平台层（内部按 Platform 分支）——
  // 所有方法均先判 pipAspectLocked / 设置项，未锁定则完全空转，不触碰任何新 API。

  /// 同步测量 Windows「外框 − 客户区」内边距（逻辑像素）。
  ///
  /// 改用 win32 读平台实时状态（GetWindowRect−GetClientRect）/ GetDpiForWindow，
  /// 与 Dart 视图 metrics 解耦，消除「隐藏标题栏样式变更后视图 metrics 滞后」的竞态。
  /// macOS 隐藏态 content≈frame、Linux 不使用 insets → 固定 FrameInsets.zero。
  ///
  /// 兜底链：非 Windows → zero；hwnd=0 / 读数返回 0 / h,v 非有限·负·不合理
  ///   → expectedHiddenInsets(dpr)；再失败 → zero（退化为不补偿、直接传 A）。
  FrameInsets measureFrameInsets() {
    // macOS 隐藏态 content==frame；Linux 不使用 insets → 固定 zero。
    if (!Platform.isWindows) return FrameInsets.zero;
    try {
      final hwnd = _findWindowHandle();
      if (hwnd == 0) return FrameInsets.zero;
      final outerPtr = calloc<win32.RECT>();
      final clientPtr = calloc<win32.RECT>();
      try {
        final okOuter = win32.GetWindowRect(hwnd, outerPtr);
        final okClient = win32.GetClientRect(hwnd, clientPtr);
        final dpr = win32.GetDpiForWindow(hwnd) / 96.0;
        final effectiveDpr = (!dpr.isFinite || dpr <= 0) ? 1.0 : dpr;
        // 任一读数失败 → 走理论值兜底
        if (okOuter == 0 || okClient == 0) {
          return PipAspectCalculator.expectedHiddenInsets(effectiveDpr);
        }
        final outer = outerPtr.ref;
        final client = clientPtr.ref;
        final outerW = (outer.right - outer.left).toDouble();
        final outerH = (outer.bottom - outer.top).toDouble();
        final clientW = (client.right - client.left).toDouble();
        final clientH = (client.bottom - client.top).toDouble();
        final h = (outerW - clientW) / effectiveDpr;
        final v = (outerH - clientH) / effectiveDpr;
        final insets = FrameInsets(
          horizontal: h < 0 ? 0 : h,
          vertical: v < 0 ? 0 : v,
        );
        // 不合理（如仍采到正常态标题栏）→ 理论值兜底
        if (!PipAspectCalculator.isPlausibleHiddenInsets(insets, dpr: effectiveDpr)) {
          return PipAspectCalculator.expectedHiddenInsets(effectiveDpr);
        }
        return insets;
      } finally {
        calloc.free(outerPtr);
        calloc.free(clientPtr);
      }
    } catch (e) {
      Log.logPrint(e);
      return FrameInsets.zero;
    }
  }

  /// 进入小窗：施加约束 + 归一化初始尺寸。aspect 非法或设置关闭则直接返回（不施加）。
  ///
  /// 顺序铁律：**先施加约束、后设尺寸**。
  Future<void> applyPipAspect(double aspect) async {
    // 未开启锁定则不施加，完全走旧逻辑
    if (!AppSettingsController.instance.pipLockAspect.value) return;
    if (!PipAspectCalculator.isUsableAspect(aspect)) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    _pipActiveAspect = aspect;
    _pipInsets = measureFrameInsets();
    _pipPendingOuter = null;
    _pipStallCount = 0;

    // 小窗态最小尺寸（按比例推导，长边客户区 ≥320）
    await setPipMinimumSize(aspect);

    // 记忆值是「外框」口径（getSize/GetWindowRect 走 GetWindowRect → 外框），
    // 先换算成客户区长边，避免「外框进、客户区长边用、再 +insets 出」导致的
    // 反复进小窗累积放大（F1 回归：每次 +insets.horizontal，窗口单调无界放大）。
    final w = AppSettingsController.instance.windowPipWidth.value;
    final h = AppSettingsController.instance.windowPipHeight.value;
    final rawLong = PipAspectCalculator.clientLongSideFromOuter(
      outer: Size(w, h),
      insets: _pipInsets,
    );
    final longSide = rawLong > 0 ? rawLong : 400.0; // 兜底：非法/过小时回退默认长边
    final client = PipAspectCalculator.normalizeClientSize(
      memoryLongSide: longSide,
      aspect: aspect,
    );
    final outer = PipAspectCalculator.outerSizeForClient(
      client: client,
      insets: _pipInsets,
    );

    // 先施加约束（Windows/Linux 原生；macOS 不调），后设尺寸
    await _applyAspectRatioConstraint(aspect, outerWidth: outer.width);
    await windowManager.setSize(outer);
  }

  /// 视频比例变化（换线路/清晰度）：锁定中且比例实质变化时，
  /// 保持当前外框宽、按新比例重算外框高并重设 R（内部自比对，未变则空转）。
  Future<void> reapplyPipAspect(double aspect) async {
    if (!pipAspectLocked) return;
    if (!PipAspectCalculator.isUsableAspect(aspect)) return;
    if ((_pipActiveAspect != null) &&
        ((_pipActiveAspect! - aspect).abs() < 1e-9)) {
      // 比例未实质变化：保持当前外框宽，避免换清晰度时窗口尺寸突跳
      return;
    }
    _pipActiveAspect = aspect;
    _pipInsets = measureFrameInsets();
    _pipPendingOuter = null;
    _pipStallCount = 0;

    if (Platform.isWindows) {
      final w = (await windowManager.getSize()).width;
      final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: w,
        aspect: aspect,
        insets: _pipInsets,
      );
      try {
        await windowManager.setAspectRatio(r);
      } catch (e) {
        Log.logPrint(e);
        _pipActiveAspect = null;
        return;
      }
    } else if (Platform.isLinux) {
      // Linux GDK 提示作用于客户区，直接传画面比例 A。
      // 注意：Wayland 下该提示为 no-op（自然降级，不劣于现状）。
      try {
        await windowManager.setAspectRatio(aspect);
      } catch (e) {
        Log.logPrint(e);
        _pipActiveAspect = null;
        return;
      }
    }
    // 精确对齐外框高（Windows/macOS）；Linux 由 GDK 提示保比，不需 setSize
    if (Platform.isWindows || Platform.isMacOS) {
      await snapToAspect(aspect);
    }
  }

  /// 拖动中（仅 Windows）：按当前外框宽重算 R 并 setAspectRatio（不触发回声）。
  Future<void> retuneAspectDuringResize(double aspect) async {
    if (!pipAspectLocked) return;
    if (!Platform.isWindows) return;
    try {
      final w = (await windowManager.getSize()).width;
      final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: w,
        aspect: aspect,
        insets: _pipInsets,
      );
      await windowManager.setAspectRatio(r);
    } catch (e) {
      Log.logPrint(e);
      _pipActiveAspect = null;
    }
  }

  /// 拖动结束（Windows/macOS）：保持外框宽、精确对齐外框高。
  /// 开头先重采样 insets（自愈）：即使进入小窗时偶发采错，松开鼠标后也会
  /// 以当前实际 insets 重新计算，消除残留竞态。
  Future<void> snapToAspect(double aspect) async {
    if (!pipAspectLocked) return;
    if (!Platform.isWindows && !Platform.isMacOS) return; // Linux 无拖动结束事件
    try {
      // 自愈：重采样 insets，若与缓存实质不同则更新
      final fresh = measureFrameInsets();
      if (fresh != _pipInsets) _pipInsets = fresh;
      final cur = await windowManager.getSize();
      final target = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: cur.width,
        aspect: aspect,
        insets: _pipInsets,
      );
      await windowManager.setSize(target);
    } catch (e) {
      Log.logPrint(e);
      _pipActiveAspect = null;
    }
  }

  /// 释放约束（必须在恢复尺寸之前调用）。
  /// Windows→setAspectRatio(0)；Linux→setAspectRatio(-1)（负数！传 0 会把比例设成 0）；
  /// macOS→空实现（未施加原生约束）。
  Future<void> releasePipAspect() async {
    try {
      if (Platform.isWindows) {
        await windowManager.setAspectRatio(0);
      } else if (Platform.isLinux) {
        // Linux 必须传负数才释放约束（判据 aspect_ratio >= 0）
        await windowManager.setAspectRatio(-1);
      }
      // macOS：未施加原生约束，无需释放
    } catch (e) {
      Log.logPrint(e);
    }
    _pipActiveAspect = null;
    _pipPendingOuter = null;
    _pipStallCount = 0;
  }

  /// 小窗态最小尺寸（按比例推导的外框最小值，长边客户区 ≥320）。
  Future<void> setPipMinimumSize(double aspect) async {
    final client = PipAspectCalculator.normalizeClientSize(
      memoryLongSide: 320,
      aspect: aspect,
      minLongSide: 320,
    );
    final outer = PipAspectCalculator.outerSizeForClient(
      client: client,
      insets: _pipInsets,
    );
    try {
      await windowManager.setMinimumSize(outer);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 恢复普通态最小尺寸 _normalMinimumSize。
  Future<void> restoreNormalMinimumSize() async {
    try {
      await windowManager.setMinimumSize(_normalMinimumSize);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 施加原生纵横比约束（Windows 外框比例 R / Linux 客户区比例 A）。
  /// macOS 方案 B 不调原生，故此处空实现。
  Future<void> _applyAspectRatioConstraint(double aspect,
      {double outerWidth = 0}) async {
    try {
      if (Platform.isWindows) {
        final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
          outerWidth: outerWidth,
          aspect: aspect,
          insets: _pipInsets,
        );
        await windowManager.setAspectRatio(r);
      } else if (Platform.isLinux) {
        // Linux GDK 提示作用于客户区，直接传画面比例 A。
        // 注意：Wayland 下该提示为 no-op（自然降级）。
        await windowManager.setAspectRatio(aspect);
      }
      // macOS：方案 B，不调原生约束
    } catch (e) {
      Log.logPrint(e);
      _pipActiveAspect = null;
    }
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
