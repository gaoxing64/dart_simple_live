import 'package:material_ui/material_ui.dart';

import 'package:simple_live_app/app/app_style.dart';

/// 列表底部「已经没有更多」的提示条。
///
/// 为什么需要它：内容不足一屏时列表不可滚动，底部那片空白没有任何解释，
/// 用户会以为还在加载或以为列表坏了。与其继续请求重复数据把空白填上，
/// 不如明确告诉用户「就这些了」。
///
/// 是否展示由调用方判断（`BasePageController.showEndBar`，判据是「已经没有
/// 下一页」），所以本组件不需要 controller——它只负责长什么样。
///
/// 与 [LoadMoreFailedBar] 互斥：那条要求 `canLoadMore` 为 true（还有下一页
/// 只是失败了），本条要求为 false（确实没有下一页了）。
///
/// 作为列表最后一个条目内联展示，不用 `Positioned` 悬浮层——悬浮层会盖住
/// 最后一行内容。
class PageEndBar extends StatelessWidget {
  const PageEndBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: AppStyle.edgeInsetsV12,
      child: Text(
        '没有更多了',
        style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
      ),
    );
  }
}
