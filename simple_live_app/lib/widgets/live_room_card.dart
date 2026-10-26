import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/group_badge.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 封面区域高度。同一屏里所有卡片共用，保证行高一致。
const double _kCoverHeight = 110;

/// 封面右下角人气胶囊的尺寸。
const double _kChipVPadding = 3;
const double _kChipFontSize = 11;
const double _kChipLineHeight = 1.2;
const EdgeInsets _kChipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: _kChipVPadding);
const double _kChipRadius = 6;

/// 封面下方那行元信息（主播名 / 累计观看时长）的文字样式。
const TextStyle _kMetaTextStyle = TextStyle(
  height: 1.4,
  fontSize: 12,
  color: Colors.grey,
);

/// 封面右下角人气胶囊的底色。
///
/// 不写死黑/白：跟着主题走，深浅色两套配色都不别扭。
/// 透明度按用户要求从 `0.92` 降到 **`0.75`** —— 让封面透出来一点、底托不那么"糊"。
/// 代价是最坏情况（浅色主题压深封面、深色主题压亮封面）对比度会下降，
/// 实测数据见 memory 2026-09-15。
Color _chipBackground(ColorScheme scheme) => scheme.surfaceContainerHighest.withValues(alpha: 0.75);

/// 房间卡片（首页 / 搜索 / 分类 / 关注页的卡面视图共用）。
///
/// 关注页里它同时服务「直播中」和「未开播」两段：未开播没有封面，由
/// [avatar] 在封面区画一个**圆形头像占位**（见 `_AvatarCover`），
/// 让两种状态一眼可分。
///
/// 它**不带取关按钮、也不显示累计观看时长**（用户明确要求）：卡面只负责
/// 吸引点击进直播间，「统计」与「取关」这两件事统一收在紧凑行
/// （`FollowMemberRow`）。主播要取关走「点卡片 → 直播间 → 取消关注」。
class LiveRoomCard extends StatelessWidget {
  final Site site;
  final LiveRoomItem item;
  final Function()? onLongPress;

  /// 勾选态（多开播放的批量选择用）：卡面加强调色描边 + 光晕。
  final bool selected;

  /// 点**主播名那一行**切换勾选（卡面布局没有头像可点，而多开最常见的就是
  /// 「直播中」这个卡面视图）。为 null 时主播名不可点，首页等处保持原样。
  final VoidCallback? onToggleSelect;

  /// 没有封面时的圆形占位头像（关注页未开播的卡面用）。
  ///
  /// 为空时保持原行为（`NetImage` 无图显示 logo）。给值时头像以圆形
  /// 居中盖在封面区，**不再拉满整块封面** —— 拉满和直播封面混在一起，
  /// 一眼分不出在播与否。
  final String avatar;

  /// 该主播所属的分组名（关注页传入；首页 / 搜索 / 分类保持空表）。
  ///
  /// 只在封面左上角画一枚展示用小胶囊，不改变卡高与底部文本块。
  final List<String> groupNames;

  const LiveRoomCard(
    this.site,
    this.item, {
    super.key,
    this.onLongPress,
    this.selected = false,
    this.onToggleSelect,
    this.avatar = '',
    this.groupNames = const [],
  });

