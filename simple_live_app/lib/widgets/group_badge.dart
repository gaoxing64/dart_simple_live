import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';

/// 关注分组的小胶囊：只展示，不参与任何手势。
///
/// 多分组只显示第一个 + `+N`；第一个名字太长时在胶囊内部省略，`+N` 始终
/// 保留。读屏按全部分组朗读。样式与 `LiveRoomCard` 右下角的人气胶囊同口径。
class GroupBadge extends StatelessWidget {
  final List<String> names;

  /// 胶囊整体宽度上限。卡面约 150dp 时由父级 `Positioned` 再收紧一次；
  /// 紧凑行传 96，给主播名留下足够宽度。
  final double maxWidth;

  const GroupBadge({
    required this.names,
    this.maxWidth = 160,
    super.key,
  });

  static const double _kFontSize = 11;
  static const double _kIconSize = 12;
  static const double _kRadius = 6;
  static const EdgeInsets _kPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);
  static const TextStyle _kTextStyle = TextStyle(
    fontSize: _kFontSize,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final name in names)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textStyle = _kTextStyle.copyWith(color: scheme.onSurfaceVariant);
    final extra = visible.length - 1;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        label: "分组 ${visible.join('、')}",
        child: ExcludeSemantics(
          // 生产环境全局钉了 textScaler=1.0；这里只防单测/外部宿主传入
          // 极端字号时固定尺寸的图标与 +N 撑破胶囊。
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(_kRadius),
              ),
              child: Padding(
                padding: _kPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Remix.folder_3_line,
                      size: _kIconSize,
                      color: scheme.onSurfaceVariant,
                    ),
                    AppStyle.hGap4,
                    // +N 放在 Flexible 外面：组名被省略时数量仍然可见。
                    Flexible(
                      child: Text(
                        visible.first,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                    if (extra > 0) ...[
                      AppStyle.hGap4,
                      Text(
                        "+$extra",
                        maxLines: 1,
                        softWrap: false,
                        style: textStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}