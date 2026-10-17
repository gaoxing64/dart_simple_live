//! 虎牙的 Rust Core 绑定层：`RustHuyaSite implements LiveSite`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：本层**只做类型翻译与转发**，零协议逻辑 ——
//! 不得出现 URL 拼接 / 签名 / TARS 解析 / 正则 / 重试；一切协议能力在
//! `slive-core`（Rust）。回退窗口已结束（ADR-008）：`sites.dart` 直连本绑定层。
//!
//! 与 B站绑定的差异：虎牙 `detail.danmakuData` / `quality.data` 在 Rust 侧是
//! **JSON 串**（`schema_version` 契约），本层**原样透传**，不解析 ——
//! App 侧 `liveDanmaku.start(detail.danmakuData)` 与
//! `getPlayUrls(detail:, quality:)` 会把它带回 Rust（J-10：
//! 任何 Dart 消费者解析失败必须抛 `FormatException`，不得静默兜底）。

import 'dart:async';

import 'package:simple_live_core/src/rust/api/slive/huya.dart' as rust_huya_danmaku;
import 'package:simple_live_core/src/rust/api/slive/huya_site.dart'
    as rust_huya;
import 'package:simple_live_core/src/rust/api/slive/models/danmu.dart' as rust_danmu;
import 'package:simple_live_core/simple_live_core.dart';

import 'rust_site_models.dart';
import 'package:flutter/foundation.dart';

/// 虎牙的 Rust Core 站点实现（D2：Dart 直连 FRB API，无 Dart 协议实现）。
class RustHuyaSite extends LiveSite {
  RustHuyaSite() {
    id = "huya";
    name = "虎牙直播";
  }

  Future<rust_huya.LiveHuyaSite>? _siteFuture;

  /// `setSiteAttrs` 是同步接口而 FRB 句柄初始化是异步 —— 暂存凭证，
  /// 下一次 `_site()` 调用前应用（App 流程 setSiteAttrs 后必跟异步请求，语义等价）。
  String? _pendingAttrs;

  Future<rust_huya.LiveHuyaSite> _site() async {
    final site = await (_siteFuture ??= rust_huya.LiveHuyaSite.default_());
    final pending = _pendingAttrs;
    if (pending != null) {
      site.setSiteAttrs(data: pending);
      _pendingAttrs = null;
    }
    return site;
  }

  @override
  LiveDanmaku getDanmaku() => RustHuyaDanmaku();

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
  Future<AccountInfo> getAccountInfo({required String credential}) async =>
      RustSiteModels.toCoreAccountInfo(
        await (await _site()).getAccountInfo(credential: credential),
      );

  @override
  Future<QRCode> getQRCode() async =>
      RustSiteModels.toCoreQrCode(await (await _site()).getQrCode());

  @override
  Future<QRPollResult> getQRPollResult({required String qrcodeKey}) async =>
      RustSiteModels.toCoreQrPollResult(
        await (await _site()).getQrPollResult(qrcodeKey: qrcodeKey),
      );
}

/// 弹幕适配：core 的回调式 `LiveDanmaku` -> Rust 的 Stream。
///
/// `start(args)` 的 `args` 为 `detail.danmakuData` 原样透传（JSON 串，
/// Rust 侧 `from_json` 解析失败抛 `CoreError` —— J-10）。
/// 心跳由 Rust 会话内部管理（60s），Dart 侧 `heartbeat()` / `heartbeatTime` 不参与。
class RustHuyaDanmaku extends LiveDanmaku {
  StreamSubscription<rust_danmu.LiveDanmuItem>? _subscription;
  bool _stopped = true;

  @override
  Future<void> start(dynamic args) async {
    if (args is! String) {
      throw ArgumentError.value(
        args,
        'args',
        '虎牙弹幕参数应为 Rust 契约的 JSON 串（detail.danmakuData）',
      );
    }
    _stopped = true;
    await _subscription?.cancel();
    _stopped = false;
    _subscription = rust_huya_danmaku.startHuyaDanmaku(argsJson: args).listen(
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
        debugPrint('[rust-huya-danmaku] stream ERROR: $e');
      },
      // Rust 会话异常退出（如线程 panic）时 sink 被 drop，流会静默 onDone；
      // 不接这个回调的话 UI 看起来就是"弹幕卡住"，没有任何提示。
      onDone: () {
        if (!_stopped) {
          onClose?.call('弹幕连接已断开');
        }
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    rust_huya_danmaku.stopHuyaDanmaku();
    await _subscription?.cancel();
    _subscription = null;
  }
}