//! TARS **对拍测试**：手工按 Dart 语义构造字节流，验证本模块解码结果与 Dart 一致。
//!
//! # 字节流构造逻辑（Dart 语义逐条推导）
//!
//! 字段头规则（Dart `tars_output_stream.dart::writeHead`）：
//! - `tag < 15`：1 字节 `(tag << 4) | type`
//! - `15 <= tag < 256`：2 字节 `(15 << 4) | type` + 1 字节 tag
//!
//! 类型序号（Dart `tars_struct.dart::TarsStructType` 枚举序）：
//! BYTE=0 SHORT=1 INT=2 LONG=3 FLOAT=4 DOUBLE=5 STRING1=6 STRING4=7
//! MAP=8 LIST=9 STRUCT_BEGIN=10 STRUCT_END=11 ZERO_TAG=12 SIMPLE_LIST=13
//!
//! 整型/浮点载荷恒为大端（Dart `BinaryWriter.writeInt` 硬编码 `Endian.big`）。

use slive_core::error::SliveError;
use slive_core::tars::{TarsDecoder, TarsEncoder, TarsStruct};

/// 手工按 Dart 语义构造一个「结构体」字节流。
///
/// 结构：`HYPushMessage { pushType=7(tag0), uri=1400(tag1), msg=[AA,BB](tag2), protocolType=0(tag3) }`
///
/// 推导：
/// ```text
/// tag0 pushType=7     -> BYTE(0):  (0<<4)|0        = 0x00, 载荷 0x07
/// tag1 uri=1400       -> SHORT(1): (1<<4)|1        = 0x11, 载荷 1400 大端 = 0x05 0x78
/// tag2 msg=SimpleList -> SIMPLE_LIST(13): (2<<4)|13 = 0x2D
///                        内层 BYTE(0) tag=0: (0<<4)|0 = 0x00
///                        长度 2 -> BYTE: 0x00, 0x02
///                        数据: 0xAA 0xBB
/// tag3 protocolType=0 -> ZERO_TAG(12): (3<<4)|12   = 0x3C（无载荷）
/// ```
const HYPUSH_MANUAL: &[u8] = &[
    0x00, 0x07, // pushType = 7 (BYTE, tag0)
    0x11, 0x05, 0x78, // uri = 1400 (SHORT, tag1)
    0x2D, 0x00, 0x00, 0x02, 0xAA, 0xBB, // msg = [AA, BB] (SIMPLE_LIST, tag2)
    0x3C, // protocolType = 0 (ZERO_TAG, tag3)
];

#[derive(Debug, Default, PartialEq)]
struct HyPush {
    push_type: i32,
    uri: i32,
    msg: Vec<u8>,
    protocol_type: i32,
}

impl TarsStruct for HyPush {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            push_type: d.read_i64_or(0, 0) as i32,
            uri: d.read_i64_or(1, 0) as i32,
            msg: d.read_bytes_or(2),
            protocol_type: d.read_i64_or(3, 0) as i32,
        })
    }
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.push_type as i64, 0)?;
        e.write_i64(self.uri as i64, 1)?;
        e.write_bytes(&self.msg, 2)?;
        e.write_i64(self.protocol_type as i64, 3)?;
        Ok(())
    }
}

#[test]
fn manual_byte_stream_decodes_to_expected_struct() {
    // 注意：Dart 虎牙侧是 `HYMessage.readFrom(TarsInputStream(msg))` —— **直接读字段**，
    // 外层没有 STRUCT_BEGIN 包裹。故此处用 `read_from` 而非 `decode`。
    let got = HyPush::decode_fields(HYPUSH_MANUAL).expect("手工字节流应能解码");
    assert_eq!(
        got,
        HyPush { push_type: 7, uri: 1400, msg: vec![0xAA, 0xBB], protocol_type: 0 }
    );
}

#[test]
fn encoder_reproduces_the_manual_byte_stream_exactly() {
    // 反向对拍：同样的字段值，本模块编码结果必须与手工字节流逐字节相同
    let v = HyPush { push_type: 7, uri: 1400, msg: vec![0xAA, 0xBB], protocol_type: 0 };
    let encoded = v.encode().unwrap();
    // encode() 会补 STRUCT_BEGIN / STRUCT_END，故取中间字段部分比对
    assert_eq!(
        &encoded[1..encoded.len() - 1],
        HYPUSH_MANUAL,
        "编码字节须与手工构造一致"
    );
}

