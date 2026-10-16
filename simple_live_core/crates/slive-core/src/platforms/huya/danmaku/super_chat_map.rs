//! 醒目留言信号的识别与消息映射（对照 Dart `huya_danmaku.dart:225-291`）。
//!
//! 从 [`super`]（会话编排）拆出：本模块只做「帧里的 SC 信号 -> 消息」的纯映射，
//! 不涉及连接 / 心跳 / 重连。
//!
//! 两条触发路径（对齐 Dart）：
//! 1. V2 推送 `iUri == 2001317`（由 [`super::frames`] 识别为 `SuperChatEvent`；
//!    2026-10-17 上游同步更正，旧值 2001314）；
//! 2. ~~聊天文案命中 `(来自 xx 上头条)`~~ —— **上游已弃用**（dev 97413c60）：
//!    文本路径会误触发/漏触发，判定只信 V2 真实 uri。本模块相关函数保留以备回退。
//!
//! 两条路径都**只置触发位、不直接产消息**；SC 内容由会话循环经
//! `SuperChatFetcher` 拉取后另行产出（QA 夹具 `expected.messages` 亦为空）。

use crate::models::{LiveDanmuItem, LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageType};

use super::SuperChatFetcher;

/// 文案是否命中醒目留言特征（对齐 Dart 旧正则 `\(来自.+?上头条\)`）。
///
/// **上游 dev 97413c60 起弃用**（不再参与 SC 判定，只信 V2 uri=2001317）；
/// 保留函数与其测试以备回退。
#[allow(dead_code)]
///
/// `pub`：会话编排与集成测试共用同一判据。
pub fn mentions_super_chat(content: &str) -> bool {
    contains_super_chat_marker(content)
}


/// 扫描 `(来自…上头条)` 标记（对齐 Dart 正则 `\(来自.+?上头条\)`）。
///
/// `.+?` 要求 `来自` 与 `上头条` 之间**至少一个字符** —— `(来自上头条)` 不命中。
pub fn contains_super_chat_marker(content: &str) -> bool {
    const START: &str = "(来自";
    const END: &str = "上头条)";
    let mut cursor = 0;
    while let Some(offset) = content[cursor..].find(START) {
        let body_start = cursor + offset + START.len();
        if let Some(end_offset) = content[body_start..].find(END) {
            // 两标记之间的距离即 `.+?` 的匹配长度，必须 >= 1
            if end_offset >= 1 {
                return true;
            }
        }
        cursor = body_start;
    }
    false
}

/// 拉取醒目留言并映射为消息（无钩子或空列表 -> 空序列）。
///
/// `pub`：会话循环与集成测试（夹具回归）都要复用同一路径。
pub fn super_chat_items(
    top_sid: i64,
    fetch_super_chat: Option<&SuperChatFetcher>,
) -> Vec<LiveDanmuItem> {
    let Some(fetch) = fetch_super_chat else {
        return Vec::new();
    };
    if top_sid == 0 {
        return Vec::new();
    }
    let list = fetch(top_sid);
    match list.into_iter().next() {
        // 对齐 Dart：增量 SC 只取最新一条
        Some(sc) => vec![LiveDanmuItem::Message(Box::new(LiveMessage {
            message_type: LiveMessageType::SuperChat,
            user_name: "SUPER_CHAT_MESSAGE".to_string(),
            user_id: None,
            message: "SUPER_CHAT_MESSAGE".to_string(),
            data: Some(LiveMessageData::SuperChat(sc)),
            color: LiveMessageColor::white(),
            emoticons: None,
        }))],
        None => Vec::new(),
    }
}
