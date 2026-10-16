//! 弹幕帧头编解码（对照 `bilibili_danmaku.dart:119-145`（`encodeData`）与 `:241-261`（`readInt`））。
//!
//! 帧结构（大端）：
//! | 偏移 | 长度 | 字段 |
//! |------|------|------|
//! | 0 | 4 | 包总长（含头） |
//! | 4 | 2 | 头长（固定 16） |
//! | 6 | 2 | 协议版本 protover（**头字段恒 0**；protover=3 只出现在 JSON body 内） |
//! | 8 | 4 | 操作码 op |
//! | 12 | 4 | 序列 seq（固定 1） |

use crate::error::SliveError;

/// 帧头长度（固定）。
pub const HEADER_LEN: usize = 16;
/// op：心跳。
pub const OP_HEARTBEAT: u32 = 2;
/// op：人气值（body 为 4 字节大端 int32）。
pub const OP_POPULARITY: u32 = 3;
/// op：通知（弹幕/礼物/SC 等）。
pub const OP_NOTIFY: u32 = 5;
/// op：加入房间。
pub const OP_JOIN: u32 = 7;
/// seq 固定值。
const SEQ: u32 = 1;

/// 解出的帧头。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameHeader {
    /// 包总长（含头）。
    pub packet_len: u32,
    /// 头长。
    pub header_len: u16,
    /// 协议版本。
    pub protover: u16,
    /// 操作码。
    pub op: u32,
    /// 序列号。
    pub seq: u32,
}

/// 编码一帧：头(16) + body。`op` 为操作码，头内 protover 恒为 0（对齐 Dart `encodeData`）。
pub fn encode_packet(body: &[u8], op: i32) -> Vec<u8> {
    let total = (HEADER_LEN + body.len()) as u32;
    let mut out = Vec::with_capacity(HEADER_LEN + body.len());
    out.extend_from_slice(&total.to_be_bytes());
    out.extend_from_slice(&(HEADER_LEN as u16).to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&(op as u32).to_be_bytes());
    out.extend_from_slice(&SEQ.to_be_bytes());
    out.extend_from_slice(body);
    out
}

/// 心跳帧：空 body + op=2。
pub fn heartbeat_packet() -> Vec<u8> {
    encode_packet(&[], OP_HEARTBEAT as i32)
}

/// 解析帧头；长度不足 -> [`SliveError::Decode`]。
pub fn parse_header(data: &[u8]) -> Result<FrameHeader, SliveError> {
    if data.len() < HEADER_LEN {
        return Err(SliveError::decode(format!(
            "帧长度不足：需 ≥{HEADER_LEN}，实际 {}",
            data.len()
        )));
    }
    Ok(FrameHeader {
        packet_len: u32::from_be_bytes([data[0], data[1], data[2], data[3]]),
        header_len: u16::from_be_bytes([data[4], data[5]]),
        protover: u16::from_be_bytes([data[6], data[7]]),
        op: u32::from_be_bytes([data[8], data[9], data[10], data[11]]),
        seq: u32::from_be_bytes([data[12], data[13], data[14], data[15]]),
    })
}

/// 取帧 body（头之后到帧尾）。
pub fn frame_body(data: &[u8]) -> Option<&[u8]> {
    let header = parse_header(data).ok()?;
    let start = header.header_len as usize;
    let end = (header.packet_len as usize).min(data.len());
    if end <= start || start > data.len() {
        return None;
    }
    Some(&data[start..end])
}

/// 读取大端 i32（op=3 人气值）。
pub fn read_i32_be(data: &[u8]) -> Option<i32> {
    if data.len() < 4 {
        return None;
    }
    Some(i32::from_be_bytes([data[0], data[1], data[2], data[3]]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_roundtrip() {
        let packet = encode_packet(b"{\"a\":1}", OP_JOIN as i32);
        let header = parse_header(&packet).expect("应能解头");
        assert_eq!(header.header_len, 16, "头长固定 16");
        assert_eq!(header.protover, 0, "头内 protover 恒 0");
        assert_eq!(header.op, OP_JOIN);
        assert_eq!(header.seq, 1);
        assert_eq!(header.packet_len as usize, packet.len());
        assert_eq!(frame_body(&packet), Some(&b"{\"a\":1}"[..]));
    }

    #[test]
    fn heartbeat_frame_is_16_bytes() {
        let hb = heartbeat_packet();
        assert_eq!(hb.len(), HEADER_LEN, "心跳包应恰为 16 字节");
        let header = parse_header(&hb).expect("应能解头");
        assert_eq!(header.op, OP_HEARTBEAT);
    }

    #[test]
    fn short_frame_reports_decode_error() {
        assert!(matches!(parse_header(&[0u8; 4]), Err(SliveError::Decode(_))));
    }
}
