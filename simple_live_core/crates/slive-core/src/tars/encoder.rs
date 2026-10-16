//! TARS 编码器 [`TarsEncoder`]（对照 Dart `tars_dart/lib/tars/codec/tars_output_stream.dart`）。
//!
//! # 与 Dart 的字节级对应
//!
//! | 操作 | Dart | 本模块 |
//! |------|------|--------|
//! | 整型 | `writeInt` 按值域选 BYTE/SHORT/INT/LONG；值为 0 时只写 `ZERO_TAG` 头 | [`TarsEncoder::write_i64`] 同 |
//! | 布尔 | `writeBool` -> `writeByte` | [`TarsEncoder::write_bool`] 同 |
//! | 浮点 | `writeFloat`(4B) / `writeDouble`(8B) | [`TarsEncoder::write_f32`] / [`TarsEncoder::write_f64`] 同 |
//! | 字符串 | 空串写 `STRING1`+0；UTF-8 字节数 <=255 走 `STRING1`，否则 `STRING4` | [`TarsEncoder::write_string`] 同 |
//! | bytes | `SIMPLE_LIST` 头 + `BYTE` 头(tag=0) + 长度 + 数据 | [`TarsEncoder::write_bytes`] 同 |
//! | 数组 | `LIST` 头 + 长度 + 元素（元素 tag 恒 0） | [`TarsEncoder::write_list`] 同 |
//! | Map | `MAP` 头 + 条数 + key(tag=0)/value(tag=1) | [`TarsEncoder::write_map`] 同 |
//! | 结构 | `STRUCT_BEGIN` + 字段表 + `STRUCT_END`(tag=0) | [`TarsEncoder::write_struct`] 同 |
//!
//! 所有整型 / 浮点载荷**恒为大端**（对齐 Dart 硬编码 `Endian.big`）。

use std::collections::BTreeMap;

use crate::error::SliveError;

use super::buffer::TARS_MAX_STRING_LENGTH;
use super::stream::{write_head, TarsType};
use super::value::TarsValue;

/// TARS 编码器（写方向），底层为 `Vec<u8>`。
#[derive(Debug, Clone, Default)]
pub struct TarsEncoder {
    buf: Vec<u8>,
}

impl TarsEncoder {
    /// 新建编码器。
    pub fn new() -> Self {
        Self {
            buf: Vec::with_capacity(256),
        }
    }

    /// 取走已编码字节。
    pub fn into_bytes(self) -> Vec<u8> {
        self.buf
    }

    /// 已编码字节数。
    pub fn len(&self) -> usize {
        self.buf.len()
    }

