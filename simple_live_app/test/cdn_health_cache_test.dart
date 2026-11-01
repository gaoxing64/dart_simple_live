import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/cdn_health_cache.dart';

void main() {
  setUp(CdnHealthCache.clear);
  tearDown(CdnHealthCache.clear);

  test('FLV/HLS 入口归并为同一个 CDN 家族', () {
    expect(
      CdnHealthCache.cdnFamilyOf('pull-flv-f11.douyinliving.com'),
      'pull-f11.douyinliving.com',
    );
    expect(
      CdnHealthCache.cdnFamilyOf('pull-hls-f11.douyinliving.com'),
      'pull-f11.douyinliving.com',
    );
    expect(
      CdnHealthCache.cdnFamilyOf('pull-x3-q5.douyincdn.com'),
      'pull-x3-q5.douyincdn.com',
    );
  });

  test('拉黑一族后 FLV/HLS 两个入口都命中，其它族不受影响', () {
    final now = DateTime(2026, 10, 31, 23, 0);
    CdnHealthCache.markSlow(
      'douyin',
      'pull-flv-f11.douyinliving.com',
      now: now,
    );

    expect(
      CdnHealthCache.isBlocked(
        'douyin',
        'pull-flv-f11.douyinliving.com',
        now: now,
      ),
      isTrue,
    );
    expect(
      CdnHealthCache.isBlocked(
        'douyin',
        'pull-hls-f11.douyinliving.com',
        now: now,
      ),
      isTrue,
    );
    expect(
      CdnHealthCache.isBlocked(
        'douyin',
        'pull-flv-f26.douyinliving.com',
        now: now,
      ),
      isFalse,
    );
  });

  test('黑名单按平台隔离且会在 TTL 后自动失效', () {
    final now = DateTime(2026, 10, 31, 23, 0);
    CdnHealthCache.markSlow(
      'douyin',
      'pull-flv-f11.douyinliving.com',
      now: now,
      duration: const Duration(minutes: 10),
    );

    expect(
      CdnHealthCache.isBlocked(
        'douyin',
        'pull-flv-f11.douyinliving.com',
        now: now.add(const Duration(minutes: 9)),
      ),
      isTrue,
    );
    expect(
      CdnHealthCache.isBlocked(
        'douyin',
        'pull-flv-f11.douyinliving.com',
        now: now.add(const Duration(minutes: 10)),
      ),
      isFalse,
    );
    expect(
      CdnHealthCache.isBlocked(
        'bilibili',
        'pull-flv-f11.douyinliving.com',
        now: now,
      ),
      isFalse,
    );
  });
}
