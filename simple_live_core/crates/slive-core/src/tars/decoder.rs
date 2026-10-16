//! TARS 解码器核心 [`TarsDecoder`]（对照 Dart `tars_dart/lib/tars/codec/tars_input_stream.dart`）。
//!
//! 本文件只放「字节层」能力：游标管理、裸读、字段头读写、按 tag 定位与跳字段。
//! 强类型字段读取（`read_i64` / `read_string` / `read_bytes` / `read_list` / `read_map` /
//! `read_struct` / `read_value`）见 [`super::decoder_read`]。
//!
//! # 与 Dart 的差异（有意为之）
//!
//! Dart 的 `skipToTag` 用 try/catch 吞掉越界并返回 `false`，随后在 `isRequire=false` 时
//! 返回默认值（0 / "" / 空 bytes）。本模块改为**返回 `Err`**，由调用方决定是否降级：
//! - 需要「缺失即默认值」语义：用 `read_*_or` 系列（见 [`super::decoder_read`]）；
//! - 需要严格校验：直接用 `read_*` 并 `?` 传播错误。
//!
//! 整型载荷**恒为大端**，且 `BYTE` 按**无符号**读取（对齐 Dart `getUint8` 与官方 C++
//! `unsigned char` 语义）。

use crate::error::SliveError;

use super::buffer::check_string_len;
use super::stream::{read_head, FieldHead, TarsType};

