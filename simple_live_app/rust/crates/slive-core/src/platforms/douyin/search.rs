//! 搜索直播间（对照 Dart `searchRooms`，`douyin_site.dart:1089-1169`）。
//!
//! 接口是 `www.douyin.com/aweme/v1/web/live/search/`（**不带** a_bogus 签名 ——
//! Dart 直接 `getJson`，未过 `buildRequestUrl`，此处照抄）。
//!
//! # 响应的双层嵌套
//! `result["data"][]` 每项的 `lives.rawdata` 是**又一层 JSON 串**，真正的字段在里面：
//! `owner.web_rid` / `title` / `cover.url_list[0]` / `owner.nickname` / `stats.total_user`。
//!
//! # 被限流
//! Dart 判 `result == "" || result == 'blocked'` —— 但 `getJson` 已把响应体解析成对象，
//! 这两个比较**恒为 false**，是死代码；真正的限流表现为 `data` 缺失或 `rawdata` 解析失败。
//! 这里按 Dart 的实际有效行为处理：`rawdata` 解不出字段就**跳过该条**，
//! 整页为空时返回空结果（不报错），与 Dart 一致。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveRoomItem, LiveSearchRoomResult};

use super::site::DouyinSite;
use super::util::{as_object, first_url};

/// 搜索接口 URL。
pub const SEARCH_URL: &str = "https://www.douyin.com/aweme/v1/web/live/search/";
/// 单页条数（Dart 固定 10，`has_more` 也按它判定）。
pub const PAGE_SIZE: i32 = 10;
/// Dart 硬编码的 `webid`（搜索接口不校验，但缺失会被拒）。
pub const WEB_ID: &str = "7382872326016435738";

