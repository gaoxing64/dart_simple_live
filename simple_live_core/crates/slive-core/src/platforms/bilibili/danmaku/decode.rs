//! 弹幕帧解码：op3 人气 / op5 多协议载荷（对照 `bilibili_danmaku.dart:147-184`）。
//!
//! 纪律（AC-28）：损坏帧只记日志、不 panic、不向调用方抛错 —— 返回空集，
//! 会话层据此继续收帧、不断连接。

use crate::models::{LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageType};
use crate::ws::frame::{frame_body, parse_header, read_i32_be, OP_NOTIFY, OP_POPULARITY};

use super::parse::parse_message;

/// 解码一帧二进制为若干条 [`LiveMessage`]。
///
/// - op=3：body 为 4 字节大端 int32 人气值（AC-12）
/// - op=5：按头内 protover 解压（0=JSON / 2=zlib / 3=brotli）后切分、逐条解析（AC-13）
/// - 其他 op：忽略（对齐 Dart 仅处理 3/5）
pub fn decode_frame(data: &[u8]) -> Vec<LiveMessage> {
    let header = match parse_header(data) {
        Ok(h) => h,
        Err(e) => {
            log::warn!("弹幕帧解码失败（头）：{e}");
            return Vec::new();
        }
    };
    let body = match frame_body(data) {
        Some(b) => b,
        None => {
            log::warn!(
                "弹幕帧 body 为空：op={} packet_len={} 实际长度={}",
                header.op,
                header.packet_len,
                data.len()
            );
            return Vec::new();
        }
    };
    match header.op {
        OP_POPULARITY => decode_popularity(body),
        OP_NOTIFY => decode_notify(&header, body),
        _ => Vec::new(),
    }
}

fn decode_popularity(body: &[u8]) -> Vec<LiveMessage> {
    match read_i32_be(body) {
        Some(online) => vec![LiveMessage {
            message_type: LiveMessageType::Online,
            user_name: String::new(),
            user_id: None,
            message: String::new(),
            data: Some(LiveMessageData::Online(online)),
            color: LiveMessageColor::white(),
            emoticons: None,
        }],
        None => {
            log::warn!("op3 人气帧 body 不足 4 字节：{} 字节", body.len());
            Vec::new()
        }
    }
}

fn decode_notify(header: &crate::ws::frame::FrameHeader, body: &[u8]) -> Vec<LiveMessage> {
    let segments = match decode_payload(body, header.protover) {
        Ok(s) => s,
        Err(e) => {
            log::warn!("op5 载荷解压失败（protover={}）：{e}", header.protover);
            return Vec::new();
        }
    };
    segments
        .into_iter()
        .filter_map(|seg| parse_message(&seg))
        .collect()
}

/// op5 载荷解压 + 控制符切分（AC-13）。
///
/// `from_utf8_lossy` 对齐 Dart `utf8.decode(..., allowMalformed: true)` 的脏字节容错。
pub fn decode_payload(body: &[u8], protover: u16) -> Result<Vec<String>, crate::error::SliveError> {
    let raw = match protover {
        0 | 1 => body.to_vec(),
        2 => inflate_zlib(body)?,
        3 => inflate_brotli(body)?,
        other => {
            return Err(crate::error::SliveError::decode(format!(
                "未知弹幕协议版本 {other}"
            )))
        }
    };
    Ok(split_json_segments(&String::from_utf8_lossy(&raw)))
}

fn inflate_zlib(data: &[u8]) -> Result<Vec<u8>, crate::error::SliveError> {
    use std::io::Read;
    let mut out = Vec::new();
    flate2::read::ZlibDecoder::new(data)
        .read_to_end(&mut out)
        .map_err(|e| crate::error::SliveError::decode(format!("zlib 解压失败：{e}")))?;
    Ok(out)
}

fn inflate_brotli(data: &[u8]) -> Result<Vec<u8>, crate::error::SliveError> {
    use std::io::Read;
    let mut out = Vec::new();
    brotli::Decompressor::new(data, 4096)
        .read_to_end(&mut out)
        .map_err(|e| crate::error::SliveError::decode(format!("brotli 解压失败：{e}")))?;
    Ok(out)
}

/// 按 `[\x00-\x1f]+` 切分，保留「以 `{` 开头且长度 > 2」的片段
/// （对照 `bilibili_danmaku.dart:176-177`）。
fn split_json_segments(text: &str) -> Vec<String> {
    let mut segments: Vec<String> = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        if (ch as u32) <= 0x1f {
            if !current.is_empty() {
                segments.push(std::mem::take(&mut current));
            }
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        segments.push(current);
    }
    segments
        .into_iter()
        .filter(|s| s.len() > 2 && s.starts_with('{'))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// QA 夹具 `frame-op3-online`（AC-12）：op=3、人气 12345。
    const OP3_HEX: &str = "00 00 00 14 00 10 00 00 00 00 00 03 00 00 00 01 00 00 30 39";

    fn hex_bytes(hex: &str) -> Vec<u8> {
        hex.split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).expect("合法 hex"))
            .collect()
    }

    #[test]
    fn ac12_popularity_frame_yields_online_message() {
        let msgs = decode_frame(&hex_bytes(OP3_HEX));
        assert_eq!(msgs.len(), 1, "op3 应产出恰 1 条 online");
        assert_eq!(msgs[0].message_type, LiveMessageType::Online);
        assert_eq!(msgs[0].data, Some(LiveMessageData::Online(12345)));
        assert_eq!(msgs[0].color, LiveMessageColor::white());
        assert_eq!(msgs[0].user_name, "");
    }

    #[test]
    fn ac28_short_body_swallowed_without_panic() {
        // op=3 头声明 20 字节、实际截断到 18 → body 不足 4 字节 → 空集（不 panic）
        let mut frame = hex_bytes(OP3_HEX);
        frame.truncate(18);
        assert!(decode_frame(&frame).is_empty());
    }

    #[test]
    fn ac28_garbage_header_swallowed() {
        assert!(decode_frame(&[0u8; 4]).is_empty());
    }

    #[test]
    fn ac13_unknown_protover_reports_decode_error() {
        let err = decode_payload(b"{}", 9).unwrap_err();
        assert!(err.to_string().contains("协议版本"), "应报未知协议版本：{err}");
    }
}
