import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';

void main() {
  const a169 = 16 / 9;
  const a43 = 4 / 3;
  // 16:9 下 max(240, 135×16/9) 与 max(135, 240×9/16) 都正好落在 240×135，
  // 但因为 16/9 不是有限小数，两处都带一点浮点尾巴。
  const cellW = 240.0;
  const cellH = 135.00000000000003;

  group('排布选择', () {
    test('单路恒 1×1，铺满可用区域', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 1200,
        maxHeight: 675,
        roomCount: 1,
        tileAspect: a169,
      );
      expect(spec.arrangement, MultiPlayArrangement.single);
      expect(spec.rows, 1);
      expect(spec.columns, 1);
      expect(spec.slots.single.index, 0);
      expect(spec.cellWidth, closeTo(1200, 1e-9));
      expect(spec.cellHeight, closeTo(675, 1e-9));
      expect(spec.degraded, isFalse);
    });

    test('双路：宽窗横排、竖窗上下', () {
      final wide = resolveMultiPlayLayout(
        maxWidth: 1920,
        maxHeight: 1080,
        roomCount: 2,
        tileAspect: a169,
      );
      expect(wide.arrangement, MultiPlayArrangement.sideBySide);
      expect(wide.rows, 1);
      expect(wide.columns, 2);

      final tall = resolveMultiPlayLayout(
        maxWidth: 1080,
        maxHeight: 1920,
        roomCount: 2,
        tileAspect: a169,
      );
      expect(tall.arrangement, MultiPlayArrangement.stacked);
      expect(tall.rows, 2);
      expect(tall.columns, 1);
    });

    test('三路/四路：宽窗 2×2', () {
      for (final count in [3, 4]) {
        final spec = resolveMultiPlayLayout(
          maxWidth: 1920,
          maxHeight: 1080,
          roomCount: count,
          tileAspect: a169,
        );
        expect(spec.arrangement, MultiPlayArrangement.grid, reason: '$count 路');
        expect(spec.rows, 2);
        expect(spec.columns, 2);
        expect(spec.slots.length, count);
      }
    });

    test('四路竖窗：翻成 4 行 1 列', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 1080,
        maxHeight: 1920,
        roomCount: 4,
        tileAspect: a169,
      );
      expect(spec.arrangement, MultiPlayArrangement.stacked);
      expect(spec.rows, 4);
      expect(spec.columns, 1);
    });

    test('形状等价时倾向宽排（1920×1080 下 2 路取 1×2 而非 2×1）', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 1920,
        maxHeight: 1080,
        roomCount: 2,
        tileAspect: a169,
      );
      expect(spec.columns, 2);
    });
  });

  group('位置稳定性', () {
    // 点某一格不应该让画面跳位置：布局函数里根本没有焦点这个输入，
    // 槽位下标恒等于「第几个加进来的」，排列恒为行优先。
    test('槽位恒按加入顺序、行优先', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 1920,
        maxHeight: 1080,
        roomCount: 4,
        tileAspect: a169,
      );
      expect(spec.slots.map((e) => e.index), [0, 1, 2, 3]);
      expect(spec.slots.map((e) => e.row), [0, 0, 1, 1]);
      expect(spec.slots.map((e) => e.col), [0, 1, 0, 1]);
    });

    test('同一输入反复计算结果一致（与任何「当前聚焦」状态无关）', () {
      final first = resolveMultiPlayLayout(
        maxWidth: 1200,
        maxHeight: 700,
        roomCount: 3,
        tileAspect: a169,
      );
      final second = resolveMultiPlayLayout(
        maxWidth: 1200,
        maxHeight: 700,
        roomCount: 3,
        tileAspect: a169,
      );
      expect(first.slots, second.slots);
      expect(first.rows, second.rows);
      expect(first.columns, second.columns);
    });

    test('格子矩形：第 0 格在左上、第 3 格在右下', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 968,
        maxHeight: 558,
        roomCount: 4,
        tileAspect: a169,
      );
      final first = spec.rectOf(spec.slots.first);
      expect(first.left, 0);
      expect(first.top, 0);
      expect(first.width, closeTo(480, 1e-9)); // (968 - 8) / 2
      expect(first.height, closeTo(275, 1e-9)); // (558 - 8) / 2

      final fourth = spec.rectOf(spec.slots.last);
      expect(fourth.left, closeTo(488, 1e-9));
      expect(fourth.top, closeTo(283, 1e-9));
    });
  });

  group('折叠（窗口过小）', () {
    test('从最后加入的一格开始丢，保留前面的', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 500,
        maxHeight: 150,
        roomCount: 4,
        tileAspect: a169,
      );
      expect(spec.degraded, isTrue);
      expect(spec.slots.map((e) => e.index), [0, 1]);
      expect(spec.hiddenIndexes, [2, 3]);
      expect(spec.totalCount, 4);
      expect(spec.slots.length + spec.hiddenIndexes.length, 4);
    });

    test('折叠时先保住聚焦格，位置仍按加入顺序升序', () {
      // 聚焦第 4 格（下标 3）而窗口只能放 2 格：它绝不能被藏起来，
      // 否则聊天区与音量还在跟着一路看不见的画面
      final spec = resolveMultiPlayLayout(
        maxWidth: 500,
        maxHeight: 150,
        roomCount: 4,
        focusedIndex: 3,
        tileAspect: a169,
      );
      expect(spec.degraded, isTrue);
      expect(spec.slots.map((e) => e.index), contains(3));
      expect(spec.hiddenIndexes, isNot(contains(3)));
      // 位置恒按加入顺序：可见格下标升序
      final visible = spec.slots.map((e) => e.index).toList();
      expect(visible, List.of(visible)..sort());
    });

    test('小到一格都放不下时仍给 1×1（取第 0 格）', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 100,
        maxHeight: 60,
        roomCount: 4,
        tileAspect: a169,
      );
      expect(spec.rows, 1);
      expect(spec.columns, 1);
      expect(spec.slots.single.index, 0);
      expect(spec.hiddenIndexes, [1, 2, 3]);
      expect(spec.cellWidth, closeTo(100, 1e-9));
    });

    test('窗口尺寸非法（0 / NaN / 负）不抛异常', () {
      for (final size in [
        const Size(0, 0),
        const Size(double.nan, 400),
        const Size(-100, 400),
      ]) {
        final spec = resolveMultiPlayLayout(
          maxWidth: size.width,
          maxHeight: size.height,
          roomCount: 4,
          tileAspect: a169,
        );
        expect(spec.rows, greaterThanOrEqualTo(1));
        expect(spec.columns, greaterThanOrEqualTo(1));
      }
    });

    test('tileAspect 非法时回退 16:9', () {
      final spec = resolveMultiPlayLayout(
        maxWidth: 1920,
        maxHeight: 1080,
        roomCount: 4,
        tileAspect: double.nan,
      );
      expect(spec.tileAspect, closeTo(a169, 1e-12));
      expect(spec.rows, 2);
      expect(spec.columns, 2);
    });
  });

  group('最小窗口尺寸', () {
    test('16:9 基准值', () {
      Size sizeOf(int count) => resolveMultiPlayMinimumWindowSize(
            roomCount: count,
            tileAspect: a169,
          );

      expect(sizeOf(1).width, closeTo(cellW, 1e-9));
      expect(sizeOf(1).height, closeTo(cellH, 1e-9));

      // 2 路：1×2 → 块宽 2 格 + 1 间距
      expect(sizeOf(2).width, closeTo(2 * cellW + kMultiPlaySpacing, 1e-9));
      expect(sizeOf(2).height, closeTo(cellH, 1e-9));

      // 3/4 路：2×2
      expect(sizeOf(3).width, closeTo(2 * cellW + kMultiPlaySpacing, 1e-9));
      expect(sizeOf(4).width, closeTo(2 * cellW + kMultiPlaySpacing, 1e-9));
      expect(sizeOf(4).height, closeTo(2 * cellH + kMultiPlaySpacing, 1e-9));
    });

    test('chrome 直接加到窗口尺寸上', () {
      final plain = resolveMultiPlayMinimumWindowSize(
        roomCount: 4,
        tileAspect: a169,
      );
      final chrome = resolveMultiPlayMinimumWindowSize(
        roomCount: 4,
        tileAspect: a169,
        chromeWidth: 300,
        chromeHeight: 100,
      );
      expect(chrome.width, closeTo(plain.width + 300, 1e-9));
      expect(chrome.height, closeTo(plain.height + 100, 1e-9));
    });

    test('4:3（scaleMode=4）与自定义比例（scaleMode=5）各自按比例抬格高', () {
      final a43Size = resolveMultiPlayMinimumWindowSize(
        roomCount: 4,
        tileAspect: a43,
      );
      // cellW 取 240，则 cellH 需求 180
      expect(a43Size.width, closeTo(2 * 240 + 8, 1e-9));
      expect(a43Size.height, closeTo(2 * 180 + 8, 1e-9));

      const custom = 2.5;
      final customSize = resolveMultiPlayMinimumWindowSize(
        roomCount: 4,
        tileAspect: custom,
      );
      // cellW 被比例抬高到 240 之上，cellH 仍是 135
      expect(customSize.width, closeTo(2 * (135 * custom) + 8, 1e-9));
      expect(customSize.height, closeTo(2 * 135 + 8, 1e-9));
    });

    test('路数超上限按上限算，0/负按 1 路算', () {
      final capped = resolveMultiPlayMinimumWindowSize(
        roomCount: 99,
        tileAspect: a169,
      );
      final one = resolveMultiPlayMinimumWindowSize(
        roomCount: 1,
        tileAspect: a169,
      );
      expect(capped.width, closeTo(2 * cellW + kMultiPlaySpacing, 1e-9));
      expect(
        resolveMultiPlayMinimumWindowSize(roomCount: 0, tileAspect: a169).width,
        closeTo(one.width, 1e-9),
      );
    });
  });

  group('不折叠不变量', () {
    // 契约：区域尺寸 ≥ 最小窗口尺寸 − chrome 时，degraded 必须为 false。
    test('所有路数 × 各种区域尺寸都不折叠', () {
      const chromeW = 300.0;
      const chromeH = 120.0;
      const aspects = [a169, a43, 1.0, 2.5, 0.6];

      for (final aspect in aspects) {
        for (var count = 1; count <= kMultiPlayMaxTiles; count++) {
          final min = resolveMultiPlayMinimumWindowSize(
            roomCount: count,
            tileAspect: aspect,
            chromeWidth: chromeW,
            chromeHeight: chromeH,
          );
          final blockW = min.width - chromeW;
          final blockH = min.height - chromeH;

          for (final factorW in [1.0, 1.01, 1.25, 2.0, 4.0]) {
            for (final factorH in [1.0, 1.01, 1.25, 2.0, 4.0]) {
              final areaW = blockW * factorW;
              final areaH = blockH * factorH;
              final spec = resolveMultiPlayLayout(
                maxWidth: areaW,
                maxHeight: areaH,
                roomCount: count,
                tileAspect: aspect,
              );
              expect(
                spec.degraded,
                isFalse,
                reason: 'aspect=$aspect count=$count area=${areaW}x$areaH',
              );
              expect(spec.slots.length, count);
              // 一路都不折叠时下标应与加入顺序完全一致
              expect(spec.slots.map((e) => e.index), List.generate(count, (i) => i));
            }
          }
        }
      }
    });
  });

  // 竖屏多开要突破单画面那条 16/9 条带，视频区高度由这个纯函数定；
  // 它同时决定「这块屏放不放得下两格」——放不下就整个退回单画面。
  group('竖屏多开的视频区高度', () {
    test('360×740 两格：每格正好回到 16:9，且没吃掉 38% 屏高', () {
      final h = resolvePortraitVideoHeight(
        screenW: 360,
        screenH: 740,
        rows: 2,
      );
      // 2 × 360 × 9/16 + 8 = 413
      expect(h, closeTo(413, 1e-9));
      // 每格 202.5 高 ≥ 135 下限
      expect((h! - kMultiPlaySpacing) / 2, greaterThanOrEqualTo(
        kMultiPlayMinTileHeight,
      ));
    });

    test('屏高不够时夹到 62%，仍给得出合法格高就用夹值', () {
      // 400 宽要 458 高才够两格 16:9；屏高 600×0.62=372 < 458 → 夹到 372，
      // 每格 (372-8)/2 = 182 ≥ 135，仍然可用。
      final h = resolvePortraitVideoHeight(
        screenW: 400,
        screenH: 600,
        rows: 2,
      );
      expect(h, closeTo(600 * kMultiPlayPortraitMaxFraction, 1e-9));
      expect((h! - kMultiPlaySpacing) / 2, greaterThanOrEqualTo(
        kMultiPlayMinTileHeight,
      ));
    });

    test('矮屏放不下两格时返回 null，调用方退回单画面', () {
      expect(
        resolvePortraitVideoHeight(screenW: 320, screenH: 400, rows: 2),
        isNull,
        reason: '上限 400×0.62=248 < 两格最小 2×135+8=278，硬排会把每格压到下限以下',
      );
    });

    test('rows<=1 一律 null：单格用不着这套，交给原来的 16/9 条带', () {
      expect(
        resolvePortraitVideoHeight(screenW: 360, screenH: 740, rows: 1),
        isNull,
      );
    });
  });
}