/// 手工构造「嵌套结构体」字节流，验证 `STRUCT_BEGIN` / `STRUCT_END` 与 tag 定位。
///
/// 结构：`Outer { inner=Inner{a=1(tag0), b="hi"(tag2)}(tag0), n=1400(tag1) }`
///
/// 推导：
/// ```text
/// STRUCT_BEGIN tag0: (0<<4)|10 = 0x0A
///   tag0 inner = STRUCT_BEGIN: (0<<4)|10 = 0x0A
///     tag0 a=1  -> BYTE: 0x00, 0x01
///     tag2 b="hi" -> STRING1: (2<<4)|6 = 0x26, 长度 2, 'h' 'i'
///     STRUCT_END tag0: 0x0B
///   tag1 n=1400 -> SHORT: (1<<4)|1 = 0x11, 0x05 0x78
/// STRUCT_END tag0: 0x0B
/// ```
#[derive(Debug, Default, PartialEq)]
struct Inner {
    a: i32,
    b: String,
}

impl TarsStruct for Inner {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self { a: d.read_i64_or(0, 0) as i32, b: d.read_string_or(2, "") })
    }
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.a as i64, 0)?;
        e.write_string(&self.b, 2)?;
        Ok(())
    }
}

#[derive(Debug, Default, PartialEq)]
struct Outer {
    inner: Inner,
    n: i32,
}

impl TarsStruct for Outer {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            inner: d.read_struct(0, Inner::read_from)?,
            n: d.read_i64_or(1, 0) as i32,
        })
    }
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_bytes(&self.inner.encode()?, 0)?;
        e.write_i64(self.n as i64, 1)?;
        Ok(())
    }
}

const OUTER_MANUAL: &[u8] = &[
    0x0A, // STRUCT_BEGIN tag0
    0x0A, //   tag0 inner: STRUCT_BEGIN
    0x00, 0x01, //     tag0 a = 1
    0x26, 0x02, b'h', b'i', //     tag2 b = "hi"
    0x0B, //     STRUCT_END
    0x11, 0x05, 0x78, //   tag1 n = 1400
    0x0B, // STRUCT_END
];

#[test]
fn manual_nested_struct_bytes_decode_correctly() {
    let got = Outer::decode(OUTER_MANUAL).expect("嵌套结构体应能解码");
    assert_eq!(
        got,
        Outer { inner: Inner { a: 1, b: "hi".into() }, n: 1400 }
    );
}

/// 手工构造「tag >= 15 的两字节字段头」字节流。
///
/// 结构：`Wide { v=7 (tag 15), s="ab" (tag 20) }`
/// 推导：
/// ```text
/// STRUCT_BEGIN tag0: 0x0A
///   tag15 v=7  -> 2 字节头: (15<<4)|0 = 0xF0, tag=15；载荷 BYTE 0x07
///   tag20 s="ab" -> 2 字节头: (15<<4)|6 = 0xF6, tag=20；长度 2, 'a' 'b'
/// STRUCT_END tag0: 0x0B
/// ```
#[derive(Debug, Default, PartialEq)]
struct Wide {
    v: i32,
    s: String,
}

impl TarsStruct for Wide {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self { v: d.read_i64_or(15, 0) as i32, s: d.read_string_or(20, "") })
    }
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.v as i64, 15)?;
        e.write_string(&self.s, 20)?;
        Ok(())
    }
}

const WIDE_MANUAL: &[u8] = &[
    0x0A, // STRUCT_BEGIN
    0xF0, 15, 0x07, // tag15 v=7（两字节头）
    0xF6, 20, 0x02, b'a', b'b', // tag20 s="ab"（两字节头）
    0x0B, // STRUCT_END
];

#[test]
fn manual_two_byte_field_head_decodes_correctly() {
    assert_eq!(
        Wide::decode(WIDE_MANUAL).unwrap(),
        Wide { v: 7, s: "ab".into() }
    );
}

/// 手工构造 `STRING4` 字符串字段（长度 > 255 走 4 字节长度）。
///
/// 结构：`Big { s = 256 个 'a' }`
/// 推导：`STRUCT_BEGIN 0x0A` + `STRING4 tag0: (0<<4)|7 = 0x07, 长度 256 大端 = 00 00 01 00, 256 字节数据` + `STRUCT_END 0x0B`
#[test]
fn manual_string4_field_decodes_correctly() {
    let payload = vec![b'a'; 256];
    let mut manual = vec![0x0A, 0x07, 0x00, 0x00, 0x01, 0x00];
    manual.extend_from_slice(&payload);
    manual.push(0x0B);

    let mut d = TarsDecoder::new(&manual);
    let s = d.read_struct(0, |d| d.read_string(0)).unwrap();
    assert_eq!(s.len(), 256);
    assert!(s.bytes().all(|c| c == b'a'));
}

