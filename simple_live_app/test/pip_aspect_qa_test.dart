/// QA 独立验证套件 —— 由 QA(严过关) 重写，不复用工程师用例的断言来源。
///
/// 目标：用**独立推导**的公式/数值证明 pip_aspect.dart 的纯逻辑正确，
/// 而不是复述工程师已写下的期望值。所有断言均从第一性原理（几何/代数）算出。
///
/// 注意：本文件只 import pip_aspect.dart（不触 window_manager），可在 Dart VM 跑。
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/pip_aspect.dart';

/// 独立推导：由外框宽 W、比例 A、内边距 I，客户区高应为 (W-hx)/A。
double _expectedClientHeight(double W, double A, FrameInsets I) =>
    (W - I.horizontal) / A;

/// 扫描用的比例集合：竖屏、方、宽、超宽、常见值。
const List<double> _aspects = [
  9 / 16, // A<1 竖屏
  0.5,
  1.0, // 方
  4 / 3,
  16 / 9,
  2.39, // 影院超宽
  10.0,
];

/// 扫描用的内边距集合：全零、Win11、Win10、很大。
const List<FrameInsets> _insets = [
  FrameInsets.zero,
  FrameInsets(horizontal: 16, vertical: 8),
  FrameInsets(horizontal: 16, vertical: 9),
  FrameInsets(horizontal: 100, vertical: 100),
];

const List<double> _widths = [200.0, 416.0, 600.0, 816.0, 1000.0, 1920.0];

