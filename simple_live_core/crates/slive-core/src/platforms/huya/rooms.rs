//! F-02 分类下房间 / F-03 推荐房间（对照 `huya_site.dart:98-130` / `:193-223`）。
//!
//! 两个接口同源（`www.huya.com/cache.php?m=LiveList&do=getLiveListByPage`），
//! 仅 query 差一个 `gameId`。单页条数由服务端决定，`page_size` **仅满足统一签名、接口忽略**
//! （对齐 Dart 注释「单页条数由服务端决定，忽略 pageSize」）。
//!
//! 封面规整：不含 `?` 时追加 `?x-oss-process=style/w338_h190&`（对齐 Dart）。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveCategoryResult, LiveRoomItem, LiveSubCategory};
use crate::util::as_i64;

use super::common::ROOM_LIST_URL;
use super::site::HuyaSite;

/// 封面样式参数（Dart 字面量，注意末尾的 `&`）。
const COVER_STYLE_SUFFIX: &str = "?x-oss-process=style/w338_h190&";

/// F-02 分类下房间。
pub(crate) async fn fetch_category_rooms(
    site: &HuyaSite,
    category: &LiveSubCategory,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let query = vec![
        ("m".to_string(), "LiveList".to_string()),
        ("do".to_string(), "getLiveListByPage".to_string()),
        ("tagAll".to_string(), "0".to_string()),
        ("gameId".to_string(), category.id.clone()),
        ("page".to_string(), page.to_string()),
    ];
    Ok(parse_room_list(&site.get_json(ROOM_LIST_URL, query).await?))
}

/// F-03 推荐房间（不带 `gameId`）。
pub(crate) async fn fetch_recommend_rooms(
    site: &HuyaSite,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let query = vec![
        ("m".to_string(), "LiveList".to_string()),
        ("do".to_string(), "getLiveListByPage".to_string()),
        ("tagAll".to_string(), "0".to_string()),
        ("page".to_string(), page.to_string()),
    ];
    Ok(parse_room_list(&site.get_json(ROOM_LIST_URL, query).await?))
}

/// 解析 `data.datas` + `hasMore = page < totalPage`。
fn parse_room_list(value: &Value) -> LiveCategoryResult {
    let items = crate::util::array_at(value, "/data/datas")
        .iter()
        .map(room_item)
        .collect();
    let page = as_i64(value.pointer("/data/page")).unwrap_or(0);
    let total_page = as_i64(value.pointer("/data/totalPage")).unwrap_or(0);
    LiveCategoryResult {
        has_more: page < total_page,
        items,
    }
}

/// 单个房间项（字段口径逐一对齐 Dart）。
fn room_item(item: &Value) -> LiveRoomItem {
    let cover = normalize_cover(&text(item, "screenshot"));
    // Dart：introduction 优先，空则回落 roomName（两者皆空 -> ""）。
    let mut title = optional_text(item, "introduction").unwrap_or_default();
    if title.is_empty() {
        title = optional_text(item, "roomName").unwrap_or_default();
    }
    LiveRoomItem {
        room_id: text(item, "profileRoom"),
        title,
        cover,
        user_name: text(item, "nick"),
        online: text(item, "totalCount").trim().parse::<i32>().unwrap_or(0),
    }
}

/// 封面规整（Dart：不含 `?` 则追加样式参数）。
fn normalize_cover(raw: &str) -> String {
    if raw.contains('?') {
        raw.to_string()
    } else {
        format!("{raw}{COVER_STYLE_SUFFIX}")
    }
}

/// 取直接键文本（缺失/null -> 空串）。
fn text(item: &Value, key: &str) -> String {
    item.get(key)
        .map(crate::util::value_to_string)
        .unwrap_or_default()
}

/// 取可选文本（键缺失时 `None`）。
fn optional_text(item: &Value, key: &str) -> Option<String> {
    item.get(key)
        .map(crate::util::value_to_string)
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample() -> Value {
        json!({
            "data": {
                "page": 1,
                "totalPage": 3,
                "datas": [
                    {
                        "profileRoom": 660000,
                        "introduction": "精彩不断",
                        "roomName": "备用标题",
                        "screenshot": "https://img.example/a.jpg",
                        "nick": "主播A",
                        "totalCount": "12345"
                    },
                    {
                        "profileRoom": 660001,
                        "introduction": "",
                        "roomName": "备用标题B",
                        "screenshot": "https://img.example/b.jpg?x=1",
                        "nick": "主播B",
                        "totalCount": 42
                    }
                ]
            }
        })
    }

    #[test]
    fn parses_items_and_has_more() {
        let result = parse_room_list(&sample());
        assert_eq!(result.items.len(), 2);
        assert!(result.has_more, "page 1 < totalPage 3");
    }

    #[test]
    fn last_page_reports_no_more() {
        let value = json!({"data": {"page": 3, "totalPage": 3, "datas": []}});
        assert!(!parse_room_list(&value).has_more);
    }

    #[test]
    fn cover_style_appended_only_without_question_mark() {
        assert_eq!(
            normalize_cover("https://img/a.jpg"),
            "https://img/a.jpg?x-oss-process=style/w338_h190&"
        );
        assert_eq!(
            normalize_cover("https://img/a.jpg?x=1"),
            "https://img/a.jpg?x=1",
            "已带参数不再追加"
        );
    }

    #[test]
    fn title_falls_back_to_room_name() {
        let items = parse_room_list(&sample()).items;
        assert_eq!(items[0].title, "精彩不断", "introduction 优先");
        assert_eq!(items[1].title, "备用标题B", "空 introduction 回落 roomName");
    }

    #[test]
    fn online_accepts_string_and_number() {
        let items = parse_room_list(&sample()).items;
        assert_eq!(items[0].online, 12345, "字符串数字");
        assert_eq!(items[1].online, 42, "数字");
    }

    #[test]
    fn online_invalid_falls_back_to_zero() {
        let value = json!({"data": {"page": 1, "totalPage": 1, "datas": [
            {"profileRoom": 1, "nick": "n", "totalCount": "N/A"}
        ]}});
        assert_eq!(parse_room_list(&value).items[0].online, 0);
    }

    #[test]
    fn missing_datas_yields_empty_result() {
        let value = json!({});
        let result = parse_room_list(&value);
        assert!(result.items.is_empty());
        assert!(!result.has_more);
    }
}