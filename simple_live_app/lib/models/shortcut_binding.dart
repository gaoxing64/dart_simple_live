/// 播放器快捷键的**数据模型**：动作、绑定、默认值、编解码与匹配。
///
/// 单独成文件（而不是留在 `player_shortcuts.dart`）有两个理由：
/// 1. 设置页与录制对话框要用这套模型，但它们绝不该 import 执行层
///    （那边连着 controller、播放器与整条动作派发链）；
/// 2. 键位表是纯数据，全部规则都能在这里被断言，不必拉起播放器与本地存储
///    （见 `test/shortcut_binding_test.dart`）。
///
/// 「一个动作此刻到底绑在哪个键」有三种状态，用 **map 键的存在性**表达，
/// 不另设标志位：
/// - 键**不存在** → 用默认值（用户从没动过这一行）；
/// - 键存在、值为 `null` → 用户选了「不设置」，这个动作被禁用；
/// - 键存在、值非空 → 自定义绑定。
/// 这样「恢复默认」就是把键删掉，而不是写回一份默认值的副本——后者会在默认值
/// 将来变更时把过时的快照永久钉在用户配置里。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// 一个可绑定的播放器动作。
enum PlayerShortcut {
  playPause,
  fullscreen,
  exitPlayer,
  volumeUp,
  volumeDown,
  danmakuToggle,
  mute,
  screenshot,
  smallWindow,
  lockControls,
  refresh,
  quality,
  pick,
  prevLine,
  nextLine,
  toggleControls,
  focusSlot1,
  focusSlot2,
  focusSlot3,
  focusSlot4,
}

/// 展示顺序＝设置页里的行序（对齐参考图的排布：播放/暂停、切换全屏、退出/关闭、
/// 音量增大、音量减小，再往后是弹幕/静音/截图这些）。
///
/// 这份顺序同时是「动作全集」的唯一出口：`kDefaultShortcuts` 必须与它一一对应，
/// 测试会钉住这一点，新增动作忘了给默认键位会直接红。
const List<PlayerShortcut> kShortcutOrder = [
  PlayerShortcut.playPause,
  PlayerShortcut.fullscreen,
  PlayerShortcut.exitPlayer,
  PlayerShortcut.volumeUp,
  PlayerShortcut.volumeDown,
  PlayerShortcut.danmakuToggle,
  PlayerShortcut.mute,
  PlayerShortcut.screenshot,
  PlayerShortcut.smallWindow,
  PlayerShortcut.lockControls,
  PlayerShortcut.refresh,
  PlayerShortcut.quality,
  PlayerShortcut.pick,
  PlayerShortcut.prevLine,
  PlayerShortcut.nextLine,
  PlayerShortcut.toggleControls,
  PlayerShortcut.focusSlot1,
  PlayerShortcut.focusSlot2,
  PlayerShortcut.focusSlot3,
  PlayerShortcut.focusSlot4,
];

/// 设置页里显示的动作名。
String shortcutActionTitle(PlayerShortcut action) => switch (action) {
  PlayerShortcut.playPause => "播放/暂停",
  PlayerShortcut.fullscreen => "切换全屏",
  PlayerShortcut.exitPlayer => "退出/关闭播放器",
  PlayerShortcut.volumeUp => "音量增大",
  PlayerShortcut.volumeDown => "音量减小",
  PlayerShortcut.danmakuToggle => "弹幕开关",
  PlayerShortcut.mute => "静音/取消静音",
  PlayerShortcut.screenshot => "截图",
  PlayerShortcut.smallWindow => "小窗播放",
  PlayerShortcut.lockControls => "锁定/解锁控制条",
  PlayerShortcut.refresh => "刷新直播间",
  PlayerShortcut.quality => "切换清晰度",
  PlayerShortcut.pick => "换台",
  PlayerShortcut.prevLine => "上一条线路",
  PlayerShortcut.nextLine => "下一条线路",
  PlayerShortcut.toggleControls => "显示/隐藏控制条",
  PlayerShortcut.focusSlot1 => "聚焦第 1 路",
  PlayerShortcut.focusSlot2 => "聚焦第 2 路",
  PlayerShortcut.focusSlot3 => "聚焦第 3 路",
  PlayerShortcut.focusSlot4 => "聚焦第 4 路",
};

