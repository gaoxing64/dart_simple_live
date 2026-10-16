//! Cookie 工具与刷新（对照 `douyu_utils.dart:50-108` + `parse_cookie.dart`）。
//!
//! 斗鱼 cookie 的过期判定靠 JWT：取 `acf_jwt_token` 的 payload `exp` 与当前秒比较。
//! 本模块**不引新依赖**（`Cargo.toml` 已锁定，且禁改）—— base64url 解码按 RFC 4648 手写，
//! 解码失败一律按「已过期」处理（与 Dart `catch → return true` 同口径）。

use serde_json::Value;

use crate::error::SliveError;
use crate::http::HttpRequest;

use super::header::request_header;
use super::site::DouyuSite;

/// safeAuth 端点（cookie 续期）。
const SAFE_AUTH_URL: &str = "https://passport.douyu.com/lapi/passport/iframe/safeAuth";
/// JWT 载荷里的 cookie 名。
const JWT_COOKIE_NAME: &str = "acf_jwt_token";

/// 从 cookie 串取字段（对照 `douyu_utils.dart:173-186`）。
pub fn pick_cookie(cookie: Option<&str>, name: &str) -> String {
    let Some(cookie) = cookie else {
        return String::new();
    };
    for part in cookie.split(';') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let Some((key, value)) = part.split_once('=') else {
            continue;
        };
        if key.trim() == name {
            return value.trim().to_string();
        }
    }
    String::new()
}

/// 从 `set-cookie` 响应头列表取指定 cookie 的值（对照 `douyu_utils.dart:162-170`）。
pub fn pick_set_cookie(raw: &[String], name: &str) -> String {
    for entry in raw {
        let pair = entry.split(';').next().unwrap_or("").trim();
        if let Some((key, value)) = pair.split_once('=') {
            if key.trim() == name {
                return value.trim().to_string();
            }
        }
    }
    String::new()
}

/// `set-cookie` 列表 -> cookie 串（各项取 `;` 前段，以 `; ` 连接；对照 `douyu_utils.dart:71-74`）。
pub fn join_set_cookie(raw: &[String]) -> String {
    raw.iter()
        .filter_map(|entry| entry.split(';').next())
        .map(|pair| pair.trim())
        .filter(|pair| pair.contains('='))
        .collect::<Vec<_>>()
        .join("; ")
}

/// 取 JWT payload（对照 `parse_cookie.dart:15-29`）。
pub fn decode_jwt_payload(token: &str) -> Result<Value, SliveError> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err(SliveError::decode("非法的 JWT 结构"));
    }
    let raw = base64url_decode(parts[1])?;
    let text = String::from_utf8(raw)
        .map_err(|e| SliveError::decode(format!("JWT 载荷不是合法 UTF-8: {e}")))?;
    serde_json::from_str(&text).map_err(|e| SliveError::decode(format!("JWT 载荷不是合法 JSON: {e}")))
}

/// cookie 是否已过期（或根本不是合法登录态）——对齐 `_isCookieExpired`。
///
/// 口径：取不到 `acf_jwt_token`、`exp` 不是整数、`now >= exp`、解码异常，**一律视为过期**。
pub fn is_cookie_expired(cookie: &str, now_secs: u64) -> bool {
    let token = pick_cookie(Some(cookie), JWT_COOKIE_NAME);
    if token.is_empty() {
        return true;
    }
    match decode_jwt_payload(&token) {
        Ok(payload) => match payload.get("exp").and_then(Value::as_i64) {
            Some(exp) => (now_secs as i64) >= exp,
            None => true,
        },
        Err(_) => true,
    }
}

/// 刷新 cookie：仅在「已过期且 `ltp0`/`did` 齐备」时请求 `safeAuth` 续期，
/// 否则原样返回（对照 `douyu_utils.dart:54-80`）。
///
/// 续期结果仍按同一 JWT 规则复检；复检不通过则**降级为空串**（游客模式）。
pub async fn refresh_cookie(
    site: &DouyuSite,
    did: &str,
    ltp0: &str,
    cookie: &str,
) -> Result<String, SliveError> {
    if !is_cookie_expired(cookie, site.now_secs()) || ltp0.is_empty() || did.is_empty() {
        return Ok(cookie.to_string());
    }

    let t = site.now_millis().to_string();
    let request = HttpRequest {
        url: SAFE_AUTH_URL.to_string(),
        query: vec![
            ("client_id".to_string(), "1".to_string()),
            ("t".to_string(), t.clone()),
            ("_".to_string(), t),
            ("callback".to_string(), "axiosJsonpCallback".to_string()),
        ],
        headers: request_header(site, "", &format!("dy_did={did};LTP0={ltp0}"), false),
    };
    let reply = site.http().get(&request).await?;
    let refreshed = join_set_cookie(&reply.set_cookie);
    let result = if is_cookie_expired(&refreshed, site.now_secs()) {
        String::new()
    } else {
        refreshed
    };
    // Dart 在此处把静态 `_did` 同步为入参 did（对齐 `_did = did`）。
    site.set_dy_did(did);
    Ok(result)
}

