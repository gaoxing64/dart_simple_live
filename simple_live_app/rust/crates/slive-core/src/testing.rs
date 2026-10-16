//! 测试支撑（注入用的 fake / mock 实现）。
//!
//! 本模块是三个 seam 的测试侧落点：
//! - [`MockTransport`]：按 URL 子串返回夹具，并**记录每次请求**（URL/query/headers）——AC-25「请求次数==1」断言基础；
//! - [`FakeTime`]：确定性时间源（wbi `wts` / 重连时序）；
//! - [`ScriptedFrameSource`]：预置帧序列事件源（IP-2 弹幕链路的注入点）。
//!
//! 生产路径不依赖本模块；仅测试与前端（Tauri 等）集成时可复用。

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use async_trait::async_trait;

use crate::error::SliveError;
use crate::http::{HttpReply, HttpRequest, HttpTransport};
use crate::time::TimeSource;
use crate::ws::FrameSource;

/// 可脚本化的 mock 响应。
#[derive(Debug, Clone)]
pub enum MockResponse {
    /// 200 + JSON 文本。
    Json(String),
    /// 200 + JSON 文本 + `set-cookie`。
    JsonWithCookie(String, Vec<String>),
    /// HTTP 错误状态。
    HttpError { status: u16, body: String },
    /// 传输层失败。
    Network(String),
}

struct Stub {
    key: String,
    response: MockResponse,
}

/// 按 URL 子串匹配夹具，并记录请求的 mock 传输。
pub struct MockTransport {
    stubs: Mutex<Vec<Stub>>,
    requests: Mutex<Vec<HttpRequest>>,
}

impl Default for MockTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl MockTransport {
    /// 新建。
    pub fn new() -> Self {
        Self {
            stubs: Mutex::new(Vec::new()),
            requests: Mutex::new(Vec::new()),
        }
    }

    /// 注册一条 200 + JSON 夹具（`key` 为 URL 子串）。
    pub fn stub(&self, key: &str, body: &str) {
        self.push(key, MockResponse::Json(body.to_string()));
    }

    /// 注册一条带 `set-cookie` 的 200 + JSON 夹具。
    pub fn stub_with_cookie(&self, key: &str, body: &str, set_cookie: Vec<String>) {
        self.push(key, MockResponse::JsonWithCookie(body.to_string(), set_cookie));
    }

    /// 注册一条 HTTP 错误夹具。
    pub fn stub_http_error(&self, key: &str, status: u16) {
        self.push(
            key,
            MockResponse::HttpError {
                status,
                body: String::new(),
            },
        );
    }

    /// 注册一条传输层失败夹具。
    pub fn stub_network_error(&self, key: &str, message: &str) {
        self.push(key, MockResponse::Network(message.to_string()));
    }

    fn push(&self, key: &str, response: MockResponse) {
        self.stubs.lock().expect("stubs poisoned").push(Stub {
            key: key.to_string(),
            response,
        });
    }

    /// 已记录的全部请求（克隆）。
    pub fn requests(&self) -> Vec<HttpRequest> {
        self.requests.lock().expect("requests poisoned").clone()
    }

    /// 命中 `key` 的请求次数（AC-25 无重试断言）。
    pub fn request_count(&self, key: &str) -> usize {
        self.requests
            .lock()
            .expect("requests poisoned")
            .iter()
            .filter(|r| r.url.contains(key))
            .count()
    }

    /// 记录到的请求 URL 集合（含 query 摘要）。
    pub fn request_urls(&self) -> Vec<String> {
        self.requests
            .lock()
            .expect("requests poisoned")
            .iter()
            .map(|r| {
                let query = r
                    .query
                    .iter()
                    .map(|(k, v)| format!("{k}={v}"))
                    .collect::<Vec<_>>()
                    .join("&");
                if query.is_empty() {
                    r.url.clone()
                } else {
                    format!("{}?{}", r.url, query)
                }
            })
            .collect()
    }
}

#[async_trait]
impl HttpTransport for MockTransport {
    async fn get(&self, request: &HttpRequest) -> Result<HttpReply, SliveError> {
        self.requests
            .lock()
            .expect("requests poisoned")
            .push(request.clone());

        let matched = {
            let stubs = self.stubs.lock().expect("stubs poisoned");
            stubs
                .iter()
                .find(|s| request.url.contains(&s.key))
                .map(|s| s.response.clone())
        };

        match matched {
            None => Err(SliveError::network(format!(
                "MockTransport 未注册 URL: {}",
                request.url
            ))),
            Some(MockResponse::Json(text)) => Ok(HttpReply {
                status: 200,
                text,
                set_cookie: vec![],
            }),
            Some(MockResponse::JsonWithCookie(text, set_cookie)) => Ok(HttpReply {
                status: 200,
                text,
                set_cookie,
            }),
            Some(MockResponse::HttpError { status, body }) => Err(SliveError::Http { status, body }),
            Some(MockResponse::Network(message)) => Err(SliveError::Network(message)),
        }
    }
}

/// 兼容别名（骨架期命名）。
pub type RecordingTransport = MockTransport;

/// 确定性时间源。
#[derive(Debug, Default)]
pub struct FakeTime {
    secs: AtomicU64,
}

impl FakeTime {
    /// 从固定秒数开始。
    pub fn new(secs: u64) -> Self {
        Self {
            secs: AtomicU64::new(secs),
        }
    }

    /// 设置当前秒数。
    pub fn set(&self, secs: u64) {
        self.secs.store(secs, Ordering::SeqCst);
    }

    /// 前进若干秒。
    pub fn advance(&self, delta_secs: u64) {
        self.secs.fetch_add(delta_secs, Ordering::SeqCst);
    }
}

#[async_trait]
impl TimeSource for FakeTime {
    fn unix_secs(&self) -> u64 {
        self.secs.load(Ordering::SeqCst)
    }

    // 测试实现：立即返回，重连时序由断言计数而非墙钟驱动（AC-26 抗 flaky）。
    async fn sleep(&self, _secs: u64) {}
}

/// 预置帧序列（或错误）的事件源，并记录所有已发送帧（供 join/心跳断言）。
pub struct ScriptedFrameSource {
    frames: VecDeque<Result<Vec<u8>, String>>,
    sent: Vec<Vec<u8>>,
}

impl ScriptedFrameSource {
    /// 由帧序列构造。
    pub fn new(frames: Vec<Vec<u8>>) -> Self {
        Self {
            frames: frames.into_iter().map(Ok).collect(),
            sent: Vec::new(),
        }
    }

    /// 追加一帧错误。
    pub fn push_error(&mut self, message: &str) {
        self.frames.push_back(Err(message.to_string()));
    }

    /// 追加一帧。
    pub fn push_frame(&mut self, frame: Vec<u8>) {
        self.frames.push_back(Ok(frame));
    }

    /// 已发送的帧（join / 心跳断言用）。
    pub fn sent_frames(&self) -> &[Vec<u8>] {
        &self.sent
    }
}

#[async_trait]
impl FrameSource for ScriptedFrameSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        self.frames
            .pop_front()
            .map(|r| r.map_err(SliveError::Websocket))
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        self.sent.push(frame);
        Ok(())
    }
}

pub mod capture;

pub use capture::CaptureLogger;
