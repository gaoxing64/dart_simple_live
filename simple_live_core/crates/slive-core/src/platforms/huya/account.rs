//! F-17 凭证注入（对照 `huya_site.dart:558-564`）。
//!
//! 虎牙的 `setSiteAttrs` **只认 `ua` 键**：命中则替换 SDK UA（影响后续所有请求头），
//! 未命中则**保留旧值**（对齐 J-5：缺键保留旧值，不置空）。
//!
//! 安全（AC-40）：UA 非凭证，但本函数**不得**打印输入串全文（可能被塞进 cookie）；
//! 只记录「键是否存在」。

use crate::error::SliveError;
use crate::logging;

use super::site::HuyaSite;

/// F-17 注入凭证（同步）。
pub(crate) fn set_site_attrs(site: &HuyaSite, data: &str) -> Result<(), SliveError> {
    // 空串 = 未登录账号的 credential（App `accountLogin` 既有路径：有账号记录但
    // credential 为空时会把空串注入进来）。空串不是合法 JSON，且会把上一次的
    // 有效 attrs 覆盖成空 —— 这里显式短路为 Ok（语义：清空注入）。
    if data.trim().is_empty() {
        return Ok(());
    }

    let value: serde_json::Value = serde_json::from_str(data)
        .map_err(|e| SliveError::invalid_input(format!("setSiteAttrs 非合法 JSON: {e}")))?;
    let Some(map) = value.as_object() else {
        return Err(SliveError::invalid_input(
            "setSiteAttrs 要求 JSON 对象",
        ));
    };

    match map.get("ua") {
        Some(serde_json::Value::String(ua)) => {
            site.set_hysdk_ua(ua);
            logging::log_credential_injected("huya-ua", ua);
            Ok(())
        }
        Some(other) => Err(SliveError::invalid_input(format!(
            "setSiteAttrs 的 ua 必须是字符串，实际 {}",
            type_name(other)
        ))),
        // 缺键：保留旧 UA（Dart 口径）
        None => {
            logging::log_credential_injected("huya-ua", "");
            Ok(())
        }
    }
}

/// JSON 值的类型名（诊断用，避免把值本身写进错误消息）。
fn type_name(value: &serde_json::Value) -> &'static str {
    match value {
        serde_json::Value::Null => "null",
        serde_json::Value::Bool(_) => "bool",
        serde_json::Value::Number(_) => "number",
        serde_json::Value::String(_) => "string",
        serde_json::Value::Array(_) => "array",
        serde_json::Value::Object(_) => "object",
    }
}

/// 构造「平台未实现」错误（口径对齐 Dart `UnimplementedError`，映射为 `InvalidInput`）。
pub(crate) fn unsupported(what: &str) -> SliveError {
    SliveError::invalid_input(format!("{what}（Dart core 亦未实现）"))
}

/// 未注入 TUP 传输时的占位实现（只在 `with_get_deps` 构造下可达）。
///
/// 存在的意义：让「只测 GET 链路」的用例不必造一个 POST mock；
/// 真的调用 TUP 接口时立刻返回明确错误，而不是 panic 或静默成功。
pub(crate) struct UnavailablePost;

#[async_trait::async_trait]
impl crate::platforms::huya::tup::PostBytesTransport for UnavailablePost {
    async fn post_bytes(
        &self,
        _request: &crate::platforms::huya::tup::PostBytesRequest,
    ) -> Result<crate::http::HttpReply, SliveError> {
        Err(SliveError::invalid_input(
            "该虎牙句柄未注入 TUP 传输（请用 with_deps 构造）",
        ))
    }
}

/// F-18 生成登录二维码。
///
/// Dart core 为 `throw UnimplementedError()`（虎牙无扫码登录）；
/// Rust 侧以类型化错误表达同一语义（不静默返回空，也不自行发明协议）。
pub(crate) async fn get_qr_code() -> Result<crate::models::QrCode, SliveError> {
    Err(unsupported("虎牙不支持二维码登录"))
}

/// F-19 扫码轮询（同上，Dart 未实现）。
pub(crate) async fn get_qr_poll_result(
    _qrcode_key: String,
) -> Result<crate::models::QrPollResult, SliveError> {
    Err(unsupported("虎牙不支持扫码轮询"))
}

/// F-20 账号信息（同上，Dart 未实现）。
pub(crate) async fn get_account_info(
    _credential: String,
) -> Result<crate::models::AccountInfo, SliveError> {
    Err(unsupported("虎牙不支持账号信息查询"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn set_site_attrs_tolerates_empty_credential() {
        let site = HuyaSite::new();
        assert!(super::set_site_attrs(&site, "").is_ok());
    }

    use super::*;
    use crate::testing::FakeTime;
    use crate::time::SystemClock;
    use std::sync::Arc;

    fn site() -> HuyaSite {
        HuyaSite::new()
    }

    #[test]
    fn ua_key_replaces_sdk_ua() {
        let site = site();
        set_site_attrs(&site, r#"{"ua":"MY-UA"}"#).expect("注入");
        assert_eq!(site.hysdk_ua(), "MY-UA");
        assert_eq!(site.request_headers()[2].1, "MY-UA");
    }

    #[test]
    fn missing_ua_key_keeps_old_value() {
        let site = site();
        let before = site.hysdk_ua();
        set_site_attrs(&site, r#"{"cookie":"x"}"#).expect("缺键不报错");
        assert_eq!(site.hysdk_ua(), before, "缺键保留旧值");
    }

    #[test]
    fn non_string_ua_is_invalid_input() {
        let site = site();
        let err = set_site_attrs(&site, r#"{"ua":123}"#).expect_err("类型错误");
        assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
    }

    #[test]
    fn malformed_json_is_invalid_input() {
        let site = site();
        let err = set_site_attrs(&site, "not json").expect_err("非法 JSON");
        assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
    }

    #[test]
    fn non_object_json_is_invalid_input() {
        let site = site();
        let err = set_site_attrs(&site, "[1,2]").expect_err("非对象");
        assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
    }

    #[test]
    fn error_message_never_contains_ua_value() {
        let site = site();
        let err = set_site_attrs(&site, r#"{"ua":["SESSDATA=secret"]}"#).expect_err("类型错误");
        let text = err.to_string();
        assert!(!text.contains("SESSDATA"), "错误消息不得含明文，实际 {text}");
        assert!(text.contains("array"), "只报类型，实际 {text}");
    }

    #[tokio::test]
    async fn injection_is_scoped_to_handle() {
        // 注入只影响当前句柄（Dart 是 static 全局；句柄级属行为不变，见 §10）
        let a = HuyaSite::with_get_deps(Arc::new(crate::testing::MockTransport::new()), Arc::new(FakeTime::new(0)));
        let b = HuyaSite::with_get_deps(Arc::new(crate::testing::MockTransport::new()), Arc::new(SystemClock));
        set_site_attrs(&a, r#"{"ua":"A-UA"}"#).expect("注入");
        assert_eq!(a.hysdk_ua(), "A-UA");
        assert_eq!(b.hysdk_ua(), super::super::common::DEFAULT_HYSDK_UA);
    }
}