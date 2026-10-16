//! buvid3 / buvid4 指纹（F-21，对照 `bilibili_site.dart:389-414` `getBuvid`）。
//!
//! 优先从 cookie 解析；否则请求 `x/frontend/finger/spi`。指纹接口失败 -> 返回空 buvid（不阻断）。
//! 结果写回**句柄级**缓存（非进程级静态，见 R-08）。

use crate::error::SliveError;
use crate::http::{HttpRequest, DEFAULT_REFERER, DEFAULT_USER_AGENT};
use crate::util::as_string;

use super::cookie;
use super::site::BilibiliSite;

const SPI_URL: &str = "https://api.bilibili.com/x/frontend/finger/spi";

/// 确保 buvid 可用；返回 `(buvid3, buvid4)`。
pub(crate) async fn ensure_buvid(
    site: &BilibiliSite,
) -> Result<(String, String), SliveError> {
    let (cached3, cached4) = site.buvid_snapshot();
    if !cached3.is_empty() {
        return Ok((cached3, cached4));
    }

    let cookie_str = site.cookie();
    if cookie_str.contains("buvid3") {
        let buvid3 = cookie::find_cookie(&cookie_str, "buvid3").unwrap_or_default();
        let buvid4 = cookie::find_cookie(&cookie_str, "buvid4").unwrap_or_default();
        site.set_buvid(&buvid3, &buvid4);
        return Ok((buvid3, buvid4));
    }

    // 指纹接口失败 -> 空 buvid，不阻断（Dart catch -> {"b_3":"","b_4":""}）。
    let (buvid3, buvid4): (String, String) =
        fetch_spi(site, &cookie_str).await.unwrap_or_default();
    site.set_buvid(&buvid3, &buvid4);
    Ok((buvid3, buvid4))
}

async fn fetch_spi(
    site: &BilibiliSite,
    cookie_str: &str,
) -> Result<(String, String), SliveError> {
    let headers = vec![
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
        ("referer".to_string(), DEFAULT_REFERER.to_string()),
        ("cookie".to_string(), cookie_str.to_string()),
    ];
    let request = HttpRequest {
        url: SPI_URL.to_string(),
        query: vec![],
        headers,
    };
    let reply = site.http().get(&request).await?;
    let value = reply.json()?;
    Ok((
        as_string(value.pointer("/data/b_3")).unwrap_or_default(),
        as_string(value.pointer("/data/b_4")).unwrap_or_default(),
    ))
}
