import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';

Set<PlayerActionId> _all(PlayerActionLayout l) => {
      ...l.bar.map((e) => e.id),
      ...l.overflow.map((e) => e.id),
    };

void main() {
  group('跨宿主一致性', () {
    test('桌面窗口化与全屏的动作全集相同（顶栏/底栏归 renderer 管）', () {
      final w = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
      );
      final f = resolvePlayerActions(
        host: PlayerHost.fullscreen,
        availableWidth: 1200,
      );
      expect(_all(w), _all(f));
    });

    test('截图／选台／画面尺寸／小窗在窗口化与全屏都必须在场', () {
      for (final host in [PlayerHost.windowed, PlayerHost.fullscreen]) {
        final ids = _all(
          resolvePlayerActions(host: host, availableWidth: 1200),
        );
        expect(
          ids,
          containsAll(<PlayerActionId>{
            PlayerActionId.screenshot,
            PlayerActionId.pick,
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
        availableWidth: 320,
      );
      expect(_all(narrow), _all(wide));
      expect(narrow.bar.length, lessThan(wide.bar.length));
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

    test('格子平铺 core 五件（含 ▾ 选台），低频动作全在 ⋮ 里', () {
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
