//! 凭证注入 / 账号信息（对照 Dart `setSiteAttrs` / `getAccountInfo`，
//! `douyin_site.dart:1232-1287`）。
//!
//! # `set_site_attrs` 的两个键（App 下发的全部内容）
//! - `cookie`：非空则覆盖，空串则**移除**（Dart `headers.remove('cookie')`）；
//! - `hlsFirst`：清晰度列表里 hls 是否排前（`LocalStorageService.kDouyinHlsFirst`）。
//!
//! ⚠️ **cookie 明文禁止进日志**（AC-40，Spec §9）：本模块与 `header` 模块都不打印
//! cookie 值，`SliveError` 的消息里也不拼接。
//!
//! # 账号信息
//! `webcast/user/me/` + `aid=6383`；cookie 为空时直接返回**未校验**的默认对象
//! （`is_valid = false`），Dart 亦然 —— App 的账号流程依赖这个语义区分
//! 「没配 cookie」与「配了但失效」。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::AccountInfo;

use super::site::DouyinSite;
use super::util::as_object;

/// 账号信息接口。
pub const ACCOUNT_URL: &str = "https://live.douyin.com/webcast/user/me/";

/// 注入凭证 / 配置（同步）。
pub(crate) fn set_site_attrs(site: &DouyinSite, data: &str) -> Result<(), SliveError> {
    // 空串 = 未登录账号的 credential（App `accountLogin` 既有路径：有账号记录但
    // credential 为空时会把空串注入进来）。空串不是合法 JSON，且会把上一次的
    // 有效 attrs 覆盖成空 —— 这里显式短路为 Ok（语义：清空注入）。
    if data.trim().is_empty() {
        return Ok(());
    }

    let parsed: Value = serde_json::from_str(data)
        .map_err(|e| SliveError::invalid_input(format!("setSiteAttrs 非法 JSON: {e}")))?;
    let Some(map) = as_object(Some(&parsed)) else {
        return Err(SliveError::invalid_input(
            "setSiteAttrs 需要 JSON 对象".to_string(),
        ));
    };

    // Dart：containsKey('cookie') 才处理；空串 = 移除
    if let Some(cookie) = map.get("cookie") {
        let value = match cookie {
            Value::String(s) => s.clone(),
            Value::Null => String::new(),
            other => crate::util::value_to_string(other),
        };
        site.set_cookie(&value);
    }
    if let Some(hls_first) = map.get("hlsFirst") {
        if let Some(flag) = crate::util::as_bool_lenient(Some(hls_first)) {
            site.set_hls_first(flag);
        }
    }
    Ok(())
}

/// 未校验的默认账号对象（`is_valid = false`）。
///
/// **必须回传入参 credential**：App 的 `accountLogin` 会把 `info.credential`
/// 原样写回账号库，回传空串会把用户已保存的 cookie 从数据库里抹掉（一次偶发
/// 失败就永久掉登录）。B站 / 斗鱼的未校验路径同样回传原值，这里对齐。
fn unverified(credential: &str) -> AccountInfo {
    AccountInfo {
        name: None,
        avatar: None,
        uid: None,
        credential: credential.to_string(),
        is_valid: false,
    }
}

/// 账号信息（`webcast/user/me/`）。
///
/// 空 credential / 非法 JSON 一律返回未校验对象而不抛错：App 启动时会对所有
/// 账号行跑一遍校验，抛错会变成没人接的异步异常（对齐 B站 / 斗鱼口径）。
pub(crate) async fn get_account_info(
    site: &DouyinSite,
    credential: &str,
) -> Result<AccountInfo, SliveError> {
    let cookie = match serde_json::from_str::<Value>(credential) {
        Ok(parsed) => parsed
            .get("cookie")
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        // 空串 = 未登录账号的 credential（App `accountLogin` 既有路径）；
        // 非法 JSON 同理，按未校验处理，不抛。
        Err(_) => String::new(),
    };

    // 未配 cookie -> 未校验的默认对象（Dart：直接 return AccountInfo()）
    if cookie.is_empty() {
        return Ok(unverified(credential));
    }

    let query = vec![("aid".to_string(), "6383".to_string())];
    match site
        .get_json(
            ACCOUNT_URL,
            query,
            super::header::account_headers(&cookie),
        )
        .await
    {
        Ok(value) => Ok(parse_account(&value, credential)),
        // Dart：请求异常只记日志、返回未校验对象（不让账号页整体崩）
        Err(e) => {
            log::warn!("抖音账号信息查询失败（按未校验处理）: {e}");
            Ok(unverified(credential))
        }
    }
}

/// 从 `webcast/user/me/` 响应组装 [`AccountInfo`]。
///
/// 字段映射对照 Dart `DouyinUserInfoModel.fromJson`：
/// `nickname -> name`、`id_str -> uid`、`avatar_thumb.url_list[0] -> avatar`；
/// 响应结构不符时返回未校验对象（与 Dart 的 `if (result is Map) {...}` 静默路径一致）。
fn parse_account(value: &Value, credential: &str) -> AccountInfo {
    let Some(data) = as_object(value.get("data")) else {
        return unverified(credential);
    };
    AccountInfo {
        name: data
            .get("nickname")
            .and_then(Value::as_str)
            .map(str::to_string),
        avatar: non_empty(super::util::first_url(data.get("avatar_thumb"))),
        uid: data
            .get("id_str")
            .map(crate::util::value_to_string)
            .filter(|s| !s.is_empty()),
        credential: credential.to_string(),
        is_valid: true,
    }
}

