//! TUP 封包层：[`RequestPacket`] / [`TarsMessage`] / [`UniAttribute`] / [`UniPacket`]。
//!
//! 对照 Dart：
//! - `tars_dart/lib/tars/tup/request_packet.dart`
//! - `tars_dart/lib/tars/tup/tars_message.dart`
//! - `tars_dart/lib/tars/tup/uni_attribute.dart`
//! - `tars_dart/lib/tars/tup/uni_packet.dart` / `tars_uni_packet.dart`
//!
//! # 封包结构
//!
//! [`UniPacket`] 的字节布局：
//!
//! ```text
//! | 0..4   | int32 大端：body 长度 + 4（kUniPacketHeadSize），即整个包的总长度 |
//! | 4..    | body：RequestPacket 字段表（STRUCT_BEGIN ... STRUCT_END）      |
//! ```
//!
//! `RequestPacket.s_buffer` 内是「参数区」：TUP3 版本下为 `Map<String, bytes>`
//! （`MAP` 头，键为 `"tReq"`/`"tRsp"`/`""`，值为各结构体的编码字节）。
//!
//! # 版本常量
//!
//! [`PACKET_TYPE_TARSNORMAL`]=0 / [`PACKET_TYPE_TARSONEWAY`]=1 /
//! [`PACKET_TYPE_TUP`]=2 / [`PACKET_TYPE_TUP3`]=3（对齐 Dart `tup/const.dart`）。

use std::collections::BTreeMap;

use crate::error::SliveError;

use super::decoder::TarsDecoder;
use super::encoder::TarsEncoder;
use super::value::TarsValue;

/// 正常包（对齐 `Const.PACKET_TYPE_TARSNORMAL`）。
pub const PACKET_TYPE_TARSNORMAL: i32 = 0;
/// 单向包（对齐 `Const.PACKET_TYPE_TARSONEWAY`）。
pub const PACKET_TYPE_TARSONEWAY: i32 = 1;
/// TUP2（对齐 `Const.PACKET_TYPE_TUP`）。
pub const PACKET_TYPE_TUP: i32 = 2;
/// TUP3（对齐 `Const.PACKET_TYPE_TUP3`）。
pub const PACKET_TYPE_TUP3: i32 = 3;

/// `UniPacket` 的固定头长度：4 字节包总长（对齐 Dart `kUniPacketHeadSize`）。
pub const UNI_PACKET_HEAD_SIZE: usize = 4;

/// 把 `Vec<(String, String)>` 转成 `TarsValue` 的字符串 Map 条目
/// （对齐 Dart `Map<String,String>`：键值都走 `writeString`）。
pub(crate) fn pairs_to_tars_map(
    pairs: &[(String, String)],
) -> Vec<(super::value::TarsValue, super::value::TarsValue)> {
    pairs
        .iter()
        .map(|(k, v)| {
            (
                super::value::TarsValue::Str(k.clone()),
                super::value::TarsValue::Str(v.clone()),
            )
        })
        .collect()
}

/// `RequestPacket`（对齐 Dart `tup/request_packet.dart`）。
///
/// tag 布局：`iVersion`=1、`cPacketType`=2、`iMessageType`=3、`iRequestId`=4、
/// `sServantName`=5、`sFuncName`=6、`sBuffer`=7、`iTimeout`=8、`context`=9、`status`=10。
#[derive(Debug, Clone, Default, PartialEq)]
pub struct RequestPacket {
    /// 协议版本（TUP3 为 3）。
    pub i_version: i32,
    /// 包类型（0=正常，1=单向）。
    pub c_packet_type: i32,
    /// 消息类型。
    pub i_message_type: i32,
    /// 请求序列号。
    pub i_request_id: i32,
    /// 服务名（servant）。
    pub s_servant_name: String,
    /// 函数名（method）。
    pub s_func_name: String,
    /// 参数区字节（TUP3 下为 `Map<String, bytes>` 的编码）。
    pub s_buffer: Vec<u8>,
    /// 超时（毫秒）。
    pub i_timeout: i32,
    /// 上下文（键值对，保持线上顺序）。
    pub context: Vec<(String, String)>,
    /// 状态（键值对；`STATUS_RESULT_CODE` 在此）。
    pub status: Vec<(String, String)>,
}

