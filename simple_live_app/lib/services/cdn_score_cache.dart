import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/live_room/player/playback_starvation_detector.dart';
import 'package:simple_live_app/services/cdn_health_cache.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// 用播放中实测的吞吐/缓冲给 CDN 家族评分，供起播排序与自动换线使用。
///
/// 直播追平直播点后 `cache-speed` 会回落到约等于视频码率，绝对 Mbps 区分不了节点，
/// 所以按「输入/视频码率 + 缓冲水位」算单次健康度，再对家族做 EWMA。
class CdnScoreCache {
  CdnScoreCache._();

  static const String _key = 'CdnScoreV1';
  static const double neutralScore = 0.7;
  static const double ewmaAlpha = 0.2;
  static const int minSamplesToRank = 3;
  static const double slowPenalty = 0.4;
  static const double fullScoreHeadroom = 1.1;
  static const Duration halfLife = Duration(hours: 1);
  static const Duration persistThrottle = Duration(seconds: 10);

  static final Map<String, _Score> _scores = <String, _Score>{};
  static bool _loaded = false;
  static DateTime? _lastPersistAt;

  /// 排序用分数。未知或样本不足的家族保持中性，不让单次采样主导顺序。
  static double rankScoreOf(String platformId, String host, {DateTime? now}) {
    _ensureLoaded();
    final family = CdnHealthCache.cdnFamilyOf(host);
    if (family.isEmpty) {
      return neutralScore;
    }
    final entry = _scores['$platformId/$family'];
    if (entry == null || entry.samples < minSamplesToRank) {
      return neutralScore;
    }
    return _decay(entry, now ?? DateTime.now());
  }

  /// 按分数稳定排序（同分保持原序），未知家族落在中位置。
  static List<T> sortByScore<T>(
    String platformId,
    List<T> items,
    String Function(T) hostOf, {
    DateTime? now,
  }) {
    if (items.length < 2) {
      return items;
    }
    final at = now ?? DateTime.now();
    final indexed = items.asMap().entries.toList(growable: false);
    indexed.sort((a, b) {
      final compared = rankScoreOf(platformId, hostOf(b.value), now: at)
          .compareTo(rankScoreOf(platformId, hostOf(a.value), now: at));
      return compared != 0 ? compared : a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  static void record(
    String platformId,
    String host,
    PlaybackHealthSample sample, {
    DateTime? now,
  }) {
    final quality = _sampleQuality(sample);
    if (quality < 0) {
      return;
    }
    _ensureLoaded();
    final family = CdnHealthCache.cdnFamilyOf(host);
    if (family.isEmpty) {
      return;
    }
    final at = now ?? DateTime.now();
    final key = '$platformId/$family';
    final entry = _scores[key] ?? _Score(score: quality, samples: 0, updatedAt: at);
    final current = _decay(entry, at);
    _scores[key] = _Score(
      score: current + ewmaAlpha * (quality - current),
      samples: entry.samples + 1,
      updatedAt: at,
    );
    _maybePersist(at);
  }

  /// 已确认持续饥饿的家族直接扣分，避免黑名单 10 分钟过期后又被选回首选。
  static void penalize(String platformId, String host, {DateTime? now}) {
    _ensureLoaded();
    final family = CdnHealthCache.cdnFamilyOf(host);
    if (family.isEmpty) {
      return;
    }
    final at = now ?? DateTime.now();
    final key = '$platformId/$family';
    final entry = _scores[key] ?? _Score(score: neutralScore, samples: 0, updatedAt: at);
    _scores[key] = _Score(
      score: math.max(0.0, _decay(entry, at) - slowPenalty),
      samples: math.max(entry.samples, minSamplesToRank),
      updatedAt: at,
    );
    _persist();
  }

  /// 显式落盘。冷启动时可能还没加载过缓存，先加载再写，避免用空表覆盖历史分数。
  static void flush() {
    _ensureLoaded();
    _lastPersistAt = DateTime.now();
    _persist();
  }

  /// 测试 / 排障用：清空内存与落盘数据。
  static void clear() {
    _scores.clear();
    _loaded = true;
    _lastPersistAt = null;
    _persist();
  }

  /// 测试用：模拟进程重启，强制下次访问重新从本地存储加载。
  @visibleForTesting
  static void resetForTest() {
    _scores.clear();
    _loaded = false;
    _lastPersistAt = null;
  }

  static double _sampleQuality(PlaybackHealthSample sample) {
    if (sample.paused) {
      return -1;
    }
    // 强饥饿是离散事件，已由 PlaybackStarvationDetector + penalize 处理；
    // 再计入 EWMA 会对同一次卡顿双重惩罚，且分数要很久才恢复。
    if (sample.pausedForCache) {
      return -1;
    }
    if (sample.videoBitsPerSecond <
        PlaybackStarvationDetector.minVideoBitsPerSecondForRatio) {
      return neutralScore;
    }
    final ratio = PlaybackStarvationDetector.inputRatioOf(sample);
    var quality = (ratio / fullScoreHeadroom).clamp(0.0, 1.0);
    if (PlaybackStarvationDetector.isInputStarved(sample)) {
      quality *= 0.35;
    } else if (sample.cacheSeconds <= PlaybackStarvationDetector.lowCacheSeconds &&
        ratio < 1.0) {
      quality *= 0.7;
    }
    return quality;
  }

  static double _decay(_Score entry, DateTime now) {
    final elapsed = now.difference(entry.updatedAt).inSeconds;
    if (elapsed <= 0) {
      return entry.score;
    }
    final factor = math.pow(0.5, elapsed / halfLife.inSeconds).toDouble();
    return neutralScore + (entry.score - neutralScore) * factor;
  }

  static void _maybePersist(DateTime now) {
    final last = _lastPersistAt;
    if (last != null && now.difference(last) < persistThrottle) {
      return;
    }
    _lastPersistAt = now;
    _persist();
  }

  static void _ensureLoaded() {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final raw = LocalStorageService.instance.getValue<String>(_key, '');
      if (raw.isEmpty) {
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return;
      }
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) {
          return;
        }
        final score = (value['s'] as num?)?.toDouble();
        final samples = (value['n'] as num?)?.toInt();
        final at = (value['t'] as num?)?.toInt();
        if (score != null && samples != null && at != null) {
          _scores[key] = _Score(
            score: score,
            samples: samples,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(at),
          );
        }
      });
    } catch (e) {
      Log.logPrint(e);
    }
  }

  static void _persist() {
    try {
      LocalStorageService.instance.setValue(
        _key,
        json.encode(<String, Object>{
          for (final entry in _scores.entries)
            entry.key: <String, Object>{
              's': entry.value.score,
              'n': entry.value.samples,
              't': entry.value.updatedAt.millisecondsSinceEpoch,
            },
        }),
      );
    } catch (e) {
      Log.logPrint(e);
    }
  }
}

class _Score {
  const _Score({
    required this.score,
    required this.samples,
    required this.updatedAt,
  });

  final double score;
  final int samples;
  final DateTime updatedAt;
}
