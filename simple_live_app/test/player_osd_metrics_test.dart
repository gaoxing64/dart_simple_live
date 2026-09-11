import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/modules/live_room/player/player_osd_widgets.dart';

/// OSD 尺寸表与组件的回归测试。
///
/// 两部分：
/// 1. **宽屏（桌面 / 平板）保持既有观感** —— desktop 断点的尺寸逐值锁定，
///    避免以后改小屏时把 Windows 横屏的密度顺手改坏；
/// 2. **小屏（安卓竖屏）锁住底部表单形态** —— 竖屏时 OSD 被 16:9 视频区
///    限制在 ~220dp 高，布局必须整体换成通栏贴底 + 一行四个指标卡 +
///    隐藏次要行，这部分用真实手机尺寸（390×219）钉住。
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

  group('desktop 断点保持约定的 Windows 参数', () {
    final m = resolve(1920, 1080);

    test('断点与密度', () {
      expect(m.breakpoint, OsdBreakpoint.desktop);
      expect(m.presentment, OsdPresentment.overlay);
      expect(m.isSheet, isFalse);
      expect(m.dense, isFalse);
      expect(m.minimal, isFalse);
    });

    test('尺寸表逐值一致', () {
      expect(m.panelMaxWidth, 420);
      expect(m.contentPadding, 16);
      expect(m.contentGap, 14);
      expect(m.sectionGap, 16);
      expect(m.insetPaddingH, 10);
      expect(m.insetPaddingV, 8);
      expect(m.tileColumns, 2);
      expect(m.tileGap, 10);
      expect(m.tilePaddingH, 12);
      expect(m.tilePaddingV, 10);
      expect(m.rowSpacing, 9);
      expect(m.rowGap, 12);
      expect(m.titleSize, 15.5);
      expect(m.groupTitleSize, 12);
      expect(m.labelSize, 12.5);
      expect(m.valueSize, 13.5);
      expect(m.secondarySize, 12);
      expect(m.tileLabelSize, 11);
      expect(m.tileValueSize, 20);
      expect(m.chipFontSize, 11.5);
      expect(m.iconButtonSize, 28);
      expect(m.advancedVPadding, 9);
      expect(m.urlMaxLines, 6);
      expect(m.headerTopPadding, 14);
    });

    test('折叠头高度不低于 ListTile 的紧凑下限', () {
      expect(m.advancedTileMinHeight, 40);
      expect(resolve(700, 323).advancedTileMinHeight, 40);
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

    test('极窄屏指标卡退化为单列', () {
      expect(resolve(319, 800).tileColumns, 1);
      expect(resolve(320, 800).tileColumns, 2);
    });
  });

  group('小屏切底部表单形态', () {
    test('mobile 是 sheet，tablet / desktop 是 overlay', () {
      expect(resolve(390, 844).presentment, OsdPresentment.sheet);
      expect(resolve(390, 844).isSheet, isTrue);
      expect(resolve(600, 844).presentment, OsdPresentment.overlay);
      expect(resolve(1920, 1080).presentment, OsdPresentment.overlay);
    });

    test('表单通栏：宽度吃满可用区、不留外边距', () {
      final m = resolve(390, 219);
      expect(m.panelMaxWidth, 390);
      expect(m.horizontalMargin, 0);
      expect(m.verticalMargin, 0);
      // 浮层形态仍是固定宽度 + 12dp 边距
      expect(resolve(1920, 1080).panelMaxWidth, 420);
      expect(resolve(1920, 1080).horizontalMargin, 12);
    });

    test('表单只圆顶部两角（28），浮层四角 16', () {
      expect(resolve(390, 844).panelRadius, OsdShape.sheetTopRadius);
      expect(resolve(1920, 1080).panelRadius, OsdShape.largeRadius);
      expect(OsdShape.sheetTopRadius.topLeft.x, 28);
      expect(OsdShape.sheetTopRadius.bottomLeft.x, 0);
    });

    test('安卓竖屏（390×219）整表', () {
      final m = resolve(390, 219);
      expect(m.dense, isTrue);
      expect(m.minimal, isFalse);
      // 2×2 指标卡在 160dp 的滚动区里太贵，改一行四个
      expect(m.tileColumns, 4);
      // 次要行让位给真正要看的数
      expect(m.showSecondaryRows, isFalse);
      expect(m.rowGap, 8);
      expect(m.contentPadding, 10);
      expect(m.bodyMaxHeight, greaterThan(0));
    });

    test('极窄竖屏（<340）四格放不下，退回两列', () {
      expect(resolve(320, 180).tileColumns, 2);
      expect(resolve(340, 191).tileColumns, 4);
    });
  });

  group('高度断点（usableHeight = 高度 - 安全区 - 上下留白）', () {
    // 用 tablet 宽度：浮层形态上下各留 12dp，可用高度 = 高度 - 24。
    test('usableHeight 300 不 dense，299 开始 dense', () {
      expect(resolve(700, 324).dense, isFalse);
      expect(resolve(700, 323).dense, isTrue);
    });

    test('usableHeight 140 不 minimal，139 开始 minimal', () {
      expect(resolve(700, 164).minimal, isFalse);
      expect(resolve(700, 163).minimal, isTrue);
    });

    test('次要行只在非 dense 时出现', () {
      expect(resolve(700, 324).showSecondaryRows, isTrue);
      expect(resolve(700, 323).showSecondaryRows, isFalse);
    });

    test('minimal 时只保留标题栏，滚动区高度为 0', () {
      final m = resolve(700, 163);
      expect(m.minimal, isTrue);
      expect(m.bodyMaxHeight, 0);
    });

    test('dense 但非 minimal 时尺寸收缩、头部仍在', () {
      final m = resolve(700, 323);
      expect(m.dense, isTrue);
      expect(m.minimal, isFalse);
      // 收缩后的 dense 尺寸
      expect(m.contentPadding, 10);
      expect(m.insetPaddingV, 6);
      expect(m.titleSize, 13);
      expect(m.valueSize, 12.5);
      // 头部是唯一还占位的一行，内容区必须是正的
      expect(m.bodyMaxHeight, greaterThan(0));
    });

    test('面板高度不超过可用高度，滚动区不超过面板', () {
      for (final h in <double>[163, 200, 324, 600, 1080]) {
        final m = resolve(500, h);
        expect(m.panelMaxHeight, lessThanOrEqualTo(h));
        expect(m.bodyMaxHeight, lessThanOrEqualTo(m.panelMaxHeight));
      }
    });

    test('滚动区 = 面板 - 头部 - 内容间距（不溢出）', () {
      for (final h in <double>[200, 324, 600, 1080]) {
        final m = resolve(500, h);
        final header = m.headerTopPadding +
            (m.titleSize * 1.35 > m.iconButtonSize
                ? m.titleSize * 1.35
                : m.iconButtonSize);
        expect(m.bodyMaxHeight, lessThanOrEqualTo(
          m.panelMaxHeight - header - m.contentGap,
        ));
      }
    });
  });

  group('触控平台放大点击区域', () {
    test('mobile', () {
      expect(resolve(390, 844).iconButtonSize, 30);
      expect(resolve(390, 844, touch: true).iconButtonSize, 44);
    });

    test('tablet', () {
      expect(resolve(800, 844).iconButtonSize, 28);
      expect(resolve(800, 844, touch: true).iconButtonSize, 40);
    });

    test('desktop 不随触控变化', () {
      expect(resolve(1920, 1080, touch: true).iconButtonSize, 28);
    });

    test('dense 也不把触控目标压回去', () {
      // 小屏恰恰是最需要点得中的场景，不能因为矮就退回 30。
      expect(resolve(390, 219, touch: true).iconButtonSize, 40);
      expect(resolve(390, 219).iconButtonSize, 30);
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

  group('Material 3 主题下可渲染', () {
    Widget wrapWith(
      OsdMetrics metrics,
      double width,
      Widget child, {
      double height = 620,
      Brightness brightness = Brightness.dark,
    }) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff3498db),
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: OsdMetricsScope(
                metrics: metrics,
                child: OsdPanel(
                  maxWidth: width,
                  maxHeight: height,
                  radius: metrics.panelRadius,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
      return wrapWith(resolve(1920, 1080), 420, child,
          brightness: brightness);
    }

    Widget sample() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OsdHeader(
              title: 'Video Information',
              onClose: () {},
            ),
            OsdStatTileGrid(
              tiles: const [
                OsdStatTile(label: 'Frame Rate', value: '60', unit: 'FPS'),
                OsdStatTile(
                  label: 'Dropped',
                  value: '3',
                  tone: OsdChipTone.warn,
                ),
              ],
            ),
            OsdGroup(
              title: 'Display',
              chips: const [OsdChip(label: 'D3D11', tone: OsdChipTone.ok)],
              child: OsdRowList(
                rows: const [
                  OsdRow(label: 'Display Resolution', value: '1920 × 1080'),
                  OsdRow(label: 'Decoder', value: 'D3D11', tone: OsdChipTone.ok),
                ],
              ),
            ),
            OsdAdvanced(
              child: OsdUrlBlock(url: 'https://example.com/live.m3u8'),
            ),
          ],
        );

    testWidgets('指标卡 / 分组 / 折叠区都能渲染，折叠区默认收起', (tester) async {
      await tester.pumpWidget(wrap(sample()));

      expect(find.text('Video Information'), findsOneWidget);
      // 分组标题不再强制全大写
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('DISPLAY'), findsNothing);
      // 指标卡的数值与单位
      expect(find.text('Frame Rate'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('FPS'), findsOneWidget);
      // Chip 与行式数据
      expect(find.text('D3D11'), findsNWidgets(2));
      expect(find.text('1920 × 1080'), findsOneWidget);

      expect(find.text('Advanced'), findsOneWidget);
      // 折叠区收起时，里面的内容不参与布局
      expect(find.text('Stream URL'), findsNothing);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Stream URL'), findsOneWidget);
    });

    testWidgets('浅色主题下同样可渲染（不写死暗色）', (tester) async {
      await tester.pumpWidget(
        wrap(sample(), brightness: Brightness.light),
      );
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭按钮可点击', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OsdHeader(title: 'Video Information', onClose: () => closed++),
            ],
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('行式列表按行插入分隔线', (tester) async {
      await tester.pumpWidget(
        wrap(
          OsdRowList(
            rows: const [
              OsdRow(label: 'A', value: '1'),
              OsdRow(label: 'B', value: '2'),
              OsdRow(label: 'C', value: '3'),
            ],
          ),
        ),
      );
      // 3 行之间插 2 条分隔线
      expect(find.byType(Divider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('小屏布局', () {
    Widget wrapMobile(
      Widget child, {
      double width = 390,
      double height = 219,
      bool touch = true,
      // 复刻 overlay 里的真实组合：内容放进受 bodyMaxHeight 约束的滚动区。
      // 只有限定高度的那部分内容才需要它 —— 面板本身是 min-sized 的。
      bool scroll = false,
    }) {
      final metrics = OsdMetrics.resolve(
        constraints: BoxConstraints.tightFor(width: width, height: height),
        safePadding: EdgeInsets.zero,
        touch: touch,
      );
      final Widget body = scroll
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: metrics.bodyMaxHeight),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      metrics.contentPadding,
                      0,
                      metrics.contentPadding,
                      metrics.contentPadding,
                    ),
                    child: child,
                  ),
                ),
              ],
            )
          : child;
      return MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff3498db),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              height: height,
                child: OsdMetricsScope(
                metrics: metrics,
                child: OsdPanel(
                  maxWidth: width,
                  maxHeight: height,
                  radius: metrics.panelRadius,
                  child: body,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('一行四个指标卡能放下，不溢出', (tester) async {
      await tester.pumpWidget(
        wrapMobile(
          OsdStatTileGrid(
            tiles: const [
              OsdStatTile(label: 'Frame Rate', value: '60', unit: 'FPS'),
              OsdStatTile(label: 'Bitrate', value: '8.5', unit: 'Mbps'),
              OsdStatTile(label: 'Dropped', value: '12'),
              OsdStatTile(label: 'Buffer', value: '2.4', unit: 's'),
            ],
          ),
        ),
      );
      for (final t in ['Frame Rate', 'Bitrate', 'Dropped', 'Buffer']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('分组标题上的长 Chip 换行而不是溢出', (tester) async {
      await tester.pumpWidget(
        wrapMobile(
          OsdGroup(
            title: 'Stream',
            chips: const [
              OsdChip(label: 'FLV', tone: OsdChipTone.primary),
              OsdChip(label: '1080P60 原画'),
              OsdChip(label: '直播中', tone: OsdChipTone.ok),
            ],
            child: const OsdRowList(
              rows: [
                OsdRow(label: 'Platform', value: '哔哩哔哩'),
              ],
            ),
          ),
          width: 320,
          height: 200,
        ),
      );
      expect(find.text('1080P60 原画'), findsOneWidget);
      expect(find.text('直播中'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dense 下隐藏次要行，非 dense 保留', (tester) async {
      const rows = [
        OsdRow(label: 'Source Resolution', value: '1920 × 1080'),
        OsdRow(
          label: 'Pixel Format',
          value: 'yuv420p',
          secondary: true,
        ),
      ];

      await tester.pumpWidget(wrapMobile(const OsdRowList(rows: rows)));
      expect(find.text('Source Resolution'), findsOneWidget);
      expect(find.text('Pixel Format'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        wrapMobile(
          const OsdRowList(rows: rows),
          width: 390,
          height: 844,
        ),
      );
      expect(find.text('Pixel Format'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('极窄屏（320）整块内容不溢出', (tester) async {
      await tester.pumpWidget(
        wrapMobile(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OsdStatTileGrid(
                tiles: const [
                  OsdStatTile(label: 'Frame Rate', value: '60', unit: 'FPS'),
                  OsdStatTile(label: 'Buffer', value: '2.4', unit: 's'),
                ],
              ),
              OsdGroup(
                title: 'Stream',
                chips: const [
                  OsdChip(label: 'FLV', tone: OsdChipTone.primary),
                  OsdChip(label: '直播中', tone: OsdChipTone.ok),
                ],
                child: const OsdRowList(
                  rows: [
                    OsdRow(label: 'Platform', value: '哔哩哔哩'),
                    OsdRow(label: 'Viewers', value: '12.3万'),
                  ],
                ),
              ),
            ],
          ),
          width: 320,
          height: 180,
          scroll: true,
        ),
      );
      expect(find.text('Frame Rate'), findsOneWidget);
      expect(find.text('哔哩哔哩'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
