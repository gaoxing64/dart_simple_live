//! 顺序写缓冲 [`WriteBuffer`]（对照 Dart `tars_dart/lib/tars/tup/write_buffer.dart` 的 `WriteBuffer`）。
//!
//! 与 Dart 的差异：
//! - Dart 默认 `Endian.host`，此处默认 [`Endian::Big`] 并支持运行时切换；TARS 字段本就恒大端，行为等价。
//! - Dart 越界由 `ByteData` 抛错，写侧无越界概念，故本类型所有写方法均不返回 `Result`。

use super::super::buffer::order_bytes;
use super::super::endian::Endian;

/// 顺序写缓冲。
#[derive(Debug, Clone)]
pub struct WriteBuffer {
    buf: Vec<u8>,
    endian: Endian,
}

impl Default for WriteBuffer {
    fn default() -> Self {
        Self::new()
    }
}

impl WriteBuffer {
    /// 新建（初始容量 64 字节，大端）。
    pub fn new() -> Self {
        Self::with_capacity(64)
    }

    /// 指定初始容量新建（大端）。
    pub fn with_capacity(cap: usize) -> Self {
        Self {
            buf: Vec::with_capacity(cap),
            endian: Endian::Big,
        }
    }

    /// 新建并设定字节序。
    pub fn with_endian(endian: Endian) -> Self {
        Self {
            buf: Vec::with_capacity(64),
            endian,
        }
    }

    /// 运行时切换字节序（对后续写入生效）。
    pub fn set_endian(&mut self, endian: Endian) {
        self.endian = endian;
    }

    /// 当前字节序。
    pub fn endian(&self) -> Endian {
        self.endian
    }

    /// 已写字节数。
    pub fn len(&self) -> usize {
        self.buf.len()
    }

