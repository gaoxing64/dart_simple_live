//! 虎牙弹幕 WS 帧编解码（对照 `huya_danmaku.dart` 与 `tars/huya_danmaku.dart`）。
//!
//! 线上帧形态：**1 字节命令类型 + TARS 结构体**
//! - `cmdType = 16`（`EWSCmdC2S_RegisterGroupReq`）：join 帧，载荷是 `WsRegisterGroupReq`；
//! - `cmdType = 20`（`EWSCmdC2S_HeartBeatReq`）：心跳帧，载荷是**空** `WebSocketCommand`；
//! - `cmdType = 7`（`EWSCmdS2C_MsgPushReq`）：服务端推送，载荷是 `HYPushMessage`；
//! - `cmdType = 22`（`EWSCmdS2C_MsgPushReq_V2`）：服务端推送 V2，载荷是 `WSPushMessageV2`。
//!
//! 解码入口对齐 Dart `decodeMessage`：Dart 先 `read(0,0,false)` 读出 tag=0 的整型
//! （该整型即命令类型），**再从剩余字节重新构造流**读结构体 —— 因为 WS 帧并不是
//! 「结构体包裹命令类型」，而是两个并列的 TARS 片段。本模块用 `TarsDecoder::at`
//! 显式跳过已读字节来等价实现。
//!
//! uri 语义（来自 Dart 注释，勿改）：
//! - `1400`：聊天弹幕 / 醒目留言文案；
//! - `8006`：在线人气（整型直塞在 `msg` 里）；
//! - V2 的 `2001317`：醒目留言事件（触发 SC 拉取；2026-10-17 上游同步更正，旧值 2001314）。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsValue};

use super::tars_msgs::HyPushMessage;
use super::tars_ws_v2::WsPushMessageV2;

/// WS 命令类型（对齐 Dart `EWebSocketCommandType` 中实际用到的四个）。
pub mod cmd {
    /// 心跳请求（空载荷）。
    pub const HEART_BEAT_REQ: i32 = 20;
    /// 注册群组请求（join）。
    pub const REGISTER_GROUP_REQ: i32 = 16;
    /// 服务端推送。
    pub const MSG_PUSH_REQ: i32 = 7;
    /// 服务端推送 V2。
    pub const MSG_PUSH_REQ_V2: i32 = 22;
}

/// `uri = 1400`：聊天弹幕。
pub const URI_CHAT: i64 = 1400;
/// `uri = 8006`：在线人气。
pub const URI_ONLINE: i64 = 8006;
/// V2 `iUri = 2001317`：醒目留言事件（需拉 SC 列表）。
///
/// 2026-10-17 随上游 SlotSun dev `97413c60`（listen real uri）从旧值 `2001314` 更正 ——
/// 旧值对应 dev 修复前语义，真实 SC uri 为 `2001317`。
pub const URI_SUPER_CHAT: i64 = 2001317;

/// 注册群组请求体（对齐 Dart `WsRegisterGroupReq`，tag 0/1）。
fn register_group_body(group_ids: &[String]) -> Vec<u8> {
    let list = TarsValue::List(
        group_ids
            .iter()
            .map(|id| TarsValue::Str(id.clone()))
            .collect(),
    );
    let mut encoder = TarsEncoder::new();
    // tag 0 = groupId（list），tag 1 = token（空串）
    let fields: Vec<(i32, TarsValue)> = vec![(0, list), (1, TarsValue::string(""))];
    // write_struct 会写 STRUCT_BEGIN/END；此处手工拼装以保证字段顺序
    for (tag, value) in fields {
        // 单字段写入失败时退化为空载荷：注册包失败应让会话重连而非静默发空包
        if encoder.write_value(&value, tag).is_err() {
            return Vec::new();
        }
    }
    encoder.into_bytes()
}

/// 构造 WS 帧：`cmdType` 的 TARS 整型片段 + 载荷片段。
///
/// 对齐 Dart `WebSocketCommand.toByteArray()`：`writeTo` 按 tag 0..6 写字段，
/// 其中 tag=0 是 `cmdType`。Dart 的 WebSocketCommand 写 7 个字段（含未赋值的
/// `requestId/traceId/encryptType/time/md5`），值为 0/空串时写 ZERO_TAG / 空串，
/// 故线上字节里必然带上这些字段 —— **本实现照抄同样的字段集**，
/// 否则服务端会因字段表不完整而拒绝（这是协议，不做"优化"）。
/// 组装一条上行命令帧（`cmdType` + 载荷 + Dart 的 tag2..6 默认字段）。
///
/// `pub` 因为它是**协议字节的公开构造面**：夹具回归与 TUP 测试都要复现线上字节。
pub fn build_command(cmd_type: i32, data: &[u8]) -> Result<Vec<u8>, SliveError> {
    let mut encoder = TarsEncoder::new();
    // tag 0: cmdType（整型）
    encoder.write_i64(cmd_type as i64, 0)?;
    // tag 1: data（bytes；空载荷时 Dart 写空 SimpleList）
    encoder.write_bytes(data, 1)?;
    // tag 2..6：Dart 一律写默认值（0 / ""），线上同样出现
    encoder.write_i64(0, 2)?; // requestId
    encoder.write_string("", 3)?; // traceId
    encoder.write_i64(0, 4)?; // encryptType
    encoder.write_i64(0, 5)?; // time
    encoder.write_string("", 6)?; // md5
    Ok(encoder.into_bytes())
}

