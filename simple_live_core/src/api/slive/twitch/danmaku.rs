//! Twitch 弹幕 FRB 桥：生产 IRC-over-WebSocket 连接注入核心 `run_twitch_session`。
//!
//! 桥层只做**连接装配与事件转发**；URL / 握手帧 / IRC 解析 / 心跳 / 重连策略全部来自
//! `slive-core::platforms::twitch`（AC-39 / 裁决 J-6）。
//!
//! ⚠️ **FRB 的 FFI 调用线程没有 tokio runtime** —— 在那里 `tokio::spawn` 会 panic
//! （"there is no reactor running"，B站真机踩过）。本文件沿用同一修法：
//! **独立线程 + 自建 current_thread runtime**。
//!
//! 与 B站弹幕桥（`../danmaku.rs`）**完全独立命名**：本文件不引用、不修改其任何符号
//! （`DanmakuConnection` 为 B站私有；本侧是 `TwitchDanmakuConnection`）。

use std::sync::Arc;

use async_trait::async_trait;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::watch;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

use slive_core::error::SliveError;
use slive_core::platforms::twitch::danmaku::args::TwitchDanmakuArgs;
use slive_core::platforms::twitch::danmaku::session::{run_session, tuning};
use slive_core::time::SystemClock;
use slive_core::ws::FrameSource;

use crate::api::slive::error::CoreError;
use crate::api::slive::models::LiveDanmuItem;
use crate::frb_generated::StreamSink;

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// Twitch IRC 帧事件源：把 WebSocket **文本帧**转成字节帧。
///
/// 与 B站的差异是**必须的**：Twitch IRC over WS 走 WebSocket `Text` 帧，
/// 而 `../danmaku.rs` 的 `WsFrameSource` 只取 `Binary`（B站弹幕是二进制包）。
/// IRC 协议是 UTF-8 文本，因此 Text -> `String::from_utf8_lossy` -> 字节帧是无损的
/// （非法字节按 U+FFFD 替换，单条脏帧不中断会话）。
pub struct TwitchIrcFrameSource {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for TwitchIrcFrameSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match self.stream.next().await {
                None => return None,
                Some(Err(e)) => return Some(Err(SliveError::Websocket(e.to_string()))),
                Some(Ok(Message::Close(_))) => return None,
                Some(Ok(Message::Text(text))) => return Some(Ok(text.as_bytes().to_vec())),
                // Twitch IRC 的指令是文本帧；Binary/Ping/Pong 在此链路无意义，忽略。
                Some(Ok(_)) => continue,
            }
        }
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        let text = String::from_utf8_lossy(&frame).to_string();
        self.stream
            .send(Message::Text(text))
            .await
            .map_err(|e| SliveError::Websocket(e.to_string()))
    }
}

/// 连接装配（URL / headers 来自核心契约；生产与端到端冒烟共用）。
///
/// `#[frb(ignore)]`：内部管线函数（测试共用），返回类型含 `slive_core` 的
/// `SliveError`/`FrameSource`，不进 FRB API（codegen 会生成无 import 的悬空引用）。
#[flutter_rust_bridge::frb(ignore)]
pub async fn connect_twitch_frame_source(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    // 由 URI 生成完整 WS 握手（含 Sec-WebSocket-Key 等），再追加业务头；
    // 直接 builder 构造的 Request 会被 tungstenite 原样发送 -> 握手头缺失报错。
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
    Ok(Box::new(TwitchIrcFrameSource { stream }))
}

/// Twitch 弹幕连接句柄（FRB opaque）：**每实例一份**，持有本会话的停止信号。
///
/// 2026-10-18 修复多开异常：旧实现用全局单例 `twitch_active_stop` 登记「当前会话」，
/// 启动第二路会先把第一路的 stop 置 `true` —— 多开时只有最后启动的那路有弹幕，
/// 其余路聊天区显示「已手动停止」。改为句柄自持 stop 后各停各的、互不影响；
/// 句柄被释放（Dart 侧丢弃且未显式 stop）时发送端 drop，会话随句柄一起结束。
#[frb(opaque)]
pub struct TwitchDanmakuConnection {
    stop_tx: watch::Sender<bool>,
}

