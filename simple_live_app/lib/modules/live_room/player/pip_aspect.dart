import 'dart:ui' show Size;

/// 外框相对客户区（Flutter 视图）的内边距，单位：逻辑像素。
///
/// horizontal = 外框宽 - 客户区宽；vertical = 外框高 - 客户区高。
/// 例如 Windows 隐藏标题栏态：左右边框各 8、合计 horizontal=16；
/// 垂直方向 Win11 仅底边 8（top=0）→ vertical=8；Win10 顶 1 底 8 → vertical=9。
class FrameInsets {
  const FrameInsets({this.horizontal = 0, this.vertical = 0});

  final double horizontal;
  final double vertical;

  static const FrameInsets zero = FrameInsets();

  bool get isZero => horizontal == 0 && vertical == 0;

  FrameInsets copyWith({double? horizontal, double? vertical}) => FrameInsets(
        horizontal: horizontal ?? this.horizontal,
        vertical: vertical ?? this.vertical,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameInsets &&
          horizontal == other.horizontal &&
          vertical == other.vertical;

  @override
  int get hashCode => horizontal.hashCode ^ vertical.hashCode;

  @override
  String toString() =>
      'FrameInsets(horizontal: $horizontal, vertical: $vertical)';
}

/// 小窗纵横比纯计算单元：无状态、无平台依赖、无 IO。
///
/// 全部算术收敛在这里，可在 Dart VM 单测稳定运行；禁止依赖任何平台通道
/// （如 `window_manager`），平台读写只留在 `WindowService` 薄层。
class PipAspectCalculator {
  PipAspectCalculator._();

  /// 兜底画面比例 16:9。
  static const double fallbackAspect = 16 / 9;

  // ---------- 比例来源 ----------

  /// 画面比例 A = width / height。
  /// width/height 任一为 null / 非有限 / <=0 → 返回 [fallbackAspect]。
  static double resolveVideoAspect({double? width, double? height}) {
    if (width == null || height == null) return fallbackAspect;
    if (!width.isFinite || !height.isFinite) return fallbackAspect;
    if (width <= 0 || height <= 0) return fallbackAspect;
    return width / height;
  }

  /// 「widget 实际显示比例」（决定窗口锁到多少），与 buildMediaPlayer 的 scaleMode 语义一致：
  ///   3 → 16/9；4 → 4/3；5 → aspectByUser（非法则回退 resolveVideoAspect）；
  ///   0 / 1 / 2 / 其它 → resolveVideoAspect。
  static double resolveDisplayAspect({
    required int scaleMode,
    double? aspectByUser,
    double? videoWidth,
    double? videoHeight,
  }) {
    switch (scaleMode) {
      case 3:
        return 16 / 9;
      case 4:
        return 4 / 3;
      case 5:
        if (isUsableAspect(aspectByUser)) return aspectByUser!;
        return resolveVideoAspect(
          width: videoWidth,
          height: videoHeight,
        );
      default:
        return resolveVideoAspect(
          width: videoWidth,
          height: videoHeight,
        );
    }
  }

  /// 护栏：a 非 null、有限、且 0.05 < a < 20。
  static bool isUsableAspect(double? a) {
    if (a == null) return false;
    if (!a.isFinite) return false;
    return a > 0.05 && a < 20;
  }

  // ---------- 尺寸换算（逻辑像素，纯算术） ----------

  /// 由「记忆长边」与比例推导客户区尺寸（长边恒 = memoryLongSide）：
  ///   aspect >= 1 → Size(memoryLongSide, memoryLongSide / aspect)
  ///   aspect <  1 → Size(memoryLongSide * aspect, memoryLongSide)
  static Size clientSizeForAspect({
    required double memoryLongSide,
    required double aspect,
  }) {
    if (aspect >= 1) {
      return Size(memoryLongSide, memoryLongSide / aspect);
    }
    return Size(memoryLongSide * aspect, memoryLongSide);
  }

