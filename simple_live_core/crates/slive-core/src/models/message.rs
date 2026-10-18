//! 弹幕消息模型（对照 Dart `live_message.dart`）。
//!
//! 字段语义保留 Dart core（RISK-01/J-2）：保留 `color` / `emoticons` / `data`；
//! `data` 用**类型化枚举** [`LiveMessageData`]（保住 AC-12 人气 int32 与 AC-15 SC 结构体）。

use chrono::{DateTime, Local};

/// 消息类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LiveMessageType {
    /// 聊天弹幕。
    Chat,
    /// 礼物（暂不支持）。
    Gift,
    /// 在线人气。
    Online,
    /// 醒目留言。
    SuperChat,
}

/// 弹幕颜色（RGB）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LiveMessageColor {
    /// 红。
    pub r: i32,
    /// 绿。
    pub g: i32,
    /// 蓝。
    pub b: i32,
}

impl LiveMessageColor {
    /// 构造。
    pub const fn new(r: i32, g: i32, b: i32) -> Self {
        Self { r, g, b }
    }

    /// 白色。
    pub const fn white() -> Self {
        Self::new(255, 255, 255)
    }

    /// 十进制颜色整数 -> RGB（对齐 Dart `numberToColor`，0 -> 白）。
    pub fn number_to_color(int_color: i32) -> Self {
        let mut hex = format!("{:x}", int_color as i64);
        if hex.len() == 4 {
            hex = format!("00{hex}");
        }
        match hex.len() {
            6 => Self::from_hex(&hex[0..2], &hex[2..4], &hex[4..6]),
            8 => Self::from_hex(&hex[2..4], &hex[4..6], &hex[6..8]),
            _ => Self::white(),
        }
    }

    fn from_hex(r: &str, g: &str, b: &str) -> Self {
        Self::new(parse_hex(r), parse_hex(g), parse_hex(b))
    }
}

fn parse_hex(s: &str) -> i32 {
    i32::from_str_radix(s, 16).unwrap_or(255)
}

/// 弹幕表情包。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveMessageEmoticon {
    /// 占位符文本（`None` 表示渲染层追加到消息末尾）。
    pub name: Option<String>,
    /// 图片地址（已规范化为 https）。
    pub url: String,
    /// 宽（服务端原始值）。
    pub width: Option<i32>,
    /// 高（服务端原始值）。
    pub height: Option<i32>,
    /// 是否为大表情（B站 `info[0][13]` / 抖音独立表情 / 虎牙 `type=2/3` 梗表情）。
    pub large: bool,
    /// B站 `emoticon_unique`。
    pub emoticon_unique: Option<String>,
}

/// 醒目留言。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveSuperChatMessage {
    /// 用户名。
    pub user_name: String,
    /// 头像。
    pub face: String,
    /// 内容。
    pub message: String,
    /// 价格。
    pub price: i32,
    /// 开始时间。
    pub start_time: DateTime<Local>,
    /// 结束时间。
    pub end_time: DateTime<Local>,
    /// 背景色。
    pub background_color: String,
    /// 背景底部色。
    pub background_bottom_color: String,
}

/// 消息附带数据（类型化枚举，替代 Dart `dynamic`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveMessageData {
    /// 人气值（op=3）。
    Online(i32),
    /// 醒目留言。
    SuperChat(LiveSuperChatMessage),
}

/// 弹幕消息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveMessage {
    /// 消息类型。
    pub message_type: LiveMessageType,
    /// 用户名。
    pub user_name: String,
    /// 用户 ID。
    pub user_id: Option<String>,
    /// 消息内容。
    pub message: String,
    /// 附带数据（人气 / SC）。
    pub data: Option<LiveMessageData>,
    /// 弹幕颜色。
    pub color: LiveMessageColor,
    /// 表情包。
    pub emoticons: Option<Vec<LiveMessageEmoticon>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn number_to_color_matches_dart() {
        assert_eq!(LiveMessageColor::number_to_color(16777215), LiveMessageColor::white());
        assert_eq!(LiveMessageColor::number_to_color(0xFF0000), LiveMessageColor::new(255, 0, 0));
        // 4 位形态补 00 前缀
        assert_eq!(LiveMessageColor::number_to_color(0x1234), LiveMessageColor::new(0x00, 0x12, 0x34));
    }
}
