//! Rust Core 模型 -> simple_live_core 模型的类型翻译层（抖音专属）。
//!
//! 纪律（AC-39 / J-6）：只做逐字段映射，零协议逻辑；`danmakuData`、`detail.data`、
//! `quality.data` 三个通道**原样透传**（不在绑定层解析 —— J-10：解析责任在 Rust 侧，
//! 失败必须抛 `FormatException`，不得静默兜底）。
//!
//! 与 `rust_site_models.dart`（B站）的差异集中在两处**类型翻译**：
//! 1. `LivePlayQuality.data`：core 是 `List<String>`（抖音的画质 data 就是地址数组），
//!    Rust 侧是 JSON 数组串 -> 双向 `jsonEncode` / `jsonDecode`；
//! 2. `LiveMessage.data`：Rust 的类型化枚举 -> core 的 `dynamic`（人气 int）。
//! 其余（分类/房间/播放/SC/账号/二维码）逐字段同名映射。

import 'dart:convert';

import 'package:simple_live_core/src/rust/api/slive/models/account.dart' as rust_acc;
import 'package:simple_live_core/src/rust/api/slive/models/message.dart' as rust_msg;
import 'package:simple_live_core/src/rust/api/slive/models/play.dart' as rust_play;
import 'package:simple_live_core/src/rust/api/slive/models/room.dart' as rust_room;
import 'package:simple_live_core/simple_live_core.dart';

/// 抖音专用的 Rust <-> core 模型翻译（纯静态函数，零协议逻辑）。
class RustDouyinModels {
  RustDouyinModels._();

  /// Rust 画质 -> core 画质：`data` 是地址数组的 JSON 串，须还原为 `List`。
  ///
  /// 解析失败抛 `FormatException`（J-10）——静默返回空列表会让播放器拿到空地址却不报错。
  static LivePlayQuality toCorePlayQuality(rust_play.LivePlayQuality v) =>
      LivePlayQuality(
        quality: v.quality,
        sort: v.sort,
        data: _decodeUrls(v.data),
      );

  /// core 画质 -> Rust 画质：地址数组序列化成 JSON 串（类型翻译，非协议逻辑）。
  static rust_play.LivePlayQuality toRustPlayQuality(LivePlayQuality v) =>
      rust_play.LivePlayQuality(
        quality: v.quality,
        sort: v.sort,
        data: v.data == null ? '' : jsonEncode(v.data),
      );

  /// Rust 房间详情 -> core：两个数据通道原样透传。
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

  /// core 房间详情 -> Rust（取流链路回传）：通道原样透传。
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

  /// Rust 播放地址 -> core（`headers` 抖音侧恒为 null，原样透传）。
  static LivePlayUrl toCorePlayUrl(rust_play.LivePlayUrl v) => LivePlayUrl(
        urls: v.urls,
        headers: v.headers,
      );

  /// Rust 弹幕消息 -> core 消息。
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

  /// 类型化枚举 -> core `dynamic`（人气 int / SC 结构体）。
  static dynamic toCoreMessageData(rust_msg.LiveMessageData? v) {
    if (v == null) {
      return null;
    }
    return switch (v) {
      rust_msg.LiveMessageData_Online(:final field0) => field0,
      rust_msg.LiveMessageData_SuperChat(:final field0) =>
        LiveSuperChatMessage(
          userName: field0.userName,
          face: field0.face,
          message: field0.message,
          price: field0.price,
          startTime: field0.startTime,
          endTime: field0.endTime,
          backgroundColor: field0.backgroundColor,
          backgroundBottomColor: field0.backgroundBottomColor,
        ),
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

  /// 地址数组 JSON 串 -> `List<String>`。
  ///
  /// 空串 -> 空列表；非法 JSON 抛 `FormatException`（J-10）。
  static List<String> _decodeUrls(String raw) {
    if (raw.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('播放地址通道应为 JSON 数组，实际: $raw');
    }
    return decoded.map((e) => e.toString()).toList();
  }
}
