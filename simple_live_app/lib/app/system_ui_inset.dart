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
/// * 平时（未全屏、也没有等待中的恢复）平台**持续**上报「没有底部系统栏」时会清空
///   该方向的记忆值，正常场景不会被多留白。注意「持续」二字：退出全屏（尤其是
///   横屏全屏转回竖屏）时平台会先夹一段 0、随后才补报真实高度，清空需要等
///   [clearDelay] 才会生效 —— 立即清空会让过渡期那一帧的避让高度变成 0，
///   底部按钮被导航条压住（MIX 3 实测，见 git 记录）。
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

  /// 平台上报 0 的起始时刻（用于「持续为 0 才清空」的去抖）
  static DateTime? _zeroSince;

  /// 平台上报 0 后，需持续该时长才认定「该方向确实没有底部系统栏」并清空记忆值。
  ///
  /// 退出全屏时（尤其是横屏全屏转回竖屏）平台会先夹一帧/一段 0，随后才是真实
  /// 高度；若立即清空，那一帧算出的避让高度就是 0 —— 表现为底部按钮被导航条
  /// 压住。见本文件顶部说明与 `test/system_ui_inset_test.dart` 的回归用例。
  @visibleForTesting
  static Duration clearDelay = const Duration(milliseconds: 400);

  /// 已记住的底部高度（横竖屏取较大值，仅用于测试/调试）
  @visibleForTesting
  static double get remembered =>
      _portrait > _landscape ? _portrait : _landscape;

  /// 进入全屏：系统栏即将被隐藏，冻结当前记忆值
  static void markHidden() {
    _hidden = true;
    _awaitingReport = false;
    _zeroSince = null;
  }

  /// 退出全屏：系统栏即将恢复，开始等待平台重新上报
  static void markRestoring() {
    _hidden = false;
    _awaitingReport = true;
    _zeroSince = null;
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

    double result;
    if (bar > 0) {
      // 平台上报了系统栏高度：记录并采信
      if (portrait) {
        _portrait = bar;
      } else {
        _landscape = bar;
      }
      _awaitingReport = false;
      _zeroSince = null;
      result = reported;
    } else if (_hidden || _awaitingReport) {
      // 系统栏被隐藏（上报 0 属正常），或退出全屏后平台还没重新上报：
      // 用同方向的记忆值兜底
      _zeroSince = null;
      result = remembered;
    } else {
      // 平台报告「该方向没有底部系统栏」。但退出全屏/横竖屏切换的过渡期里，
      // 平台会先夹一段 0 再报真实高度，直接清空会让这一帧的避让高度变成 0；
      // 因此要求「持续为 0」超过 [clearDelay] 才清空，期间仍用记忆值兜底。
      _zeroSince ??= DateTime.now();
      if (DateTime.now().difference(_zeroSince!) >= clearDelay) {
        if (portrait) {
          _portrait = 0;
        } else {
          _landscape = 0;
        }
        result = reported;
      } else {
        result = remembered;
      }
    }
    return result;
  }

  /// 清空状态（仅测试使用）
  @visibleForTesting
  static void reset() {
    _portrait = 0;
    _landscape = 0;
    _hidden = false;
    _awaitingReport = false;
    _zeroSince = null;
    clearDelay = const Duration(milliseconds: 400);
  }
}