/// TARS 解码器（读方向），持有底层字节与游标。
#[derive(Debug, Clone)]
pub struct TarsDecoder<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> TarsDecoder<'a> {
    /// 从 `buf` 起始处解码。
    pub fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    /// 从指定偏移开始解码。
    pub fn at(buf: &'a [u8], pos: usize) -> Self {
        Self { buf, pos }
    }

    /// 当前游标。
    pub fn position(&self) -> usize {
        self.pos
    }

    /// 剩余字节数。
    pub fn remaining(&self) -> usize {
        self.buf.len().saturating_sub(self.pos)
    }

    /// 是否已读完。
    pub fn is_empty(&self) -> bool {
        self.remaining() == 0
    }

    /// 借阅剩余数据（不推进游标）。
    pub fn remaining_slice(&self) -> &'a [u8] {
        &self.buf[self.pos.min(self.buf.len())..]
    }

    /// 直接读 1 字节（不解释字段头）。
    pub fn read_raw_u8(&mut self) -> Result<u8, SliveError> {
        if self.pos >= self.buf.len() {
            return Err(SliveError::decode("TARS 读字节失败：已到末尾"));
        }
        let v = self.buf[self.pos];
        self.pos += 1;
        Ok(v)
    }

    /// 直接读裸字节 `n` 个（不解释字段头，零拷贝）。
    pub fn read_raw_bytes(&mut self, n: usize) -> Result<&'a [u8], SliveError> {
        if self.remaining() < n {
            return Err(SliveError::decode(format!(
                "TARS 读 {n} 字节越界：偏移 {} 剩余 {} 字节",
                self.pos,
                self.remaining()
            )));
        }
        let s = &self.buf[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }

    /// 直接读 4 字节大端 i32（不解释字段头），对齐 Dart `readInt(tag, ...)` 在
    /// 「长度字段的字段头已被消费」后的裸读场景。
    pub fn read_raw_i32(&mut self) -> Result<i32, SliveError> {
        let b = self.read_raw_bytes(4)?;
        Ok(i32::from_be_bytes([b[0], b[1], b[2], b[3]]))
    }

    /// 读字段头（不跳字段）。
    pub fn read_field_head(&mut self) -> Result<FieldHead, SliveError> {
        let (h, n) = read_head(self.buf, self.pos)?;
        self.pos += n;
        Ok(h)
    }

    /// 定位到 `tag` 字段并读出其字段头；缺失或类型不符时由调用方处理。
    ///
    /// 返回的 `FieldHead` 的 `tag` 即定位到的 tag。
    pub(crate) fn locate(&mut self, tag: i32) -> Result<FieldHead, SliveError> {
        if !self.skip_to_tag(tag)? {
            return Err(SliveError::decode(format!(
                "TARS 必填字段缺失: tag={tag}"
            )));
        }
        self.read_field_head()
    }

    /// 跳到 `tag`：跳过所有更小 tag 的字段，直到遇到 `tag` 或 `STRUCT_END`。
    /// 返回 `true` 表示当前字段就是 `tag`（对齐 Dart `skipToTag`）。
    pub fn skip_to_tag(&mut self, tag: i32) -> Result<bool, SliveError> {
        loop {
            let (h, n) = read_head(self.buf, self.pos)?;
            if tag <= h.tag || h.ty == TarsType::StructEnd {
                return Ok(tag == h.tag);
            }
            self.pos += n;
            self.skip_field_with_type(h.ty)?;
        }
    }

    /// 按已知类型跳过一个字段的**载荷**（字段头已被消费）。
    pub(crate) fn skip_field_with_type(&mut self, ty: TarsType) -> Result<(), SliveError> {
        match ty {
            // `ZERO_TAG` 无任何载荷字节（对齐 Dart `writeByte`：值为 0 时只写头）。
            TarsType::ZeroTag => {}
            TarsType::Byte => self.pos += 1,
            TarsType::Short => self.pos += 2,
            TarsType::Int | TarsType::Float => self.pos += 4,
            TarsType::Long | TarsType::Double => self.pos += 8,
            TarsType::String1 => {
                let n = self.read_raw_u8()? as usize;
                self.pos += n;
            }
            TarsType::String4 => {
                let n = self.read_raw_i32()?;
                self.pos += check_string_len(n)?;
            }
            TarsType::Map => {
                let size = self.read_len_field()?;
                for _ in 0..size.saturating_mul(2) {
                    self.skip_field()?;
                }
            }
            TarsType::List => {
                let size = self.read_len_field()?;
                for _ in 0..size {
                    self.skip_field()?;
                }
            }
            TarsType::SimpleList => {
                let inner = self.read_field_head()?;
                if inner.ty != TarsType::Byte {
                    return Err(SliveError::decode(format!(
                        "TARS SimpleList 内层类型应为 BYTE，实为 {}",
                        inner.ty.as_str()
                    )));
                }
                let size = self.read_len_field()?;
                self.pos += size;
            }
            TarsType::StructBegin => return self.skip_to_struct_end(),
            TarsType::StructEnd => {}
        }
        if self.pos > self.buf.len() {
            return Err(SliveError::decode(format!(
                "TARS 跳过 {} 字段后越界（偏移 {} > 长度 {}）",
                ty.as_str(),
                self.pos,
                self.buf.len()
            )));
        }
        Ok(())
    }

    /// 读「长度字段」：按 tag=0 读一个整型（对齐 Dart `readInt(0, true)`）。
    pub(crate) fn read_len_field(&mut self) -> Result<usize, SliveError> {
        if !self.skip_to_tag(0)? {
            return Err(SliveError::decode("TARS 长度字段缺失"));
        }
        let h = self.read_field_head()?;
        if !h.ty.is_integral() {
            return Err(SliveError::decode(format!(
                "TARS 长度字段类型应为整型，实为 {}",
                h.ty.as_str()
            )));
        }
        let n = self.read_int_payload(h.ty)?;
        if n < 0 {
            return Err(SliveError::decode(format!("TARS 长度为负: {n}")));
        }
        Ok(n as usize)
    }

    /// 按整型类型读载荷（字段头已消费）。
    ///
    /// `BYTE` 按 `0..=255` 返回（对齐 Dart `getUint8` 与官方 C++ `unsigned char`）。
    pub(crate) fn read_int_payload(&mut self, ty: TarsType) -> Result<i64, SliveError> {
        match ty {
            TarsType::Byte => Ok(self.read_raw_u8()? as i64),
            TarsType::Short => {
                let b = self.read_raw_bytes(2)?;
                Ok(i16::from_be_bytes([b[0], b[1]]) as i64)
            }
            TarsType::Int => Ok(self.read_raw_i32()? as i64),
            TarsType::Long => {
                let b = self.read_raw_bytes(8)?;
                let mut a = [0u8; 8];
                a.copy_from_slice(b);
                Ok(i64::from_be_bytes(a))
            }
            TarsType::ZeroTag => Ok(0),
            other => Err(SliveError::decode(format!(
                "TARS 整型载荷遇到非整型类型 {}",
                other.as_str()
            ))),
        }
    }

    /// 按浮点类型读载荷（字段头已消费）。
    pub(crate) fn read_float_payload(&mut self, ty: TarsType) -> Result<f64, SliveError> {
        match ty {
            TarsType::Float => {
                let b = self.read_raw_bytes(4)?;
                Ok(f32::from_be_bytes([b[0], b[1], b[2], b[3]]) as f64)
            }
            TarsType::Double => {
                let b = self.read_raw_bytes(8)?;
                let mut a = [0u8; 8];
                a.copy_from_slice(b);
                Ok(f64::from_be_bytes(a))
            }
            other => Err(SliveError::decode(format!(
                "TARS 浮点载荷遇到非浮点类型 {}",
                other.as_str()
            ))),
        }
    }

    /// 跳过一个完整字段（头 + 载荷）。
    pub fn skip_field(&mut self) -> Result<(), SliveError> {
        let h = self.read_field_head()?;
        self.skip_field_with_type(h.ty)
    }

    /// 跳到当前结构的 `STRUCT_END` 头之后（含该头）。
    pub fn skip_to_struct_end(&mut self) -> Result<(), SliveError> {
        loop {
            let h = self.read_field_head()?;
            let is_end = h.ty == TarsType::StructEnd;
            self.skip_field_with_type(h.ty)?;
            if is_end {
                return Ok(());
            }
        }
    }

    /// 窥探当前位置的字段头（不推进游标）。
    pub(crate) fn peek_field_head(&self) -> Result<FieldHead, SliveError> {
        read_head(self.buf, self.pos).map(|(h, _)| h)
    }

    /// 字段头类型不符的标准错误（供 `decoder_read` 复用）。
    pub(crate) fn type_mismatch(tag: i32, actual: TarsType, expect: &str) -> SliveError {
        SliveError::decode(format!(
            "TARS 字段类型不符: tag={tag} 期望 {expect}，实为 {}",
            actual.as_str()
        ))
    }
}