/// 搜索直播间。
pub(crate) async fn search_rooms(
    site: &DouyinSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchRoomResult, SliveError> {
    super::header::ensure_ttwid(site).await?;
    let url = format!("{SEARCH_URL}?{}", search_params(keyword, page).to_query());
    let value = site
        .get_json(&url, Vec::new(), super::header::search_headers(site, keyword))
        .await?;

    let raw_list = value
        .get("data")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let items: Vec<LiveRoomItem> = raw_list.iter().filter_map(parse_item).collect();

    Ok(LiveSearchRoomResult {
        has_more: items.len() >= PAGE_SIZE as usize,
        items,
    })
}

/// 搜索参数（顺序对齐 Dart `Uri.replace(queryParameters: {...})`）。
///
/// 抽成独立函数是为了**参数级防回归**（见 `rooms::feed_slice_params` 的同款注释）：
/// 合成夹具校验不到请求参数。`search_params_carry_aid_and_webid` 钉住关键键。
pub fn search_params(keyword: &str, page: i32) -> super::util::QueryParams {
    let mut q = super::util::QueryParams::new();
    q.put("device_platform", "webapp")
        .put("aid", "6383")
        .put("channel", "channel_pc_web")
        .put("search_channel", "aweme_live")
        .put("keyword", keyword)
        .put("search_source", "switch_tab")
        .put("query_correct_type", "1")
        .put("is_filter_search", "0")
        .put("from_group_id", "")
        .put("offset", ((page - 1) * PAGE_SIZE).to_string())
        .put("count", PAGE_SIZE.to_string())
        .put("pc_client_type", "1")
        .put("version_code", "170400")
        .put("version_name", "17.4.0")
        .put("cookie_enabled", "true")
        .put("screen_width", "1980")
        .put("screen_height", "1080")
        .put("browser_language", "zh-CN")
        .put("browser_platform", "Win32")
        .put("browser_name", "Edge")
        .put("browser_version", "125.0.0.0")
        .put("browser_online", "true")
        .put("engine_name", "Blink")
        .put("engine_version", "125.0.0.0")
        .put("os_name", "Windows")
        .put("os_version", "10")
        .put("cpu_core_num", "12")
        .put("device_memory", "8")
        .put("platform", "PC")
        .put("downlink", "10")
        .put("effective_type", "4g")
        .put("round_trip_time", "100")
        .put("webid", WEB_ID);
    q
}

/// 一条搜索结果 -> `LiveRoomItem`；`rawdata` 缺失/畸形 -> `None`（跳过，不拖垮整页）。
fn parse_item(item: &Value) -> Option<LiveRoomItem> {
    let rawdata = item.pointer("/lives/rawdata")?;
    // rawdata 是 JSON 串（也可能是对象，兼容两种形态）
    let parsed: Value = match rawdata {
        Value::String(s) => super::util::safe_json_decode(s)?,
        Value::Object(_) => rawdata.clone(),
        _ => return None,
    };
    let owner = as_object(parsed.get("owner"))?;
    let web_rid = owner.get("web_rid")?;
    Some(LiveRoomItem {
        room_id: crate::util::value_to_string(web_rid),
        title: parsed
            .get("title")
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        cover: first_url(parsed.get("cover")),
        user_name: owner
            .get("nickname")
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        online: parsed
            .pointer("/stats/total_user")
            .map(crate::util::value_to_string)
            .and_then(|s| s.parse::<i32>().ok())
            .unwrap_or(0),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn item_with_rawdata(raw: &Value) -> Value {
        json!({"lives": {"rawdata": raw.to_string()}})
    }

    #[test]
    fn search_params_carry_aid_and_webid() {
        let q = search_params("主播", 3);
        let map: std::collections::HashMap<_, _> = q.iter().collect();
        assert_eq!(map["keyword"], "主播");
        assert_eq!(map["offset"], "20", "第 3 页 -> offset (3-1)*10");
        assert_eq!(map["count"], "10");
        assert_eq!(
            map["aid"], "6383",
            "aid 缺失会被服务端拒（真机 400，2026-10-16 复现）"
        );
        assert_eq!(map["webid"], WEB_ID, "webid 缺失会被服务端拒");
        assert_eq!(map["search_channel"], "aweme_live");
        // Dart 的 33 个键，一个不多一个不少
        assert_eq!(q.iter().count(), 33, "搜索参数表必须与 Dart 完全一致");
        // 搜索接口不走 buildRequestUrl
        for absent in ["compress", "msToken", "a_bogus", "app_name", "live_id"] {
            assert!(
                !map.contains_key(absent),
                "搜索不该带 {absent}（Dart 未过 buildRequestUrl）"
            );
        }
    }

    #[test]
    fn search_params_order_matches_dart_literal_order() {
        let params = search_params("k", 1);
        let keys: Vec<&str> = params.iter().map(|(k, _)| k).collect();
        assert_eq!(keys[0], "device_platform");
        assert_eq!(keys[1], "aid");
        assert_eq!(keys[2], "channel");
        assert_eq!(keys[4], "keyword");
    }

    #[test]
    fn parses_nested_rawdata_string() {
        let raw = json!({
            "owner": {"web_rid": "416144012050", "nickname": "主播"},
            "title": "直播间标题",
            "cover": {"url_list": ["https://c1", "https://c2"]},
            "stats": {"total_user": "8888"},
        });
        let got = parse_item(&item_with_rawdata(&raw)).expect("应能解析");
        assert_eq!(got.room_id, "416144012050");
        assert_eq!(got.title, "直播间标题");
        assert_eq!(got.cover, "https://c1", "取 url_list[0]");
        assert_eq!(got.user_name, "主播");
        assert_eq!(got.online, 8888);
    }

    #[test]
    fn accepts_rawdata_object_form() {
        let raw = json!({"owner": {"web_rid": "1", "nickname": "n"}, "title": "t"});
        let got = parse_item(&json!({"lives": {"rawdata": raw}})).expect("对象形态也应解析");
        assert_eq!(got.room_id, "1");
    }

    #[test]
    fn dirty_entries_are_skipped() {
        assert!(parse_item(&json!({})).is_none(), "缺 lives 应跳过");
        assert!(parse_item(&json!({"lives": {}})).is_none(), "缺 rawdata 应跳过");
        assert!(parse_item(&item_with_rawdata(&json!("not json"))).is_none());
        assert!(parse_item(&item_with_rawdata(&json!({}))).is_none(), "rawdata 无 owner 应跳过");
        assert!(parse_item(&item_with_rawdata(&json!({"owner": {}}))).is_none(), "owner 无 web_rid 应跳过");
    }

    #[test]
    fn non_numeric_total_user_degrades_to_zero() {
        let raw = json!({"owner": {"web_rid": "1"}, "stats": {"total_user": "1.2万"}});
        assert_eq!(
            parse_item(&item_with_rawdata(&raw)).expect("应能解析").online,
            0,
            "Dart 的 int.tryParse 同样失败为 0"
        );
    }
}
