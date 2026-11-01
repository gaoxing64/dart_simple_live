/// 进程内 CDN 健康度黑名单。
///
/// 只记录已经通过播放器运行时指标确认“持续饥饿”的 CDN 家族，默认封禁 10 分钟。
/// 不落盘：网络路径会随网络、Wi-Fi、运营商和 CDN 调度变化，跨启动保留黑名单反而
/// 容易把已经恢复的节点长期判死。
class CdnHealthCache {
  CdnHealthCache._();

  static const Duration defaultBlockDuration = Duration(minutes: 10);

  static final Map<String, DateTime> _blockedUntil = <String, DateTime>{};

  /// 把 FLV/HLS 两个入口归到同一个 CDN 家族。
  ///
  /// 抖音同一档画质通常同时给 `pull-flv-f11...` 和 `pull-hls-f11...`，它们走同一
  /// 组边缘节点；只封其中一个会让换 HLS 后再次撞上同一条慢链路。
  static String cdnFamilyOf(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized.replaceFirst(RegExp(r'^pull-(?:flv|hls)-'), 'pull-');
  }

  static bool isBlocked(
    String platformId,
    String host, {
    DateTime? now,
  }) {
    final family = cdnFamilyOf(host);
    if (family.isEmpty) {
      return false;
    }
    final key = _key(platformId, family);
    final until = _blockedUntil[key];
    if (until == null) {
      return false;
    }
    if (!until.isAfter(now ?? DateTime.now())) {
      _blockedUntil.remove(key);
      return false;
    }
    return true;
  }

  /// 标记一个 CDN 家族为慢节点，返回实际写入的家族名。
  static String markSlow(
    String platformId,
    String host, {
    DateTime? now,
    Duration duration = defaultBlockDuration,
  }) {
    final family = cdnFamilyOf(host);
    if (family.isEmpty || duration <= Duration.zero) {
      return family;
    }
    final at = now ?? DateTime.now();
    _blockedUntil[_key(platformId, family)] = at.add(duration);
    return family;
  }

  /// 清空全部记录（测试 / 排障）。
  static void clear() {
    _blockedUntil.clear();
  }

  static String _key(String platformId, String family) => '$platformId/$family';
}
