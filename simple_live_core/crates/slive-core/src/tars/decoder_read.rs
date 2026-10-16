//! [`TarsDecoder`] 的强类型字段读取扩展（`impl` 续接）。
//!
//! 与 Dart `TarsInputStream.read<T>(data, tag, isRequire)` 一一对应：
//! - `read_i64(tag)` ~ Dart `readInt(tag, false)`
//! - `read_f64(tag)` ~ Dart `readFloat(tag, false)`
//! - `read_string(tag)` ~ Dart `readString(tag, false)`
//! - `read_bytes(tag)` ~ Dart `readBytes(tag, false)`
//! - `read_list` / `read_map` / `read_struct` ~ Dart 同名方法（元素类型由回调给出，
//!   取代 Dart 依赖「proxy 实例首个元素推断类型」的动态做法）。
//!
//! 缺失字段：`*` 版本返回 `Err`；`*_or` 版本返回调用方给定的默认值（对齐 Dart 的静默降级）。

use crate::error::SliveError;

use super::buffer::{check_string_len, decode_utf8};
use super::decoder::TarsDecoder;
use super::stream::TarsType;
use super::value::TarsValue;

impl<'a> TarsDecoder<'a> {
    /// 读 `tag` 处的整型字段；缺失或类型不符返回 `Err`。
    pub fn read_i64(&mut self, tag: i32) -> Result<i64, SliveError> {
        let h = self.locate(tag)?;
        if !h.ty.is_integral() {
            return Err(Self::type_mismatch(tag, h.ty, "整型"));
        }
        self.read_int_payload(h.ty)
    }

    /// 读 `tag` 处的整型字段，缺失/类型不符时返回 `default`。
    pub fn read_i64_or(&mut self, tag: i32, default: i64) -> i64 {
        self.read_i64(tag).unwrap_or(default)
    }

    /// 读 `tag` 处的浮点字段（`ZERO_TAG` 视为 0.0）。
    pub fn read_f64(&mut self, tag: i32) -> Result<f64, SliveError> {
        let h = self.locate(tag)?;
        match h.ty {
            TarsType::ZeroTag => Ok(0.0),
            TarsType::Float | TarsType::Double => self.read_float_payload(h.ty),
            other => Err(Self::type_mismatch(tag, other, "浮点")),
        }
    }

    /// 读 `tag` 处的浮点字段，缺失时返回 `default`。
    pub fn read_f64_or(&mut self, tag: i32, default: f64) -> f64 {
        self.read_f64(tag).unwrap_or(default)
    }

    /// 读 `tag` 处的布尔字段（非 0 为真）。
    pub fn read_bool(&mut self, tag: i32) -> Result<bool, SliveError> {
        Ok(self.read_i64(tag)? != 0)
    }

    /// 读 `tag` 处的布尔字段，缺失时返回 `default`。
    pub fn read_bool_or(&mut self, tag: i32, default: bool) -> bool {
        self.read_bool(tag).unwrap_or(default)
    }

    /// 读 `tag` 处的字符串字段（`STRING1`/`STRING4`；`ZERO_TAG` 视为空串）。
    pub fn read_string(&mut self, tag: i32) -> Result<String, SliveError> {
        let h = self.locate(tag)?;
        match h.ty {
            TarsType::ZeroTag => Ok(String::new()),
            TarsType::String1 => {
                let n = self.read_raw_u8()? as i32;
                let s = self.read_raw_bytes(check_string_len(n)?)?;
                decode_utf8(s, "STRING1")
            }
            TarsType::String4 => {
                let n = self.read_raw_i32()?;
                let s = self.read_raw_bytes(check_string_len(n)?)?;
                decode_utf8(s, "STRING4")
            }
            other => Err(Self::type_mismatch(tag, other, "字符串")),
        }
    }

    /// 读 `tag` 处的字符串字段，缺失时返回 `default`。
    pub fn read_string_or(&mut self, tag: i32, default: &str) -> String {
        self.read_string(tag).unwrap_or_else(|_| default.to_owned())
    }

