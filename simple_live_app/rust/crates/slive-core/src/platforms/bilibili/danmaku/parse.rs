//! 弹幕 JSON 消息解析（对照 `bilibili_danmaku.dart:186-239`）。
//!
//! 只处理 `DANMU_MSG`（聊天，F-14）与 `SUPER_CHAT_MESSAGE`（F-15）；
//! 其他 cmd 与异常载荷一律静默跳过（对齐 Dart 的 catch-and-log）。
//! 表情包解析（F-16）接入点在 `parse_danmu_msg` 的 `emoticons` 字段，由 `emoticon` 模块填充。

use crate::models::{
    LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageType, LiveSuperChatMessage,
};

/// 解析单条 JSON 串；非目标 cmd / 异常载荷 → `None`。
pub fn parse_message(json_str: &str) -> Option<LiveMessage> {
    let obj: serde_json::Value = serde_json::from_str(json_str).ok()?;
    let cmd = obj.get("cmd")?.as_str()?.to_string();
    if cmd.contains("DANMU_MSG") {
        parse_danmu_msg(&obj)
    } else if cmd == "SUPER_CHAT_MESSAGE" {
        parse_super_chat(&obj)
    } else {
        None
    }
}

/// F-14：`DANMU_MSG` → 聊天消息。
///
/// 字段路径（对齐 Dart）：
/// - `info[1]` 消息文本
/// - `info[0][3]` 颜色整数（0 → 白）
/// - `info[2]` 非空时 `info[2][1]` 为用户名
fn parse_danmu_msg(obj: &serde_json::Value) -> Option<LiveMessage> {
    let info = obj.get("info")?.as_array()?;
    if info.is_empty() {
        return None;
    }
    let message = json_to_plain_string(info.get(1)?);
    let color_int = info
        .first()
        .and_then(|head| head.get(3))
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let user_name = info
        .get(2)
        .and_then(|u| u.as_array())
        .filter(|u| !u.is_empty())
        .and_then(|u| u.get(1))
        .map(json_to_plain_string)
        .unwrap_or_default();
    // F-16：表情包解析（两入口 + 去重 + 上限 8）；无表情 → None
    let emoticons = crate::platforms::bilibili::emoticon::parse_bilibili_emoticons(info, &message);
    Some(LiveMessage {
        message_type: LiveMessageType::Chat,
        user_name,
        user_id: None,
        message,
        data: None,
        color: if color_int == 0 {
            LiveMessageColor::white()
        } else {
            LiveMessageColor::number_to_color(color_int)
        },
        emoticons,
    })
}

/// F-15：`SUPER_CHAT_MESSAGE` → 醒目留言。
///
/// `data = null` 时直接返回（AC-15）；时间字段为**秒**，转毫秒时间戳。
fn parse_super_chat(obj: &serde_json::Value) -> Option<LiveMessage> {
    let data = obj.get("data")?;
    if data.is_null() {
        return None;
    }
    let start_ms = data.get("start_time")?.as_i64()? * 1000;
    let end_ms = data.get("end_time")?.as_i64()? * 1000;
    let start_time = chrono::DateTime::from_timestamp_millis(start_ms)?.with_timezone(&chrono::Local);
    let end_time = chrono::DateTime::from_timestamp_millis(end_ms)?.with_timezone(&chrono::Local);
    let sc = LiveSuperChatMessage {
        user_name: data
            .pointer("/user_info/uname")
            .map(json_to_plain_string)
            .unwrap_or_default(),
        face: format!(
            "{}@200w.jpg",
            data.pointer("/user_info/face")
                .map(json_to_plain_string)
                .unwrap_or_default()
        ),
        message: data.get("message").map(json_to_plain_string).unwrap_or_default(),
        price: data.get("price").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
        start_time,
        end_time,
        background_color: data
            .get("background_color")
            .map(json_to_plain_string)
            .unwrap_or_default(),
        background_bottom_color: data
            .get("background_bottom_color")
            .map(json_to_plain_string)
            .unwrap_or_default(),
    };
    Some(LiveMessage {
        message_type: LiveMessageType::SuperChat,
        // 对齐 Dart：外层 userName/message 为固定字面量，真实内容在 data 里
        user_name: "SUPER_CHAT_MESSAGE".to_string(),
        user_id: None,
        message: "SUPER_CHAT_MESSAGE".to_string(),
        color: LiveMessageColor::white(),
        data: Some(LiveMessageData::SuperChat(sc)),
        emoticons: None,
    })
}

/// JSON 值 → 平文本（对齐 Dart `.toString()`：字符串原样，其余 JSON 序列化）。
fn json_to_plain_string(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ac14_danmu_msg_parses_chat_fields() {
        let msg = parse_message(
            r#"{"cmd":"DANMU_MSG","info":[[0,0,0,16777215],"hello world",[0,"tester"],0]}"#,
        )
        .expect("应解析成功");
        assert_eq!(msg.message_type, LiveMessageType::Chat);
        assert_eq!(msg.user_name, "tester");
        assert_eq!(msg.message, "hello world");
        assert_eq!(msg.color, LiveMessageColor::white(), "16777215 → 白");
    }

    #[test]
    fn ac14_colored_danmu_maps_number_to_color() {
        let msg = parse_message(
            r#"{"cmd":"DANMU_MSG","info":[[0,0,0,16711680],"红",[0,"u"],0]}"#,
        )
        .expect("应解析成功");
        assert_eq!(msg.color, LiveMessageColor::new(255, 0, 0), "0xFF0000 → 红");
    }

    #[test]
    fn ac14_danmu_msg_without_sender_keeps_empty_name() {
        // info[2] 为空数组 → user_name 为空（不 panic）
        let msg = parse_message(r#"{"cmd":"DANMU_MSG","info":[[0,0,0,0],"m",[],0]}"#)
            .expect("info[2] 为空不应阻断解析");
        assert_eq!(msg.user_name, "");
        assert_eq!(msg.color, LiveMessageColor::white(), "0 → 白");
    }

    #[test]
    fn ac15_super_chat_parses_structured_data() {
        let msg = parse_message(
            r##"{"cmd":"SUPER_CHAT_MESSAGE","data":{
                "price":30,"message":"冲！","start_time":1700000000,"end_time":1700003600,
                "background_color":"#EDF5FF","background_bottom_color":"#2A4777",
                "user_info":{"uname":"老板","face":"http://i0.hdslb.com/bfs/face/x.jpg"}}}"##,
        )
        .expect("应解析成功");
        assert_eq!(msg.message_type, LiveMessageType::SuperChat);
        assert_eq!(msg.user_name, "SUPER_CHAT_MESSAGE");
        let LiveMessageData::SuperChat(sc) = msg.data.expect("应携带 SC 数据") else {
            panic!("data 应为 SuperChat 变体");
        };
        assert_eq!(sc.user_name, "老板");
        assert_eq!(sc.message, "冲！");
        assert_eq!(sc.price, 30);
        assert_eq!(sc.face, "http://i0.hdslb.com/bfs/face/x.jpg@200w.jpg");
        assert_eq!(sc.background_bottom_color, "#2A4777");
    }

    #[test]
    fn ac15_super_chat_null_data_returns_none() {
        assert!(parse_message(r#"{"cmd":"SUPER_CHAT_MESSAGE","data":null}"#).is_none());
    }

    #[test]
    fn non_target_cmd_and_garbage_return_none() {
        assert!(parse_message(r#"{"cmd":"ONLINE_RANK_COUNT","data":{}}"#).is_none());
        assert!(parse_message("not json").is_none());
        assert!(parse_message(r#"{"cmd":123}"#).is_none());
    }
}
