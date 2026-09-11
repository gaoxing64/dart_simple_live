import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// 应用级滚动行为：让桌面端也能用鼠标左键直接拖动滚动内容。
///
/// Flutter 默认的 [ScrollBehavior.dragDevices] 只包含「触摸类」设备
/// （touch / stylus / invertedStylus / trackpad / unknown），**鼠标被排除在外**，
/// 因此在 Windows / macOS / Linux 上按住鼠标左键拖动不会滚动 [Scrollable]，
/// 只能靠滚轮或滚动条。移动端没有这条限制，于是同一个页面在两端手感不一致：
/// 手机上能左右滑动切换平台标签、上下拖动列表，桌面上却只能点标签、拖滚动条。
///
/// 注意范围（别把它当成「全局都拖不动」的根据）：easy_refresh 会把自己的子树
/// 再包一层 `ERScrollBehavior`，那个 behavior 本来就把 dragDevices 放开为全部
/// 指针设备，所以 [PageGridView] / [PageListView] 这类被 EasyRefresh 包住的列表
/// 在引入本类之前就已经能用鼠标拖。本类真正补齐的是：
/// - TabBarView / PageView（平台标签左右切页）——它们不在 EasyRefresh 里；
/// - 其它未被 EasyRefresh 包住的滚动区，例如直播间的聊天列表。
///
/// 顺带保证两端一致：
/// - 上下拖动：列表跟随鼠标滚动（与 easy_refresh 内部 ERScrollBehavior 的行为对齐）；
/// - 左右拖动：TabBarView / PageView 跟随鼠标切换平台。
///
/// 放开范围仅限 [Scrollable] 自身的拖动识别器，不受影响的有：
/// - 使用自带手势的控件（ReorderableListView 的拖拽排序、Slider、播放器手势区等）
///   不依赖 [dragDevices]；
/// - 声明了 `NeverScrollableScrollPhysics` 的列表本就不可拖动，不会被放开。
///
/// 已知取舍：鼠标进入 dragDevices 后，可滚动区域内的 `SelectableText` 拖选会与
/// 列表的拖动识别器同场竞争（Flutter 默认把鼠标排除在外，正是为了保住纯鼠标
/// 拖选）。移动端不受影响。若后续在桌面端确认「聊天区拖选文字」被抢，需要把
/// 放开范围收窄到横向翻页场景，而不是继续全局放开。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// 全部指针设备。用集合缓存，避免每次 `get dragDevices` 都重新分配。
  ///
  /// 取不可变视图：这是进程级共享实例，而 `dragDevices` 的契约是「只读」，
  /// 万一有调用方对它 add / remove，污染的是所有 [Scrollable]。
  static final Set<PointerDeviceKind> _allDragDevices =
      Set.unmodifiable(PointerDeviceKind.values);

  @override
  Set<PointerDeviceKind> get dragDevices => _allDragDevices;
}
