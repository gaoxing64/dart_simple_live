import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 直播间「详情 / 清晰度 / 直链」的短时缓存，用于切台预取。
///
/// # 为什么需要它
///
/// 起播的三段网络（详情 → 清晰度 → 直链）是**串行**的，实测中位数约
/// detail 185ms + qualities 47ms + play-urls 224ms ≈ 520ms，这部分无论怎么优化
/// 请求本身都下不去 —— 直播直链必须现取，缓存过期就不能播。
///
/// 但「关注列表里上下键换台」是完全可预测的：下一个房间就是列表里的相邻项。
/// 所以在**当前房间播放稳定后**，后台把相邻房间的这三段结果预先取回来，
/// 用户真正切过去时直接命中缓存，起播就只剩播放器 open 的那几十毫秒。
///
/// # 失效策略（宁可不用，也不能播错）
///
/// - 直链带签名与时效，TTL 保守取 [liveTtl]，且**留 [serveMargin] 余量**：
///   剩余寿命不足余量就直接判过期，避免把「还有 1 秒到期」的直链交给播放器。
/// - 未开播的房间不缓存：预取了也用不上。
/// - 缓存键含 `siteId + roomId`，跨平台不串；直链再叠一层清晰度，切档不会串用。
/// - 容量有上限，写入时就地淘汰，不依赖调用方记得调用 [evictExpired]。
class LiveRoomPrefetch {
  LiveRoomPrefetch._();

  /// 直链缓存有效期。保守取 40s：过期后重新取一次的成本远低于「拿旧直链播放失败」。
  static const Duration liveTtl = Duration(seconds: 40);

  /// 直链出借时的剩余寿命余量：不足这个值就当过期。
  ///
  /// 缓存到第 39 秒的直链可能已经在 CDN 侧失效，交出去只会让播放器报错重连。
  static const Duration serveMargin = Duration(seconds: 6);

  /// 详情与清晰度缓存有效期（不含签名，可以比直链长）。
  static const Duration metaTtl = Duration(seconds: 90);

  /// 单个预取请求的超时。超时必须放掉 in-flight 槽位，否则该房间再也不会被预取。
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// 并发预取半径：前后各一个。
  static const int prefetchRadius = 1;

  /// 条目上限（防无界增长）。超出时按最早写入淘汰。
  static const int maxEntries = 64;

  static final Map<String, _MetaEntry> _meta = <String, _MetaEntry>{};
  static final Map<String, _LiveEntry> _live = <String, _LiveEntry>{};
  static final Set<String> _inflightRooms = <String>{};

  /// 正在预取的平台：同一站点句柄不并发预取，避免与正在播放的房间抢内部状态。
  static final Set<String> _busySites = <String>{};

  static String _key(String siteId, String roomId) => "$siteId/$roomId";

  /// 读详情缓存；过期返回 null。
  static LiveRoomDetail? takeDetail(String siteId, String roomId) {
    final entry = _meta[_key(siteId, roomId)];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.detail;
  }

  /// 写详情缓存（未开播的房间不缓存：预取了也用不上）。
  static void putDetail(String siteId, String roomId, LiveRoomDetail detail) {
    final key = _key(siteId, roomId);
    if (!detail.status && !detail.isRecord) {
      _meta.remove(key);
      return;
    }
    _meta[key] = _MetaEntry(detail, DateTime.now());
    _trim();
  }

  /// 读清晰度缓存；过期返回 null。返回的是不可变副本，调用方改不动缓存内容。
  static List<LivePlayQuality>? takeQualities(String siteId, String roomId) {
    final entry = _meta[_key(siteId, roomId)];
    if (entry == null || entry.isExpired || entry.qualities == null) {
      return null;
    }
    return entry.qualities;
  }

  /// 写清晰度缓存（存副本，避免调用方后续改动串进缓存）。
  static void putQualities(
    String siteId,
    String roomId,
    List<LivePlayQuality> qualities,
  ) {
    final entry = _meta[_key(siteId, roomId)];
    if (entry == null || entry.isExpired) {
      return;
    }
    entry.qualities = List<LivePlayQuality>.unmodifiable(qualities);
    _trim();
  }

  /// 读直链缓存；剩余寿命不足 [serveMargin] 时按过期处理。
  ///
  /// 键里带清晰度名：同一个房间切清晰度不能复用另一档的直链。
  static LivePlayUrl? takePlayUrl(
    String siteId,
    String roomId,
    String quality,
  ) {
    final entry = _live[_key(siteId, roomId) + "#$quality"];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.play;
  }

  /// 写直链缓存。
  static void putPlayUrl(
    String siteId,
    String roomId,
    String quality,
    LivePlayUrl play,
  ) {
    if (play.urls.isEmpty) {
      return;
    }
    _live[_key(siteId, roomId) + "#$quality"] =
        _LiveEntry(play, DateTime.now());
    _trim();
  }