/// base64url 解码（RFC 4648 §5：`-_` 还原为 `+/`，补位 padding）。
fn base64url_decode(input: &str) -> Result<Vec<u8>, SliveError> {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let normalized: String = input
        .chars()
        .filter(|c| *c != '=' && !c.is_whitespace())
        .map(|c| match c {
            '-' => '+',
            '_' => '/',
            other => other,
        })
        .collect();
    if normalized.len() % 4 == 1 {
        return Err(SliveError::decode("非法的 base64url 长度"));
    }
    let mut out = Vec::with_capacity(normalized.len() / 4 * 3);
    for chunk in normalized.as_bytes().chunks(4) {
        let mut buffer = 0u32;
        for (index, byte) in chunk.iter().enumerate() {
            let value = TABLE
                .iter()
                .position(|t| t == byte)
                .ok_or_else(|| SliveError::decode("非法的 base64url 字符"))?;
            buffer |= (value as u32) << (18 - 6 * index);
        }
        let take = match chunk.len() {
            2 => 1,
            3 => 2,
            4 => 3,
            _ => 0,
        };
        for index in 0..take {
            out.push(((buffer >> (16 - 8 * index)) & 0xFF) as u8);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 生成一个 `exp` 在未来的 cookie（payload 用固定明文，测试内联 base64url）。
    fn cookie_with_exp(payload_b64: &str) -> String {
        format!("acf_uid=u1; acf_jwt_token=aaa.{payload_b64}.ccc")
    }

    #[test]
    fn base64url_decodes_rfc4648_vectors() {
        assert_eq!(base64url_decode("aGVsbG8").unwrap(), b"hello".to_vec());
        assert_eq!(base64url_decode("aGVsbG8h").unwrap(), b"hello!".to_vec());
        // URL-safe 变体：`_` / `-`
        let url_safe = base64url_decode("Pz8_Pg").unwrap();
        assert_eq!(url_safe, base64url_decode("Pz8/Pg").unwrap());
        assert!(base64url_decode("A").is_err(), "长度为 1 的余数非法");
    }

    #[test]
    fn jwt_payload_exp_is_read() {
        // {"exp":4102444800} -> base64url
        let cookie = cookie_with_exp("eyJleHAiOjQxMDI0NDQ4MDB9");
        assert_eq!(
            decode_jwt_payload(&pick_cookie(Some(&cookie), "acf_jwt_token"))
                .expect("payload 可解析")["exp"],
            4_102_444_800i64
        );
    }

    #[test]
    fn expired_when_token_missing_malformed_or_time_passed() {
        assert!(is_cookie_expired("", 1_000), "空 cookie 视为过期");
        assert!(is_cookie_expired("acf_uid=u1", 1_000), "无 JWT 视为过期");
        assert!(
            is_cookie_expired("acf_jwt_token=bad.token", 1_000),
            "结构非法视为过期"
        );
        let future = cookie_with_exp("eyJleHAiOjQxMDI0NDQ4MDB9");
        assert!(!is_cookie_expired(&future, 1_700_000_000), "未过期");
        assert!(
            is_cookie_expired(&future, 4_102_444_800),
            "now == exp 即过期（对齐 Dart nowSec >= exp）"
        );
    }

    #[test]
    fn pick_cookie_and_set_cookie() {
        let cookie = "acf_uid=u1; acf_nickname=%E5%BC%A0%E4%B8%89 ";
        assert_eq!(pick_cookie(Some(cookie), "acf_uid"), "u1");
        assert_eq!(pick_cookie(Some(cookie), "acf_nickname"), "%E5%BC%A0%E4%B8%89");
        assert_eq!(pick_cookie(Some(cookie), "missing"), "");
        assert_eq!(pick_cookie(None, "acf_uid"), "");

        let raw = vec![
            "LTP0=ltp-value; Path=/; HttpOnly".to_string(),
            "acf_uid=u9; Path=/".to_string(),
        ];
        assert_eq!(pick_set_cookie(&raw, "LTP0"), "ltp-value");
        assert_eq!(pick_set_cookie(&raw, "acf_uid"), "u9");
        assert_eq!(pick_set_cookie(&raw, "nope"), "");
        assert_eq!(join_set_cookie(&raw), "LTP0=ltp-value; acf_uid=u9");
    }
}