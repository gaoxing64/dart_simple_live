//! B站的 Rust Core 绑定层：`RustBilibiliSite implements LiveSite`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：本层**只做类型翻译与转发**，零协议逻辑 ——
//! 不得出现 URL 拼接 / 签名 / 解析 / 重试；一切协议能力在 `slive-core`（Rust）。
//! 回退窗口已结束（ADR-008）：`sites.dart` 直连本绑定层，无运行时开关；
//! Dart core 的 B站实现待 console 迁移后删除（console 暂留 Dart 路径）。

import 'dart:async';

import 'package:simple_live_core/src/rust/api/slive/danmaku.dart' as rust_danmaku;
import 'package:simple_live_core/src/rust/api/slive/site.dart' as rust_site;
import 'package:simple_live_core/src/rust/api/slive/models/danmu.dart' as rust_danmu;
import 'package:simple_live_core/simple_live_core.dart';

import 'rust_site_models.dart';
import 'package:flutter/foundation.dart';

/// B站的 Rust Core 站点实现（D2：Dart 直连 FRB API，无 Dart 协议实现）。
class RustBilibiliSite extends LiveSite {
  RustBilibiliSite() {
    id = "bilibili";
    name = "哔哩哔哩直播";
  }

  Future<rust_site.LiveBilibiliSite>? _siteFuture;

  /// `setSiteAttrs` 是同步接口而 FRB 句柄初始化是异步 —— 暂存凭证，
  /// 下一次 `_site()` 调用前应用（App 流程 setSiteAttrs 后必跟异步请求，语义等价）。
  String? _pendingAttrs;

  Future<rust_site.LiveBilibiliSite> _site() async {
    final site = await (_siteFuture ??= rust_site.LiveBilibiliSite.default_());
    final pending = _pendingAttrs;
    if (pending != null) {
      site.setSiteAttrs(data: pending);
      _pendingAttrs = null;
    }
    return site;
  }

  @override
  LiveDanmaku getDanmaku() => RustLiveDanmaku();

  @override
  Future<List<LiveCategory>> getCategories() async {
    final list = await (await _site()).getCategories();
    return list.map(RustSiteModels.toCoreCategory).toList();
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async =>
      RustSiteModels.toCoreSearchRoom(
        await (await _site()).searchRooms(keyword: keyword, page: page),
      );

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async =>
      RustSiteModels.toCoreSearchAnchor(
        await (await _site()).searchAnchors(keyword: keyword, page: page),
      );

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
    int? pageSize,
  }) async =>
      RustSiteModels.toCoreCategoryResult(
        await (await _site()).getCategoryRooms(
          category: RustSiteModels.toRustSubCategory(category),
          page: page,
          pageSize: pageSize,
        ),
      );

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1, int? pageSize}) async =>
      RustSiteModels.toCoreCategoryResult(
        await (await _site())
            .getRecommendRooms(page: page, pageSize: pageSize),
      );

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      RustSiteModels.toCoreRoomDetail(
        await (await _site()).getRoomDetail(roomId: roomId),
      );

  @override
  Future<List<LivePlayQuality>> getPlayQualities(
      {required LiveRoomDetail detail}) async =>
      (await (await _site()).getPlayQualities(
        detail: RustSiteModels.toRustRoomDetail(detail),
      ))
          .map(RustSiteModels.toCorePlayQuality)
          .toList();

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail, required LivePlayQuality quality}) async =>
      RustSiteModels.toCorePlayUrl(
        await (await _site()).getPlayUrls(
          detail: RustSiteModels.toRustRoomDetail(detail),
          quality: RustSiteModels.toRustPlayQuality(quality),
        ),
      );

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await _site()).getLiveStatus(roomId: roomId);

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) async =>
      (await (await _site()).getSuperChatMessages(roomId: roomId))
          .map(RustSiteModels.toCoreSuperChat)
          .toList();

  @override
  void setSiteAttrs(String data) => _pendingAttrs = data;

  @override
  Future<QRCode> getQRCode() async =>
      RustSiteModels.toCoreQrCode(await (await _site()).getQrCode());

  @override
  Future<QRPollResult> getQRPollResult({required String qrcodeKey}) async =>
      RustSiteModels.toCoreQrPollResult(
        await (await _site()).getQrPollResult(qrcodeKey: qrcodeKey),
      );

  @override
  Future<AccountInfo> getAccountInfo({required String credential}) async =>
      RustSiteModels.toCoreAccountInfo(
        await (await _site()).getAccountInfo(credential: credential),
      );
}

/// 弹幕适配：core 的回调式 `LiveDanmaku` -> Rust 的 Stream。
///
/// `start(args)` 的 `args` 为 `detail.danmakuData` 原样透传（JSON 串，
/// Rust 侧 `from_json` 解析失败抛 `CoreError` —— J-10）。
///
/// 多开播放（2026-10-18 修复）：每个 `RustLiveDanmaku` 实例自持一个
/// `DanmakuConnection` 句柄 —— 旧实现是全局单例，第二路 start 会把第一路 stop 掉，
/// 表现为「只有一路有弹幕，另一路聊天区显示已手动停止」。
class RustLiveDanmaku extends LiveDanmaku {
  StreamSubscription<rust_danmu.LiveDanmuItem>? _subscription;
  rust_danmaku.DanmakuConnection? _conn;

  // 心跳由 Rust 会话内部管理（60s），Dart 侧 heartbeat()/heartbeatTime 不参与。

  @override
  Future<void> start(dynamic args) async {
    // `args` 只接受 `detail.danmakuData` 原样透传的 JSON 串（Rust 契约）。
    // Dart 侧已无 `BiliBiliDanmakuArgs` 类型（ADR-014 删除 Dart core 实现）。
    final argsJson = args is String
        ? args
        : throw ArgumentError(
            'RustLiveDanmaku.start 需要 danmakuData JSON 串，收到 ${args.runtimeType}',
          );
    // 新会话 = 新句柄：先停掉旧会话（换台 / 刷新路径），再多开时各停各的。
    await stop();
    _conn = rust_danmaku.DanmakuConnection();
    _subscription = _conn!.start(argsJson: argsJson).listen(
      (item) {
        switch (item) {
          case rust_danmu.LiveDanmuItem_Message(:final field0):
            onMessage?.call(RustSiteModels.toCoreMessage(field0));
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
        debugPrint('[rust-danmaku] stream ERROR: $e');
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