  @override
  Widget build(BuildContext context) {
    final card = ShadowCard(
      onTap: () {
        AppNavigator.toLiveRoomDetail(site: site, roomId: item.roomId);
      },
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                child: item.cover.isEmpty && avatar.isNotEmpty
                    ? _AvatarCover(avatar: avatar)
                    : NetImage(
                        item.cover,
                        fit: BoxFit.cover,
                        height: _kCoverHeight,
                        width: double.infinity,
                      ),
              ),
              // 关注页的分组归属：封面左上角，只展示、不吃手势。
              // 与右下角人气胶囊错开；未分组时完全不渲染。
              if (groupNames.isNotEmpty)
                Positioned(
                  left: 6,
                  top: 6,
                  right: 6,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IgnorePointer(
                      child: GroupBadge(names: groupNames),
                    ),
                  ),
                ),
              // 平台图标挪进了右下角的人气胶囊（用户要求），这里不再单独放一个
              // 平台框 —— 同一张卡片上同一个 logo 出现两次是冗余。
              // ⚠️ 胶囊必须始终渲染：它是卡片上唯一的平台标识。虎牙 / Twitch
              // 等平台接口可能不下发人数、或上层走默认的 online: 0，
              // 整块不渲染的话多平台混排的列表里就什么都剩不下了。
              Positioned(
                right: 6,
                bottom: 6,
                child: _OnlineChip(site: site, online: item.online),
              ),
            ],
          ),
          // 封面下方只有标题 + 主播名两行，右侧不再挂任何东西（没有时长、没有按钮）。
          Padding(
            padding: AppStyle.edgeInsetsH8.copyWith(
              top: 8,
              bottom: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _buildUserName(),
              ],
            ),
          )
        ],
      ),
    );

    if (onToggleSelect == null) {
      return card;
    }
    // 强调色描边 + 光晕：卡面布局里没有头像那圈「选中环」，勾选态只能靠卡面本身表达。
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: card,
    );
  }

  /// 主播名一行。选择态下整行可点（比只点几个字好按），点它就切换勾选；
  /// 标题与封面仍然整卡进直播间。
  Widget _buildUserName() {
    final label = Text(
      item.userName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _kMetaTextStyle,
    );
    final onToggle = onToggleSelect;
    if (onToggle == null) {
      return label;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: SizedBox(width: double.infinity, child: label),
    );
  }
}

/// 封面区的圆形头像占位（未开播 / 无封面时）。
///
/// 中性底 + 居中的圆形头像：整块封面是「占位」而不是一张直播画面，
/// 和直播中的卡面一眼能分开。头像沿用关注页未开播的压暗口径
/// （[AppStyle.offlineDim]），跨视图的视觉语言保持一致。
class _AvatarCover extends StatelessWidget {
  final String avatar;

  const _AvatarCover({required this.avatar});

  /// 圆形头像直径：与**原来的图标占位同尺寸**。
  ///
  /// 原来无封面时 `NetImage` 显示 512×512 的 logo，在 `width: infinity,
  /// height: 110` 的封面里按 `BoxFit.scaleDown` 缩成 110×110 —— 也就是填满
  /// 封面高度。头像沿用这个尺寸，才是「卡面占位」的量级；照紧凑行的 48/56
  /// 放进来会小得像漏了一张缩略图。
  static const double _kAvatarSize = _kCoverHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      // key 供测试定位：断言「未开播的卡面走圆形占位」而不依赖内部结构。
      key: const ValueKey('card-avatar-cover'),
      height: _kCoverHeight,
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: ColorFiltered(
        colorFilter: AppStyle.offlineDim,
        child: NetImage(
          avatar,
          width: _kAvatarSize,
          height: _kAvatarSize,
          borderRadius: _kAvatarSize / 2,
        ),
      ),
    );
  }
}

/// 封面右下角的人气胶囊：**平台图标 + 在线人数**。
///
/// 左边原来是火焰图标，换成平台图标（用户要求）—— 顺带把「哪个平台」这条信息
/// 也带进来了，所以卡片上不再需要单独的平台框。
/// 在线人数为 0 时只显示平台图标（保住「这是哪个平台」这一条信息）。
class _OnlineChip extends StatelessWidget {
  final Site site;
  final int online;
  const _OnlineChip({required this.site, required this.online});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: _kChipPadding,
      decoration: BoxDecoration(
        color: _chipBackground(scheme),
        borderRadius: BorderRadius.circular(_kChipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            site.iconData,
            size: 12,
            color: scheme.onSurfaceVariant,
          ),
          if (online > 0) ...[
            AppStyle.hGap4,
            Text(
              Utils.onlineToString(online),
              style: TextStyle(
                fontSize: _kChipFontSize,
                height: _kChipLineHeight,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
