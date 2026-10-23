import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_selection.dart';
import 'package:simple_live_app/modules/live_room/player/pip_aspect.dart';
import 'package:simple_live_app/modules/live_room/sidebar_layout.dart';
import 'package:simple_live_app/routes/live_room_route_args.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/window_service.dart';
import 'package:window_manager/window_manager.dart';

/// 一次直播间多开会话：持有页面主格 + 若干副格。
///
/// 只有页面主格那份是「真的」：副格在 [addRoom] 里被回填成同一个会话
/// （`attachHostSession`），所以四路查到的「是否在多开、谁是焦点」是同一份状态。
/// 这一点对音量尤其关键——否则副格会以为自己没在多开，开了压低时也不会被压低。
///
/// 为什么每格就是一个完整的 `LiveRoomController` 而不是抽一层「纯播放器」：
/// `resetRoom` 早就划好了「一个直播间 = 一个 controller」的边界（弹幕 WS、Rust 面具、
/// 消息列表、清晰度/线路、播放器全在里面），而 `player_controls.dart` 里十几个
/// helper 的类型都是具体类。复用整套既有链路，比新造抽象改动小得多。
class MultiPlaySession {
  MultiPlaySession(this.page) {
    slots.add(page);
    enabled.value = AppSettingsController.instance.multiPlayEnable.value;
  }

  /// 页面主格（`slots[0]` 恒为它）。它同时是路由绑定的那个 controller。
  final LiveRoomController page;

  /// 多画面模式开关（持久化）。真正的多开还要看已经加了几路，见 [isActive]。
  final RxBool enabled = false.obs;

  /// 当前聚焦格在 [slots] 里的下标。聊天区、音量分配都以它为唯一真源。
  final RxInt focusedSlot = 0.obs;

  /// 全部格子，`[主格, ...副格]`。
  ///
  /// 用 RxList 而不是普通 List：网格的 Obx 要能感知加/减路（只靠 focusedSlot
  /// 不够——摘掉一个非聚焦格时焦点下标可能根本没变）。
  final RxList<LiveRoomController> slots = RxList<LiveRoomController>();

  Size? _preMultiPlaySize;

  /// 是否真的以多开形态呈现：开关打开且确实有 2 路以上。
  ///
  /// 只有 1 路时按单画面渲染——那时网格与单画面没区别，但每格控件会退化成
  /// 轻量浮层，不如直接给完整 OSD。
  bool get isActive => enabled.value && slots.length > 1;

  LiveRoomController get focused =>
      slots[focusedSlot.value.clamp(0, slots.length - 1)];

  /// 关注列表点选：多画面模式下占一个空格，否则维持原来的「替换当前房间」。
  void onFollowItemTap(Site site, String roomId) {
    // 原来这里还叠了一道「桌面才有渲染」的判据，防的是 enabled 被同步带成 true
    // 而界面根本不画网格 → 建出一个永不渲染却照旧出声解码的幽灵格子。
    // 移动端适配后视频区的平台门已拆（`live_room_page.buildLiveRoomVideoArea`），
    // enabled 为真就一定有渲染，那道保险成了多余的第二份平台知识。
    if (enabled.value) {
      addRoom(site, roomId);
    } else {
      page.resetRoom(site, roomId);
    }
  }

  /// 关注列表那颗「加入多开」icon 的语义：**只负责加入**。
  ///
  /// 这是把多开从「模式」改成「动作」后的入口——原先只有 [onFollowItemTap] 一条
  /// 路径，它按 [enabled] 分流（开着就加入、关着就替换当前房间），用户得先切模式
  /// 才谈得上「加一路」。现在加入是行内一颗 icon 直接表达的意图。
  ///
  /// **移出刻意不在这条路径上**：面板里已经在播的那些行不再显示任何 icon
  /// （见 [shouldShowMultiPlayAddAction]），关格子一律去网格里点那颗 ✕ ——
  /// 那里能直接看到「关掉的是哪一格」，不必在列表里隔着一层焦点关系去推。
  ///
  /// 已经在多开里时点不动（那颗 icon 压根不画），所以这里只需处理「不在多开」这一种；
  /// 仍以 [addRoom] 为准而不是直接写实现，是为了让「已存在则切焦点」这条既有语义
  /// 继续生效（面板行点击也走它）。
  void addRoomFromList(Site site, String roomId) => addRoom(site, roomId);