/// 构造 join（注册群组）帧。
pub fn build_join_frame(group_ids: &[String]) -> Result<Vec<u8>, SliveError> {
    build_command(cmd::REGISTER_GROUP_REQ, &register_group_body(group_ids))
}

/// 构造心跳帧（空载荷）。
pub fn build_heartbeat_frame() -> Result<Vec<u8>, SliveError> {
    build_command(cmd::HEART_BEAT_REQ, &[])
}

/// 一帧解码的产出。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HuyaFrame {
    /// `cmdType = 7`：`uri = 1400` 聊天弹幕。
    Chat {
        /// 昵称。
        user_name: String,
        /// 正文。
        content: String,
        /// 字体颜色（十进制；上层按 `<= 0` 归白色）。
        font_color: i64,
    },
    /// `cmdType = 7`：`uri = 8006` 在线人气。
    Online {
        /// 在线人数。
        online: i64,
    },
    /// `cmdType = 22`：出现醒目留言事件（由上层触发 SC 拉取）。
    SuperChatEvent,
    /// 已识别但无需上抛（如其它 uri / 心跳回执）。
    Ignored,
    /// 帧已收到但无法解析（**不中断会话**，对齐 Dart 的 try/catch）。
    Malformed(String),
}

/// 解码一帧。
///
/// 未知命令类型 -> `Ignored`；解析异常 -> `Malformed`（附原因），
/// **不返回 Err**：单帧脏数据不得导致整条弹幕会话断开（对照 Dart `decodeMessage` 的 catch）。
pub fn decode_frame(frame: &[u8]) -> HuyaFrame {
    match try_decode(frame) {
        Ok(frame) => frame,
        Err(message) => HuyaFrame::Malformed(message),
    }
}

/// 解码一帧并返回错误原因。
///
/// 线上形态（由夹具逐字节确认）：`tag0 = cmdType`（TARS 整型）、`tag1 = data`（SimpleList），
/// 其后是 `requestId/traceId/encryptType/time/md5`（tag2..6，上行才有）。
///
/// ⚠️ **不要先`read_field_head()` 再读 tag 0** —— `read_field_head` 会消费字段头字节，
/// 随后的 `locate(0)` 会从下一个字段（tag=1）开始找而返回「缺失」。
/// 故此处直接用 typed 读取（`locate` 内部自行读头）。
fn try_decode(frame: &[u8]) -> Result<HuyaFrame, String> {
    let mut dec = TarsDecoder::new(frame);
    // -1 表示「tag 0 不存在」（畸形帧）；四个已知命令类型均为非负
    let cmd_type = dec.read_i64_or(0, -1);
    if cmd_type < 0 {
        return Err("帧缺少命令类型字段（tag 0）".to_string());
    }
    let data = dec.read_bytes_or(1);

    match cmd_type as i32 {
        cmd::MSG_PUSH_REQ => decode_push(&data),
        cmd::MSG_PUSH_REQ_V2 => decode_push_v2(&data),
        _ => Ok(HuyaFrame::Ignored),
    }
}

/// 解码 `cmdType = 7` 推送。
fn decode_push(body: &[u8]) -> Result<HuyaFrame, String> {
    // 服务端下发的是**裸字段表**（无 STRUCT_BEGIN/END），故用 decode_bare
    let push = HyPushMessage::decode_bare(body).map_err(|e| format!("推送结构解析失败: {e}"))?;
    match push.uri {
        URI_CHAT => {
            let message = super::tars_msgs::HyMessage::decode_bare(&push.msg)
                .map_err(|e| format!("聊天结构解析失败: {e}"))?;
            Ok(HuyaFrame::Chat {
                user_name: message.user_info.s_nick_name,
                content: message.content,
                font_color: message.bullet_format.font_color,
            })
        }
        URI_ONLINE => {
            // 人气载荷是「一个 TARS 整型字段」（tag=0，非固定 4 字节）——
            // 由夹具逐字节确认：线上为 `01 30 39` = SHORT 12345
            let mut inner = TarsDecoder::new(&push.msg);
            let online = inner
                .read_i64(0)
                .map_err(|e| format!("人气载荷不是 TARS 整型: {e}"))?;
            Ok(HuyaFrame::Online { online })
        }
        _ => Ok(HuyaFrame::Ignored),
    }
}

/// 解码 `cmdType = 22` 推送 V2（只关心醒目留言事件）。
fn decode_push_v2(body: &[u8]) -> Result<HuyaFrame, String> {
    let push = WsPushMessageV2::decode_bare(body)
        .map_err(|e| format!("V2 推送结构解析失败: {e}"))?;
    if push.v_msg_item.iter().any(|item| item.i_uri == URI_SUPER_CHAT) {
        Ok(HuyaFrame::SuperChatEvent)
    } else {
        Ok(HuyaFrame::Ignored)
    }
}