    /// 是否为空。
    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }

    /// 借阅已写内容。
    pub fn as_slice(&self) -> &[u8] {
        &self.buf
    }

    /// 取走已写内容（对齐 Dart `WriteBuffer.done()`）。
    pub fn into_bytes(self) -> Vec<u8> {
        self.buf
    }

    /// 补 0 对齐到 `alignment` 的整数倍（Dart `_alignTo`；`alignment == 0` 时无操作）。
    pub fn align_to(&mut self, alignment: usize) {
        if alignment == 0 {
            return;
        }
        let pad = (alignment - self.buf.len() % alignment) % alignment;
        self.buf.resize(self.buf.len() + pad, 0);
    }

    /// 写 u8。
    pub fn put_u8(&mut self, v: u8) {
        self.buf.push(v);
    }

    /// 写 i8（2 补码存 1 字节）。
    pub fn put_i8(&mut self, v: i8) {
        self.buf.push(v as u8);
    }

    /// 写 bool（TARS 中即 int1）。
    pub fn put_bool(&mut self, v: bool) {
        self.buf.push(u8::from(v));
    }

    /// 写 u16（按当前字节序）。
    pub fn put_u16(&mut self, v: u16) {
        self.put_u64_raw(v as u64, 2);
    }

    /// 写 i16（按当前字节序）。
    pub fn put_i16(&mut self, v: i16) {
        self.put_u16(v as u16);
    }

    /// 写 u32（按当前字节序）。
    pub fn put_u32(&mut self, v: u32) {
        self.put_u64_raw(v as u64, 4);
    }

    /// 写 i32（按当前字节序）。
    pub fn put_i32(&mut self, v: i32) {
        self.put_u32(v as u32);
    }

    /// 写 u64（按当前字节序）。
    pub fn put_u64(&mut self, v: u64) {
        self.put_u64_raw(v, 8);
    }

    /// 写 i64（按当前字节序）。
    pub fn put_i64(&mut self, v: i64) {
        self.put_u64(v as u64);
    }

    /// 写 f32（按当前字节序）。
    pub fn put_f32(&mut self, v: f32) {
        self.put_u32(v.to_bits());
    }

    /// 写 f64（按当前字节序）。
    pub fn put_f64(&mut self, v: f64) {
        self.put_u64(v.to_bits());
    }

    fn put_u64_raw(&mut self, v: u64, width: usize) {
        match width {
            1 => self.buf.push(v as u8),
            2 => self.buf.extend_from_slice(&order_bytes::<2>(v, self.endian)),
            4 => self.buf.extend_from_slice(&order_bytes::<4>(v, self.endian)),
            _ => self.buf.extend_from_slice(&order_bytes::<8>(v, self.endian)),
        }
    }

    /// 写裸字节。
    pub fn put_bytes(&mut self, v: &[u8]) {
        self.buf.extend_from_slice(v);
    }

    /// 写单个字节的 `v` 重复 `n` 次。
    pub fn put_repeated(&mut self, v: u8, n: usize) {
        self.buf.resize(self.buf.len() + n, v);
    }

    /// 写「1 字节长度 + UTF-8 内容」字符串（TARS `STRING1` 载荷，不含字段头）。
    /// 长度超 255 时**报错语义交由调用方**：此处按 `u8::MAX` 截断，
    /// 需要完整长度请改用 [`WriteBuffer::put_string_u32_len`]。
    pub fn put_string_u8_len(&mut self, s: &str) {
        let b = s.as_bytes();
        let n = b.len().min(u8::MAX as usize);
        self.put_u8(n as u8);
        self.put_bytes(&b[..n]);
    }

    /// 写「4 字节长度 + UTF-8 内容」字符串（TARS `STRING4` 载荷，不含字段头）。
    pub fn put_string_u32_len(&mut self, s: &str) {
        let b = s.as_bytes();
        self.put_u32(b.len() as u32);
        self.put_bytes(b);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tars::ReadBuffer;

    #[test]
    fn ints_roundtrip_in_both_endians() {
        for e in [Endian::Big, Endian::Little] {
            let mut w = WriteBuffer::with_endian(e);
            w.put_i32(-2);
            w.put_u32(0xDEAD_BEEF);
            w.put_i64(-1_234_567_890_123);
            w.put_i16(-300);
            w.put_i8(-5);
            let bytes = w.into_bytes();

            let mut r = ReadBuffer::with_endian(&bytes, e);
            assert_eq!(r.read_i32().unwrap(), -2);
            assert_eq!(r.read_u32().unwrap(), 0xDEAD_BEEF);
            assert_eq!(r.read_i64().unwrap(), -1_234_567_890_123);
            assert_eq!(r.read_i16().unwrap(), -300);
            assert_eq!(r.read_i8().unwrap(), -5);
        }
    }

    #[test]
    fn endian_switch_changes_byte_order_at_runtime() {
        let mut w = WriteBuffer::new();
        w.set_endian(Endian::Big);
        w.put_u16(0x0102);
        w.set_endian(Endian::Little);
        w.put_u16(0x0102);
        assert_eq!(w.as_slice(), &[0x01, 0x02, 0x02, 0x01]);
        assert_eq!(w.endian(), Endian::Little);
    }

    #[test]
    fn float_and_double_roundtrip() {
        let mut w = WriteBuffer::new();
        w.put_f32(1.5);
        w.put_f64(-2.25);
        w.put_bool(true);
        let b = w.into_bytes();
        let mut r = ReadBuffer::new(&b);
        assert_eq!(r.read_f32().unwrap(), 1.5);
        assert_eq!(r.read_f64().unwrap(), -2.25);
        assert!(r.read_bool().unwrap());
    }

    #[test]
    fn strings_are_length_prefixed_utf8_bytes() {
        let mut w = WriteBuffer::new();
        w.put_string_u8_len("弹幕");
        w.put_string_u32_len("ab");
        // "弹幕" 的 UTF-8 字节数为 6（不是 char 数 2）
        assert_eq!(w.as_slice()[0], 6);
        let b = w.into_bytes();
        let mut r = ReadBuffer::new(&b);
        assert_eq!(r.read_string_u8_len().unwrap(), "弹幕");
        assert_eq!(r.read_string_u32_len().unwrap(), "ab");
    }

    #[test]
    fn u8_len_string_truncates_over_255() {
        let long = "x".repeat(300);
        let mut w = WriteBuffer::new();
        w.put_string_u8_len(&long);
        let b = w.into_bytes();
        assert_eq!(b[0], u8::MAX, "长度前缀应截断为 255");
        assert_eq!(b.len(), 256);
    }

    #[test]
    fn align_to_pads_with_zero() {
        let mut w = WriteBuffer::new();
        w.put_u8(1);
        w.align_to(4);
        assert_eq!(w.as_slice(), &[1, 0, 0, 0]);
        w.align_to(0);
        assert_eq!(w.len(), 4, "alignment=0 应无操作");
    }

    #[test]
    fn repeated_and_capacity_helpers() {
        let mut w = WriteBuffer::with_capacity(2);
        assert!(w.is_empty());
        w.put_repeated(0xAB, 3);
        assert_eq!(w.as_slice(), &[0xAB, 0xAB, 0xAB]);
        assert_eq!(w.len(), 3);
        assert!(!w.is_empty());
        assert_eq!(w.into_bytes().len(), 3);
    }
}