  /// 这一路在会话里的槽位下标；不在多开里返回 -1。
  ///
  /// 给界面判「这一行还要不要显示加入 icon」用（[shouldShowMultiPlayAddAction]）。
  /// 取不到（不是 [Site] + roomId 的组合）时返回 -1，调用方按「不在多开」渲染即可，
  /// 不必自己再判一遍相等。
  int slotIndexOf(Site site, String roomId) {
    return slots.indexWhere(
      (t) => t.site.id == site.id && t.roomId == roomId,
    );
  }

  /// 开关多画面模式。
  void setEnabled(bool value) {
    if (enabled.value == value) {
      return;
    }
    enabled.value = value;
    AppSettingsController.instance.setMultiPlayEnable(value);
    if (!value) {
      // 关掉多开时其余几路必须一起停：不然它们还在后台出声、还在耗解码，
      // 而界面上已经看不到任何线索。removeTile 会顺带恢复窗口下限。
      closeAllTiles();
      return;
    }
    refreshWindowFloor();
  }

  /// 把一路主播加进多开；已在多开里则只切焦点。
  void addRoom(Site site, String roomId) {
    final exist = slots.indexWhere(
      (t) => t.site.id == site.id && t.roomId == roomId,
    );
    if (exist >= 0) {
      focusSlot(exist);
      return;
    }
    if (slots.length >= kMultiPlayMaxTiles) {
      SmartDialog.showToast("已满 $kMultiPlayMaxTiles 路，可用格子上的 ▾ 换掉一路");
      return;
    }

    _createTile(site, roomId);
    setEnabled(true);
    // 这里**不切焦点**：多开时注意力本来就在你正看的那一路（加一路通常是因为它提到了
    // 别人），不切焦点也不会打断当前音频；新那一路等加载好了手动点过去即可。
    //
    // 但音量必须重算一次：新建的格在 onInit 里算音量时还没进 slots（入列在上面那行
    // 之后），会判断成「没在多开」而拿主音量 —— 不重算就和聚焦格等响、开了压低也失效。
    applyVolumes();
    refreshWindowFloor();
  }

  /// 批量加进来（关注页的「多开」入口用）。
  ///
  /// 与 [addRoom] 的区别：不在路上逐个跳焦点、不重复算窗口下限，结束后焦点留在
  /// 第 0 格——批量开的语义是「都看着」，没有哪一路更该抢声音，也让
  /// 「第 0 格＝你点开的那一路」这个直觉成立。
  ///
  /// [limit] 给 None 时取设置里的「默认路数」（桌面 4 / 移动 2，见
  /// [resolveDefaultMultiPlayTiles]）——移动端一次塞四路会因放不下而折叠。
  void addRooms(List<LiveRoomTarget> targets, {int? limit}) {
    final max = (limit ?? AppSettingsController.instance.multiPlayDefaultTiles.value)
        .clamp(kMultiPlayMinTiles, kMultiPlayMaxTiles);
    var added = 0;
    for (final target in targets) {
      if (slots.length >= max) {
        break;
      }
      final exist = slots.indexWhere(
        (t) => t.site.id == target.site.id && t.roomId == target.roomId,
      );
      if (exist >= 0) {
        continue;
      }
      _createTile(target.site, target.roomId);
      added++;
    }
    if (added == 0) {
      return;
    }
    setEnabled(true);
    focusSlot(0);
    refreshWindowFloor();
  }

  /// 建一格并注册进 GetX；[addRoom] / [addRooms] 共用这条路径。
  LiveRoomController _createTile(Site site, String roomId) {
    final tile = LiveRoomController(
      pSite: site,
      pRoomId: roomId,
      isSecondaryTile: true,
      tileSlot: slots.length,
    );
    // 先回填归属会话再 Get.put：这样副格的 onInit 一开始就能读到正确的多开状态
    // （音量、弹幕显隐、窗口操作门控都靠它）。
    tile.attachHostSession(this);
    // 带 tag 注册：fork 的 get 不会覆盖已存活实例，不带 tag 时这一路会静默复用
    // 主格的播放器。Get.delete(tag:) 会走 onDelete → onClose，销毁是现成的。
    // tag 由 tile.tileId 派生（与房间无关），换台后仍然销得掉。
    Get.put(tile, tag: tile.getxTag);
    slots.add(tile);
    return tile;
  }

