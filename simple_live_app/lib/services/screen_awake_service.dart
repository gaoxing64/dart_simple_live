import 'dart:async';

import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:simple_live_app/app/log.dart';

/// 屏幕常亮服务：把「哪几路需要常亮」按持有者引用计数，最后一份释放才真正熄灭。
///
/// 为什么需要它：`WakelockPlus` 是**进程级全局开关**，而直播间是多开的 ——
/// 每一路各有一个 `PlayerController`。旧实现是「谁起播谁 enable、谁结束/暂停
/// 谁 disable」，于是：
/// * 多开时关掉或断流其中一路，会把其余路的常亮一起灭掉；
/// * 单开时一次断线重连（EOF → `mediaEnd` → disable）也有几百毫秒到几秒的
///   空窗，弱网时足以让系统熄屏；
/// * Windows / macOS / Linux 桌面端同样命中（`mediaEnd` 的 disable 与平台无关）。
///
/// 语义改成「按路持有」：
/// * 起播（`playing=true`）持有一份，暂停 / 停止 / 关闭房间 / 直播确实结束才释放；
/// * 断线重连、换线路**不**释放 —— 那一跳不足以让屏幕熄掉，却足以把正在看直播
///   的用户弹回手动点亮；
/// * 同一持有者重复 acquire 只刷新原因，不重复计数；release 幂等。
///
/// 平台覆盖（wakelock_plus 1.3.3）：Android `FLAG_KEEP_SCREEN_ON`、iOS
/// `isIdleTimerDisabled`、macOS IOPM 断言、Windows
/// `SetThreadExecutionState(ES_DISPLAY_REQUIRED)`、Linux
/// `org.freedesktop.ScreenSaver.Inhibit`。插件调用失败（不支持的平台等）只记
/// 日志 —— 常亮是体验优化，不是播放正确性依赖。
class ScreenAwakeService extends GetxService {
  static ScreenAwakeService get instance => Get.find<ScreenAwakeService>();

  /// 常亮开关的实际执行入口；测试注入假实现，避免碰平台通道。
  final Future<void> Function(bool enable) _toggle;

  ScreenAwakeService({Future<void> Function(bool enable)? toggle})
      : _toggle = toggle ?? _defaultToggle;

  static Future<void> _defaultToggle(bool enable) async {
    await WakelockPlus.toggle(enable: enable);
  }

  final Map<Object, String> _holders = {};

  bool _enabled = false;

  /// 当前持有常亮的持有者数量（调试与测试用）。
  int get holderCount => _holders.length;

  /// 应用侧视角的常亮状态（不代表系统实际状态）。
  bool get enabled => _enabled;

  /// 登记一路需要常亮。同一 owner 重复登记只刷新原因，不重复计数。
  void acquire(Object owner, {String reason = ''}) {
    final wasEmpty = _holders.isEmpty;
    _holders[owner] = reason;
    if (wasEmpty) {
      _apply(true);
    }
  }

  /// 释放一路。未登记过的 owner 静默返回（幂等）。
  void release(Object owner) {
    if (_holders.remove(owner) == null) {
      return;
    }
    if (_holders.isEmpty) {
      _apply(false);
    }
  }

  /// 全量释放（app 退出 / 定时关闭）。
  Future<void> releaseAll() async {
    _holders.clear();
    if (_enabled) {
      await _applyAwait(false);
    }
  }

  /// 不 await：调用方是播放事件回调，不该被平台通道往返拖住。
  void _apply(bool enable) {
    unawaited(_applyAwait(enable));
  }

  Future<void> _applyAwait(bool enable) async {
    _enabled = enable;
    try {
      await _toggle(enable);
    } catch (e, s) {
      Log.e('屏幕常亮切换失败（enable=$enable）: $e', s);
    }
  }
}
