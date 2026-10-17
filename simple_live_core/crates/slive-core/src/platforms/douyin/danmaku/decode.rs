//! 抖音弹幕帧解码：`PushFrame` → gzip → `Response` → [`LiveMessage`]。
//!
//! 对照 Dart `DouyinDanmaku.decodeMessage`（`douyin_danmaku.dart:133-182`）：
//! ```text
//! PushFrame.fromBuffer(bytes) → gzip.decode(payload) → Response.fromBuffer
//!   → needAck 则 sendAck(logId, internalExt)
//!   → messagesList 逐条按 method 分发：
//!       WebcastChatMessage      → LiveMessage(type: chat,  color: white, message: content, userName: user.nickName,
//!                                              emoticons: content 中的标准表情码)
//!       WebcastRoomUserSeqMessage→ LiveMessage(type: online, data: totalUser, color: white)
//!       WebcastEmojiChatMessage → LiveMessage(type: chat, emoticons: emojiContent 里的图片)
// ```
//!
//! 未知 method **静默跳过**（Dart 的 if/else 链亦然；服务端会持续下发点赞/礼物/
//! 进场等十几种 method，硬解只会产生噪音日志）。

use std::io::Read;

use flate2::read::GzDecoder;
use prost::Message as _;

use crate::error::SliveError;
use crate::models::{
    LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageEmoticon, LiveMessageType,
};

use super::emoticon::extract_emoticons;
use super::proto::{ChatMessage, EmojiChatMessage, PushFrame, Response, RoomUserSeqMessage};

/// 帧载荷类型：业务消息。
pub const PAYLOAD_TYPE_MSG: &str = "msg";
/// 帧载荷类型：心跳。
pub const PAYLOAD_TYPE_HB: &str = "hb";
/// 帧载荷类型：ack 回执。
pub const PAYLOAD_TYPE_ACK: &str = "ack";

/// 方法名：聊天弹幕。
pub const METHOD_CHAT: &str = "WebcastChatMessage";
/// 方法名：在线人数。
pub const METHOD_ROOM_USER_SEQ: &str = "WebcastRoomUserSeqMessage";
/// 方法名：会员表情 / 表情包弹幕。
pub const METHOD_EMOJI_CHAT: &str = "WebcastEmojiChatMessage";

/// 解码一帧为业务消息列表。
///
/// 帧不是 `msg` 类型（`hb` / `ack`）时返回空列表（Dart 也会解出空 `messagesList`）。
pub fn decode_frame(frame: &[u8]) -> Result<Vec<LiveMessage>, SliveError> {
    let push = PushFrame::decode(frame)
        .map_err(|e| SliveError::decode(format!("PushFrame 解码失败: {e}")))?;
    if push.payload_type != PAYLOAD_TYPE_MSG || push.payload.is_empty() {
        return Ok(Vec::new());
    }
    let response = decode_response(&push.payload)?;
    let mut out = Vec::with_capacity(response.messages_list.len());
    for msg in &response.messages_list {
        if let Some(message) = decode_payload(&msg.method, &msg.payload) {
            out.push(message);
        }
    }
    Ok(out)
}

/// 解码 `Response` 的 gzip 载荷；空载荷 -> 空 `Response`（心跳帧无 body）。
pub fn decode_response(payload: &[u8]) -> Result<Response, SliveError> {
    if payload.is_empty() {
        return Ok(Response::default());
    }
    let mut decompressed = Vec::new();
    GzDecoder::new(payload)
        .read_to_end(&mut decompressed)
        .map_err(|e| SliveError::decode(format!("弹幕载荷 gzip 解压失败: {e}")))?;
    Response::decode(decompressed.as_slice())
        .map_err(|e| SliveError::decode(format!("Response 解码失败: {e}")))
}

/// 按 method 分发单条消息；未知 method -> `None`。
fn decode_payload(method: &str, payload: &[u8]) -> Option<LiveMessage> {
    match method {
        METHOD_CHAT => decode_chat(payload).ok(),
        METHOD_EMOJI_CHAT => decode_emoji_chat(payload).ok(),
        METHOD_ROOM_USER_SEQ => decode_room_user_seq(payload).ok(),
        _ => None,
    }
}

