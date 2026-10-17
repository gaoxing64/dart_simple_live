//! 斗鱼 Rust Core 模型 -> simple_live_core 模型的类型翻译层。
//!
//! 纪律（AC-39 / J-6）：**只做逐字段映射，零协议逻辑**。
//! - `danmakuData`（斗鱼=房间号）与 `quality.data`（斗鱼=`{"rate":..,"cdns":[..]}` JSON 串）
//!   **原样透传**：App 侧 `liveDanmaku.start(detail.danmakuData)` 与取流链路直接消费，
//!   绑定层**不解析**（解析责任在 Rust 侧，失败抛 `CoreError` —— J-10）。
//!
//! 与 B站 `rust_site_models.dart` 的差别：独立文件、只服务斗鱼（多平台并行期间互不覆盖）。

import 'package:simple_live_core/src/rust/api/slive/models/account.dart' as rust_acc;
import 'package:simple_live_core/src/rust/api/slive/models/category.dart' as rust_cat;
import 'package:simple_live_core/src/rust/api/slive/models/message.dart' as rust_msg;
import 'package:simple_live_core/src/rust/api/slive/models/play.dart' as rust_play;
import 'package:simple_live_core/src/rust/api/slive/models/result.dart' as rust_result;
import 'package:simple_live_core/src/rust/api/slive/models/room.dart' as rust_room;
import 'package:simple_live_core/simple_live_core.dart';

/// 斗鱼的 Rust -> core 模型映射集合（纯静态函数）。
class RustDouyuModels {
  RustDouyuModels._();

  static LiveCategory toCoreCategory(rust_cat.LiveCategory v) => LiveCategory(
        id: v.id,
        name: v.name,
        children: v.children.map(toCoreSubCategory).toList(),
      );

  static LiveSubCategory toCoreSubCategory(rust_cat.LiveSubCategory v) =>
      LiveSubCategory(
        id: v.id,
        name: v.name,
        parentId: v.parentId,
        pic: v.pic,
      );

  /// 反向翻译（分类下房间回传 Rust）。
  static rust_cat.LiveSubCategory toRustSubCategory(LiveSubCategory v) =>
      rust_cat.LiveSubCategory(
        id: v.id,
        name: v.name,
        parentId: v.parentId,
        pic: v.pic,
      );

  static LiveRoomItem toCoreRoomItem(rust_room.LiveRoomItem v) => LiveRoomItem(
        roomId: v.roomId,
        title: v.title,
        cover: v.cover,
        userName: v.userName,
        online: v.online,
      );

  static LiveAnchorItem toCoreAnchorItem(rust_room.LiveAnchorItem v) =>
      LiveAnchorItem(
        roomId: v.roomId,
        avatar: v.avatar,
        userName: v.userName,
        liveStatus: v.liveStatus,
      );

  static LiveSearchRoomResult toCoreSearchRoom(rust_result.LiveSearchRoomResult v) =>
      LiveSearchRoomResult(
        hasMore: v.hasMore,
        items: v.items.map(toCoreRoomItem).toList(),
      );

  static LiveSearchAnchorResult toCoreSearchAnchor(
          rust_result.LiveSearchAnchorResult v) =>
      LiveSearchAnchorResult(
        hasMore: v.hasMore,
        items: v.items.map(toCoreAnchorItem).toList(),
      );

  static LiveCategoryResult toCoreCategoryResult(
          rust_result.LiveCategoryResult v) =>
      LiveCategoryResult(
        hasMore: v.hasMore,
        items: v.items.map(toCoreRoomItem).toList(),
      );

  /// 房间详情：`danmakuData`（斗鱼=房间号）原样透传，App 直接传给 `liveDanmaku.start`。
  static LiveRoomDetail toCoreRoomDetail(rust_room.LiveRoomDetail v) =>
      LiveRoomDetail(
        roomId: v.roomId,
        title: v.title,
        cover: v.cover,
        userName: v.userName,
        userAvatar: v.userAvatar,
        online: v.online,
        introduction: v.introduction,
        notice: v.notice,
        status: v.status,
        data: v.data,
        danmakuData: v.danmakuData,
        isRecord: v.isRecord,
        url: v.url,
      );