/// 一个动作的按键绑定：一个主键 + 四个修饰键。
///
/// 只存**一个**主键：参考图里那排 chips 是「Shift + Alt + Space」这种
/// 「修饰键们 + 一个主键」的形态，不支持两个主键并押（那是 chord，另一套复杂度）。
///
/// 修饰键存成四个 bool 而不是位掩码：这份数据要进 JSON、要显示、要比相等，
/// 位掩码在三个场合都得再解释一次，省不下什么。
class ShortcutBinding {
  const ShortcutBinding(this.key, {this.shift = false, this.ctrl = false, this.alt = false, this.meta = false});

  final LogicalKeyboardKey key;
  final bool shift;
  final bool ctrl;
  final bool alt;
  final bool meta;

  bool get hasModifier => shift || ctrl || alt || meta;

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.key == key &&
      other.shift == shift &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, shift, ctrl, alt, meta);

  @override
  String toString() => 'ShortcutBinding(${shortcutBindingLabel(this)})';
}

/// 默认键位：与上一版硬编码表**逐键一致**，外加 `exitPlayer = Escape`。
///
/// 键位的选择理由见 `player_shortcuts.dart` 的文件头注释（参考 PiliPlus，
/// 直播场景把 ←/→ 从 seek 改成了切线路）。
const Map<PlayerShortcut, ShortcutBinding> kDefaultShortcuts = {
  PlayerShortcut.playPause: ShortcutBinding(LogicalKeyboardKey.space),
  PlayerShortcut.fullscreen: ShortcutBinding(LogicalKeyboardKey.keyF),
  PlayerShortcut.exitPlayer: ShortcutBinding(LogicalKeyboardKey.escape),
  PlayerShortcut.volumeUp: ShortcutBinding(LogicalKeyboardKey.arrowUp),
  PlayerShortcut.volumeDown: ShortcutBinding(LogicalKeyboardKey.arrowDown),
  PlayerShortcut.danmakuToggle: ShortcutBinding(LogicalKeyboardKey.keyD),
  PlayerShortcut.mute: ShortcutBinding(LogicalKeyboardKey.keyM),
  PlayerShortcut.screenshot: ShortcutBinding(LogicalKeyboardKey.keyS),
  PlayerShortcut.smallWindow: ShortcutBinding(LogicalKeyboardKey.keyP),
  PlayerShortcut.lockControls: ShortcutBinding(LogicalKeyboardKey.keyL),
  PlayerShortcut.refresh: ShortcutBinding(LogicalKeyboardKey.keyR),
  PlayerShortcut.quality: ShortcutBinding(LogicalKeyboardKey.keyQ),
  PlayerShortcut.pick: ShortcutBinding(LogicalKeyboardKey.keyG),
  PlayerShortcut.prevLine: ShortcutBinding(LogicalKeyboardKey.arrowLeft),
  PlayerShortcut.nextLine: ShortcutBinding(LogicalKeyboardKey.arrowRight),
  PlayerShortcut.toggleControls: ShortcutBinding(LogicalKeyboardKey.enter),
  PlayerShortcut.focusSlot1: ShortcutBinding(LogicalKeyboardKey.digit1),
  PlayerShortcut.focusSlot2: ShortcutBinding(LogicalKeyboardKey.digit2),
  PlayerShortcut.focusSlot3: ShortcutBinding(LogicalKeyboardKey.digit3),
  PlayerShortcut.focusSlot4: ShortcutBinding(LogicalKeyboardKey.digit4),
};

/// 吃「按住不放」重复事件的动作。
///
/// 只有音量：按住 ↑/↓ 连续加减是想要的节拍，而按住 F/D/M/L/P 若也吃重复，
/// 就会一路来回开关全屏／弹幕／静音。单独提出来是为了让这条规则可以被断言
/// （见 `test/shortcut_binding_test.dart`），而不是散在处理函数里的一个 if。
const Set<PlayerShortcut> repeatablePlayerShortcuts = {
  PlayerShortcut.volumeUp,
  PlayerShortcut.volumeDown,
};

/// 绑定**永不接受**这些键：它们承担着界面自己的键盘可用性。
///
/// `Tab` / `Shift+Tab` 是 Flutter 焦点遍历的键，绑上去等于把设置界面与播放器
/// 条带变成按不动的按钮；纯修饰键单独按下不产生任何可派发事件（`KeyDownEvent`
/// 会来，但用户还没按主键，此时触发动作就是误触）。
bool isForbiddenShortcutKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.tab || isModifierKey(key);

