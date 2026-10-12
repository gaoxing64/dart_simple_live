import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'dart:ui' as ui;

/// 行尾动作区的**固定槽宽**。
///
/// 三种形态（在播指示 / 加入多开 / 取消关注）必须共用同一个槽并居中，否则
/// `ListTile` 只对齐**右边缘**、图标中心会跟着各自内容宽度漂：在播指示原本是
/// `SizedBox(width: 64)` 居中（中心距右 32px），两颗 `IconButton` 是 48 宽
/// （中心距右 24px）——混在一列里就是 8px 的锯齿。
///
/// 48 是 `IconButton` 的默认最小尺寸，取它可以让按钮**原样**落进槽里不额外留白，
/// 同时把在播指示也收进同一列。
const double _kTrailingSlotWidth = 48;

/// MaterialIcons 字形里 `play_arrow` 的**墨迹中心**（24px em 盒坐标，实测）。
///
/// 数字来源：解出字体里这个字形的轮廓，按鞋带公式求墨迹包围盒与形心。
/// 见 2026-10-06 的 memory，那里记了脚本与复现方式。
const double _kPlayArrowInkCenterX = 13.50;

/// 同上，`playlist_add` 的墨迹中心。
const double _kPlaylistAddInkCenterX = 12.49;

/// 播放三角的光学补偿（约 -1.01px）。
///
/// WHY 需要它：Material 的设计者把三角往右挪过，让它的**重心**落在盒子中心
/// （三角的重心在 1/3 宽度处、包围盒中心在 1/2，两者天然不重合）。于是
/// `play_arrow` 与 `playlist_add` 的**重心**只差 0.22px，**墨迹中心**却差 1.01px。
/// 一列图标里眼睛比的是墨迹的左右边界，所以三角看上去偏右约 1px ——
/// 2026-10-07 按运行截图逐像素复核确认（截图 2 倍缩放，量得 +2px 即真实 +1px）。
///
/// 这里补的就是这 1px：写成两个实测值相减，而不是 `-1.0` 这种来路不明的魔数，
/// 下次换图标只要重量一次字形就有了新的数。
const Offset _kPlayArrowOpticalNudge = Offset(
  _kPlaylistAddInkCenterX - _kPlayArrowInkCenterX,
  0,
);

class FollowUserItem extends StatelessWidget {
  final FollowUser item;
  final Function()? onRemove;
  final Function()? onTap;
  final Function()? onLongPress;
  final bool playing;

  /// 自定义右侧动作区。为 null 时按原样渲染（[playing] 时一颗静态的 `play_arrow`
  /// 指示「在播」，否则是「取消关注」按钮）。
  ///
  /// 直播间页的关注面板要在这里挂「加入多开」那颗 icon，于是把尾部整块交给调用方。
  /// 首页等处不传 → 产物与改造前逐字相同。
  ///
  /// 传进来的东西会被收进 [_kTrailingSlotWidth] 宽的槽里居中，保证与另外两种形态
  /// 对齐——调用方不必（也不该）自己管宽度。
  final Widget? trailing;

