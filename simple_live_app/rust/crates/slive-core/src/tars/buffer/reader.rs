//! 顺序读缓冲 [`ReadBuffer`]（对照 Dart `tars_dart/lib/tars/tup/write_buffer.dart` 的 `ReadBuffer`）。
//!
//! 与 Dart 的差异：
//! - Dart 由 `ByteData` 抛 `RangeError`；本类型一律返回 `Err(SliveError::Decode)`，**绝不 panic**。
//! - Dart 默认 `Endian.host`，此处默认 [`Endian::Big`] 并支持运行时切换（TARS 字段恒大端，行为等价）。
//! - 字符串非法 UTF-8 时 Dart `utf8.decode` 抛异常；此处返回 `Decode` 错误，不做 lossy 替换
//!   （弹幕昵称/内容不能被静默改写）。

use crate::error::SliveError;

use super::super::buffer::{check_string_len, decode_utf8, from_order_bytes, out_of_bounds};
use super::super::endian::Endian;

/// 顺序读缓冲，零拷贝借用底层字节。
#[derive(Debug, Clone)]
pub struct ReadBuffer<'a> {
    data: &'a [u8],
    pos: usize,
    endian: Endian,
}

impl<'a> ReadBuffer<'a> {
    /// 从 `data` 起始处读（大端）。
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            data,
            pos: 0,
            endian: Endian::Big,
        }
    }

    /// 从 `pos` 开始读（大端）。`pos > len` 不立即报错，首次读取时返回越界错误。
    pub fn at(data: &'a [u8], pos: usize) -> Self {
        Self {
            data,
            pos,
            endian: Endian::Big,
        }
    }

    /// 新建并设定字节序。
    pub fn with_endian(data: &'a [u8], endian: Endian) -> Self {
        Self {
            data,
            pos: 0,
            endian,
        }
    }

    /// 运行时切换字节序（对后续读取生效）。
    pub fn set_endian(&mut self, endian: Endian) {
        self.endian = endian;
    }

    /// 当前字节序。
    pub fn endian(&self) -> Endian {
        self.endian
    }

    /// 当前读偏移。
    pub fn position(&self) -> usize {
        self.pos
    }

    /// 跳到指定偏移；越界返回 `Err`（游标保持不变）。
    pub fn seek(&mut self, pos: usize) -> Result<(), SliveError> {
        if pos > self.data.len() {
            return Err(out_of_bounds("seek", pos, 0, self.data.len()));
        }
        self.pos = pos;
        Ok(())
    }

    /// 底层总长。
    pub fn total_len(&self) -> usize {
        self.data.len()
    }

    /// 剩余未读字节数。
    pub fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.pos)
    }

    /// 是否已读完。
    pub fn is_empty(&self) -> bool {
        self.remaining() == 0
    }

    /// 剩余字节的切片视图（不推进游标）。
    pub fn remaining_slice(&self) -> &'a [u8] {
        &self.data[self.pos.min(self.data.len())..]
    }

    fn take(&mut self, n: usize, what: &str) -> Result<&'a [u8], SliveError> {
        if self.remaining() < n {
            return Err(out_of_bounds(what, self.pos, n, self.data.len()));
        }
        let s = &self.data[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }

    /// 跳过 `n` 字节。
    pub fn skip(&mut self, n: usize) -> Result<(), SliveError> {
        self.take(n, "skip").map(|_| ())
    }

    /// 读 u8。
    pub fn read_u8(&mut self) -> Result<u8, SliveError> {
        Ok(self.take(1, "u8")?[0])
    }

    /// 读 i8。
    pub fn read_i8(&mut self) -> Result<i8, SliveError> {
        Ok(self.read_u8()? as i8)
    }

    /// 读 bool。
    pub fn read_bool(&mut self) -> Result<bool, SliveError> {
        Ok(self.read_u8()? != 0)
    }

    /// 按 `width` 字节读整型（1/2/4/8），字节序与 [`WriteBuffer`](super::WriteBuffer) 对称。
    fn read_u64_raw(&mut self, width: usize, what: &str) -> Result<u64, SliveError> {
        Ok(match width {
            1 => u64::from(self.read_u8()?),
            2 => from_order_bytes::<2>(self.read_array::<2>("u16")?, self.endian),
            4 => from_order_bytes::<4>(self.read_array::<4>("u32")?, self.endian),
            8 => from_order_bytes::<8>(self.read_array::<8>("u64")?, self.endian),
            _ => {
                return Err(SliveError::decode(format!(
                    "TARS 不支持的整数宽度: {width}（{what}）"
                )))
            }
        })
    }

    /// 读 `N` 字节到定长数组。
    fn read_array<const N: usize>(&mut self, what: &str) -> Result<[u8; N], SliveError> {
        let s = self.take(N, what)?;
        let mut a = [0u8; N];
        a.copy_from_slice(s);
        Ok(a)
    }

    /// 读 u16（按当前字节序）。
    pub fn read_u16(&mut self) -> Result<u16, SliveError> {
        Ok(self.read_u64_raw(2, "u16")? as u16)
    }

    /// 读 i16（按当前字节序）。
    pub fn read_i16(&mut self) -> Result<i16, SliveError> {
        Ok(self.read_u16()? as i16)
    }

    /// 读 u32（按当前字节序）。
    pub fn read_u32(&mut self) -> Result<u32, SliveError> {
        Ok(self.read_u64_raw(4, "u32")? as u32)
    }

    /// 读 i32（按当前字节序）。
    pub fn read_i32(&mut self) -> Result<i32, SliveError> {
        Ok(self.read_u32()? as i32)
    }

    /// 读 u64（按当前字节序）。
    pub fn read_u64(&mut self) -> Result<u64, SliveError> {
        self.read_u64_raw(8, "u64")
    }

    /// 读 i64（按当前字节序）。
    pub fn read_i64(&mut self) -> Result<i64, SliveError> {
        Ok(self.read_u64()? as i64)
    }

    /// 读 f32（按当前字节序）。
    pub fn read_f32(&mut self) -> Result<f32, SliveError> {
        Ok(f32::from_bits(self.read_u32()?))
    }

    /// 读 f64（按当前字节序）。
    pub fn read_f64(&mut self) -> Result<f64, SliveError> {
        Ok(f64::from_bits(self.read_u64()?))
    }

    /// 读 `n` 字节裸数据（零拷贝）。
    pub fn read_bytes(&mut self, n: usize) -> Result<&'a [u8], SliveError> {
        self.take(n, "bytes")
    }

    /// 读全部剩余字节（零拷贝）。
    pub fn read_to_end(&mut self) -> &'a [u8] {
        let s = &self.data[self.pos.min(self.data.len())..];
        self.pos = self.data.len();
        s
    }

    /// 读「1 字节长度 + UTF-8 内容」字符串（TARS `STRING1` 载荷，不含字段头）。
    pub fn read_string_u8_len(&mut self) -> Result<String, SliveError> {
        let n = self.read_u8()? as i32;
        let s = self.take(check_string_len(n)?, "STRING1")?;
        decode_utf8(s, "STRING1")
    }

    /// 读「4 字节长度 + UTF-8 内容」字符串（TARS `STRING4` 载荷，不含字段头）。
    pub fn read_string_u32_len(&mut self) -> Result<String, SliveError> {
        let n = self.read_i32()?;
        let s = self.take(check_string_len(n)?, "STRING4")?;
        decode_utf8(s, "STRING4")
    }

    /// 读 `n` 个 u32 数组。
    pub fn read_u32_array(&mut self, n: usize) -> Result<Vec<u32>, SliveError> {
        let mut out = Vec::with_capacity(n.min(4096));
        for _ in 0..n {
            out.push(self.read_u32()?);
        }
        Ok(out)
    }

    /// 读 `n` 个 i64 数组。
    pub fn read_i64_array(&mut self, n: usize) -> Result<Vec<i64>, SliveError> {
        let mut out = Vec::with_capacity(n.min(4096));
        for _ in 0..n {
            out.push(self.read_i64()?);
        }
        Ok(out)
    }
}
#[cfg(test)]
#[path = "reader_tests.rs"]
mod tests;