impl RequestPacket {
    /// 构造 TUP3 请求包骨架（对齐 Dart `TarsUniPacket()` 构造：version=3、packetType=0、
    /// `sBuffer` 初值 `[0x0]`、context/status 为空 Map）。
    pub fn new_tup3() -> Self {
        Self {
            i_version: PACKET_TYPE_TUP3,
            c_packet_type: PACKET_TYPE_TARSNORMAL,
            i_message_type: 0,
            i_request_id: 0,
            s_servant_name: String::new(),
            s_func_name: String::new(),
            // Dart `RequestPacket.cache_sBuffer = Uint8List.fromList([0x0])`
            s_buffer: vec![0u8],
            i_timeout: 0,
            context: Vec::new(),
            status: Vec::new(),
        }
    }

    /// 编码字段表（`STRUCT_BEGIN` ... `STRUCT_END`，不含外层 tag 头）。
    pub fn encode(&self) -> Result<Vec<u8>, SliveError> {
        let mut e = TarsEncoder::new();
        e.write_struct(&self.to_fields(), 0)?;
        Ok(e.into_bytes())
    }

    /// 字段表（供 [`TarsValue::Struct`] 与调试）。
    pub fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        let ctx: Vec<(TarsValue, TarsValue)> = self
            .context
            .iter()
            .map(|(k, v)| (TarsValue::Str(k.clone()), TarsValue::Str(v.clone())))
            .collect();
        let st: Vec<(TarsValue, TarsValue)> = self
            .status
            .iter()
            .map(|(k, v)| (TarsValue::Str(k.clone()), TarsValue::Str(v.clone())))
            .collect();
        vec![
            (1, TarsValue::Int(self.i_version as i64)),
            (2, TarsValue::Int(self.c_packet_type as i64)),
            (3, TarsValue::Int(self.i_message_type as i64)),
            (4, TarsValue::Int(self.i_request_id as i64)),
            (5, TarsValue::Str(self.s_servant_name.clone())),
            (6, TarsValue::Str(self.s_func_name.clone())),
            (7, TarsValue::Bytes(self.s_buffer.clone())),
            (8, TarsValue::Int(self.i_timeout as i64)),
            (9, TarsValue::Map(ctx)),
            (10, TarsValue::Map(st)),
        ]
    }

    /// 从字节流解码（`bytes` 起始处即为 `STRUCT_BEGIN`）。
    pub fn decode(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        d.read_struct(0, Self::read_fields)
    }

    /// 从解码器读取字段表（**调用方已定位到 `STRUCT_BEGIN` 之后**）。
    pub(crate) fn read_fields(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            i_version: d.read_i64_or(1, 0) as i32,
            c_packet_type: d.read_i64_or(2, 0) as i32,
            i_message_type: d.read_i64_or(3, 0) as i32,
            i_request_id: d.read_i64_or(4, 0) as i32,
            s_servant_name: d.read_string_or(5, ""),
            s_func_name: d.read_string_or(6, ""),
            s_buffer: d.read_bytes_or(7),
            i_timeout: d.read_i64_or(8, 0) as i32,
            context: d.read_str_str_map(9).unwrap_or_default(),
            status: d.read_str_str_map(10).unwrap_or_default(),
        })
    }

    /// 把字段表**平铺**写入编码器（tag 1..10，**不套** `STRUCT_BEGIN`/`STRUCT_END`）。
    ///
    /// 对齐 Dart `RequestPacket.writeTo`：逐字段 `_os.write(field, tag)`，外层无结构包裹。
    /// [`UniPacket`](super::UniPacket) 的包体正是这种平铺形态（与 `TarsMessage` 的
    /// `STRUCT_BEGIN` 包裹形态不同，两者不可混用）。
    pub(crate) fn write_fields_flat(
        &self,
        e: &mut TarsEncoder,
    ) -> Result<(), SliveError> {
        e.write_i64(self.i_version as i64, 1)?;
        e.write_i64(self.c_packet_type as i64, 2)?;
        e.write_i64(self.i_message_type as i64, 3)?;
        e.write_i64(self.i_request_id as i64, 4)?;
        e.write_string(&self.s_servant_name, 5)?;
        e.write_string(&self.s_func_name, 6)?;
        e.write_bytes(&self.s_buffer, 7)?;
        e.write_i64(self.i_timeout as i64, 8)?;
        // Dart `context` / `status` 是 `Map<String,String>` -> 键值都走 writeString，
        // 故此处必须用字符串 Map；读侧 `read_str_str_map` 才对得上。
        e.write_map(&pairs_to_tars_map(&self.context), 9)?;
        e.write_map(&pairs_to_tars_map(&self.status), 10)?;
        Ok(())
    }

    /// 从解码器**平铺**读取字段表（跳过 tag 小于 1 的字段，容忍额外头部字节）。
    pub(crate) fn read_fields_flat(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Self::read_fields(d)
    }

    /// 从 `status` 中取 TUP 返回码（`STATUS_RESULT_CODE`，缺失或非法则 0）。
    ///
    /// 对齐 Dart `TarsUniPacket.getTarsResultCode`。
    pub fn result_code(&self) -> i32 {
        self.status
            .iter()
            .find(|(k, _)| k == super::consts::STATUS_RESULT_CODE)
            .and_then(|(_, v)| v.parse::<i32>().ok())
            .unwrap_or(0)
    }

    /// 从 `status` 中取 TUP 返回描述（`STATUS_RESULT_DESC`，缺失则空串）。
    pub fn result_desc(&self) -> String {
        self.status
            .iter()
            .find(|(k, _)| k == super::consts::STATUS_RESULT_DESC)
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    }
}