/// 空串 -> `None`（避免把 `""` 当成有效头像/UID 显示在 UI 上）。
fn non_empty(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn set_site_attrs_tolerates_empty_credential() {
        // 未登录账号的 credential 是空串（App accountLogin 既有路径）：
        // 不得报错，也不得把已有 attrs 清空。
        let site = DouyinSite::new();
        assert!(super::set_site_attrs(&site, "").is_ok());
        assert!(super::set_site_attrs(&site, "   ").is_ok());
    }

    use super::*;
    use serde_json::json;

    #[test]
    fn set_site_attrs_requires_json_object() {
        let site = DouyinSite::new();
        assert!(matches!(
            set_site_attrs(&site, "not json"),
            Err(SliveError::InvalidInput(_))
        ));
        assert!(matches!(
            set_site_attrs(&site, "[1,2]"),
            Err(SliveError::InvalidInput(_))
        ));
    }

    #[test]
    fn set_site_attrs_applies_cookie_and_hls_first() {
        let site = DouyinSite::new();
        set_site_attrs(&site, r#"{"cookie":"a=1","hlsFirst":true}"#).expect("应成功");
        assert!(site.hls_first());
        assert!(site.header_cookie().contains("a=1"));
    }

    #[test]
    fn set_site_attrs_ignores_absent_keys() {
        let site = DouyinSite::new();
        site.set_cookie("keep=1");
        site.set_hls_first(true);
        set_site_attrs(&site, r#"{}"#).expect("应成功");
        assert_eq!(site.header_cookie(), "keep=1", "缺 cookie 键应保留旧值（Dart 同口径）");
        assert!(site.hls_first(), "缺 hlsFirst 键应保留旧值");
    }

    #[test]
    fn set_site_attrs_empty_cookie_removes_it() {
        let site = DouyinSite::new();
        set_site_attrs(&site, r#"{"cookie":"a=1"}"#).expect("应成功");
        set_site_attrs(&site, r#"{"cookie":""}"#).expect("应成功");
        assert_eq!(site.header_cookie(), "");
    }

    #[tokio::test]
    async fn account_info_without_cookie_returns_unverified() {
        let site = DouyinSite::new();
        let info = get_account_info(&site, r#"{"cookie":""}"#)
            .await
            .expect("不应报错");
        assert!(!info.is_valid, "没配 cookie -> 未校验");
        assert!(info.name.is_none());
        assert_eq!(
            info.credential, r#"{"cookie":""}"#,
            "未校验必须回传入参 credential，否则 App 写回时会把已存 cookie 抹掉"
        );
    }

    #[tokio::test]
    async fn account_info_empty_credential_returns_unverified() {
        // App 启动会对所有账号行跑校验，空 credential（未登录）不能抛错
        let site = DouyinSite::new();
        let info = get_account_info(&site, "").await.expect("空串不应抛");
        assert!(!info.is_valid);
        assert_eq!(info.credential, "");
    }

    #[tokio::test]
    async fn account_info_malformed_credential_returns_unverified() {
        let site = DouyinSite::new();
        let info = get_account_info(&site, "not json")
            .await
            .expect("非法 JSON 按未校验处理，不抛");
        assert!(!info.is_valid);
        assert_eq!(info.credential, "not json", "原样回传，避免抹掉用户数据");
    }

    #[test]
    fn parse_account_maps_dart_user_info_fields() {
        let value = json!({"data": {
            "id_str": "1234567890",
            "nickname": "测试用户",
            "short_id": "123",
            "sign": "签名",
            "birthday": "1990-01-01",
            "gender": "1",
            "avatar_thumb": {"url_list": ["https://a", "https://b"]},
        }});
        let info = parse_account(&value, r#"{"cookie":"a=1"}"#);
        assert!(info.is_valid);
        assert_eq!(info.name.as_deref(), Some("测试用户"));
        assert_eq!(info.uid.as_deref(), Some("1234567890"));
        assert_eq!(info.avatar.as_deref(), Some("https://a"));
        assert_eq!(info.credential, r#"{"cookie":"a=1"}"#);
    }

    #[test]
    fn parse_account_degrades_on_unexpected_shape() {
        let info = parse_account(&json!({}), "{}");
        assert!(!info.is_valid, "缺 data -> 未校验");
        let info = parse_account(&json!({"data": "not-object"}), "{}");
        assert!(!info.is_valid);
        // 空串字段不应作为有效值回传
        let info = parse_account(&json!({"data": {"nickname": "n", "id_str": "", "avatar_thumb": {}}}), "{}");
        assert!(info.is_valid);
        assert!(info.uid.is_none(), "空 id_str -> None");
        assert!(info.avatar.is_none(), "缺 url_list -> None");
    }

    #[test]
    fn account_error_messages_never_leak_cookie() {
        let site = DouyinSite::new();
        let err = set_site_attrs(&site, "{").expect_err("应报错");
        let msg = err.to_string();
        assert!(!msg.contains("ttwid"), "错误消息不得含 cookie：{msg}");
    }
}
