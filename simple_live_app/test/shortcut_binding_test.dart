// 快捷键**数据模型**的回归。
//
// 这里钉的是纯函数：默认表、编解码往返、匹配与冲突。之所以能全用真对象测，
// 是因为 `shortcut_binding.dart` 刻意不碰 controller / 播放器 / 本地存储。
// 「按下键之后真的做了什么」归 `player_shortcuts_test.dart` 与人工验证。
import 'dart:convert';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 用「无修饰键」调 matchShortcut 的简写，测试里绝大多数用例都不带修饰键。
PlayerShortcut? _match(
  Map<PlayerShortcut, ShortcutBinding?> effective,
  LogicalKeyboardKey key,
) => matchShortcut(effective, key, shift: false, ctrl: false, alt: false, meta: false);

void main() {
  final effective = resolveEffectiveShortcuts({});

  group('默认表与动作全集一致', () {
    test('每个动作都有默认键位，且没有多余项', () {
      expect(
        kDefaultShortcuts.keys.toSet(),
        kShortcutOrder.toSet(),
        reason: '新增动作忘了给默认值，或删了动作没清默认值',
      );
      expect(kShortcutOrder.toSet().length, kShortcutOrder.length,
          reason: '展示顺序里有重复动作');
    });

    test('默认键位互不冲突（两两不同）', () {
      final bindings = kDefaultShortcuts.values.toList();
      final distinct = bindings.toSet();
      expect(distinct.length, bindings.length, reason: '两个默认动作撞在同一个键上');
    });

    test('默认键位都不在被禁的键上', () {
      for (final entry in kDefaultShortcuts.entries) {
        expect(
          isForbiddenShortcutKey(entry.value.key),
          isFalse,
          reason: '${entry.key.name} 的默认键不可绑定',
        );
      }
    });
  });

  group('生效表：三种状态', () {
    test('没有覆盖项时全部回落默认', () {
      expect(_match(effective, LogicalKeyboardKey.space),
          PlayerShortcut.playPause);
      expect(_match(effective, LogicalKeyboardKey.keyF),
          PlayerShortcut.fullscreen);
      expect(_match(effective, LogicalKeyboardKey.escape),
          PlayerShortcut.exitPlayer);
    });

    test('覆盖项存在但为 null＝该动作被禁用，按它的默认键不再命中', () {
      final withUnset = resolveEffectiveShortcuts({
        PlayerShortcut.playPause: null,
      });
      expect(_match(withUnset, LogicalKeyboardKey.space), isNull);
      // 别的动作不受影响
      expect(_match(withUnset, LogicalKeyboardKey.keyF),
          PlayerShortcut.fullscreen);
    });

    test('覆盖项存在且有值＝改键生效，旧默认键释放', () {
      final rebound = resolveEffectiveShortcuts({
        PlayerShortcut.playPause: const ShortcutBinding(LogicalKeyboardKey.keyJ),
      });
      expect(_match(rebound, LogicalKeyboardKey.keyJ), PlayerShortcut.playPause);
      expect(_match(rebound, LogicalKeyboardKey.space), isNull,
          reason: '改键后旧键必须彻底失效，否则用户会以为有两个键都能暂停');
    });

    test('未知动作名的覆盖项不会污染生效表', () {
      // decodeShortcuts 已经挡掉未知名字，这里再确认生效表长度恒等于动作数。
      final resolved = resolveEffectiveShortcuts({});
      expect(resolved.length, kShortcutOrder.length);
    });
  });

  group('修饰键匹配与输入法旁路', () {
    // 中文输入法激活时，字母键被输入法截获去做拼音合成，Flutter 收不到事件，
    // 裸字母快捷键全部失效；`Ctrl + 字母` 输入法会放行，所以放开这一条旁路
    // （参考项目 PiliPlus 的匹配根本不看 Ctrl）。
    // 但旁路只给字母：Ctrl+Space 是 Windows 输入法切换、Ctrl+Enter 是输入法
    // 中英标点切换，抢了就废掉系统热键。
    test('字母绑定可被 Ctrl+字母 旁路命中（中文输入法下的通路）', () {
      expect(
        matchShortcut(effective, LogicalKeyboardKey.keyS,
            shift: false, ctrl: true, alt: false, meta: false),
        PlayerShortcut.screenshot,
        reason: '中文输入法下 Ctrl+S 要能触发截图',
      );
      expect(
        matchShortcut(effective, LogicalKeyboardKey.keyF,
            shift: false, ctrl: true, alt: false, meta: false),
        PlayerShortcut.fullscreen,
      );
    });

    test('空格/回车/方向键/数字/Esc 一律不旁路', () {
      // 这些键输入法不截，本就能正常触发；旁路它们只会废掉系统热键。
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.escape,
      ]) {
        expect(
          matchShortcut(effective, key,
              shift: false, ctrl: true, alt: false, meta: false),
          isNull,
          reason: 'Ctrl+$key 不该被应用抢走',
        );
      }
    });

    test('旁路只放过 Ctrl：Shift/Alt/Meta 仍必须严格相等', () {
      for (final key in [
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyF,
      ]) {
        expect(
          matchShortcut(effective, key,
              shift: true, ctrl: false, alt: false, meta: false),
          isNull,
          reason: 'Shift+$key 不该命中裸 $key 的绑定',
        );
        expect(
          matchShortcut(effective, key,
              shift: false, ctrl: false, alt: true, meta: false),
          isNull,
        );
        expect(
          matchShortcut(effective, key,
              shift: false, ctrl: false, alt: false, meta: true),
          isNull,
        );
      }
    });

    test('显式绑定了 Ctrl 的组合：裸主键不命中，且多按一个 Shift 不命中', () {
      final rebound = resolveEffectiveShortcuts({
        PlayerShortcut.screenshot: const ShortcutBinding(LogicalKeyboardKey.keyS,
            ctrl: true),
      });
      expect(_match(rebound, LogicalKeyboardKey.keyS), isNull);
      expect(
        matchShortcut(rebound, LogicalKeyboardKey.keyS,
            shift: false, ctrl: true, alt: false, meta: false),
        PlayerShortcut.screenshot,
      );
      // 多按一个 Shift 就不算同一个组合
      expect(
        matchShortcut(rebound, LogicalKeyboardKey.keyS,
            shift: true, ctrl: true, alt: false, meta: false),
        isNull,
      );
    });

    test('严格命中优先于旁路：显式绑了 Ctrl+F 的动作不被裸 F 抢走', () {
      // 截图=裸 F、某动作=Ctrl+F 时，按下 Ctrl+F 必须走那个显式绑定，
      // 而不是被裸 F 的旁路截走。两遍匹配（先严格后旁路）保证这一点。
      final rebound = resolveEffectiveShortcuts({
        PlayerShortcut.fullscreen: const ShortcutBinding(LogicalKeyboardKey.keyF),
        PlayerShortcut.screenshot: const ShortcutBinding(LogicalKeyboardKey.keyF,
            ctrl: true),
      });
      expect(
        matchShortcut(rebound, LogicalKeyboardKey.keyF,
            shift: false, ctrl: true, alt: false, meta: false),
        PlayerShortcut.screenshot,
      );
      expect(
        matchShortcut(rebound, LogicalKeyboardKey.keyF,
            shift: false, ctrl: false, alt: false, meta: false),
        PlayerShortcut.fullscreen,
      );
    });

    test('纯修饰键作为主键按下一律不命中', () {
      for (final key in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.metaLeft,
      ]) {
        expect(_match(effective, key), isNull, reason: '$key 不该触发动作');
        expect(isModifierKey(key), isTrue);
      }
    });
  });

  group('字母键判定（旁路的适用边界）', () {
    test('26 个字母全在旁路范围内', () {
      for (var i = 0; i < 26; i++) {
        final key = LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i);
        expect(isLetterShortcutKey(key), isTrue, reason: '$key 应判为字母');
      }
    });

    test('非字母一律不在旁路范围内', () {
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.comma,
        LogicalKeyboardKey.numpad1,
      ]) {
        expect(isLetterShortcutKey(key), isFalse, reason: '$key 不该被旁路');
      }
    });
  });

  group('被禁的键', () {
    test('Tab 不可绑定（会毁掉界面自己的焦点遍历）', () {
      expect(isForbiddenShortcutKey(LogicalKeyboardKey.tab), isTrue);
    });

    test('字母与方向键可以绑定', () {
      for (final key in [
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        expect(isForbiddenShortcutKey(key), isFalse, reason: '$key 该可绑定');
      }
    });
  });

  group('编解码往返', () {
    test('空覆盖表编成空串，再解回空表', () {
      final encoded = encodeShortcuts({});
      expect(encoded, '');
      expect(decodeShortcuts(encoded), isEmpty);
    });

    test('自定义 / 禁用 / 默认三种状态各自往返无损', () {
      final overrides = <PlayerShortcut, ShortcutBinding?>{
        PlayerShortcut.playPause: const ShortcutBinding(LogicalKeyboardKey.keyJ),
        PlayerShortcut.screenshot: const ShortcutBinding(LogicalKeyboardKey.keyS,
            shift: true, ctrl: true, alt: true, meta: true),
        PlayerShortcut.mute: null, // 不设置
        PlayerShortcut.fullscreen: const ShortcutBinding(
            LogicalKeyboardKey.f5), // 非 ASCII 标签的键
      };
      final decoded = decodeShortcuts(encodeShortcuts(overrides));
      expect(decoded, overrides);
    });

    test('存的是 keyId 而不是显示名：Enter 与小键盘 Enter 不会串味', () {
      // `keyLabel` 对 enter 与 numpadEnter 都给 'Enter'，若按名字往返就会互相冒充。
      final overrides = {
        PlayerShortcut.toggleControls: const ShortcutBinding(
          LogicalKeyboardKey.numpadEnter,
        ),
      };
      final decoded = decodeShortcuts(encodeShortcuts(overrides));
      expect(
        decoded[PlayerShortcut.toggleControls]!.key,
        LogicalKeyboardKey.numpadEnter,
      );
    });

    test('未动过的动作不落一行（默认值将来变更时能自动跟上）', () {
      final encoded = encodeShortcuts({
        PlayerShortcut.playPause: const ShortcutBinding(LogicalKeyboardKey.keyJ),
      });
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      expect(map.keys, [PlayerShortcut.playPause.name]);
    });
  });

  group('坏数据一律回落默认，绝不让键盘失灵', () {
    test('非法 JSON / 非 Map / 空串都解成空表', () {
      for (final raw in ['', '{', 'not json', '[1,2,3]', '"a string"']) {
        expect(decodeShortcuts(raw), isEmpty, reason: '坏数据：$raw');
      }
    });

    test('未知动作名被丢弃，其余项照常解析', () {
      final raw = jsonEncode({
        'playPause': {'k': LogicalKeyboardKey.keyJ.keyId},
        'someRemovedAction': {'k': LogicalKeyboardKey.keyK.keyId},
      });
      final decoded = decodeShortcuts(raw);
      expect(decoded.keys, {PlayerShortcut.playPause});
    });

    test('畸形绑定被跳过（不是当成「不设置」）', () {
      // 缺 k、k 不是整数、绑了被禁的键：这三种都该「回落默认」，
      // 若误判成 null 就成了「用户禁用了这个动作」，那是完全相反的行为。
      final raw = jsonEncode({
        'playPause': {'k': 'not an int'},
        'fullscreen': {},
        'screenshot': {'k': LogicalKeyboardKey.tab.keyId},
        'mute': {'k': LogicalKeyboardKey.shiftLeft.keyId},
        'refresh': null, // 这一条才是合法的「不设置」
      });
      final decoded = decodeShortcuts(raw);
      expect(decoded.containsKey(PlayerShortcut.playPause), isFalse);
      expect(decoded.containsKey(PlayerShortcut.fullscreen), isFalse);
      expect(decoded.containsKey(PlayerShortcut.screenshot), isFalse);
      expect(decoded.containsKey(PlayerShortcut.mute), isFalse);
      expect(decoded.containsKey(PlayerShortcut.refresh), isTrue);
      expect(decoded[PlayerShortcut.refresh], isNull);
    });
  });

  group('冲突判定', () {
    test('与别的动作撞键时报出那个动作', () {
      final conflict = conflictShortcut(
        effective,
        const ShortcutBinding(LogicalKeyboardKey.keyF),
        PlayerShortcut.screenshot,
      );
      expect(conflict, PlayerShortcut.fullscreen);
    });

    test('与自己撞键不算冲突（改回同一个键是合法操作）', () {
      final conflict = conflictShortcut(
        effective,
        const ShortcutBinding(LogicalKeyboardKey.keyF),
        PlayerShortcut.fullscreen,
      );
      expect(conflict, isNull);
    });

    test('修饰键不同就不算冲突', () {
      final conflict = conflictShortcut(
        effective,
        const ShortcutBinding(LogicalKeyboardKey.keyF, ctrl: true),
        PlayerShortcut.screenshot,
      );
      expect(conflict, isNull);
    });

    test('被禁用的动作不占键（它的绑定是 null，不该挡住别人）', () {
      final withUnset = resolveEffectiveShortcuts({
        PlayerShortcut.fullscreen: null,
      });
      final conflict = conflictShortcut(
        withUnset,
        const ShortcutBinding(LogicalKeyboardKey.keyF),
        PlayerShortcut.screenshot,
      );
      expect(conflict, isNull);
    });
  });

  group('显示名', () {
    test('形状特殊的键给紧凑名，字母数字回落 keyLabel', () {
      expect(shortcutKeyLabel(LogicalKeyboardKey.space), 'Space');
      expect(shortcutKeyLabel(LogicalKeyboardKey.escape), 'Esc');
      expect(shortcutKeyLabel(LogicalKeyboardKey.arrowUp), 'Up');
      expect(shortcutKeyLabel(LogicalKeyboardKey.arrowDown), 'Down');
      expect(shortcutKeyLabel(LogicalKeyboardKey.keyA), 'A');
      expect(shortcutKeyLabel(LogicalKeyboardKey.digit1), '1');
      expect(shortcutKeyLabel(LogicalKeyboardKey.comma), ',');
    });

    test('组合键串里修饰键顺序固定', () {
      expect(
        shortcutBindingLabel(const ShortcutBinding(LogicalKeyboardKey.space,
            meta: true, alt: true, ctrl: true, shift: true)),
        'Shift + Ctrl + Alt + Meta + Space',
      );
      expect(
        shortcutBindingLabel(const ShortcutBinding(LogicalKeyboardKey.keyS)),
        'S',
      );
    });
  });

  test('每个动作都有中文名（设置页不漏字）', () {
    for (final action in kShortcutOrder) {
      expect(shortcutActionTitle(action), isNotEmpty);
      // 兜底实现会返回枚举名（含大写），真配上中文后不该再出现。
      expect(shortcutActionTitle(action), isNot(action.name));
    }
  });

  test('音量步进是唯一吃长按重复的动作集', () {
    expect(repeatablePlayerShortcuts, {
      PlayerShortcut.volumeUp,
      PlayerShortcut.volumeDown,
    });
  });
}
