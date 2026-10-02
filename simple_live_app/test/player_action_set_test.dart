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
      expect(
        l.overflow.map((e) => e.id),
        isNot(contains(PlayerActionId.quality)),
      );
      expect(l.bar.map((e) => e.id), isNot(contains(PlayerActionId.line)));
    });

    // 「装得下」指的是没有动作被**宽度**挤进 ⋮：menuOnly 一档按 spec §7 恒在 ⋮ 里
    // （页级「更多」正是读 windowed 的 overflow 全集，见 spec §8），所以宽到 4000
    // 也仍然给 ⋮，只是再没有别的动作沉下去。
    test('装得下时没有动作是被宽度挤进 ⋮ 的', () {
      final l = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 4000,
      );
      expect(
        l.overflow.where((e) => e.tier != PlayerActionTier.menuOnly),
        isEmpty,
      );
      expect(l.hasOverflow, isTrue);
    });

    test('条带顺序与 _kAllActions 声明顺序一致（左簇在前、右簇在后）', () {
      final bar = resolvePlayerActions(
        host: PlayerHost.windowed,
        availableWidth: 1200,
      ).bar;
      final right = bar.where((e) => e.rightSide).map((e) => e.id).toList();
      expect(bar.last.id, right.last);
      expect(bar.first.rightSide, isFalse);
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
