import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/duration_2_str_utils.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 封面区域高度。同一屏里所有卡片共用，保证行高一致。
const double _kCoverHeight = 110;

/// 封面右下角人气胶囊的尺寸。
const double _kChipVPadding = 3;
const double _kChipFontSize = 11;
const double _kChipLineHeight = 1.2;
const EdgeInsets _kChipPadding =
    EdgeInsets.symmetric(horizontal: 8, vertical: _kChipVPadding);
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
Color _chipBackground(ColorScheme scheme) =>
    scheme.surfaceContainerHighest.withValues(alpha: 0.75);

/// 直播中的房间卡片。
///
/// 整合布局下它只服务「正在直播」那一段 —— 未开播的房间走紧凑行
/// （`FollowUserItem`）。所以这里**不再需要**状态胶囊（段头已经在说明
/// 这一段是什么）、圆形头像占位、未开播压暗、上次直播画面这些东西，
/// 相应参数也就一并去掉了，卡片重新变回「只认 site + LiveRoomItem」。
class LiveRoomCard extends StatelessWidget {
  final Site site;
  final LiveRoomItem item;
  final Function()? onLongPress;
  final Function()? onFollowRemove;

  /// 累计观看时长（秒），显示在封面下方那行的右侧。<=0 时不显示。
  final int watchDurationSec;

  const LiveRoomCard(
    this.site,
    this.item, {
    super.key,
    this.onLongPress,
    this.onFollowRemove,
    this.watchDurationSec = 0,
  });

  /// 「累计观看 N 小时」。格式化见 [watchDurationText]（和关注页下段的紧凑行共用）。
  String get _watchDurationLabel => watchDurationText(watchDurationSec);

  @override
  Widget build(BuildContext context) {
    return ShadowCard(
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
                child: NetImage(
                  item.cover,
                  fit: BoxFit.cover,
                  height: _kCoverHeight,
                  width: double.infinity,
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
          Padding(
            padding: AppStyle.edgeInsetsH8.copyWith(
              top: 8,
              bottom: 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _kMetaTextStyle,
                            ),
                          ),
                          if (watchDurationSec > 0) ...[
                            AppStyle.hGap4,
                            // 时长是 Row 的非 flex 子项，卡片窄 / 系统字体放大
                            // 时会挤占用户名甚至溢出。用 flex: 0 的 Flexible
                            // 让它按固有宽度摆放、放不下时收缩并省略。
                            Flexible(
                              flex: 0,
                              child: Text(
                                _watchDurationLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _kMetaTextStyle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onFollowRemove != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: "取消关注",
                    onPressed: onFollowRemove,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Remix.dislike_line),
                  )
                ]
              ],
            ),
          )
        ],
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