impl TwitchDanmakuConnection {
    /// 构造连接句柄（尚未连接；`start` 之后才持有会话）。
    #[frb(sync)]
    pub fn new() -> Self {
        let (stop_tx, _stop_rx) = watch::channel(false);
        Self { stop_tx }
    }

    /// 启动 Twitch 弹幕会话：连接 IRC over WebSocket，事件推入 stream。
    ///
    /// `channel_or_args` 是 `LiveRoomDetail.danmakuData` 的原样透参。
    /// ⚠️ **照搬 Dart**（`twitch_site.dart:241` + `twitch_danmaku.dart:56`）：Twitch 的
    /// `danmakuData` 就是 **roomId 字符串**（QA 夹具 `gql_twitch_tv_room_shell` 已钉死
    /// `expected.danmaku_data == "alice"`），**不带** `schema_version` 的 JSON 包装 ——
    /// Twitch 弹幕唯一入参就是频道名，无需版本化契约。
    /// 为兼容两种形态（裸频道名 / JSON 契约串），这里**显式**先按裸频道名解析，
    /// 失败再回退契约串；两者都非法 -> `CoreError(InvalidInput)`（**不静默兜底**，J-10 精神）。
    /// 多路播放各自持句柄调用，会话之间互不停止。
    pub fn start(
        &self,
        channel_or_args: String,
        sink: StreamSink<LiveDanmuItem>,
    ) -> Result<(), CoreError> {
        let args = parse_channel_args(&channel_or_args)?;
        let stop_rx = self.stop_tx.subscribe();

        // URL / headers 固定：提前计算，闭包只持有克隆（args 本身交给 run_twitch_session）
        let ws_url = args.ws_url();
        let ws_headers = args.connect_headers();

        std::thread::spawn(move || {
            // ⚠️ FRB FFI 线程无 tokio runtime —— 必须独立线程 + 自建 runtime（同 B站修法）。
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("twitch danmaku runtime");
            runtime.block_on(async move {
                let connect = move || {
                    let url = ws_url.clone();
                    let headers = ws_headers.clone();
                    Box::pin(async move { connect_twitch_frame_source(url, headers).await })
                        as std::pin::Pin<
                            Box<
                                dyn std::future::Future<
                                        Output = Result<Box<dyn FrameSource>, SliveError>,
                                    > + Send,
                            >,
                        >
                };
                run_session(
                    args,
                    Box::new(connect),
                    Arc::new(SystemClock),
                    tuning(),
                    stop_rx,
                    move |item| {
                        let _ = sink.add(item);
                    },
                )
                .await;
            });
        });

        Ok(())
    }

    /// 手动停止本会话（对齐 Dart `TwitchDanmaku.stop()`：发出 `Closed`，不再重连）。
    #[frb(sync)]
    pub fn stop(&self) {
        let _ = self.stop_tx.send(true);
    }
}

/// 解析 `danmakuData` -> 弹幕入参（**显式两形态**，不做隐式兜底）。
///
/// 1. 裸频道名（`"alice"` / `"Alice"`）—— Dart 与 QA 夹具的主形态；
/// 2. JSON 契约串（`{"schema_version":1,"channel":"alice"}`）—— 兼容未来版本化契约。
///
/// 两者都不成立 -> [`SliveError::InvalidInput`]（明确报错，不静默取默认频道）。
fn parse_channel_args(input: &str) -> Result<TwitchDanmakuArgs, SliveError> {
    let trimmed = input.trim();
    if !trimmed.is_empty() && !trimmed.starts_with('{') {
        return Ok(TwitchDanmakuArgs::new(trimmed));
    }
    TwitchDanmakuArgs::from_json(trimmed)
}
