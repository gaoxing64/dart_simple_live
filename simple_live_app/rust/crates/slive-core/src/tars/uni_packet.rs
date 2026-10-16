//! TUP 封包 [`UniPacket`]（对照 Dart `tars_dart/lib/tars/tup/uni_packet.dart` 与
//! `tars_uni_packet.dart`）。
//!
//! # 编码布局
//!
//! ```text
//! | 0..4 | int32 大端：4 + body.len()（整包长度，对齐 Dart `putInt32(size + 4, Endian.big)`） |
//! | 4..  | body：header(STRUCT, tag=0) + params(MAP<String,bytes>, tag=1)               |
//! ```
//!
//! # 与 Dart 的差异
//!
//! - Dart `UniPacket.encode()` 在 `iVersion == PACKET_TYPE_TUP`（TUP2）时抛
//!   `UnimplementedError`（该库只实现 TUP3 编码）。本模块同样**只实现 TUP3 编码**，
//!   TUP2 请求返回 `Err`，不 panic。
//! - Dart 在 `sServantName` / `sFuncName` 为空时抛 `ArgumentError`；本模块返回
//!   `Err(SliveError::InvalidInput)`。

use crate::error::SliveError;

use super::decoder::TarsDecoder;
use super::encoder::TarsEncoder;
use super::packet::{RequestPacket, PACKET_TYPE_TUP, UNI_PACKET_HEAD_SIZE};
use super::uni_attribute::UniAttribute;

/// TUP 请求/响应封包（对齐 Dart `UniPacket` + `TarsUniPacket`）。
///
/// # 编码布局
///
/// ```text
/// | 0..4 | int32 大端：4 + body.len()（整包长度）                  |
/// | 4..  | body：TARSMap{ header(STRUCT) -> tag0,
///                          params(MAP<String,bytes>) -> tag1 }  |
/// ```
#[derive(Debug, Clone, PartialEq)]
pub struct UniPacket {
    /// 包头（`RequestPacket`）。
    pub package: RequestPacket,
    /// 参数区（TUP3 字段表）。
    pub attributes: UniAttribute,
}

impl Default for UniPacket {
    fn default() -> Self {
        Self::new()
    }
}

impl UniPacket {
    /// 构造 TUP3 请求包（对齐 Dart `TarsUniPacket()`）。
    pub fn new() -> Self {
        Self {
            package: RequestPacket::new_tup3(),
            attributes: UniAttribute::new_tup3(),
        }
    }

    /// 设置协议版本（同时写 `package.i_version` 与 attributes 版本）。
    pub fn set_version(&mut self, version: i32) {
        self.package.i_version = version;
        self.attributes.set_version(version);
    }

    /// 协议版本。
    pub fn version(&self) -> i32 {
        self.package.i_version
    }

    /// 设置服务名。
    pub fn set_servant_name(&mut self, v: &str) {
        self.package.s_servant_name = v.to_owned();
    }

    /// 服务名。
    pub fn servant_name(&self) -> &str {
        &self.package.s_servant_name
    }

    /// 设置函数名。
    pub fn set_func_name(&mut self, v: &str) {
        self.package.s_func_name = v.to_owned();
    }

    /// 函数名。
    pub fn func_name(&self) -> &str {
        &self.package.s_func_name
    }

    /// 设置请求序列号。
    pub fn set_request_id(&mut self, v: i32) {
        self.package.i_request_id = v;
    }

    /// 请求序列号。
    pub fn request_id(&self) -> i32 {
        self.package.i_request_id
    }

    /// 写入一个 TUP3 参数（结构体编码字节）。
    pub fn put(&mut self, name: &str, bytes: Vec<u8>) -> Result<(), SliveError> {
        self.attributes.put_bytes(name, bytes)
    }

    /// 编码整包（含 4 字节大端总长前缀）。
    ///
    /// 与 Dart 一致：`sServantName` / `sFuncName` 为空时直接返回 `Err`
    /// （Dart 抛 `ArgumentError`），本模块不 panic。
    pub fn encode(&self) -> Result<Vec<u8>, SliveError> {
        if self.package.s_servant_name.is_empty() {
            return Err(SliveError::invalid_input("TUP servantName 不能为空"));
        }
        if self.package.s_func_name.is_empty() {
            return Err(SliveError::invalid_input("TUP funcName 不能为空"));
        }
        if self.package.i_version == PACKET_TYPE_TUP {
            return Err(SliveError::invalid_input(
                "TUP2 编码未实现（对齐 Dart：TarsUniPacket 仅支持 TUP3）",
            ));
        }

        // 参数区字节 -> s_buffer（对齐 Dart：先 `_os.write(newData, 0)` 得 sBuffer，
        // 再把 sBuffer 装进 package 后整体写出）
        let params = self.attributes.encode()?;
        let mut package = self.package.clone();
        package.s_buffer = params;

        // body = RequestPacket 字段表（tag 1..10，**平铺、无 STRUCT_BEGIN 包裹**）
        // 对齐 Dart `UniPacket.encode()` -> `writeTo(_os)` -> `package.writeTo(_os)`：
        // Dart `RequestPacket.writeTo` 直接逐字段 `_os.write(field, tag)`，
        // 外层不再套 STRUCT_BEGIN/STRUCT_END。
        let mut e = TarsEncoder::new();
        package.write_fields_flat(&mut e)?;
        let body = e.into_bytes();

        let total = (body.len() + UNI_PACKET_HEAD_SIZE) as i32;
        let mut out = Vec::with_capacity(body.len() + UNI_PACKET_HEAD_SIZE);
        out.extend_from_slice(&total.to_be_bytes());
        out.extend_from_slice(&body);
        Ok(out)
    }

