import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/widgets/m3e_loading_indicator.dart';

/// 全局 loading（`main.dart` 中 `SmartDialog.loadingBuilder` 的返回值）。
///
/// Material 3 Expressive 风格的变形图形，不再套卡片底：SmartDialog 的
/// loading 遮罩（默认 46% 黑）已经提供了背衬，图形直接浮在遮罩之上。
class AppLoaddingWidget extends StatelessWidget {
  const AppLoaddingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: M3ELoadingIndicator(size: 48),
    );
  }
}
