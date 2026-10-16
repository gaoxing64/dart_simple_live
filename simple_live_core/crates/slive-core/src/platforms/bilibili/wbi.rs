//! wbi 签名链路的**网络 + 缓存**部分（F-22）。
//!
//! - `getWbiKeys`：`x/web-interface/nav` -> `img_key/sub_key`（句柄级缓存）；
//! - `getAccessId`：`live.bilibili.com/lol` -> `w_webid`（句柄级缓存）；
//! - `sign`：从注入时间源取 `wts`，调用 crate 级纯算法 [`crate::wbi`] 产出 `w_rid`。
//!
//! 纯算法在 [`crate::wbi`]（确定性，供 golden 断言）。

use once_cell::sync::Lazy;
use regex::Regex;

use crate::error::SliveError;
use crate::http::HttpRequest;
use crate::util::as_string;

use super::site::BilibiliSite;

const NAV_URL: &str = "https://api.bilibili.com/x/web-interface/nav";
const ACCESS_ID_URL: &str = "https://live.bilibili.com/lol";

static ACCESS_ID_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r#""access_id":"(.*?)""#).expect("access_id 正则字面量合法"));

/// 取（并缓存）wbi `img_key/sub_key`。
pub(crate) async fn wbi_keys(site: &BilibiliSite) -> Result<(String, String), SliveError> {
    if let Some(cached) = site.wbi_keys_cached() {
        return Ok(cached);
    }
    let headers = super::header::build_header(site).await?;
    let request = HttpRequest {
        url: NAV_URL.to_string(),
        query: vec![],
        headers,
    };
    let reply = site.http().get(&request).await?;
    let value = reply.json()?;
    // ⚠️ nav 匿名响应 code=-101（"账号未登录"）但 data.wbi_img 有效 ——
    // 对齐 Dart core `getWbiKeys`（不检查 code），靠下方字段解析兜底。
    // （真实网络冒烟发现的差异：离线合成夹具的 nav 都写了 code:0，未暴露此行为。）

    let img_url = as_string(value.pointer("/data/wbi_img/img_url")).unwrap_or_default();
    let sub_url = as_string(value.pointer("/data/wbi_img/sub_url")).unwrap_or_default();
    let img_key = file_stem(&img_url).ok_or_else(|| {
        SliveError::decode(format!("nav 响应缺少有效 img_url: {img_url}"))
    })?;
    let sub_key = file_stem(&sub_url).ok_or_else(|| {
        SliveError::decode(format!("nav 响应缺少有效 sub_url: {sub_url}"))
    })?;
    site.set_wbi_keys(&img_key, &sub_key);
    Ok((img_key, sub_key))
}

/// 取（并缓存）`access_id`（`w_webid`）。
pub(crate) async fn access_id(site: &BilibiliSite) -> Result<String, SliveError> {
    if let Some(cached) = site.access_id_cached() {
        return Ok(cached);
    }
    let headers = super::header::build_header(site).await?;
    let request = HttpRequest {
        url: ACCESS_ID_URL.to_string(),
        query: vec![],
        headers,
    };
    let reply = site.http().get(&request).await?;
    let id = extract_access_id(&reply.text);
    site.set_access_id(&id);
    Ok(id)
}

/// 对「含 query 的完整 URL」签名，返回可用的 query 参数（含 `wts` + `w_rid`）。
pub(crate) async fn sign(
    site: &BilibiliSite,
    full_url: &str,
) -> Result<Vec<(String, String)>, SliveError> {
    let (img_key, sub_key) = wbi_keys(site).await?;
    let mixin_key = crate::wbi::get_mixin_key(&format!("{img_key}{sub_key}"));

    let mut params = crate::util::parse_query(full_url);
    params.push(("wts".to_string(), site.now_secs().to_string()));
    let w_rid = crate::wbi::get_wbi_sign(&params, &mixin_key);
    params.push(("w_rid".to_string(), w_rid));
    Ok(params)
}

/// 取 URL 路径最后一段的文件名（去扩展名），对齐 Dart `imgUrl.substring(lastIndexOf('/')+1).split('.').first`。
fn file_stem(url: &str) -> Option<String> {
    let last = url.rsplit('/').next().unwrap_or("");
    let stem = last.split('.').next().unwrap_or("");
    if stem.is_empty() {
        None
    } else {
        Some(stem.to_string())
    }
}

/// 从 HTML 文本抽取 `"access_id":"..."`（去反斜杠）。
pub(crate) fn extract_access_id(html: &str) -> String {
    ACCESS_ID_RE
        .captures(html)
        .and_then(|caps| caps.get(1))
        .map(|m| m.as_str().replace('\\', ""))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_stem_strips_dir_and_ext() {
        assert_eq!(
            file_stem("https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png"),
            Some("7cd084941338484aae1ad9425b84077c".to_string())
        );
        assert_eq!(file_stem(""), None);
    }

    #[test]
    fn extract_access_id_handles_escaped_quotes() {
        let html = r#"<html>{"access_id":"ABCDEF123"}</html>"#;
        assert_eq!(extract_access_id(html), "ABCDEF123");
    }
}
