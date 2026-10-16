//! 公共请求头与 ttwid cookie 获取（对照 Dart `DouyinSite.getRequestHeaders`，
//! `douyin_site.dart:31-57`）。
//!
//! 行为要点：
//! - 基础三头固定：`Authority=live.douyin.com` / `Referer=https://live.douyin.com` /
//!   `User-Agent=DouyinRequestParams.kDefaultUserAgent`；
//! - cookie 已含 `ttwid` -> 直接复用（不额外请求）；
//! - 否则取一次 `live.douyin.com` 的 `set-cookie`，把 `ttwid=...` **前置**拼到现有 cookie；
//! - 取 cookie 失败**吞掉**并照常返回（Dart 的 `catch` 只 `CoreLog.error`）——
//!   抖音首页/分类接口对无 cookie 也返回降级数据，不该因此整页失败。
//!
//! ⚠️ **刻意偏离：HEAD -> GET**。Dart 用 `dio.head` 只取响应头；core 的
//! [`HttpTransport`] seam 只暴露 `get`（`head` 会牵动 `http.rs` / `testing.rs` 两个
//! **共享文件**，四路并行期间不可改）。改用 GET 后 `set-cookie` 同样可得，
//! **请求数与 Dart 同路径仍为 1 次**（§9 性能口径不受影响），仅多下载一次首页体积。
//! 若日后 `HttpTransport` 增补 `head`，此处改回即可（调用点已隔离在本文件）。

use crate::error::SliveError;
use crate::http::HttpRequest;

use super::danmaku::args::DEFAULT_USER_AGENT;
use super::site::DouyinSite;

/// 默认 Authority（`DouyinSite.kDefaultAuthority`）。
pub const DEFAULT_AUTHORITY: &str = "live.douyin.com";
/// 默认 Referer（`DouyinSite.kDefaultReferer`）。
pub const DEFAULT_REFERER: &str = "https://live.douyin.com";
/// 取 ttwid 的目标站点（Dart HEAD 的同一个 URL）。
pub const TTWID_HOST_URL: &str = "https://live.douyin.com";
/// cookie 中 ttwid 的键名。
pub const TTWID_KEY: &str = "ttwid";

/// 基础三头（不含 cookie）。
pub fn base_headers() -> Vec<(String, String)> {
    vec![
        ("Authority".to_string(), DEFAULT_AUTHORITY.to_string()),
        ("Referer".to_string(), DEFAULT_REFERER.to_string()),
        ("User-Agent".to_string(), DEFAULT_USER_AGENT.to_string()),
    ]
}

/// 携带 cookie 的完整请求头。
pub fn build_header(site: &DouyinSite) -> Vec<(String, String)> {
    let mut headers = base_headers();
    let cookie = site.header_cookie();
    if !cookie.is_empty() {
        headers.push(("cookie".to_string(), cookie));
    }
    headers
}

/// 取一次 ttwid 并写入句柄（幂等：已有 ttwid 时**不发请求**，对齐 Dart 的短路）。
pub async fn ensure_ttwid(site: &DouyinSite) -> Result<(), SliveError> {
    if site.header_cookie().contains(TTWID_KEY) {
        return Ok(());
    }
    let request = HttpRequest {
        url: TTWID_HOST_URL.to_string(),
        query: Vec::new(),
        headers: base_headers(),
    };
    match site.http().get(&request).await {
        Ok(reply) => {
            if let Some(ttwid) = reply
                .set_cookie
                .iter()
                .filter_map(|raw| ttwid_pair(raw))
                .next_back()
            {
                site.merge_ttwid(&ttwid);
            }
            Ok(())
        }
        // Dart：取 cookie 失败只记日志、照常返回 headers
        Err(e) => {
            log::warn!("获取抖音 ttwid 失败（以无 cookie 继续）: {e}");
            Ok(())
        }
    }
}

/// 直播间页专用 cookie：取 `ttwid` + `__ac_nonce` + `msToken` 三个键。
///
/// 对照 Dart `_getWebCookie`（`douyin_site.dart:860-879`）：进房前先 HEAD 一次
/// 房间页，把这三个 cookie 攒起来专供 HTML 链路使用。
///
/// ⚠️ **这是 HTML 兜底链路的关键前置**：`web/enter` 被风控拦下时才走 HTML，
/// 而那正是最需要完整 cookie 的时刻 —— 只带根域 ttwid 时页面可能返回骨架
/// （`roomInfo.room` 为空），表现为「进不去房但没有任何提示」。
///
/// 与 Dart 的两处差异（均为「不丢能力」方向）：
/// 1. Dart 用 HEAD，core 的 [`slive_core::http::HttpTransport`] 只暴露 GET
///    （与 `ensure_ttwid` 同一约束，见模块文档）；
/// 2. Dart 的返回**只含**这三个 cookie、丢掉注入的登录 cookie，这里把注入 cookie
///    一并带上（否则会员房间在 HTML 链路上必然进不去）。
pub async fn room_page_cookie(site: &DouyinSite, web_rid: &str) -> String {
    let url = format!("https://live.douyin.com/{web_rid}");
    let collected = match site
        .http()
        .get(&HttpRequest {
            url,
            query: Vec::new(),
            headers: base_headers(),
        })
        .await
    {
        Ok(reply) => collect_room_cookies(&reply.set_cookie),
        Err(e) => {
            log::warn!("获取抖音房间页 cookie 失败（以现有 cookie 继续）: {e}");
            String::new()
        }
    };
    let injected = site.header_cookie();
    match (collected.is_empty(), injected.is_empty()) {
        (true, true) => String::new(),
        (true, false) => injected,
        (false, true) => collected,
        (false, false) => format!("{collected}; {injected}"),
    }
}

