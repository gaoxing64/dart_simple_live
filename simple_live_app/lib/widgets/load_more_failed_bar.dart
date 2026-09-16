import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';

/// 列表底部「加载更多失败」重试条。
///
/// 下一页加载失败后 [BasePageController.loadFailed] 会加闩停止自动重试
/// （防止"失败 → 骨架消失、内容收缩 → 尺寸变化又触发加载"的请求风暴）。
/// 此前唯一的恢复手段是下拉刷新，但**内容不满一屏时列表根本不可滚动**，
/// "离开底部再触底"无从谈起，门闩再也解不开——表现为列表永远停在半屏。
/// 这里提供一个常驻的显式重试入口。
///
/// 作为列表最后一个条目内联展示，不用 `Positioned` 悬浮层：
/// 悬浮层会盖住最后一行内容。
class LoadMoreFailedBar extends StatelessWidget {
  final BasePageController pageController;

  const LoadMoreFailedBar({required this.pageController, super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppStyle.radius8,
      onTap: pageController.retryLoadMore,
      child: Container(
        alignment: Alignment.center,
        padding: AppStyle.edgeInsetsV12,
        child: Text(
          "加载失败，点击重试",
          style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}
