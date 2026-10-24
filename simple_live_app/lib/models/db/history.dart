import 'package:hive_ce/hive_ce.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/app/utils/dynamic_filter.dart';

part 'history.g.dart';

@HiveType(typeId: 2)
class History implements Mappable {
  History({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.updateTime,
    this.watchDuration = "00:00:00",
    this.syncDuration = 0,
    Map<String, int>? dailyWatchSeconds,
    Map<String, int>? dailySyncSeconds,
  })  : dailyWatchSeconds = Map<String, int>.from(dailyWatchSeconds ?? const {}),
        dailySyncSeconds = Map<String, int>.from(dailySyncSeconds ?? const {});

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
  DateTime updateTime;

  @HiveField(6)
  String? watchDuration; // "00:00:00"

  @HiveField(7)
  int syncDuration;

  @HiveField(8, defaultValue: <String, int>{})
  Map<String, int> dailyWatchSeconds;

  @HiveField(9, defaultValue: <String, int>{})
  Map<String, int> dailySyncSeconds;

  Duration get duration => watchDuration!.toDuration(); //for filter

  factory History.fromJson(Map<String, dynamic> json) => History(
        id: json["id"],
        roomId: json["roomId"],
        siteId: json["siteId"],
        userName: json["userName"],
        face: json["face"],
        updateTime: DateTime.parse(json["updateTime"]),
        watchDuration: json["watchDuration"] ?? "00:00:00",
        syncDuration: json["syncDuration"] ?? 0,
        dailyWatchSeconds: _dailySecondsFromJson(json["dailyWatchSeconds"]),
        dailySyncSeconds: _dailySecondsFromJson(json["dailySyncSeconds"]),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "roomId": roomId,
        "siteId": siteId,
        "userName": userName,
        "face": face,
        "updateTime": updateTime.toString(),
        "watchDuration": watchDuration ?? "00:00:00",
        "syncDuration": syncDuration,
        "dailyWatchSeconds": dailyWatchSeconds,
        "dailySyncSeconds": dailySyncSeconds,
      };

  History copyWith({
    String? id,
    String? watchDuration,
    int? syncDuration,
    DateTime? updateTime,
    String? roomId,
    String? siteId,
    String? userName,
    String? face,
    Map<String, int>? dailyWatchSeconds,
    Map<String, int>? dailySyncSeconds,
  }) {
    return History(
      id: id ?? this.id,
      watchDuration: watchDuration ?? this.watchDuration,
      syncDuration: syncDuration ?? this.syncDuration,
      updateTime: updateTime ?? this.updateTime,
      roomId: roomId ?? this.roomId,
      siteId: siteId ?? this.siteId,
      userName: userName ?? this.userName,
      face: face ?? this.face,
      dailyWatchSeconds: dailyWatchSeconds ?? this.dailyWatchSeconds,
      dailySyncSeconds: dailySyncSeconds ?? this.dailySyncSeconds,
    );
  }

  @override
  Map<String, dynamic> toMap() => toJson();
}

Map<String, int> _dailySecondsFromJson(dynamic value) {
  if (value is! Map) {
    return {};
  }
  final result = <String, int>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      continue;
    }
    final rawSeconds = entry.value;
    final seconds = rawSeconds is num
        ? (rawSeconds.isFinite ? rawSeconds.toInt() : null)
        : rawSeconds is String
            ? int.tryParse(rawSeconds)
            : null;
    if (seconds != null) {
      result[entry.key as String] = seconds;
    }
  }
  return result;
}