void main() {
  // ============================================================
  // A.1 自洽性：outer → client 必须精确复原 A（静止态零残差）
  // ============================================================
  group('A.1 静止态零残差（独立扫描）', () {
    test('任意 (W,A,I) 下 client.width/client.height == A，误差 < 1e-9', () {
      for (final A in _aspects) {
        for (final I in _insets) {
          for (final W in _widths) {
            final outer = PipAspectCalculator.outerSizeForOuterWidth(
              outerWidth: W,
              aspect: A,
              insets: I,
            );
            // 客户区 = 外框 − 内边距（几何定义，独立于实现）
            final cw = outer.width - I.horizontal;
            final ch = outer.height - I.vertical;
            expect(outer.width, W, reason: 'A=$A I=$I W=$W 外框宽必须保持');
            expect(ch, closeTo(_expectedClientHeight(W, A, I), 1e-9),
                reason: 'A=$A I=$I W=$W 客户区高');
            expect(cw / ch, closeTo(A, 1e-9),
                reason: 'A=$A I=$I W=$W 客户区比例');
          }
        }
      }
    });
  });

  // ============================================================
  // A.2 R 与 snap 一致；两个 R 重载等价
  // ============================================================
  group('A.2 R 与 snap 一致（独立扫描）', () {
    test('Size(W, W/R) 的客户区比例 == A', () {
      for (final A in _aspects) {
        for (final I in _insets) {
          for (final W in _widths) {
            final R = PipAspectCalculator.outerAspectRatioForOuterWidth(
              outerWidth: W,
              aspect: A,
              insets: I,
            );
            final snapped = Size(W, W / R);
            final cw = snapped.width - I.horizontal;
            final ch = snapped.height - I.vertical;
            expect(cw / ch, closeTo(A, 1e-9),
                reason: 'A=$A I=$I W=$W 用 R 反推的客户区比例');
          }
        }
      }
    });

    test('R_outer(W) == R_client(W - hx)', () {
      for (final A in _aspects) {
        for (final I in _insets) {
          for (final W in _widths) {
            final rOuter = PipAspectCalculator.outerAspectRatioForOuterWidth(
              outerWidth: W,
              aspect: A,
              insets: I,
            );
            final rClient = PipAspectCalculator.outerAspectRatioForClientWidth(
              clientWidth: W - I.horizontal,
              aspect: A,
              insets: I,
            );
            expect(rOuter, closeTo(rClient, 1e-12),
                reason: 'A=$A I=$I W=$W 两重载应等价');
          }
        }
      }
    });
  });

  // ============================================================
  // A.3 与旧行为兼容（回退守护）
  // ============================================================
  group('A.3 旧行为兼容', () {
    test('记忆 400 → 16:9 得 (400,225)；9:16 得 (225,400)', () {
      final land = PipAspectCalculator.clientSizeForAspect(
        memoryLongSide: 400,
        aspect: 16 / 9,
      );
      expect(land, const Size(400, 225));

      final port = PipAspectCalculator.clientSizeForAspect(
        memoryLongSide: 400,
        aspect: 9 / 16,
      );
      expect(port, const Size(225, 400));
    });
  });

  // ============================================================
  // A.4 残差对照：不补偿会残留 hx/A - hy（与 W 无关）
  // ============================================================
  group('A.4 残差对照（独立推导）', () {
    test('单一 R=A：残差恒 = hx/A - hy，与 W 无关', () {
      const A = 16 / 9;
      const hx = 16.0;
      const hy = 8.0;
      // 若把 A 当作外框比例施加：外框高 = W/A → 客户区高 = W/A - hy。
      // 目标客户区高 = (W-hx)/A。残差 = |W/A - hy - (W-hx)/A| = |hx/A - hy|。
      final theoretical = (hx / A - hy).abs();
      expect(theoretical, closeTo(1.0, 1e-12)); // 16/(16/9)=9, 9-8=1
      for (final W in _widths) {
        final chSingle = W / A - hy;
        final chTarget = (W - hx) / A;
        expect((chSingle - chTarget).abs(), closeTo(theoretical, 1e-9),
            reason: 'W=$W 残差应恒为 ${theoretical}px');
      }
      // 1px 级别 → 可见黑边（证明"必须补偿/重算"）
      expect(theoretical, greaterThan(0.5));
    });

    test('补偿后残差 < 1e-9（对照消除）', () {
      const A = 16 / 9;
      const I = FrameInsets(horizontal: 16, vertical: 8);
      for (final W in _widths) {
        final outer = PipAspectCalculator.outerSizeForOuterWidth(
          outerWidth: W,
          aspect: A,
          insets: I,
        );
        final cw = outer.width - I.horizontal;
        final ch = outer.height - I.vertical;
        expect((cw / A - ch).abs(), lessThan(1e-9), reason: 'W=$W');
      }
    });
  });

  // ============================================================
  // A.5 normalizeClientSize
  // ============================================================
  group('A.5 normalizeClientSize', () {
    test('长边不足 → 抬升；比例精确 == A', () {
      for (final A in [16 / 9, 9 / 16, 4 / 3, 0.5, 2.0]) {
        final s = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: 100,
          aspect: A,
          minLongSide: 320,
        );
        final longSide = s.width > s.height ? s.width : s.height;
        expect(longSide, closeTo(320, 1e-9), reason: 'A=$A 长边抬升');
        expect(s.width / s.height, closeTo(A, 1e-12), reason: 'A=$A 比例');
      }
    });

    test('长边充足 → 保持（横/竖分别取长边）', () {
      final land = PipAspectCalculator.normalizeClientSize(
        memoryLongSide: 400,
        aspect: 16 / 9,
        minLongSide: 320,
      );
      expect(land, const Size(400, 225));
      final port = PipAspectCalculator.normalizeClientSize(
        memoryLongSide: 400,
        aspect: 9 / 16,
        minLongSide: 320,
      );
      expect(port, const Size(225, 400));
    });
  });

  // ============================================================
  // A.6 边界与非法输入
  // ============================================================
  group('A.6 边界与非法输入', () {
    test('resolveVideoAspect 非法输入一律 fallbackAspect', () {
      const f = PipAspectCalculator.fallbackAspect;
      expect(PipAspectCalculator.resolveVideoAspect(width: null, height: 1), f);
      expect(PipAspectCalculator.resolveVideoAspect(width: 1, height: null), f);
      expect(PipAspectCalculator.resolveVideoAspect(width: 0, height: 1), f);
      expect(PipAspectCalculator.resolveVideoAspect(width: 1, height: 0), f);
      expect(PipAspectCalculator.resolveVideoAspect(width: -1, height: 1), f);
      expect(PipAspectCalculator.resolveVideoAspect(width: 1, height: -1), f);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: double.nan, height: 1),
          f);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: 1, height: double.nan),
          f);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: double.infinity, height: 1),
          f);
      expect(
          PipAspectCalculator.resolveVideoAspect(
              width: 1, height: double.negativeInfinity),
          f);
    });

    test('isUsableAspect 开区间 (0.05, 20)', () {
      expect(PipAspectCalculator.isUsableAspect(0.05), isFalse); // 恰在下界 → 开
      expect(PipAspectCalculator.isUsableAspect(20.0), isFalse); // 恰在上界 → 开
      expect(PipAspectCalculator.isUsableAspect(0.05 + 1e-12), isTrue);
      expect(PipAspectCalculator.isUsableAspect(20.0 - 1e-12), isTrue);
      expect(PipAspectCalculator.isUsableAspect(null), isFalse);
      expect(PipAspectCalculator.isUsableAspect(double.nan), isFalse);
      expect(PipAspectCalculator.isUsableAspect(double.infinity), isFalse);
    });

    test('matchesAspect 容差边界（用 A=1、I=0 构造精确 eps）', () {
      // A=1、insets=0 → cw/A - ch = cw - ch，可控到精确值
      const I = FrameInsets.zero;
      // 恰等于 eps=1.0 → true
      expect(
          PipAspectCalculator.matchesAspect(
              outer: const Size(100, 99), aspect: 1.0, insets: I, epsPx: 1.0),
          isTrue);
      // 略超 eps → false
      expect(
          PipAspectCalculator.matchesAspect(
              outer: const Size(100, 98.9999998),
              aspect: 1.0,
              insets: I,
              epsPx: 1.0),
          isFalse);
      // 客户区 <=0 → false
      expect(
          PipAspectCalculator.matchesAspect(
              outer: const Size(10, 100),
              aspect: 1.0,
              insets: const FrameInsets(horizontal: 20)),
          isFalse);
    });

    test('insetsFromSizes 负值归零', () {
      expect(
          PipAspectCalculator.insetsFromSizes(
              outer: const Size(100, 50), client: const Size(120, 80)),
          FrameInsets.zero);
      expect(
          PipAspectCalculator.insetsFromSizes(
              outer: const Size(120, 80), client: const Size(100, 50)),
          const FrameInsets(horizontal: 20, vertical: 30));
    });
  });

  // ============================================================
  // A.7 isPlausibleHiddenInsets —— 物理像素判据（重点证伪）
  // ============================================================
  group('A.7 isPlausibleHiddenInsets 物理像素判据', () {
    test('dpr=1：隐藏 (16,8)=true，正常 (16,39)=false', () {
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 16, vertical: 8),
              dpr: 1.0),
          isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 16, vertical: 39),
              dpr: 1.0),
          isFalse);
    });

    test('dpr=2：隐藏 (8,4)=true，正常 (8,19.5)=false（关键回归点）', () {
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 8, vertical: 4),
              dpr: 2.0),
          isTrue);
      // 物理 (16, 39) > 阈值 20 → 必须拒；若逻辑口径会误判 true
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 8, vertical: 19.5),
              dpr: 2.0),
          isFalse);
    });

    test('dpr=1.25 / 1.5：隐藏 true，正常 false', () {
      // dpr=1.25：隐藏 (12.8,6.4)，正常逻辑 vertical=39/1.25=31.2
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 12.8, vertical: 6.4),
              dpr: 1.25),
          isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 6.4, vertical: 31.2),
              dpr: 1.25),
          isFalse);

      // dpr=1.5：隐藏 (16/1.5, 8/1.5)，正常 vertical=39/1.5=26
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 16 / 1.5, vertical: 8 / 1.5),
              dpr: 1.5),
          isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 8 / 1.5, vertical: 26),
              dpr: 1.5),
          isFalse);
    });

    test('正常态两种物理模型都被拒（稳健性）', () {
      // 模型 a：正常物理恒 39 → 逻辑 39/dpr
      // 模型 b：正常物理 39*dpr（逻辑恒定 39）
      for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        expect(
            PipAspectCalculator.isPlausibleHiddenInsets(
                FrameInsets(horizontal: 8 / dpr, vertical: 39 / dpr),
                dpr: dpr),
            isFalse,
            reason: 'dpr=$dpr 模型a 应拒');
        expect(
            PipAspectCalculator.isPlausibleHiddenInsets(
                const FrameInsets(horizontal: 8, vertical: 39),
                dpr: dpr),
            isFalse,
            reason: 'dpr=$dpr 模型b 应拒');
      }
    });

    test('负 / NaN / Infinity → false', () {
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: -1, vertical: 5)),
          isFalse);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 5, vertical: -1)),
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

    test('物理判据严格强于逻辑判据（dpr>=1 时）', () {
      // 独立推导：物理判据拒 ⟺ v*dpr > 20 ⟺ v > 20/dpr；逻辑拒 ⟺ v > 20。
      // dpr>=1 ⇒ 20/dpr <= 20 ⇒ 物理拒的集合 ⊇ 逻辑拒的集合。
      for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        for (final v in [0.0, 4.0, 10.0, 19.5, 20.0, 20.1, 26.0, 39.0]) {
          final physical = PipAspectCalculator.isPlausibleHiddenInsets(
              FrameInsets(horizontal: 8, vertical: v),
              dpr: dpr);
          final logicalOk = 8 <= 32 && v <= 20;
          if (!logicalOk) {
            expect(physical, isFalse,
                reason: 'dpr=$dpr v=$v：逻辑已拒，物理必须也拒');
          }
        }
      }
    });

    test('dpr<=0 / 非有限 → 退化为 dpr=1', () {
      const hidden = FrameInsets(horizontal: 16, vertical: 8);
      expect(PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: 0), isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: -3), isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(hidden, dpr: double.nan),
          isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(hidden,
              dpr: double.infinity),
          isTrue);
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(
              const FrameInsets(horizontal: 16, vertical: 39),
              dpr: 0),
          isFalse);
    });
  });

  // ============================================================
  // A.8 expectedHiddenInsets
  // ============================================================
  group('A.8 expectedHiddenInsets', () {
    test('Win11：vertical=8/dpr；Win10：vertical=9/dpr', () {
      for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        expect(PipAspectCalculator.expectedHiddenInsets(dpr),
            FrameInsets(horizontal: 16 / dpr, vertical: 8 / dpr));
        expect(PipAspectCalculator.expectedHiddenInsets(dpr, windows11: false),
            FrameInsets(horizontal: 16 / dpr, vertical: 9 / dpr));
      }
    });

    test('dpr<=0 / 非有限 → 按 dpr=1 处理', () {
      const fallback = FrameInsets(horizontal: 16, vertical: 8);
      expect(PipAspectCalculator.expectedHiddenInsets(0), fallback);
      expect(PipAspectCalculator.expectedHiddenInsets(-1), fallback);
      expect(PipAspectCalculator.expectedHiddenInsets(double.nan), fallback);
      expect(
          PipAspectCalculator.expectedHiddenInsets(double.infinity), fallback);
    });

    test('expectedHiddenInsets 恒被 isPlausibleHiddenInsets 接受', () {
      for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        final ins = PipAspectCalculator.expectedHiddenInsets(dpr);
        expect(PipAspectCalculator.isPlausibleHiddenInsets(ins, dpr: dpr),
            isTrue,
            reason: 'dpr=$dpr 理论隐藏值必须自洽通过');
      }
    });
  });

  // ============================================================
  // 专项：复核 team-lead 修正过的两处判据
  // ============================================================
  group('复核修正点', () {
    test('R(416, 16/9, (16,8)) == 416/233（独立推导）', () {
      // ch = (416-16)/(16/9) + 8 = 400*9/16 + 8 = 225 + 8 = 233
      const expected = 416 / 233;
      final r = PipAspectCalculator.outerAspectRatioForOuterWidth(
        outerWidth: 416,
        aspect: 16 / 9,
        insets: const FrameInsets(horizontal: 16, vertical: 8),
      );
      expect(r, closeTo(expected, 1e-15));
      // 交叉校验：W/R 必须等于 233
      expect(416 / r, closeTo(233, 1e-9));
    });

    test('物理像素口径确为必要：逻辑口径会漏判 dpr=2 正常态', () {
      const normal2 = FrameInsets(horizontal: 8, vertical: 19.5);
      // 逻辑口径（错误）会误判为 true：
      final logicalWouldPass = normal2.horizontal <= 32 && normal2.vertical <= 20;
      expect(logicalWouldPass, isTrue, reason: '证实逻辑口径确有漏洞');
      // 物理口径（正确）拒绝：
      expect(
          PipAspectCalculator.isPlausibleHiddenInsets(normal2, dpr: 2.0),
          isFalse);
    });
  });

  // ============================================================
  // F1 复验：外框→客户区长边换算 + 复合映射幂等性（QA 独立构造）
  // ============================================================
  group('F1 复验 clientLongSideFromOuter', () {
    test('基本换算：横屏减 horizontal / 竖屏减 vertical / 等高走纵向', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(416, 233), insets: I),
          400); // 宽为长边 → 416-16
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(233, 416), insets: I),
          408); // 高为长边 → 416-8
      // 等高：width>height 为 false → 取高为长边、减 vertical
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(300, 300), insets: I),
          292);
    });

    test('非法/退化输入 → 0', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      for (final o in <Size>[
        const Size(-1, 50),
        const Size(50, -1),
        const Size(0, 50),
        const Size(50, 0),
        Size(double.nan, 50),
        Size(50, double.nan),
        Size(double.infinity, 50),
        Size(50, double.infinity),
        const Size(5, 5), // 内边距(纵向 8) >= 长边(5)
      ]) {
        expect(
            PipAspectCalculator.clientLongSideFromOuter(outer: o, insets: I),
            0,
            reason: '$o');
      }
    });
  });

  group('F1 复合映射 F 幂等性 F(F(x))==F(x)', () {
    // F 精确复刻 window_service.applyPipAspect(:457-471) 的记忆值消费链路
    Size f(Size x, double a, FrameInsets insets) {
      final raw =
          PipAspectCalculator.clientLongSideFromOuter(outer: x, insets: insets);
      final longSide = raw > 0 ? raw : 400.0;
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: longSide, aspect: a);
      return PipAspectCalculator.outerSizeForClient(
          client: client, insets: insets);
    }

    // 旧（有 bug）消费：外框长边直接当客户区长边
    Size oldF(Size x, double a, FrameInsets insets) {
      final longSide = x.width > x.height ? x.width : x.height;
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: longSide, aspect: a);
      return PipAspectCalculator.outerSizeForClient(
          client: client, insets: insets);
    }

    final aspects = [16 / 9, 4 / 3, 2.39, 9 / 16, 0.5];
    const insetsList = [
      FrameInsets.zero,
      FrameInsets(horizontal: 16, vertical: 8),
      FrameInsets(horizontal: 16, vertical: 9),
      FrameInsets(horizontal: 20, vertical: 40),
    ];

    test('全扫描：F(F(x))==F(x) 且 F(x) 客户区比例==A', () {
      final starts = <Size>[];
      for (double w = 100; w <= 2200; w += 137) {
        for (double h = 80; h <= 1400; h += 111) {
          starts.add(Size(w, h));
        }
      }
      for (final a in aspects) {
        for (final ins in insetsList) {
          for (final x in starts) {
            final f1 = f(x, a, ins);
            final f2 = f(f1, a, ins);
            expect(f2.width, closeTo(f1.width, 1e-9),
                reason: 'a=$a ins=$ins x=$x 幂等(宽)');
            expect(f2.height, closeTo(f1.height, 1e-9),
                reason: 'a=$a ins=$ins x=$x 幂等(高)');
            final cw = f1.width - ins.horizontal;
            final ch = f1.height - ins.vertical;
            expect(cw / ch, closeTo(a, 1e-9),
                reason: 'a=$a ins=$ins x=$x 客户区比例');
          }
        }
      }
    });

    test('被旧 bug 污染的记忆值：一步即稳定，此后不再变化', () {
      final polluted = [
        const Size(800, 450),
        const Size(2000, 1000),
        const Size(233, 416),
        const Size(416, 233),
        const Size(1234, 777),
        const Size(777, 1234),
      ];
      for (final a in aspects) {
        for (final ins in insetsList) {
          for (final x in polluted) {
            final f1 = f(x, a, ins);
            final f2 = f(f1, a, ins);
            expect(f2.width, closeTo(f1.width, 1e-9),
                reason: 'a=$a ins=$ins x=$x');
            expect(f2.height, closeTo(f1.height, 1e-9),
                reason: 'a=$a ins=$ins x=$x');
          }
        }
      }
    });

    test('对照实验：去掉换算（旧消费）—— 5 轮长边严格单调放大', () {
      const ins = FrameInsets(horizontal: 16, vertical: 8);
      var x = const Size(416, 233);
      var prevLong = 416.0;
      for (var i = 0; i < 5; i++) {
        x = oldF(x, 16 / 9, ins);
        final long = x.width > x.height ? x.width : x.height;
        expect(long, greaterThan(prevLong),
            reason: '旧消费第 $i 轮长边应严格增大（证明 F1 真实存在）');
        prevLong = long;
      }
    });

    test('零 insets：新链路与旧消费逐位一致（macOS/Linux 无回归）', () {
      const ins = FrameInsets.zero;
      for (final a in aspects) {
        for (final x in [
          const Size(400, 225),
          const Size(225, 400),
          const Size(800, 450),
          const Size(1000, 1000),
        ]) {
          final nw = f(x, a, ins);
          final ow = oldF(x, a, ins);
          expect(nw.width, ow.width, reason: 'a=$a x=$x');
          expect(nw.height, ow.height, reason: 'a=$a x=$x');
        }
      }
    });
  });

  group('F1 定点点（横屏强恒等 / 竖屏独立推导）', () {
    const I = FrameInsets(horizontal: 16, vertical: 8);

    test('横屏精确恒等：(416,233) ↔ 客户区长边 400（严格 ==）', () {
      final l = PipAspectCalculator.clientLongSideFromOuter(
          outer: const Size(416, 233), insets: I);
      expect(l, 400);
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: l, aspect: 16 / 9);
      expect(client, const Size(400, 225));
      final outer = PipAspectCalculator.outerSizeForClient(
          client: client, insets: I);
      expect(outer, const Size(416, 233));
    });

    test('竖屏不动点独立推导：F(245.5,416)==(245.5,416)，客户区长边=408', () {
      // 独立推导：A=9/16，客户区长边取高 ms。客户区=(0.5625ms, ms)，外框=(0.5625ms+16, ms+8)。
      // 取不变量 ms=408 → 外框=(408*0.5625+16, 408+8)=(229.5+16, 416)=(245.5, 416)。
      // 校验客户区=(229.5,408)，229.5/408=0.5625=9/16 ✓。
      expect(408 * (9 / 16) + 16, closeTo(245.5, 1e-12));
      final l = PipAspectCalculator.clientLongSideFromOuter(
          outer: const Size(245.5, 416), insets: I);
      expect(l, closeTo(408, 1e-12)); // 客户区长边恒 408
      final back = PipAspectCalculator.outerSizeForClient(
        client: PipAspectCalculator.normalizeClientSize(
            memoryLongSide: l, aspect: 9 / 16),
        insets: I,
      );
      expect(back, const Size(245.5, 416)); // ① 不动点
      // ② 客户区长边 = 外框高 − vertical = 416−8 = 408
      expect(416 - I.vertical, closeTo(408, 1e-12));
      // 客户区比例精确 9/16
      expect((245.5 - I.horizontal) / (416 - I.vertical),
          closeTo(9 / 16, 1e-12));
    });

    test('竖屏不变量：从被污染外框 (233,416) 连跑 5 轮，长边恒 408', () {
      var outer = const Size(233, 416);
      final longs = <double>[];
      for (var i = 0; i < 5; i++) {
        final l = PipAspectCalculator.clientLongSideFromOuter(
            outer: outer, insets: I);
        longs.add(l);
        outer = PipAspectCalculator.outerSizeForClient(
          client: PipAspectCalculator.normalizeClientSize(
              memoryLongSide: l, aspect: 9 / 16),
          insets: I,
        );
      }
      expect(longs, [408, 408, 408, 408, 408]);
    });
  });

  group('F1 首次进入与调用方兜底', () {
    test('默认记忆 (400,225)+insets(16,8)+A=16/9 → 客户区(384,216)、外框(400,224)', () {
      final l = PipAspectCalculator.clientLongSideFromOuter(
          outer: const Size(400, 225),
          insets: const FrameInsets(horizontal: 16, vertical: 8));
      expect(l, 384);
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: l, aspect: 16 / 9);
      expect(client, const Size(384, 216));
      final outer = PipAspectCalculator.outerSizeForClient(
          client: client,
          insets: const FrameInsets(horizontal: 16, vertical: 8));
      expect(outer, const Size(400, 224));
      expect(client.width / client.height, closeTo(16 / 9, 1e-12));
    });

    test('内边距 ≥ 长边 → 0（触发调用方 400.0 兜底）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      // 等高 → 取高为长边、减 vertical：5-8 = -3 < 0 → 0
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(5, 5), insets: I),
          0);
      // 横屏（宽为长边）但宽 < horizontal：12-16 = -4 < 0 → 0
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(12, 5), insets: I),
          0);
      // 等高但长边恰大于 vertical 的边界：10-8 = 2（说明等高走纵向而非横向）
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(10, 10), insets: I),
          2);
    });
  });

  // ============================================================
  // F1 收口复验：新 max(cw,ch) 语义（近方形方向问题消除）
  // ============================================================
  group('F1 收口复验 新 max(cw,ch) 语义', () {
    Size f(Size x, double a, FrameInsets insets) {
      final raw =
          PipAspectCalculator.clientLongSideFromOuter(outer: x, insets: insets);
      final longSide = raw > 0 ? raw : 400.0;
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: longSide, aspect: a);
      return PipAspectCalculator.outerSizeForClient(
          client: client, insets: insets);
    }

    // 旧口径（按外框维度取长边）——用于对照，证明 Low 问题真实存在
    Size oldF(Size x, double a, FrameInsets insets) {
      final longSide = x.width > x.height ? x.width : x.height;
      final client = PipAspectCalculator.normalizeClientSize(
          memoryLongSide: longSide, aspect: a);
      return PipAspectCalculator.outerSizeForClient(
          client: client, insets: insets);
    }

    test('近方形 A∈{0.98,0.99,1.0,1.02}：F(F(x))==F(x)（上轮失败处应通过）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const aspects = [0.98, 0.99, 1.0, 1.02, 0.975, 1.025, 0.995, 1.005];
      const starts = [
        Size(410, 405),
        Size(412, 408),
        Size(416, 412),
        Size(500, 800),
        Size(800, 500),
        Size(600, 590),
        Size(590, 600),
        Size(333, 330),
        Size(330, 333),
      ];
      for (final a in aspects) {
        for (final x in starts) {
          final f1 = f(x, a, I);
          final f2 = f(f1, a, I);
          expect(f2.width, closeTo(f1.width, 1e-9), reason: 'a=$a x=$x');
          expect(f2.height, closeTo(f1.height, 1e-9), reason: 'a=$a x=$x');
        }
      }
    });

    test('近方形多轮不漂移：5 轮 clientLongSideFromOuter 序列恒定', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      for (final a in [0.98, 0.99, 1.0, 1.02]) {
        for (final x0 in [
          const Size(520, 830),
          const Size(830, 520),
          const Size(410, 405),
        ]) {
          var x = x0;
          final longs = <double>[];
          for (var i = 0; i < 5; i++) {
            longs.add(
                PipAspectCalculator.clientLongSideFromOuter(outer: x, insets: I));
            x = f(x, a, I);
          }
          expect(
              longs.skip(1).every((l) => (l - longs.first).abs() < 1e-9), isTrue,
              reason: 'a=$a x0=$x0 序列应恒定：$longs');
        }
      }
    });

    test('对照：旧口径近方形确实非幂等（证明 Low 问题真实、已被修掉）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      var anyOldNonIdem = false;
      for (final a in [0.98, 0.99, 1.02]) {
        for (final x in [
          const Size(820, 800),
          const Size(410, 405),
          const Size(800, 820),
        ]) {
          final o1 = oldF(x, a, I);
          final o2 = oldF(o1, a, I);
          if ((o2.width - o1.width).abs() > 1e-6 ||
              (o2.height - o1.height).abs() > 1e-6) {
            anyOldNonIdem = true;
          }
          // 新口径对同一输入必须幂等
          final n1 = f(x, a, I);
          final n2 = f(n1, a, I);
          expect(n2.width, closeTo(n1.width, 1e-9), reason: 'a=$a x=$x');
          expect(n2.height, closeTo(n1.height, 1e-9), reason: 'a=$a x=$x');
        }
      }
      expect(anyOldNonIdem, isTrue, reason: '旧口径应存在近方形非幂等样例');
    });

    test('全 A 扫描：不存在任何 A 使 F 非幂等（含 0.05…20 边界）', () {
      const insetsList = [
        FrameInsets.zero,
        FrameInsets(horizontal: 16, vertical: 8),
        FrameInsets(horizontal: 20, vertical: 40),
        FrameInsets(horizontal: 40, vertical: 20),
      ];
      const aspects = [
        0.051, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98, 0.99, 1.0, 1.01, 1.02, 1.1,
        4 / 3, 16 / 9, 2.39, 5.0, 10.0, 19.9,
      ];
      final starts = <Size>[];
      for (double w = 5; w <= 2100; w += 149) {
        for (double h = 5; h <= 1300; h += 97) {
          starts.add(Size(w, h));
        }
      }
      for (final a in aspects) {
        for (final ins in insetsList) {
          for (final x in starts) {
            final f1 = f(x, a, ins);
            final f2 = f(f1, a, ins);
            expect(f2.width, closeTo(f1.width, 1e-9),
                reason: 'a=$a ins=$ins x=$x');
            expect(f2.height, closeTo(f1.height, 1e-9),
                reason: 'a=$a ins=$ins x=$x');
            final cw = f1.width - ins.horizontal;
            final ch = f1.height - ins.vertical;
            expect(cw / ch, closeTo(a, 1e-9), reason: 'a=$a ins=$ins x=$x');
          }
        }
      }
    });

    test('新语义护栏：恒等于 max(outer.w-hx, outer.h-hy)', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      const cases = [
        Size(410, 405), Size(412, 408), Size(416, 412), Size(416, 233),
        Size(233, 416), Size(10, 10), Size(12, 5), Size(5, 12), Size(100, 100),
        Size(800, 500), Size(500, 800), Size(97, 100), Size(100, 97),
      ];
      for (final o in cases) {
        final cw = o.width - I.horizontal;
        final ch = o.height - I.vertical;
        final expected = cw > ch ? cw : ch;
        final got =
            PipAspectCalculator.clientLongSideFromOuter(outer: o, insets: I);
        if (expected.isFinite && expected > 0) {
          expect(got, closeTo(expected, 1e-12), reason: '$o');
        } else {
          expect(got, 0, reason: '$o max<=0 应返回 0');
        }
      }
      // 任一维为负但 max 仍正 → 返回正的 max（不提前返回 0）
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(10, 100), insets: I),
          92); // cw=-6, ch=92
    });

    test('语义确已改变：Size(10,10)→2 是巧合；存在两者不同的输入', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      // Size(10,10)：旧 (高 10)−vertical 8 = 2；新 max(-6,2)=2 —— 巧合相等
      const oCoincide = Size(10, 10);
      final newVal =
          PipAspectCalculator.clientLongSideFromOuter(outer: oCoincide, insets: I);
      final oldVal = oCoincide.width > oCoincide.height
          ? oCoincide.width - I.horizontal
          : oCoincide.height - I.vertical;
      expect(newVal, 2);
      expect(oldVal, 2);
      // 反驳"只是换写法"：存在两者不同的输入
      const oDiff = Size(800.5, 800);
      final newVal2 =
          PipAspectCalculator.clientLongSideFromOuter(outer: oDiff, insets: I);
      final oldVal2 = oDiff.width > oDiff.height
          ? oDiff.width - I.horizontal
          : oDiff.height - I.vertical;
      expect(newVal2, closeTo(792, 1e-9)); // max(784.5, 792)
      expect(oldVal2, closeTo(784.5, 1e-9));
      expect(newVal2, isNot(closeTo(oldVal2, 1e-6)));
    });

    test('回归：横屏精确恒等 + 竖屏不动点/不变量（新语义下不变）', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      expect(
          PipAspectCalculator.clientLongSideFromOuter(
              outer: const Size(416, 233), insets: I),
          400);
      expect(
          PipAspectCalculator.normalizeClientSize(
              memoryLongSide: 400, aspect: 16 / 9),
          const Size(400, 225));
      expect(
          PipAspectCalculator.outerSizeForClient(
              client: const Size(400, 225), insets: I),
          const Size(416, 233));
      // 竖屏不变量 408 与不动点 (245.5,416)
      final l = PipAspectCalculator.clientLongSideFromOuter(
          outer: const Size(233, 416), insets: I);
      expect(l, 408);
      final back = PipAspectCalculator.outerSizeForClient(
        client: PipAspectCalculator.normalizeClientSize(
            memoryLongSide: l, aspect: 9 / 16),
        insets: I,
      );
      expect(back, const Size(245.5, 416));
    });

    test('回归：insets=zero 与旧消费逐位一致', () {
      const ins = FrameInsets.zero;
      for (final a in [16 / 9, 4 / 3, 2.39, 9 / 16, 0.5, 0.99]) {
        for (final x in [
          const Size(400, 225),
          const Size(225, 400),
          const Size(800, 450),
          const Size(1000, 1000),
        ]) {
          final nw = f(x, a, ins);
          final ow = oldF(x, a, ins);
          expect(nw.width, ow.width, reason: 'a=$a x=$x');
          expect(nw.height, ow.height, reason: 'a=$a x=$x');
        }
      }
    });

    test('回归：非法/退化输入 → 0', () {
      const I = FrameInsets(horizontal: 16, vertical: 8);
      for (final o in <Size>[
        const Size(-1, 50),
        const Size(50, -1),
        const Size(0, 50),
        Size(double.nan, 50),
        Size(double.infinity, 50),
        const Size(5, 5),
        const Size(12, 5),
      ]) {
        expect(
            PipAspectCalculator.clientLongSideFromOuter(outer: o, insets: I), 0,
            reason: '$o');
      }
    });
  });
}
