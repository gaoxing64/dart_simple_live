//! 列表接口结果（对照 Dart `live_category_result.dart` / `live_search_result.dart`）。

use crate::models::{LiveAnchorItem, LiveRoomItem};

/// 分类下房间 / 推荐结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveCategoryResult {
    /// 是否还有下一页。
    pub has_more: bool,
    /// 房间列表。
    pub items: Vec<LiveRoomItem>,
}

/// 房间搜索结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveSearchRoomResult {
    /// 是否还有下一页（`items.len() >= 40`）。
    pub has_more: bool,
    /// 房间列表。
    pub items: Vec<LiveRoomItem>,
}

/// 主播搜索结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveSearchAnchorResult {
    /// 是否还有下一页（`items.len() >= 40`）。
    pub has_more: bool,
    /// 主播列表。
    pub items: Vec<LiveAnchorItem>,
}
