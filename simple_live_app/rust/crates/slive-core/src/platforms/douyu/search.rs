//! F-04 搜索房间 / F-05 搜索主播（对照 `douyu_site.dart:239-272` / `:301-334`）。
//!
//! 两个接口都要求带一个**随机 `dy_did`/`acf_did`** cookie（未登录也能出结果），
//! Dart 用 `generateRandomString(32)` 生成 32 位十六进制串。
//! 本模块用 md5 从「当前时间 + 进程内计数器」取熵（**不引新依赖**：`Cargo.toml` 已锁定
//! 且禁改，`rand` 不在其中），输出同为 32 位十六进制，语义等价。

use md5::{Digest, Md5};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::error::SliveError;
use crate::models::{
    LiveAnchorItem, LiveRoomItem, LiveSearchAnchorResult, LiveSearchRoomResult,
};
use crate::util::{as_i64, value_to_string};

use super::api_code::check_error_code;
use super::header::search_header;
use super::site::DouyuSite;
use super::util::{parse_hot_num, value_or_empty};

/// 搜索房间端点。
const SEARCH_SHOW_URL: &str = "https://www.douyu.com/japi/search/api/searchShow";
/// 搜索主播端点。
const SEARCH_USER_URL: &str = "https://www.douyu.com/japi/search/api/searchUser";
/// 斗鱼搜索固定每页条数（Dart 硬编码 20）。
const PAGE_SIZE: i32 = 20;

/// F-04 搜索房间。
pub(crate) async fn search_rooms(
    site: &DouyuSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchRoomResult, SliveError> {
    let value = request(site, SEARCH_SHOW_URL, keyword, page, Vec::new()).await?;
    check_error_code(&value)?;

    let relate = crate::util::array_at(&value, "/data/relateShow");
    let items: Vec<LiveRoomItem> = relate
        .iter()
        .map(|item| LiveRoomItem {
            room_id: value_or_empty(item, "rid"),
            title: value_or_empty(item, "roomName"),
            cover: value_or_empty(item, "roomSrc"),
            user_name: value_or_empty(item, "nickName"),
            // 斗鱼人气是 "1.2万" 这类串，需按万换算
            online: parse_hot_num(&value_or_empty(item, "hot")),
        })
        .collect();
    Ok(LiveSearchRoomResult {
        has_more: !relate.is_empty(),
        items,
    })
}

/// F-05 搜索主播。
pub(crate) async fn search_anchors(
    site: &DouyuSite,
    keyword: &str,
    page: i32,
) -> Result<LiveSearchAnchorResult, SliveError> {
    let value = request(
        site,
        SEARCH_USER_URL,
        keyword,
        page,
        vec![("filterType".to_string(), "1".to_string())],
    )
    .await?;
    check_error_code(&value)?;

    let relate = crate::util::array_at(&value, "/data/relateUser");
    let items: Vec<LiveAnchorItem> = relate
        .iter()
        .map(|item| {
            let anchor = item.get("anchorInfo");
            let is_live = anchor
                .and_then(|a| a.get("isLive"))
                .map(value_to_string)
                .and_then(|raw| raw.trim().parse::<i64>().ok())
                .unwrap_or(0)
                == 1;
            let room_type = anchor
                .and_then(|a| a.get("roomType"))
                .and_then(|v| as_i64(Some(v)))
                .unwrap_or(0);
            LiveAnchorItem {
                room_id: anchor.map(|a| value_or_empty(a, "rid")).unwrap_or_default(),
                avatar: anchor.map(|a| value_or_empty(a, "avatar")).unwrap_or_default(),
                user_name: anchor.map(|a| value_or_empty(a, "nickName")).unwrap_or_default(),
                // Dart: `liveStatus = isLive == 1 && roomType == 0`
                live_status: is_live && room_type == 0,
            }
        })
        .collect();
    Ok(LiveSearchAnchorResult {
        has_more: !relate.is_empty(),
        items,
    })
}

/// 搜索请求：随机 did cookie + `kw/page/pageSize`。
async fn request(
    site: &DouyuSite,
    url: &str,
    keyword: &str,
    page: i32,
    extra: Vec<(String, String)>,
) -> Result<serde_json::Value, SliveError> {
    let mut query = vec![
        ("kw".to_string(), keyword.to_string()),
        ("page".to_string(), page.max(1).to_string()),
        ("pageSize".to_string(), PAGE_SIZE.to_string()),
    ];
    query.extend(extra);
    site.get_json_with(url, query, search_header(&random_did())).await
}

/// 生成 32 位十六进制随机串（对齐 Dart `generateRandomString(32)`）。
pub(crate) fn random_did() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let seq = COUNTER.fetch_add(1, Ordering::SeqCst);
    let mut hasher = Md5::new();
    hasher.update(site_now_nanos().to_le_bytes());
    hasher.update(seq.to_le_bytes());
    hasher.update(std::process::id().to_le_bytes());
    let digest = format!("{:x}", hasher.finalize());
    digest.chars().take(32).collect()
}