  /// 客户区 → 外框：Size(client.width + insets.horizontal, client.height + insets.vertical)。
  static Size outerSizeForClient({
    required Size client,
    required FrameInsets insets,
  }) =>
      Size(
        client.width + insets.horizontal,
        client.height + insets.vertical,
      );

  /// 保持外框宽不变、按比例重算外框高（拖动结束精确对齐用）：
  ///   ch = (outerWidth - insets.horizontal) / aspect
  ///   → Size(outerWidth, ch + insets.vertical)
  static Size outerSizeForOuterWidth({
    required double outerWidth,
    required double aspect,
    required FrameInsets insets,
  }) {
    final ch = (outerWidth - insets.horizontal) / aspect;
    return Size(outerWidth, ch + insets.vertical);
  }

  /// WM_SIZING 需要的外框纵横比（按当前外框宽）：
  ///   R = outerWidth / ((outerWidth - hx) / aspect + hy)
  static double outerAspectRatioForOuterWidth({
    required double outerWidth,
    required double aspect,
    required FrameInsets insets,
  }) {
    final denom = (outerWidth - insets.horizontal) / aspect + insets.vertical;
    return outerWidth / denom;
  }

  /// 同上，按客户区宽度表达（等价，便于测试对照）：
  ///   R = (clientWidth + hx) / (clientWidth / aspect + hy)
  static double outerAspectRatioForClientWidth({
    required double clientWidth,
    required double aspect,
    required FrameInsets insets,
  }) {
    return (clientWidth + insets.horizontal) /
        (clientWidth / aspect + insets.vertical);
  }

  /// 测量反推：horizontal = outer.width - client.width（负值按 0）；
  ///           vertical   = outer.height - client.height（负值按 0）。
  static FrameInsets insetsFromSizes({
    required Size outer,
    required Size client,
  }) {
    final h = outer.width - client.width;
    final v = outer.height - client.height;
    return FrameInsets(
      horizontal: h < 0 ? 0 : h,
      vertical: v < 0 ? 0 : v,
    );
  }

  // ---------- 归一化与守卫判定 ----------

  /// 进入小窗时的客户区尺寸归一化：
  ///   1) 客户区比例精确 = aspect；2) 长边 >= minLongSide（不足按长边抬升）。
  /// 返回客户区尺寸（外框由 outerSizeForClient 再算）。
  static Size normalizeClientSize({
    required double memoryLongSide,
    required double aspect,
    double minLongSide = 320,
  }) {
    final longSide =
        memoryLongSide < minLongSide ? minLongSide : memoryLongSide;
    return clientSizeForAspect(
      memoryLongSide: longSide,
      aspect: aspect,
    );
  }

  /// 守卫判定：外框尺寸是否已使客户区比例落在 [aspect] 容差内。
  ///   cw = outer.width - hx；ch = outer.height - hy；
  ///   返回 cw > 0 && ch > 0 && (cw / aspect - ch).abs() <= epsPx
  /// 用途：识别「已合规」与「我们自己 setSize 造成的回声」，是死循环守卫的核心。
  static bool matchesAspect({
    required Size outer,
    required double aspect,
    required FrameInsets insets,
    double epsPx = 1.0,
  }) {
    final cw = outer.width - insets.horizontal;
    final ch = outer.height - insets.vertical;
    if (cw <= 0 || ch <= 0) return false;
    return (cw / aspect - ch).abs() <= epsPx;
  }

  // —— 本轮新增：Windows 隐藏态「非客户区环」理论值 与 合理性校验（纯函数，可单测）——
  // 采样源竞态的根因是「用 Dart 视图 metrics 当客户区」会滞后于平台侧样式变更；
  // 这里改用「理论值 + 合理性校验」做兜底与防御，与平台测量解耦。

  /// Windows「无标题栏」态下环形内边距的理论值（逻辑像素）。
  /// 插件硬编码 left/right/bottom = 8 物理像素、top = 0(Win11)/1(Win10)：
  ///   horizontal = 16 / dpr；vertical = (windows11 ? 8 : 9) / dpr。
  /// dpr <= 0 或非有限 → 视为 1.0。用于测量失败兜底与合理性参照。
  static FrameInsets expectedHiddenInsets(double dpr, {bool windows11 = true}) {
    final d = (!dpr.isFinite || dpr <= 0) ? 1.0 : dpr;
    return FrameInsets(
      horizontal: 16 / d,
      vertical: (windows11 ? 8 : 9) / d,
    );
  }

