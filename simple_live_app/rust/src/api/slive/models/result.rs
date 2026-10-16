//! 列表结果模型镜像。

pub use slive_core::models::{
    LiveCategoryResult, LiveSearchAnchorResult, LiveSearchRoomResult,
};

#[flutter_rust_bridge::frb(mirror(LiveCategoryResult))]
pub struct _LiveCategoryResult {
    pub has_more: bool,
    pub items: Vec<slive_core::models::LiveRoomItem>,
}

#[flutter_rust_bridge::frb(mirror(LiveSearchRoomResult))]
pub struct _LiveSearchRoomResult {
    pub has_more: bool,
    pub items: Vec<slive_core::models::LiveRoomItem>,
}

#[flutter_rust_bridge::frb(mirror(LiveSearchAnchorResult))]
pub struct _LiveSearchAnchorResult {
    pub has_more: bool,
    pub items: Vec<slive_core::models::LiveAnchorItem>,
}
