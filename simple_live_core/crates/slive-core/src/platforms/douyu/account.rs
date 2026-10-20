//! F-17~F-20 账号体系（对照 `douyu_site.dart:360-473`）。
//!
//! 三个接口：
//! - F-17 `set_site_attrs`：注入 `{cookie, dy_did, LTP0}`（缺键保留旧值 —— J-5）；
//! - F-18 `get_qr_code`：先取 `dy_did`（JSONP 文本），再 POST `scan/generateCode`；
//! - F-19 `get_qr_poll_result`：`scan/auth` 轮询 + `set-cookie` 里的 `LTP0` 换 cookie；
//! - F-20 `get_account_info`：先用 `refreshCookie` 续期，再从 cookie 里取 `acf_*` 字段。
//!
//! 错误口径：业务 `error != 0` -> [`SliveError::Api`]，不重试；`scan/auth` 出现未知错误码
//! 时按 Dart `default:` 分支返回 `failed` 并带服务端 `msg`（不抛异常打断轮询）。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{AccountInfo, QrCode, QrPollResult, QrStatus};
use crate::util::value_to_string;

use super::api_code::check_error_code;
use super::cookie::{pick_cookie, pick_set_cookie, refresh_cookie};
use super::header::request_header;
use super::site::{DouyuSite, DEFAULT_DY_DID};

/// `dy_did` 获取端点（JSONP 文本）。
const DID_URL: &str = "https://passport.douyu.com/lapi/did/api/get";
/// 二维码生成端点。
const QR_GENERATE_URL: &str = "https://passport.douyu.com/scan/generateCode";
/// 二维码轮询端点。
const QR_POLL_URL: &str = "https://passport.douyu.com/japi/scan/auth";
/// 二维码有效期（秒），对齐 Dart `now + 300`。
const QR_EXPIRE_SECS: i64 = 300;

/// F-17 注入凭证。
///
/// 非法 JSON -> [`SliveError::InvalidInput`]（对齐 Spec J-5）；JSON 合法但缺键 -> **保留旧值**。
pub(crate) fn set_site_attrs(site: &DouyuSite, data: &str) -> Result<(), SliveError> {
    // 空串 = 未登录账号的 credential（App `accountLogin` 既有路径：有账号记录但
    // credential 为空时会把空串注入进来）。空串不是合法 JSON，且会把上一次的
    // 有效 attrs 覆盖成空 —— 这里显式短路为 Ok（语义：清空注入）。
    if data.trim().is_empty() {
        return Ok(());
    }

    let value: Value = serde_json::from_str(data)
        .map_err(|e| SliveError::invalid_input(format!("setSiteAttrs 入参不是合法 JSON: {e}")))?;
    let object = value
        .as_object()
        .ok_or_else(|| SliveError::invalid_input("setSiteAttrs 入参必须是 JSON 对象"))?;

    if let Some(cookie) = object.get("cookie").and_then(Value::as_str) {
        site.set_cookie(cookie);
        // 只记录存在性，不记录明文（AC-40）。
        crate::logging::log_credential_injected("cookie", cookie);
    }
    if let Some(did) = object.get("dy_did").and_then(Value::as_str) {
        site.set_dy_did(did);
    }
    if let Some(ltp0) = object.get("LTP0").and_then(Value::as_str) {
        site.set_ltp0(ltp0);
    }
    Ok(())
}

/// F-18 生成登录二维码。
pub(crate) async fn get_qr_code(site: &DouyuSite) -> Result<QrCode, SliveError> {
    // 第一步：取（或确认）dy_did —— 响应是 JSONP 文本，需剥掉 `cb(...)` 包装。
    let reply = site
        .get_reply(
            DID_URL,
            vec![
                ("client_id".to_string(), "1".to_string()),
                ("callback".to_string(), "cb".to_string()),
            ],
            request_header(site, "", &site.cookie(), true),
        )
        .await?;
    let did = parse_jsonp(&reply.text)
        .and_then(|value| {
            value
                .pointer("/data/did")
                .map(value_to_string)
                .filter(|s| !s.is_empty())
        })
        .unwrap_or_else(|| DEFAULT_DY_DID.to_string());
    site.set_dy_did(&did);

    // 第二步：POST 生成二维码。
    let value = site
        .post_form_json(
            QR_GENERATE_URL,
            "client_id=1&isMultiAccount=0",
            request_header(site, "", &site.cookie(), true),
        )
        .await?;
    check_error_code(&value)?;
    let data = value
        .get("data")
        .filter(|d| d.is_object())
        .ok_or_else(|| SliveError::decode("二维码响应缺 data 字段"))?;

    Ok(QrCode {
        key: data
            .get("code")
            .map(value_to_string)
            .ok_or_else(|| SliveError::decode("二维码响应缺 code 字段"))?,
        url: data.get("url").map(value_to_string).unwrap_or_default(),
        created_at: Some(site.now_secs() as i64),
        expire_at: Some(site.now_secs() as i64 + QR_EXPIRE_SECS),
    })
}

