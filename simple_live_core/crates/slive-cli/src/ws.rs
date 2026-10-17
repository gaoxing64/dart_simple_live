//! 生产 WS 帧源：包装 tokio-tungstenite。
//!
//! 与 FRB 桥层的实现同口径，但**不依赖 flutter_rust_bridge** —— 这正是
//! `slive-core` 零 FRB 依赖带来的可移植性：CLI / Tauri 可各自装配连接。
//!
//! 两种帧源：
//! - [`connect_binary`]：二进制帧（B站/斗鱼/虎牙/抖音），Text 帧忽略；
//! - [`connect_text`]：IRC 文本帧（Twitch），Binary 帧也照收。

use async_trait::async_trait;
use futures_util::{SinkExt, StreamExt};
use slive_core::error::SliveError;
use slive_core::ws::FrameSource;
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};

type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// 建立连接并追加业务头。
///
/// 必须由 URI 生成完整握手（含 `Sec-WebSocket-Key`）后再插头 —— 直接用 builder
/// 构造的 Request 会被 tungstenite 原样发出，因缺握手头而失败（桥层同修法）。
async fn connect(url: String, headers: Vec<(String, String)>) -> Result<WsStream, SliveError> {
    let mut request = url
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
    let (stream, _response) = connect_async(request)
        .await
        .map_err(|e| SliveError::Websocket(e.to_string()))?;
    Ok(stream)
}

async fn connect_binary(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    Ok(Box::new(BinaryFrames {
        stream: connect(url, headers).await?,
    }))
}

async fn connect_text(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    Ok(Box::new(TextFrames {
        stream: connect(url, headers).await?,
    }))
}

/// 二进制帧源（Text / Ping / Pong 忽略）。
pub struct BinaryFrames {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for BinaryFrames {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match self.stream.next().await {
                None => return None,
                Some(Err(e)) => return Some(Err(SliveError::Websocket(e.to_string()))),
                Some(Ok(Message::Binary(data))) => return Some(Ok(data)),
                Some(Ok(Message::Close(_))) => return None,
                Some(Ok(_)) => continue,
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

/// 文本帧源（IRC over WS）：Binary 帧同样视为有效载荷。
pub struct TextFrames {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for TextFrames {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match self.stream.next().await {
                None => return None,
                Some(Err(e)) => return Some(Err(SliveError::Websocket(e.to_string()))),
                Some(Ok(Message::Text(text))) => return Some(Ok(text.into_bytes())),
                Some(Ok(Message::Binary(data))) => return Some(Ok(data)),
                Some(Ok(Message::Close(_))) => return None,
                Some(Ok(_)) => continue,
            }
        }
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        let text = String::from_utf8(frame)
            .map_err(|e| SliveError::Websocket(format!("IRC 帧非 UTF-8: {e}")))?;
        self.stream
            .send(Message::Text(text))
            .await
            .map_err(|e| SliveError::Websocket(e.to_string()))
    }
}

/// 二进制帧连接工厂（供各平台 `ConnectFactory` 使用）。
pub fn binary_factory(
    url: String,
    headers: Vec<(String, String)>,
) -> slive_core::ws::ConnectFactory {
    Box::new(move || {
        let url = url.clone();
        let headers = headers.clone();
        Box::pin(async move { connect_binary(url, headers).await })
    })
}

/// 文本帧连接工厂（Twitch 专用）。
pub fn text_factory(
    url: String,
    headers: Vec<(String, String)>,
) -> slive_core::ws::ConnectFactory {
    Box::new(move || {
        let url = url.clone();
        let headers = headers.clone();
        Box::pin(async move { connect_text(url, headers).await })
    })
}