  const FollowUserItem({
    required this.item,
    this.onRemove,
    this.onTap,
    this.onLongPress,
    this.playing = false,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var site = Sites.allSites[item.siteId]!;
    return ListTile(
      contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 4),
      // `ListTile.titleAlignment` 默认是 `threeLine` —— 它按「三行」的高度来定位
      // 内容，两行的条目会被顶到偏上，**底部空出一截**。关注页下段的行高是固定的
      // （`FollowUserPage._kCompactRowExtent`），多出来的空间全堆在下面，上下明显
      // 不对称（用户报过）。改成 center，多出来的空间上下均分。
      titleAlignment: ListTileTitleAlignment.center,
      // 未开播时压暗头像，和网格样式（`LiveRoomCard`）共用同一个蒙版常量。
      // 必须包 `Obx`：`liveStatus` 是 Rx，不订阅的话状态回来后头像不会跟着变。
      leading: Obx(() => _buildFace()),
      title: Text.rich(
        TextSpan(
          text: item.remark?.isNotEmpty == true ? item.remark : item.userName,
          children: [
              WidgetSpan(
                alignment: ui.PlaceholderAlignment.middle,
                child: Obx(
                  () => Offstage(
                    offstage: item.liveStatus.value == 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppStyle.hGap12,
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: item.liveStatus.value == 2
                                ? Colors.green
                                : Colors.grey,
                            borderRadius: AppStyle.radius12,
                          ),
                        ),
                        AppStyle.hGap4,
                        Text(
                          getStatus(item.liveStatus.value),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: item.liveStatus.value == 2
                                ? null
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      subtitle: Wrap(
          runSpacing: 1.0,
          children: [
            Image.asset(
              site.logo,
              width: 20,
            ),
            AppStyle.hGap4,
            Text(
              site.name,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            AppStyle.hGap4,
            Text(
              item.watchDuration ?? "00:00:00",
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            AppStyle.hGap4,
            Text(
              // 归属唯一真源是分组的成员表，这里显示它所属的分组（多个用 · 连接，
              // 整体仍截到 8 字，避免长组名把行尾挤没）。
              () {
                // 本组件还被直播间关注面板等宿主复用，那边（以及单测宿主）
                // 可能没注册 FollowService，此时退回主分组缓存兜底。
                if (!Get.isRegistered<FollowService>()) {
                  return item.tag;
                }
                final names =
                    FollowService.instance.userTagNamesOf(item.id);
                if (names.isEmpty) return '全部';
                final joined = names.join(' · ');
                return joined.length > 8 ? '${joined.substring(0, 8)}...' : joined;
              }(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      trailing: _buildTrailing(),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// 行尾动作区。三种形态一律收进同一个固定宽度的槽并居中。
  ///
  /// WHY 必须收进槽：`ListTile` 只把 trailing 的**右边缘**贴齐，图标中心则随内容
  /// 宽度漂——在播指示是 64 宽的居中盒（中心距右 32），IconButton 是 48 宽
  /// （中心距右 24），两者混在一列里就是 8px 的锯齿。同一份列表里这三种形态会同时
  /// 出现（正在播的那行是在播指示，其余是按钮），所以必须统一。
  Widget? _buildTrailing() {
    final custom = trailing;
    if (custom != null) {
      return SizedBox(
        width: _kTrailingSlotWidth,
        child: Center(child: custom),
      );
    }
    if (playing) {
      // 盒子居中之后，再把三角按字形重心补回那 1px（见 [_kPlayArrowOpticalNudge]）。
      // 这层不能是 const：`Transform.translate` 没有 const 构造。
      return SizedBox(
        width: _kTrailingSlotWidth,
        child: Center(
          child: Transform.translate(
            offset: _kPlayArrowOpticalNudge,
            child: const Icon(Icons.play_arrow),
          ),
        ),
      );
    }
    if (onRemove == null) {
      return null;
    }
    return SizedBox(
      width: _kTrailingSlotWidth,
      child: Center(
        child: IconButton(
          tooltip: "取消关注",
          onPressed: () {
            onRemove?.call();
          },
          icon: const Icon(Remix.dislike_line),
        ),
      ),
    );
  }

  /// 头像。
  ///
  /// 只有明确在播（`liveStatus == 2`）才不上蒙版；读取中（0）也先按未开播压暗，
  /// 与网格样式「没有封面就压暗」的判据一致，避免状态回来时先亮后暗地闪一下。
  /// 注意 `liveStatus` 是 Rx，调用方必须包在 `Obx` 里。
  Widget _buildFace() {
    final face = NetImage(
      item.face,
      width: 48,
      height: 48,
      borderRadius: 24,
    );
    if (item.liveStatus.value == 2) {
      return face;
    }
    return ColorFiltered(
      colorFilter: AppStyle.offlineDim,
      child: face,
    );
  }

  String getStatus(int status) {
    if (status == 0) {
      return "读取中";
    } else if (status == 1) {
      return "未开播";
    } else {
      return "直播中";
    }
  }
}