  /// 合理性校验：该内边距是否为「无标题栏」态的合理值。
  ///
  /// **阈值按物理像素判定**（阈值常量 32/20 本身是物理像素）——这是本轮修正的关键：
  /// 文档原字面写法是「对逻辑像素判 h<=32 && v<=20」，仅在 dpr=1 成立；隐藏态的 8px 是
  /// 插件在 WM_NCCALCSIZE 里减的物理像素、与 DPR 无关，而正常态标题栏高度随 DPI 放大，
  /// 于是 dpr=2 时正常态逻辑 v≈19.5<=20 会**漏判**、竞态残留。
  ///
  /// 正确做法：physicalH = insets.horizontal * dpr；physicalV = insets.vertical * dpr；
  ///   返回 physicalH<=32 && physicalV<=20 && 二者均 >=0 且有限。
  /// 验证：隐藏态物理 (16, 8~9) 恒通过；正常态物理 (16, 39*dpr) 恒被拒（dpr=1→39、dpr=2→78）。
  static bool isPlausibleHiddenInsets(FrameInsets insets, {double dpr = 1.0}) {
    final d = (!dpr.isFinite || dpr <= 0) ? 1.0 : dpr;
    final physicalH = insets.horizontal * d;
    final physicalV = insets.vertical * d;
    if (!physicalH.isFinite || !physicalV.isFinite) return false;
    if (physicalH < 0 || physicalV < 0) return false;
    return physicalH <= 32 && physicalV <= 20;
  }

  /// 把「外框尺寸」换算为「客户区长边」（用于消费记忆尺寸）。
  ///
  /// 记忆的 windowPipWidth/Height 来自 windowManager.getSize()，在 Windows 上走
  /// GetWindowRect → **外框**口径；而归一化需要的是客户区长边，两者差一圈内边距。
  /// 若直接把外框长边当客户区长边用、再 outerSizeForClient 加回一圈 insets，
  /// 每次进出小窗会累积 +insets → 窗口单调放大（F1 回归）。本函数把换算收口到
  /// 纯逻辑层，便于单测与定点验证。
  ///
  /// 长边取法：**先按客户区维度比较**，再减去对应方向内边距。
  /// 即 clientW = outer.width - insets.horizontal、clientH = outer.height - insets.vertical，
  /// 取 max(clientW, clientH) 作为客户区长边。
  ///
  /// 之所以不按外框 outer.width > outer.height 取方向，是因为 insets 非对称
  /// （Win11 隐藏态 h=16、v=8）：对近方形比例 A∈(0.98,1)，外框长边方向与
  /// 客户区长边方向可能相反 → 旧口径映射非幂等 → 反复进出小窗单调收缩（有界，
  /// 收敛到 320 下限，比例仍正确、无黑边，但尺寸会变小）。改按客户区维度比较后，
  /// 映射在记忆尺寸稳定点处满足 F(F(x))==F(x)，彻底收口。
  ///
  /// 注意：若某方向内边距 ≥ 对应外框边（clientW 或 clientH 为负），仍取二者之
  /// 较大者；仅当 max(clientW, clientH) 非有限或 <=0 时才返回 0，由调用方兜底。
  /// 外框尺寸非有限/非正 → 直接返回 0。
  static double clientLongSideFromOuter({
    required Size outer,
    required FrameInsets insets,
  }) {
    if (!outer.width.isFinite || !outer.height.isFinite) return 0;
    if (outer.width <= 0 || outer.height <= 0) return 0;
    final cw = outer.width - insets.horizontal;
    final ch = outer.height - insets.vertical;
    final result = cw > ch ? cw : ch; // max(clientW, clientH)
    if (!result.isFinite || result <= 0) return 0;
    return result;
  }
}