/// `WebcastChatMessage` -> 聊天消息（Dart 固定白色，注释说明颜色转换方式未知）。
fn decode_chat(payload: &[u8]) -> Result<LiveMessage, SliveError> {
    let chat = ChatMessage::decode(payload)
        .map_err(|e| SliveError::decode(format!("ChatMessage 解码失败: {e}")))?;
    let emoticons = extract_emoticons(&chat.content);
    Ok(LiveMessage {
        message_type: LiveMessageType::Chat,
        user_name: chat
            .user
            .as_ref()
            .map(|u| u.nick_name.clone())
            .unwrap_or_default(),
        user_id: None,
        message: chat.content,
        data: None,
        color: LiveMessageColor::white(),
        emoticons,
    })
}

/// `WebcastEmojiChatMessage` -> 聊天消息（表情图片挂在 `emoticons`）。
///
/// `defaultContent` 是占位文案（线上为 `[表情]`），首张图片用它做 name，
/// 渲染层会把占位符替换成图片；没有图片时退化为普通文本，避免整条消息消失。
fn decode_emoji_chat(payload: &[u8]) -> Result<LiveMessage, SliveError> {
    let chat = EmojiChatMessage::decode(payload)
        .map_err(|e| SliveError::decode(format!("EmojiChatMessage 解码失败: {e}")))?;
    let mut emoticons = Vec::new();
    let mut placeholder_used = false;
    if let Some(content) = &chat.emoji_content {
        for piece in &content.pieces_list {
            let Some(image) = piece
                .image_value
                .as_ref()
                .and_then(|value| value.image.as_ref())
            else {
                continue;
            };
            let Some(url) = pick_image_url(&image.url_list) else {
                continue;
            };
            let name = if !placeholder_used && !chat.default_content.is_empty() {
                placeholder_used = true;
                Some(chat.default_content.clone())
            } else {
                None
            };
            emoticons.push(LiveMessageEmoticon {
                name,
                url,
                // 线上会员表情 / 守护表情都不下发宽高；渲染层按图片固有比例处理。
                // 整条消息就是一个独立表情，与大表情（B站 info[0][13]）同构。
                width: image_dimension(image.width),
                height: image_dimension(image.height),
                large: true,
                emoticon_unique: None,
            });
        }
    }
    let message = if chat.default_content.is_empty() && emoticons.is_empty() {
        "[表情]".to_string()
    } else {
        chat.default_content
    };
    Ok(LiveMessage {
        message_type: LiveMessageType::Chat,
        user_name: chat
            .user
            .as_ref()
            .map(|u| u.nick_name.clone())
            .unwrap_or_default(),
        user_id: None,
        message,
        data: None,
        color: LiveMessageColor::white(),
        emoticons: (!emoticons.is_empty()).then_some(emoticons),
    })
}

/// 取第一张可用的 https 图片地址；`http://` 与协议相对地址统一升 https。
fn pick_image_url(urls: &[String]) -> Option<String> {
    urls.iter().find_map(|raw| {
        let url = raw.trim();
        if let Some(rest) = url.strip_prefix("https://") {
            return Some(format!("https://{rest}"));
        }
        if let Some(rest) = url.strip_prefix("http://") {
            return Some(format!("https://{rest}"));
        }
        url.strip_prefix("//").map(|_| format!("https:{url}"))
    })
}

/// 服务端宽高（u64）-> 模型 i32；0 或缺省视为未知。
fn image_dimension(value: u64) -> Option<i32> {
    i32::try_from(value).ok().filter(|v| *v > 0)
}

