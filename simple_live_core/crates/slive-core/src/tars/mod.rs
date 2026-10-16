//! TARS 编解码模块（共享基础层）。
//!
//! 供 `platforms/huya`（TARS over WSS + TUP over HTTP）复用。
//! **依赖方向单向向下**：`platforms/*` -> `crate::tars` -> `crate::error`，
//! `crate::tars` 不依赖任何 `platforms` 模块。
//!
//! # 模块结构
//!
//! | 文件 | 职责 | 对应 Dart |
//! |------|------|-----------|
//! | [`endian`] | 字节序类型与运行时切换 | `dart:typed_data.Endian` |
//! | [`buffer`] | 裸读写缓冲（整型/浮点/字符串/bytes/数组） | `tup/write_buffer.dart` 的 `WriteBuffer`/`ReadBuffer` |
//! | [`stream`] | 字段类型枚举与字段头（tag/type）编解码 | `codec/tars_struct.dart` + `writeHead`/`readBinaryReaderHead` |
//! | [`encoder`] | 值编码引擎（按值域选宽、字符串/bytes/数组/Map/结构） | `codec/tars_output_stream.dart` |
//! | [`decoder`] | 解码引擎（按 tag 定位、跳字段） | `codec/tars_input_stream.dart` |
//! | [`decoder_read`] | 强类型字段读取扩展 | `TarsInputStream.read<T>` 系列 |
//! | [`value`] | 动态值枚举 | —（Dart 依赖 dynamic） |
//! | [`packet`] | `RequestPacket` / `TarsMessage` 封包 | `tup/request_packet.dart`、`tup/tars_message.dart` |
//! | [`uni_attribute`] | `UniAttribute` TUP 字段容器 | `tup/uni_attribute.dart` |
//! | [`uni_packet`] | `UniPacket` TUP 封包 | `tup/uni_packet.dart`、`tup/tars_uni_packet.dart` |
//! | [`consts`] | 协议常量与返回码键名 | `tup/const.dart` |
//!
//! # 快速上手
//!
//! 结构体定义推荐实现 [`TarsStruct`]：
//!
//! ```
//! use slive_core::tars::{TarsDecoder, TarsEncoder, TarsStruct};
//!
//! // `TarsStruct: Default` —— 解码跳未知字段时需要默认值兜底
//! #[derive(Default)]
//! struct HuyaPush {
//!     push_type: i32,
//!     uri: i32,
//!     msg: Vec<u8>,
//! }
//!
//! impl TarsStruct for HuyaPush {
//!     fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, slive_core::error::SliveError> {
//!         Ok(Self {
//!             push_type: d.read_i64_or(0, 0) as i32,
//!             uri: d.read_i64_or(1, 0) as i32,
//!             msg: d.read_bytes_or(2),
//!         })
//!     }
//!     fn write_to(&self, e: &mut TarsEncoder) -> Result<(), slive_core::error::SliveError> {
//!         e.write_i64(self.push_type as i64, 0)?;
//!         e.write_i64(self.uri as i64, 1)?;
//!         e.write_bytes(&self.msg, 2)?;
//!         Ok(())
//!     }
//! }
//!
//! let p = HuyaPush { push_type: 7, uri: 1400, msg: vec![1, 2, 3] };
//! let bytes = p.encode()?;
//! let got = HuyaPush::decode(&bytes)?;
//! assert_eq!(got.uri, 1400);
//! # Ok::<(), slive_core::error::SliveError>(())
//! ```
//!
//! # 关键兼容性约定
//!
//! 1. **字段头**：`(tag << 4) | type`；`tag >= 15` 追加 1 字节 tag；`tag > 255` 报错。
//! 2. **结束标记**：结构体以 `STRUCT_END`(type=11, tag=0) 结束。
//! 3. **零值**：`ZERO_TAG`(type=12) 表示值为 0 且不携带载荷字节。
//! 4. **字节序**：TARS 整型/浮点载荷恒大端；`Endian` 仅作用于 [`WriteBuffer`]/[`ReadBuffer`]。
//! 5. **无 panic**：越界/类型不符一律 `Err(SliveError::Decode)`。