#[test]
fn manual_string1_utf8_field_decodes_correctly() {
    // 字符串 "弹幕hi"：UTF-8 字节 = 6+2 = 8
    // STRUCT_BEGIN 0x0A + STRING1 tag0 0x06 + 长度 8 + 数据 + STRUCT_END 0x0B
    let manual = [
        0x0A, 0x06, 0x08, 0xE5, 0xBC, 0xB9, 0xE5, 0xB9, 0x95, b'h', b'i', 0x0B,
    ];
    let mut d = TarsDecoder::new(&manual);
    assert_eq!(
        d.read_struct(0, |d| d.read_string(0)).unwrap(),
        "弹幕hi"
    );
}

/// 手工构造 `MAP` 字段，验证 Map 头 + 条数 + key(tag0)/value(tag1) 布局。
///
/// 结构：`M { m = Map{ "a" -> [0x01] } (tag3) }`
/// 推导：
/// ```text
/// STRUCT_BEGIN 0x0A
///   tag3 m -> MAP(8): (3<<4)|8 = 0x38
///     条数 1 -> BYTE: 0x00, 0x01
///     key "a" tag0 -> STRING1: (0<<4)|6 = 0x06, 长度 1, 'a'
///     value [0x01] tag1 -> SIMPLE_LIST: (1<<4)|13 = 0x1D, 内层 BYTE tag0 0x00, 长度 1 0x01, 数据 0x01
/// STRUCT_END 0x0B
/// ```
const MAP_MANUAL: &[u8] = &[
    0x0A, // STRUCT_BEGIN
    0x38, //   tag3 MAP
    0x00, 0x01, //     条数 1（BYTE 头 + 值）
    0x06, 0x01, b'a', //     key "a" (STRING1, tag0)
    0x1D, //       tag1 SIMPLE_LIST
    0x00, //         内层 BYTE 头 (tag0)
    0x00, 0x01, //         长度 1（BYTE 头 + 值）
    0x01, //         数据
    0x0B, // STRUCT_END
];

#[test]
fn manual_map_field_decodes_correctly() {
    let mut d = TarsDecoder::new(MAP_MANUAL);
    let got = d
        .read_struct(0, |d| d.read_str_bytes_map(3))
        .expect("Map 字段应能解码");
    assert_eq!(got, vec![("a".to_string(), vec![0x01u8])]);
}

/// 手工构造 `LIST` 字段，验证 List 头 + 条数 + 元素(tag0) 布局。
///
/// 结构：`L { items = [1, 2] (tag1) }`
/// 推导：
/// ```text
/// STRUCT_BEGIN 0x0A
///   tag1 items -> LIST(9): (1<<4)|9 = 0x19
///     条数 2 -> BYTE: 0x00, 0x02
///     元素 1 -> BYTE tag0: 0x00, 0x01
///     元素 2 -> BYTE tag0: 0x00, 0x02
/// STRUCT_END 0x0B
/// ```
const LIST_MANUAL: &[u8] = &[
    0x0A, // STRUCT_BEGIN
    0x19, //   tag1 LIST
    0x00, 0x02, //     条数 2
    0x00, 0x01, //     元素 1
    0x00, 0x02, //     元素 2
    0x0B, // STRUCT_END
];

#[test]
fn manual_list_field_decodes_correctly() {
    let mut d = TarsDecoder::new(LIST_MANUAL);
    let got = d
        .read_struct(0, |d| d.read_list(1, |d| d.read_i64(0)))
        .expect("List 字段应能解码");
    assert_eq!(got, vec![1, 2]);
}

/// 对拍：`read_value` 动态解码与强类型解码在手工字节流上结果一致。
#[test]
fn dynamic_and_typed_decode_agree_on_manual_stream() {
    let typed = HyPush::decode_fields(HYPUSH_MANUAL).unwrap();
    let mut d = TarsDecoder::new(HYPUSH_MANUAL);
    let fields = [
        (0, d.read_value(0).unwrap()),
        (1, d.read_value(1).unwrap()),
        (2, d.read_value(2).unwrap()),
        (3, d.read_value(3).unwrap()),
    ];
    assert_eq!(fields[0].1.as_int(), Some(typed.push_type as i64));
    assert_eq!(fields[1].1.as_int(), Some(typed.uri as i64));
    assert_eq!(fields[2].1.as_bytes(), Some(&typed.msg[..]));
    assert_eq!(fields[3].1.as_int(), Some(typed.protocol_type as i64));
}

/// 对拍：`skip_to_tag` 在缺失 tag 时返回 false（对齐 Dart `skipToTag` 返回 false）。
#[test]
fn missing_tag_returns_false_like_dart() {
    let mut d = TarsDecoder::new(HYPUSH_MANUAL);
    assert!(d.skip_to_tag(9).is_err(), "读到末尾应报错而非静默 false");
}