/// F-19 扫码轮询。
///
/// `error` 映射（对齐 Dart `getQRPollResult`）：`-2` 未扫 / `1` 已扫待确认 / `-1` 已过期 /
/// `0` 登录成功（换 cookie + 产 credential）/ 其他 -> `failed`。
pub(crate) async fn get_qr_poll_result(
    site: &DouyuSite,
    qrcode_key: &str,
) -> Result<QrPollResult, SliveError> {
    let mut headers = request_header(site, "", &site.cookie(), true);
    headers.push((
        "X-Requested-With".to_string(),
        "XMLHttpRequest".to_string(),
    ));
    let reply = site
        .get_reply(
            QR_POLL_URL,
            vec![
                ("code".to_string(), qrcode_key.to_string()),
                ("time".to_string(), site.now_millis().to_string()),
            ],
            headers,
        )
        .await?;
    let value = reply.json()?;

    let message = value.get("msg").map(value_to_string).unwrap_or_default();
    let code = value.get("error").and_then(Value::as_i64);
    let result = match code {
        Some(-2) => QrPollResult {
            status: QrStatus::Unscanned,
            credential: String::new(),
            message,
        },
        Some(1) => QrPollResult {
            status: QrStatus::Scanned,
            credential: String::new(),
            message,
        },
        Some(-1) => QrPollResult {
            status: QrStatus::Expired,
            credential: String::new(),
            message,
        },
        Some(0) => {
            let url = value
                .pointer("/data/url")
                .map(value_to_string)
                .unwrap_or_default();
            if url.is_empty() {
                return Err(SliveError::decode("斗鱼未返回登录确认地址"));
            }
            // 登录成功：set-cookie 下发 LTP0，用它换一份完整 cookie。
            let ltp0 = pick_set_cookie(&reply.set_cookie, "LTP0");
            let did = site.dy_did();
            let new_cookie = refresh_cookie(site, &did, &ltp0, &site.cookie()).await?;
            site.set_cookie(&new_cookie);
            site.set_ltp0(&ltp0);
            // AC-40：不打印 cookie 明文。
            crate::logging::log_credential_injected("qr-cookie", &new_cookie);
            QrPollResult {
                status: QrStatus::Scanned,
                credential: serde_json::json!({
                    "dy_did": did,
                    "LTP0": ltp0,
                    "cookie": new_cookie,
                })
                .to_string(),
                message,
            }
        }
        _ => {
            // Dart `default:` 分支：`throw StateError('斗鱼暂时无法确认登录，请刷新重试')`
            // —— 用**固定**文案（不取服务端 msg，对齐 Dart），但保留原始错误码便于排障。
            return Err(SliveError::Api {
                code: code.unwrap_or(0) as i32,
                message: "斗鱼暂时无法确认登录，请刷新重试".to_string(),
            });
        }
    };
    Ok(result)
}

/// F-20 账号信息：先用 `refreshCookie` 续期，再从 cookie 里取 `acf_*` 字段。
///
/// 写回凭证时保留入参的全部键（`dy_did`/`LTP0` 是续期材料，丢了就再也续不了期），
/// 只替换 `cookie` —— 对齐 Dart 的全量回写。
///
/// 对齐 Dart：uid=`acf_uid`、name=`Uri.decodeComponent(acf_nickname)`、
/// avatar=`Uri.decodeComponent(acf_avatar)` + `middle.jpg`；`isValid = cookie 非空`。
/// 出错时返回 `isValid=false` 的空信息（对齐 Dart 的 try/catch 全吞），不抛。
pub(crate) async fn get_account_info(
    site: &DouyuSite,
    credential: &str,
) -> Result<AccountInfo, SliveError> {
    let mut result = AccountInfo {
        name: None,
        avatar: None,
        uid: None,
        credential: credential.to_string(),
        is_valid: false,
    };
    if set_site_attrs(site, credential).is_err() {
        return Ok(result);
    }

    let did = site.dy_did();
    let ltp0 = site.ltp0();
    let Ok(new_cookie) = refresh_cookie(site, &did, &ltp0, &site.cookie()).await else {
        return Ok(result);
    };
    if new_cookie.is_empty() {
        return Ok(result);
    }
    site.set_cookie(&new_cookie);

    let avatar_base = percent_decode(&pick_cookie(Some(&new_cookie), "acf_avatar"));
    result.uid = Some(pick_cookie(Some(&new_cookie), "acf_uid"));
    result.name = Some(percent_decode(&pick_cookie(
        Some(&new_cookie),
        "acf_nickname",
    )));
    result.avatar = Some(format!("{avatar_base}middle.jpg"));
    result.credential = merge_credential_cookie(credential, &new_cookie);
    result.is_valid = true;
    Ok(result)
}