pub mod buffer;
pub mod consts;
mod decoder;
pub mod decoder_read;
pub mod endian;
mod encoder;
mod packet;
pub mod stream;
mod uni_attribute;
mod uni_packet;
mod value;

pub use buffer::{ReadBuffer, WriteBuffer, TARS_MAX_STRING_LENGTH};
pub use decoder::TarsDecoder;
pub use endian::Endian;
pub use encoder::TarsEncoder;
pub use packet::{
    RequestPacket, TarsMessage, PACKET_TYPE_TARSNORMAL, PACKET_TYPE_TARSONEWAY,
    PACKET_TYPE_TUP, PACKET_TYPE_TUP3, UNI_PACKET_HEAD_SIZE,
};
pub use stream::{FieldHead, TarsType, MAX_TAG};
pub use uni_attribute::UniAttribute;
pub use uni_packet::UniPacket;
pub use value::TarsValue;

use crate::error::SliveError;

/// TARS 结构体：平台侧消息定义只需实现本 trait（对齐 Dart `TarsStruct` 的
/// `readFrom` / `writeTo`）。
///
/// `encode` 产出**完整结构体字节**（以 `STRUCT_BEGIN`(tag=0) 开头、`STRUCT_END` 结尾），
/// 可直接放进 `UniPacket::put` 的参数区或作为 `UniAttribute` 的字段值。
pub trait TarsStruct: Sized + Default {
    /// 从解码器读取字段（调用方已定位到本结构的 `STRUCT_BEGIN` 之后）。
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError>;

    /// 向编码器写入字段（**不含** `STRUCT_BEGIN`/`STRUCT_END`，由 `encode` 负责）。
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError>;

    /// 编码为完整结构体字节。
    fn encode(&self) -> Result<Vec<u8>, SliveError> {
        let mut e = TarsEncoder::new();
        e.write_struct_begin()?;
        self.write_to(&mut e)?;
        e.write_struct_end()?;
        Ok(e.into_bytes())
    }

    /// 从完整结构体字节解码（期望以 `STRUCT_BEGIN`(tag=0) 开头）。
    fn decode(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        d.read_struct(0, Self::read_from)
    }

    /// 从**裸字段区**解码（无 `STRUCT_BEGIN`/`STRUCT_END` 包裹）。
    ///
    /// 对齐 Dart 虎牙的实际用法：`HYMessage.readFrom(TarsInputStream(wSPushMessage.msg))`
    /// —— 直接对 payload 读字段，外层没有结构头。
    /// 若字节流确实是完整结构体（含 `STRUCT_BEGIN`），请用 [`TarsStruct::decode`]。
    fn decode_fields(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        Self::read_from(&mut d)
    }

    /// 从解码器的**当前位置**读字段（裸字段区语义），便于在已定位的流上复用。
    fn read_from_current(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Self::read_from(d)
    }
}

impl TarsEncoder {
    /// 写 `STRUCT_BEGIN` 头（tag=0）。
    pub fn write_struct_begin(&mut self) -> Result<(), SliveError> {
        self.write_struct_begin_at(0)
    }

    /// 写 `STRUCT_BEGIN` 头（指定 tag）。
    pub fn write_struct_begin_at(&mut self, tag: i32) -> Result<(), SliveError> {
        crate::tars::stream::write_head(self.as_mut_vec(), TarsType::StructBegin, tag)
    }

    /// 写 `STRUCT_END` 头（tag 恒为 0，对齐 Dart `writeHead(STRUCT_END, 0)`）。
    pub fn write_struct_end(&mut self) -> Result<(), SliveError> {
        crate::tars::stream::write_head(self.as_mut_vec(), TarsType::StructEnd, 0)
    }