/// 是不是一个纯修饰键（左右各一都算）。
bool isModifierKey(LogicalKeyboardKey key) => _modifierKeys.contains(key);

/// 主键的紧凑显示名（`Space` / `Esc` / `Up` / `A` / `1` / `,`）。
///
/// 不直接用 `LogicalKeyboardKey.keyLabel`：它给的是 `'Arrow Up'`、`'Page Up'`、
/// `'Escape'` 这种带空格的长名，放进参考图那种小 chips 里会撑破；而空格的
/// `keyLabel` 干脆就是一个空格字符，看不见。
///
/// 字母与数字**恰好**能靠 `keyLabel` 拿到想要的大写形态（`keyA` → `A`、
/// `digit1` → `1`），所以这里只覆盖形状特殊的键，其余回落 `keyLabel`。
String shortcutKeyLabel(LogicalKeyboardKey key) {
  final special = _keyLabels[key];
  if (special != null) {
    return special;
  }
  final label = key.keyLabel;
  return label.isEmpty ? '?' : label;
}

/// 按命名常量索引而不是按 `keyId` 字面量：Dart 不许 `const` map 用重写过 `==` 的
/// 类当 key（`LogicalKeyboardKey` 正是），改成 `final` 就够了——手抄十六进制
/// keyId 看着只省了一个关键字，实际会把「arrowDown 抄成 end」这种错永久埋进表里，
/// 而且编译期完全发现不了。
final Map<LogicalKeyboardKey, String> _keyLabels = {
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'Num Enter',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.backslash: r'\',
  LogicalKeyboardKey.semicolon: ';',
  LogicalKeyboardKey.quoteSingle: "'",
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.backquote: '`',
  LogicalKeyboardKey.minus: '-',
  LogicalKeyboardKey.equal: '=',
};

/// 纯修饰键（左右各一都算）。
///
/// 单独一份而不是复用 [_keyLabels]：「不能绑定」与「显示成什么」是两个问题，
/// 合并成一张表迟早会有人为了显示去动禁绑名单。
final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  // 这四个是「任意 Shift」那类归组键：真实按键事件不会报它们（报的是左右具体值），
  // 但手改过的配置或未来的事件源可能带进来，一并禁掉免得成了绑不上的死键。
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.meta,
};

/// 一个绑定的完整显示串，如 `Shift + Alt + Space`。
///
/// 修饰键顺序固定（Shift→Ctrl→Alt→Meta），否则同一个组合在列表里、chips 里、
/// 提示文案里会长得不一样。
String shortcutBindingLabel(ShortcutBinding binding) {
  final parts = <String>[
    if (binding.shift) 'Shift',
    if (binding.ctrl) 'Ctrl',
    if (binding.alt) 'Alt',
    if (binding.meta) 'Meta',
    shortcutKeyLabel(binding.key),
  ];
  return parts.join(' + ');
}

/// 用户覆盖表 → 生效表（每个动作都有确定的一项）。
///
/// 返回的 map 覆盖**全部**动作：没有覆盖项的填默认值，显式「不设置」的填 null。
/// 执行层与设置页都只读这一份，两边不会各算各的。
Map<PlayerShortcut, ShortcutBinding?> resolveEffectiveShortcuts(
  Map<PlayerShortcut, ShortcutBinding?> overrides,
) {
  return {
    for (final action in kShortcutOrder)
      action: overrides.containsKey(action)
          ? overrides[action]
          : kDefaultShortcuts[action],
  };
}

/// 主键是不是一个字母键（A–Z）。
///
/// 这是「Ctrl 旁路」的适用边界，只放开字母：中文输入法激活时，字母键会被截获
/// 去做拼音合成，Flutter 根本收不到 `KeyDownEvent`，裸字母快捷键因此在中文
/// 输入法下全部失效；而 `Ctrl + 字母` 输入法会放行（参考项目 PiliPlus 正是靠
/// 「匹配时不看 Ctrl」让 `Ctrl+F` 也能触发全屏）。
///
/// 空格 / 回车 / 方向键 / 数字 / Esc **一律不旁路**，两个理由：
/// 1. 输入法不截这些键，它们本来就能正常触发，没有旁路的需要；
/// 2. 抢了会废掉系统级热键——`Ctrl+Space` 是 Windows 的输入法切换、
///    `Ctrl+Enter` 是输入法的中英标点切换。
bool isLetterShortcutKey(LogicalKeyboardKey key) => _letterKeys.contains(key);

