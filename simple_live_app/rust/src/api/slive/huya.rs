//! F-11 虎牙弹幕会话桥：生产 WS 连接（tokio-tungstenite + rustls）注入核心 `run_session`。
//!
//! 与 B站桥（`crate::api::slive::danmaku`）**并列独立**：本文件只服务虎牙，
//! 不修改 B站的 `start_danmaku` / `stop_danmaku`（共享文件接线由总监统一处理）。
//!
//! 桥层只做连接装配与事件转发；URL / headers / 帧编解码 / 重连策略全部来自
//! `slive-core::platforms::huya`（AC-39）。

use std::sync::Arc;

use async_trait::async_trait;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::watch;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

use slive_core::error::SliveError;
use slive_core::platforms::huya::danmaku::{run_session, ConnectFactory, HuyaDanmakuArgs};
use slive_core::platforms::huya::HuyaSite;
use slive_core::time::SystemClock;
use slive_core::ws::{FrameSource, SessionTuning};

use crate::api::slive::error::CoreError;
use crate::api::slive::models::LiveDanmuItem;
use crate::frb_generated::StreamSink;

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// 生产 WS 帧事件源：包装 tokio-tungstenite 连接。
struct HuyaWsFrameSource {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for HuyaWsFrameSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match self.stream.next().await {
                None => return None,
                Some(Err(e)) => return Some(Err(SliveError::Websocket(e.to_string()))),
                Some(Ok(Message::Binary(data))) => return Some(Ok(data)),
                Some(Ok(Message::Close(_))) => return None,
                Some(Ok(_)) => continue, // Text / Ping / Pong 等忽略
            }
        }
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        self.stream
            .send(Message::Binary(frame))
            .await
            .map_err(|e| SliveError::Websocket(e.to_string()))
    }
}

/// 连接装配（URL / headers 来自核心契约）。
#[flutter_rust_bridge::frb(ignore)]
async fn connect_ws_frame_source(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    // 由 URI 生成完整 WS 握手（含 Sec-WebSocket-Key 等），再追加业务头
    let mut request = url
        .clone()
        .into_client_request()
        .map_err(|e| SliveError::Websocket(format!("非法 WS 地址: {e}")))?;
    for (key, value) in headers {
        let name = key
            .parse::<tokio_tungstenite::tungstenite::http::HeaderName>()
            .map_err(|e| SliveError::Websocket(format!("非法头名: {e}")))?;
        let value = value
            .parse::<tokio_tungstenite::tungstenite::http::HeaderValue>()
            .map_err(|e| SliveError::Websocket(format!("非法头值: {e}")))?;
        request.headers_mut().insert(name, value);
    }
    let (stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .map_err(|e| SliveError::Websocket(e.to_string()))?;
    Ok(Box::new(HuyaWsFrameSource { stream }))
}

/// 当前活跃虎牙弹幕会话的停止信号（单房间语义，与 Dart core `LiveDanmaku` 一致）。
fn active_huya_stop() -> &'static std::sync::Mutex<Option<watch::Sender<bool>>> {
    static CELL: std::sync::OnceLock<std::sync::Mutex<Option<watch::Sender<bool>>>> =
        std::sync::OnceLock::new();
    CELL.get_or_init(|| std::sync::Mutex::new(None))
}

/// 手动停止当前虎牙弹幕会话（全局单例；对齐 Dart `LiveDanmaku.stop()`）。
#[frb(sync)]
pub fn stop_huya_danmaku() {
    if let Some(stop_tx) = active_huya_stop().lock().expect("stop 锁").take() {
        let _ = stop_tx.send(true);
    }
}

/// 启动虎牙弹幕会话（F-11）。
///
/// `args_json` 是 [`HuyaDanmakuArgs`] 的 JSON 串（`danmaku_data` 通道）；解析失败 ->
/// `CoreError(Decode)`，对应 Dart 侧 `FormatException`（J-10）。
/// 同时启动新会话会**停止**旧会话（单房间语义）。
pub fn start_huya_danmaku(
    args_json: String,
    sink: StreamSink<LiveDanmuItem>,
) -> Result<(), CoreError> {
    let args = HuyaDanmakuArgs::from_json(&args_json).map_err(CoreError::from)?;
    let (stop_tx, stop_rx) = watch::channel(false);

    // 单房间语义：新会话顶掉旧会话
    {
        let mut active = active_huya_stop().lock().expect("stop 锁");
        if let Some(old) = active.take() {
            let _ = old.send(true);
        }
        *active = Some(stop_tx.clone());
    }

    // URL / headers 固定：提前计算，闭包只持有克隆
    let ws_url = slive_core::platforms::huya::common::WS_SERVER_URL.to_string();
    let ws_headers = ws_headers();

    let connect: ConnectFactory = Box::new(move || {
        let url = ws_url.clone();
        let headers = ws_headers.clone();
        Box::pin(async move { connect_ws_frame_source(url, headers).await })
    });

    // 醒目留言增量拉取：借一个独立句柄走 core 的 TUP 链路（core 不持有 HTTP 连接，
    // 故此处注入生产传输；SC 拉取失败返回空列表，不影响弹幕主循环 —— 对齐 Dart 的 try/catch）。
    let sc_site = Arc::new(HuyaSite::new());
    let fetch_super_chat = Arc::new(move |pid: i64| {
        let site = Arc::clone(&sc_site);
        // 同步上下文（FRB 回调在会话线程内）：用阻塞 runtime 执行异步 TUP 调用
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(_) => return Vec::new(),
        };
        rt.block_on(async move {
            match slive_core::platforms::huya::super_chat::fetch_by_pid(&site, pid, false).await {
                Ok(list) => list,
                Err(e) => {
                    eprintln!("[huya-danmaku] SC 拉取失败: {e}");
                    Vec::new()
                }
            }
        })
    });

    // ⚠️ FRB 的 FFI 调用线程没有 tokio runtime —— 在这里 `tokio::spawn` 会 panic
    // （"there is no reactor running"，真机日志抓到过，13-spec §13）。弹幕会话放到
    // 独立线程 + 自建 runtime（current_thread 足够：单会话 IO）。
    std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("虎牙弹幕 runtime");
        runtime.block_on(async move {
            run_session(
                args,
                connect,
                Arc::new(SystemClock),
                SessionTuning::bilibili(),
                stop_rx,
                Some(fetch_super_chat),
                move |item| {
                    let _ = sink.add(item);
                },
            )
            .await;
        });
    });

    Ok(())
}

/// 虎牙 WS 握手头（对齐 Dart：浏览器 UA + Origin）。
fn ws_headers() -> Vec<(String, String)> {
    vec![
        (
            "user-agent".to_string(),
            slive_core::http::DEFAULT_USER_AGENT.to_string(),
        ),
        (
            "origin".to_string(),
            slive_core::platforms::huya::common::BASE_URL.to_string(),
        ),
    ]
}