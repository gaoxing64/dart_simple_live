import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/player/playback_starvation_detector.dart';
import 'package:simple_live_app/services/cdn_score_cache.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class _MemoryStorage extends LocalStorageService {
  final Map<dynamic, dynamic> data = <dynamic, dynamic>{};
  int writes = 0;

  @override
  T getValue<T>(dynamic key, T defaultValue) =>
      (data[key] as T?) ?? defaultValue;

  @override
  Future<dynamic> setValue<T>(dynamic key, T value) async {
    writes++;
    data[key] = value;
  }
}

const _flvF11 = 'pull-flv-f11.douyinliving.com';
const _hlsF11 = 'pull-hls-f11.douyinliving.com';
const _flvF26 = 'pull-flv-f26.douyinliving.com';
const _flvQ1 = 'pull-flv-q1.douyincdn.com';
const _flvQ6 = 'pull-flv-q6.douyincdn.com';
const _flvX3 = 'pull-x3-t5.douyincdn.com';
const _hlsX3 = 'pull-x3-t5-hls.douyincdn.com';

final _at = DateTime(2026, 11, 5, 10);

PlaybackHealthSample _sample({
  bool paused = false,
  bool pausedForCache = false,
  double inputMbps = 9,
  double videoMbps = 6,
  double cacheSeconds = 2,
  double buffering = 100,
}) {
  return PlaybackHealthSample(
    paused: paused,
    pausedForCache: pausedForCache,
    inputBitsPerSecond: inputMbps * 1000000,
    videoBitsPerSecond: videoMbps * 1000000,
    cacheSeconds: cacheSeconds,
    cacheBufferingState: buffering,
  );
}

/// 弱饥饿：输入追不上视频码率、缓存见底，但还没真正暂停。
PlaybackHealthSample _weakStarved() => _sample(
      inputMbps: 3,
      videoMbps: 6,
      cacheSeconds: 0.1,
      buffering: 20,
    );

/// 强饥饿：mpv 已因缓冲暂停，由 detector + penalize 单独处理。
PlaybackHealthSample _hardStall() => _sample(
      pausedForCache: true,
      inputMbps: 3,
      videoMbps: 6,
      cacheSeconds: 0.1,
      buffering: 20,
    );

void _record(String host, PlaybackHealthSample sample, {int times = 5}) {
  for (var i = 0; i < times; i++) {
    CdnScoreCache.record('douyin', host, sample, now: _at);
  }
}

