import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 主播详情页头部：头像预览、主播 ID 复制、房间号复制。
class FollowProfileHeader extends StatelessWidget {
  final FollowUser follow;
  final Site site;
  final bool isFollowed;

  const FollowProfileHeader({
    super.key,
    required this.follow,
    required this.site,
    required this.isFollowed,
  });

  Future<void> _copyText(
    BuildContext context,
    String text,
    String successMessage,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      _showBottomMessage(context, successMessage);
    } catch (_) {
      if (!context.mounted) return;
      _showBottomMessage(context, '复制失败');
    }
  }

  void _showBottomMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      Get.snackbar('提示', message, duration: const Duration(seconds: 2));
      return;
    }
    // 与设置页同口径：底部悬浮提示，避免顶部 Toast 遮挡 AppBar。
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 420.0).toDouble(),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _showAvatarPreview(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.width < size.height ? size.width : size.height;
    final side = shortest * 0.72;

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭头像预览',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Container(
                    key: const ValueKey('avatar-preview'),
                    width: side,
                    height: side,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: NetImage(follow.face, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: '关闭头像预览',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Remix.close_line),
                ),
              ),
            ],
          ),
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
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Tooltip(
      message: '查看头像',
      child: Stack(
        children: [
          NetImage(follow.face, width: 72, height: 72, borderRadius: 36),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('follow-avatar'),
                customBorder: const CircleBorder(),
                onTap: () => _showAvatarPreview(context),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLive = follow.liveStatus.value == 2;
    final remark = follow.remark?.trim() ?? '';
    final profile = Row(
      children: [
        _buildAvatar(context),
        AppStyle.hGap12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: '点击复制主播 ID',
                child: InkWell(
                  key: const ValueKey('copy-anchor-id'),
                  borderRadius: AppStyle.radius8,
                  onTap: () => _copyText(context, follow.userName, '已复制主播 ID'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Text(
                      follow.displayName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              // 「显示为昵称」开启时标题已是备注，再重复一行反而冗余；
              // 只有关闭开关、显示主播原名时才把备注单独列出。
              if (remark.isNotEmpty && !follow.showRemarkAsName) ...[
                AppStyle.vGap4,
                Text(
                  '备注：$remark',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              AppStyle.vGap4,
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Image.asset(site.logo, width: 18, height: 18),
                  Text(site.name),
                  Tooltip(
                    message: '点击复制房间号',
                    child: InkWell(
                      key: const ValueKey('copy-room-id'),
                      borderRadius: AppStyle.radius8,
                      onTap: () => _copyText(context, follow.roomId, '已复制房间号'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('房间号 ${follow.roomId}'),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isLive ? scheme.primary : scheme.onSurfaceVariant).withValues(alpha: 0.12),
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
                ],
              ),
              AppStyle.vGap4,
              Text(
                isFollowed ? '关注于 ${Utils.dateFormatWithYear.format(follow.addTime)}' : '尚未关注',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
    final enterButton = FilledButton.icon(
      onPressed: () => AppNavigator.toLiveRoomDetail(site: site, roomId: follow.roomId),
      icon: const Icon(Remix.play_circle_line),
      label: const Text('进入直播间'),
    );

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppStyle.radius16,
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: AppStyle.edgeInsetsA16,
        decoration: BoxDecoration(
          borderRadius: AppStyle.radius16,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  profile,
                  AppStyle.vGap12,
                  enterButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: profile),
                AppStyle.hGap12,
                enterButton,
              ],
            );
          },
        ),
      ),
    );
  }
}
