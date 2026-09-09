import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_osd_widgets.dart';

/// OSD 尺寸表的回归测试。
///
/// 重点是「Windows 横屏观感与重构前一致」：desktop 断点的每个数值都必须保持
/// 改造前的取值；同时锁住 dense / minimal 的高度边界，避免以后微调阈值时
/// 悄悄把手机竖屏（OSD 落在 16:9 视频区里）的布局改坏。
void main() {
  OsdMetrics resolve(
    double width,
    double height, {
    EdgeInsets safePadding = EdgeInsets.zero,
    bool touch = false,
  }) {
    return OsdMetrics.resolve(
      constraints: BoxConstraints.tightFor(width: width, height: height),
      safePadding: safePadding,
      touch: touch,
    );
  }

  group('desktop 断点保持重构前的 Windows 参数', () {
    final m = resolve(1920, 1080);

    test('断点与密度', () {
      expect(m.breakpoint, OsdBreakpoint.desktop);
      expect(m.dense, isFalse);
      expect(m.minimal, isFalse);
      expect(m.inlineHeader, isFalse);
    });

    test('尺寸表逐值一致', () {
      expect(m.panelMaxWidth, 420);
      expect(m.contentPadding, 16);
      expect(m.contentGap, 14);
      expect(m.sectionGap, 18);
      expect(m.cardPaddingH, 12);
      expect(m.cardPaddingV, 10);
      expect(m.gridGap, 12);
      expect(m.rowSpacing, 10);
      expect(m.columns, 2);
      expect(m.titleSize, 15.5);
      expect(m.sectionTitleSize, 10.5);
      expect(m.labelSize, 10.5);
      expect(m.valueSize, 14);
      expect(m.secondarySize, 12);
      expect(m.segmentSize, 11.5);
      expect(m.iconButtonSize, 28);
      expect(m.segmentVPadding, 6);
      expect(m.advancedVPadding, 9);
      expect(m.urlMaxLines, 6);
      expect(m.headerTopPadding, 14);
      expect(m.tabsMarginTop, 12);
    });
  });

  group('宽度断点', () {
    test('899 是 tablet，900 起是 desktop', () {
      expect(resolve(899, 800).breakpoint, OsdBreakpoint.tablet);
      expect(resolve(900, 800).breakpoint, OsdBreakpoint.desktop);
    });

    test('599 是 mobile，600 起是 tablet', () {
      expect(resolve(599, 800).breakpoint, OsdBreakpoint.mobile);
      expect(resolve(600, 800).breakpoint, OsdBreakpoint.tablet);
    });

    test('极窄屏退化为单列', () {
      expect(resolve(319, 800).columns, 1);
      expect(resolve(320, 800).columns, 2);
    });
  });

  group('高度断点（usableHeight = 高度 - 安全区 - 上下留白 24）', () {
    test('usableHeight 300 不 dense，299 开始 dense', () {
      expect(resolve(400, 324).dense, isFalse);
      expect(resolve(400, 323).dense, isTrue);
    });

    test('usableHeight 140 不 minimal，139 开始 minimal', () {
      expect(resolve(400, 164).minimal, isFalse);
      expect(resolve(400, 163).minimal, isTrue);
    });

    test('minimal 时只保留标题栏，滚动区高度为 0', () {
      final m = resolve(400, 163);
      expect(m.minimal, isTrue);
      expect(m.inlineHeader, isFalse);
      expect(m.bodyMaxHeight, 0);
    });

    test('dense 但非 minimal 时关闭按钮并入页签行', () {
      final m = resolve(400, 323);
      expect(m.dense, isTrue);
      expect(m.minimal, isFalse);
      expect(m.inlineHeader, isTrue);
    });

    test('面板高度不超过可用高度，滚动区不超过面板', () {
      for (final h in <double>[163, 200, 324, 600, 1080]) {
        final m = resolve(500, h);
        expect(m.panelMaxHeight, lessThanOrEqualTo(h));
        expect(m.bodyMaxHeight, lessThanOrEqualTo(m.panelMaxHeight));
      }
    });
  });

  group('触控平台放大点击区域', () {
    test('mobile', () {
      expect(resolve(390, 844).iconButtonSize, 30);
      expect(resolve(390, 844, touch: true).iconButtonSize, 40);
    });

    test('tablet', () {
      expect(resolve(800, 844).iconButtonSize, 28);
      expect(resolve(800, 844, touch: true).iconButtonSize, 38);
    });

    test('desktop 不随触控变化', () {
      expect(resolve(1920, 1080, touch: true).iconButtonSize, 28);
    });
  });

  group('安全区参与可用高度计算', () {
    test('全屏刘海屏会扣掉上下安全区', () {
      final m = resolve(
        390,
        844,
        safePadding: const EdgeInsets.only(top: 44, bottom: 34),
      );
      expect(m.dense, isFalse);
      expect(m.panelMaxHeight, lessThanOrEqualTo(844 - 44 - 34 - 24));
    });
  });
}
