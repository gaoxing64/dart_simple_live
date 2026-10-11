// 直播间**默认键位**的逐键回归。
//
// 与 `shortcut_binding_test.dart` 的分工：那边钉的是模型的**结构性质**
// （默认表与动作全集一致、编解码往返、坏数据回落、冲突判定）；这里钉的是
// 「哪个键翻成哪个动作」这份**具体映射**——它是用户的肌肉记忆，也是这套系统
// 唯一的对外契约。键位可自定义之后，这份默认值更要有人守着：重构时手滑挪一位，
// 用户不会读到任何报错，只会在某天按 F 发现没反应。
//
// 动作的**执行**（真的暂停、真的切线路）归 controller 层与人工验证，
// 这里不拉起播放器。
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';

/// 默认表下按一个键（无修饰键）命中哪个动作。
PlayerShortcut? _defaultHit(LogicalKeyboardKey key) => matchShortcut(
  resolveEffectiveShortcuts({}),
  key,
  shift: false,
  ctrl: false,
  alt: false,
  meta: false,
);

void main() {
  group('默认键位逐键对应（参考 PiliPlus 的播放器手势集）', () {
    test('播放与窗口类动作', () {
      expect(_defaultHit(LogicalKeyboardKey.space), PlayerShortcut.playPause);
      expect(_defaultHit(LogicalKeyboardKey.keyF), PlayerShortcut.fullscreen);
      expect(_defaultHit(LogicalKeyboardKey.escape), PlayerShortcut.exitPlayer);
      expect(
          _defaultHit(LogicalKeyboardKey.keyD), PlayerShortcut.danmakuToggle);
      expect(_defaultHit(LogicalKeyboardKey.keyP), PlayerShortcut.smallWindow);
      expect(_defaultHit(LogicalKeyboardKey.keyM), PlayerShortcut.mute);
      expect(_defaultHit(LogicalKeyboardKey.keyS), PlayerShortcut.screenshot);
      expect(_defaultHit(LogicalKeyboardKey.keyL), PlayerShortcut.lockControls);
      expect(_defaultHit(LogicalKeyboardKey.keyR), PlayerShortcut.refresh);
    });

    test('直播适配：方向键切线路与音量，Q/G 开面板', () {
      expect(_defaultHit(LogicalKeyboardKey.arrowUp), PlayerShortcut.volumeUp);
      expect(
          _defaultHit(LogicalKeyboardKey.arrowDown), PlayerShortcut.volumeDown);
      expect(
          _defaultHit(LogicalKeyboardKey.arrowLeft), PlayerShortcut.prevLine);
      expect(_defaultHit(LogicalKeyboardKey.arrowRight),
          PlayerShortcut.nextLine);
      expect(_defaultHit(LogicalKeyboardKey.keyQ), PlayerShortcut.quality);
      expect(_defaultHit(LogicalKeyboardKey.keyG), PlayerShortcut.pick);
    });

    test('Enter 显隐控制条，1-4 切多开聚焦格', () {
      expect(
          _defaultHit(LogicalKeyboardKey.enter), PlayerShortcut.toggleControls);
      expect(_defaultHit(LogicalKeyboardKey.digit1),
          PlayerShortcut.focusSlot1);
      expect(_defaultHit(LogicalKeyboardKey.digit2),
          PlayerShortcut.focusSlot2);
      expect(_defaultHit(LogicalKeyboardKey.digit3),
          PlayerShortcut.focusSlot3);
      expect(_defaultHit(LogicalKeyboardKey.digit4),
          PlayerShortcut.focusSlot4);
    });
  });

  group('不吞不属于自己的键', () {
    // PiliPlus 里这些键有含义（W 投币、E 收藏、T/V 稍后再看、Q/R 三连），
    // 直播场景没有对应动作，必须原样放行——否则用户在聊天输入框里打字、
    // 或按 Tab 想走到某个按钮，都会被播放器半路截走。
    test('PiliPlus 的稿件类按键在直播间是未映射的', () {
      for (final key in [
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyV,
      ]) {
        expect(_defaultHit(key), isNull, reason: '$key 不该被直播间吞掉');
      }
    });

    test('导航与修饰键未映射', () {
      for (final key in [
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit5,
      ]) {
        expect(_defaultHit(key), isNull, reason: '$key 不该被直播间吞掉');
      }
    });

    test('字母键里默认只占用约定的那 9 个', () {
      // 反向遍历 a-z：命中集合必须与已断言过的那批**完全相等**，不能多一个。
      // 多出来的那个就是「悄悄吞掉一个字母键」，而它不会有任何报错。
      final mapped = <LogicalKeyboardKey>{
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyS,
      };
      final hit = <LogicalKeyboardKey>{};
      for (var i = 0; i < 26; i++) {
        final key = LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i);
        if (_defaultHit(key) != null) {
          hit.add(key);
        }
      }
      expect(hit, mapped);
    });
  });

  test('默认表覆盖每一个动作（新增动作忘了配键，这条会红）', () {
    final reachable = <PlayerShortcut>{
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ])
        if (_defaultHit(key) case final s?) s,
    };
    expect(reachable, kShortcutOrder.toSet());
  });

  group('改键之后', () {
    test('旧键立即失效，新键接管', () {
      final rebound = resolveEffectiveShortcuts({
        PlayerShortcut.playPause: const ShortcutBinding(
          LogicalKeyboardKey.keyK,
        ),
      });
      PlayerShortcut? hit(LogicalKeyboardKey k) => matchShortcut(
        rebound,
        k,
        shift: false,
        ctrl: false,
        alt: false,
        meta: false,
      );
      expect(hit(LogicalKeyboardKey.keyK), PlayerShortcut.playPause);
      expect(hit(LogicalKeyboardKey.space), isNull);
    });

    test('「不设置」的那个动作彻底不响应，其余不受牵连', () {
      final withUnset = resolveEffectiveShortcuts({
        PlayerShortcut.exitPlayer: null,
      });
      expect(
        matchShortcut(withUnset, LogicalKeyboardKey.escape,
            shift: false, ctrl: false, alt: false, meta: false),
        isNull,
      );
      expect(
        matchShortcut(withUnset, LogicalKeyboardKey.space,
            shift: false, ctrl: false, alt: false, meta: false),
        PlayerShortcut.playPause,
      );
    });
  });
}