  /// 把某一格换成另一个直播间（原地换台；路数与排布都不动）。
  ///
  /// 不动焦点：换的是「这一格播什么」，不是「我在看哪一格」。若换的正好是聚焦格，
  /// 它本来就是焦点，聊天区/音量会自然跟着新房间走。
  void replaceTileRoom(LiveRoomController tile, Site site, String roomId) {
    final index = slots.indexOf(tile);
    if (index < 0) {
      return;
    }
    if (tile.site.id == site.id && tile.roomId == roomId) {
      return;
    }
    // 已经在别的格子里播着 → 只把焦点移过去，绝不建第二个实例：同一房间两条 WS、
    // 两个播放器既浪费，又会让音量分配与观看时长互相打架。
    final other = slots.indexWhere(
      (t) => t.site.id == site.id && t.roomId == roomId,
    );
    if (other >= 0 && other != index) {
      focusSlot(other);
      SmartDialog.showToast("该直播间已在第${other + 1}路播放");
      return;
    }
    tile.resetRoom(site, roomId);
  }

  /// 换台下拉的数据源：关注列表里**正在直播**的那些，并标出已在本会话某格播的。
  ///
  /// 与直播间页「关注」页签同一个列表（`FollowService.liveList`），所见即所得。
  List<MultiPlaySwitchEntry> buildSwitchEntries() {
    return [
      for (final user in FollowService.instance.liveList)
        MultiPlaySwitchEntry(
          user: user,
          platform: Sites.allSites[user.siteId]?.name ?? user.siteId,
          playingSlot: slots.indexWhere(
            (t) => t.site.id == user.siteId && t.roomId == user.roomId,
          ),
        ),
    ];
  }

  /// 摘掉一路副格（主格不可摘：它是路由绑定的那个 controller，销掉它等于把整页拆了；
/// 要换内容请走 [onFollowItemTap] 的单画面分支，或格子上的 ▾ 换台）。
  void removeTile(LiveRoomController tile) {
    final index = slots.indexOf(tile);
    if (index <= 0) {
      return;
    }
    _dropTile(index);
  }

  /// 摘掉全部副格，回到只剩主格（返回键第一段 / 关掉多开开关时用）。
  void closeAllTiles() {
    final tiles = slots.where((t) => t != page).toList();
    for (final tile in tiles) {
      removeTile(tile);
    }
  }

  /// 摘掉指定下标的格子并收尾（焦点校正 / 音量 / 画面尺寸收口 / 窗口下限）。
  void _dropTile(int index) {
    final tile = slots[index];
    slots.removeAt(index);
    Get.delete<LiveRoomController>(tag: tile.getxTag);
    focusedSlot.value = focusedSlotAfterRemoval(
      focused: focusedSlot.value,
      removedIndex: index,
      remainingLength: slots.length,
    );
    applyVolumes();
    _clearScaleModeOverridesWhenIdle();
    refreshWindowFloor();
  }

  /// 会话不再以多开形态呈现时，清掉留下来的每一路按格画面尺寸覆盖。
  ///
  /// WHY 收在这一处、而不是散在三个调用点：`scaleModeOverride` 的语义是
  /// 「这一格的临时选择」（会话级、不落盘）；一路不再是「一格」（关掉多开 / 关到
  /// 只剩主格）之后，再持有这个临时值就没有身份可归属——主格若留着它，单画面会
  /// 带着「第 2 路选的铺满」继续播，而设置面板显示「适应」，下一次 `Video` 重建
  /// 还静默换画面。`setEnabled(false)`→`closeAllTiles` 与逐格 `removeTile` 全部
  /// 汇入 `_dropTile`，所以这一处就是「会话不再 active」的唯一漏斗。
  void _clearScaleModeOverridesWhenIdle() {
    if (isActive) {
      return;
    }
    for (final tile in slots) {
      if (tile.scaleModeOverride.value != null) {
        tile.scaleModeOverride.value = null;
        // 清完必须按全局设置重下发一次：已经建好的那路 Video 还带着旧覆盖值。
        tile.updateScaleMode();
      }
    }
  }

  /// 切换聚焦格。切焦点不销毁任何一路：所有播放器、弹幕 WS、Rust 面具都继续跑。
  void focusSlot(int index) {
    if (index < 0 || index >= slots.length) {
      return;
    }
    focusedSlot.value = index;
    applyVolumes();
  }

  /// 按当前焦点重新分配各路音量（开了压低时，总音量按设置里
  /// [AppSettingsController.multiPlayDuckVolume] 的比例压低非聚焦格）。
  /// 总音量滑块变化时也走这里。
  void applyVolumes() {
    for (final tile in slots) {
      tile.applyTargetVolume();
    }
  }

