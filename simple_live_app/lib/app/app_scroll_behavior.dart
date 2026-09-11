import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// 应用级滚动行为：让桌面端也能用鼠标左键直接拖动滚动内容。
///
/// Flutter 默认的 [ScrollBehavior.dragDevices] 只包含「触摸类」设备
/// （touch / stylus / invertedStylus / trackpad / unknown），**鼠标被排除在外**，
/// 因此在 Windows / macOS / Linux 上按住鼠标左键拖动不会滚动任何 [Scrollable]，
/// 只能靠滚轮或滚动条。移动端没有这条限制，于是同一个页面在两端手感不一致：
/// 手机上能左右滑动切换平台标签、上下拖动列表，桌面上却只能点标签、拖滚动条。
///
/// 这里把 [dragDevices] 放开为全部指针设备，使桌面端与移动端保持一致：
/// - 上下拖动：列表跟随鼠标滚动（与 easy_refresh 内部 ERScrollBehavior 的行为对齐）；
/// - 左右拖动：TabBarView / PageView 跟随鼠标切换平台。
///
/// 放开范围仅限 [Scrollable] 自身的拖动识别器，不受影响的有：
/// - 使用自带手势的控件（ReorderableListView 的拖拽排序、Slider、播放器手势区等）
///   不依赖 [dragDevices]；
/// - 声明了 `NeverScrollableScrollPhysics` 的列表本就不可拖动，不会被放开。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// 全部指针设备。用集合缓存，避免每次 `get dragDevices` 都重新分配。
  static final Set<PointerDeviceKind> _allDragDevices =
      PointerDeviceKind.values.toSet();

  @override
  Set<PointerDeviceKind> get dragDevices => _allDragDevices;
}