    /// 解码整包（`bytes` 起始处为 4 字节大端总长）。
    ///
    /// 对齐 Dart `UniPacket.decode`：跳过 4 字节头 -> 平铺读 `RequestPacket` 字段
    /// -> 再从 `s_buffer` 解析参数区。
    pub fn decode(bytes: &[u8]) -> Result<Self, SliveError> {
        if bytes.len() < UNI_PACKET_HEAD_SIZE {
            return Err(SliveError::decode(format!(
                "TUP 包长度不足：需 ≥{UNI_PACKET_HEAD_SIZE}，实际 {}",
                bytes.len()
            )));
        }
        // 头部 4 字节总长（大端）—— Dart `buffer.putInt32(size + 4, endian: Endian.big)`
        let _total_len = i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let body = &bytes[UNI_PACKET_HEAD_SIZE..];

        let mut d = TarsDecoder::new(body);
        let package = RequestPacket::read_fields_flat(&mut d)?;
        // 参数区另起解码器（对齐 Dart：`_is = TarsInputStream(package.sBuffer)`）
        let version = package.i_version;
        let mut attributes = UniAttribute::with_version(version);
        if !package.s_buffer.is_empty() {
            let mut pd = TarsDecoder::new(&package.s_buffer);
            for (k, v) in pd.read_str_bytes_map(0)? {
                attributes.new_data.insert(k, v);
            }
        }
        Ok(Self { package, attributes })
    }

    /// 读取 TUP3 返回码（对齐 Dart `respPack.get("", 0)`）。
    ///
    /// 参数区 `""` 键的字节内容是一段 TARS 编码的整型（tag=0 的字段），
    /// 故需按 tag=0 解出整型；缺失或解码失败返回 0。
    pub fn result_code(&self) -> i32 {
        let Some(bytes) = self.attributes.get_bytes("") else {
            return 0;
        };
        let mut d = TarsDecoder::new(bytes);
        d.read_i64(0).unwrap_or(0) as i32
    }

    /// 读取 TUP3 返回码（`RequestPacket.status` 的 `STATUS_RESULT_CODE`）。
    ///
    /// 服务端把返回码放在包头 `status` 里时用此方法；放在参数区 `""` 键时用
    /// [`UniPacket::result_code`]。缺失返回 0。
    pub fn result_code_from_status(&self) -> i32 {
        self.package.result_code()
    }

    /// 读取 TUP3 响应结构体字节（`"tRsp"` 键）。
    pub fn resp_bytes(&self) -> Option<&[u8]> {
        self.attributes.get_bytes("tRsp")
    }

    /// 读取 TUP3 请求结构体字节（`"tReq"` 键）。
    pub fn req_bytes(&self) -> Option<&[u8]> {
        self.attributes.get_bytes("tReq")
    }
}

#[cfg(test)]
mod tests {
    use super::super::packet::PACKET_TYPE_TUP3;
    use super::*;

    #[test]
    fn encode_decode_roundtrip() {
        let mut p = UniPacket::new();
        p.set_servant_name("Obj");
        p.set_func_name("getCdnToken");
        p.set_request_id(1);
        p.put("tReq", vec![1, 2]).unwrap();
        let bytes = p.encode().unwrap();

        // 前 4 字节是 int32 大端总长 = body + 4
        let total = i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        assert_eq!(total as usize, bytes.len());

        let got = UniPacket::decode(&bytes).unwrap();
        assert_eq!(got.servant_name(), "Obj");
        assert_eq!(got.func_name(), "getCdnToken");
        assert_eq!(got.request_id(), 1);
        assert_eq!(got.version(), PACKET_TYPE_TUP3);
        assert_eq!(got.req_bytes(), Some(&[1u8, 2][..]));
    }

    #[test]
    fn encode_requires_servant_and_func() {
        let mut p = UniPacket::new();
        assert!(p.encode().is_err(), "servantName 空应报错");
        p.set_servant_name("Obj");
        assert!(p.encode().is_err(), "funcName 空应报错");
    }

    #[test]
    fn tup2_encode_returns_error_not_panic() {
        let mut p = UniPacket::new();
        p.set_servant_name("Obj");
        p.set_func_name("f");
        p.set_version(PACKET_TYPE_TUP);
        assert!(p.encode().is_err());
    }

    #[test]
    fn decode_short_buffer_errors() {
        assert!(UniPacket::decode(&[0u8; 3]).is_err());
    }

    #[test]
    fn set_version_updates_both_places() {
        let mut p = UniPacket::new();
        p.set_version(PACKET_TYPE_TUP3);
        assert_eq!(p.package.i_version, PACKET_TYPE_TUP3);
        assert_eq!(p.attributes.version(), PACKET_TYPE_TUP3);
        assert_eq!(p.version(), PACKET_TYPE_TUP3);
    }

    #[test]
    fn result_code_reads_from_params_empty_key() {
        let mut inner = TarsEncoder::new();
        inner.write_i64(0, 0).unwrap();
        let mut p = UniPacket::new();
        p.attributes.put_bytes("", inner.into_bytes()).unwrap();
        assert_eq!(p.result_code(), 0);
        assert_eq!(p.result_code_from_status(), 0, "status 缺失时为 0");
    }
}
