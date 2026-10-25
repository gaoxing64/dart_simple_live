import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 显式打开预览卡片：220ms 淡入 + 96% → 100% 轻微缩放，关闭反向播放。
///
/// 不用 `Get.dialog` 的默认线性淡入：桌面端 300ms 线性透明度变化观感很弱，
/// 看起来像直接出现。这里同时动透明度和缩放，开关都有明确但不过度的过渡。
Future<void> showFollowCardPreviewDialog({
  required FollowUser item,
  required List<String> groupNames,
  required VoidCallback onSetGroup,
  required VoidCallback onViewDetail,
}) {
  return Get.generalDialog(
    barrierDismissible: true,
    barrierLabel: '关闭主播预览',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return FollowCardPreviewDialog(
        item: item,
        groupNames: groupNames,
        onSetGroup: onSetGroup,
        onViewDetail: onViewDetail,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 关注卡片右键 / 长按后弹出的预览卡片。
///
/// 参考 PiliNara 的卡片预览交互：先展示当前封面和标题，再把原本底部菜单里的
/// 「设置分组 / 查看详情」收成右下角两个图标按钮。点图标后先关预览，再执行
/// 原动作，避免弹层叠着弹层。
class FollowCardPreviewDialog extends StatelessWidget {
  final FollowUser item;
  final List<String> groupNames;
  final VoidCallback onSetGroup;
  final VoidCallback onViewDetail;

  const FollowCardPreviewDialog({
    super.key,
    required this.item,
    this.groupNames = const [],
    required this.onSetGroup,
    required this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site = Sites.allSites[item.siteId];
    final cover = item.cover.value;
    final title = item.title.value.trim();
    final isLive = item.liveStatus.value == 2;
    final tags = [
      for (final tag in groupNames)
        if (tag.trim().isNotEmpty) tag.trim(),
    ];
    final displayTags = tags.isEmpty ? const ['未分组'] : tags;
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 桌面端按窗口比例放大，移动端保持窗口减边距；封面图的分辨率不参与
    // 布局计算，只由这里的宽度和下方 AspectRatio 决定显示尺寸。
    final preferredWidth = screenWidth * 0.62;
    final maxWidth = screenWidth >= 700
        ? preferredWidth.clamp(520.0, 760.0).toDouble()
        : screenWidth - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          key: const ValueKey('follow-preview-card'),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppStyle.radius16,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: cover.isNotEmpty
                      ? NetImage(cover, fit: BoxFit.cover)
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: NetImage(
                            item.face,
                            width: 88,
                            height: 88,
                            borderRadius: 44,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '未开播' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                    AppStyle.vGap4,
                    Wrap(
                      key: const ValueKey('preview-meta-row'),
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (site != null) Image.asset(site.logo, width: 16, height: 16),
                        Text(
                          site?.name ?? item.siteId,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isLive ? scheme.primary : scheme.onSurfaceVariant)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isLive ? '直播中' : '未开播',
                            style: TextStyle(
                              fontSize: 12,
                              color: isLive ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // 标签跟随平台 / 直播状态排布，空间足够时同一行，不单独占一行。
                        for (final tag in displayTags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    AppStyle.vGap4,
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: '设置分组',
                          style: AppStyle.iconButtonStyle(scheme),
                          onPressed: () {
                            Get.back();
                            onSetGroup();
                          },
                          icon: const Icon(Remix.price_tag_3_line),
                        ),
                        IconButton(
                          tooltip: '查看详情',
                          style: AppStyle.iconButtonStyle(scheme),
                          onPressed: () {
                            Get.back();
                            onViewDetail();
                          },
                          icon: const Icon(Remix.information_line),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