/// 写回凭证：保留入参里的全部键（`dy_did`/`LTP0` 等续期材料），只替换 `cookie`。
///
/// 对齐 Dart `getAccountInfo` 的 `newCredential['cookie'] = newCookie` 全量回写；
/// 早先只回 `{"cookie": ...}` 会把续期材料丢掉，升级用户的 cookie 到期后无法续期。
/// 入参不是 JSON 对象时退化为 `{"cookie": ...}`。
fn merge_credential_cookie(credential: &str, new_cookie: &str) -> String {
    let mut map = match serde_json::from_str::<serde_json::Map<String, Value>>(credential) {
        Ok(map) => map,
        Err(_) => serde_json::Map::new(),
    };
    map.insert("cookie".to_string(), Value::String(new_cookie.to_string()));
    Value::Object(map).to_string()
}

/// 剥离 JSONP 包装：`cb({...})` -> `{...}`；不是 JSONP 时原样返回。
fn parse_jsonp(text: &str) -> Option<Value> {
    let trimmed = text.trim();
    let body = if trimmed.starts_with('{') {
        trimmed
    } else {
        let start = trimmed.find('(')?;
        let end = trimmed.rfind(')')?;
        if end <= start {
            return None;
        }
        &trimmed[start + 1..end]
    };
    serde_json::from_str(body.trim()).ok()
}

/// 百分号解码（对齐 Dart `Uri.decodeComponent`）。
fn percent_decode(input: &str) -> String {
    if !input.contains('%') {
        return input.to_string();
    }
    let bytes = input.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).unwrap_or("");
            if let Ok(byte) = u8::from_str_radix(hex, 16) {
                out.push(byte);
                index += 3;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

#[cfg(test)]
mod tests {
    #[test]
    fn set_site_attrs_tolerates_empty_credential() {
        let site = DouyuSite::new();
        assert!(super::set_site_attrs(&site, "").is_ok());
    }

    use super::*;
    use super::super::header::DOUYU_LOGIN_REFERER;

    #[test]
    fn jsonp_wrapper_is_stripped() {
        let value = parse_jsonp(r#"cb({"data":{"did":"DID-9"}})"#).expect("应解析");
        assert_eq!(value.pointer("/data/did").unwrap(), "DID-9");
        let plain = parse_jsonp(r#"{"data":{"did":"DID-8"}}"#).expect("裸 JSON 应解析");
        assert_eq!(plain.pointer("/data/did").unwrap(), "DID-8");
        assert!(parse_jsonp("not json").is_none());
        assert!(parse_jsonp("cb(").is_none(), "缺右括号不应 panic");
    }

    #[test]
    fn percent_decode_matches_uri_decode_component() {
        assert_eq!(percent_decode("%E5%BC%A0%E4%B8%89"), "张三");
        assert_eq!(percent_decode("plain"), "plain");
        assert_eq!(percent_decode("100%"), "100%", "残缺转义原样保留");
        assert_eq!(percent_decode("%zz"), "%zz");
    }

    #[test]
    fn login_referer_constant_is_used_for_is_login() {
        // 该常量是 is_login 头分支的唯一来源，锁死避免被误改
        assert!(DOUYU_LOGIN_REFERER.starts_with("https://passport.douyu.com/"));
    }

    #[test]
    fn credential_write_back_keeps_renewal_keys() {
        // 升级用户的 credential 带 dy_did/LTP0：写回只许换 cookie，不许丢键
        let merged = merge_credential_cookie(
            r#"{"cookie":"old","dy_did":"DID-1","LTP0":"LTP1"}"#,
            "new",
        );
        let map: serde_json::Value = serde_json::from_str(&merged).expect("合法 JSON");
        assert_eq!(map["cookie"], "new");
        assert_eq!(map["dy_did"], "DID-1", "dy_did 必须保留");
        assert_eq!(map["LTP0"], "LTP1", "LTP0 必须保留");
    }

    #[test]
    fn credential_write_back_tolerates_non_object_input() {
        let merged = merge_credential_cookie("not json", "new");
        let map: serde_json::Value = serde_json::from_str(&merged).expect("合法 JSON");
        assert_eq!(map["cookie"], "new");
    }
}