    /// 读 `tag` 处的 bytes 字段（`SIMPLE_LIST`；亦兼容 Dart 支持的 `LIST` of int 形态）。
    pub fn read_bytes(&mut self, tag: i32) -> Result<Vec<u8>, SliveError> {
        let h = self.locate(tag)?;
        match h.ty {
            TarsType::ZeroTag => Ok(Vec::new()),
            TarsType::SimpleList => {
                let inner = self.read_field_head()?;
                if inner.ty != TarsType::Byte {
                    return Err(Self::type_mismatch(
                        tag,
                        inner.ty,
                        "SIMPLE_LIST 内层 BYTE",
                    ));
                }
                let size = self.read_len_field()?;
                Ok(self.read_raw_bytes(size)?.to_vec())
            }
            // 对齐 Dart `readBytes` 的 LIST 分支：元素逐个读整型再截断为 u8。
            TarsType::List => {
                let size = self.read_len_field()?;
                let mut out = Vec::with_capacity(size.min(4096));
                for i in 0..size {
                    let eh = self.read_field_head()?;
                    let v = self.read_int_payload(eh.ty)?;
                    if !(0..=255).contains(&v) {
                        return Err(SliveError::decode(format!(
                            "TARS LIST 第 {i} 项 {v} 超出 byte 范围"
                        )));
                    }
                    out.push(v as u8);
                }
                Ok(out)
            }
            other => Err(Self::type_mismatch(tag, other, "bytes")),
        }
    }

    /// 读 `tag` 处的 bytes 字段，缺失时返回空 `Vec`（对齐 Dart `readBytes` 缺省行为）。
    pub fn read_bytes_or(&mut self, tag: i32) -> Vec<u8> {
        self.read_bytes(tag).unwrap_or_default()
    }

