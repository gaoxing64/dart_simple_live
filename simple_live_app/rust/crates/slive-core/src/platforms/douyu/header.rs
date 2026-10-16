//! 斗鱼公共请求头（对照 `douyu_utils.dart:23-48` `requestHeader`）。
//!
//! 差异说明（已在映射文档登记）：Dart 头里带 `accept-encoding: gzip, deflate, br, zstd`，
//! 但 reqwest 侧只启用了 gzip/brotli 解码器 —— 若原样声明 `zstd` 而服务端回 zstd 响应，
//! 会出现「声明能解码却解不出」的静默失败。故本实现**不手写 accept-encoding**，
//! 交由 reqwest 按已启用特性自动声明。

use super::site::DouyuSite;

/// 站点主域。
pub const DOUYU_ORIGIN: &str = "https://www.douyu.com";
/// 登录页 referer（`is_login` 时使用）。
pub const DOUYU_LOGIN_REFERER: &str =
    "https://passport.douyu.com/index/login?type=login&client_id=1";
/// 站点默认 UA（对齐 `douyu_utils.dart:41`）。
pub const DOYU_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43";
/// 搜索接口的 UA（对齐 `douyu_site.dart:250-251`，与站点默认 UA 末段不同）。
pub const DOYU_SEARCH_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51";
/// 站点默认语言协商（对齐 `douyu_utils.dart:36`）。
pub const DOYU_ACCEPT_LANGUAGE: &str =
    "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6,zh-Hans;q=0.5";
/// 搜索页 referer（对齐 `douyu_site.dart:252`）。
pub const DOYU_SEARCH_REFERER: &str = "https://www.douyu.com/search/";

/// 标准请求头（`douyu_utils.dart:28-48`）。
///
/// `room_id` 非空 -> referer 指向房间页；`is_login` -> referer 指向登录页；
/// `cookie` 非空时**整串替换**默认的 `dy_did/acf_did`。
pub(crate) fn request_header(
    site: &DouyuSite,
    room_id: &str,
    cookie: &str,
    is_login: bool,
) -> Vec<(String, String)> {
    let referer = if is_login {
        DOUYU_LOGIN_REFERER.to_string()
    } else if room_id.is_empty() {
        DOUYU_ORIGIN.to_string()
    } else {
        // 房间页 referer
        format!("{DOUYU_ORIGIN}/{room_id}")
    };
    let did = site.dy_did();
    let cookie_header = if cookie.is_empty() {
        format!("dy_did={did}; acf_did={did}")
    } else {
        cookie.to_string()
    };

    vec![
        ("accept".to_string(), "*/*".to_string()),
        (
            "accept-language".to_string(),
            DOYU_ACCEPT_LANGUAGE.to_string(),
        ),
        ("origin".to_string(), DOUYU_ORIGIN.to_string()),
        ("referer".to_string(), referer),
        (
            "content-type".to_string(),
            "application/x-www-form-urlencoded".to_string(),
        ),
        ("user-agent".to_string(), DOYU_USER_AGENT.to_string()),
        ("cookie".to_string(), cookie_header),
    ]
}

/// 房间详情（`betard`）请求头（对齐 `douyu_site.dart:276-280`：仅 referer + UA）。
pub(crate) fn room_info_header(room_id: &str) -> Vec<(String, String)> {
    vec![
        (
            "referer".to_string(),
            format!("{DOUYU_ORIGIN}/{room_id}"),
        ),
        ("user-agent".to_string(), DOYU_USER_AGENT.to_string()),
    ]
}

/// 搜索请求头（对齐 `douyu_site.dart:249-255`：UA + referer + 随机 did cookie）。
pub(crate) fn search_header(did: &str) -> Vec<(String, String)> {
    vec![
        ("user-agent".to_string(), DOYU_SEARCH_USER_AGENT.to_string()),
        ("referer".to_string(), DOYU_SEARCH_REFERER.to_string()),
        (
            "Cookie".to_string(),
            format!("dy_did={did};acf_did={did}"),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use crate::platforms::douyu::transport::MockDouyuPost;

    fn site() -> DouyuSite {
        DouyuSite::with_deps(
            Arc::new(MockTransport::new()),
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        )
    }

    fn header_of(headers: &[(String, String)], name: &str) -> String {
        headers
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    }

    #[test]
    fn referer_switches_by_room_and_login() {
        let s = site();
        assert_eq!(
            header_of(&request_header(&s, "", "", false), "referer"),
            DOUYU_ORIGIN
        );
        assert_eq!(
            header_of(&request_header(&s, "999", "", false), "referer"),
            "https://www.douyu.com/999"
        );
        assert_eq!(
            header_of(&request_header(&s, "999", "", true), "referer"),
            DOUYU_LOGIN_REFERER
        );
    }

    #[test]
    fn default_cookie_is_dy_did_pair_and_overridden_by_cookie() {
        let s = site();
        s.set_dy_did("DID-1");
        assert_eq!(
            header_of(&request_header(&s, "", "", false), "cookie"),
            "dy_did=DID-1; acf_did=DID-1"
        );
        assert_eq!(
            header_of(&request_header(&s, "", "acf_uid=u1", false), "cookie"),
            "acf_uid=u1",
            "传入 cookie 必须整串替换默认值"
        );
    }

    #[test]
    fn search_header_carries_random_did_pair() {
        let headers = search_header("abc123");
        assert_eq!(header_of(&headers, "Cookie"), "dy_did=abc123;acf_did=abc123");
        assert_eq!(header_of(&headers, "referer"), DOYU_SEARCH_REFERER);
        assert_eq!(header_of(&headers, "user-agent"), DOYU_SEARCH_USER_AGENT);
    }
}