//! TUP 属性容器 [`UniAttribute`]（对照 Dart `tars_dart/lib/tars/tup/uni_attribute.dart`）。
//!
//! # 与 Dart 的差异
//!
//! - Dart `UniAttribute.decode()` 先按 TUP2 试解、失败再按 TUP3 解（try/catch 探测版本）。
//!   本模块保留同样的「先试 TUP2 后试 TUP3」策略，但失败以 `Err` 返回，由调用方决定。
//! - Dart `get<T>(name, defaultObj)` 用 try/catch 把任何异常吞掉并返回默认值；
//!   本模块拆为 `get_value`（返回 `Result`）与 `get_or`（返回默认值），语义更明确。
//! - Dart 用两个 Map（`newData` / `oldData`）分别承载 TUP3 / TUP2 数据，本模块沿用该结构。

use std::collections::BTreeMap;

use crate::error::SliveError;

use super::decoder::TarsDecoder;
use super::encoder::TarsEncoder;
use super::packet::{PACKET_TYPE_TUP, PACKET_TYPE_TUP3};
use super::value::TarsValue;

/// TUP 属性容器（字段表 + 按名读写，对齐 Dart `UniAttribute`）。
///
/// 内部维护两个字段表：
/// - TUP3（`version == 3`）：`name -> bytes`，线上形态 `Map<String, SimpleList<BYTE>>`；
/// - TUP2（`version == 2`）：`name -> (type_name -> bytes)`，线上形态
///   `Map<String, Map<String, SimpleList<BYTE>>>`。
#[derive(Debug, Clone, PartialEq)]
pub struct UniAttribute {
    version: i32,
    /// TUP3 字段表。
    pub new_data: BTreeMap<String, Vec<u8>>,
    /// TUP2 字段表（含类型名层）。
    pub old_data: BTreeMap<String, BTreeMap<String, Vec<u8>>>,
}

impl Default for UniAttribute {
    fn default() -> Self {
        Self::new_tup3()
    }
}

impl UniAttribute {
    /// 构造 TUP3 容器（对齐 Dart `UniAttribute()` 默认 `version = PACKET_TYPE_TUP`，
    /// 但 `UniPacket()` 会强制置为 TUP3 —— 编码侧统一从 TUP3 起步）。
    pub fn new_tup3() -> Self {
        Self {
            version: PACKET_TYPE_TUP3,
            new_data: BTreeMap::new(),
            old_data: BTreeMap::new(),
        }
    }

    /// 构造指定版本的容器。
    pub fn with_version(version: i32) -> Self {
        Self {
            version,
            new_data: BTreeMap::new(),
            old_data: BTreeMap::new(),
        }
    }

    /// 当前版本（2=TUP2，3=TUP3）。
    pub fn version(&self) -> i32 {
        self.version
    }

    /// 设置版本（同时用于解码后记录服务端版本）。
    pub fn set_version(&mut self, version: i32) {
        self.version = version;
    }

    /// TUP2 版本下写字段（`type_name` 为 Dart `BasicClassTypeUtil.transTypeList` 的产物，如 `"string"`）。
    pub fn put_typed(&mut self, name: &str, type_name: &str, bytes: Vec<u8>) -> Result<(), SliveError> {
        if name.is_empty() {
            return Err(SliveError::invalid_input("TUP 字段名不能为空"));
        }
        let mut inner = BTreeMap::new();
        inner.insert(type_name.to_owned(), bytes);
        self.old_data.insert(name.to_owned(), inner);
        Ok(())
    }

    /// TUP3 版本下写字段（值为已编码的结构体字节）。
    pub fn put_bytes(&mut self, name: &str, bytes: Vec<u8>) -> Result<(), SliveError> {
        if name.is_empty() && self.version != PACKET_TYPE_TUP3 {
            return Err(SliveError::invalid_input("TUP2 字段名不能为空"));
        }
        self.new_data.insert(name.to_owned(), bytes);
        Ok(())
    }

    /// 取 TUP3 字段的原始字节。
    pub fn get_bytes(&self, name: &str) -> Option<&[u8]> {
        self.new_data.get(name).map(Vec::as_slice)
    }

    /// 取 TUP2 字段的原始字节（忽略类型名层）。
    pub fn get_typed_bytes(&self, name: &str) -> Option<&[u8]> {
        self.old_data
            .get(name)
            .and_then(|m| m.values().next())
            .map(Vec::as_slice)
    }

    /// 字段数量（按当前版本对应的表计）。
    pub fn len(&self) -> usize {
        if self.version == PACKET_TYPE_TUP3 {
            self.new_data.len()
        } else {
            self.old_data.len()
        }
    }

    /// 是否为空。
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// 编码当前版本的字段表（TUP2 -> `Map<String, Map<...>>`；TUP3 -> `Map<String, bytes>`）。
    ///
    /// 注意：Dart `UniAttribute.encode()` 写的是**裸 Map**（不含 `STRUCT_BEGIN` 外层），
    /// 因其使用者（`UniPacket`）会把它塞进 `sBuffer`。本模块保持一致。
    pub fn encode(&self) -> Result<Vec<u8>, SliveError> {
        let mut e = TarsEncoder::new();
        self.write_fields(&mut e, 0)?;
        Ok(e.into_bytes())
    }

