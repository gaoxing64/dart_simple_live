import 'package:simple_live_app/app/sites.dart';

/// 一起打开的一路直播间（多开批量入口用）。
class LiveRoomTarget {
  const LiveRoomTarget({required this.site, required this.roomId});

  final Site site;
  final String roomId;

  @override
  String toString() => '${site.id}_$roomId';
}

/// `/room/detail` 的路由参数。
///
/// 原来这条路由把 site 放在 `arguments`、roomId 放在 `parameters`；多开的批量入口需要
/// 在一次导航里把「另外几路」也带上，统一收进这个对象更清楚，binding 也只需读一处。
class LiveRoomRouteArgs {
  const LiveRoomRouteArgs({
    required this.site,
    required this.roomId,
    this.together = const [],
  });

  final Site site;
  final String roomId;

  /// 一起预载的其余几路（不含 [site]/[roomId] 这条在内）。
  final List<LiveRoomTarget> together;
}