void main() {
  final storage = _MemoryStorage();

  setUpAll(() {
    Get.put<LocalStorageService>(storage, permanent: true);
  });
  setUp(() {
    storage.data.clear();
    storage.writes = 0;
    CdnScoreCache.clear();
  });
  tearDown(CdnScoreCache.clear);

  test('FLV/HLS 入口共享同一家族分数', () {
    _record(_flvF11, _sample());
    expect(
      CdnScoreCache.rankScoreOf('douyin', _hlsF11, now: _at),
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
    );
    expect(
      CdnScoreCache.rankScoreOf('douyin', _hlsF11, now: _at),
      greaterThan(CdnScoreCache.neutralScore),
    );
  });

  test('后缀式 -hls 命名也归并到同一家族', () {
    _record(_flvX3, _sample());
    expect(
      CdnScoreCache.rankScoreOf('douyin', _hlsX3, now: _at),
      CdnScoreCache.rankScoreOf('douyin', _flvX3, now: _at),
    );
    expect(
      CdnScoreCache.rankScoreOf('douyin', _hlsX3, now: _at),
      greaterThan(CdnScoreCache.neutralScore),
    );
  });

  test('稳态健康样本得分高于中性', () {
    _record(_flvF11, _sample(inputMbps: 6.2, videoMbps: 6));
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      greaterThan(CdnScoreCache.neutralScore),
    );
  });

  test('弱饥饿信号压低家族分数', () {
    _record(_flvF11, _weakStarved());
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      lessThan(CdnScoreCache.neutralScore),
    );
  });

  test('强 stall 不重复计入 EWMA，只由 penalize 处理', () {
    _record(_flvF11, _sample());
    final before = CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at);
    _record(_flvF11, _hardStall());
    expect(CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at), before);
  });

  test('paused 样本不参与评分', () {
    _record(_flvF11, _sample());
    final before = CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at);
    _record(_flvF11, _sample(paused: true));
    expect(CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at), before);
  });

  test('样本不足时保持中性，不被单次抖动主导', () {
    _record(_flvF11, _weakStarved(), times: 1);
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      CdnScoreCache.neutralScore,
    );
  });

  test('视频码率未知时保持中性，不误判静态画面', () {
    _record(_flvF11, _sample(videoMbps: 1));
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      closeTo(CdnScoreCache.neutralScore, 0.001),
    );
  });

  test('penalize 让已确认饥饿的家族落到未知节点之后', () {
    _record(_flvF11, _sample());
    CdnScoreCache.penalize('douyin', _flvF11, now: _at);
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      lessThan(CdnScoreCache.rankScoreOf('douyin', _flvF26, now: _at)),
    );
  });

  test('分数按半衰期向中性衰减', () {
    _record(_flvF11, _sample());
    final before = CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at);
    final after = CdnScoreCache.rankScoreOf(
      'douyin',
      _flvF11,
      now: _at.add(const Duration(hours: 1)),
    );
    expect(after, lessThan(before));
    expect(
      after,
      closeTo(
        CdnScoreCache.neutralScore +
            (before - CdnScoreCache.neutralScore) * 0.5,
        0.001,
      ),
    );
  });

  test('平台之间互不影响', () {
    _record(_flvF11, _sample());
    expect(
      CdnScoreCache.rankScoreOf('bilibili', _flvF11, now: _at),
      CdnScoreCache.neutralScore,
    );
  });

  test('排序：健康优先，未知居中且保持原序，慢节点最后', () {
    _record(_flvF11, _sample());
    _record(_flvQ1, _weakStarved());
    final sorted = CdnScoreCache.sortByScore(
      'douyin',
      <String>[_flvQ1, _flvF26, _flvF11, _flvQ6],
      (host) => host,
      now: _at,
    );
    expect(sorted, <String>[_flvF11, _flvF26, _flvQ6, _flvQ1]);
  });

  test('flush 把评分写入本地存储', () {
    _record(_flvF11, _sample());
    storage.data.clear();
    CdnScoreCache.flush();
    final raw = storage.data['CdnScoreV1'];
    expect(raw, isA<String>());
    expect(raw as String, contains('douyin/pull-f11.douyinliving.com'));
  });

  test('冷启动 flush 不覆盖已持久化的分数', () {
    _record(_flvF11, _sample());
    CdnScoreCache.flush();
    final persisted = storage.data['CdnScoreV1'];
    CdnScoreCache.resetForTest();
    CdnScoreCache.flush();
    expect(storage.data['CdnScoreV1'], persisted);
  });

  test('重启后能从本地存储读回分数', () {
    _record(_flvF11, _sample());
    CdnScoreCache.flush();
    CdnScoreCache.resetForTest();
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      greaterThan(CdnScoreCache.neutralScore),
    );
  });

  test('损坏的持久化数据退回中性', () {
    storage.data['CdnScoreV1'] = '{not json';
    CdnScoreCache.resetForTest();
    expect(
      CdnScoreCache.rankScoreOf('douyin', _flvF11, now: _at),
      CdnScoreCache.neutralScore,
    );
  });

  test('节流窗口内不重复写盘', () {
    final before = storage.writes;
    for (var i = 0; i < 4; i++) {
      CdnScoreCache.record(
        'douyin',
        _flvF11,
        _sample(),
        now: _at.add(Duration(seconds: i)),
      );
    }
    expect(storage.writes, before + 1);
  });

  test('空 host 不写入评分', () {
    CdnScoreCache.record('douyin', '', _weakStarved(), now: _at);
    expect(
      CdnScoreCache.rankScoreOf('douyin', '', now: _at),
      CdnScoreCache.neutralScore,
    );
  });
}
