import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';

Set<PlayerActionId> _all(PlayerActionLayout l) => l.all.map((e) => e.id).toSet();

/// 平铺件（顶簇 + 底栏）——「沉进 ⋮ 之前有没有位置」问的是这个并集。
Set<PlayerActionId> _flat(PlayerActionLayout l) => {
  ...l.topBar.map((e) => e.id),
  ...l.bar.map((e) => e.id),
};

void main() {
  group('跨宿主一致性', () {
    // 作者 2026-10-04：换台只在全屏出现（它点开的是右侧面板，而右侧面板仅全屏使用）。
    // 所以两宿主的全集**只**差这一颗——其余动作仍必须一模一样，
    // 否则「按宿主分」又成了各排一份的挡箭牌。
    test('桌面窗口化与全屏的动作全集只差「换台」，其余相同', () {
      final w = _all(
        resolvePlayerActions(host: PlayerHost.windowed, availableWidth: 1200),
      );
      final f = _all(
        resolvePlayerActions(host: PlayerHost.fullscreen, availableWidth: 1200),
      );
      expect(f.difference(w), {PlayerActionId.pick});
      expect(w.difference(f), isEmpty, reason: '窗口化不该有全屏没有的动作');
    });

    test('换台只在全屏与格子在场，窗口化／小窗没有这颗', () {
      expect(
        _all(
          resolvePlayerActions(
            host: PlayerHost.windowed,
            availableWidth: 4000,
          ),
        ),
        isNot(contains(PlayerActionId.pick)),
      );
      expect(
        _all(
          resolvePlayerActions(
            host: PlayerHost.smallWindow,
            availableWidth: 4000,
          ),
        ),
        isNot(contains(PlayerActionId.pick)),
      );
      for (final host in [PlayerHost.fullscreen, PlayerHost.tile]) {
        expect(
          _all(resolvePlayerActions(host: host, availableWidth: 4000)),
          contains(PlayerActionId.pick),
          reason: '$host 少了换台',
        );
      }
    });

    // 作者 2026-10-03：截图／换台／小窗／`⋮` 归右上角那一簇，与改造前一致；
    // 窗口化以前没有顶栏，现在也有了。两宿主的顶簇在**共有的件**上顺序一致，
    // 全屏多出的就是那颗换台。
    test('右上那一簇：窗口化＝截图／小窗，全屏再多一颗换台', () {
      expect(
        resolvePlayerActions(
          host: PlayerHost.windowed,
          availableWidth: 1200,
        ).topBar.map((e) => e.id).toList(),
        [PlayerActionId.screenshot, PlayerActionId.smallWindow],
      );
      expect(
        resolvePlayerActions(
          host: PlayerHost.fullscreen,
          availableWidth: 1200,
        ).topBar.map((e) => e.id).toList(),
        [
          PlayerActionId.screenshot,
          PlayerActionId.pick,
          PlayerActionId.smallWindow,
        ],
      );
    });

    test('没有顶栏的宿主（小窗／格子）顶簇恒空，件留在底栏／胶囊', () {
      for (final host in [PlayerHost.smallWindow, PlayerHost.tile]) {
        final l = resolvePlayerActions(host: host, availableWidth: 360);
        expect(l.topBar, isEmpty, reason: '$host 不该有右上簇');
      }
      // 小窗里那颗「退出小窗」必须在底栏，不能因带 placeInTopBar 就两头都不在。
      final pip = resolvePlayerActions(
        host: PlayerHost.smallWindow,
        availableWidth: 360,
      );
      expect(pip.bar.map((e) => e.id), contains(PlayerActionId.smallWindow));
    });

    test('截图／画面尺寸／小窗在窗口化与全屏都必须在场', () {
      for (final host in [PlayerHost.windowed, PlayerHost.fullscreen]) {
        final ids = _all(
          resolvePlayerActions(host: host, availableWidth: 1200),
        );
        expect(
          ids,
          containsAll(<PlayerActionId>{
            PlayerActionId.screenshot,
            PlayerActionId.scale,
            PlayerActionId.smallWindow,
          }),
          reason: '$host 少动作',
        );
      }
    });

    test('窄窗口不会把动作吃掉，只会沉进 ⋮', () {
      final wide = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
      );
      final narrow = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 240,
      );
      expect(_all(narrow), _all(wide));
      expect(narrow.bar.length, lessThan(wide.bar.length));
    });

    test('音量任何宽度、全屏的换台任何宽度都保持平铺，不沉进 ⋮', () {
      // 音量是悬停锚定件，沉进 ⋮ 就没人画它了；换台同理——它落在右上那一簇，
      // 一旦因宽度沉下去，右上角就没有换台入口了（作者明确要求它待在右上）。
      for (final host in PlayerHost.values) {
        for (final width in [0.0, 120.0, 240.0, 320.0, 400.0, 1200.0]) {
          final l = resolvePlayerActions(host: host, availableWidth: width);
          expect(
            _flat(l),
            contains(PlayerActionId.volume),
            reason: '$host 宽 $width 时音量被收进了 ⋮',
          );
          if (host == PlayerHost.fullscreen) {
            expect(
              _flat(l),
              contains(PlayerActionId.pick),
              reason: '$host 宽 $width 时换台被收进了 ⋮',
            );
            expect(
              l.overflow.map((e) => e.id),
              isNot(contains(PlayerActionId.pick)),
              reason: '$host 宽 $width 时 pick 落进了抽屉',
            );
          }
        }
      }
    });
  });

  group('格子', () {
    test('格子永不给窗口级动作', () {
      final ids = _all(
        resolvePlayerActions(host: PlayerHost.tile, availableWidth: 240),
      );
      expect(ids.contains(PlayerActionId.smallWindow), isFalse);
      expect(ids.contains(PlayerActionId.fullscreenToggle), isTrue);
      // 返回键／标题／锁定是容器结构，不建模为动作（spec §8 的建模口径修订）
      expect(PlayerActionId.values.map((e) => e.name), isNot(contains('exit')));
      expect(PlayerActionId.values.map((e) => e.name), isNot(contains('lock')));
    });

    test('关闭这一路只在可关时出现', () {
      expect(
        _all(
          resolvePlayerActions(
            host: PlayerHost.tile,
            availableWidth: 400,
            canCloseTile: true,
          ),
        ).contains(PlayerActionId.closeTile),
        isTrue,
      );
      expect(
        _all(resolvePlayerActions(host: PlayerHost.tile, availableWidth: 400))
            .contains(PlayerActionId.closeTile),
        isFalse,
      );
    });

    test('格子平铺 core 五件（含 ▾ 换台），低频动作全在 ⋮ 里', () {
      final l = resolvePlayerActions(
        host: PlayerHost.tile,
        availableWidth: 240,
        canCloseTile: true,
      );
      expect(l.bar.map((e) => e.id).toSet(), {
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
        PlayerActionId.pick,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.closeTile,
      });
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.refresh));
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.quality));
    });
  });

  group('小窗（PiP）', () {
    test('小窗态平铺恰好四件，其余进 ⋮', () {
      final l = resolvePlayerActions(
        host: PlayerHost.smallWindow,
        availableWidth: 360,
      );
      expect(l.bar.map((e) => e.id).toSet(), {
        PlayerActionId.smallWindow,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
      });
      expect(l.hasOverflow, isTrue);
      expect(l.overflow.map((e) => e.id), contains(PlayerActionId.screenshot));
    });
  });

  group('常驻兜底与收纳', () {
    test('core 动作任何宽度下都留在条带里', () {
      const core = {
        PlayerActionId.danmakuToggle,
        PlayerActionId.volume,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.refresh,
      };
      for (final width in [0.0, 120.0, 400.0, 1200.0, 4000.0]) {
        final ids = resolvePlayerActions(
          host: PlayerHost.windowed,
          availableWidth: width,
        ).bar.map((e) => e.id).toSet();
        expect(ids, containsAll(core), reason: '宽 $width 时常驻件被收进了 ⋮');
      }
    });

    test('竖屏主播时清晰度/线路降到 ⋮ 而不是消失', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
        isVertical: true,
      );
      for (final id in [PlayerActionId.quality, PlayerActionId.line]) {
        expect(l.bar.map((e) => e.id), isNot(contains(id)));
        expect(l.overflow.map((e) => e.id), contains(id));
      }
    });

    test('没有清晰度/线路数据时该动作不提供', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
        hasQuality: false,
        hasLine: false,
      );
      // 两个 id 都得同时从 bar 和 overflow 里消失：只查一侧会放过「把 quality 留在
      // bar、只把 line 挪走」这类镜像 bug，所以取全集 _all 来断言。
      final ids = _all(l);
      expect(ids, isNot(contains(PlayerActionId.quality)));
      expect(ids, isNot(contains(PlayerActionId.line)));
    });

    // 「装得下」指的是没有动作被**宽度**挤进 ⋮：windowed 下恒进 ⋮ 的只有 menuOnly
    // 一档（spec §8 末行：页级「更多」＝这一列的 overflow 全集），宽到 4000 再没有
    // 别的动作沉下去，⋮ 仍在。这里不读 PlayerAction.tier——tier 不是清单字段。
    test('装得下时没有动作是被宽度挤进 ⋮ 的', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 4000,
      );
      expect(l.overflow.map((e) => e.id).toSet(), {
        PlayerActionId.scale,
        PlayerActionId.share,
        PlayerActionId.copyUrl,
        PlayerActionId.openApp,
        PlayerActionId.debugInfo,
        PlayerActionId.autoExit,
      });
      expect(l.hasOverflow, isTrue);
    });

    test('条带顺序与 _kAllActions 声明顺序一致（左簇在前、右簇在后）', () {
      final bar = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
      ).bar;
      // 真正要锁的性质是「最后一个左簇项的索引 < 第一个右簇项的索引」。
      // （旧断言 bar.last.id == right.last 只证明最右那颗属于右簇，整条簇被反接
      // 也照样通过，压根测不到标题说的「左簇在前、右簇在后」。）
      final lastLeftIndex = bar.lastIndexWhere((e) => !e.rightSide);
      final firstRightIndex = bar.indexWhere((e) => e.rightSide);
      expect(
        lastLeftIndex,
        greaterThanOrEqualTo(0),
        reason: '左簇为空，该断言失去意义',
      );
      expect(
        firstRightIndex,
        greaterThanOrEqualTo(0),
        reason: '右簇为空，该断言失去意义',
      );
      expect(lastLeftIndex, lessThan(firstRightIndex));
    });
  });

  group('页级「更多」', () {
    // `live_room_page.showMore` 的桌面分支把 `layout.all` 整份递给 `showActionMenu`，
    // 抽屉真正列出的行由 `actionableMenuItems` 这一处判定。钉四条：
    // ① 内容＝全集（页级菜单是直达入口，不受条带宽度与顶簇/底栏拆分的影响）；
    // ② 每个动作只一行——页级菜单原先那颗「小窗播放」包着 `Visibility(Platform.isAndroid)`
    //    被隐藏、视频区条带另给一份，同源后两份都要来自同一个清单，必须只剩一行；
    // ③ 抽屉里没有死行（`volume` 是悬停锚定件、`closeTile` 要格子的 index，
    //    两者在 `invokePlayerAction` 里是 no-op）；
    // ④ 没有换台——它按宿主只在全屏／格子在场，页级这颗挂在窗口化的 AppBar 上，
    //    清单取的正是 windowed 那一份（改造前的页级菜单本来也没有这条）。
    test('给足宽度时抽屉列出全集，且每个动作只一行', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 4000,
      );
      final rows = actionableMenuItems(l.all);
      expect(rows.map((e) => e.id).toList(), [
        PlayerActionId.refresh,
        PlayerActionId.danmakuToggle,
        PlayerActionId.danmakuSettings,
        PlayerActionId.screenshot,
        PlayerActionId.quality,
        PlayerActionId.line,
        PlayerActionId.scale,
        PlayerActionId.smallWindow,
        PlayerActionId.fullscreenToggle,
        PlayerActionId.debugInfo,
        PlayerActionId.autoExit,
        PlayerActionId.share,
        PlayerActionId.copyUrl,
        PlayerActionId.openApp,
      ]);
      expect(
        rows.map((e) => e.id),
        isNot(contains(PlayerActionId.pick)),
        reason: '页级「更多」是窗口化的入口，换台只在全屏',
      );
      expect(
        rows.where((e) => e.id == PlayerActionId.smallWindow).length,
        1,
        reason: '桌面「小窗播放」只能有一个入口',
      );
      expect(
        rows.map((e) => e.id),
        isNot(contains(PlayerActionId.volume)),
        reason: '音量是悬停锚定件，进抽屉就是点了没反应的死行',
      );
      // 原页级菜单的措辞一字不改地保留：合流只换清单来源，不换文案。
      expect(rows.map((e) => e.title).toList(), [
        "刷新",
        "弹幕",
        "弹幕设置",
        "截图",
        "切换清晰度",
        "切换线路",
        "画面尺寸",
        "小窗播放",
        "全屏",
        "播放信息",
        "定时关闭",
        "分享直播间",
        "复制链接",
        "APP 中打开",
      ]);
    });
  });

  // 容器判据：作者 2026-10-04 定「右侧面板仅在全屏时使用」——窗口化那条右侧本来就站着
  // 聊天／SC／关注那一栏，再来一块 400 宽的面板会把它整个盖掉；改造前窗口化的清晰度／
  // 线路／弹幕设置落的都是底部抽屉。小窗与格子留右侧面板（小窗复用全屏那一套；格子的
  // 底部抽屉会横切另外几路的画面）。**触屏一律底部抽屉**：手机竖屏只有 ~360 宽。
  group('容器判据', () {
    test('桌面：只有窗口化用底部抽屉，全屏／小窗／格子用右侧面板', () {
      expect(
        usesRightPanelSurface(PlayerHost.windowed, isDesktop: true),
        isFalse,
      );
      for (final host in [
        PlayerHost.fullscreen,
        PlayerHost.smallWindow,
        PlayerHost.tile,
      ]) {
        expect(
          usesRightPanelSurface(host, isDesktop: true),
          isTrue,
          reason: '$host 该用右侧面板',
        );
      }
    });

    test('触屏：四宿主全落底部抽屉（360 宽放不下 320~400 的面板）', () {
      for (final host in PlayerHost.values) {
        expect(
          usesRightPanelSurface(host, isDesktop: false),
          isFalse,
          reason: '$host 在触屏上不该开右侧面板',
        );
      }
    });
  });

  // 触屏格子的「静音这一路」：音量颗的点击在触屏上是「弹滑条」（没 hover），
  // 静音需要另一个入口，就收进 ⋮ 这一行。桌面不传 isTouch，清单必须一个字节都没变。
  group('触屏静音入口', () {
    test('muteTile 只在 tile + 触屏在场，且恒进 ⋮ 不平铺', () {
      final touch = resolvePlayerActions(
        host: PlayerHost.tile,
        availableWidth: 240,
        canCloseTile: true,
        isTouch: true,
      );
      expect(touch.overflow.map((e) => e.id), contains(PlayerActionId.muteTile));
      expect(
        touch.bar.map((e) => e.id),
        isNot(contains(PlayerActionId.muteTile)),
        reason: '胶囊只有 224px 可用，这颗只能待在 ⋮ 里',
      );
      // 抽屉里必须真画得出这一行（actionableMenuItems 别把它误滤掉）
      expect(
        actionableMenuItems(touch.overflow).map((e) => e.id),
        contains(PlayerActionId.muteTile),
      );
    });

    test('isTouch 默认 false：四宿主的产物与触屏适配前逐字相同', () {
      for (final host in PlayerHost.values) {
        final desktop = resolvePlayerActions(
          host: host,
          availableWidth: 400,
          canCloseTile: true,
        );
        final explicit = resolvePlayerActions(
          host: host,
          availableWidth: 400,
          canCloseTile: true,
          isTouch: false,
        );
        expect(
          [...desktop.topBar, ...desktop.bar, ...desktop.overflow].map(
            (e) => e.id,
          ),
          [...explicit.topBar, ...explicit.bar, ...explicit.overflow].map(
            (e) => e.id,
          ),
        );
        expect(
          _all(desktop),
          isNot(contains(PlayerActionId.muteTile)),
          reason: '$host 在桌面上不该冒出这颗',
        );
      }
      // 非格子的触屏宿主也不给：只有 tile 的音量颗会因触屏改语义
      expect(
        _all(
          resolvePlayerActions(
            host: PlayerHost.windowed,
            availableWidth: 400,
            isTouch: true,
          ),
        ),
        isNot(contains(PlayerActionId.muteTile)),
      );
    });
  });

  test('动作标题与 id 一一对应，没有重复 id', () {
    final l = resolvePlayerActions(
      host: PlayerHost.windowed,
      availableWidth: 4000,
    );
    final ids = [...l.bar, ...l.overflow].map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final a in [...l.bar, ...l.overflow]) {
      expect(a.title, isNotEmpty);
    }
  });
}
