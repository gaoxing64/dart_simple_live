import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/sandbox.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_block.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/danmaku_merge_plan.dart';
import 'package:simple_live_app/modules/live_room/player/danmaku_emoticon.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_session.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_volume.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/live_room_route_args.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_block_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/history_service.dart';
import 'package:simple_live_app/services/playback/live_playback_audio_handler.dart';
import 'package:simple_live_app/services/playback/live_playback_target.dart';
import 'package:simple_live_app/services/screen_awake_service.dart';
import 'package:simple_live_app/services/stream_relay/stream_relay_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class LiveRoomController extends PlayerController
    with WidgetsBindingObserver
    implements LivePlaybackTarget {
  StreamSubscription<dynamic>? subscription;
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  late DanmakuMask rustDanmakuMask;

  List<LiveMessage> danmakuBuffer = [];
  Timer? danmakuTimer;
  bool _isProcessingBuffer = false;

  /// 合并模式展示项：key = Rust 归一化文本 -> 聊天区那条消息（原地更新「×N」）。
  /// 与 [danmakuBuffer] 同一生命周期，换台时清空。
  final Map<String, _DanmakuMergeEntry> _mergeEntries = {};

  /// 多开播放时本实例是「副格」而非页面主格。
  ///
  /// 副格只负责自己那一路的播放 / 弹幕 / 聊天，绝不碰窗口操作、SmartDialog 加载
  /// 浮层、自动关闭计时这些全 app 只有一份的东西——四路同时跑会互相打架。
  final bool isSecondaryTile;

  /// 多开时的槽位（0 = 主格）。用于弹幕定时器错峰与日志区分。
  final int tileSlot;

  /// 批量入口预载的其余几路（不含自己）。只有主格会消费它。
  final List<LiveRoomTarget> together;

  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
    this.isSecondaryTile = false,
    this.tileSlot = 0,
    this.together = const [],
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  /// 历史记录 / 关注记录的 id。
  String get historyId => "${site.id}_$roomId";

  /// 每格的身份编号：只用于 GetX 的注册 tag 与网格 key，**与房间无关**。
  ///
  /// 全局单调 + `late final` 懒分配：首次访问取号、之后永不变。
  /// 不能用 [historyId] 派生——换台（[resetRoom]）会改掉它的值，而实例仍注册在旧
  /// tag 下，`Get.delete` 会静默返回 false，那一格的播放器与弹幕 WS 就泄漏了
  /// （而且还在出声），连关掉直播间页都回收不了。
  static int _tileSeq = 0;
  late final int tileId = ++_tileSeq;

  /// 多开时注册进 GetX 用的 tag。
  ///
  /// 主格走路由绑定的无 tag 注册；副格必须带 tag——fork 的 get 不会覆盖已存活实例，
  /// 不带 tag 时第二个直播间会静默复用第一个的播放器。
  /// 用 [tileId] 而不是房间，保证换台后 tag 不变、销得掉。
  String get getxTag => "multi_tile_$tileId";

  @override
  bool get multiPlayActive => multiPlay.isActive;

  @override
  bool get allowsWindowOps => !isSecondaryTile;

  /// 这一路相对基准音量的系数（0~1）。1 = 按焦点（及可选压低）规则算出来的值，0 = 静音。
  ///
  /// 格子底栏的音量按钮改的就是它：点一下在 0 与上次的值之间切换，滚轮悬停微调。
  /// 让用户能对「这一路」做细调（两路都听得见时把吵的那路再压低；或从静音慢慢加上来）。
  final RxDouble volumeFactor = 1.0.obs;

  /// 这一格的画面尺寸覆盖值；null ＝跟随全局设置。
  ///
  /// 会话级、不落盘：格子是临时身份（换台会换房间、关一格就散），存下来下一次
  /// 对不上号反而更困惑。新加入的一路继承全局设置。
  /// 自定义比例的宽:高仍然是全局值，按格只覆盖模式。
  final RxnInt scaleModeOverride = RxnInt();

  int get effectiveScaleMode => scaleModeOverride.value ?? AppSettingsController.instance.scaleMode.value;

  @override
  int effectiveScaleModeForFit() => effectiveScaleMode;

  /// 由格子的画面尺寸菜单调用：改完立刻下发到这一格的 `Video`。
  void setTileScaleMode(int mode) {
    scaleModeOverride.value = mode;
    updateScaleMode();
  }

  /// 静音前的系数，取消静音时还原。
  double _factorBeforeMute = 1.0;

  bool get muted => volumeFactor.value <= 0.001;

  void toggleMute() {
    if (muted) {
      volumeFactor.value = _factorBeforeMute > 0.001 ? _factorBeforeMute : 1.0;
    } else {
      _factorBeforeMute = volumeFactor.value;
      volumeFactor.value = 0;
    }
    applyTargetVolume();
  }

  /// 滚轮微调这一路的音量系数（[delta] 如 ±0.05）。
  void nudgeVolumeFactor(double delta) {
    final next = (volumeFactor.value + delta).clamp(0.0, 1.0);
    if (next == volumeFactor.value) {
      return;
    }
    volumeFactor.value = next;
    if (next > 0.001) {
      _factorBeforeMute = next;
    }
    applyTargetVolume();
  }

  /// 本路此刻该给多大音量：见 `resolveTileVolume`。
  @override
  double resolveTargetVolume() {
    final settings = AppSettingsController.instance;
    return resolveTileVolume(
      master: settings.playerVolume.value,
      duckEnabled: settings.multiPlayDuckEnabled.value,
      duckRatio: settings.multiPlayDuckVolume.value,
      factor: volumeFactor.value,
      focused: !multiPlay.isActive || multiPlay.focused == this,
    );
  }

  @override
  String get playerTitle =>
      isSecondaryTile ? "Slive Player · 第${tileSlot + 1}路" : "Slive Player";

  /// 副格用设置项压低缓存上限：四路各 32MiB 起步对弱机不友好。
  ///
  /// 注意 `Player` 只构造一次，改了设置要重进直播间才生效。
  @override
  int get playerBufferSize => isSecondaryTile
      ? AppSettingsController.instance.multiPlayTileBufferSize.value * 1024 * 1024
      : super.playerBufferSize;

  /// Twitch 的 mpv 前向预读秒数（`cache-secs`）。
  ///
  /// 依据是**外部事实**：Twitch 的 HLS 按 2 秒切片（分片时长是平台投放配置，
  /// 本仓库不可验证），1 秒预读连一个完整分片都覆盖不住，网络稍抖即卡。
  /// 10 ≈ 5 个分片的容错带。
  ///
  /// 代价必须写明白：mpv 对直播会尽量维持 `cache-secs` 的前向水位，
  /// 这 10 秒**直接变成画面延迟**——相对其他站点（1/3 秒），Twitch 的视频
  /// 会比弹幕/聊天慢约 10 秒。这是按站点刻意做的「流畅优先」取舍；
  /// 若日后要降到 4~6 或做成设置项，那是产品决定，别在这里顺手改数。
  static const int kTwitchPlayerCacheSecs = 10;

  @override
  int resolvePlayerCacheSecs(bool doubleBuffering) {
    if (site.id == Constant.kTwitch) {
      return kTwitchPlayerCacheSecs;
    }
    return super.resolvePlayerCacheSecs(doubleBuffering);
  }

  /// 页面各区块要跟随的那一路：多开时是聚焦格，单画面时就是自己。
  ///
  /// 页面里读「当前房间」的地方都走这个 getter。因为里面读了 focusedSlot，
  /// `Obx` 会自动订阅它，切焦点时聊天区自己重建，不需要手动 update。
  LiveRoomController get focused => multiPlay.focused;

  MultiPlaySession? _hostSession;

  /// 我归属的多开会话。
  ///
  /// 主格惰性建自己那份；副格由 [MultiPlaySession.addRoom] 回填成页面主格那个。
  /// 必须回填：副格若查自己那份「单人会话」，`isActive` 恒为 false，音量判定就会
  /// 得出「没在多开」的结论——结果开了压低时副格不被压低而主格会，两路音量在
  /// 「一样大」和「差 10dB」之间随焦点乱跳。
  MultiPlaySession get multiPlay => _hostSession ??= MultiPlaySession(this);

  /// 由会话在创建副格时回填归属。
  void attachHostSession(MultiPlaySession session) {
    _hostSession = session;
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 当前直播间屏蔽项
  Rx<FollowUserBlock?> followUserBlock = Rx<FollowUserBlock?>(null);

  /// 清晰度数据
  RxList<LivePlayQuality> qualities = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  /// 下发给播放器的地址（与 [playUrls] 一一对应）。
  ///
  /// 斗鱼的直链带 300 秒硬寿命，由 [buildPlayerUrls] 替换为本地续流中转地址，
  /// 播放器实际拉的是中转流；[playUrls] 始终保留真实直链，供线路列表展示与
  /// 复制链接使用。
  List<String> playerUrls = [];

  /// 每条线路的续流上下文（与 [playUrls] 一一对应），平台不支持续流时为 null。
  ///
  /// 与 DTV 同构：这里只登记「房间 + 清晰度 + 线路 + 取流入口」，中转到期时
  /// 自己调 core 重新取流。Rust 化后 core 不再产出 `LivePlayUrl.renewers`（O-7）。
  List<StreamRenewContext>? _playUrlRenewContexts;

  /// 本控制器登记的续流会话（本地中转地址），换流与销毁时统一回收。
  final List<String> _relaySessions = [];

  /// 续流会话的代次：并发刷新时只认最后一次，作废的那批立即回收。
  int _relayGeneration = 0;

  /// 清晰度/线路动作「是否存在」的谓词：多于一路可选项才提供入口。
  ///
  /// WHY 收在 controller：`qualities.length > 1` 此前在桌面两条宿主、格子胶囊与页级
  /// 「更多」四个调用点各写一遍，改一处漏一处就会让「同一动作在不同宿主有的有、
  /// 有的没有」这个本次要消灭的问题重新长回来。注意这比 spec §9 的
  /// 「无数据」措辞更严——只有一档也算「无可切换」，行/按钮同样不提供，
  /// 这是既有出货行为，保持不变。
  bool get hasMultipleQualities => qualities.length > 1;

  bool get hasMultipleLines => playUrls.length > 1;

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 聊天栏平滑滚底的节流窗口（见 [chatScrollToBottom]）。
  Timer? _chatScrollTimer;
  bool _chatScrollPending = false;

  /// 上滑暂停跟随后，手动滑回底部并停手时的恢复倒计时（见 [_scheduleChatFollowResume]）。
  Timer? _chatFollowResumeTimer;

  /// 已经播过入场动画的消息（按对象身份记账）。
  ///
  /// 列表项滑出屏幕会被回收，重建时不能重播；超过消息上限两倍时剔除已离场
  /// 的对象，长时观看不会无限增长。
  final Set<LiveMessage> _chatEntrancePlayed = {};

  /// 最近一次聊天列表的滚动位置。
  ///
  /// 列表挂载位置会在全屏/换布局时被整棵摘掉重建，而它没有 PageStorageKey，
  /// 新 ScrollPosition 会从 0 起；上滑看历史时用这个值把位置接回去。
  double? _lastChatScrollOffset;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Error? error;

  int _count = 0;

  final int _kMaxChatMessageCount = 150;

  /// 滚底动画与节流窗口都取 500ms：一个窗口恰好跑完一段动画，刷屏时
  /// 画面是连续的，而不是每来一条就打断上一次缓动从头再跑。
  static const Duration _kChatScrollDuration = Duration(milliseconds: 500);
  static const Duration _kChatScrollThrottle = Duration(milliseconds: 500);

  /// 滑到底部后静止这么久就恢复「跟随最新」，期间再滚动一次就重新计时。
  static const Duration _kChatFollowResumeDelay = Duration(seconds: 1);

  /// 「已在底部」的判定容差（逻辑像素）：吸收亚像素舍入，贴底时不会因浮点误差判成未到底。
  static const double _kChatBottomTolerance = 1.0;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    // 播放事件 → 系统媒体控制（通知栏/锁屏/耳机键）的那条订阅。
    initBackgroundPlayback();
    // 起播即持有屏幕常亮，暂停/停止/关房/直播结束才释放（见 [ScreenAwakeService]）。
    initScreenAwake();
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    // 自动关闭会 exit(0) 并弹确认框，只能由页面主格管；副格跑了就是四份倒计时
    if (!isSecondaryTile) {
      initAutoExit();
    }
    // 副格的弹幕还要看「多开时显示弹幕」设置：关掉后 addDanmaku 直接提前返回，
    // 弹幕集合保持为空、ticker 近乎免费（Offstage 是停不了 Ticker 的）。
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value &&
        (!isSecondaryTile || AppSettingsController.instance.multiPlayTileDanmaku.value);
    followed.value = FollowService.instance.getFollowExist(historyId);
    // 解冻：更新 lastWatchTime 并从休眠列表移除
    FollowService.instance.resumeUser(historyId);
    loadData();

    scrollController.addListener(scrollListener);
    // 这个字号是 WindowService 按**整窗高度**算出来的，多开时每格高度都不同，
    // 只该由主格在单画面下消费；多开的字号走 MultiPlaySession 的按格缩放。
    if (!isSecondaryTile) {
      subscription = EventBus.instance.listen(Constant.kUpdateDanmaku, (data) {
        // 多开时主格也只是其中一格，按整窗算出来的值会让它比其他格大一大截
        // （「弹幕跟随窗口缩放」开着时尤其明显），必须让位给按格字号。
        if (multiPlay.isActive) {
          return;
        }
        if (danmakuController?.option.fontSize != data as double) {
          updateDanmuOption(danmakuController?.option.copyWith(fontSize: data));
        }
      });
    }
    _initDanmakuMask();
    DanmakuEmoticonRenderer.acquireCache();
    super.onInit();
    // 批量入口预载的其余几路。放在 super.onInit() 之后，避免建格跟主格自己的初始化
    // 抢顺序（此时播放器与弹幕 WS 都已就位）。
    if (together.isNotEmpty) {
      // 移动端以前在这里被静默丢掉（关注页那颗按钮没有平台门，选 5 个只开第 1 路、
      // 还不提示）。视频区的平台门拆掉之后，批量入口在手机上是真的了。
      multiPlay.addRooms(together);
    }
  }

  void _initDanmakuMask() {
    rustDanmakuMask = DanmakuMask(
      baseWindowMs: AppSettingsController.instance.danmuWindowMs.value * 1000,
      bucketCount: AppSettingsController.instance.danmuWindowMs.value,
      useNormalization: AppSettingsController.instance.danmuTextNormalization.value,
      useFrequencyControl: AppSettingsController.instance.danmuFrequencyControl.value,
      maxFrequency: AppSettingsController.instance.danmuMaxFrequency.value,
    );
    danmakuTimer = Timer.periodic(
      // 多开时按槽位错峰：每 500ms 每个房间各有一次同步 FFI 的 allowListBatch 与一次
      // messages 追加，四路同相位会把它们挤在同一帧上。
      Duration(milliseconds: 500 + tileSlot * 125),
      (timer) {
        _processDanmakuBuffer();
        // sc同步计时调用 先刷后删
        _count = (_count + 1) % 2;
        if (_count == 0) {
          superChats.refresh();
          removeSuperChats();
        }
      },
    );
  }

  // 缓存降低跨线程消息开销 估算弹幕延迟在800ms左右
  void _processDanmakuBuffer() async {
    if (_isProcessingBuffer) return;
    if (danmakuBuffer.isEmpty) return;

    _isProcessingBuffer = true;
    try {
      final batch = List<LiveMessage>.from(danmakuBuffer);
      danmakuBuffer.clear();

      final batchMessages = batch.map((e) => e.message).toList();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 合并模式：不丢弹幕，窗口内的重复聚成一条并显示计数（保留热闹氛围）。
      // 与屏蔽模式共用同一套窗口计数，按批二选一调用。
      if (AppSettingsController.instance.danmakuMergeEnable.value) {
        final groups = await rustDanmakuMask.mergeListBatch(
          texts: batchMessages,
          nowMs: BigInt.from(nowMs),
        );
        _applyDanmakuMerge(batch, groups);
        return;
      }

      final allowedResults = await rustDanmakuMask.allowListBatch(texts: batchMessages, nowMs: BigInt.from(nowMs));

      final filteredBatch = <LiveMessage>[];
      for (int i = 0; i < batch.length; i++) {
        if (allowedResults[i] == 1) {
          filteredBatch.add(batch[i]);
        }
      }

      if (filteredBatch.isEmpty) return;

      messages.addAll(filteredBatch);
      if (messages.length > _kMaxChatMessageCount && !disableAutoScroll.value) {
        messages.removeRange(0, messages.length - _kMaxChatMessageCount);
      }

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku(filteredBatch
          .map((msg) => DanmakuContentItem(
                msg.message,
                color: Color.fromARGB(
                  255,
                  msg.color.r,
                  msg.color.g,
                  msg.color.b,
                ),
                // 表情包（目前仅 B 站下发）：交给渲染层把 [占位符] 换成图片
                extra: msg.emoticons,
              ))
          .toList());
    } finally {
      _isProcessingBuffer = false;
    }
  }

  /// 合并模式落地：新组新建展示项（聊天区 + 飘屏一次），老组只原地更新计数。
  ///
  /// 飘屏库（canvas_danmaku）没有「更新已发射项」的能力，×N 只能在发射那一刻
  /// 定稿：同批到达的重复一次性显示最终计数，后续批次只增长聊天区的「×N」，
  /// 不再补发飘屏——否则长刷屏会变成每 500ms 一条，比屏蔽模式更吵。
  void _applyDanmakuMerge(List<LiveMessage> batch, List<DanmakuMergeGroup> groups) {
    _pruneMergeEntries();

    final actions = planDanmakuMerge(
      batch: batch,
      groups: groups,
      lookup: (key) => _mergeEntries[key]?.message,
    );

    final newItems = <LiveMessage>[];
    final flyItems = <DanmakuContentItem>[];
    var touched = false;

    for (final action in actions) {
      switch (action) {
        case DanmakuMergeCreate():
          action.message.repeatCount = action.count;
          _mergeEntries[action.key] = _DanmakuMergeEntry(action.message);
          newItems.add(action.message);
          flyItems.add(
            DanmakuContentItem(
              danmakuMergeText(action.message.message, action.count),
              color: Color.fromARGB(
                255,
                action.message.color.r,
                action.message.color.g,
                action.message.color.b,
              ),
              extra: action.message.emoticons,
            ),
          );
          touched = true;
        case DanmakuMergeBump():
          final entry = _mergeEntries[action.key];
          if (entry == null) continue;
          entry.lastSeen = DateTime.now();
          entry.message.repeatCount = action.count;
          final index = messages.indexOf(entry.message);
          if (index < 0) continue;
          // 同一对象写回原位：RxList 通知重建，ValueKey 不变 ⇒ 这一行不会重放入场动画
          messages[index] = entry.message;
          touched = true;
        case DanmakuMergeSkip():
          break;
      }
    }

    if (!touched) return;

    if (newItems.isNotEmpty) {
      messages.addAll(newItems);
      if (messages.length > _kMaxChatMessageCount && !disableAutoScroll.value) {
        messages.removeRange(0, messages.length - _kMaxChatMessageCount);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => chatScrollToBottom(),
    );

    if (!liveStatus.value || isBackground) {
      return;
    }
    if (flyItems.isNotEmpty) {
      addDanmaku(flyItems);
    }
  }

  /// 清掉窗口外的展示项：Rust 侧计数已滑出窗口，不会再有 bump 命中它们。
  void _pruneMergeEntries() {
    final now = DateTime.now();
    final ttl = Duration(
      milliseconds: AppSettingsController.instance.danmuWindowMs.value * 1000 + 5000,
    );
    _mergeEntries.removeWhere((_, entry) => now.difference(entry.lastSeen) > ttl);
  }

  void scrollListener() {
    if (!scrollController.hasClients) {
      return;
    }
    final position = scrollController.position;
    _lastChatScrollOffset = position.pixels;
    final atBottom = position.extentAfter <= _kChatBottomTolerance;
    // 已经贴底时上滑不暂停跟随：`extentAfter` 只按剩余可滚距离判断，用户此时
    // 看到的仍是最新一条；这类「轻推一下就回弹」若切进暂停态，会出现按钮闪一下
    // 又被恢复计时器撤销的观感。
    if (position.userScrollDirection == ScrollDirection.forward && !atBottom) {
      disableAutoScroll.value = true;
    }
    if (disableAutoScroll.value) {
      _scheduleChatFollowResume(atBottom: atBottom);
    }
  }

  /// 上滑翻历史后，手动滑回底部并停手 [_kChatFollowResumeDelay] 就恢复跟随最新。
  ///
  /// 以前只有「最新」按钮能解除 [disableAutoScroll]，用户滑回底部后再来新消息
  /// 列表会停在原处。这里按「已到底 + 滚动静止」判定：每次滚动都重排倒计时，
  /// 因此计时从**最后一次**滚动开始算；期间到达的新消息不会取消它——人已经在
  /// 底部，意图就是继续跟最新。
  void _scheduleChatFollowResume({required bool atBottom}) {
    _cancelChatFollowResume();
    if (!atBottom) {
      return;
    }
    _startChatFollowResumeTimer();
  }

  void _startChatFollowResumeTimer() {
    _chatFollowResumeTimer = Timer(_kChatFollowResumeDelay, () {
      if (!disableAutoScroll.value || !scrollController.hasClients) {
        _chatFollowResumeTimer = null;
        return;
      }
      // 拖动或惯性还没停：再等一轮，别在用户手里抢滚动位置。按住不动时框架
      // 走 HoldScrollActivity（isScrolling 为 false），这里识别不到；那一瞬列表
      // 本就贴底，恢复也只会落回原位。
      if (scrollController.position.isScrollingNotifier.value) {
        _startChatFollowResumeTimer();
        return;
      }
      resumeChatFollow(animate: true);
    });
  }

  void _cancelChatFollowResume() {
    _chatFollowResumeTimer?.cancel();
    _chatFollowResumeTimer = null;
  }

  /// 立刻回到「跟随最新」：解除上滑暂停并落到底。
  ///
  /// 「最新」按钮与 [_startChatFollowResumeTimer] 共用这一条出口，避免两条
  /// 路径对「是否还排着恢复倒计时」各持一份判断。
  ///
  /// [animate] 默认 false（瞬移）：按钮可能要跨过上百条积压。自动恢复时用户
  /// 本就停在底部附近，交给平滑滚底更自然。
  void resumeChatFollow({bool animate = false}) {
    _cancelChatFollowResume();
    disableAutoScroll.value = false;
    chatScrollToBottom(animate: animate);
  }

  /// 聊天列表重新挂载（退出全屏、切换布局）时接回滚动位置。
  ///
  /// 全屏分支只保留视频区，聊天区整棵子树会被销毁；退出后新的 ScrollPosition
  /// 从 0 开始，若不补这一步就会停在最旧一条，直到下一条消息触发滚底。
  /// 仍处于「跟随最新」时直接落到底；上滑看历史时回到离开前的位置。
  void restoreChatScrollOnMount() {
    if (!scrollController.hasClients) {
      return;
    }
    if (!disableAutoScroll.value) {
      chatScrollToBottom(animate: false);
      return;
    }
    final offset = _lastChatScrollOffset;
    if (offset == null) {
      return;
    }
    scrollController.jumpTo(
      offset.clamp(0.0, scrollController.position.maxScrollExtent).toDouble(),
    );
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value = AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value = AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    // 定时关闭是**会话级**：倒计时归页面主格一份，退出时 exit(0) 收整个 app。
    // 副格碰它就是第二份倒计时 + 第二个 exit(0)，而且用户看到的「还剩几分钟」
    // 会和主格那份对不上。这道门与 [onInit] 里 `!isSecondaryTile` 那道同源，
    // 放在这里是因为 [showAutoExitSheet] 也可能被副格的入口触发。
    if (isSecondaryTile) {
      return;
    }
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer = Timer(const Duration(seconds: 10), () async {
          await ScreenAwakeService.instance.releaseAll();
          exit(0);
        });
        autoExitTimer?.cancel();
        // 多开时把「关的是几路」讲清楚：到点退的是整个 app，不只是当前这一格。
        final routes = multiPlay.isActive ? multiPlay.slots.length : 0;
        var delay = await Utils.showAlertDialog(
          routes > 1 ? "定时关闭已到时，将关闭全部 $routes 路播放，是否延迟关闭?" : "定时关闭已到时,是否延迟关闭?",
          title: "延迟关闭", confirm: "延迟", cancel: "关闭", selectable: true);
        if (delay) {
          timer.cancel();
          delayAutoExit.value = true;
          showAutoExitSheet();
          setAutoExit();
        } else {
          delayAutoExit.value = false;
          // 到点直接退 app：先把会话收干净，否则 exit(0) 之前那几路解码器
          // 还占着资源，也会让「关掉之后播放器仍在响」这种观测混进崩溃日志。
          multiPlay.dispose();
          await ScreenAwakeService.instance.releaseAll();
          exit(0);
        }
      }
    });
  }
  // 弹窗逻辑

  void refreshRoom() {
    //messages.clear();
    superChats.clear();
    liveDanmaku.stop();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  ///
  /// 用动画而不是 jumpTo：一次到一批消息时列表是滑上去的，已有内容不会
  /// 整块瞬移。刷屏时按 [_kChatScrollThrottle] 节流，窗口结束时若还有积压
  /// 再补滚一次，保证最后一批也落在视野里。
  ///
  /// [animate] 为 false 时直接跳到底，给「最新」按钮用：积压可能上百条，
  /// 500ms 划过整段历史只会看到一片模糊；新到消息仍走动画。
  void chatScrollToBottom({bool animate = true}) {
    if (!scrollController.hasClients || disableAutoScroll.value) {
      return;
    }
    // 设置里关掉聊天动画时回到旧行为：一次跳到底，不做节流与补滚。
    if (!animate || !AppSettingsController.instance.chatAnimationEnable.value) {
      _chatScrollTimer?.cancel();
      _chatScrollTimer = null;
      _chatScrollPending = false;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      return;
    }
    if (_chatScrollTimer != null) {
      _chatScrollPending = true;
      return;
    }
    _chatScrollTimer = Timer(_kChatScrollThrottle, () {
      _chatScrollTimer = null;
      if (!_chatScrollPending) {
        return;
      }
      _chatScrollPending = false;
      chatScrollToBottom();
    });
    unawaited(
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: _kChatScrollDuration,
        curve: Curves.linearToEaseOut,
      ),
    );
  }

  /// 消费一条消息的入场动画名额：第一次返回 true，之后同一条消息因列表项
  /// 回收/重建再次取用都返回 false。
  ///
  /// 上滑翻历史（[disableAutoScroll]）时不播动画，但照样记账，回看旧消息
  /// 不会一片闪动。
  bool claimChatMessageEntrance(LiveMessage message) {
    if (!_chatEntrancePlayed.add(message)) {
      return false;
    }
    if (_chatEntrancePlayed.length > _kMaxChatMessageCount * 2) {
      _chatEntrancePlayed.removeWhere((e) => !messages.contains(e));
    }
    return !disableAutoScroll.value;
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) async {
    if (msg.type == LiveMessageType.chat) {
      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      // 当前直播间关键词屏蔽检查
      for (var keyword in followUserBlock.value!.blockWords) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽${site.id}_$roomId消息内容：${msg.message}");
          return;
        }
      }
      // 当前直播间发言用户屏蔽
      // todo: 更精细化的uid匹配
      var accountInBlock = followUserBlock.value!.blockAccounts.any((item) => item.name == msg.userName);
      if (accountInBlock) {
        return;
      }

      // 弹幕去重（Rust DanmakuMask，每 500ms 批量判定）：开启即全量生效。
      // 早期的"前 50 条跳过去重"热身门槛是 Dart 逐条同步实现防开屏卡 UI 的遗留，
      // Rust FFI 批量判定无此顾虑，且进房历史弹幕回放恰是最需要去重的场景。
      if (AppSettingsController.instance.danmakuMaskEnable.value) {
        danmakuBuffer.add(msg);
      } else {
        if (messages.length > _kMaxChatMessageCount && !disableAutoScroll.value) {
          messages.removeAt(0);
        }
        messages.add(msg);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => chatScrollToBottom(),
        );
        if (!liveStatus.value || isBackground) {
          return;
        }

        addDanmaku([
          DanmakuContentItem(
            msg.message,
            color: Color.fromARGB(
              255,
              msg.color.r,
              msg.color.g,
              msg.color.b,
            ),
            // 表情包（目前仅 B 站下发）：交给渲染层把 [占位符] 换成图片
            extra: msg.emoticons,
          ),
        ]);
      }
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      // set newest sc at the top， limit 20 better I think
      // unique ensures from front
      // 没想到 huya-data居然会有时间戳不准的问题
      LiveSuperChatMessage scData = msg.data;
      bool contain = superChats.any(
        (s) => s.price == scData.price && s.userName == scData.userName && s.message == scData.message,
      );
      if (!contain) {
        superChats.insert(0, msg.data);
        if (superChats.length > 20) {
          superChats.removeRange(20, superChats.length);
        }
      }
    }
  }

  /// 添加当前房间屏蔽词
  void addCurBlockWord(String word) {
    // 为剥离getx做准备
    if (!followUserBlock.value!.blockWords.contains(word) && word != "") {
      followUserBlock.value!.blockWords.add(word);
      FollowBlockService.instance.addBlockWord(siteId: site.id, roomId: roomId, word: word);
      followUserBlock.refresh();
    }
    SmartDialog.showToast("已屏蔽词:$word");
  }

  void delCurBlockWord(String word) {
    if (followUserBlock.value!.blockWords.contains(word)) {
      followUserBlock.value!.blockWords.remove(word);
      FollowBlockService.instance.removeBlockWord(siteId: site.id, roomId: roomId, word: word);
      followUserBlock.refresh();
    }
  }

  /// 添加当前房间屏蔽用户
  void addCurBlockAccount(String accName) {
    bool exists = followUserBlock.value!.blockAccounts.any((acc) => acc.name == accName);
    if (!exists && accName != "") {
      //todo: temp use uid == 0
      var accInMessage = messages.firstWhereOrNull((e) => e.userName == accName);
      var accId = accInMessage?.userId ?? "0";
      var acc = FollowUserBlockAccount(uid: accId, name: accName);
      followUserBlock.value!.blockAccounts.add(acc);
      FollowBlockService.instance.addBlockAccount(siteId: site.id, roomId: roomId, account: acc);
      followUserBlock.refresh();
    }
    SmartDialog.showToast("已屏蔽用户:$accName");
  }

  void delCurBlockAccount(String accName) {
    bool exists = followUserBlock.value!.blockAccounts.any((acc) => acc.name == accName);
    if (exists) {
      followUserBlock.value!.blockAccounts.removeWhere((e) => e.name == accName);
      FollowBlockService.instance.removeBlockAccount(siteId: site.id, roomId: roomId, name: accName);
      followUserBlock.refresh();
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    // 多开时主格也只是其中一格：整窗加载浮层会盖住棋盘，交给格子自身的进度指示。
    final ownsLoading = !isSecondaryTile && !multiPlay.isActive;
    try {
      if (ownsLoading) {
        SmartDialog.showLoading(msg: "");
      }
      loadError.value = false;
      addSysMsg("正在读取直播间信息");
      // 本次加载针对哪一路；换台时上一次的请求可能更晚落地
      final target = roomId;
      detail.value = await site.liveSite.getRoomDetail(roomId: target);
      // 世代守卫：换台后旧请求晚到会把上一路的标题/封面/在线数盖到新房间上。
      // 只认最后一次发起的那个（注意要放在下面抖音改写 roomId 之前判断，
      // 否则会被那个改写误伤）。
      if (roomId != target) {
        return;
      }

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      addHistory();
      // 确认房间关注状态
      followed.value = FollowService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      followUserBlock.value = FollowBlockService.instance.getBlock(siteId: site.id, roomId: roomId);
      // 标题/封面/主播名刚就位，马上刷一次通知：直播流稳定时 playing/buffering
      // 可以很久不跳，等事件的话用户看到的会一直是上一路的元数据。
      syncBackgroundPlayback();
      if (liveStatus.value) {
        getSuperChatMessage();
        getPlayQualities();
        addSysMsg("开始连接弹幕服务器");
        initDanmau();
        liveDanmaku.start(detail.value?.danmakuData);
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
    } catch (e) {
      Log.logPrint(e);
      //SmartDialog.showToast(e.toString());
      loadError.value = true;
      if (e is Error) {
        error = e;
      }
    } finally {
      if (ownsLoading) {
        SmartDialog.dismiss(status: SmartStatus.loading);
      }
    }
  }

  /// 聊天区当前页码（0 聊天 / 1 SC / 2 关注 / 3 设置）。
  ///
  /// 挂在**页面主格**而不是聚焦格上：`_ChatTabs` 是页面级 UI，快捷键也认这个对象，
  /// 两边共用一份才不会各读各的。放在这里而不是页面 state 里，是因为直播间页的
  /// 聊天区会被多开的悬浮抽屉重建，重建时要能从这儿接回上次停在哪个 Tab。
  final chatTab = 0.obs;

  /// [chatTab] 里「关注」那一页的下标。快捷键 G 与 `_ChatTabs` 都引用它，
  /// 免得两处各自数 Tab 顺序。
  static const int kChatTabFollow = 2;

  /// 初始化播放器
  void getPlayQualities() async {
    currentQuality = -1;

    try {
      var playQualities = await site.liveSite.getPlayQualities(detail: detail.value!);

      if (playQualities.isEmpty) {
        SmartDialog.showToast("无法读取播放清晰度");
        return;
      }
      qualities.assignAll(playQualities);
      var qualityLevel = await getQualityLevel();
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualities.length - 1;
      } else {
        //中间值
        int middle = (playQualities.length / 2).floor();
        currentQuality = middle;
      }
      await getPlayUrl();
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放清晰度");
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel = AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  Future<void> getPlayUrl() async {
    currentQualityInfo.value = qualities[currentQuality].quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    var playUrl = await site.liveSite.getPlayUrls(detail: detail.value!, quality: qualities[currentQuality]);
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    playUrls.assignAll(playUrl.urls); // 深拷贝
    playHeaders = playUrl.headers;
    _playUrlRenewContexts = _buildRenewContexts();
    currentLineIndex = 0;
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    //重置错误次数
    mediaErrorRetryCount = 0;
    initPlaylist();
  }

  /// 斗鱼直链 300 秒后会被 CDN 主动断开，为每条线路登记续流上下文，
  /// 交给中转在到期前自行重取；其余平台不经过中转。
  List<StreamRenewContext>? _buildRenewContexts() {
    if (site.id != Constant.kDouyu) {
      return null;
    }
    final roomDetail = detail.value!;
    final quality = qualities[currentQuality];
    return List.generate(playUrls.length, (line) {
      return StreamRenewContext(
        roomId: roomDetail.roomId,
        quality: quality.quality,
        line: line,
        fetchUrls: () async {
          final fresh = await site.liveSite.getPlayUrls(
            detail: roomDetail,
            quality: quality,
          );
          return fresh.urls;
        },
      );
    });
  }

  void changePlayLine(int index) {
    currentLineIndex = index;
    //重置错误次数
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  void initPlaylist() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    // 斗鱼等平台的直链带硬性寿命（300 秒后 CDN 主动断开），先包一层本地
    // 续流中转，把「每 5 分钟断一次」变成一条对播放器不中断的流。
    await buildPlayerUrls();

    final mediaList = playerUrls.map((url) {
      if (StreamRelayService.instance.isRelayUrl(url)) {
        // 中转地址是本地 http：不参与「强制 https」改写，也不带平台防盗链头
        //（这些请求头由中转服务补在上游连接上）。
        return Media(url);
      }
      var finalUrl = url;
      if (AppSettingsController.instance.playerForceHttps.value) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      return Media(finalUrl, httpHeaders: playHeaders);
    }).toList();

    // 初始化播放器并设置 ao 参数
    await initializePlayer();

    await player.open(Playlist(mediaList));
    // 换台抑制位在这里解开（流的起点 = 新房间元数据的起点），并把通知重新挂上。
    // 此刻 playing 还是 false，所以只会发布元数据，不会去拉前台服务。
    _bgSuppressed = false;
    syncBackgroundPlayback();
  }

  /// 刷新 [playerUrls]：可续流的线路替换为本地中转地址，其余保持直链。
  ///
  /// 中转起不来的单条线路直接退回直链——最坏结果只是断流问题照旧，
  /// 不影响这次播放。
  Future<void> buildPlayerUrls() async {
    final generation = ++_relayGeneration;
    _releaseRelaySessions();

    final urls = List<String>.from(playUrls);
    playerUrls = urls;

    final renewContexts = _playUrlRenewContexts;
    if (renewContexts == null) {
      return;
    }

    final relay = StreamRelayService.instance;
    final forceHttps = AppSettingsController.instance.playerForceHttps.value;
    final registered = <String>[];
    for (var i = 0; i < urls.length && i < renewContexts.length; i++) {
      final renew = renewContexts[i];
      try {
        final upstreamUrl = forceHttps ? urls[i].replaceAll("http://", "https://") : urls[i];
        final localUrl = await relay.register(
          url: upstreamUrl,
          renew: renew,
          headers: playHeaders,
        );
        urls[i] = localUrl;
        registered.add(localUrl);
      } catch (e) {
        Log.logPrint(e);
      }
    }

    if (generation != _relayGeneration) {
      // 期间又刷新过一轮：这批会话已作废，立即回收避免泄漏。
      for (final url in registered) {
        relay.release(url);
      }
      return;
    }
    _relaySessions.addAll(registered);
  }

  /// 回收本控制器登记的续流会话（断开上游连接，释放端口资源）。
  ///
  /// 释放后播放器若还持着旧中转地址，请求会拿到 404，等同一次流结束，
  /// 走 [mediaEnd] 的正常重试路径。
  void _releaseRelaySessions() {
    for (final url in _relaySessions) {
      StreamRelayService.instance.release(url);
    }
    _relaySessions.clear();
  }

  void setPlayer() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    await player.jump(currentLineIndex);
  }

  @override
  void mediaEnd() async {
    super.mediaEnd();
    if (mediaErrorRetryCount < 2) {
      Log.d("播放结束，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        //延迟一秒再刷新
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      //刷新一次
      setPlayer();
      return;
    }

    Log.d("播放结束");
    // 遍历线路，如果全部链接都断开就是直播结束了
    if (playUrls.length - 1 == currentLineIndex) {
      liveStatus.value = false;
      // 直播确实结束：不再重连，这一路释放常亮（用户还可能盯着结束页看）。
      ScreenAwakeService.instance.release(this);
    } else {
      // 还有下一条线路：换线重连期间**不**释放常亮（见 ScreenAwakeService）。
      changePlayLine(currentLineIndex + 1);

      //setPlayer();
    }
  }

  int mediaErrorRetryCount = 0;
  @override
  void mediaError(String error) async {
    super.mediaEnd();
    if (mediaErrorRetryCount < 2) {
      Log.d("播放失败，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        //延迟一秒再刷新
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      //刷新一次
      setPlayer();
      return;
    }

    if (playUrls.length - 1 == currentLineIndex) {
      errorMsg.value = "播放失败";
      // 重试与换线都穷尽：这一路不会再有声画，释放常亮。
      ScreenAwakeService.instance.release(this);
      SmartDialog.showToast("播放失败:$error");
    } else {
      //currentLineIndex += 1;
      //setPlayer();
      changePlayLine(currentLineIndex + 1);
    }
  }

  /// 音量均衡滤波链不可用（播放内核未编译音频滤镜）时被回调。
  ///
  /// af 链失败后音频轨道已被 mpv 判死，播放器层清掉 `af` 不会自动恢复出声，
  /// 这里重连当前线路重新拉流。
  @override
  void onVolumeNormalizeUnavailable() {
    setPlayer();
  }

  /// 读取SC
  void getSuperChatMessage() async {
    try {
      var sc = await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      superChats.addAll(sc);
    } catch (e) {
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.removeWhere((x) => x.endTime.millisecondsSinceEpoch <= now);
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    History history = History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );
    HistoryService.instance.start(history);
  }

  /// 关注用户
  Future<void> followUser() async {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var historyDurationSec = HistoryService.instance.getHistoryDurationSec(followUserId: id);
    await FollowService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
        lastWatchTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        watchDurationSec: historyDurationSec,
      )
        ..liveStatus.value = liveStatus.value ? 2 : 1
        ..cover.value = detail.value?.cover ?? "",
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 打开当前主播详情页。
  ///
  /// 已关注时直接复用列表里的关注对象；未关注时用当前房间详情临时构造一份，
  /// 详情页会据 [FollowService.getFollowExist] 隐藏分组/备注/迁移等关注专属操作。
  void showAnchorDetail() {
    final info = detail.value;
    if (info == null) return;
    final id = "${site.id}_$roomId";
    final follow = DBService.instance.getFollow(id) ??
        FollowUser(
          id: id,
          roomId: roomId,
          siteId: site.id,
          userName: info.userName,
          face: info.userAvatar,
          addTime: DateTime.now(),
          watchDurationSec: HistoryService.instance.getHistoryDurationSec(
            followUserId: id,
          ),
          lastWatchTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
    follow
      ..userName = info.userName
      ..face = info.userAvatar
      ..liveStatus.value = liveStatus.value ? 2 : 1
      ..cover.value = info.cover
      ..title.value = info.title
      ..online.value = info.online;
    AppNavigator.toFollowInfo(follow);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    await FollowService.instance.removeFollowUser(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(text: detail.value!.url));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  Future<void> visitWebLive() async {
    Uri uri = Uri.parse(detail.value!.url);
    if (await canLaunchUrl(uri) || runningInSandbox()) {
      await launchUrl(uri);
    } else {
      throw '无法打开网页 $uri';
    }
  }

  /// 「弹幕设置」本体：底部抽屉与右侧抽屉两个容器共用这一份。容器按 surface 选、
  /// 不按平台选——桌面条带／⋮ 与移动横屏全屏开的都是右侧抽屉。
  ///
  /// WHY 共用而不是两处各写一份：和 `buildScaleModeRadioList` 同一个理由——两个
  /// 容器之间该只有容器之差，可「关键词屏蔽」这条入口原先只长在底部抽屉那一份里，
  /// 桌面改成右侧抽屉后等于把这条入口弄丢了（条带／⋮ 进弹幕设置就再也进不去屏蔽）。
  /// 清单收在一处，这类分叉才写不出来。
  ///
  /// [onDismiss] 由容器各自给：关掉底部抽屉是 `Get.back`，关掉右侧抽屉是
  /// `Utils.hideRightDialog`，本体只管「先收起当前这层，再开这一路的屏蔽面板」。
  /// 屏蔽面板跟着 `this` 走，也就是打开这条 surface 的那一路（`target`），不是页面
  /// 主格——多开里副格设置的是副格自己的主播屏蔽词。
  ///
  /// [perStreamerShield] 这条按主播的屏蔽入口**按 surface 选入**，默认关。
  /// WHY 要选入而不是统一开着：本体收拢（`d1b02d45`）之前，移动横屏全屏那层弹层是
  /// 自己抄的一份 `DanmuSettingsView`、没抄 `onTapDanmuShield`，点「关键词屏蔽」落的是
  /// 它的默认（全局屏蔽设置页）。收拢时桌面补回了入口，顺手把移动端那层也改成了按主播
  /// ——而本项目的硬约束是「移动端不进这套模型」，移动端路径必须与改造前逐位一致。
  /// 关掉时什么都不往下传，`DanmuSettingsView` 于是走它自己那份默认，正是改前的行为。
  /// 开关做成 bool 而不是把回调透传给调用方自己拼：「先收层再开面板」这个顺序留在本体这
  /// 一份里，两个 surface 才拼不出两种顺序，测试也才钉得住它。
  Widget buildDanmuSettingsBody({
    required VoidCallback onDismiss,
    bool perStreamerShield = false,
  }) {
    return DanmuSettingsView(
      danmakuController: danmakuController,
      onTapDanmuShield: perStreamerShield
          ? () {
              onDismiss();
              showFollowBlockShield();
            }
          : null,
    );
  }

  /// 底部打开弹幕设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          // 落到底部抽屉的三个宿主（移动非全屏底栏、页面「更多设置」面板、竖屏主播
          // 兜底）改前就有这条入口，所以这里恒给 true。唯独移动横屏全屏不落这儿：
          // 它经 `showDanmakuSettings` 进右侧抽屉，那一层的 perStreamerShield 是关的。
          // 「移动端逐位不变」钉的是全屏那一层，别把它也算成底部抽屉的宿主再补 true。
          buildDanmuSettingsBody(
            onDismiss: () => Get.back(),
            perStreamerShield: true,
          ),
        ],
      ),
    );
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) async {
          Get.back();
          currentQuality = e ?? 0;
          await getPlayUrl();
        },
        child: ListView.builder(
          itemCount: qualities.length,
          itemBuilder: (_, i) {
            var item = qualities[i];
            return ListTile(
              leading: Radio<int>(
                // 选中值/回调由外层 `RadioGroup` 统一提供（新 API）。
                // 这里再写一遍 `groupValue` / `onChanged` 会触发
                // `deprecated_member_use`（v3.32 之后废弃），而且两处回调会打架。
                value: i,
              ),
              title: Text(item.quality),
              trailing: IconButton(
                tooltip: "复制直链",
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  try {
                    var playUrl = await site.liveSite
                        .getPlayUrls(detail: detail.value!, quality: item);
                    if (playUrl.urls.isNotEmpty) {
                      Utils.copyToClipboard(playUrl.urls.first);
                      SmartDialog.showToast("已复制直链");
                    } else {
                      SmartDialog.showToast("无法获取播放链接");
                    }
                  } catch (e) {
                    SmartDialog.showToast("获取直链失败: $e");
                  }
                },
              ),
              onTap: () async {
                Get.back();
                currentQuality = i;
                await getPlayUrl();
              },
            );
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          //currentLineIndex = i;
          //setPlayer();
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(
                playUrls[i].contains(".flv") ? "FLV" : "HLS",
              ),
            );
          },
        ),
      ),
    );
  }

  /// 「画面尺寸」弹层的标题：按格生效时必须标出作用范围（spec §6）。
  ///
  /// 标题与作用范围必须用**同一个谓词**（multiPlay.isActive，即下方写入分支的判据）：
  /// 主格在多开期间也是槽位、也只改本格（isSecondaryTile=false 却 isActive=true），
  /// 若按 isSecondaryTile 定标题，主格会显示「全局」字样却做按格的事。
  String get scaleModeSheetTitle => multiPlay.isActive
      ? "画面尺寸 · 第${tileSlot + 1}路（仅这一格）"
      : "画面尺寸";

  /// 「画面尺寸」单选列表本体：底部抽屉（移动）与右侧抽屉（桌面）共用这一份。
  ///
  /// WHY 共用而不是两处各写一份：两个容器之间唯一的差别本来是容器本身，可按格
  /// 写入逻辑（Task 7 修的：`multiPlay.isActive` 时走 `setTileScaleMode`）却只长在
  /// 底部抽屉那一份里——右侧那份照旧写全局，会把本格刚设好的覆盖值顶掉，同一个
  /// 动作在两种宿主下做出两种结果。清单收在一处，这类分叉才写不出来。
  Widget buildScaleModeRadioList() {
    return Obx(
      () => RadioGroup(
        groupValue: effectiveScaleMode,
        onChanged: (e) {
          final mode = e ?? 0;
          if (multiPlay.isActive) {
            setTileScaleMode(mode);
          } else {
            // 从多开退回单画面时本格可能还留着会话期的覆盖值：既然这次写的是
            // 全局设置，就把它一并清掉，否则本格有效值仍被覆盖值主导，
            // 单选钮点完会跳回旧值。
            scaleModeOverride.value = null;
            AppSettingsController.instance.setScaleMode(mode);
            updateScaleMode();
          }
        },
        child: Column(
          children: [
            RadioListTile(
              value: 0,
              title: const Text("适应"),
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile(
              value: 1,
              title: const Text("拉伸"),
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile(
              value: 2,
              title: const Text("铺满"),
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile(
              value: 3,
              title: const Text("16:9"),
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile(
              value: 4,
              title: const Text("4:3"),
              visualDensity: VisualDensity.compact,
            ),
            RadioListTile(
              value: 5,
              title: Obx(() => Text(
                  "自定义（${AppSettingsController.instance.aspectWidth.value}:${AppSettingsController.instance.aspectHeight.value}）")),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: scaleModeSheetTitle,
      child: ListView(
        padding: AppStyle.edgeInsetsV12,
        children: [buildScaleModeRadioList()],
      ),
    );
  }

  void showAspectRatioSheet() {
    final widthController = TextEditingController(text: AppSettingsController.instance.aspectWidth.value.toString());
    final heightController = TextEditingController(text: AppSettingsController.instance.aspectHeight.value.toString());
    Utils.showBottomSheet(
      title: "自定义缩放比例",
      child: Padding(
        padding: AppStyle.edgeInsetsH16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "宽",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                AppStyle.hGap12,
                const Text("x", style: TextStyle(fontSize: 18)),
                AppStyle.hGap12,
                Expanded(
                  child: TextField(
                    controller: heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "高",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            AppStyle.vGap12,
            TextButton(
              onPressed: () {
                final w = int.tryParse(widthController.text) ?? 16;
                final h = int.tryParse(heightController.text) ?? 9;
                if (w <= 0 || h <= 0) return;
                AppSettingsController.instance.setAspectWidth(w);
                AppSettingsController.instance.setAspectHeight(h);
                AppSettingsController.instance.setAspectByUser(w / h);
                if (multiPlay.isActive) {
                  // 多开里与单选列表同一口径：只把本格切到自定义模式。
                  // 全局 scaleMode 不动——否则从这一格改比例，会把所有没有
                  // 覆盖值的格子一起换走；宽:高本身仍是全局值。
                  setTileScaleMode(5);
                } else {
                  // 与 `buildScaleModeRadioList` 的单画面分支同理：写全局前先清掉
                  // 会话期覆盖值，否则本格有效值仍被旧覆盖主导，「确定」看不见效果。
                  scaleModeOverride.value = null;
                  AppSettingsController.instance.setScaleMode(5);
                  updateScaleMode();
                }
                Get.back();
              },
              child: const Text("确定"),
            ),
          ],
        ),
      ),
    );
  }

  void showFollowBlockShield({bool blockWords = true}) {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入${blockWords ? "关键词" : "用户名"}");
        return;
      }
      addCurBlockWord(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "当前主播${blockWords ? "弹幕" : "用户"}屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入${blockWords ? "关键词" : "用户名"}",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(() {
            var len =
                blockWords ? followUserBlock.value!.blockWords.length : followUserBlock.value!.blockAccounts.length;
            return Text(
              "已添加$len个${blockWords ? "关键词" : "用户"}（点击移除）",
              style: Get.textTheme.titleSmall,
            );
          }),
          AppStyle.vGap12,
          Obx(() {
            final block = followUserBlock.value!;

            final List<({String label, VoidCallback onTap})> items = blockWords
                ? block.blockWords
                    .map(
                      (item) => (
                        label: item,
                        onTap: () => delCurBlockWord(item),
                      ),
                    )
                    .toList()
                : block.blockAccounts
                    .map(
                      (item) => (
                        label: item.name,
                        onTap: () => delCurBlockAccount(item.name),
                      ),
                    )
                    .toList();

            return Wrap(
              runSpacing: 12,
              spacing: 12,
              children: items
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: item.onTap,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(top: 4, bottom: 4),
                        child: Text(item.label, style: Get.textTheme.bodyMedium),
                      ),
                    ),
                  )
                  .toList(),
            );
          })
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: Obx(
        () => Stack(
          children: [
            RefreshIndicator(
              onRefresh: FollowService.instance.loadData,
              child: ListView.builder(
                itemCount: FollowService.instance.liveList.length,
                itemBuilder: (_, i) {
                  var item = FollowService.instance.liveList[i];
                  return Obx(
                    () => FollowUserItem(
                      item: item,
                      playing: rxSite.value.id == item.siteId && rxRoomId.value == item.roomId,
                      onTap: () {
                        Get.back();
                        // 多画面模式下挑选的是「加入哪一格」，单画面模式仍是切换当前房间
                        multiPlay.onFollowItemTap(
                          Sites.allSites[item.siteId]!,
                          item.roomId,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
              Positioned(
                right: 12,
                bottom: 12,
                child: Obx(
                  () => DesktopRefreshButton(
                    refreshing: FollowService.instance.updating.value,
                    onPressed: FollowService.instance.loadData,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void showAutoExitSheet() {
    // 定时关闭是会话级（见 [setAutoExit]）：副格点进来一律转到主格那份，
    // 不能让它开第二份倒计时。
    if (isSecondaryTile) {
      return;
    }
    if (AppSettingsController.instance.autoExitEnable.value && !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SettingsSwitch(
              title: "启用定时关闭",
              titleStyle: Get.textTheme.titleMedium,
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration = Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance.setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 解析 `danmakuData`（Rust 契约 JSON 串，键为 snake_case）。
  ///
  /// Dart 侧的 `DouyinDanmakuArgs` / `HuyaDanmakuArgs` 已随 ADR-014 删除，
  /// 这里直接读 JSON；缺字段时返回空 Map，让深链退化为浏览器打开。
  Map<String, dynamic> _danmakuArgsMap() {
    final raw = detail.value?.danmakuData;
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      // danmakuData 是 Rust 契约 JSON 串（Dart 侧 args 类已随 ADR-014 删除）。
      final args = _danmakuArgsMap();
      naviteUrl = "snssdk1128://webcast_room?room_id=${args['room_id']}";
      webUrl = "https://live.douyin.com/${args['web_rid']}";
    } else if (site.id == Constant.kHuya) {
      final args = _danmakuArgsMap();
      final subSid = args['sub_sid'];
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D$subSid%26subid%3D$subSid%26liveuid%3D$subSid%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }
    // 离开的房间停止计时：观看时长现在按房间各记一份，不显式停掉它会一直累加。
    HistoryService.instance.stop(roomId: historyId);

    rxSite.value = site;
    rxRoomId.value = roomId;

    // 与构造里的默认保持一致：抖音默认竖屏
    if (site.id == Constant.kDouyin) {
      isVertical.value = true;
    }

    // 清除全部消息
    liveDanmaku.stop();
    messages.clear();
    _chatEntrancePlayed.clear();
    _lastChatScrollOffset = null;
    _chatScrollTimer?.cancel();
    _chatScrollTimer = null;
    _chatScrollPending = false;
    _cancelChatFollowResume();
    // 换台要复位跟随：新房间的消息不会再触发滚动事件，暂停态留着会让聊天区
    // 停在该房间最旧一条、只能靠「最新」按钮救回来。
    disableAutoScroll.value = false;
    superChats.clear();
    danmakuController?.clear();
    // 表情包是分房间下发的，换房间后上一个房间的合成位图没有复用价值；
    // 但缓存是进程级共享的，多开时别的格子还在用，交给计数决定最后一个持有者才清。
    DanmakuEmoticonRenderer.releaseCache();
    DanmakuEmoticonRenderer.acquireCache();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();
    rustDanmakuMask.reset();
    // 换台后窗口计数归零，旧的合并展示项再也等不到 bump，直接丢弃
    _mergeEntries.clear();

    // 换台：先摘掉通知并抑制重挂。`player.stop()` 会推一次 playing=false 的事件，
    // 不压住的话那一瞬间会用**旧房间**的标题与封面重新挂上去，而新房间的详情还在路上。
    _bgSuppressed = true;
    await _bgHandler?.detach(this);

    // 停止播放
    await player.stop();
    // 旧房间这一路的常亮持有到此为止：新房间起播时会重新 acquire。
    // 不释放的话，新房间加载失败会让常亮一直挂在一个播不出画面的页面上。
    ScreenAwakeService.instance.release(this);

    // 刷新信息
    loadData();
    HistoryService.instance.reset(historyId);
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${error?.stackTrace}''');
    SmartDialog.showToast("已复制错误信息");
  }

  // ------------------------------------------------------------------ 后台播放

  StreamSubscription<bool>? _bgPlayingSubscription;
  StreamSubscription<bool>? _bgBufferingSubscription;
  StreamSubscription<bool>? _bgCompletedSubscription;
  StreamSubscription<dynamic>? _bgSettingSubscription;
  StreamSubscription<bool>? _awakeSubscription;

  /// 播放器已释放/正在收尾：此期间任何事件都不许再往通知上写。
  ///
  /// `onClose` 里先置它再 `player.dispose()`——通知的寿命和播放器的寿命并不同步，
  /// 少了这个位就会读到已释放的 platform。
  bool _bgReleased = false;

  /// 换台抑制位：见 [resetRoom]。
  bool _bgSuppressed = false;

  /// 「audio_service 初始化失败 / 当前平台没有实现」时是 null，下面整套逻辑随之空转。
  LivePlaybackAudioHandler? get _bgHandler =>
      LivePlaybackAudioHandler.maybeInstance;

  /// 移动端的媒体控制属于「后台播放」的一部分（前台服务 + 通知栏），随开关走；
  /// 桌面端没有后台服务这一层，窗口最小化后系统媒体控制才是唯一入口，常开。
  bool get _mediaControlsFollowSwitch => Platform.isAndroid || Platform.isIOS;

  void initBackgroundPlayback() {
    // 副格不挂通知：多开时四路争同一条通知只会互相顶掉。
    if (isSecondaryTile) {
      return;
    }
    _bgPlayingSubscription =
        player.stream.playing.listen((_) => syncBackgroundPlayback());
    _bgBufferingSubscription =
        player.stream.buffering.listen((_) => syncBackgroundPlayback());
    // 直播结束（EOS）时 mpv 只报 completed，`playing` 仍是 true：不接这一路的话
    // 通知会停在「正在播放」上，而声音早就没了。
    _bgCompletedSubscription =
        player.stream.completed.listen((_) => syncBackgroundPlayback());
    _bgSettingSubscription =
        EventBus.instance.listen(EventBus.kBackgroundPlayChanged, (event) {
      // 开与关都要立刻处理：流稳定时 playing/buffering 可以很久不跳，等下一次事件的
      // 话，用户在设置页关了开关、通知还挂在屏幕上。
      syncBackgroundPlayback();
    });
  }

  /// 屏幕常亮订阅：起播即持有（[ScreenAwakeService]）。
  ///
  /// 副格也要订阅 —— 常亮是全局开关，多开时每一路各自持有一份，靠服务里的
  /// 引用计数决定何时真正熄灭，这里不能像通知那样只归主格。
  /// 只在 `playing=true` 时 acquire：`playing=false` 既可能是用户暂停，也可能
  /// 是断线重连的一跳，区分不了就不该在这里 release —— 释放只走
  /// [playbackPause] / [playbackStop] / [onClose] 与直播终态这些明确入口。
  void initScreenAwake() {
    _awakeSubscription = player.stream.playing.listen((playing) {
      if (playing) {
        ScreenAwakeService.instance.acquire(this, reason: 'playing');
      }
    });
  }

  /// 「此刻系统媒体控制该不该显示这一路、显示成什么样」的唯一入口。幂等。
  void syncBackgroundPlayback() {
    if (_bgReleased || _bgSuppressed || isSecondaryTile) {
      return;
    }
    final handler = _bgHandler;
    if (handler == null) {
      return;
    }
    if (_mediaControlsFollowSwitch &&
        !AppSettingsController.instance.backgroundPlay.value) {
      unawaited(handler.detach(this));
      return;
    }
    // attach 内部幂等：同一个实例重复挂载只等价于一次重推。
    handler.attach(this);
  }

  /// 必须在 `player.dispose()` 之前调用（见 [onClose]）。
  Future<void> releaseBackgroundPlayback() async {
    _bgReleased = true;
    await _bgPlayingSubscription?.cancel();
    await _bgBufferingSubscription?.cancel();
    await _bgCompletedSubscription?.cancel();
    await _bgSettingSubscription?.cancel();
    await _bgHandler?.detach(this);
  }

  // ------------------------------------------------------ LivePlaybackTarget

  /// 房间的稳定身份，与历史记录/关注记录用的是同一个口径。
  @override
  String get playbackMediaId => historyId;

  @override
  String get playbackTitle => detail.value?.title ?? roomId;

  @override
  String get playbackArtist => detail.value?.userName ?? site.name;

  @override
  String get playbackAlbum => site.name;

  @override
  Uri? get playbackArtUri {
    final cover = detail.value?.cover ?? '';
    if (cover.isEmpty) {
      return null;
    }
    return Uri.tryParse(cover);
  }

  /// 未开播时在轮播的那段录像按点播处理。
  /// 详情还没拿到时按直播算——这是个直播 app，默认值该站在「直播」这边。
  @override
  bool get playbackIsLive => !(detail.value?.isRecord ?? false);

  @override
  bool get playbackPlaying =>
      !_bgReleased && player.state.playing && !player.state.completed;

  @override
  bool get playbackBuffering => !_bgReleased && player.state.buffering;

  @override
  Future<void> playbackPlay() async {
    if (_bgReleased) {
      return;
    }
    await player.play();
    // 从前台以外的入口（通知/锁屏/耳机键）起播时，常亮状态也得接回来，
    // 否则回到 app 会发现屏幕常亮早就掉了。
    ScreenAwakeService.instance.acquire(this, reason: 'playbackPlay');
  }

  @override
  Future<void> playbackPause() async {
    if (_bgReleased) {
      return;
    }
    await player.pause();
    // 用户/系统明确暂停：这一路不再需要常亮（多开时其余路各自持有，不受影响）。
    ScreenAwakeService.instance.release(this);
  }

  /// 通知里的「停止」= 暂停出声 + 撤掉通知与前台服务。
  ///
  /// 不是 `player.stop()`：EOS 会把 completed 推给 [mediaEnd]，那套「播放结束就重连
  /// /换线路」的自愈逻辑会把「停止」当成一次意外断流，立刻又把流拉起来。
  @override
  Future<void> playbackStop() async {
    if (_bgReleased) {
      return;
    }
    await player.pause();
    ScreenAwakeService.instance.release(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Android 12+ 在后台起前台服务会抛异常，而 audio_service 那边没兜（原因见
    // LivePlaybackAudioHandler.appInForeground）。把这个状态递给 handler，
    // 由它决定这一刻敢不敢把 playing 报成 true。
    _bgHandler?.appInForeground = state == AppLifecycleState.resumed;

    if (state == AppLifecycleState.paused) {
      var height = MediaQuery.of(Get.context!).padding.top;
      Log.d("当前状态栏高度$height");
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      // update();
      var height = MediaQuery.of(Get.context!).padding.top;
      Log.d("当前状态栏高度$height");
      Log.d("返回前台");
      danmakuController?.resume();
      isBackground = false;
      // 回前台补一次：在后台被那道闸压住的 playing=true 现在可以正常发出去了。
      syncBackgroundPlayback();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    // 这一路的常亮持有随房间一起释放；多开时其余路的常亮由服务里的计数保住。
    ScreenAwakeService.instance.release(this);
    _awakeSubscription?.cancel();
    // 离开直播间必须让通知与前台服务一起消失。必须排在 super.onClose() 之前——
    // 那边会 `player.dispose()`，晚一步 handler 就会读到已释放的播放器。
    unawaited(releaseBackgroundPlayback());
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();
    danmakuTimer?.cancel();
    _chatScrollTimer?.cancel();
    _cancelChatFollowResume();
    // 这个 EventBus 订阅原来一直没被取消：每关一个直播间就漏一个 kUpdateDanmaku
    // 监听者，多开时泄漏量翻四倍。
    subscription?.cancel();
    HistoryService.instance.stop(roomId: historyId);

    liveDanmaku.stop();
    danmakuController = null;
    // 续流中转会话随这一路一起回收：断开上游连接，避免退出后还在偷偷拉流。
    _releaseRelaySessions();
    // 直接退出直播间不经过 resetRoom，这里补一次：表情是分房间下发的，
    // 留在静态缓存里的源图句柄与合成位图出房间后就没有复用价值了。
    DanmakuEmoticonRenderer.releaseCache();
    rustDanmakuMask.dispose();
    if (!isSecondaryTile) {
      // 副格是手工 Get.put(tag:) 注册的，路由 pop 不会回收它们——必须在主格退出时
      // 显式摘掉，否则四路播放器会连着音频一起泄漏。副格自己的 onClose 不做这件事
      // （它持有的空会话会把窗口下限改回常规值）。
      multiPlay.dispose();
    }
    super.onClose();
  }
}

/// 合并模式的一条展示项：消息对象（计数原地改写）+ 最后命中时间（用于清窗）
class _DanmakuMergeEntry {
  _DanmakuMergeEntry(this.message) : lastSeen = DateTime.now();

  final LiveMessage message;
  DateTime lastSeen;
}
