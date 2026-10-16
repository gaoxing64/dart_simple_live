//! 斗鱼专属 **POST form-urlencoded** seam。
//!
//! 背景：斗鱼取流（`lapi/live/getH5PlayV1`）与二维码（`passport/scan/generateCode`）都是
//! POST 表单，而共享的 `HttpTransport` 只暴露 `get`（B站全 GET）。为避免在多平台并行期间
//! 改动共享 `http.rs`，这里在斗鱼模块内自建一条**向下依赖**的 POST 通道：
//! - 生产：[`ReqwestDouyuPost`]（复用 `crate::http::build_client` 的共享 rustls Client 配置）
//! - 测试：[`MockDouyuPost`]（按 URL 子串返回夹具 + 记录请求，供离线用例断言）
//!
//! 纪律：**不自动重试**（业务错误码由上层判定并抛错，见 `docs/rust-core/13-spec.md` §9）。

use std::sync::Mutex;

use async_trait::async_trait;

use crate::error::SliveError;
use crate::http::{build_client, HttpReply};

/// 表单 POST 的响应体上限（错误体截断，防止把整页 HTML 塞进错误消息）。
const ERROR_BODY_CAP: usize = 512;

/// 一次 POST form-urlencoded 请求描述。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PostRequest {
    /// 目标 URL（query 由调用方拼进 `body`，与 Dart `postJson(data:)` 一致）。
    pub url: String,
    /// 表单体（`a=1&b=2`，已 URL 编码）。
    pub body: String,
    /// 请求头（顺序保留）。
    pub headers: Vec<(String, String)>,
}

/// 斗鱼 POST 通道抽象（seam）。
#[async_trait]
pub trait DouyuPost: Send + Sync {
    /// 发送一次表单 POST。
    async fn post_form(&self, request: &PostRequest) -> Result<HttpReply, SliveError>;
}

/// 生产实现：`reqwest` + rustls（复用共享 Client 构造，保持与 GET 通道同 TLS/超时口径）。
pub struct ReqwestDouyuPost {
    client: reqwest::Client,
}

impl ReqwestDouyuPost {
    /// 生产构造。
    pub fn new() -> Self {
        Self {
            client: build_client(),
        }
    }
}

