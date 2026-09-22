import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 关注页的紧凑成员行：分组卡片内、未分组段、未开播视图共用。
///
/// **没有复用 `FollowUserItem`**，两个原因（沿自原 `_OfflineRow`）：
/// 1. 那是个 `ListTile`，内容定位由 `titleAlignment` / `_isDense` / 三行假定
///    等一整套默认规则决定。放进**固定行高**的网格单元里时内容会偏上
///    （实测：行高 96 逻辑，内容中心比行中心高 11 逻辑像素；
///    改成 `ListTileTitleAlignment.center` 也没纠正过来）。
///    这里用显式的 `Row` + `Center`，位置完全可控。
/// 2. `FollowUserItem` 还被播放器侧 3 处复用，改它的布局会连带影响那边。
///
/// `InkWell` 铺满整个网格单元，所以 hover 高亮是**整行**、内容居中后上下留白相等。
class FollowMemberRow extends StatelessWidget {
  final FollowUser item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  /// 直播中头像的红色描边圈（设计稿样式）。未开播视图不开（整段都没有直播，
  /// 圈是纯噪音）。
  final bool liveRing;

  /// 头像是否可长按拖拽（拖到分组卡片上换组）。
  ///
  /// 拖拽手势**只绑在头像上**：行体的长按/右键仍是操作菜单，同一行里
  /// 「长按弹菜单」与「长按起拖」无法共存。按住头像未到时而先移动了手指，
  /// 手势竞技场会让给滚动，滚动不受影响。不想用拖拽的仍走菜单里的
  /// 「设置分组」。桌面端同理：左键按住头像 500ms 起拖，右键仍是菜单。
  final bool draggable;

  /// 快速重组：是否被勾选。徽标显示在头像右下角。
  final bool selected;

  /// 点头像触发（勾选/取消）。为 null 时头像不拦截点按，
  /// 点头像和点行体一样进直播间。
  ///
  /// 与长按拖拽（[draggable]）互不干扰：tap 与 long-press 是不同手势类型。
  final VoidCallback? onToggleSelect;

  const FollowMemberRow({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onRemove,
    this.liveRing = false,
    this.draggable = false,
    this.selected = false,
    this.onToggleSelect,
    super.key,
  });

  static const double faceSize = 48;

  /// 紧凑行行高：48 头像 + 两行文字，上下各留 16。
  /// 未分组段、分组卡片成员、未开播视图三处共用这一个值。
  static const double rowExtent = 80;

  static String displayName(FollowUser item) =>
      item.remark?.isNotEmpty == true ? item.remark! : item.userName;

  /// 第二行的「平台 · 累计观看 N 小时」。没有观看记录时只显示平台名，
  /// 不留孤零零的分隔符。
  static String durationMeta(Site site, FollowUser item) {
    final duration = watchDurationText(item.watchDurationSec);
    return duration.isEmpty ? site.name : "${site.name} · $duration";
  }

  bool get _isLive => item.liveStatus.value == 2;

  Widget _buildAvatar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final face = NetImage(
      item.face,
      width: faceSize,
      height: faceSize,
      borderRadius: faceSize / 2,
    );
    // 未开播的头像压暗，和网格里那套占位用同一套视觉语言。
    var core = _isLive
        ? face
        : ColorFiltered(colorFilter: AppStyle.offlineDim, child: face);
    if (liveRing && _isLive && !selected) {
      // 直播中：头像描边圈，颜色跟随外观设置的主题色。
      core = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
        child: core,
      );
    }
    if (selected) {
      // 勾选态（设计稿）：头像整体换成主题色对勾圆片，再点一下取消。
      core = Container(
        width: faceSize,
        height: faceSize,
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
        child: const Icon(Icons.check, color: Colors.white, size: 24),
      );
    }
    if (onToggleSelect != null) {
      // 点头像 = 勾选/取消（快速重组）；点行体其他位置仍进直播间。
      core = GestureDetector(onTap: onToggleSelect, child: core);
    }
    return core;
  }

  Widget _buildAvatarWithDrag(BuildContext context) {
    final avatar = _buildAvatar(context);
    if (!draggable) {
      return avatar;
    }
    return LongPressDraggable<FollowUser>(
      data: item,
      feedback: _DragFeedback(item: item),
      childWhenDragging: Opacity(opacity: 0.35, child: avatar),
      child: avatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site = Sites.allSites[item.siteId]!;
    return Material(
      // 勾选态整行铺一层淡主题色底（设计稿）；未勾选保持透明。
      type: selected ? MaterialType.canvas : MaterialType.transparency,
      color: selected
          ? scheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      // 圆角要**三处一起给**才真的圆：Material 的 `borderRadius` + `clipBehavior`
      // 负责把 ink 裁成圆角，InkWell 的 `borderRadius` 负责高亮本身是圆角。
      // 全局 `listTileTheme.shape` 只管 `ListTile`，这里是自己拼的 InkWell，
      // 必须显式指定（否则就是直角，和列表别处不一致 —— 用户报过）。
      borderRadius: AppStyle.radius8,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppStyle.radius8,
        onTap: onTap,
        onLongPress: onLongPress,
        // 桌面端右键 = 长按，和列表别处保持一致。
        onSecondaryTap: onLongPress,
        child: Center(
          child: Padding(
            padding: AppStyle.edgeInsetsL16.copyWith(right: 4),
            child: Row(
              children: [
                _buildAvatarWithDrag(context),
                AppStyle.hGap12,
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface,
                        ),
                      ),
                      AppStyle.vGap4,
                      Row(
                        children: [
                          Image.asset(site.logo, width: 16),
                          AppStyle.hGap4,
                          Expanded(
                            child: Text(
                              // 在播的成员直接看直播标题更有用；未开播才显示
                              // 平台 + 累计观看（没有观看记录时 watchDurationText
                              // 返回空串，不能在末尾留一个孤零零的「·」）。
                              _isLive && item.title.value.isNotEmpty
                                  ? item.title.value
                                  : durationMeta(site, item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    // 统一规格：40dp 圆形高亮。**不要**在这里再叠
                    // `visualDensity: compact` / `padding: zero` /
                    // `constraints: BoxConstraints()` —— 那套组合会把它压到
                    // 16dp，几乎看不见（用户报过）。要更小改
                    // `AppStyle.kIconButtonSize`。
                    style: AppStyle.iconButtonStyle(scheme),
                    tooltip: "取消关注",
                    onPressed: onRemove,
                    icon: const Icon(Remix.dislike_line),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽时跟随指针的浮块：小头像 + 名字胶囊。
class _DragFeedback extends StatelessWidget {
  final FollowUser item;
  const _DragFeedback({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppStyle.radius24,
          border: Border.all(color: scheme.primary, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NetImage(item.face, width: 32, height: 32, borderRadius: 16),
            AppStyle.hGap8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                FollowMemberRow.displayName(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