/// 26 个字母逻辑键。`keyA`–`keyZ` 在 Unicode 区段内连续，从 `keyA` 递增构造，
/// 而不是手抄 26 个常量（抄漏一个就是「某个字母在中文输入法下按不动」这种
/// 只在特定键上复现的诡异 bug）。
final Set<LogicalKeyboardKey> _letterKeys = {
  for (var i = 0; i < 26; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i),
};

/// 单个绑定是否命中这次按键。
///
/// [imeBypass] 关掉时是**严格相等**：只绑了 `S`（截图）时 `Ctrl+S` 不得命中，
/// 否则用户想存个档就把播放器切走了；反过来绑了 `Ctrl+S` 时裸 `S` 也不命中。
/// 打开时额外允许「按下带 Ctrl、绑定本身不带 Ctrl、主键是字母」这一种偏差，
/// 即上面说的输入法旁路。其余修饰键（Shift/Alt/Meta）两种模式下都必须相等。
bool _bindingMatches(
  ShortcutBinding binding,
  LogicalKeyboardKey key, {
  required bool shift,
  required bool ctrl,
  required bool alt,
  required bool meta,
  bool imeBypass = false,
}) {
  if (binding.key != key) {
    return false;
  }
  if (binding.shift != shift || binding.alt != alt || binding.meta != meta) {
    return false;
  }
  if (binding.ctrl == ctrl) {
    return true;
  }
  return imeBypass &&
      ctrl &&
      !binding.ctrl &&
      isLetterShortcutKey(key);
}

/// 按下的键（含修饰键状态）命中哪个动作。
///
/// 纯修饰键作为主键按下一律不匹配（见 [isForbiddenShortcutKey]）。
///
/// **两遍匹配，严格优先**：先找完全相等的绑定，都没有才找旁路。顺序反了的话，
/// 用户把某个动作显式绑成 `Ctrl+F`、另一个动作是裸 `F` 时，`Ctrl+F` 会被裸 `F`
/// 抢走——显式配置必须赢过隐式旁路。
PlayerShortcut? matchShortcut(
  Map<PlayerShortcut, ShortcutBinding?> effective,
  LogicalKeyboardKey key, {
  required bool shift,
  required bool ctrl,
  required bool alt,
  required bool meta,
}) {
  if (isModifierKey(key)) {
    return null;
  }
  for (final entry in effective.entries) {
    final binding = entry.value;
    if (binding == null) {
      continue;
    }
    if (_bindingMatches(
      binding,
      key,
      shift: shift,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
    )) {
      return entry.key;
    }
  }
  // 第二遍：输入法旁路。只在真的按住了 Ctrl 时才可能命中，所以裸键不会走到这里。
  if (ctrl) {
    for (final entry in effective.entries) {
      final binding = entry.value;
      if (binding == null) {
        continue;
      }
      if (_bindingMatches(
        binding,
        key,
        shift: shift,
        ctrl: ctrl,
        alt: alt,
        meta: meta,
        imeBypass: true,
      )) {
        return entry.key;
      }
    }
  }
  return null;
}

/// 按下的键（含修饰键状态）是否就是 [binding] 所描述的那个组合。
///
/// 与 [matchShortcut] 同一套判据（含输入法旁路），只是调用方手上只有一个绑定
/// 而不是整张表——`main.dart` 那条全局链正是这种情况：它只需要知道「这一下是不是
/// 用户给『退出/关闭播放器』配的那个键」。单绑定不需要「严格优先」的两遍结构。
bool shortcutBindingMatches(
  ShortcutBinding binding,
  LogicalKeyboardKey key, {
  required bool shift,
  required bool ctrl,
  required bool alt,
  required bool meta,
}) {
  if (isModifierKey(key)) {
    return false;
  }
  return _bindingMatches(
    binding,
    key,
    shift: shift,
    ctrl: ctrl,
    alt: alt,
    meta: meta,
    imeBypass: true,
  );
}

