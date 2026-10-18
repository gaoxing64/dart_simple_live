//! 斗鱼的 Rust Core 绑定层：`RustDouyuSite implements LiveSite`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：本层**只做类型翻译与转发**，零协议逻辑 ——
//! 不得出现 URL 拼接 / 签名 / STT 解析 / 重试；一切协议能力在 `slive-core`（Rust）。
//! 回退窗口已结束（ADR-008）：`sites.dart` 直连本绑定层，无运行时开关。

import 'dart:async';

import 'package:simple_live_core/src/rust/api/slive/douyu.dart' as rust_douyu;
import 'package:simple_live_core/src/rust/api/slive/models/danmu.dart' as rust_danmu;
import 'package:simple_live_core/simple_live_core.dart';

import 'rust_douyu_models.dart';
import 'package:flutter/foundation.dart';

/// 斗鱼的 Rust Core 站点实现（D2：Dart 直连 FRB API，无 Dart 协议实现）。
class RustDouyuSite extends LiveSite {
  RustDouyuSite() {
    id = "douyu";
    name = "斗鱼直播";
  }

  Future<rust_douyu.LiveDouyuSite>? _siteFuture;

  /// `setSiteAttrs` 是同步接口而 FRB 句柄初始化是异步 —— 暂存凭证，
  /// 下一次 `_site()` 调用前应用（App 流程 setSiteAttrs 后必跟异步请求，语义等价）。
  String? _pendingAttrs;

  Future<rust_douyu.LiveDouyuSite> _site() async {
    final site = await (_siteFuture ??= rust_douyu.LiveDouyuSite.default_());
    final pending = _pendingAttrs;
    if (pending != null) {
      site.setSiteAttrs(data: pending);
      _pendingAttrs = null;
    }
    return site;
  }

  @override
  LiveDanmaku getDanmaku() => RustDouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategories() async {
    final list = await (await _site()).getCategories();
    return list.map(RustDouyuModels.toCoreCategory).toList();
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async =>
      RustDouyuModels.toCoreSearchRoom(
        await (await _site()).searchRooms(keyword: keyword, page: page),
      );

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async =>
      RustDouyuModels.toCoreSearchAnchor(
        await (await _site()).searchAnchors(keyword: keyword, page: page),
      );

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
    int? pageSize,
  }) async =>
      RustDouyuModels.toCoreCategoryResult(
        await (await _site()).getCategoryRooms(
          category: RustDouyuModels.toRustSubCategory(category),
          page: page,
          pageSize: pageSize,
        ),
      );

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1, int? pageSize}) async =>
      RustDouyuModels.toCoreCategoryResult(
        await (await _site())
            .getRecommendRooms(page: page, pageSize: pageSize),
      );

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      RustDouyuModels.toCoreRoomDetail(
        await (await _site()).getRoomDetail(roomId: roomId),
      );

  @override
  Future<List<LivePlayQuality>> getPlayQualities(
      {required LiveRoomDetail detail}) async =>
      (await (await _site()).getPlayQualities(
        detail: RustDouyuModels.toRustRoomDetail(detail),
      ))
          .map(RustDouyuModels.toCorePlayQuality)
          .toList();

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail, required LivePlayQuality quality}) async =>
      RustDouyuModels.toCorePlayUrl(
        await (await _site()).getPlayUrls(
          detail: RustDouyuModels.toRustRoomDetail(detail),
          quality: RustDouyuModels.toRustPlayQuality(quality),
        ),
      );

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await _site()).getLiveStatus(roomId: roomId);

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
          {required String roomId}) async =>
      (await (await _site()).getSuperChatMessages(roomId: roomId))
          .map(RustDouyuModels.toCoreSuperChat)
          .toList();

  @override
  @override
  void setSiteAttrs(String data) {
    // 空串 = 未登录账号的 credential（`accountLogin` 既有路径）。空串不是合法
    // JSON：Rust 侧解析报错，且会把 `_updateXxxAttr` 暂存的有效 attrs 覆盖成空
    // （竞态：谁后谁赢，导致首页请求带着空 attrs 去炸 Rust）。core 层虽已容错，
    // 这里仍显式跳过 —— 暂存语义只接受有效 JSON。
    if (data.isEmpty) return;
    _pendingAttrs = data;
  }

  @override
  Future<QRCode> getQRCode() async =>
      RustDouyuModels.toCoreQrCode(await (await _site()).getQrCode());

  @override
  Future<QRPollResult> getQRPollResult({required String qrcodeKey}) async =>
      RustDouyuModels.toCoreQrPollResult(
        await (await _site()).getQrPollResult(qrcodeKey: qrcodeKey),
      );

  @override
  Future<AccountInfo> getAccountInfo({required String credential}) async =>
      RustDouyuModels.toCoreAccountInfo(
        await (await _site()).getAccountInfo(credential: credential),
      );
}

/// 弹幕适配：core 的回调式 `LiveDanmaku` -> Rust 的 Stream。
///
/// `start(args)` 的 `args` 为 `detail.danmakuData`，斗鱼即**房间号字符串**（原样透传，
/// Rust 侧空值/非法值抛 `CoreError` —— J-10）。
///
/// 多开播放（2026-10-18 修复）：每个 `RustDouyuDanmaku` 实例自持一个
/// `DouyuDanmakuConnection` 句柄 —— 旧实现是全局单例，第二路 start 会把第一路
/// stop 掉，表现为「只有一路有弹幕，另一路聊天区显示已手动停止」。
class RustDouyuDanmaku extends LiveDanmaku {
  StreamSubscription<rust_danmu.LiveDanmuItem>? _subscription;
  rust_douyu.DouyuDanmakuConnection? _conn;

  // 心跳由 Rust 会话内部管理（45s，与 Dart `DouyuDanmaku.heartbeatTime` 一致），
  // Dart 侧 heartbeat()/heartbeatTime 不参与。

  @override
  Future<void> start(dynamic args) async {
    final roomId = args is String
        ? args
        : (args?.toString() ?? '');
    // 新会话 = 新句柄：先停掉旧会话（换台 / 刷新路径），再多开时各停各的。
    await stop();
    _conn = rust_douyu.DouyuDanmakuConnection();
    _subscription = _conn!.start(roomId: roomId).listen(
      (item) {
        switch (item) {
          case rust_danmu.LiveDanmuItem_Message(:final field0):
            onMessage?.call(RustDouyuModels.toCoreMessage(field0));
          case rust_danmu.LiveDanmuItem_Control(:final field0):
            switch (field0) {
              case rust_danmu.LiveDanmuControlEvent_Ready():
                onReady?.call();
              case rust_danmu.LiveDanmuControlEvent_Reconnecting(:final attempt):
                onClose?.call('与服务器断开连接，正在尝试重连($attempt)');
              case rust_danmu.LiveDanmuControlEvent_Closed(:final field0):
                onClose?.call(field0);
            }
        }
      },
      onError: (Object e) {
        // 流级错误（解码失败等）不中断弹幕，记录即可
        // ignore: avoid_print
        debugPrint('[rust-douyu-danmaku] stream ERROR: $e');
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    _conn?.stop();
    await _subscription?.cancel();
    _subscription = null;
    _conn = null;
  }
}