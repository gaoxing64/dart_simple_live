//! 抖音的 Rust Core 绑定层：`RustDouyinSite extends LiveSite`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：本层**只做类型翻译与转发**，零协议逻辑 ——
//! 不得出现 URL 拼接 / a_bogus 签名 / protobuf 编解码 / 重连；一切协议能力在
//! `slive-core`（Rust）。回退窗口已结束（ADR-008）：`sites.dart` 直连本绑定层。
//!
//! 与 `RustBilibiliSite` 的三处差异：
//! 1. `getDanmaku()` 返回抖音专属适配器（protobuf over WS 的参数契约键名不同）；
//! 2. `searchAnchors` / `getQRCode` / `getQRPollResult` 在抖音是**不支持**的能力，
//!    Rust 侧恒报错，这里不做「假装成功」的空实现；
//! 3. 清晰度 `data` 通道是地址数组的 JSON 串（见 `RustDouyinModels`）。

import 'dart:async';
import 'dart:convert';

import 'package:simple_live_core/src/rust/api/slive/douyin.dart' as rust_douyin;
import 'package:simple_live_core/src/rust/api/slive/models/danmu.dart' as rust_danmu;
import 'package:simple_live_core/simple_live_core.dart';

import 'rust_douyin_models.dart';
import 'rust_site_models.dart';
import 'package:flutter/foundation.dart';

/// 抖音的 Rust Core 站点实现（类型翻译 + 转发，零协议逻辑）。
class RustDouyinSite extends LiveSite {
  RustDouyinSite() {
    id = "douyin";
    name = "抖音直播";
  }

  Future<rust_douyin.LiveDouyinSite>? _siteFuture;

  /// `setSiteAttrs` 是同步接口而 FRB 句柄初始化是异步 —— 暂存凭证，
  /// 下一次 `_site()` 调用前应用（App 流程 setSiteAttrs 后必跟异步请求，语义等价）。
  String? _pendingAttrs;

  /// 抖音侧的 `hlsFirst` 偏好（App 从本地存储下发）。
  ///
  /// 必须在句柄可用**之后**下发才有意义，故与 `_pendingAttrs` 合并成同一条 JSON
  /// （Rust 侧 `set_site_attrs` 同时吃 `cookie` 与 `hlsFirst` 两个键）。
  bool? _pendingHlsFirst;

  Future<rust_douyin.LiveDouyinSite> _site() async {
    final site = await (_siteFuture ??= rust_douyin.LiveDouyinSite.default_());
    final pending = _pendingAttrs;
    if (pending != null || _pendingHlsFirst != null) {
      site.setSiteAttrs(data: _composeAttrs());
      _pendingAttrs = null;
      _pendingHlsFirst = null;
    }
    return site;
  }

  /// 合成待下发的 `setSiteAttrs` 载荷（cookie 与 hlsFirst 合并成一条 JSON）。
  String _composeAttrs() {
    final pending = _pendingAttrs;
    final hlsFirst = _pendingHlsFirst;
    if (hlsFirst == null) {
      return pending ?? '{}';
    }
    final map = <String, dynamic>{};
    if (pending != null && pending.isNotEmpty) {
      // App 侧传的是 jsonEncode 结果；万一不是对象就原样保留（由 Rust 侧报错，
      // 绑定层不做协议判断 —— AC-39）
      final decoded = jsonDecode(pending);
      if (decoded is Map) {
        map.addAll(decoded.cast<String, dynamic>());
      }
    }
    map['hlsFirst'] = hlsFirst;
    return jsonEncode(map);
  }

  @override
  LiveDanmaku getDanmaku() => RustDouyinDanmaku();

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

  /// 抖音不支持搜索主播 —— Rust 侧恒报错，这里直接转发错误（不假装返回空结果）。
  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
          {int page = 1}) async =>
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
        await (await _site()).getRecommendRooms(page: page, pageSize: pageSize),
      );

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      RustDouyinModels.toCoreRoomDetail(
        await (await _site()).getRoomDetail(roomId: roomId),
      );

  @override
  Future<List<LivePlayQuality>> getPlayQualities(
          {required LiveRoomDetail detail}) async =>
      (await (await _site()).getPlayQualities(
        detail: RustDouyinModels.toRustRoomDetail(detail),
      ))
          .map(RustDouyinModels.toCorePlayQuality)
          .toList();

  @override
  Future<LivePlayUrl> getPlayUrls(
          {required LiveRoomDetail detail, required LivePlayQuality quality}) async =>
      RustDouyinModels.toCorePlayUrl(
        await (await _site()).getPlayUrls(
          detail: RustDouyinModels.toRustRoomDetail(detail),
          quality: RustDouyinModels.toRustPlayQuality(quality),
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
  @override
  void setSiteAttrs(String data) {
    // 空串 = 未登录账号的 credential（`accountLogin` 既有路径）。空串不是合法
    // JSON：Rust 侧解析报错，且会把 `_updateXxxAttr` 暂存的有效 attrs 覆盖成空
    // （竞态：谁后谁赢，导致首页请求带着空 attrs 去炸 Rust）。core 层虽已容错，
    // 这里仍显式跳过 —— 暂存语义只接受有效 JSON。
    if (data.isEmpty) return;
    _pendingAttrs = data;
  }

  /// 抖音的 hls 优先偏好（与 cookie 一起下发，见 [_composeAttrs]）。
  void setHlsFirst(bool value) => _pendingHlsFirst = value;

  /// 抖音不支持扫码登录 —— 转发 Rust 侧错误，不返回伪造的失败对象。
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
      RustDouyinModels.toCoreAccountInfo(
        await (await _site()).getAccountInfo(credential: credential),
      );
}

/// 抖音弹幕适配：core 的回调式 `LiveDanmaku` -> Rust 的 Stream。
///
/// `start(args)` 的 `args` 为 `detail.danmakuData` 原样透传（JSON 串，Rust 侧
/// `from_json` 解析失败抛 `CoreError` —— J-10）。
///
/// 多开播放（2026-10-18 修复）：每个 `RustDouyinDanmaku` 实例自持一个
/// `DouyinDanmakuConnection` 句柄 —— 旧实现是全局单例，第二路 start 会把第一路
/// stop 掉，表现为「只有一路有弹幕，另一路聊天区显示已手动停止」。
class RustDouyinDanmaku extends LiveDanmaku {
  StreamSubscription<rust_danmu.LiveDanmuItem>? _subscription;
  rust_douyin.DouyinDanmakuConnection? _conn;

  // 心跳由 Rust 会话内部管理（10s），Dart 侧 heartbeat()/heartbeatTime 不参与。

  @override
  Future<void> start(dynamic args) async {
    // `args` 只接受 `detail.danmakuData` 原样透传的 JSON 串（Rust 契约）。
    // Dart 侧已无 `DouyinDanmakuArgs` 类型（ADR-014 删除 Dart core 实现）。
    final argsJson = args is String
        ? args
        : throw ArgumentError(
            'RustDouyinDanmaku.start 需要 danmakuData JSON 串，收到 ${args.runtimeType}',
          );
    // 新会话 = 新句柄：先停掉旧会话（换台 / 刷新路径），再多开时各停各的。
    await stop();
    _conn = rust_douyin.DouyinDanmakuConnection();
    _subscription = _conn!.start(argsJson: argsJson).listen(
      (item) {
        switch (item) {
          case rust_danmu.LiveDanmuItem_Message(:final field0):
            onMessage?.call(RustDouyinModels.toCoreMessage(field0));
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
        debugPrint('[rust-douyin-danmaku] stream ERROR: $e');
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