fn site_now_nanos() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use super::super::transport::MockDouyuPost;

    const SHOW_FIXTURE: &str = r#"{"error":0,"data":{"relateShow":[
        {"rid":"999","roomName":"标题","roomSrc":"http://c.jpg","nickName":"主播","hot":"1.2万"}
    ]}}"#;
    const USER_FIXTURE: &str = r#"{"error":0,"data":{"relateUser":[
        {"anchorInfo":{"rid":"999","avatar":"http://a.jpg","nickName":"主播","isLive":"1","roomType":"0"}},
        {"anchorInfo":{"rid":"888","avatar":"http://b.jpg","nickName":"下播主播","isLive":"0","roomType":"0"}},
        {"anchorInfo":{"rid":"777","avatar":"http://c.jpg","nickName":"游戏直播间","isLive":"1","roomType":"1"}}
    ]}}"#;

    fn site() -> (DouyuSite, Arc<MockTransport>) {
        let mock = Arc::new(MockTransport::new());
        mock.stub("searchShow", SHOW_FIXTURE);
        mock.stub("searchUser", USER_FIXTURE);
        let s = DouyuSite::with_deps(
            mock.clone(),
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        (s, mock)
    }

    #[tokio::test]
    async fn search_rooms_maps_hot_and_sends_required_query() {
        let (s, mock) = site();
        let result = s.search_rooms(" LOL ".into(), 2).await.expect("搜索应成功");
        assert_eq!(result.items.len(), 1);
        assert_eq!(result.items[0].room_id, "999");
        assert_eq!(result.items[0].online, 12000, "1.2万 -> 12000");
        assert!(result.has_more);

        // query 以「原值」交给 HttpRequest（URL 编码由 reqwest 负责，见 http.rs）
        let query = &mock.requests()[0].query;
        assert_eq!(
            query,
            &vec![
                ("kw".to_string(), " LOL ".to_string()),
                ("page".to_string(), "2".to_string()),
                ("pageSize".to_string(), "20".to_string()),
            ],
            "Dart 固定 pageSize=20，kw 原样透传"
        );
    }

    #[tokio::test]
    async fn search_rooms_carries_random_did_cookie_header() {
        let (s, mock) = site();
        s.search_rooms("x".into(), 1).await.expect("搜索应成功");
        let cookie = mock.requests()[0]
            .headers
            .iter()
            .find(|(k, _)| k == "Cookie")
            .map(|(_, v)| v.clone())
            .expect("必须带 Cookie 头");
        assert!(cookie.starts_with("dy_did="), "实际 {cookie}");
        assert!(cookie.contains(";acf_did="), "实际 {cookie}");
    }

    #[tokio::test]
    async fn search_anchors_applies_live_status_rule() {
        let (s, mock) = site();
        let result = s.search_anchors("x".into(), 1).await.expect("搜索主播应成功");
        assert_eq!(result.items.len(), 3);
        assert!(result.items[0].live_status, "isLive=1 && roomType=0 -> 在播");
        assert!(!result.items[1].live_status, "isLive=0 -> 不在播");
        assert!(
            !result.items[2].live_status,
            "roomType=1（游戏直播间）不算在播，对齐 Dart"
        );
        assert!(mock.request_urls()[0].contains("filterType=1"));
    }

    #[tokio::test]
    async fn business_error_is_api_error() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("searchShow", r#"{"error":100,"msg":"搜索失败"}"#);
        let s = DouyuSite::with_deps(
            mock,
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        let err = s
            .search_rooms("x".into(), 1)
            .await
            .expect_err("error!=0 必须抛错");
        match err {
            SliveError::Api { code, message } => {
                assert_eq!(code, 100);
                assert_eq!(message, "搜索失败");
            }
            other => panic!("期望 SliveError::Api，实际 {other:?}"),
        }
    }

    #[test]
    fn random_did_is_32_hex_and_varies() {
        let a = random_did();
        let b = random_did();
        assert_eq!(a.len(), 32, "实际 {a}");
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()), "实际 {a}");
        assert_ne!(a, b, "两次生成不应相同（避免被服务端按固定设备识别）");
    }
}