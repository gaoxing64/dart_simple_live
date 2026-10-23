//! F-17 注入凭证（对照 `bilibili_site.dart:553-558` `setSiteAttrs`）。
//!
//! 口径（J-5 / AC-17）：
//! - 非法 JSON -> [`SliveError::InvalidInput`]；
//! - JSON 合法但缺 `cookie` 键 -> **保留旧值**（不抛、不清空）；
//! - 写入的是 cookie **值本身**，非整串 JSON。
//!
//! IP-2 的二维码/账号三接口（F-18~F-20）亦将落在本模块。

use serde_json::Value;

use crate::error::SliveError;
use crate::http::{check_api_code, HttpRequest, DEFAULT_REFERER, DEFAULT_USER_AGENT};
use crate::models::{AccountInfo, QrCode, QrPollResult, QrStatus};

use super::site::BilibiliSite;

/// 二维码生成端点（对照 `bilibili_site.dart:563`）。
const QRCODE_GENERATE_URL: &str =
    "https://passport.bilibili.com/x/passport-login/web/qrcode/generate";
/// 二维码轮询端点（对照 `bilibili_site.dart:579`）。
const QRCODE_POLL_URL: &str = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll";
/// 账号信息端点（对照 `bilibili_site.dart:617`）。
const ACCOUNT_INFO_URL: &str = "https://api.bilibili.com/x/member/web/account";

/// 注入站点属性（当前仅消费 `cookie`）。
pub(crate) fn set_site_attrs(site: &BilibiliSite, data: &str) -> Result<(), SliveError> {
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
    Ok(())
}

/// F-18 生成登录二维码（`code != 0` 抛错，不返回空码 —— AC-18）。
pub(crate) async fn get_qr_code(site: &BilibiliSite) -> Result<QrCode, SliveError> {
    let value = site.get_json(QRCODE_GENERATE_URL, vec![]).await?;
    check_api_code(&value)?;
    let data = value
        .get("data")
        .ok_or_else(|| SliveError::decode("二维码响应缺 data 字段"))?;
    Ok(QrCode {
        key: data
            .get("qrcode_key")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        url: data
            .get("url")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        created_at: None,
        expire_at: None,
    })
}

/// F-19 扫码轮询：code 映射 `0→scanned+credential` / `86038→expired` / `86090→scanned` /
/// 其余→保持 `unscanned`（AC-19）。
///
/// credential 由 `set-cookie` 各条取 `;` 前段再以 `;` 连接，包成 `{"cookie":...}`
/// （对照 `bilibili_site.dart:590-603`）；`set-cookie` 为空则**不产 credential**、保持未扫描。
pub(crate) async fn get_qr_poll_result(
    site: &BilibiliSite,
    qrcode_key: &str,
) -> Result<QrPollResult, SliveError> {
    let headers = super::header::build_header(site).await?;
    let request = HttpRequest {
        url: QRCODE_POLL_URL.to_string(),
        query: vec![("qrcode_key".to_string(), qrcode_key.to_string())],
        headers,
    };
    let reply = site.http().get(&request).await?;
    let value = reply.json()?;
    check_api_code(&value)?;

    let mut result = QrPollResult {
        status: QrStatus::Unscanned,
        credential: String::new(),
        message: String::new(),
    };
    let Some(data) = value.get("data") else {
        return Ok(result);
    };
    match data.get("code").and_then(Value::as_i64) {
        Some(0) => {
            let cookies: Vec<String> = reply
                .set_cookie
                .iter()
                .filter_map(|c| c.split(';').next())
                .map(str::to_string)
                .collect();
            if !cookies.is_empty() {
                let cookie_str = cookies.join(";");
                // AC-40：只记录注入事件，不打印明文（Dart :598 `CoreLog.i(cookieStr)` 是教训，禁止复刻）。
                crate::logging::log_credential_injected("qr-cookie", &cookie_str);
                result.credential = serde_json::json!({ "cookie": cookie_str }).to_string();
                result.status = QrStatus::Scanned;
            }
        }
        Some(86038) => result.status = QrStatus::Expired,
        Some(86090) => result.status = QrStatus::Scanned,
        _ => {}
    }
    Ok(result)
}

/// F-20 账号信息：成功时**回填 `user_id` 副作用**；任何失败都返回 `is_valid=false`
/// 的空 [`AccountInfo`] 且**不抛**（AC-20 / AC-24，对齐 Dart 的 try/catch 全吞）。
///
/// credential 是 JSON 串，键值对作为**附加请求头**（对照 `bilibili_site.dart:616-619`）。
pub(crate) async fn get_account_info(
    site: &BilibiliSite,
    credential: &str,
) -> Result<AccountInfo, SliveError> {
    let mut result = AccountInfo {
        name: None,
        avatar: None,
        uid: None,
        credential: credential.to_string(),
        is_valid: false,
    };

    // Dart: jsonDecode(credential) 作为 header；解析失败走 catch → 空 AccountInfo
    let Ok(header_object) = serde_json::from_str::<serde_json::Map<String, Value>>(credential)
    else {
        return Ok(result);
    };
    // 只带 credential 自己的头，**不得**叠加 build_header 的 buvid/站点 cookie：
    // B站只认首个 Cookie 头，叠加后校验读到的是 buvid 头，重启后稳定误判未登录。
    let mut headers = vec![
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
        ("referer".to_string(), DEFAULT_REFERER.to_string()),
    ];
    for (key, value) in &header_object {
        if let Some(text) = value.as_str() {
            headers.retain(|(name, _)| !name.eq_ignore_ascii_case(key));
            headers.push((key.clone(), text.to_string()));
        }
    }

    let request = HttpRequest {
        url: ACCOUNT_INFO_URL.to_string(),
        query: vec![],
        headers,
    };
    // Dart: try/catch 全吞 —— 传输/解析失败同样返回 is_valid=false
    let Ok(reply) = site.http().get(&request).await else {
        return Ok(result);
    };
    let Ok(value) = reply.json() else {
        return Ok(result);
    };
    if value.get("code").and_then(Value::as_i64) != Some(0) {
        return Ok(result);
    }
    let Some(data) = value.get("data") else {
        return Ok(result);
    };
    // mid 缺失 → Dart `info.mid!` 抛错被 catch → 空 AccountInfo（AC-20）
    let Some(mid) = data.get("mid").and_then(Value::as_i64) else {
        return Ok(result);
    };
    site.set_user_id(mid);
    result.name = data.get("uname").map(crate::util::value_to_string);
    result.avatar = data.get("face").map(crate::util::value_to_string);
    result.uid = data.get("userid").map(crate::util::value_to_string);
    result.is_valid = true;
    Ok(result)
}