    /// 按当前版本把字段表写入编码器（`tag` 为 Map 的字段头标签）。
    pub fn write_fields(&self, e: &mut TarsEncoder, tag: i32) -> Result<(), SliveError> {
        if self.version == PACKET_TYPE_TUP3 {
            e.write_str_map(&self.new_data, tag)
        } else {
            // TUP2：外层 key=字段名 -> 内层 Map{类型名 -> bytes}
            let entries: Vec<(TarsValue, TarsValue)> = self
                .old_data
                .iter()
                .map(|(name, inner)| {
                    let bytes: Vec<u8> = inner.values().next().cloned().unwrap_or_default();
                    let type_name = inner.keys().next().cloned().unwrap_or_default();
                    (
                        TarsValue::Str(name.clone()),
                        TarsValue::map(vec![(
                            TarsValue::Str(type_name),
                            TarsValue::Bytes(bytes),
                        )]),
                    )
                })
                .collect();
            e.write_map(&entries, tag)
        }
    }

    /// 从字节流解码字段表：先按 TUP2 试解，失败再按 TUP3（对齐 Dart 的版本探测策略）。
    ///
    /// `bytes` 起始处即为 `MAP` 字段头（tag 通常为 0）。
    pub fn decode(bytes: &[u8]) -> Result<Self, SliveError> {
        if let Ok(v) = Self::decode_tup2(bytes) {
            return Ok(v);
        }
        Self::decode_tup3(bytes)
    }

    /// 按 TUP3 解码字段表。
    pub fn decode_tup3(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        let new_data: BTreeMap<String, Vec<u8>> =
            d.read_str_bytes_map(0)?.into_iter().collect();
        Ok(Self {
            version: PACKET_TYPE_TUP3,
            new_data,
            old_data: BTreeMap::new(),
        })
    }

    /// 按 TUP2 解码字段表。
    pub fn decode_tup2(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        let raw = d.read_map(
            0,
            |d| d.read_string(0),
            |d| d.read_map(1, |d| d.read_string(0), |d| d.read_bytes(1)),
        )?;
        let mut old_data = BTreeMap::new();
        for (name, inner) in raw {
            let mut m = BTreeMap::new();
            for (tn, bytes) in inner {
                m.insert(tn, bytes);
            }
            old_data.insert(name, m);
        }
        Ok(Self {
            version: PACKET_TYPE_TUP,
            new_data: BTreeMap::new(),
            old_data,
        })
    }

    /// 动态读取 TUP3 字段的解码结果（内部是嵌套 TARS 值）。
    ///
    /// 对齐 Dart `UniAttribute.getByClass` 的通用读取：先按字段字节解出动态值。
    pub fn get_value(&self, name: &str) -> Result<TarsValue, SliveError> {
        let bytes = self
            .new_data
            .get(name)
            .or_else(|| self.old_data.get(name).and_then(|m| m.values().next()))
            .ok_or_else(|| {
                SliveError::decode(format!("TUP 字段不存在: {name}"))
            })?;
        // 字段字节本身是一段完整的 TARS 编码（结构体以 STRUCT_BEGIN 开头，tag=0）。
        let mut d = TarsDecoder::new(bytes);
        d.read_value(0)
    }

    /// 读取 TUP3 字段的解码结果，缺失/出错时返回默认值（对齐 Dart `get<T>(name, defaultObj)`）。
    pub fn get_or(&self, name: &str, default: TarsValue) -> TarsValue {
        self.get_value(name).unwrap_or(default)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tars::TarsEncoder;

    #[test]
    fn tup3_roundtrip() {
        let mut a = UniAttribute::new_tup3();
        a.put_bytes("tReq", vec![1, 2, 3]).unwrap();
        a.put_bytes("tRsp", vec![4]).unwrap();
        let bytes = a.encode().unwrap();
        let got = UniAttribute::decode(&bytes).unwrap();
        assert_eq!(got.version(), PACKET_TYPE_TUP3);
        assert_eq!(got.get_bytes("tReq"), Some(&[1u8, 2, 3][..]));
        assert_eq!(got.len(), 2);
        assert!(!got.is_empty());
    }

    #[test]
    fn tup2_roundtrip() {
        let mut a = UniAttribute::with_version(PACKET_TYPE_TUP);
        a.put_typed("f", "string", vec![9]).unwrap();
        let bytes = a.encode().unwrap();
        let got = UniAttribute::decode(&bytes).unwrap();
        assert_eq!(got.version(), PACKET_TYPE_TUP, "应识别为 TUP2");
        assert_eq!(got.get_typed_bytes("f"), Some(&[9u8][..]));
    }

    #[test]
    fn tup2_empty_name_rejected() {
        let mut a = UniAttribute::with_version(PACKET_TYPE_TUP);
        assert!(a.put_typed("", "string", vec![1]).is_err());
    }

    #[test]
    fn get_value_and_default() {
        let mut e = TarsEncoder::new();
        e.write_struct(&[(0, TarsValue::Int(42))], 0).unwrap();
        let mut a = UniAttribute::new_tup3();
        a.put_bytes("tRsp", e.into_bytes()).unwrap();
        assert_eq!(
            a.get_value("tRsp").unwrap().as_struct().map(|f| f.len()),
            Some(1)
        );
        assert_eq!(a.get_or("nope", TarsValue::Int(-1)), TarsValue::Int(-1));
    }

    #[test]
    fn version_accessors() {
        let mut a = UniAttribute::with_version(PACKET_TYPE_TUP);
        assert_eq!(a.version(), PACKET_TYPE_TUP);
        a.set_version(PACKET_TYPE_TUP3);
        assert_eq!(a.version(), PACKET_TYPE_TUP3);
        assert_eq!(UniAttribute::default().version(), PACKET_TYPE_TUP3);
    }
}
