//! 统一错误模型（对照 `docs/rust-core/10-architecture.md §7`）。
//!
//! 两层：
//! - [`SliveError`]（thiserror）：core 层错误，`platforms` 层方法统一返回它，**可枚举匹配**（AC-17/AC-23/AC-25 断言依据）。
//! - [`CoreError`]：FRB 可见的强类型错误 `{message, status_code}`；由 [`From<SliveError>`] 映射，
//!   供桥层还原 Dart `simple_live_core::CoreError`（两路径收敛到同一异常类型）。

use std::fmt;

/// core 层错误。`platforms` 层所有方法返回 `Result<T, SliveError>`。
#[derive(Debug, thiserror::Error)]
pub enum SliveError {
    /// 网络层失败（连接失败 / 超时 / DNS 等）。
    #[error("网络请求失败: {0}")]
    Network(String),
    /// 非 2xx/3xx 的 HTTP 响应。
    #[error("HTTP 响应异常({status})")]
    Http { status: u16, body: String },
    /// 服务端业务错误码（`code != 0`），如风控 `-352`。**不自动重试**（AC-25）。
    #[error("接口返回错误码 {code}: {message}")]
    Api { code: i32, message: String },
    /// 数据解码失败（非法 JSON / 字段缺失 / 版本不符）。
    #[error("数据解码失败: {0}")]
    Decode(String),
    /// WebSocket 相关错误。
    #[error("WebSocket 错误: {0}")]
    Websocket(String),
    /// 资源不存在。
    #[error("资源不存在: {0}")]
    NotFound(String),
    /// 入参非法（如 `setSiteAttrs` 非 JSON，AC-17）。
    #[error("入参非法: {0}")]
    InvalidInput(String),
}

impl SliveError {
    /// 构造网络错误。
    pub fn network(msg: impl Into<String>) -> Self {
        Self::Network(msg.into())
    }
    /// 构造解码错误。
    pub fn decode(msg: impl Into<String>) -> Self {
        Self::Decode(msg.into())
    }
    /// 构造入参错误。
    pub fn invalid_input(msg: impl Into<String>) -> Self {
        Self::InvalidInput(msg.into())
    }
    /// 构造资源不存在错误。
    pub fn not_found(msg: impl Into<String>) -> Self {
        Self::NotFound(msg.into())
    }
}

/// HTTP 状态码 -> 文案（对齐全 `simple_live_core/lib/src/common/core_error.dart`）。
pub fn status_code_to_string(status: u16) -> String {
    match status {
        400 => "错误的请求(400)".to_string(),
        401 => "无权限访问资源(401)".to_string(),
        403 => "无权限访问资源(403)".to_string(),
        404 => "服务器找不到请求的资源(404)".to_string(),
        500 => "服务器出现错误(500)".to_string(),
        502 => "服务器出现错误(502)".to_string(),
        503 => "服务器出现错误(503)".to_string(),
        other => format!("连接服务器失败，请稍后再试({other})"),
    }
}

/// FRB 可见的强类型错误（桥层映射目标）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreError {
    /// 错误信息（业务错误为服务端原文，如风控 message）。
    pub message: String,
    /// 错误码（HTTP 状态码或业务 `code`；无则为 0）。
    pub status_code: i32,
}

impl CoreError {
    /// 构造。
    pub fn new(message: impl Into<String>, status_code: i32) -> Self {
        Self {
            message: message.into(),
            status_code,
        }
    }
}

impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.status_code != 0 {
            write!(f, "{}", status_code_to_string(self.status_code as u16))
        } else {
            write!(f, "{}", self.message)
        }
    }
}

impl From<SliveError> for CoreError {
    fn from(err: SliveError) -> Self {
        match err {
            SliveError::Http { status, .. } => Self {
                message: status_code_to_string(status),
                status_code: status as i32,
            },
            // 业务错误码原样带出 message（AC-25）。
            SliveError::Api { code, message } => Self {
                message,
                status_code: code,
            },
            SliveError::Network(msg) => Self {
                message: if msg.is_empty() {
                    "发送GET请求失败".to_string()
                } else {
                    format!("发送GET请求失败: {msg}")
                },
                status_code: 0,
            },
            SliveError::Decode(msg)
            | SliveError::Websocket(msg)
            | SliveError::NotFound(msg)
            | SliveError::InvalidInput(msg) => Self {
                message: msg,
                status_code: 0,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_error_keeps_server_message_and_code() {
        let err = SliveError::Api {
            code: -352,
            message: "风控校验失败".to_string(),
        };
        let mapped: CoreError = err.into();
        assert_eq!(
            mapped.status_code, -352,
            "业务错误码必须原样带出，实际 {}",
            mapped.status_code
        );
        assert_eq!(mapped.message, "风控校验失败");
    }

    #[test]
    fn http_error_uses_status_code_text() {
        let err = SliveError::Http {
            status: 404,
            body: "x".to_string(),
        };
        let mapped: CoreError = err.into();
        assert_eq!(mapped.status_code, 404);
        assert_eq!(mapped.message, "服务器找不到请求的资源(404)");
    }
}