  /// 按播放器的档位策略（0 最低 / 1 中间 / 2 最高）算出应预取的清晰度下标。
  ///
  /// 必须和 `LiveRoomController.getPlayQualities()` 的口径一致：预取错档位等于
  /// 白花带宽 —— 命中不了，还要和正在播放的房间抢流量。
  static int indexForLevel(int level, int count) {
    if (count <= 0) {
      return 0;
    }
    if (level >= 2) {
      return 0;
    }
    if (level <= 0) {
      return count - 1;
    }
    return count ~/ 2;
  }

  /// 后台预取一个房间（详情 + 清晰度 + 目标档位直链）。
  ///
  /// [qualityLevel] 与 `AppSettingsController.qualityLevel` 同口径（0/1/2）。
  /// 失败一律静默：预取是锦上添花，任何异常都不能影响正在播放的房间，
  /// 所以这里**每条路径**都自己 try/catch，绝不把异常漏成 unhandled async error。
  static Future<void> warmUp(
    Site site,
    String roomId, {
    required int qualityLevel,
  }) async {
    final roomKey = _key(site.id, roomId);
    if (_inflightRooms.contains(roomKey) || _busySites.contains(site.id)) {
      return;
    }
    _inflightRooms.add(roomKey);
    _busySites.add(site.id);

    try {
      var detail = takeDetail(site.id, roomId);
      if (detail == null) {
        detail = await site.liveSite
            .getRoomDetail(roomId: roomId)
            .timeout(_requestTimeout);
        putDetail(site.id, roomId, detail);
      }
      if (!detail.status && !detail.isRecord) {
        return;
      }

      var qualities = takeQualities(site.id, roomId);
      if (qualities == null) {
        final fetched = await site.liveSite
            .getPlayQualities(detail: detail)
            .timeout(_requestTimeout);
        putQualities(site.id, roomId, fetched);
        qualities = takeQualities(site.id, roomId);
      }
      if (qualities == null || qualities.isEmpty) {
        return;
      }

      final index = indexForLevel(qualityLevel, qualities.length);
      final quality = qualities[index];
      if (takePlayUrl(site.id, roomId, quality.quality) != null) {
        return;
      }
      final play = await site.liveSite
          .getPlayUrls(detail: detail, quality: quality)
          .timeout(_requestTimeout);
      putPlayUrl(site.id, roomId, quality.quality, play);
    } catch (e) {
      // 预取失败只影响「下次切台能不能命中缓存」，一律静默。
      Log.logPrint(e);
    } finally {
      _inflightRooms.remove(roomKey);
      _busySites.remove(site.id);
    }
  }

  /// 清理过期条目。
  static void evictExpired() {
    final now = DateTime.now();
    _meta.removeWhere((_, entry) => entry.isExpiredAt(now));
    _live.removeWhere((_, entry) => entry.isExpiredAt(now));
  }

  /// 写入后就地淘汰：先清过期，再按写入时间丢最早的，保证有界。
  static void _trim() {
    evictExpired();
    while (_meta.length + _live.length > maxEntries) {
      _MetaEntry? oldestMeta;
      String? oldestMetaKey;
      for (final entry in _meta.entries) {
        if (oldestMeta == null ||
            entry.value.createdAt.isBefore(oldestMeta.createdAt)) {
          oldestMeta = entry.value;
          oldestMetaKey = entry.key;
        }
      }
      _LiveEntry? oldestLive;
      String? oldestLiveKey;
      for (final entry in _live.entries) {
        if (oldestLive == null ||
            entry.value.createdAt.isBefore(oldestLive.createdAt)) {
          oldestLive = entry.value;
          oldestLiveKey = entry.key;
        }
      }
      if (oldestMeta == null && oldestLive == null) {
        return;
      }
      final dropMeta = oldestLive == null ||
          (oldestMeta != null &&
              oldestMeta.createdAt.isBefore(oldestLive.createdAt));
      if (dropMeta && oldestMetaKey != null) {
        _meta.remove(oldestMetaKey);
      } else if (oldestLiveKey != null) {
        _live.remove(oldestLiveKey);
      } else {
        return;
      }
    }
  }
}

class _MetaEntry {
  _MetaEntry(this.detail, this.createdAt)
      : expiresAt = createdAt.add(LiveRoomPrefetch.metaTtl);

  final LiveRoomDetail detail;
  final DateTime createdAt;
  final DateTime expiresAt;
  List<LivePlayQuality>? qualities;

  bool get isExpired => isExpiredAt(DateTime.now());

  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);
}

class _LiveEntry {
  _LiveEntry(this.play, this.createdAt)
      : expiresAt = createdAt.add(LiveRoomPrefetch.liveTtl);

  final LivePlayUrl play;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// 剩余寿命不足出借余量即视为过期（避免把「马上到期」的直链交给播放器）。
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(LiveRoomPrefetch.serveMargin));

  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);
}
