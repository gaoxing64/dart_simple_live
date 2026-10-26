import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_volume.dart';

void main() {
  group('resolveTileVolume', () {
    test('压低关闭时，聚焦与否同一音量', () {
      final unfocused = resolveTileVolume(
        master: 80,
        duckEnabled: false,
        duckRatio: 0.3,
        factor: 1,
        focused: false,
      );
      final focused = resolveTileVolume(
        master: 80,
        duckEnabled: false,
        duckRatio: 0.3,
        factor: 1,
        focused: true,
      );
      expect(unfocused, 80);
      expect(focused, 80);
    });

    test('压低开启时，非聚焦按 ratio 乘上去', () {
      expect(
        resolveTileVolume(
          master: 80,
          duckEnabled: true,
          duckRatio: 0.3,
          factor: 1,
          focused: false,
        ),
        closeTo(24, 1e-9),
      );
      expect(
        resolveTileVolume(
          master: 80,
          duckEnabled: true,
          duckRatio: 0.3,
          factor: 1,
          focused: true,
        ),
        80,
      );
    });

    test('该格系数与压低叠乘', () {
      expect(
        resolveTileVolume(
          master: 100,
          duckEnabled: true,
          duckRatio: 0.5,
          factor: 0.4,
          focused: false,
        ),
        closeTo(20, 1e-9),
      );
    });

    test('系数为 0 即静音，与压低和焦点无关', () {
      for (final duck in [true, false]) {
        for (final focused in [true, false]) {
          expect(
            resolveTileVolume(
              master: 100,
              duckEnabled: duck,
              duckRatio: 0.3,
              factor: 0,
              focused: focused,
            ),
            0,
          );
        }
      }
    });

    test('结果恒不超过总音量（压低只向下乘，永不越 volume-max）', () {
      for (final duckRatio in [0.0, 0.3, 1.0]) {
        for (final factor in [0.0, 0.25, 1.0]) {
          final v = resolveTileVolume(
            master: 90,
            duckEnabled: true,
            duckRatio: duckRatio,
            factor: factor,
            focused: false,
          );
          expect(v, lessThanOrEqualTo(90));
        }
      }
    });

    test('ratio 取 1 时等于不压低', () {
      expect(
        resolveTileVolume(
          master: 70,
          duckEnabled: true,
          duckRatio: 1,
          factor: 1,
          focused: false,
        ),
        70,
      );
    });
  });
}
