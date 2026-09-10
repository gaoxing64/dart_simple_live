import 'package:flutter/widgets.dart';

/// 底部系统栏（Android 导航条 / 手势「小白条」）避让高度的可靠来源。
///
/// 进全屏时系统栏会被隐藏，此时平台上报的底部 inset 必然是 0；退出全屏后系统栏
/// 会重新出现，但部分设备（实测 Flyme / Android 16、targetSdk 37）不会再把恢复后的
/// 高度上报给 Flutter，或者上报明显滞后于页面重建。于是 [MediaQuery.padding] 会停留
/// 在 0，底部按钮（例如直播间的刷新键）就被导航条 / 小白条压住。
///
/// 这里按横竖屏分别记住「系统栏可见时最后一次上报的底部高度」，只在系统栏被隐藏
/// 或退出全屏后平台尚未重新上报时用它替代上报值：
///
/// * 平台一旦上报有效值就立即采信，回到平台值；
/// * 记忆值按方向分开存：进全屏会旋转（竖屏 → 横屏全屏 → 竖屏），横屏时的底部
///   系统栏位置可能不同（三键导航在横屏时移到侧边，底部高度就是 0），分开存可以
///   避免退出全屏后误用另一个方向的高度；
/// * 平时（未全屏、也没有等待中的恢复）平台上报「没有底部系统栏」时会清空该方向的
///   记忆值，正常场景不会被多留白。
///
/// 因此正常运行时行为与直接读 [MediaQuery] 一致，只有「平台漏报」这一种异常状态
/// 会走记忆值。
class SystemUiBottomInset {
  SystemUiBottomInset._();

  /// 竖屏时最后一次上报的底部高度（逻辑像素）
  static double _portrait = 0;

  /// 横屏时最后一次上报的底部高度（逻辑像素）
  static double _landscape = 0;

  /// 系统栏是否被应用隐藏（全屏中）
  static bool _hidden = false;

  /// 退出全屏后是否还在等平台重新上报
  static bool _awaitingReport = false;

  /// 已记住的底部高度（横竖屏取较大值，仅用于测试/调试）
  @visibleForTesting
  static double get remembered =>
      _portrait > _landscape ? _portrait : _landscape;

  /// 进入全屏：系统栏即将被隐藏，冻结当前记忆值
  static void markHidden() {
    _hidden = true;
    _awaitingReport = false;
  }

  /// 退出全屏：系统栏即将恢复，开始等待平台重新上报
  static void markRestoring() {
    _hidden = false;
    _awaitingReport = true;
  }

  /// 由平台上报值解析出实际需要避让的底部高度
  ///
  /// * [reported]：打算使用的上报值，通常是 `MediaQuery.padding.bottom`
  ///   （键盘弹出时该值会收缩到 0，语义由调用方决定）；
  /// * [systemBar]：平台上报的底部系统栏**原始**高度，通常是
  ///   `MediaQuery.viewPadding.bottom`，用来区分「键盘遮挡，系统栏仍在上报」与
  ///   「平台没有上报系统栏」；不传时等于 [reported]；
  /// * [viewSize]：当前视图尺寸，用于区分横竖屏。
  static double resolve(
    double reported, {
    double? systemBar,
    required Size viewSize,
  }) {
    final bar = systemBar ?? reported;
    final bool portrait = viewSize.height >= viewSize.width;
    final double remembered = portrait ? _portrait : _landscape;

    if (bar > 0) {
      // 平台上报了系统栏高度：记录并采信
      if (portrait) {
        _portrait = bar;
      } else {
        _landscape = bar;
      }
      _awaitingReport = false;
      return reported;
    }

    if (_hidden || _awaitingReport) {
      // 系统栏被隐藏（上报 0 属正常），或退出全屏后平台还没重新上报：
      // 用同方向的记忆值兜底
      return remembered;
    }

    // 正常状态下平台报告「该方向没有底部系统栏」：清空这一方向的记忆值
    if (portrait) {
      _portrait = 0;
    } else {
      _landscape = 0;
    }
    return reported;
  }

  /// 清空状态（仅测试使用）
  @visibleForTesting
  static void reset() {
    _portrait = 0;
    _landscape = 0;
    _hidden = false;
    _awaitingReport = false;
  }
}
