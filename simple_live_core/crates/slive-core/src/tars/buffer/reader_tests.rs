//! `reader.rs`（`ReadBuffer`）的单元测试。
//!
//! 外置到独立文件以满足单文件 <= 300 行门禁；由 `reader.rs` 的
//! `#[path = "reader_tests.rs"] mod tests;` 引入。

use super::*;
use crate::tars::WriteBuffer;

#[test]
fn truncated_read_returns_error_not_panic() {
    let b = [0x01u8, 0x02];
    let mut r = ReadBuffer::new(&b);
    assert!(matches!(r.read_u32(), Err(SliveError::Decode(_))));
    assert_eq!(r.position(), 0, "失败后游标不推进");
    assert!(matches!(r.read_i64(), Err(SliveError::Decode(_))));
    assert!(matches!(r.read_f64(), Err(SliveError::Decode(_))));
    // 2 字节刚好够 u16/i16，应成功
    assert_eq!(r.read_u16().unwrap(), 0x0102);
}

#[test]
fn empty_buffer_reads_report_error() {
    let mut r = ReadBuffer::new(&[]);
    assert!(r.is_empty());
    assert_eq!(r.remaining(), 0);
    assert!(r.read_u8().is_err());
    assert_eq!(r.remaining_slice(), &[] as &[u8]);
    assert_eq!(r.read_to_end(), &[] as &[u8]);
}

#[test]
fn seek_beyond_end_is_error_and_keeps_cursor() {
    let b = [0u8; 3];
    let mut r = ReadBuffer::new(&b);
    assert!(r.seek(4).is_err());
    assert_eq!(r.position(), 0);
    assert!(r.seek(3).is_ok());
    assert_eq!(r.position(), 3);
}

#[test]
fn negative_string_length_is_rejected() {
    let b = [0xFFu8, 0xFF, 0xFF, 0xFF];
    let mut r = ReadBuffer::new(&b);
    assert!(matches!(r.read_string_u32_len(), Err(SliveError::Decode(_))));
}

#[test]
fn invalid_utf8_string_is_rejected_not_replaced() {
    let b = [0x02u8, 0xFF, 0xFE];
    let mut r = ReadBuffer::new(&b);
    let err = r.read_string_u8_len().unwrap_err();
    assert!(err.to_string().contains("非 UTF-8"), "实际: {err}");
}

#[test]
fn arrays_read_correctly() {
    let mut w = WriteBuffer::new();
    w.put_u32(1);
    w.put_u32(2);
    w.put_i64(-7);
    let b = w.into_bytes();
    let mut r = ReadBuffer::new(&b);
    assert_eq!(r.read_u32_array(2).unwrap(), vec![1, 2]);
    assert_eq!(r.read_i64_array(1).unwrap(), vec![-7]);
    assert!(r.is_empty());
}

#[test]
fn read_to_end_drains_remaining() {
    let b = [1u8, 2, 3, 4, 5];
    let mut r = ReadBuffer::new(&b);
    assert_eq!(r.skip(2).unwrap(), ());
    assert_eq!(r.read_to_end(), &[3, 4, 5]);
    assert_eq!(r.total_len(), 5);
    assert!(r.is_empty());
}

#[test]
fn endian_can_switch_mid_stream() {
    let b = [0x01u8, 0x02, 0x02, 0x01];
    let mut r = ReadBuffer::new(&b);
    assert_eq!(r.read_u16().unwrap(), 0x0102);
    r.set_endian(Endian::Little);
    assert_eq!(r.read_u16().unwrap(), 0x0102);
    assert_eq!(r.endian(), Endian::Little);
}

#[test]
fn unsupported_width_is_error() {
    let b = [0u8; 3];
    let mut r = ReadBuffer::new(&b);
    assert!(r.read_u64_raw(3, "u24").is_err());
}
