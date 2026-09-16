// `watchDurationText` 的纯 Dart 单测：不依赖 Flutter，可以直接用 `dart` 跑。
//
// 三个边界值得钉住：
//   - 0 / 负数返回空串（关注一个新主播、或计数还没起来时的合法状态），
//     调用方据此决定要不要显示这一段，别在各自再写一份 `> 0` 守卫；
//   - 三档阈值各取整数部分，不存在「累计观看 1.5 分钟」这种文案；
//   - 上限不溢出（int 秒数再大也只取整小时）。
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/utils/duration_2_str_utils.dart';

void main() {
  group('无观看记录', () {
    test('0 秒返回空串，由调用方决定是否显示', () {
      expect(watchDurationText(0), '');
    });

    test('负数（计时器异常回退）也返回空串，不显示负的时长', () {
      expect(watchDurationText(-1), '');
      expect(watchDurationText(-3600), '');
    });
  });

  group('三档文案', () {
    test('不足一分钟显示秒', () {
      expect(watchDurationText(1), '累计观看 1 秒');
      expect(watchDurationText(59), '累计观看 59 秒');
    });

    test('满一分钟显示分钟，向下取整不四舍五入', () {
      expect(watchDurationText(60), '累计观看 1 分钟');
      expect(watchDurationText(119), '累计观看 1 分钟');
      expect(watchDurationText(3599), '累计观看 59 分钟');
    });

    test('满一小时显示小时，分钟段被丢弃', () {
      expect(watchDurationText(3600), '累计观看 1 小时');
      expect(watchDurationText(3600 + 1800), '累计观看 1 小时');
      expect(watchDurationText(3600 * 2 + 59), '累计观看 2 小时');
    });
  });

  test('大数值不溢出', () {
    // 一年 ≈ 31_536_000 秒，取整小时
    expect(watchDurationText(31536000), '累计观看 8760 小时');
  });
}