    /// 读 `tag` 处的列表字段。`read_elem` 收到的解码器已定位在元素字段头之前，
    /// 元素在线上 tag 恒为 0，故回调内一般用 `read_i64(0)` / `read_string(0)` 等。
    pub fn read_list<T, F>(&mut self, tag: i32, mut read_elem: F) -> Result<Vec<T>, SliveError>
    where
        F: FnMut(&mut TarsDecoder<'a>) -> Result<T, SliveError>,
    {
        let h = self.locate(tag)?;
        if h.ty != TarsType::List {
            return Err(Self::type_mismatch(tag, h.ty, "列表"));
        }
        let size = self.read_len_field()?;
        let mut out = Vec::with_capacity(size.min(4096));
        for _ in 0..size {
            out.push(read_elem(self)?);
        }
        Ok(out)
    }

    /// 读 `tag` 处的结构体字段：定位 `STRUCT_BEGIN` 后把解码器交给 `read_body`，
    /// 回调返回后自动跳到 `STRUCT_END`（对齐 Dart `readTarsStruct` 的 `skipToStructEnd`）。
    pub fn read_struct<T, F>(&mut self, tag: i32, read_body: F) -> Result<T, SliveError>
    where
        F: FnOnce(&mut TarsDecoder<'a>) -> Result<T, SliveError>,
    {
        let h = self.locate(tag)?;
        if h.ty != TarsType::StructBegin {
            return Err(Self::type_mismatch(tag, h.ty, "结构体"));
        }
        let v = read_body(self)?;
        self.skip_to_struct_end()?;
        Ok(v)
    }

    /// 读 `tag` 处的 Map：返回 `(key, value)` 序列，保持线上顺序。
    /// key 线上 tag 恒为 0、value 恒为 1（对齐 Dart `readMap`）。
    pub fn read_map<K, V, FK, FV>(
        &mut self,
        tag: i32,
        mut read_key: FK,
        mut read_val: FV,
    ) -> Result<Vec<(K, V)>, SliveError>
    where
        FK: FnMut(&mut TarsDecoder<'a>) -> Result<K, SliveError>,
        FV: FnMut(&mut TarsDecoder<'a>) -> Result<V, SliveError>,
    {
        let h = self.locate(tag)?;
        if h.ty != TarsType::Map {
            return Err(Self::type_mismatch(tag, h.ty, "Map"));
        }
        let size = self.read_len_field()?;
        let mut out = Vec::with_capacity(size.min(4096));
        for _ in 0..size {
            let k = read_key(self)?;
            let v = read_val(self)?;
            out.push((k, v));
        }
        Ok(out)
    }

    /// 读 `tag` 处的「字符串 -> bytes」Map（虎牙 TUP 响应 `tRsp` 容器的形态）。
    pub fn read_str_bytes_map(&mut self, tag: i32) -> Result<Vec<(String, Vec<u8>)>, SliveError> {
        self.read_map(tag, |d| d.read_string(0), |d| d.read_bytes(1))
    }

    /// 读 `tag` 处的「字符串 -> 字符串」Map（`RequestPacket.context` / `status` 的形态）。
    pub fn read_str_str_map(&mut self, tag: i32) -> Result<Vec<(String, String)>, SliveError> {
        self.read_map(tag, |d| d.read_string(0), |d| d.read_string(1))
    }

    /// 读 `tag` 处的动态值：按线上类型字节自动判定形态，无需预先知道字段类型。
    ///
    /// 供「协议字段会变、需容错」的通道使用（如虎牙 TUP 的 `tRsp` 内部结构）。
    pub fn read_value(&mut self, tag: i32) -> Result<TarsValue, SliveError> {
        let h = self.locate(tag)?;
        match h.ty {
            TarsType::ZeroTag => Ok(TarsValue::Int(0)),
            TarsType::Byte | TarsType::Short | TarsType::Int | TarsType::Long => {
                Ok(TarsValue::Int(self.read_int_payload(h.ty)?))
            }
            TarsType::Float | TarsType::Double => {
                Ok(TarsValue::Double(self.read_float_payload(h.ty)?))
            }
            TarsType::String1 | TarsType::String4 => {
                let n = if h.ty == TarsType::String1 {
                    self.read_raw_u8()? as i32
                } else {
                    self.read_raw_i32()?
                };
                let s = self.read_raw_bytes(check_string_len(n)?)?;
                Ok(TarsValue::Str(decode_utf8(s, "STRING")?))
            }
            TarsType::SimpleList => {
                let inner = self.read_field_head()?;
                if inner.ty != TarsType::Byte {
                    return Err(Self::type_mismatch(
                        tag,
                        inner.ty,
                        "SIMPLE_LIST 内层 BYTE",
                    ));
                }
                let size = self.read_len_field()?;
                Ok(TarsValue::Bytes(self.read_raw_bytes(size)?.to_vec()))
            }
            TarsType::List => {
                let size = self.read_len_field()?;
                let mut out = Vec::with_capacity(size.min(4096));
                for _ in 0..size {
                    out.push(self.read_value(0)?);
                }
                Ok(TarsValue::List(out))
            }
            TarsType::Map => {
                let size = self.read_len_field()?;
                let mut out = Vec::with_capacity(size.min(4096));
                for _ in 0..size {
                    let k = self.read_value(0)?;
                    let v = self.read_value(1)?;
                    out.push((k, v));
                }
                Ok(TarsValue::Map(out))
            }
            TarsType::StructBegin => {
                // 子字段逐个读；遇 STRUCT_END 结束。
                // 注意：`peek_field_head` **不推进游标**，故此处不可 rewind ——
                // 直接让 `read_value` 走完整 `locate`（此时游标本就停在该子字段头上）。
                let mut fields: Vec<(i32, TarsValue)> = Vec::new();
                loop {
                    let probe = self.peek_field_head()?;
                    if probe.ty == TarsType::StructEnd {
                        break;
                    }
                    fields.push((probe.tag, self.read_value(probe.tag)?));
                }
                // 消费 STRUCT_END 头
                self.skip_to_struct_end()?;
                Ok(TarsValue::Struct(fields))
            }
            TarsType::StructEnd => Err(SliveError::decode(
                "TARS 字段为 STRUCT_END，无值可读（字段表已结束）",
            )),
        }
    }
}
