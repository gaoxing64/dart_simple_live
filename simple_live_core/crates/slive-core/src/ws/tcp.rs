//! 明文 TCP 帧源（斗鱼弹幕 `danmuproxy.douyu.com:8601`，ADR-015）。
//!
//! 与 [`super::session::FrameSource`] 同接口，供斗鱼会话直接复用；帧格式与 WSS 一致：
//!
//! ```text
//! | 全长(4,LE)=帧长-4 | 全长(4,LE) | 包类型(2,LE) | 加密(1) | 保留(1) | 载荷 | 结束符(1) |
//! ```
//!
//! TCP 是字节流：一次 `read` 可能只拿到半帧，也可能拿到多帧。切帧在
//! [`take_frame`] 里按「先读 4 字节全长，再攒满整帧」处理。

use async_trait::async_trait;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

use crate::error::SliveError;
use crate::ws::ConnectFactory;

use super::session::FrameSource;

/// 单帧上限（防御异常长度字段导致缓冲无限膨胀）。
const MAX_FRAME_BYTES: usize = 1 << 20;

/// 按 `tcp://host:port/` 构造连接工厂（scheme 在此剥掉）。
pub fn factory(url: String) -> ConnectFactory {
    let addr = url
        .strip_prefix("tcp://")
        .unwrap_or(&url)
        .trim_end_matches('/')
        .to_string();
    Box::new(move || {
        let addr = addr.clone();
        Box::pin(async move {
            let source = TcpFrameSource::connect(&addr).await?;
            Ok(Box::new(source) as Box<dyn FrameSource>)
        })
    })
}

/// 明文 TCP 帧源。
pub struct TcpFrameSource {
    stream: TcpStream,
    buffer: Vec<u8>,
}

impl TcpFrameSource {
    /// 建立 TCP 连接。
    pub async fn connect(addr: &str) -> Result<Self, SliveError> {
        let stream = TcpStream::connect(addr)
            .await
            .map_err(|e| SliveError::network(format!("TCP 连接失败({addr}): {e}")))?;
        Ok(Self {
            stream,
            buffer: Vec::with_capacity(8 * 1024),
        })
    }
}

#[async_trait]
impl FrameSource for TcpFrameSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match take_frame(&mut self.buffer) {
                Ok(Some(frame)) => return Some(Ok(frame)),
                Ok(None) => {}
                Err(e) => return Some(Err(e)),
            }
            match self.stream.read_buf(&mut self.buffer).await {
                Ok(0) => return None,
                Ok(_) => {}
                Err(e) => return Some(Err(SliveError::network(format!("TCP 读取失败: {e}")))),
            }
        }
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        self.stream
            .write_all(&frame)
            .await
            .map_err(|e| SliveError::network(format!("TCP 发送失败: {e}")))
    }
}

/// 从缓冲切出一个完整帧；不足一帧返回 `Ok(None)`。
fn take_frame(buffer: &mut Vec<u8>) -> Result<Option<Vec<u8>>, SliveError> {
    if buffer.len() < 4 {
        return Ok(None);
    }
    let declaration = u32::from_le_bytes([buffer[0], buffer[1], buffer[2], buffer[3]]) as usize;
    if declaration < 9 {
        return Err(SliveError::decode(format!(
            "斗鱼 TCP 帧长度非法: {declaration}"
        )));
    }
    if declaration > MAX_FRAME_BYTES {
        return Err(SliveError::decode(format!(
            "斗鱼 TCP 帧过大: {declaration}"
        )));
    }
    // 全长字段 = 帧长 - 4（首 4 字节自身不计入）
    let total = declaration + 4;
    if buffer.len() < total {
        return Ok(None);
    }
    Ok(Some(buffer.drain(..total).collect()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio::net::TcpListener;

    fn frame(body: &str) -> Vec<u8> {
        let payload = body.as_bytes();
        let declaration = (payload.len() + 9) as u32;
        let mut out = Vec::with_capacity(payload.len() + 13);
        out.extend_from_slice(&declaration.to_le_bytes());
        out.extend_from_slice(&declaration.to_le_bytes());
        out.extend_from_slice(&[0xb1, 0x02]);
        out.extend_from_slice(&[0, 0]);
        out.extend_from_slice(payload);
        out.push(0);
        out
    }

    #[test]
    fn take_frame_waits_for_complete_frame() {
        let full = frame("type@=chatmsg/");
        for split in 0..full.len() {
            let mut buffer = full[..split].to_vec();
            assert!(
                take_frame(&mut buffer).expect("不报错").is_none(),
                "split={split} 时不足一帧"
            );
            buffer.extend_from_slice(&full[split..]);
            assert_eq!(take_frame(&mut buffer).expect("不报错"), Some(full.clone()));
            assert!(buffer.is_empty(), "整帧应被取走");
        }
    }

    #[test]
    fn take_frame_handles_sticky_frames() {
        let a = frame("type@=loginres/");
        let b = frame("type@=chatmsg/");
        let mut buffer = [a.clone(), b.clone()].concat();
        assert_eq!(take_frame(&mut buffer).expect("不报错"), Some(a));
        assert_eq!(take_frame(&mut buffer).expect("不报错"), Some(b));
        assert!(take_frame(&mut buffer).expect("不报错").is_none());
    }

    #[test]
    fn take_frame_rejects_illegal_length() {
        let mut too_small = vec![1, 0, 0, 0];
        assert!(take_frame(&mut too_small).is_err());
        let mut too_large = vec![0xff, 0xff, 0xff, 0xff];
        assert!(take_frame(&mut too_large).is_err());
    }

    #[tokio::test]
    async fn tcp_source_sends_and_reassembles_split_frame() {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let addr = listener.local_addr().expect("addr");
        let outbound = frame("type@=loginreq/roomid@=999/");
        let inbound = frame("type@=chatmsg/");

        let server_outbound = outbound.clone();
        let server_inbound = inbound.clone();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.expect("accept");
            let mut received = vec![0u8; server_outbound.len()];
            socket.read_exact(&mut received).await.expect("read");
            assert_eq!(received, server_outbound, "客户端发送的帧必须逐字节一致");
            let split = server_inbound.len() / 2;
            socket
                .write_all(&server_inbound[..split])
                .await
                .expect("write");
            socket.flush().await.expect("flush");
            tokio::time::sleep(Duration::from_millis(30)).await;
            socket
                .write_all(&server_inbound[split..])
                .await
                .expect("write");
            socket.flush().await.expect("flush");
            tokio::time::sleep(Duration::from_millis(200)).await;
        });

        let mut source = TcpFrameSource::connect(&addr.to_string())
            .await
            .expect("connect");
        source.send(outbound).await.expect("send");
        let got = source.next_frame().await.expect("有帧").expect("帧可读");
        assert_eq!(got, inbound, "半帧分两次到达也应拼成整帧");
        server.await.expect("server");
    }
}