/// `WebcastRoomUserSeqMessage` -> 在线人气（`total_user` 收敛为 i32，对齐 core 模型）。
fn decode_room_user_seq(payload: &[u8]) -> Result<LiveMessage, SliveError> {
    let seq = RoomUserSeqMessage::decode(payload)
        .map_err(|e| SliveError::decode(format!("RoomUserSeqMessage 解码失败: {e}")))?;
    let online = i32::try_from(seq.total_user).unwrap_or(i32::MAX);
    Ok(LiveMessage {
        message_type: LiveMessageType::Online,
        user_name: String::new(),
        user_id: None,
        message: String::new(),
        data: Some(LiveMessageData::Online(online)),
        color: LiveMessageColor::white(),
        emoticons: None,
    })
}

/// 心跳帧：`PushFrame{payload_type: "hb"}`，无 body（对齐 Dart `heartbeat()`）。
pub fn heartbeat_frame() -> Vec<u8> {
    PushFrame {
        payload_type: PAYLOAD_TYPE_HB.to_string(),
        ..Default::default()
    }
    .encode_to_vec()
}

/// ack 回帧：回带 `log_id` 与 `internal_ext`。
///
/// ⚠️ **刻意偏离 Dart**：`douyin_danmaku.dart:184-190` 的 `sendAck` 写成
/// ```dart
/// obj.payloadType = 'ack';
/// obj.logId = logId;
/// obj.payloadType = internalExt;   // ← 覆盖了上一行的 payloadType
/// ```
/// 即 `payloadType` 最终是 `internalExt`（一段长文本）而非 `ack`，且 `internalExt`
/// 从未写进 `payload`。照抄会发出服务端无法识别的帧（`payload_type` 既非 `ack`
/// 也非 `msg`，连接随即被服务端断开），属「沉默逻辑错误」的高发形态。
/// 这里按 proto 语义（`PushFrame.payload`）与 DTV 参考实现落地：
/// `payload_type = "ack"`、`payload = internal_ext 的 UTF-8 字节`、`log_id` 回带。
pub fn ack_frame(log_id: u64, internal_ext: &str) -> Vec<u8> {
    PushFrame {
        payload_type: PAYLOAD_TYPE_ACK.to_string(),
        log_id,
        payload: internal_ext.as_bytes().to_vec(),
        ..Default::default()
    }
    .encode_to_vec()
}

