//! 弹幕消息模型镜像（保留 Dart core 语义：`color`/`emoticons`/`data`）。

pub use slive_core::models::{
    LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageEmoticon, LiveMessageType,
    LiveSuperChatMessage,
};

#[flutter_rust_bridge::frb(mirror(LiveMessageType))]
pub enum _LiveMessageType {
    Chat,
    Gift,
    Online,
    SuperChat,
}

#[flutter_rust_bridge::frb(mirror(LiveMessageColor))]
pub struct _LiveMessageColor {
    pub r: i32,
    pub g: i32,
    pub b: i32,
}

#[flutter_rust_bridge::frb(mirror(LiveMessageEmoticon))]
pub struct _LiveMessageEmoticon {
    pub name: Option<String>,
    pub url: String,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub large: bool,
    pub emoticon_unique: Option<String>,
}

#[flutter_rust_bridge::frb(mirror(LiveSuperChatMessage))]
pub struct _LiveSuperChatMessage {
    pub user_name: String,
    pub face: String,
    pub message: String,
    pub price: i32,
    pub start_time: chrono::DateTime<chrono::Local>,
    pub end_time: chrono::DateTime<chrono::Local>,
    pub background_color: String,
    pub background_bottom_color: String,
}

#[flutter_rust_bridge::frb(mirror(LiveMessageData))]
pub enum _LiveMessageData {
    Online(i32),
    SuperChat(LiveSuperChatMessage),
}

#[flutter_rust_bridge::frb(mirror(LiveMessage))]
pub struct _LiveMessage {
    pub message_type: LiveMessageType,
    pub user_name: String,
    pub user_id: Option<String>,
    pub message: String,
    pub data: Option<LiveMessageData>,
    pub color: LiveMessageColor,
    pub emoticons: Option<Vec<LiveMessageEmoticon>>,
}
