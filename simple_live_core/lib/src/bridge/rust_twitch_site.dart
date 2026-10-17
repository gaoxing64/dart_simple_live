//! Twitch 的 Rust Core 绑定层：`RustTwitchSite implements LiveSite`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-18）：本层**只做类型翻译与转发**，零协议逻辑 ——
//! 不得出现 URL 拼接 / 哈希 / 签名 / 解析 / 重试；一切协议能力在 `slive-core`（Rust）。
//! `sites.dart` 直连本绑定层（回退窗口已结束，ADR-008）；Dart core 的 Twitch 实现已删除。
//!
//! 与 B站绑定层（`rust_bilibili_site.dart`）的关系：**并列且独立**。
//! 模型翻译复用 `rust_site_models.dart` 的纯映射函数（跨平台模型同构，无需 Twitch 专属翻译层），
//! 本文件只做「Rust 句柄 -> core 接口」的转发与命名对齐。
//!
//! 命名对齐（J-4/J-8）：Rust 侧 `getSuperChatMessages`（复数，对齐上游），
//! Dart core 侧可见名仍是单数 `getSuperChatMessage`。
//!
//! ⚠️ `uri_does_not_exist`：下列两个 import 指向 **FRB 代码生成产物**
//! （`lib/src/rust/api/slive/twitch/{site,danmaku}.dart`）。按 IP-5 文件边界，
//! 本任务**不执行** `flutter_rust_bridge_codegen`（由总监在四路模块齐备后统一生成），
//! 故此处显式 ignore；生成后请连同本 ignore 一并复核。
// ignore_for_file: uri_does_not_exist

import 'dart:async';
import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';

import 'package:simple_live_core/src/rust/api/slive/twitch/danmaku.dart' as rust_twitch_danmaku;
import 'package:simple_live_core/src/rust/api/slive/twitch/site.dart' as rust_twitch_site;
import 'package:simple_live_core/src/rust/api/slive/models/danmu.dart' as rust_danmu;

import 'rust_site_models.dart';
import 'package:flutter/foundation.dart';

/// Twitch 的 Rust Core 站点实现（D2：Dart 直连 FRB API，无 Dart 协议实现）。
class RustTwitchSite extends LiveSite {
  RustTwitchSite() {
    id = 'twitch';
    name = 'Twitch';
  }

  Future<rust_twitch_site.LiveTwitchSite>? _siteFuture;

  /// `setSiteAttrs` 是同步接口而 FRB 句柄初始化是异步 —— 暂存，
  /// 下一次 `_site()` 调用前应用。
  ///
  /// ⚠️ Twitch 的 Dart core 实现是 `throw UnimplementedError()`（`twitch_site.dart:298`），
  /// Rust 侧同样返回错误（`platforms/twitch/unsupported.rs`）。**这里不做静默吞掉**：
  /// 保留暂存语义是为了让 App 若调用该接口时能看到 Rust 抛出的同一类错误，
  /// 而不是被本地缓存骗过去。
  String? _pendingAttrs;

  Future<rust_twitch_site.LiveTwitchSite> _site() async {
    final site =
        await (_siteFuture ??= rust_twitch_site.LiveTwitchSite.default_());
    final pending = _pendingAttrs;
    if (pending != null) {
      site.setSiteAttrs(data: pending);
      _pendingAttrs = null;
    }
    return site;
  }

  @override
  LiveDanmaku getDanmaku() => RustTwitchDanmaku();

  /// Twitch 无分类（Dart core 直接返回空列表）。
  @override
  Future<List<LiveCategory>> getCategories() async =>
      (await (await _site()).getCategories())
          .map(RustSiteModels.toCoreCategory)
          .toList();

  /// Twitch 无分类房间（Dart core 返回空结果）。
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

  /// Twitch 不支持推荐（Dart core `throw UnimplementedError`）—— 错误原样抛出。
  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1, int? pageSize}) async =>
      RustSiteModels.toCoreCategoryResult(
        await (await _site()).getRecommendRooms(page: page, pageSize: pageSize),
      );

  /// Twitch 不支持搜索房间（Dart core `throw Exception`）。
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async =>
      RustSiteModels.toCoreSearchRoom(
        await (await _site()).searchRooms(keyword: keyword, page: page),
      );

  /// Twitch 不支持搜索主播（Dart core `throw Exception`）。
  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
          {int page = 1}) async =>
      RustSiteModels.toCoreSearchAnchor(
        await (await _site()).searchAnchors(keyword: keyword, page: page),
      );

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      RustSiteModels.toCoreRoomDetail(
        await (await _site()).getRoomDetail(roomId: roomId),
      );

  @override
  Future<List<LivePlayQuality>> getPlayQualities(
          {required LiveRoomDetail detail}) async =>
      (await (await _site())
              .getPlayQualities(detail: RustSiteModels.toRustRoomDetail(detail)))
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

  /// Rust 侧方法名为复数（对齐上游），Dart core 可见名保持单数（J-4/J-8）。
  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
          {required String roomId}) async =>
      (await (await _site()).getSuperChatMessages(roomId: roomId))
          .map(RustSiteModels.toCoreSuperChat)
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

  /// Twitch 无扫码登录（Dart core `throw UnimplementedError`）。
  @override
  Future<QRCode> getQRCode() async =>
      RustSiteModels.toCoreQrCode(await (await _site()).getQrCode());

  /// Twitch 无扫码登录（Dart core `throw UnimplementedError`）。
  @override
  Future<QRPollResult> getQRPollResult({required String qrcodeKey}) async =>
      RustSiteModels.toCoreQrPollResult(
        await (await _site()).getQrPollResult(qrcodeKey: qrcodeKey),
      );

  /// Twitch 无账号体系（Dart core `throw UnimplementedError`）。
  @override
  Future<AccountInfo> getAccountInfo({required String credential}) async =>
      RustSiteModels.toCoreAccountInfo(
        await (await _site()).getAccountInfo(credential: credential),
      );
}

/// 弹幕适配：core 的回调式 `LiveDanmaku` -> Rust 的 Stream。
///
/// `start(args)` 的 `args` 为 `detail.danmakuData` 原样透传（JSON 契约串，
/// Rust 侧 `TwitchDanmakuArgs::from_json` 解析失败抛 `CoreError` —— J-10）。
class RustTwitchDanmaku extends LiveDanmaku {
  StreamSubscription<rust_danmu.LiveDanmuItem>? _subscription;

  // 心跳由 Rust 会话内部管理（40s，对齐 Dart `heartbeatTime`），
  // Dart 侧 heartbeat()/heartbeatTime 不参与。

  @override
  Future<void> start(dynamic args) async {
    final argsJson = args is String
        ? args
        : jsonEncode({
            'schema_version': 1,
            'channel': (args as String).toLowerCase(),
          });
    await _subscription?.cancel();
    _subscription = rust_twitch_danmaku.startTwitchDanmaku(channelOrArgs: argsJson)
        .listen(
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
        debugPrint('[rust-twitch-danmaku] stream ERROR: $e');
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    rust_twitch_danmaku.stopTwitchDanmaku();
    await _subscription?.cancel();
    _subscription = null;
  }
}
