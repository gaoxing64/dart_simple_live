//! HTTP 传输层：`HttpTransport` 抽象（seam）+ `ReqwestTransport` 生产实现。
//!
//! 设计要点（见 `docs/rust-core/10-architecture.md §6.2 / §8.1`）：
//! - 复用单个 `reqwest::Client`（连接池 / keep-alive），差异化请求头按请求携带；
//! - 统一 rustls（纯 Rust），`.http1_only()` + `.no_proxy()` + 连接/请求超时；
//! - **不对业务错误码自动重试**（AC-25）；传输层亦不重试（保持与 Dart core 同路径的请求数）。

use std::time::Duration;

use async_trait::async_trait;
use serde_json::Value;

use crate::error::SliveError;

/// 默认 User-Agent（对齐 Dart `BiliBiliSite.kDefaultUserAgent`）。
pub const DEFAULT_USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0";
/// 默认 Referer（对齐 Dart `BiliBiliSite.kDefaultReferer`）。
pub const DEFAULT_REFERER: &str = "https://live.bilibili.com/";
/// 取流 headers 的 Referer（对齐 Dart `getPlayUrls`）。
pub const PLAY_REFERER: &str = "https://live.bilibili.com";
/// 取流 headers 的 User-Agent（对齐 Dart `getPlayUrls`）。
pub const PLAY_USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36 Edg/115.0.1901.188";

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);
const ERROR_BODY_CAP: usize = 512;

/// 一次 GET 请求描述（URL + query + 差异头）。MockTransport 依此记录与匹配。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpRequest {
    /// 不含 query 的基准 URL。
    pub url: String,
    /// query 参数（顺序保留）。
    pub query: Vec<(String, String)>,
    /// 请求头（顺序保留）。
    pub headers: Vec<(String, String)>,
}

/// 一次 GET 响应。
#[derive(Debug, Clone)]
pub struct HttpReply {
    /// HTTP 状态码。
    pub status: u16,
    /// 响应体文本。
    pub text: String,
    /// `set-cookie` 响应头（QR 轮询汇总 credential 需要）。
    pub set_cookie: Vec<String>,
}

impl HttpReply {
    /// 解析响应体为 JSON（非法 JSON -> `SliveError::Decode`）。
    pub fn json(&self) -> Result<Value, SliveError> {
        serde_json::from_str(&self.text)
            .map_err(|e| SliveError::decode(format!("解析 JSON 失败: {e}")))
    }
}

/// 校验服务端业务错误码：存在且 `code != 0` -> `SliveError::Api`（AC-25，不静默返回空）。
pub fn check_api_code(value: &Value) -> Result<(), SliveError> {
    let Some(code) = value.get("code").and_then(Value::as_i64) else {
        return Ok(());
    };
    if code == 0 {
        return Ok(());
    }
    let message = value
        .get("message")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    Err(SliveError::Api {
        code: code as i32,
        message,
    })
}

/// HTTP 传输抽象（seam）。
#[async_trait]
pub trait HttpTransport: Send + Sync {
    /// 发送一次 GET 请求。
    async fn get(&self, request: &HttpRequest) -> Result<HttpReply, SliveError>;
}

/// 生产实现：`reqwest` + rustls，复用单个 Client。
pub struct ReqwestTransport {
    client: reqwest::Client,
}

/// 构造共享 `reqwest::Client`（ADR-003 / §6.2）。
pub fn build_client() -> reqwest::Client {
    reqwest::Client::builder()
        .http1_only()
        .no_proxy()
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
        .build()
        .unwrap_or_default()
}

impl ReqwestTransport {
    /// 生产构造。
    pub fn new() -> Self {
        Self {
            client: build_client(),
        }
    }
}

impl Default for ReqwestTransport {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl HttpTransport for ReqwestTransport {
    async fn get(&self, request: &HttpRequest) -> Result<HttpReply, SliveError> {
        let mut url = reqwest::Url::parse(&request.url)
            .map_err(|e| SliveError::invalid_input(format!("非法 URL({}): {e}", request.url)))?;
        if !request.query.is_empty() {
            let mut pairs = url.query_pairs_mut();
            for (key, value) in &request.query {
                pairs.append_pair(key, value);
            }
        }

        let mut builder = self.client.get(url);
        for (key, value) in &request.headers {
            builder = builder.header(key.as_str(), value.as_str());
        }

        let response = builder
            .send()
            .await
            .map_err(|e| SliveError::network(e.to_string()))?;

        let status = response.status().as_u16();
        let set_cookie = response
            .headers()
            .get_all(reqwest::header::SET_COOKIE)
            .iter()
            .filter_map(|v| v.to_str().ok())
            .map(str::to_string)
            .collect();
        let text = response
            .text()
            .await
            .map_err(|e| SliveError::network(format!("读取响应体失败: {e}")))?;

        if !(200..400).contains(&status) {
            return Err(SliveError::Http {
                status,
                body: truncate(&text),
            });
        }
        Ok(HttpReply {
            status,
            text,
            set_cookie,
        })
    }
}

fn truncate(body: &str) -> String {
    if body.chars().count() <= ERROR_BODY_CAP {
        body.to_string()
    } else {
        body.chars().take(ERROR_BODY_CAP).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn check_api_code_passes_zero_and_missing() {
        assert!(check_api_code(&json!({"code": 0})).is_ok());
        assert!(check_api_code(&json!({"data": []})).is_ok());
    }

    #[test]
    fn check_api_code_maps_business_error() {
        let err = check_api_code(&json!({"code": -352, "message": "风控"}))
            .expect_err("code!=0 必须报错");
        match err {
            SliveError::Api { code, message } => {
                assert_eq!(code, -352, "错误码应原样带出");
                assert_eq!(message, "风控");
            }
            other => panic!("期望 SliveError::Api，实际 {other:?}"),
        }
    }

    #[test]
    fn reply_json_reports_decode_error() {
        let reply = HttpReply {
            status: 200,
            text: "not json".to_string(),
            set_cookie: vec![],
        };
        assert!(matches!(reply.json(), Err(SliveError::Decode(_))));
    }
}
