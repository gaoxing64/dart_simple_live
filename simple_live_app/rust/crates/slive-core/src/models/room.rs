//! 房间列表项 / 主播项 / 房间详情（对照 Dart `live_room_item.dart` / `live_anchor_item.dart` / `live_room_detail.dart`）。

/// 直播房间列表项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveRoomItem {
    /// 房间 ID。
    pub room_id: String,
    /// 标题。
    pub title: String,
    /// 封面。
    pub cover: String,
    /// 主播名。
    pub user_name: String,
    /// 人气 / 在线人数。
    pub online: i32,
}

/// 主播搜索项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveAnchorItem {
    /// 房间 ID。
    pub room_id: String,
    /// 头像。
    pub avatar: String,
    /// 主播名。
    pub user_name: String,
    /// 是否在播。
    pub live_status: bool,
}

/// 房间详情。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveRoomDetail {
    /// 真实房间 ID。
    pub room_id: String,
    /// 标题。
    pub title: String,
    /// 封面。
    pub cover: String,
    /// 主播名。
    pub user_name: String,
    /// 主播头像。
    pub user_avatar: String,
    /// 人气 / 在线人数。
    pub online: i32,
    /// 简介。
    pub introduction: Option<String>,
    /// 公告。
    pub notice: Option<String>,
    /// 是否在播。
    pub status: bool,
    /// 附加数据通道（JSON String，B站本轮为 `None`；见 §3.3(a)）。
    pub data: Option<String>,
    /// 弹幕参数通道（JSON String，承载 `BiliBiliDanmakuArgs`；见 §3.3(b)）。
    pub danmaku_data: Option<String>,
    /// 是否录播。
    pub is_record: bool,
    /// 房间链接。
    pub url: String,
}