impl Default for ReqwestDouyuPost {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl DouyuPost for ReqwestDouyuPost {
    async fn post_form(&self, request: &PostRequest) -> Result<HttpReply, SliveError> {
        let mut builder = self
            .client
            .post(&request.url)
            .header("content-type", "application/x-www-form-urlencoded");
        for (key, value) in &request.headers {
            builder = builder.header(key.as_str(), value.as_str());
        }
        let response = builder
            .body(request.body.clone())
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

/// 可克隆的 mock 响应规格（[`SliveError`] 不可克隆，故用规格枚举 + 现场构造）。
#[derive(Debug, Clone)]
enum StubResponse {
    /// 200 + 文本。
    Text(String, Vec<String>),
    /// HTTP 错误。
    Http(u16),
    /// 传输层失败。
    Network(String),
}

/// 可脚本化的 mock POST 通道：按 URL 子串匹配，**记录全部请求**。
///
/// 定位对齐 `crate::testing::MockTransport`（测试侧 seam 实现），放在斗鱼模块内是为了
/// 不改动共享 `testing.rs`（多平台并行期间共享文件由总监统一接线）。
pub struct MockDouyuPost {
    stubs: Mutex<Vec<(String, StubResponse)>>,
    requests: Mutex<Vec<PostRequest>>,
}

impl Default for MockDouyuPost {
    fn default() -> Self {
        Self::new()
    }
}

impl MockDouyuPost {
    /// 新建。
    pub fn new() -> Self {
        Self {
            stubs: Mutex::new(Vec::new()),
            requests: Mutex::new(Vec::new()),
        }
    }

    /// 注册一条 200 + 文本响应夹具（`key` 为 URL 子串）。
    pub fn stub(&self, key: &str, body: &str) {
        self.push(key, StubResponse::Text(body.to_string(), Vec::new()));
    }

    /// 注册一条 200 + 文本 + `set-cookie` 夹具。
    pub fn stub_with_cookie(&self, key: &str, body: &str, set_cookie: Vec<String>) {
        self.push(
            key,
            StubResponse::Text(body.to_string(), set_cookie),
        );
    }

    /// 注册一条 HTTP 错误夹具。
    pub fn stub_http_error(&self, key: &str, status: u16) {
        self.push(key, StubResponse::Http(status));
    }

    /// 注册一条传输层失败夹具。
    pub fn stub_network_error(&self, key: &str, message: &str) {
        self.push(key, StubResponse::Network(message.to_string()));
    }

    fn push(&self, key: &str, response: StubResponse) {
        self.stubs
            .lock()
            .expect("stubs poisoned")
            .push((key.to_string(), response));
    }

    /// 已记录的全部请求（克隆）。
    pub fn requests(&self) -> Vec<PostRequest> {
        self.requests.lock().expect("requests poisoned").clone()
    }

    /// 命中 `key` 的请求次数（无重试断言）。
    pub fn request_count(&self, key: &str) -> usize {
        self.requests
            .lock()
            .expect("requests poisoned")
            .iter()
            .filter(|r| r.url.contains(key))
            .count()
    }
}

fn reply(body: &str, set_cookie: Vec<String>) -> HttpReply {
    HttpReply {
        status: 200,
        text: body.to_string(),
        set_cookie,
    }
}

#[async_trait]
impl DouyuPost for MockDouyuPost {
    async fn post_form(&self, request: &PostRequest) -> Result<HttpReply, SliveError> {
        self.requests
            .lock()
            .expect("requests poisoned")
            .push(request.clone());
        let matched = {
            let stubs = self.stubs.lock().expect("stubs poisoned");
            stubs
                .iter()
                .find(|(key, _)| request.url.contains(key.as_str()))
                .map(|(_, response)| response.clone())
        };
        match matched {
            None => Err(SliveError::network(format!(
                "MockDouyuPost 未注册 URL: {}",
                request.url
            ))),
            Some(StubResponse::Text(body, set_cookie)) => Ok(reply(&body, set_cookie)),
            Some(StubResponse::Http(status)) => Err(SliveError::Http {
                status,
                body: String::new(),
            }),
            Some(StubResponse::Network(message)) => Err(SliveError::network(message)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mock_records_requests_and_returns_stub() {
        let mock = MockDouyuPost::new();
        mock.stub("getH5PlayV1", r#"{"error":0,"data":{}}"#);
        let request = PostRequest {
            url: "https://www.douyu.com/lapi/live/getH5PlayV1/999".to_string(),
            body: "rate=0".to_string(),
            headers: vec![("referer".to_string(), "https://www.douyu.com/999".to_string())],
        };
        let got = mock.post_form(&request).await.expect("命中夹具");
        assert_eq!(got.status, 200);
        assert!(!got.text.contains("getH5PlayV1"), "回显的是夹具内容");
        assert_eq!(mock.request_count("getH5PlayV1"), 1);
        assert_eq!(mock.requests()[0].body, "rate=0");
    }

    #[tokio::test]
    async fn mock_unregistered_url_is_network_error() {
        let mock = MockDouyuPost::new();
        let err = mock
            .post_form(&PostRequest {
                url: "https://www.douyu.com/x".to_string(),
                body: String::new(),
                headers: vec![],
            })
            .await
            .expect_err("未注册必须报错");
        assert!(matches!(err, SliveError::Network(_)), "实际 {err:?}");
    }

    #[test]
    fn truncate_caps_error_body() {
        assert_eq!(truncate("abc"), "abc");
        assert_eq!(truncate(&"x".repeat(600)).chars().count(), ERROR_BODY_CAP);
    }
}