/// 这个绑定已被哪个**别的**动作占用；没有冲突返回 null。
///
/// [exclude] 是正在编辑的那个动作：它自己当然占着自己的键，不算冲突。
/// 比较走 [ShortcutBinding] 的 `==`，所以 `Shift+A` 与 `A` 不会互相误判。
///
/// 这里**刻意用精确相等**而不是复用 [_bindingMatches]：输入法旁路会让裸 `F`
/// 与 `Ctrl+F` 在「按下」时都能命中 `F` 那条绑定，但那是**有优先级规则的**
/// （见 [matchShortcut]：严格命中先于旁路），不是一处需要拦下来的冲突。若这里
/// 也按旁路判等，用户就没法同时保留「F 全屏」与「Ctrl+F 截图」这种合法配置了。
PlayerShortcut? conflictShortcut(
  Map<PlayerShortcut, ShortcutBinding?> effective,
  ShortcutBinding candidate,
  PlayerShortcut exclude,
) {
  for (final entry in effective.entries) {
    if (entry.key == exclude) {
      continue;
    }
    if (entry.value == candidate) {
      return entry.key;
    }
  }
  return null;
}

/// 覆盖表 → 存盘的 JSON 字符串。
///
/// 只写用户真正动过的项（键存在＝动过）：从没碰过的动作不落一行，将来默认值
/// 调整时它们会自动跟上。`null` 显式写成 `null`，那是「不设置」，不能丢。
String encodeShortcuts(Map<PlayerShortcut, ShortcutBinding?> overrides) {
  if (overrides.isEmpty) {
    return '';
  }
  final map = <String, Object?>{
    for (final entry in overrides.entries)
      entry.key.name: entry.value == null ? null : _bindingToJson(entry.value!),
  };
  return jsonEncode(map);
}

/// JSON 字符串 → 覆盖表。
///
/// 坏数据（空串、非法 JSON、字段缺失、未知动作名）**一律按不存在处理**，
/// 也就是回落到默认值：快捷键配置坏了不该让设置页打不开，更不该让播放器
/// 从此不响应键盘。整份坏掉就当没配过。
Map<PlayerShortcut, ShortcutBinding?> decodeShortcuts(String raw) {
  if (raw.isEmpty) {
    return {};
  }
  final Map<String, dynamic> decoded;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map) {
      return {};
    }
    decoded = parsed.cast<String, dynamic>();
  } catch (_) {
    return {};
  }
  final byName = {for (final a in PlayerShortcut.values) a.name: a};
  final result = <PlayerShortcut, ShortcutBinding?>{};
  for (final entry in decoded.entries) {
    final action = byName[entry.key];
    if (action == null) {
      // 来自动作已被删掉的旧版本：丢掉，别让它在配置里越攒越多。
      continue;
    }
    // 这里要分清两种「没有绑定」：JSON 里显式的 `null` 是用户选的「不设置」，
    // 必须记下来；而**畸形**的那一项（缺 k、k 不是整数、绑了被禁的键）是坏数据，
    // 记成 null 会把它误读成「用户禁用了这个动作」，所以整条跳过＝回落默认。
    if (entry.value == null) {
      result[action] = null;
      continue;
    }
    final binding = _bindingFromJson(entry.value);
    if (binding != null) {
      result[action] = binding;
    }
  }
  return result;
}

Map<String, Object?> _bindingToJson(ShortcutBinding b) => {
  'k': b.key.keyId,
  if (b.shift) 's': true,
  if (b.ctrl) 'c': true,
  if (b.alt) 'a': true,
  if (b.meta) 'm': true,
};

/// 主键存 `keyId` 而**不是**显示名：`keyLabel` 是有歧义的（`'Enter'` 同时是
/// `enter` 与 `numpadEnter` 的 label，`'Space'` 也有两个来源），拿名字往返会把
/// 小键盘回车存成主键盘回车。`keyId` 是稳定且跨平台一致的数字。
ShortcutBinding? _bindingFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    return null;
  }
  final keyId = value['k'];
  if (keyId is! int) {
    return null;
  }
  final key = LogicalKeyboardKey(keyId);
  // 存盘前被禁的键（Tab、纯修饰键）不该在读取后又生效：老版本或手改过的配置
  // 里都可能留着，一律视为「这一项作废，回落默认」。
  if (isForbiddenShortcutKey(key)) {
    return null;
  }
  return ShortcutBinding(
    key,
    shift: value['s'] == true,
    ctrl: value['c'] == true,
    alt: value['a'] == true,
    meta: value['m'] == true,
  );
}
