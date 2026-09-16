import 'package:hive_ce/hive.dart';
part 'follow_snapshot.g.dart';

@HiveType(typeId: 5)
class FollowSnapshot {
  FollowSnapshot({
    required this.expireAt,
    required this.followSnapshotItems,
  });

  @HiveField(0, defaultValue: 0)
  int expireAt;
  @HiveField(1, defaultValue: [])
  List<FollowSnapshotItem> followSnapshotItems;

  factory FollowSnapshot.fromJson(Map<String, dynamic> json) =>
      FollowSnapshot(
        expireAt: json['expireAt'] ?? 0,
        followSnapshotItems: (json['followSnapshotItems'] as List<dynamic>?)
                ?.map((e) => FollowSnapshotItem.fromJson(e))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'expireAt': expireAt,
        'followSnapshotItems':
            followSnapshotItems.map((e) => e.toJson()).toList(),
      };

  Map<String, dynamic> toMap() => toJson();
}

@HiveType(typeId: 4)
class FollowSnapshotItem {
  FollowSnapshotItem({
    required this.id,
    required this.liveStatus,
    required this.cover,
    required this.title,
    required this.online,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  int liveStatus;

  @HiveField(2)
  String cover;

  @HiveField(3)
  String title;

  @HiveField(4)
  int online;

  // 这里原来还有 `@HiveField(5) String lastCover`（「上次直播画面」）。
  // 2026-09-15 删除：关注页改成「开播走卡片、未开播走紧凑行」之后，
  // 未开播那一段根本不渲染封面，这个字段没有消费方；而且拿**上一次**直播的
  // 画面去配**这一次**直播，画面是对不上的，比不显示更糟。
  // 老快照里残留的第 5 个字段会被 Hive 忽略，不需要做迁移。

  factory FollowSnapshotItem.fromJson(Map<String, dynamic> json) =>
      FollowSnapshotItem(
        id: json['id'],
        liveStatus: json['liveStatus'] ?? 0,
        cover: json['cover'] ?? '',
        title: json['title'] ?? '',
        online: json['online'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'liveStatus': liveStatus,
        'cover': cover,
        'title': title,
        'online': online,
      };

  Map<String, dynamic> toMap() => toJson();
}