/// 从帧里取出 ack 所需信息（`(log_id, internal_ext)`）；无需 ack 时 `None`。
pub fn pending_ack(frame: &[u8]) -> Result<Option<(u64, String)>, SliveError> {
    let push = PushFrame::decode(frame)
        .map_err(|e| SliveError::decode(format!("PushFrame 解码失败: {e}")))?;
    if push.payload_type != PAYLOAD_TYPE_MSG || push.payload.is_empty() {
        return Ok(None);
    }
    let response = decode_response(&push.payload)?;
    if response.need_ack {
        Ok(Some((push.log_id, response.internal_ext)))
    } else {
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;

    use crate::models::LiveMessageType;
    use crate::platforms::douyin::danmaku::proto::{
        ChatMessage, EmojiChatMessage, Image, Message, Text, TextPiece, TextPieceImage, User,
    };
    use std::io::Write;

    fn chat_payload(content: &str, nick: &str) -> Vec<u8> {
        ChatMessage {
            content: content.to_string(),
            user: Some(User {
                nick_name: nick.to_string(),
                ..Default::default()
            }),
            ..Default::default()
        }
        .encode_to_vec()
    }

    fn gzip(data: &[u8]) -> Vec<u8> {
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(data).expect("压缩");
        encoder.finish().expect("收尾")
    }

    fn push_frame(
        log_id: u64,
        messages: Vec<Message>,
        need_ack: bool,
        internal_ext: &str,
    ) -> Vec<u8> {
        let response = Response {
            messages_list: messages,
            need_ack,
            internal_ext: internal_ext.to_string(),
            ..Default::default()
        };
        PushFrame {
            log_id,
            payload_type: PAYLOAD_TYPE_MSG.to_string(),
            payload: gzip(&response.encode_to_vec()),
            ..Default::default()
        }
        .encode_to_vec()
    }

    #[test]
    fn decodes_chat_message_to_live_message() {
        let msg = Message {
            method: METHOD_CHAT.to_string(),
            payload: chat_payload("你好", "小明"),
            msg_id: 1,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(7, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message_type, LiveMessageType::Chat);
        assert_eq!(got.message, "你好");
        assert_eq!(got.user_name, "小明");
        assert_eq!(got.color, LiveMessageColor::white());
        assert!(got.data.is_none());
    }

    #[test]
    fn decodes_standard_emoji_codes_in_chat() {
        let msg = Message {
            method: METHOD_CHAT.to_string(),
            payload: chat_payload("哈喽[微笑][赞]", "小明"),
            msg_id: 8,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(14, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message, "哈喽[微笑][赞]", "正文保持原样，由渲染层替换");
        let emoticons = got.emoticons.expect("应带标准表情");
        let names: Vec<&str> = emoticons
            .iter()
            .filter_map(|e| e.name.as_deref())
            .collect();
        assert_eq!(names, vec!["[微笑]", "[赞]"]);
        assert!(emoticons.iter().all(|e| !e.large));
        assert!(emoticons.iter().all(|e| e.url.starts_with("https://")));
    }

    #[test]
    fn unknown_bracket_text_stays_plain() {
        let msg = Message {
            method: METHOD_CHAT.to_string(),
            payload: chat_payload("[不存在]", "小明"),
            msg_id: 9,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(15, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message, "[不存在]");
        assert!(got.emoticons.is_none(), "表外方括号不得被吞掉");
    }

    #[test]
    fn decodes_room_user_seq_to_online() {
        let msg = Message {
            method: METHOD_ROOM_USER_SEQ.to_string(),
            payload: RoomUserSeqMessage {
                total_user: 4321,
                ..Default::default()
            }
            .encode_to_vec(),
            msg_id: 2,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(8, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message_type, LiveMessageType::Online);
        assert_eq!(got.data, Some(LiveMessageData::Online(4321)));
        assert_eq!(got.user_name, "", "人气消息无用户名（Dart 传空串）");
    }

    fn emoji_chat_payload(
        default_content: &str,
        nick: &str,
        images: Vec<(&str, u64, u64)>,
    ) -> Vec<u8> {
        EmojiChatMessage {
            user: Some(User {
                nick_name: nick.to_string(),
                ..Default::default()
            }),
            default_content: default_content.to_string(),
            emoji_content: Some(Text {
                pieces_list: images
                    .into_iter()
                    .map(|(url, width, height)| TextPiece {
                        r#type: 15,
                        schema_key: "subscribe_emoji".to_string(),
                        image_value: Some(TextPieceImage {
                            image: Some(Image {
                                url_list: vec![url.to_string()],
                                width,
                                height,
                                ..Default::default()
                            }),
                            scaling_rate: 2.25,
                        }),
                        ..Default::default()
                    })
                    .collect(),
                ..Default::default()
            }),
            ..Default::default()
        }
        .encode_to_vec()
    }

    #[test]
    fn decodes_emoji_chat_to_chat_with_emoticon() {
        let msg = Message {
            method: METHOD_EMOJI_CHAT.to_string(),
            payload: emoji_chat_payload("[表情]", "小明", vec![("https://cdn/a.png", 0, 0)]),
            msg_id: 4,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(10, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message_type, LiveMessageType::Chat);
        assert_eq!(got.message, "[表情]");
        assert_eq!(got.user_name, "小明");
        let emoticons = got.emoticons.expect("应带表情");
        assert_eq!(emoticons.len(), 1);
        assert_eq!(emoticons[0].name.as_deref(), Some("[表情]"));
        assert_eq!(emoticons[0].url, "https://cdn/a.png");
        assert_eq!(
            (emoticons[0].width, emoticons[0].height),
            (None, None),
            "服务端不下发宽高，渲染层按图片固有比例处理"
        );
        assert!(
            emoticons[0].large,
            "整条消息就是一个独立表情，按大表情口径渲染（对齐 B 站 info[0][13]）"
        );
    }

    #[test]
    fn emoji_chat_uses_server_size_and_upgrades_http() {
        let msg = Message {
            method: METHOD_EMOJI_CHAT.to_string(),
            payload: emoji_chat_payload("[表情]", "小明", vec![("http://cdn/a.png", 340, 256)]),
            msg_id: 5,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(11, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        let emoticon = &got.emoticons.expect("应带表情")[0];
        assert_eq!(emoticon.url, "https://cdn/a.png", "http 一律升 https");
        assert_eq!((emoticon.width, emoticon.height), (Some(340), Some(256)));
    }

    #[test]
    fn emoji_chat_with_multiple_images_names_only_the_first() {
        let msg = Message {
            method: METHOD_EMOJI_CHAT.to_string(),
            payload: emoji_chat_payload(
                "[表情]",
                "小明",
                vec![("https://cdn/a.png", 0, 0), ("https://cdn/b.png", 0, 0)],
            ),
            msg_id: 6,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(12, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        let emoticons = got.emoticons.expect("应带表情");
        assert_eq!(emoticons.len(), 2);
        assert_eq!(emoticons[0].name.as_deref(), Some("[表情]"));
        assert!(emoticons[1].name.is_none(), "重复 name 会让第二张被丢弃");
    }

    #[test]
    fn emoji_chat_without_image_falls_back_to_text() {
        let msg = Message {
            method: METHOD_EMOJI_CHAT.to_string(),
            payload: EmojiChatMessage {
                user: Some(User {
                    nick_name: "小明".to_string(),
                    ..Default::default()
                }),
                default_content: "[表情]".to_string(),
                ..Default::default()
            }
            .encode_to_vec(),
            msg_id: 7,
            msg_type: 0,
        };
        let got = decode_frame(&push_frame(13, vec![msg], false, ""))
            .expect("应能解码")
            .remove(0);
        assert_eq!(got.message, "[表情]");
        assert!(got.emoticons.is_none());
    }

    #[test]
    fn unknown_method_is_skipped() {
        let msg = Message {
            method: "WebcastLikeMessage".to_string(),
            payload: vec![8, 1],
            msg_id: 3,
            msg_type: 0,
        };
        assert!(decode_frame(&push_frame(9, vec![msg], false, ""))
            .expect("应能解码")
            .is_empty());
    }

    #[test]
    fn heartbeat_frame_yields_no_messages() {
        assert!(decode_frame(&heartbeat_frame())
            .expect("心跳帧应能解")
            .is_empty());
    }

    #[test]
    fn ack_frame_encodes_log_id_and_internal_ext() {
        let raw = ack_frame(123, "internal-ext");
        let back = PushFrame::decode(raw.as_slice()).expect("应能解码");
        assert_eq!(back.payload_type, "ack");
        assert_eq!(back.log_id, 123);
        assert_eq!(String::from_utf8(back.payload).expect("utf8"), "internal-ext");
    }

    #[test]
    fn pending_ack_reads_log_id_and_internal_ext() {
        let frame = push_frame(555, vec![], true, "ext-abc");
        assert_eq!(
            pending_ack(&frame).expect("应能解析"),
            Some((555, "ext-abc".to_string()))
        );
        let no_ack = push_frame(556, vec![], false, "ext-xyz");
        assert_eq!(pending_ack(&no_ack).expect("应能解析"), None);
    }

    #[test]
    fn dirty_frame_reports_decode_error_not_panic() {
        // 非法 protobuf：0xFF 起始字节组不完整
        assert!(decode_frame(&[0xff, 0xff, 0xff]).is_err());
        // payload_type=msg 但 payload 非 gzip
        let bad = PushFrame {
            payload_type: PAYLOAD_TYPE_MSG.to_string(),
            payload: vec![1, 2, 3, 4],
            ..Default::default()
        }
        .encode_to_vec();
        assert!(matches!(
            decode_frame(&bad),
            Err(SliveError::Decode(_))
        ));
    }
}
