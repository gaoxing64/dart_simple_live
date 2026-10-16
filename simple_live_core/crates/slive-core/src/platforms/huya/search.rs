//! F-04 搜索房间 / F-05 搜索主播（对照 `huya_site.dart:411-482`）。
//!
//! 两接口同源（`search.cdn.huya.com/?m=Search&do=getSearchContent`），仅差 `v`：
//! `v=4` 取房间（`response.3`），`v=1` 取主播（`response.1`）。
//!
//! 两个口径需注意（均对齐 Dart，不擅自"修正"）：
//! - 房间 `roomId` 形如 `yy/{yyid}`（带前缀，与分类列表的裸 `profileRoom` 不同）；
//! - `hasMore = numFound > page * 20`（严格大于）。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveAnchorItem, LiveRoomItem, LiveSearchAnchorResult, LiveSearchRoomResult};
use crate::util::{as_bool_lenient, as_i64};

use super::common::SEARCH_URL;
use super::site::HuyaSite;

/// 单页条数（固定 20，对齐 Dart `rows: 20`）。
const PAGE_SIZE: i64 = 20;

/// F-04 搜索房间。
pub(crate) async fn search_rooms(
    site: &HuyaSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchRoomResult, SliveError> {
    let value = site
        .get_json(SEARCH_URL, query(keyword, page, "4"))
        .await?;
    let items = crate::util::array_at(&value, "/response/3/docs")
        .iter()
        .map(room_item)
        .collect();
    Ok(LiveSearchRoomResult {
        has_more: num_found(&value, "/response/3", page),
        items,
    })
}

/// F-05 搜索主播。
pub(crate) async fn search_anchors(
    site: &HuyaSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchAnchorResult, SliveError> {
    let value = site
        .get_json(SEARCH_URL, query(keyword, page, "1"))
        .await?;
    let items = crate::util::array_at(&value, "/response/1/docs")
        .iter()
        .map(anchor_item)
        .collect();
    Ok(LiveSearchAnchorResult {
        has_more: num_found(&value, "/response/1", page),
        items,
    })
}

/// 构造搜索 query（`v` 区分房间/主播）。
fn query(keyword: &str, page: i32, v: &str) -> Vec<(String, String)> {
    let start = (page as i64 - 1) * PAGE_SIZE;
    vec![
        ("m".to_string(), "Search".to_string()),
        ("do".to_string(), "getSearchContent".to_string()),
        ("q".to_string(), keyword.to_string()),
        ("uid".to_string(), "0".to_string()),
        ("v".to_string(), v.to_string()),
        ("typ".to_string(), "-5".to_string()),
        ("livestate".to_string(), "0".to_string()),
        ("rows".to_string(), PAGE_SIZE.to_string()),
        ("start".to_string(), start.to_string()),
    ]
}

/// `hasMore = numFound > page * 20`（Dart 口径：严格大于）。
fn num_found(value: &Value, pointer: &str, page: i32) -> bool {
    let found = as_i64(value.pointer(&format!("{pointer}/numFound"))).unwrap_or(0);
    found > page as i64 * PAGE_SIZE
}

/// 房间项（`roomId` 带 `yy/` 前缀）。
fn room_item(item: &Value) -> LiveRoomItem {
    let cover = normalize_cover(&text(item, "game_screenshot"));
    let mut title = optional(item, "game_introduction").unwrap_or_default();
    if title.is_empty() {
        title = optional(item, "game_roomName").unwrap_or_default();
    }
    LiveRoomItem {
        room_id: format!("yy/{}", text(item, "yyid")),
        title,
        cover,
        user_name: text(item, "game_nick"),
        online: text(item, "game_total_count").trim().parse::<i32>().unwrap_or(0),
    }
}

/// 主播项（`live_status` 服务端可能给 int，Dart 裸赋 bool；此处宽松归一化，见 `util` 口径）。
fn anchor_item(item: &Value) -> LiveAnchorItem {
    LiveAnchorItem {
        room_id: text(item, "room_id"),
        avatar: text(item, "game_avatarUrl180"),
        user_name: text(item, "game_nick"),
        live_status: as_bool_lenient(item.get("gameLiveOn")).unwrap_or(false),
    }
}

/// 封面规整（与房间列表同口径）。
fn normalize_cover(raw: &str) -> String {
    if raw.contains('?') {
        raw.to_string()
    } else {
        format!("{raw}?x-oss-process=style/w338_h190&")
    }
}

fn text(item: &Value, key: &str) -> String {
    item.get(key)
        .map(crate::util::value_to_string)
        .unwrap_or_default()
}

fn optional(item: &Value, key: &str) -> Option<String> {
    item.get(key)
        .map(crate::util::value_to_string)
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn query_uses_page_offsets_and_version() {
        let q = query("lol", 3, "4");
        let get = |k: &str| {
            q.iter()
                .find(|(key, _)| key == k)
                .map(|(_, v)| v.clone())
                .expect("字段存在")
        };
        assert_eq!(get("v"), "4");
        assert_eq!(get("rows"), "20");
        assert_eq!(get("start"), "40", "第 3 页 -> (3-1)*20");
        assert_eq!(get("q"), "lol");
        assert_eq!(get("typ"), "-5");
    }

    #[test]
    fn first_page_start_is_zero() {
        assert_eq!(query("k", 1, "1")[8].1, "0");
    }

    #[test]
    fn has_more_is_strictly_greater() {
        let value = json!({"response": {"3": {"numFound": 60}}});
        assert!(num_found(&value, "/response/3", 2), "60 > 40");
        assert!(!num_found(&value, "/response/3", 3), "60 非 > 60");
    }

    #[test]
    fn room_id_carries_yy_prefix() {
        let item = json!({
            "yyid": 660000,
            "game_screenshot": "https://img/a.jpg",
            "game_introduction": "标题",
            "game_nick": "主播",
            "game_total_count": "100"
        });
        let parsed = room_item(&item);
        assert_eq!(parsed.room_id, "yy/660000");
        assert_eq!(parsed.title, "标题");
        assert_eq!(parsed.online, 100);
        assert!(parsed.cover.ends_with("w338_h190&"));
    }

    #[test]
    fn room_title_falls_back_to_room_name() {
        let item = json!({"yyid": 1, "game_introduction": "", "game_roomName": "备用"});
        assert_eq!(room_item(&item).title, "备用");
    }

    #[test]
    fn anchor_item_normalizes_live_status() {
        let item = json!({"room_id": "yy/1", "game_avatarUrl180": "a", "game_nick": "n", "gameLiveOn": 1});
        let parsed = anchor_item(&item);
        assert!(parsed.live_status, "int 1 -> true");
        let item = json!({"room_id": "yy/1", "gameLiveOn": 0});
        assert!(!anchor_item(&item).live_status);
    }

    #[test]
    fn missing_docs_yields_empty() {
        let value = json!({"response": {"3": {"numFound": 0}}});
        assert!(!num_found(&value, "/response/3", 1));
    }
}