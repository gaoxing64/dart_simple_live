//! 房间 / 主播 / 详情模型镜像。

pub use slive_core::models::{LiveAnchorItem, LiveRoomDetail, LiveRoomItem};

#[flutter_rust_bridge::frb(mirror(LiveRoomItem))]
pub struct _LiveRoomItem {
    pub room_id: String,
    pub title: String,
    pub cover: String,
    pub user_name: String,
    pub online: i32,
}

#[flutter_rust_bridge::frb(mirror(LiveAnchorItem))]
pub struct _LiveAnchorItem {
    pub room_id: String,
    pub avatar: String,
    pub user_name: String,
    pub live_status: bool,
}

#[flutter_rust_bridge::frb(mirror(LiveRoomDetail))]
pub struct _LiveRoomDetail {
    pub room_id: String,
    pub title: String,
    pub cover: String,
    pub user_name: String,
    pub user_avatar: String,
    pub online: i32,
    pub introduction: Option<String>,
    pub notice: Option<String>,
    pub status: bool,
    pub data: Option<String>,
    pub danmaku_data: Option<String>,
    pub is_record: bool,
    pub url: String,
}