    /// 是否为空。
    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }

    /// 借阅已编码内容。
    pub fn as_slice(&self) -> &[u8] {
        &self.buf
    }

    /// 可变借阅底层缓冲（供 [`crate::tars::TarsStruct`] 实现写 `STRUCT_BEGIN`/`STRUCT_END` 等标记头）。
    pub fn as_mut_vec(&mut self) -> &mut Vec<u8> {
        &mut self.buf
    }

    /// 写整型：按值域选 `BYTE`/`SHORT`/`INT`/`LONG`；值为 0 时只写 `ZERO_TAG`（对齐 Dart `writeInt`/`writeByte`）。
    pub fn write_i64(&mut self, value: i64, tag: i32) -> Result<(), SliveError> {
        if (-128..=127).contains(&value) {
            return self.write_byte_raw(value, tag);
        }
        if (-32768..=32767).contains(&value) {
            write_head(&mut self.buf, TarsType::Short, tag)?;
            self.buf.extend_from_slice(&(value as i16).to_be_bytes());
            return Ok(());
        }
        if (-2147483648..=2147483647).contains(&value) {
            write_head(&mut self.buf, TarsType::Int, tag)?;
            self.buf.extend_from_slice(&(value as i32).to_be_bytes());
            return Ok(());
        }
        write_head(&mut self.buf, TarsType::Long, tag)?;
        self.buf.extend_from_slice(&value.to_be_bytes());
        Ok(())
    }

    /// 写 1 字节整型；值为 0 时写 `ZERO_TAG` 且不带载荷（对齐 Dart `writeByte`）。
    ///
    /// 注意：TARS `BYTE` 按无符号语义读取（对齐 Dart `getUint8` / 官方 C++ `unsigned char`），
    /// 因此**负数不应写入本路径**，负数请改用 `write_i64` 的 SHORT/INT/LONG 分支。
    fn write_byte_raw(&mut self, value: i64, tag: i32) -> Result<(), SliveError> {
        if value == 0 {
            write_head(&mut self.buf, TarsType::ZeroTag, tag)?;
            return Ok(());
        }
        write_head(&mut self.buf, TarsType::Byte, tag)?;
        self.buf.push((value as u64 & 0xFF) as u8);
        Ok(())
    }

    /// 写布尔（对齐 Dart `writeBool` -> `writeByte`）。
    pub fn write_bool(&mut self, value: bool, tag: i32) -> Result<(), SliveError> {
        self.write_byte_raw(i64::from(value), tag)
    }

    /// 写 f32（`FLOAT`，4 字节大端）。
    pub fn write_f32(&mut self, value: f32, tag: i32) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::Float, tag)?;
        self.buf.extend_from_slice(&value.to_be_bytes());
        Ok(())
    }

    /// 写 f64（`DOUBLE`，8 字节大端）。
    pub fn write_f64(&mut self, value: f64, tag: i32) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::Double, tag)?;
        self.buf.extend_from_slice(&value.to_be_bytes());
        Ok(())
    }

    /// 写字符串：空串 -> `STRING1` + 长度 0；UTF-8 字节数 <=255 -> `STRING1`；否则 `STRING4`
    /// （对齐 Dart `writeString`，长度按 **UTF-8 字节数** 而非 char 数）。
    pub fn write_string(&mut self, value: &str, tag: i32) -> Result<(), SliveError> {
        let bytes = value.as_bytes();
        if bytes.is_empty() {
            write_head(&mut self.buf, TarsType::String1, tag)?;
            self.buf.push(0);
            return Ok(());
        }
        if bytes.len() <= 255 {
            write_head(&mut self.buf, TarsType::String1, tag)?;
            self.buf.push(bytes.len() as u8);
            self.buf.extend_from_slice(bytes);
            return Ok(());
        }
        if bytes.len() > TARS_MAX_STRING_LENGTH {
            return Err(SliveError::invalid_input(format!(
                "TARS 字符串过长: {} 字节 > {TARS_MAX_STRING_LENGTH}",
                bytes.len()
            )));
        }
        write_head(&mut self.buf, TarsType::String4, tag)?;
        self.buf
            .extend_from_slice(&(bytes.len() as i32).to_be_bytes());
        self.buf.extend_from_slice(bytes);
        Ok(())
    }

    /// 写 bytes（`SIMPLE_LIST` + `BYTE` 头(tag=0) + 长度 + 数据，对齐 Dart `writeUint8List`）。
    pub fn write_bytes(&mut self, value: &[u8], tag: i32) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::SimpleList, tag)?;
        write_head(&mut self.buf, TarsType::Byte, 0)?;
        self.write_i64(value.len() as i64, 0)?;
        self.buf.extend_from_slice(value);
        Ok(())
    }

    /// 写列表（`LIST` + 长度 + 元素序列，元素 tag 恒为 0）。
    pub fn write_list(&mut self, items: &[TarsValue], tag: i32) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::List, tag)?;
        self.write_i64(items.len() as i64, 0)?;
        for it in items {
            self.write_value(it, 0)?;
        }
        Ok(())
    }

    /// 写 Map（`MAP` + 条数 + key(tag=0)/value(tag=1) 交替）。
    pub fn write_map(
        &mut self,
        entries: &[(TarsValue, TarsValue)],
        tag: i32,
    ) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::Map, tag)?;
        self.write_i64(entries.len() as i64, 0)?;
        for (k, v) in entries {
            self.write_value(k, 0)?;
            self.write_value(v, 1)?;
        }
        Ok(())
    }

    /// 写「字符串键 -> 字节值」的 Map。
    ///
    /// 使用 `BTreeMap` 保证键序确定（对齐 Dart `LinkedHashMap` 的插入序不一致，此处取更利于对拍的
    /// 确定序；虎牙/斗鱼协议均不依赖 Map 的键序）。
    pub fn write_str_map(
        &mut self,
        m: &BTreeMap<String, Vec<u8>>,
        tag: i32,
    ) -> Result<(), SliveError> {
        let entries: Vec<(TarsValue, TarsValue)> = m
            .iter()
            .map(|(k, v)| (TarsValue::Str(k.clone()), TarsValue::Bytes(v.clone())))
            .collect();
        self.write_map(&entries, tag)
    }

    /// 写结构体字段表：`STRUCT_BEGIN` + 各字段 + `STRUCT_END`(tag=0)。
    pub fn write_struct(
        &mut self,
        fields: &[(i32, TarsValue)],
        tag: i32,
    ) -> Result<(), SliveError> {
        write_head(&mut self.buf, TarsType::StructBegin, tag)?;
        for (ftag, v) in fields {
            self.write_value(v, *ftag)?;
        }
        write_head(&mut self.buf, TarsType::StructEnd, 0)?;
        Ok(())
    }

    /// 按值形态分派写单个值（对齐 Dart `write(dynamic, tag)`）。
    pub fn write_value(&mut self, value: &TarsValue, tag: i32) -> Result<(), SliveError> {
        match value {
            TarsValue::Int(v) => self.write_i64(*v, tag),
            TarsValue::Double(v) => self.write_f64(*v, tag),
            TarsValue::Bool(v) => self.write_bool(*v, tag),
            TarsValue::Str(v) => self.write_string(v, tag),
            TarsValue::Bytes(v) => self.write_bytes(v, tag),
            TarsValue::List(v) => self.write_list(v, tag),
            TarsValue::Map(v) => self.write_map(v, tag),
            TarsValue::Struct(v) => self.write_struct(v, tag),
        }
    }
}
