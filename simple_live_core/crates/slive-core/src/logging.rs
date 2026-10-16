//! 日志辅助 + 敏感信息脱敏（AC-40）。
//!
//! 规则（对齐 `docs/rust-core/13-spec.md §9` 安全项）：credential / cookie **禁止**写入日志
//! （`bilibili_site.dart:598` 的 `CoreLog.i(cookieStr)` 行为在 Rust 侧**不得**复刻）。
//! 本模块提供安全的日志入口，凡是与凭证相关的日志一律走 [`redact_secret`] / [`presence`]。

/// 将敏感串替换为不含明文的占位符（保留长度摘要，便于排障）。
///
/// ```
/// # use slive_core::logging::redact_secret;
/// assert_eq!(redact_secret(""), "<empty>");
/// assert_eq!(redact_secret("SESSDATA=abc"), "<redacted:12>");
/// ```
pub fn redact_secret(value: &str) -> String {
    if value.is_empty() {
        "<empty>".to_string()
    } else {
        format!("<redacted:{}>", value.len())
    }
}

/// 描述凭证是否存在，不含任何明文。
pub fn presence(value: &str) -> &'static str {
    if value.is_empty() {
        "absent"
    } else {
        "present"
    }
}

/// 记录一次凭证注入动作（**只记录存在性，不记录明文**）。
pub fn log_credential_injected(kind: &str, value: &str) {
    log::debug!("注入 {kind}: {}", presence(value));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redact_never_leaks_plaintext() {
        let secret = "SESSDATA=deadbeef";
        let masked = redact_secret(secret);
        assert!(
            !masked.contains("SESSDATA"),
            "脱敏结果不得含明文，实际 {masked}"
        );
    }
}
