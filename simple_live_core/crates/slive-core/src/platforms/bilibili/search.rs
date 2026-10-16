//! F-04 搜索房间 / F-05 搜索主播（对照 `bilibili_site.dart:273-337`）。

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::models::{LiveAnchorItem, LiveRoomItem, LiveSearchAnchorResult, LiveSearchRoomResult};
use crate::util::{as_bool_lenient, as_i32};

use super::site::BilibiliSite;
use super::util::{strip_em_tags, text};

const SEARCH_URL: &str = "https://api.bilibili.com/x/web-interface/search/type";
/// 满页判据（Dart `items.length >= 40`）。
const FULL_PAGE: usize = 40;

fn base_query(keyword: &str, page: i32, search_type: &str) -> Vec<(String, String)> {
    vec![
        ("context".to_string(), String::new()),
        ("search_type".to_string(), search_type.to_string()),
        ("cover_type".to_string(), "user_cover".to_string()),
        ("order".to_string(), String::new()),
        ("keyword".to_string(), keyword.to_string()),
        ("category_id".to_string(), String::new()),
        ("__refresh__".to_string(), String::new()),
        ("_extra".to_string(), String::new()),
        ("highlight".to_string(), "0".to_string()),
        ("single_column".to_string(), "0".to_string()),
        ("page".to_string(), page.to_string()),
    ]
}

/// F-04 搜索房间。
pub(crate) async fn search_rooms(
    site: &BilibiliSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchRoomResult, SliveError> {
    let value = site
        .get_json(SEARCH_URL, base_query(keyword, page, "live"))
        .await?;
    check_api_code(&value)?;

    let items: Vec<LiveRoomItem> = crate::util::array_at(&value, "/data/result/live_room")
        .iter()
        .map(|item| LiveRoomItem {
            room_id: text(item, "roomid"),
            title: strip_em_tags(&text(item, "title")),
            // Dart: `"https:${cover}@400w.jpg"`（相对协议 // 补 https）。
            cover: format!("https:{}@400w.jpg", text(item, "cover")),
            user_name: text(item, "uname"),
            online: as_i32(item.get("online")).unwrap_or(0),
        })
        .collect();

    let has_more = items.len() >= FULL_PAGE;
    Ok(LiveSearchRoomResult { has_more, items })
}

/// F-05 搜索主播（DTV/上游均缺，须从 Dart core 重实现）。
pub(crate) async fn search_anchors(
    site: &BilibiliSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchAnchorResult, SliveError> {
    let value = site
        .get_json(SEARCH_URL, base_query(keyword, page, "live_user"))
        .await?;
    check_api_code(&value)?;

    let items: Vec<LiveAnchorItem> = crate::util::array_at(&value, "/data/result")
        .iter()
        .map(|item| LiveAnchorItem {
            room_id: text(item, "roomid"),
            avatar: format!("https:{}@400w.jpg", text(item, "uface")),
            user_name: strip_em_tags(&text(item, "uname")),
            // G-4：`is_live` 显式接受 int/bool 并归一化（不照抄 Dart 裸赋 bool 的缺陷）。
            live_status: as_bool_lenient(item.get("is_live")).unwrap_or(false),
        })
        .collect();

    let has_more = items.len() >= FULL_PAGE;
    Ok(LiveSearchAnchorResult { has_more, items })
}