/// 从 `set-cookie` 列表里挑出房间页需要的三个键（截断到第一个 `;`）。
fn collect_room_cookies(set_cookie: &[String]) -> String {
    const KEYS: [&str; 3] = ["ttwid", "__ac_nonce", "msToken"];
    let mut out = Vec::new();
    for raw in set_cookie {
        let pair = raw.split(';').next().unwrap_or("").trim();
        let key = pair.split('=').next().unwrap_or("");
        if KEYS.contains(&key) {
            out.push(pair.to_string());
        }
    }
    out.join("; ")
}

/// 从一条 `set-cookie` 里取出 `ttwid=...`（截断到第一个 `;`）。
fn ttwid_pair(raw: &str) -> Option<String> {
    let pair = raw.split(';').next().unwrap_or("").trim();
    pair.starts_with(TTWID_KEY)
        .then(|| pair.to_string())
}

/// 供搜索接口使用：以 `www.douyin.com` 为 Authority 的头（对齐 Dart `searchRooms`）。
pub fn search_headers(site: &DouyinSite, keyword: &str) -> Vec<(String, String)> {
    vec![
        ("Authority".to_string(), "www.douyin.com".to_string()),
        (
            "accept".to_string(),
            "application/json, text/plain, */*".to_string(),
        ),
        (
            "accept-language".to_string(),
            "zh-CN,zh;q=0.9,en;q=0.8".to_string(),
        ),
        ("cookie".to_string(), site.header_cookie()),
        ("priority".to_string(), "u=1, i".to_string()),
        (
            "referer".to_string(),
            format!(
                "https://www.douyin.com/search/{}?type=live",
                crate::util::encode_query_component(keyword)
            ),
        ),
        (
            "sec-ch-ua".to_string(),
            "\"Microsoft Edge\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\""
                .to_string(),
        ),
        ("sec-ch-ua-mobile".to_string(), "?0".to_string()),
        (
            "sec-ch-ua-platform".to_string(),
            "\"Windows\"".to_string(),
        ),
        ("sec-fetch-dest".to_string(), "empty".to_string()),
        ("sec-fetch-mode".to_string(), "cors".to_string()),
        ("sec-fetch-site".to_string(), "same-origin".to_string()),
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
    ]
}

/// 供账号接口使用：`webcast/user/me/` 的头（对齐 Dart `getAccountInfo`）。
pub fn account_headers(cookie: &str) -> Vec<(String, String)> {
    vec![
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
        (
            "accept".to_string(),
            "application/json, text/plain, */*".to_string(),
        ),
        (
            "accept-language".to_string(),
            "zh-CN,zh;q=0.9,en;q=0.8".to_string(),
        ),
        ("Cookie".to_string(), cookie.to_string()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ttwid_pair_strips_attributes_and_requires_prefix() {
        assert_eq!(
            ttwid_pair("ttwid=1%2Cabc; Path=/; HttpOnly"),
            Some("ttwid=1%2Cabc".to_string())
        );
        assert_eq!(ttwid_pair("other=1; Path=/"), None);
        assert_eq!(ttwid_pair(""), None);
    }

    #[test]
    fn collect_room_cookies_picks_the_three_dart_keys() {
        let got = collect_room_cookies(&[
            "ttwid=1%2Cabc; Path=/; HttpOnly".to_string(),
            "__ac_nonce=0691f2c3d4000e5a; Path=/; Max-Age=3600".to_string(),
            "msToken=AbCdEf123; Path=/".to_string(),
            "sessionid=should-not-be-taken; Path=/".to_string(),
            "odin_tt=also-not".to_string(),
        ]);
        assert_eq!(
            got,
            "ttwid=1%2Cabc; __ac_nonce=0691f2c3d4000e5a; msToken=AbCdEf123",
            "只取 Dart `_getWebCookie` 的三个键，其余一律忽略"
        );
    }

    #[test]
    fn collect_room_cookies_tolerates_empty_and_dirty_input() {
        assert_eq!(collect_room_cookies(&[]), "");
        assert_eq!(collect_room_cookies(&["".to_string()]), "");
        assert_eq!(collect_room_cookies(&["no-equals-sign".to_string()]), "");
        // 没有 Path/属性尾巴时也要能取到
        assert_eq!(collect_room_cookies(&["ttwid=xyz".to_string()]), "ttwid=xyz");
    }

    #[test]
    fn base_headers_are_the_three_dart_defaults() {
        let headers = base_headers();
        assert_eq!(headers.len(), 3);
        assert_eq!(headers[0], ("Authority".to_string(), DEFAULT_AUTHORITY.to_string()));
        assert_eq!(headers[1], ("Referer".to_string(), DEFAULT_REFERER.to_string()));
        assert_eq!(headers[2], ("User-Agent".to_string(), DEFAULT_USER_AGENT.to_string()));
    }

    #[test]
    fn account_headers_carry_cookie_verbatim() {
        let headers = account_headers("ttwid=abc");
        assert!(headers
            .iter()
            .any(|(k, v)| k == "Cookie" && v == "ttwid=abc"));
    }

    #[test]
    fn search_headers_encode_keyword_in_referer() {
        let site = DouyinSite::new();
        let headers = search_headers(&site, "a b");
        let referer = headers
            .iter()
            .find(|(k, _)| k == "referer")
            .map(|(_, v)| v.clone())
            .expect("应带 referer");
        assert_eq!(referer, "https://www.douyin.com/search/a+b?type=live");
    }
}