/// 完整 TARS 消息：`RequestPacket` 头 + `Map<String, bytes>` 消息体
/// （对齐 Dart `tup/tars_message.dart`）。
///
/// `header` 为 tag=0 的结构体，`body` 为 tag=1 的 Map。
#[derive(Debug, Clone, Default, PartialEq)]
pub struct TarsMessage {
    /// 包头。
    pub header: RequestPacket,
    /// 消息体：`"tReq"` -> 请求结构体字节；`"tRsp"` -> 响应结构体字节。
    pub body: BTreeMap<String, Vec<u8>>,
}

impl TarsMessage {
    /// 编码（`header` 结构体 + `body` Map）。
    pub fn encode(&self) -> Result<Vec<u8>, SliveError> {
        let mut e = TarsEncoder::new();
        e.write_struct(&self.header.to_fields(), 0)?;
        e.write_str_map(&self.body, 1)?;
        Ok(e.into_bytes())
    }

    /// 解码。
    pub fn decode(bytes: &[u8]) -> Result<Self, SliveError> {
        let mut d = TarsDecoder::new(bytes);
        let header = d.read_struct(0, |d| {
            Ok(RequestPacket {
                i_version: d.read_i64_or(1, 0) as i32,
                c_packet_type: d.read_i64_or(2, 0) as i32,
                i_message_type: d.read_i64_or(3, 0) as i32,
                i_request_id: d.read_i64_or(4, 0) as i32,
                s_servant_name: d.read_string_or(5, ""),
                s_func_name: d.read_string_or(6, ""),
                s_buffer: d.read_bytes_or(7),
                i_timeout: d.read_i64_or(8, 0) as i32,
                context: d.read_str_str_map(9).unwrap_or_default(),
                status: d.read_str_str_map(10).unwrap_or_default(),
            })
        })?;
        let body: BTreeMap<String, Vec<u8>> = d.read_str_bytes_map(1)?.into_iter().collect();
        Ok(Self { header, body })
    }

    /// 取 body 中的结构体字节（不存在返回空 `Vec`）。
    pub fn get(&self, key: &str) -> &[u8] {
        self.body.get(key).map(Vec::as_slice).unwrap_or(&[])
    }
}
#[cfg(test)]
#[path = "packet_tests.rs"]
mod tests;
