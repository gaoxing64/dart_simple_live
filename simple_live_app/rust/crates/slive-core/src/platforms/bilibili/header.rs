//! 公共请求头（F-21，对照 `bilibili_site.dart:31-48` `getHeader`）。
//!
//! 无 cookie -> 注入 `buvid3/buvid4`；有 cookie 且不含 `buvid3` -> 追加。
//! **禁止**记录 cookie 明文（AC-40）。

use crate::error::SliveError;
use crate::http::{DEFAULT_REFERER, DEFAULT_USER_AGENT};

use super::site::BilibiliSite;

/// 构造带 buvid 的请求头。
pub(crate) async fn build_header(
    site: &BilibiliSite,
) -> Result<Vec<(String, String)>, SliveError> {
    let (buvid3, buvid4) = super::buvid::ensure_buvid(site).await?;
    let cookie = site.cookie();

    let cookie_header = if cookie.is_empty() {
        format!("buvid3={buvid3};buvid4={buvid4};")
    } else if cookie.contains("buvid3") {
        cookie
    } else {
        format!("{cookie};buvid3={buvid3};buvid4={buvid4};")
    };

    Ok(vec![
        ("cookie".to_string(), cookie_header),
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
        ("referer".to_string(), DEFAULT_REFERER.to_string()),
    ])
}
