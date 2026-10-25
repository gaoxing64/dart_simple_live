import 'package:get/get.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:simple_live_app/app/utils/dynamic_filter.dart';
import 'package:simple_live_app/models/db/follow_snapshot.dart';

part 'follow_user.g.dart';

@HiveType(typeId: 1)
class FollowUser implements Mappable {
  FollowUser({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.addTime,
    this.watchDuration = "00:00:00",
    this.remark = "",
    this.showRemarkAsName = true,
    this.romanName = "",
    this.syncDuration = 0,
    this.watchDurationSec = 0,
    this.deleted = false,
    this.updateTime = 0,
    this.lastWatchTime = 0,
  });

  ///id=siteId_roomId
  @HiveField(0)
  String id;

  @HiveField(1)
  String roomId;

  @HiveField(2)
  String siteId;

  @HiveField(3)
  String userName;

  @HiveField(4)
  String face;

  @HiveField(5)
  DateTime addTime;

  @Deprecated('Use watchDurationSec instead')
  @HiveField(6)
  String? watchDuration; // "00:00:00"

  // 这里原来还有 @HiveField(7) 的「主分组」展示缓存 `String tag`。
  // 2026-10-12 删除：归属唯一真源是 `FollowUserTag.userId`（多分组归属），
  // 展示取 `FollowService.userTagNamesOf`。旧记录里的 field 7 读取时被忽略，
  // 旧版本 app 读新记录时按它的旧逻辑回退「全部」，成员表本身不受影响。

  @HiveField(8)
  String? remark;

  /// 是否把 [remark] 作为昵称替换 [userName] 显示。
  ///
  /// 默认 true：老版本没有这个字段，而旧逻辑只要备注非空就自动用备注当名字；
  /// 新字段默认开启，老用户升级后显示行为不变，只有主动关掉才回到主播原名。
  @HiveField(15, defaultValue: true)
  bool showRemarkAsName;

  /// 实际展示名：开关开启且备注非空时用备注，否则回退主播原名。
  String get displayName {
    final nickname = remark?.trim() ?? '';
    return showRemarkAsName && nickname.isNotEmpty ? nickname : userName;
  }

  @HiveField(9)
  String? romanName;

  @HiveField(10, defaultValue: 0)
  int syncDuration; // 需要同步增加的观看时长

  @HiveField(11, defaultValue: 0)
  int watchDurationSec; // watchDuration -> sec easy to calculate

  /// 墓碑标记：true表示已取消关注
  @HiveField(12, defaultValue: false)
  bool deleted;

  /// 墓碑更新时间（秒级时间戳），用于定期清理
  @HiveField(13, defaultValue: 0)
  int updateTime;

  // 最后一次观看
  @HiveField(14, defaultValue: 0)
  int? lastWatchTime;

  /// 直播状态
  /// 0=未知(加载中) 1=未开播 2=直播中
  Rx<int> liveStatus = 0.obs;

  /// 直播封面（只在直播中有值，未开播会被清空）
  Rx<String> cover = "".obs;

  // 这里原来还有 `Rx<String> lastCover`（「上次直播画面」）。
  // 2026-09-15 删除，理由见 `FollowSnapshotItem` 里的注释。

  /// 直播标题
  Rx<String> title = "".obs;

  Rx<int> online = 0.obs;

  factory FollowUser.fromJson(Map<String, dynamic> json) => FollowUser(
        id: json['id'],
        roomId: json['roomId'],
        siteId: json['siteId'],
        userName: json['userName'],
        face: json['face'],
        addTime: DateTime.parse(json['addTime']),
        watchDuration: json["watchDuration"] ?? "00:00:00",
        remark: json["remark"] ?? "",
        showRemarkAsName: json["showRemarkAsName"] ?? true,
        romanName: json["romanName"] ?? "",
        syncDuration: json["syncDuration"] ?? 0,
        watchDurationSec: json["watchDurationSec"] ?? 0,
        deleted: json["deleted"] ?? false,
        updateTime: json["updateTime"] ?? 0,
        lastWatchTime: json["lastWatchTime"] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'siteId': siteId,
        'userName': userName,
        'face': face,
        'addTime': addTime.toString(),
        "watchDuration": watchDuration ?? "00:00:00",
        "remark": remark,
        "showRemarkAsName": showRemarkAsName,
        "romanName": romanName,
        "syncDuration": syncDuration,
        "watchDurationSec": watchDurationSec,
        "deleted": deleted,
        "updateTime": updateTime,
        "lastWatchTime": lastWatchTime,
      };

  @override
  Map<String, dynamic> toMap() => toJson();

  FollowSnapshotItem toSnapshot() => FollowSnapshotItem(
        id: id,
        liveStatus: liveStatus.value,
        cover: cover.value,
        title: title.value,
        online: online.value,
      );

  void applySnapshot(FollowSnapshotItem snapshot) {
    liveStatus.value = snapshot.liveStatus;
    cover.value = snapshot.cover;
    title.value = snapshot.title;
    // 和 FollowService.updateLiveInformation 保持同一个不变量：未开播的房间
    // online 一律为 0。老快照里可能存着上一次直播的人气值，这里再兜一道。
    online.value = snapshot.liveStatus == 2 ? snapshot.online : 0;
  }
}