  /// 按格子高度算出这一轮该用的弹幕字号。
  ///
  /// 与 `WindowService.danmakuFontClamped` 是同一条公式，只把「窗口高度」换成
  /// 「格子高度」——每格就当成「一个这么高的窗口」，缩放灵敏度也沿用用户配的。
  /// 关闭「弹幕跟随窗口缩放」时四路都用原始字号。
  ///
  /// 会读 Rx 设置，所以必须在 `Obx`（也就是网格的 build）里调用：这样改弹幕字号
  /// 或开关跟随缩放时，四路能当场跟着变，不用等下一次布局变化。
  double resolveTileDanmakuFontSize(MultiPlayLayoutSpec spec) {
    final settings = AppSettingsController.instance;
    final danmuSize = settings.danmuSize.value;
    if (!settings.danmakuFontClamped.value) {
      return danmuSize;
    }
    return Utils.scaleValue(
      value: danmuSize,
      playerH: spec.cellHeight,
      designH: 720.0,
      upSens: settings.danmakuFontClampUpSens.value / 10,
      downSens: settings.danmakuFontClampDownSens.value / 10,
      minSize: 8,
      maxSize: 48,
    );
  }

  /// 把算好的字号下发给每一格（含主格，它也只是其中一格）。
  void applyTileDanmakuFontSize(double fontSize) {
    if (!isActive) {
      return;
    }
    for (final tile in slots) {
      tile.applyDanmakuFontSize(fontSize);
    }
  }

  /// 回到单画面：清掉按格字号，各路回到整窗口径。
  void clearTileDanmakuFonts() {
    for (final tile in slots) {
      tile.clearDanmakuFontSizeOverride();
    }
  }

  /// 「多开时显示弹幕」开关：把各路弹幕显隐一起切。
  ///
  /// 关掉后 `addDanmaku` 直接提前返回，弹幕集合保持为空、ticker 近乎免费——比
  /// `Offstage` 有效（`Offstage` 不会停 Ticker）。
  void setTileDanmakuVisible(bool value) {
    AppSettingsController.instance.setMultiPlayTileDanmaku(value);
    for (final tile in slots) {
      tile.showDanmakuState.value =
          value && AppSettingsController.instance.danmuEnable.value;
    }
  }

  /// 页面退出：摘掉全部副格并恢复常规窗口下限。
  ///
  /// 不能指望 GetX 自动回收：副格是手工 `Get.put(tag:)` 注册的，路由 pop 只会
  /// 销毁路由绑定里的主格，副格会连播放器一起泄漏。
  void dispose() {
    final tiles = slots.where((t) => t != page).toList();
    for (final tile in tiles) {
      Get.delete<LiveRoomController>(tag: tile.getxTag);
      slots.remove(tile);
    }
    focusedSlot.value = 0;
    unawaited(refreshWindowFloor());
  }

  /// 退出多开时把弹幕口径交还给单画面：字号交还「按整窗高度缩放」，
  /// 显隐交还全局「弹幕」设置。
  ///
  /// 这条**没有平台门**（2026-10-04 从 [refreshWindowFloor] 里拆出来）：原来它躲在
  /// 那句桌面守卫后面，于是移动端多开一退出，主格的弹幕会永远停在格子字号，
  /// 「各格显示弹幕」关着时甚至一直没弹幕。窗口那两段才是真·桌面专属。
  void restoreTileDanmakuOwnership() {
    if (isActive) {
      return;
    }
    clearTileDanmakuFonts();
    // 主格的弹幕显隐也交还给全局「弹幕」设置：不然「各格显示弹幕」关着时
    // 退出多开，单画面会一直没弹幕。只在「确实退出过多种布局」时写，单画面
    // 关闭页面这条路径不该顺手动它（保持单画面逐位不变）。
    if (enabled.value) {
      page.showDanmakuState.value =
          AppSettingsController.instance.danmuEnable.value;
    }
  }