  /// 反向翻译（取流链路回传 Rust）：`danmakuData` 原样透传。
  static rust_room.LiveRoomDetail toRustRoomDetail(LiveRoomDetail v) =>
      rust_room.LiveRoomDetail(
        roomId: v.roomId,
        title: v.title,
        cover: v.cover,
        userName: v.userName,
        userAvatar: v.userAvatar,
        online: v.online,
        introduction: v.introduction,
        notice: v.notice,
        status: v.status,
        data: v.data is String ? v.data as String : null,
        danmakuData:
            v.danmakuData is String ? v.danmakuData as String : null,
        isRecord: v.isRecord,
        url: v.url,
      );

  /// 清晰度：`data` 是 Rust 侧的 `{"rate":..,"cdns":[..]}` JSON 串，原样透传。
  static LivePlayQuality toCorePlayQuality(rust_play.LivePlayQuality v) =>
      LivePlayQuality(quality: v.quality, data: v.data, sort: v.sort);

  /// 反向翻译：`data` 必须原样回传（Rust 侧解析失败会抛 `CoreError`）。
  static rust_play.LivePlayQuality toRustPlayQuality(LivePlayQuality v) =>
      rust_play.LivePlayQuality(
        quality: v.quality,
        data: v.data?.toString() ?? '',
        sort: v.sort,
      );

  static LivePlayUrl toCorePlayUrl(rust_play.LivePlayUrl v) => LivePlayUrl(
        urls: v.urls,
        headers: v.headers,
      );

  static LiveSuperChatMessage toCoreSuperChat(rust_msg.LiveSuperChatMessage v) =>
      LiveSuperChatMessage(
        userName: v.userName,
        face: v.face,
        message: v.message,
        price: v.price,
        startTime: v.startTime,
        endTime: v.endTime,
        backgroundColor: v.backgroundColor,
        backgroundBottomColor: v.backgroundBottomColor,
      );

  static LiveMessage toCoreMessage(rust_msg.LiveMessage v) => LiveMessage(
        type: toCoreMessageType(v.messageType),
        userName: v.userName,
        message: v.message,
        userId: v.userId,
        color: LiveMessageColor(v.color.r, v.color.g, v.color.b),
        data: toCoreMessageData(v.data),
        emoticons: v.emoticons?.map(toCoreEmoticon).toList(),
      );

  static LiveMessageType toCoreMessageType(rust_msg.LiveMessageType v) =>
      switch (v) {
        rust_msg.LiveMessageType.chat => LiveMessageType.chat,
        rust_msg.LiveMessageType.gift => LiveMessageType.gift,
        rust_msg.LiveMessageType.online => LiveMessageType.online,
        rust_msg.LiveMessageType.superChat => LiveMessageType.superChat,
      };

  /// `data`：Rust 类型化枚举 -> core `dynamic`（人气 int / SC 结构体）。
  static dynamic toCoreMessageData(rust_msg.LiveMessageData? v) {
    if (v == null) {
      return null;
    }
    return switch (v) {
      rust_msg.LiveMessageData_Online(:final field0) => field0,
      rust_msg.LiveMessageData_SuperChat(:final field0) => toCoreSuperChat(field0),
    };
  }

  static LiveMessageEmoticon toCoreEmoticon(rust_msg.LiveMessageEmoticon v) =>
      LiveMessageEmoticon(
        name: v.name,
        url: v.url,
        width: v.width,
        height: v.height,
        large: v.large,
        emoticonUnique: v.emoticonUnique,
      );

  static QRCode toCoreQrCode(rust_acc.QrCode v) => QRCode(key: v.key, url: v.url);

  static QRPollResult toCoreQrPollResult(rust_acc.QrPollResult v) =>
      QRPollResult(
        status: toCoreQrStatus(v.status),
        credential: v.credential,
      );

  static QRStatus toCoreQrStatus(rust_acc.QrStatus v) => switch (v) {
        rust_acc.QrStatus.loading => QRStatus.loading,
        rust_acc.QrStatus.unscanned => QRStatus.unscanned,
        rust_acc.QrStatus.scanned => QRStatus.scanned,
        rust_acc.QrStatus.expired => QRStatus.expired,
        rust_acc.QrStatus.failed => QRStatus.failed,
      };

  static AccountInfo toCoreAccountInfo(rust_acc.AccountInfo v) {
    var info = AccountInfo();
    return info.copyWith(
      name: v.name,
      avatar: v.avatar,
      uid: v.uid,
      credential: v.credential,
      isValid: v.isValid,
    );
  }
}