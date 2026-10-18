//! F-11 弹幕会话桥：生产 WS 连接（tokio-tungstenite + rustls）注入核心 `run_session`。
//!
//! 桥层只做连接装配与事件转发；URL / headers / 编解码 / 重连策略全部来自 `slive-core`（AC-39）。

use std::sync::Arc;

use async_trait::async_trait;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::watch;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

use slive_core::error::SliveError;
use slive_core::platforms::bilibili::danmaku::BiliBiliDanmakuArgs;
use slive_core::time::SystemClock;
use slive_core::ws::{run_session, ConnectFactory, FrameSource, SessionTuning};

use crate::api::slive::error::CoreError;
use crate::api::slive::models::LiveDanmuItem;
use crate::frb_generated::StreamSink;

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// 生产 WS 帧事件源：包装 tokio-tungstenite 连接。
pub struct WsFrameSource {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for WsFrameSource {
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

/// 连接装配（URL/headers 来自核心契约；生产与端到端冒烟共用）。
///
/// `#[frb(ignore)]`：内部管线函数（测试共用），不进 FRB API —— 其签名含
/// `slive_core` 的 `SliveError`/`FrameSource`，codegen 会生成无 import 的
/// 悬空引用炸 `frb_generated.rs`。
#[flutter_rust_bridge::frb(ignore)]
pub async fn connect_ws_frame_source(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    // 由 URI 生成完整 WS 握手（含 Sec-WebSocket-Key 等），再追加业务头；
    // 直接 builder 构造的 Request 会被 tungstenite 原样发送 → 握手头缺失报错。
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
    Ok(Box::new(WsFrameSource { stream }))
}

/// 弹幕会话句柄（FRB opaque）：**每实例一份**，持有本会话的停止信号。
///
/// 2026-10-18 修复多开异常：旧实现用全局单例 `active_stop` 登记「当前会话」，
/// 启动第二路会先把第一路的 stop 置 `true` —— 多开时只有最后启动的那路有弹幕，
/// 其余路聊天区显示「已手动停止」。改为句柄自持 stop 后各停各的、互不影响；
/// 句柄被释放（Dart 侧丢弃且未显式 stop）时发送端 drop，会话随句柄一起结束。
#[frb(opaque)]
pub struct DanmakuConnection {
    stop_tx: watch::Sender<bool>,
}

impl DanmakuConnection {
    /// 构造连接句柄（尚未连接；`start` 之后才持有会话）。
    #[frb(sync)]
    pub fn new() -> Self {
        let (stop_tx, _stop_rx) = watch::channel(false);
        Self { stop_tx }
    }

    /// 启动弹幕会话（F-11）：连接 `args` 指定的 WS 地址，事件推入 stream。
    ///
    /// `args_json` 是 [`BiliBiliDanmakuArgs`] 的 JSON 串（J-2 契约）；解析失败 →
    /// `CoreError(Decode)`，对应 Dart 侧 `FormatException`（J-10）。
    /// 多路播放各自持句柄调用，会话之间互不停止。
    pub fn start(
        &self,
        args_json: String,
        sink: StreamSink<LiveDanmuItem>,
    ) -> Result<(), CoreError> {
        let args = BiliBiliDanmakuArgs::from_json(&args_json).map_err(CoreError::from)?;
        let stop_rx = self.stop_tx.subscribe();

        // URL / headers 固定：提前计算，闭包只持有克隆（args 本身交给 run_session）
        let ws_url = args.ws_url();
        let ws_headers = args.connect_headers();

        let connect: ConnectFactory = Box::new(move || {
            let url = ws_url.clone();
            let headers = ws_headers.clone();
            Box::pin(async move { connect_ws_frame_source(url, headers).await })
        });

        // ⚠️ FRB 的 FFI 调用线程没有 tokio runtime —— 在这里 `tokio::spawn` 会
        // panic（"there is no reactor running"，真实日志抓到）。弹幕会话放到
        // 独立线程 + 自建 runtime（current_thread 足够：单会话 IO）。
        std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("danmaku runtime");
            runtime.block_on(async move {
                run_session(
                    args,
                    connect,
                    Arc::new(SystemClock),
                    SessionTuning::bilibili(),
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

    /// 手动停止（对齐 Dart `LiveDanmaku.stop()`：发出 `Closed`，不再重连）。
    #[frb(sync)]
    pub fn stop(&self) {
        let _ = self.stop_tx.send(true);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 多开回归（2026-10-18）：每个句柄的 stop 通道必须互相独立 ——
    /// 旧全局单例在这里会表现为「停 A 把 B 也停掉」。
    #[test]
    fn stop_channels_are_per_connection() {
        let a = DanmakuConnection::new();
        let b = DanmakuConnection::new();
        let mut rx_a = a.stop_tx.subscribe();

        a.stop();

        assert!(*rx_a.borrow_and_update(), "停 A 只应影响 A 自己");
        assert!(
            !*b.stop_tx.subscribe().borrow(),
            "B 的停止信号不得被 A 的 stop 触发"
        );
    }
}
