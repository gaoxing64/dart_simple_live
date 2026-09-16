import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'dart:ui' as ui;

class FollowUserItem extends StatelessWidget {
  final FollowUser item;
  final Function()? onRemove;
  final Function()? onTap;
  final Function()? onLongPress;
  final bool playing;
  const FollowUserItem({
    required this.item,
    this.onRemove,
    this.onTap,
    this.onLongPress,
    this.playing = false,
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
              item.tag.length > 8
                  ? '${item.tag.substring(0, 8)}...'
                  : item.tag,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      trailing: playing
          ? const SizedBox(
              width: 64,
              child: Center(
                child: Icon(
                  Icons.play_arrow,
                ),
              ),
            )
          : (onRemove == null
              ? null
              : IconButton(
                  tooltip: "取消关注",
                  onPressed: () {
                    onRemove?.call();
                  },
                  icon: const Icon(Remix.dislike_line),
                )),
      onTap: onTap,
      onLongPress: onLongPress,
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