    /// 写**嵌套结构体字段**：`STRUCT_BEGIN`(tag) + `write_body` + `STRUCT_END`。
    ///
    /// 这是平台侧在 `write_to` 里嵌子结构体的推荐写法 —— 读侧对应
    /// [`TarsDecoder::read_struct`]。不要用
    /// `write_bytes(&sub.encode()?, tag)` 代替：那会写成 `SIMPLE_LIST`，
    /// 与读侧 `read_struct` 期待的 `STRUCT_BEGIN` 不匹配。
    ///
    /// ```
    /// # use slive_core::tars::TarsEncoder;
    /// # fn demo(sub_write: impl FnOnce(&mut TarsEncoder) -> Result<(), slive_core::error::SliveError>)
    /// #     -> Result<(), slive_core::error::SliveError> {
    /// let mut e = TarsEncoder::new();
    /// e.write_nested_struct(0, sub_write)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_nested_struct<F>(&mut self, tag: i32, write_body: F) -> Result<(), SliveError>
    where
        F: FnOnce(&mut TarsEncoder) -> Result<(), SliveError>,
    {
        self.write_struct_begin_at(tag)?;
        write_body(self)?;
        self.write_struct_end()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Default, PartialEq)]
    struct Demo {
        a: i32,
        b: String,
        c: Vec<u8>,
    }

    impl TarsStruct for Demo {
        fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
            Ok(Self {
                a: d.read_i64_or(0, 0) as i32,
                b: d.read_string_or(1, ""),
                c: d.read_bytes_or(2),
            })
        }
        fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
            e.write_i64(self.a as i64, 0)?;
            e.write_string(&self.b, 1)?;
            e.write_bytes(&self.c, 2)?;
            Ok(())
        }
    }

    #[test]
    fn tars_struct_encode_decode_roundtrip() {
        let d = Demo {
            a: 7,
            b: "弹幕".into(),
            c: vec![1, 2, 3],
        };
        let bytes = d.encode().unwrap();
        // STRUCT_BEGIN(tag0)=0x0A ... STRUCT_END=0x0B
        assert_eq!(bytes[0], 0x0A);
        assert_eq!(*bytes.last().unwrap(), 0x0B);
        assert_eq!(Demo::decode(&bytes).unwrap(), d);
    }

    #[test]
    fn tars_struct_defaults_when_fields_missing() {
        let bytes = Demo::default().encode().unwrap();
        assert_eq!(Demo::decode(&bytes).unwrap(), Demo::default());
    }

    #[test]
    fn tars_struct_with_nested_struct_field() {
        #[derive(Debug, Default, PartialEq)]
        struct Outer {
            inner: Demo,
            n: i32,
        }
        impl TarsStruct for Outer {
            fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
                Ok(Self {
                    inner: d.read_struct(0, Demo::read_from)?,
                    n: d.read_i64_or(1, 0) as i32,
                })
            }
            fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
                e.write_nested_struct(0, |e| self.inner.write_to(e))?;
                e.write_i64(self.n as i64, 1)?;
                Ok(())
            }
        }
        let o = Outer {
            inner: Demo { a: 1, b: "x".into(), c: vec![7] },
            n: 3,
        };
        let bytes = o.encode().unwrap();
        assert_eq!(Outer::decode(&bytes).unwrap(), o);
    }

    #[test]
    fn public_surface_is_reachable() {
        // 冒烟：确认主要公开类型均可从 crate::tars 访问
        let _: Endian = Endian::Big;
        let mut e = TarsEncoder::new();
        e.write_i64(1, 0).unwrap();
        let bytes = e.into_bytes();
        let mut d = TarsDecoder::new(&bytes);
        assert_eq!(d.read_i64(0).unwrap(), 1);
        let _ = TarsType::Byte;
        let _ = MAX_TAG;
        let _ = TARS_MAX_STRING_LENGTH;
        let _ = PACKET_TYPE_TUP3;
        let _ = UNI_PACKET_HEAD_SIZE;
        let _ = UniPacket::new();
        let _ = UniAttribute::new_tup3();
        let _ = RequestPacket::new_tup3();
        let _ = TarsMessage::default();
        let _ = TarsValue::Int(1);
        let _ = FieldHead::new(0, TarsType::Byte);
        let _ = consts::STATUS_RESULT_CODE;
    }
}