  /// 重算并施加多开态窗口下限（多路时）或恢复常规下限（回到单路时）。
  ///
  /// `setMinimumSize` 不会把已经更小的窗口撑大，所以小于下限时要自己 setSize；
  /// 多开前的尺寸另存一份，退出多开时还原（`WindowService` 在多开期间不落盘窗口尺寸，
  /// 所以还原动作本身不会被记成用户偏好）。
  ///
  /// ⚠️ 全屏态下**一概不摆窗口几何**（小窗 implies `fullScreenState==true`，一并覆盖）：
  /// 那两种态的几何归「进入时采的还原点」管（`exitFull`/`exitSmallWindow` 消费
  /// `_lastWindowSize`）。在这里 `setSize` 只会把 OS 全屏窗改小——window_manager 的
  /// `setBounds` 就是一次 `SetWindowPos`，既不退全屏也不动 C++ 侧
  /// `g_is_window_fullscreen`——于是窗口缩回多开前尺寸、Dart 侧 `fullScreenState`
  /// 仍是 true，界面停在「在全屏、画面却不全屏」的半态里；采集同理，全屏期
  /// `getSize` 返回的是显示器矩形，存下来当还原点，退成窗口态后会把窗口撑满屏幕。
  Future<void> refreshWindowFloor() async {
    restoreTileDanmakuOwnership();
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    // 全屏/小窗态：几何归 OS 还原点。本方法只维护下限（`setMinimumSize` 只存值、
    // 不碰摆放），不采也不摆尺寸。
    final osOwnsGeometry = page.fullScreenState.value;
    final window = WindowService.instance;
    if (!isActive) {
      await window.setMultiPlayMinimumSize(null);
      final restore = _preMultiPlaySize;
      _preMultiPlaySize = null;
      if (restore != null && !osOwnsGeometry) {
        await windowManager.setSize(restore);
      }
      return;
    }

    final minSize = requiredMinimumWindowSize();
    if (!osOwnsGeometry) {
      _preMultiPlaySize ??= await windowManager.getSize();
    }
    await window.setMultiPlayMinimumSize(minSize);
    if (osOwnsGeometry) {
      return;
    }

    final current = await windowManager.getSize();
    final width = current.width < minSize.width ? minSize.width : current.width;
    final height = current.height < minSize.height ? minSize.height : current.height;
    if (width != current.width || height != current.height) {
      Log.i("多开播放：窗口放大到 ${width}x$height（下限 ${minSize.width}x${minSize.height}）");
      await windowManager.setSize(Size(width, height));
    }
  }

  /// 当前路数下不折叠所需的窗口下限，且不低于常规下限。
  ///
  /// 右侧 chrome 按**实际**侧栏宽度算（收起时为 0，展开时还要带上分隔条）：
  /// 侧栏可拖拽后它不再是 [kMultiPlayChromeWidth] 那个定值，继续写死会在
  /// 侧栏拖宽时算出偏小的下限、拖窄或收起时白占一截。
  Size requiredMinimumWindowSize() {
    final settings = AppSettingsController.instance;
    final chromeWidth =
        settings.roomSidebarCollapsed.value ? 0.0 : settings.roomSidebarWidth.value + kLiveRoomSidebarHandleWidth;
    final layout = resolveMultiPlayMinimumWindowSize(
      roomCount: slots.length,
      tileAspect: tileAspect(),
      chromeWidth: chromeWidth,
      chromeHeight: kMultiPlayChromeHeight,
    );
    final normal = WindowService.instance.normalMinimumSize;
    return Size(
      layout.width < normal.width ? normal.width : layout.width,
      layout.height < normal.height ? normal.height : layout.height,
    );
  }

  /// 喂给布局引擎的显示比例：取各格里**最宽**的那个。
  ///
  /// 每格按**自己的 effectiveScaleMode** 推导（按格覆盖优先，否则读全局），而非统一读全局——
  /// 现在一格能把画面尺寸单独改掉，窗口下限就得按它真实显示的比例算，否则可能按旧的全局比例
  /// 定出一个偏低/偏高的下限。自定义比例(5)的宽:高仍是全局值，按格只覆盖模式。
  /// 取最大值而不是「聚焦格的比例」，是为了让窗口下限与焦点无关：否则切到一个竖屏格时
  /// 布局会按新比例重排、而下限还是旧比例算的，窗口可能低于新下限、白折几格。
  double tileAspect() {
    var aspect = 0.0;
    for (final tile in slots) {
      final state = tile.player.state;
      final value = PipAspectCalculator.resolveDisplayAspect(
        scaleMode: tile.effectiveScaleMode,
        aspectByUser: AppSettingsController.instance.aspectByUser.value,
        videoWidth: state.width?.toDouble(),
        videoHeight: state.height?.toDouble(),
      );
      if (value.isFinite && value > aspect) {
        aspect = value;
      }
    }
    return aspect > 0 ? aspect : PipAspectCalculator.fallbackAspect;
  }
}

/// 换台下拉里的一项：一路正在直播的关注主播 + 它当前占着哪一格。
class MultiPlaySwitchEntry {
  const MultiPlaySwitchEntry({
    required this.user,
    required this.platform,
    required this.playingSlot,
  });

  final FollowUser user;

  /// 平台显示名（跟主播名一起显示，方便认人）。
  final String platform;

  /// 已在本会话某格里播放时的槽位下标；-1 = 没在播。
  final int playingSlot;

  bool get isPlaying => playingSlot >= 0;
}
