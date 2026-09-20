import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show Size;
import 'package:simple_live_app/modules/live_room/player/pip_aspect.dart';

void main() {
  const a169 = 16 / 9;
  const a43 = 4 / 3;

  group('FrameInsets 值语义', () {
    test('zero 与 isZero', () {
      expect(FrameInsets.zero.isZero, isTrue);
      expect(const FrameInsets(horizontal: 1).isZero, isFalse);
    });

    test('==/hashCode/toString', () {
      expect(
        const FrameInsets(horizontal: 16, vertical: 8),
        const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(
        const FrameInsets(horizontal: 16, vertical: 8).hashCode,
        const FrameInsets(horizontal: 16, vertical: 8).hashCode,
      );
      expect(
        const FrameInsets(horizontal: 16, vertical: 8).toString(),
        contains('16'),
      );
    });

    test('copyWith', () {
      const ins = FrameInsets(horizontal: 16, vertical: 8);
      expect(ins.copyWith(vertical: 9), const FrameInsets(horizontal: 16, vertical: 9));
      expect(ins.copyWith(horizontal: 0), const FrameInsets(horizontal: 0, vertical: 8));
    });
  });

  group('resolveVideoAspect', () {
    test('正常比例', () {
      expect(PipAspectCalculator.resolveVideoAspect(width: 1920, height: 1080),
          closeTo(a169, 1e-12));
      expect(PipAspectCalculator.resolveVideoAspect(width: 1280, height: 960),
          closeTo(a43, 1e-12));
    });

    test('null / 非有限 / <=0 回退 16/9', () {
      expect(PipAspectCalculator.resolveVideoAspect(width: null, height: 1080),
          a169);
      expect(PipAspectCalculator.resolveVideoAspect(width: 1920, height: null),
          a169);
      expect(
          PipAspectCalculator.resolveVideoAspect(width: 0, height: 1080), a169);
      expect(
          PipAspectCalculator.resolveVideoAspect(width: 1920, height: 0), a169);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: double.infinity, height: 1080),
          a169);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: 1920, height: double.nan),
          a169);
    });
  });

  group('resolveDisplayAspect', () {
    test('scaleMode 3/4/5 与非法回退', () {
      // 3 → 16/9
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 3, aspectByUser: a43, videoWidth: 800, videoHeight: 600),
          closeTo(a169, 1e-12));
      // 4 → 4/3
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 4, aspectByUser: a169, videoWidth: 800, videoHeight: 600),
          closeTo(a43, 1e-12));
      // 5 + 合法 aspectByUser → 返回用户比例
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 5, aspectByUser: a43, videoWidth: 800, videoHeight: 600),
          closeTo(a43, 1e-12));
      // 5 + 非法 aspectByUser → 回退视频比例
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 5, aspectByUser: 0, videoWidth: 1920, videoHeight: 1080),
          closeTo(a169, 1e-12));
      // 0/1/2/其它 → 视频比例；非法视频 → 16/9
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 0, videoWidth: 1920, videoHeight: 1080),
          closeTo(a169, 1e-12));
      expect(
          PipAspectCalculator.resolveDisplayAspect(
              scaleMode: 2, videoWidth: null, videoHeight: null),
          closeTo(a169, 1e-12));
    });
  });

  group('isUsableAspect', () {
    test('边界', () {
      expect(PipAspectCalculator.isUsableAspect(a169), isTrue);
      expect(PipAspectCalculator.isUsableAspect(null), isFalse);
      expect(PipAspectCalculator.isUsableAspect(double.nan), isFalse);
      expect(PipAspectCalculator.isUsableAspect(0.05), isFalse);
      expect(PipAspectCalculator.isUsableAspect(20), isFalse);
      expect(PipAspectCalculator.isUsableAspect(0.06), isTrue);
      expect(PipAspectCalculator.isUsableAspect(19.9), isTrue);
    });
  });

  group('clientSizeForAspect', () {
    test('横屏 (400,225) / 竖屏 (225,400)', () {
      final landscape = PipAspectCalculator.clientSizeForAspect(
        memoryLongSide: 400,
        aspect: a169,
      );
      expect(landscape.width, closeTo(400, 1e-9));
      expect(landscape.height, closeTo(225, 1e-9));

      final portrait = PipAspectCalculator.clientSizeForAspect(
        memoryLongSide: 400,
        aspect: 9 / 16,
      );
      expect(portrait.width, closeTo(225, 1e-9));
      expect(portrait.height, closeTo(400, 1e-9));
    });

    test('aspect>=1 时宽=长边', () {
      final s = PipAspectCalculator.clientSizeForAspect(
        memoryLongSide: 320,
        aspect: a43,
      );
      expect(s.width, 320);
      expect(s.height, closeTo(240, 1e-9));
    });
  });

  group('outerSizeForClient', () {
    test('Win11 insets=(16,8) → (416,233)', () {
      final outer = PipAspectCalculator.outerSizeForClient(
        client: const Size(400, 225),
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(outer.width, 416);
      expect(outer.height, 233);
    });
  });

  group('outerSizeForOuterWidth', () {
    test('W=416, A=16/9, insets=(16,8) → (416,233)', () {
      final outer = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(outer.width, 416);
      expect(outer.height, 233);
    });

    test('精确对齐后客户区比例 == A（误差 < 1e-9）', () {
      const W = 816.0;
      final outer = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: W,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      final cw = outer.width - 16;
      final ch = outer.height - 8;
      expect((cw / a169 - ch).abs(), lessThan(1e-9));
    });
  });

  group('outerAspectRatioForOuterWidth 与 outerAspectRatioForClientWidth 等价', () {
    test('Win11 insets=(16,8)', () {
      const W = 416.0;
      final rOuter = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: W,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      final rClient = PipAspectCalculator.outerAspectRatioForClientWidth(
        clientWidth: W - 16,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(rOuter, closeTo(rClient, 1e-12));
    });

    test('竖屏比例也等价', () {
      const clientW = 225.0;
      final rClient = PipAspectCalculator.outerAspectRatioForClientWidth(
        clientWidth: clientW,
        aspect: 9 / 16,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      final rOuter = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: clientW + 16,
        aspect: 9 / 16,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(rOuter, closeTo(rClient, 1e-12));
    });
  });

  group('固定样例断言（修正后）', () {
    test('insets=(16,8)、A=16/9、W0=416 → R(416)==416/233', () {
      final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      // 推导：ch = (416-16)/(16/9) + 8 = 400*9/16 + 8 = 225 + 8 = 233
      //      R = W / ch = 416 / 233
      expect(r, closeTo(416 / 233, 1e-12));
    });

    test('Win10 insets=(16,9) → R(416)==416/234', () {
      final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 9),
      );
      // 推导：ch = (416-16)/(16/9) + 9 = 225 + 9 = 234
      //      R = 416 / 234
      expect(r, closeTo(416 / 234, 1e-12));
    });
  });

  group('残差对照（复现黑边成因）', () {
    test('未补偿（单一 R=A）在 W=816 时约 1px 残差', () {
      // 直接把画面比例 A 当作外框比例施加（不做边框补偿），
      // 任意外框宽下客户区比例都不精确等于 A，残差恒为 hx/A - hy。
      const W = 816.0;
      const hx = 16.0;
      const hy = 8.0;
      final chSingle = W / a169 - hy; // OS 按外框比例 R=A 设高
      final chTarget = (W - hx) / a169; // 目标客户区高
      final residual = (chSingle - chTarget).abs();
      // hx/A - hy = 16/(16/9) - 8 = 9 - 8 = 1px
      expect(residual, closeTo(1.0, 1e-9));
      // 且不经精确对齐时确实 > 0（即会产生可见黑边）
      expect(residual, greaterThan(0.5));
    });

    test('经 outerSizeForOuterWidth 精确对齐后残差 < 1e-9', () {
      for (final W in [416.0, 600.0, 816.0, 1000.0]) {
        final outer = PipAspectCalculator.outerSizeForOuterWidth(
          outerWidth: W,
          aspect: a169,
          insets: const FrameInsets(horizontal: 16, vertical: 8),
        );
        final cw = outer.width - 16;
        final ch = outer.height - 8;
        expect((cw / a169 - ch).abs(), lessThan(1e-9),
            reason: 'W=$W 应对齐');
      }
    });
  });

  group('insetsFromSizes（负值归零）', () {
    test('正常', () {
      final ins = PipAspectCalculator.insetsFromSizes(
        outer: const Size(416, 233),
        client: const Size(400, 225),
      );
      expect(ins, const FrameInsets(horizontal: 16, vertical: 8));
    });

    test('负值归零', () {
      final ins = PipAspectCalculator.insetsFromSizes(
        outer: const Size(400, 225),
        client: const Size(416, 233),
      );
      expect(ins, FrameInsets.zero);
    });
  });

  group('normalizeClientSize（minLongSide 抬升）', () {
    test('长边不足 → 抬升到 minLongSide', () {
      final s = PipAspectCalculator.normalizeClientSize(
        memoryLongSide: 100,
        aspect: a169,
        minLongSide: 320,
      );
      // 长边抬升到 320
      expect(s.width, closeTo(320, 1e-9));
      expect(s.height, closeTo(180, 1e-9));
    });

    test('长边充足 → 保持记忆长边', () {
      final s = PipAspectCalculator.normalizeClientSize(
        memoryLongSide: 400,
        aspect: a169,
        minLongSide: 320,
      );
      expect(s.width, closeTo(400, 1e-9));
      expect(s.height, closeTo(225, 1e-9));
    });

    test('默认 minLongSide=320', () {
      final s = PipAspectCalculator.normalizeClientSize(
        memoryLongSide: 400,
        aspect: a169,
      );
      expect(s.width, closeTo(400, 1e-9));
    });
  });

  group('matchesAspect（容差边界）', () {
    test('精确合规命中', () {
      final outer = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(
          PipAspectCalculator.matchesAspect(
            outer: outer,
            aspect: a169,
            insets: const FrameInsets(horizontal: 16, vertical: 8),
          ),
          isTrue);
    });

    test('略偏（< eps）仍视为合规', () {
      const ins = FrameInsets(horizontal: 16, vertical: 8);
      final within = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: ins,
      );
      final slightlyOff = Size(within.width, within.height + 0.5); // 偏差 0.5px
      expect(
          PipAspectCalculator.matchesAspect(
            outer: slightlyOff,
            aspect: a169,
            insets: ins,
            epsPx: 1.0,
          ),
          isTrue);
    });

    test('超出 eps 视为不合规', () {
      const ins = FrameInsets(horizontal: 16, vertical: 8);
      final aligned = PipAspectCalculator.outerSizeForOuterWidth(
        outerWidth: 416,
        aspect: a169,
        insets: ins,
      );
      final off = Size(aligned.width, aligned.height + 3.0); // 偏差 3px
      expect(
          PipAspectCalculator.matchesAspect(
            outer: off,
            aspect: a169,
            insets: ins,
          ),
          isFalse);
    });

    test('客户区尺寸 <=0 返回 false', () {
      expect(
          PipAspectCalculator.matchesAspect(
            outer: const Size(10, 10),
            aspect: a169,
            insets: const FrameInsets(horizontal: 16, vertical: 8),
          ),
          isFalse);
    });
  });

  group('expectedHiddenInsets（无标题栏态理论内边距）', () {
    test('dpr 各取值 → 逻辑像素 = 物理/dpr', () {
      // 物理边框 16(左右)/8(底, Win11)：horizontal=16/dpr、vertical=8/dpr
      expect(PipAspectCalculator.expectedHiddenInsets(1.0),
          const FrameInsets(horizontal: 16, vertical: 8));
      expect(PipAspectCalculator.expectedHiddenInsets(1.25),
          const FrameInsets(horizontal: 12.8, vertical: 6.4));
      expect(PipAspectCalculator.expectedHiddenInsets(1.5),
          const FrameInsets(horizontal: 16 / 1.5, vertical: 8 / 1.5));
      expect(PipAspectCalculator.expectedHiddenInsets(2.0),
          const FrameInsets(horizontal: 8, vertical: 4));
    });

    test('Win10 垂直为 9/dpr', () {
      expect(PipAspectCalculator.expectedHiddenInsets(1.0, windows11: false),
          const FrameInsets(horizontal: 16, vertical: 9));
      expect(PipAspectCalculator.expectedHiddenInsets(2.0, windows11: false),
          const FrameInsets(horizontal: 8, vertical: 4.5));
    });

    test('dpr<=0 / 非有限 → 退化为 dpr=1', () {
      const fallback = FrameInsets(horizontal: 16, vertical: 8);
      expect(PipAspectCalculator.expectedHiddenInsets(0), fallback);
      expect(PipAspectCalculator.expectedHiddenInsets(-1), fallback);
      expect(PipAspectCalculator.expectedHiddenInsets(double.infinity), fallback);
      expect(PipAspectCalculator.expectedHiddenInsets(double.nan), fallback);
    });
  });

  group('isPlausibleHiddenInsets（物理像素判据，修正后）', () {
    // 隐藏态：理论值在所有 dpr 下都必须通过。
    test('隐藏态各 dpr 通过', () {
      for (final dpr in const [1.0, 1.25, 1.5, 2.0]) {
        final hidden = PipAspectCalculator.expectedHiddenInsets(dpr);
        expect(PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: dpr),
            isTrue,
            reason: 'dpr=$dpr 隐藏态应判为合理');
      }
    });

    // 正常态（保留标题栏）：物理垂直≈39*dpr 恒 > 20，必须全部被拒。
    test('正常态各 dpr 被拒', () {
      // logical normal insets = 物理(8,39)/dpr
      final normals = <double, FrameInsets>{
        1.0: const FrameInsets(horizontal: 8, vertical: 39),
        1.25: const FrameInsets(horizontal: 6.4, vertical: 31.2),
        1.5: const FrameInsets(horizontal: 16 / 1.5, vertical: 26),
        2.0: const FrameInsets(horizontal: 8, vertical: 19.5),
      };
      normals.forEach((dpr, ins) {
        expect(PipAspectCalculator.isPlausibleHiddenInsets(ins, dpr: dpr),
            isFalse,
            reason: 'dpr=$dpr 正常态应被拒（物理垂直≥39）');
      });
    });

    // dpr=2 正常态逻辑 (8, 19.5) 的回归点：
    //   物理 H=8*2=16<=32、V=19.5*2=39>20 → 拒。
    // 若按文档原字面「对逻辑像素判 h<=32 && v<=20」，则 19.5<=20 会**漏判为通过**，
    // 正是竞态残留黑边的根因；修正后物理判据正确拒绝它。
    test('dpr=2 正常态（逻辑 8/19.5）必须被拒——关键回归点', () {
      const normal2 = FrameInsets(horizontal: 8, vertical: 19.5);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(normal2, dpr: 2.0),
          isFalse);
    });

    test('负 / 非有限内边距被拒', () {
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: -1, vertical: 5)),
          isFalse);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: double.nan, vertical: 5)),
          isFalse);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 5, vertical: double.infinity)),
          isFalse);
    });

    test('dpr<=0 / 非有限 → 退化为 dpr=1 判据', () {
      const hidden = FrameInsets(horizontal: 16, vertical: 8);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: 0), isTrue);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: -1), isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: double.nan),
          isTrue);
      const normal = FrameInsets(horizontal: 8, vertical: 39);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(normal, dpr: 0), isFalse);
    });

    test('恰好压线（物理 32/20）通过，超线被拒', () {
      // dpr=2 下逻辑 (16,10) → 物理 (32,20)，边界值通过
      const onEdge = FrameInsets(horizontal: 16, vertical: 10);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(onEdge, dpr: 2.0),
          isTrue);
      // 物理垂直刚超 20 → 拒
      const overV = FrameInsets(horizontal: 16, vertical: 10.001);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(overV, dpr: 2.0),
          isFalse);
    });
  });

  group('clientLongSideFromOuter（F1 外框→客户区长边换算）', () {
    // 横屏不动点：outer=(416,233)、A=16/9、insets=(16,8)
    //   → clientLong == 400 → normalize(400,16/9)==(400,225)
    //   → outerSizeForClient==(416,233)。即 outer→clientLong→outer 恒等，
    //     反复进出小窗不再累积 +insets。
    test('横屏：外框(416,233) ↔ 客户区长边 400 的精确不动点', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const A = 16 / 9;
      final outer0 = const Size(416, 233);
      final long =
          PipAspectCalculator.clientLongSideFromOuter(outer: outer0, insets: I);
      expect(long, 400);
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: long, aspect: A);
      expect(client, const Size(400, 225));
      final outer1 = PipAspectCalculator.outerSizeForClient(
          client: client, insets: I);
      expect(outer1, const Size(416, 233)); // 恒等恢复（不动点）
    });

    // 竖屏：outer=(233,416)、A=9/16、insets=(16,8)
    //   高为长边 → clientLong == 416-8 == 408；回代外框高恒 416（长边不动点）。
    //   备注：规格里的「回代恢复 (233,416)」是笔误——该比例下稳定外框实为 (245.5,416)，
    //   但客户区长边恒为 408，关键是 clientLong 不再漂移（F1 直接回归点）。
    test('竖屏：外框(233,416) → 客户区长边 408（高为长边，减 vertical）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const A = 9 / 16;
      final long = PipAspectCalculator.clientLongSideFromOuter(
          outer: const Size(233, 416), insets: I);
      expect(long, 408);
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: long, aspect: A);
      final outer1 = PipAspectCalculator.outerSizeForClient(
          client: client, insets: I);
      // 外框高 = 408+8 = 416 不变，即该比例下的稳定不动点。
      expect(outer1.height, 416);
      // 再次提取长边仍是 408 → 证明不再漂移。
      final long2 = PipAspectCalculator.clientLongSideFromOuter(
          outer: outer1, insets: I);
      expect(long2, 408);
    });

    // 零 insets（macOS/Linux 口径）：outer=(400,225) → clientLong==400，回代不变。
    test('零 insets（macOS/Linux 口径）：长边不变', () {
      const I = FrameInsets.zero;
      const A = 16 / 9;
      final outer0 = const Size(400, 225);
      final long =
          PipAspectCalculator.clientLongSideFromOuter(outer: outer0, insets: I);
      expect(long, 400);
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: long, aspect: A);
      final outer1 = PipAspectCalculator.outerSizeForClient(
          client: client, insets: I);
      expect(outer1, const Size(400, 225));
    });

    // 非法输入：负数 / NaN / Infinity / 内边距 ≥ 长边 → 返回 0（由调用方兜底）。
    test('非法输入返回 0', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(-10, 50), insets: I),
          0);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(50, -10), insets: I),
          0);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: Size(double.nan, 50), insets: I),
          0);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: Size(double.infinity, 50), insets: I),
          0);
      // 内边距 ≥ 长边：近方小窗，高 5 < 8 → 5-8 < 0 → 0
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(5, 5), insets: I),
          0);
    });

    // 多轮迭代不漂移：outer→clientLong→normalize→outer 连跑 5 次，
    // 客户区长边恒定（横屏 400 / 竖屏 408），外框稳定，绝不单调放大（F1 直接回归点）。
    test('多轮迭代不漂移（F1 直接回归点）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      // 横屏：首轮即精确不动点
      var land = const Size(416, 233);
      final landLongs = <double>[];
      for (var i = 0; i < 5; i++) {
        final long =
            PipAspectCalculator.clientLongSideFromOuter(outer: land, insets: I);
        landLongs.add(long);
        final client = PipAspectCalculator.normalizeClientSize(
            memoryLongSide: long, aspect: 16 / 9);
        land = PipAspectCalculator.outerSizeForClient(client: client, insets: I);
      }
      expect(landLongs.every((l) => l == 400), isTrue,
          reason: '横屏长边恒 400');

      // 竖屏：首轮由记忆 (233,416) 得 408，随后全部保持 408（不再变化）
      var port = const Size(233, 416);
      final portLongs = <double>[];
      for (var i = 0; i < 5; i++) {
        final long =
            PipAspectCalculator.clientLongSideFromOuter(outer: port, insets: I);
        portLongs.add(long);
        final client = PipAspectCalculator.normalizeClientSize(
            memoryLongSide: long, aspect: 9 / 16);
        port = PipAspectCalculator.outerSizeForClient(client: client, insets: I);
      }
      expect(portLongs.first, 408);
      expect(portLongs.skip(1).every((l) => l == 408), isTrue,
          reason: '竖屏长边恒 408');
    });

    // —— Task C 收口：近方形方向定义回归（核心）——
    // 旧口径按 outer.width > outer.height 取方向，对近方形（外框长宽差 ≤ insets 差=8）
    // 会翻转客户区长边方向：A<1 时每轮把长边乘 A → 单调收缩直到 320 下限。
    // 新口径按客户区维度取 max(cw,ch)，在记忆尺寸稳定点满足 F(F(x))==F(x)。
    group('近方形方向收口（max(cw,ch) 幂等，A∈{0.98,0.99,1.0,1.02}）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const aspects = [0.98, 0.99, 1.0, 1.02];
      // 初始外框刻意做成「外框宽略大于高」（翻转易发区，长宽差 ≤8），
      // 使得旧口径误判长边方向。
      const initialOuters = [
        Size(410, 405),
        Size(412, 408),
        Size(416, 412),
      ];

      for (final A in aspects) {
        for (final o0 in initialOuters) {
          test('A=$A, outer=$o0：一轮映射后长边幂等 F(F(x))==F(x)', () {
            final long0 = PipAspectCalculator.clientLongSideFromOuter(
                outer: o0, insets: I);
            // 完整应用一次映射：长边 → 归一化客户区 → 外框
            final client = PipAspectCalculator.normalizeClientSize(
                memoryLongSide: long0, aspect: A);
            final o1 = PipAspectCalculator.outerSizeForClient(
                client: client, insets: I);
            final long1 = PipAspectCalculator.clientLongSideFromOuter(
                outer: o1, insets: I);
            expect(long1, closeTo(long0, 1e-9),
                reason: 'A=$A 近方形映射非幂等（方向翻转）');
          });

          test('A=$A, outer=$o0：5 轮迭代长边恒定（不漂移/不收缩）', () {
            var o = o0;
            final longs = <double>[];
            for (var i = 0; i < 5; i++) {
              final long = PipAspectCalculator.clientLongSideFromOuter(
                  outer: o, insets: I);
              longs.add(long);
              final client = PipAspectCalculator.normalizeClientSize(
                  memoryLongSide: long, aspect: A);
              o = PipAspectCalculator.outerSizeForClient(
                  client: client, insets: I);
            }
            expect(
                longs.skip(1).every((l) => (l - longs.first).abs() < 1e-9),
                isTrue,
                reason: 'A=$A 近方形多轮长边漂移（应为恒定序列 $longs）');
          });
        }
      }
    });

    // 直接等价护栏：新口径返回值恒等于 max(outer.width-h, outer.height-v)。
    // 覆盖翻转易发区（外框宽>高 但差≤8，旧口径取错边）与非翻转区，
    // 旧口径在此类用例会返回 width-h 而非客户区长边。
    test('返回值恒等于 max(clientW, clientH)', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const cases = <Size>[
        // 翻转易发区：外框宽>高 但差≤8 → 旧口径取宽边、新口径取客户区长边
        Size(410, 405), // cw=394, ch=397 → 397
        Size(412, 408), // cw=396, ch=400 → 400
        Size(416, 412), // cw=400, ch=404 → 404
        // 非翻转（外框宽>>高）：两边均取宽边，等价
        Size(600, 350), // cw=584, ch=342 → 584
        // 竖向外框（高>宽）
        Size(350, 600), // cw=334, ch=592 → 592
      ];
      for (final o in cases) {
        final cw = o.width - I.horizontal;
        final ch = o.height - I.vertical;
        final expected = cw > ch ? cw : ch;
        final got =
            PipAspectCalculator.clientLongSideFromOuter(outer: o, insets: I);
        expect(got, closeTo(expected, 1e-9), reason: 'outer=$o');
      }
    });
  });
}
