//! TARS 编解码引擎验收测试（对照 Dart `tars_dart/lib/tars/codec/`）。
//!
//! 覆盖：字节序切换、整型按值域选宽、字符串 STRING1/STRING4 切换、bytes 两种形态、
//! 数组/Map/结构体往返、字段头 tag 边界、越界与类型不符的错误路径（不 panic）。
//!
//! 行为基准：Dart `tars_dart/lib/tars/codec/tars_output_stream.dart`（写）
//! 与 `tars_input_stream.dart`（读）。

use slive_core::error::SliveError;
use slive_core::tars::{
    Endian, ReadBuffer, RequestPacket, TarsDecoder, TarsEncoder, TarsStruct, TarsType, TarsValue,
    WriteBuffer, MAX_TAG, PACKET_TYPE_TUP3,
};

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

// ---------------------------------------------------------------- 字节序切换

#[test]
fn endian_switch_changes_byte_layout_at_runtime() {
    let mut w = WriteBuffer::new();
    w.set_endian(Endian::Big);
    w.put_u16(0x0102);
    w.set_endian(Endian::Little);
    w.put_u16(0x0102);
    assert_eq!(w.as_slice(), &[0x01, 0x02, 0x02, 0x01], "同一值两种字节序布局不同");

    let bytes = w.into_bytes();
    let mut r = ReadBuffer::new(&bytes);
    assert_eq!(r.read_u16().unwrap(), 0x0102);
    r.set_endian(Endian::Little);
    assert_eq!(r.read_u16().unwrap(), 0x0102);
}

#[test]
fn buffer_int_and_float_roundtrip_in_both_endians() {
    for e in [Endian::Big, Endian::Little] {
        let mut w = WriteBuffer::with_endian(e);
        w.put_i8(-5);
        w.put_i16(-300);
        w.put_i32(-70000);
        w.put_i64(-5_000_000_000);
        w.put_u32(0xDEAD_BEEF);
        w.put_f32(1.5);
        w.put_f64(-2.25);
        w.put_bool(true);
        let bytes = w.into_bytes();

        let mut r = ReadBuffer::with_endian(&bytes, e);
        assert_eq!(r.read_i8().unwrap(), -5);
        assert_eq!(r.read_i16().unwrap(), -300);
        assert_eq!(r.read_i32().unwrap(), -70000);
        assert_eq!(r.read_i64().unwrap(), -5_000_000_000);
        assert_eq!(r.read_u32().unwrap(), 0xDEAD_BEEF);
        assert_eq!(r.read_f32().unwrap(), 1.5);
        assert_eq!(r.read_f64().unwrap(), -2.25);
        assert!(r.read_bool().unwrap());
        assert!(r.is_empty());
    }
}

#[test]
fn buffer_string_length_prefix_counts_utf8_bytes() {
    let mut w = WriteBuffer::new();
    w.put_string_u8_len("弹幕"); // 2 chars but 6 UTF-8 bytes
    w.put_string_u32_len("ab");
    assert_eq!(w.as_slice()[0], 6, "长度前缀按字节数而非 char 数");
    let bytes = w.into_bytes();
    let mut r = ReadBuffer::new(&bytes);
    assert_eq!(r.read_string_u8_len().unwrap(), "弹幕");
    assert_eq!(r.read_string_u32_len().unwrap(), "ab");
}

#[test]
fn buffer_truncated_read_is_error_not_panic() {
    let data = [0x01u8, 0x02];
    let mut r = ReadBuffer::new(&data);
    assert!(matches!(r.read_u32(), Err(SliveError::Decode(_))));
    assert_eq!(r.position(), 0, "失败后游标不推进");
    assert!(r.seek(99).is_err());
}

#[test]
fn buffer_array_reads() {
    let mut w = WriteBuffer::new();
    w.put_u32(1);
    w.put_u32(2);
    let bytes = w.into_bytes();
    let mut r = ReadBuffer::new(&bytes);
    assert_eq!(r.read_u32_array(2).unwrap(), vec![1, 2]);
}

// ---------------------------------------------------------------- 字段头

#[test]
fn field_head_encoding_matches_dart_write_head() {
    // Dart: tag<15 -> 1 字节 (tag<<4)|type；15<=tag<256 -> 2 字节
    let mut e = TarsEncoder::new();
    e.write_struct_begin_at(3).unwrap();
    assert_eq!(e.as_slice(), &[(3u8 << 4) | 10], "STRUCT_BEGIN tag=3");

    let mut e2 = TarsEncoder::new();
    e2.write_i64(1, 20).unwrap();
    assert_eq!(e2.as_slice()[0], 0xF0, "tag>=15 头字节固定为 0xF0");
    assert_eq!(e2.as_slice()[1], 20, "第二字节为实际 tag");
}

#[test]
fn tag_above_255_is_rejected() {
    let mut e = TarsEncoder::new();
    assert!(e.write_i64(1, MAX_TAG + 1).is_err());
    assert!(e.write_i64(1, -1).is_err());
    assert!(e.is_empty(), "非法 tag 不应写入字节");
    let mut e2 = TarsEncoder::new();
    assert!(e2.write_i64(1, MAX_TAG).is_ok(), "tag=255 合法");
}

#[test]
fn field_type_enum_values_match_dart() {
    // Dart enum 顺序：BYTE..SIMPLE_LIST
    assert_eq!(TarsType::Byte as u8, 0);
    assert_eq!(TarsType::StructBegin as u8, 10);
    assert_eq!(TarsType::StructEnd as u8, 11);
    assert_eq!(TarsType::ZeroTag as u8, 12);
    assert_eq!(TarsType::SimpleList as u8, 13);
}

// ---------------------------------------------------------------- 整型选宽

#[test]
fn int_width_selected_by_value_range() {
    // Dart `writeInt`: 值 0 -> 只写 ZERO_TAG(12) 头；<=127 -> BYTE；<=32767 -> SHORT；
    // <=i32::MAX -> INT；其余 -> LONG。tag 均为 0，故头字节 = type 本身。
    let cases: [(i64, u8); 5] = [
        (0, 12),     // ZERO_TAG
        (127, 0),    // BYTE
        (128, 1),    // SHORT
        (32767, 1),  // SHORT
        (32768, 2),  // INT
    ];
    for (v, head) in cases {
        let mut e = TarsEncoder::new();
        e.write_i64(v, 0).unwrap();
        assert_eq!(e.as_slice()[0], head, "值 {v}");
    }
    let mut e = TarsEncoder::new();
    e.write_i64(i64::MAX, 0).unwrap();
    assert_eq!(e.as_slice()[0], 3, "超 i32 用 LONG");
}

#[test]
fn zero_value_writes_header_only() {
    let mut e = TarsEncoder::new();
    e.write_i64(0, 3).unwrap();
    assert_eq!(e.as_slice(), &[0x3C], "ZeroTag 无载荷字节");
}

#[test]
fn int_roundtrip_non_negative_values() {
    for v in [0i64, 1, 127, 128, 32767, 32768, 65535, 65536, i32::MAX as i64, i64::MAX] {
        let mut e = TarsEncoder::new();
        e.write_i64(v, 0).unwrap();
        let bytes = e.into_bytes();
        let mut d = TarsDecoder::new(&bytes);
        assert_eq!(d.read_i64(0).unwrap(), v, "值 {v}");
    }
}

#[test]
fn byte_field_reads_unsigned_like_dart() {
    // Dart `readInt(1)` -> `getUint8`，与官方 C++ `unsigned char` 一致：0..=255。
    let mut e = TarsEncoder::new();
    e.write_i64(-5, 0).unwrap();
    assert_eq!(e.as_slice(), &[0x00, 0xFB]);
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_i64(0).unwrap(), 251, "按无符号读，与 Dart 逐字节等价");
}

// ---------------------------------------------------------------- 字符串

#[test]
fn string_switches_between_string1_and_string4() {
    let mut e = TarsEncoder::new();
    e.write_string("", 0).unwrap();
    assert_eq!(e.as_slice(), &[0x06, 0], "空串走 STRING1 + 长度 0");

    let mut e2 = TarsEncoder::new();
    e2.write_string("弹幕", 0).unwrap();
    assert_eq!(e2.as_slice()[0], 0x06);
    assert_eq!(e2.as_slice()[1], 6, "UTF-8 字节数");

    let mut e3 = TarsEncoder::new();
    e3.write_string(&"a".repeat(256), 0).unwrap();
    assert_eq!(e3.as_slice()[0], 0x07, "STRING4");
    assert_eq!(&e3.as_slice()[1..5], &[0, 0, 1, 0], "长度 256 大端");

    for s in ["", "弹幕", "hello", &"a".repeat(300)] {
        let mut e = TarsEncoder::new();
        e.write_string(s, 0).unwrap();
        let bytes = e.into_bytes();
        let mut d = TarsDecoder::new(&bytes);
        assert_eq!(d.read_string(0).unwrap(), s, "字符串往返 {s:?}");
    }
}

// ---------------------------------------------------------------- bytes / 数组 / Map

#[test]
fn bytes_use_simple_list_layout() {
    // Dart `writeUint8List`:
    //   writeHead(SIMPLE_LIST, tag) -> (2<<4)|13 = 0x2D
    //   writeHead(BYTE, 0)           -> 0x00        （内层元素类型头）
    //   writeInt(3, 0)               -> 0x00, 0x03  （长度自身也带 BYTE 头 + 值）
    //   writeBytes([1,2,3])          -> 0x01 0x02 0x03
    let mut e = TarsEncoder::new();
    e.write_bytes(&[1, 2, 3], 2).unwrap();
    assert_eq!(e.as_slice(), &[0x2D, 0x00, 0x00, 0x03, 1, 2, 3]);
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_bytes(2).unwrap(), vec![1, 2, 3]);
}

#[test]
fn bytes_also_accept_list_form_like_dart() {
    let mut e = TarsEncoder::new();
    e.write_list(&[TarsValue::Int(1), TarsValue::Int(2)], 0)
        .unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_bytes(0).unwrap(), vec![1u8, 2]);
}

#[test]
fn list_and_map_roundtrip_via_callbacks() {
    let mut e = TarsEncoder::new();
    e.write_list(&[TarsValue::Int(1), TarsValue::Int(2), TarsValue::Int(3)], 0)
        .unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_list(0, |d| d.read_i64(0)).unwrap(), vec![1, 2, 3]);

    let mut m = std::collections::BTreeMap::new();
    m.insert("k".to_string(), vec![1u8, 2]);
    let mut e2 = TarsEncoder::new();
    e2.write_str_map(&m, 1).unwrap();
    let bytes2 = e2.into_bytes();
    let mut d2 = TarsDecoder::new(&bytes2);
    assert_eq!(
        d2.read_str_bytes_map(1).unwrap(),
        vec![("k".to_string(), vec![1u8, 2])]
    );
}

#[test]
fn str_str_map_roundtrip() {
    let mut e = TarsEncoder::new();
    e.write_map(
        &[(
            TarsValue::string("STATUS_RESULT_CODE"),
            TarsValue::string("0"),
        )],
        9,
    )
    .unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(
        d.read_str_str_map(9).unwrap(),
        vec![("STATUS_RESULT_CODE".to_string(), "0".to_string())]
    );
}

// ---------------------------------------------------------------- 结构体

#[test]
fn struct_roundtrip_and_terminator_bytes() {
    let d = Demo { a: 7, b: "弹幕".into(), c: vec![1, 2, 3] };
    let bytes = d.encode().unwrap();
    assert_eq!(bytes[0], 0x0A, "STRUCT_BEGIN tag=0");
    assert_eq!(*bytes.last().unwrap(), 0x0B, "STRUCT_END 结束标记");
    assert_eq!(Demo::decode(&bytes).unwrap(), d);
}

#[test]
fn struct_read_auto_skips_to_struct_end() {
    let mut e = TarsEncoder::new();
    e.write_struct(
        &[(0, TarsValue::Int(11)), (2, TarsValue::string("hi"))],
        0,
    )
    .unwrap();
    e.write_i64(99, 5).unwrap();
    let bytes = e.into_bytes();

    let mut d = TarsDecoder::new(&bytes);
    let (a, b) = d
        .read_struct(0, |d| Ok((d.read_i64(0)?, d.read_string(2)?)))
        .unwrap();
    assert_eq!(a, 11);
    assert_eq!(b, "hi");
    assert_eq!(d.read_i64(5).unwrap(), 99, "STRUCT_END 被正确跳过");
}

#[test]
fn skip_to_tag_skips_lower_tags() {
    let mut e = TarsEncoder::new();
    e.write_i64(7, 0).unwrap();
    e.write_i64(1400, 1).unwrap();
    e.write_i64(9, 3).unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_i64(0).unwrap(), 7);
    assert_eq!(d.read_i64(1).unwrap(), 1400);
    assert_eq!(d.read_i64(3).unwrap(), 9, "跳过 tag=2");
}

// ---------------------------------------------------------------- 动态值

#[test]
fn dynamic_value_read_covers_all_shapes() {
    let mut e = TarsEncoder::new();
    e.write_value(&TarsValue::Int(5), 0).unwrap();
    e.write_value(&TarsValue::string("s"), 1).unwrap();
    e.write_value(&TarsValue::Double(1.5), 2).unwrap();
    e.write_value(&TarsValue::bytes(vec![1, 2]), 4).unwrap();
    e.write_value(&TarsValue::list(vec![TarsValue::Int(1)]), 5)
        .unwrap();
    e.write_value(&TarsValue::strukt(vec![(0, TarsValue::Int(3))]), 6)
        .unwrap();
    e.write_value(
        &TarsValue::map(vec![(TarsValue::string("k"), TarsValue::Int(1))]),
        7,
    )
    .unwrap();
    let bytes = e.into_bytes();

    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_value(0).unwrap(), TarsValue::Int(5));
    assert_eq!(d.read_value(1).unwrap(), TarsValue::string("s"));
    assert_eq!(d.read_value(2).unwrap(), TarsValue::Double(1.5));
    assert_eq!(d.read_value(4).unwrap(), TarsValue::bytes(vec![1, 2]));
    assert_eq!(d.read_value(5).unwrap().as_list().map(|x| x.len()), Some(1));
    assert_eq!(d.read_value(6).unwrap().as_struct().map(|x| x.len()), Some(1));
    assert_eq!(d.read_value(7).unwrap().as_map().map(|x| x.len()), Some(1));
}

#[test]
fn bool_is_encoded_as_byte_one_on_the_wire() {
    // TARS 线上格式没有独立的 bool 类型：`writeBool` -> `writeByte` -> BYTE(1)。
    // 因此 `read_value` 读回的是 `Int(1)`，这是与 Dart 一致的行为。
    let mut e = TarsEncoder::new();
    e.write_bool(true, 0).unwrap();
    assert_eq!(e.as_slice(), &[0x00, 0x01]);
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(d.read_value(0).unwrap(), TarsValue::Int(1));
    let mut d2 = TarsDecoder::new(&bytes);
    assert!(d2.read_bool(0).unwrap(), "read_bool 按 Dart：int != 0");
}

#[test]
fn value_accessors_and_constructors() {
    assert_eq!(TarsValue::int(7i32).as_int(), Some(7));
    assert_eq!(TarsValue::string("a").as_str(), Some("a"));
    assert_eq!(TarsValue::bytes(vec![1]).as_bytes(), Some(&[1u8][..]));
    assert_eq!(TarsValue::double(1.5).as_double(), Some(1.5));
    assert_eq!(TarsValue::boolean(true).as_bool(), Some(true));
    assert_eq!(TarsValue::int(1).as_str(), None, "类型不符返回 None");
    assert_eq!(TarsValue::Int(1).type_name(), "int");
}

// ---------------------------------------------------------------- 错误路径

#[test]
fn errors_are_returned_not_panicked() {
    // 缺失字段
    let mut e = TarsEncoder::new();
    e.write_i64(1, 0).unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert!(matches!(d.read_i64(5), Err(SliveError::Decode(_))));
    assert_eq!(d.read_i64_or(5, -1), -1, "or 变体给默认值");
    assert_eq!(d.read_string_or(5, "def"), "def");
    assert!(d.read_bytes_or(5).is_empty());

    // 类型不符
    let mut e2 = TarsEncoder::new();
    e2.write_string("x", 0).unwrap();
    let b2 = e2.into_bytes();
    let mut d2 = TarsDecoder::new(&b2);
    assert!(d2
        .read_i64(0)
        .unwrap_err()
        .to_string()
        .contains("类型不符"));
}

#[test]
fn truncated_streams_do_not_panic() {
    for len in 0..8 {
        let data = vec![0x0Au8; len];
        let _ = Demo::decode(&data);
        let mut d = TarsDecoder::new(&data);
        let _ = d.read_i64(0);
        let _ = d.read_string(0);
        let _ = d.read_bytes(0);
        let _ = d.skip_to_struct_end();
    }
}

#[test]
fn huge_string_length_is_rejected_before_alloc() {
    // STRING4(tag=0) 头字节 = (0<<4)|7 = 0x07；随后 4 字节长度声明 0x7FFFFFFF
    let data = [0x07u8, 0x7F, 0xFF, 0xFF, 0xFF];
    let mut d = TarsDecoder::new(&data);
    assert!(d.skip_field().is_err(), "超长声明必须拒绝，不得巨额分配");
}

#[test]
fn negative_string_length_is_rejected() {
    let data = [0x07u8, 0xFF, 0xFF, 0xFF, 0xFF];
    let mut d = TarsDecoder::new(&data);
    assert!(d.skip_field().is_err());
}

// ---------------------------------------------------------------- 封包

#[test]
fn request_packet_roundtrip_with_version_field() {
    let mut p = RequestPacket::new_tup3();
    assert_eq!(p.i_version, PACKET_TYPE_TUP3, "版本字段默认 TUP3");
    p.i_request_id = 7;
    p.s_servant_name = "Obj".into();
    p.s_func_name = "getCdnToken".into();
    p.s_buffer = vec![1, 2, 3];
    p.status = vec![(
        slive_core::tars::consts::STATUS_RESULT_CODE.into(),
        "0".into(),
    )];
    let bytes = p.encode().unwrap();
    let got = RequestPacket::decode(&bytes).unwrap();
    assert_eq!(got, p);
    assert_eq!(got.result_code(), 0);
}

#[test]
fn request_packet_result_code_from_status() {
    let mut p = RequestPacket::default();
    assert_eq!(p.result_code(), 0, "缺失时为 0");
    p.status = vec![
        (
            slive_core::tars::consts::STATUS_RESULT_CODE.into(),
            "-1".into(),
        ),
        (
            slive_core::tars::consts::STATUS_RESULT_DESC.into(),
            "boom".into(),
        ),
    ];
    assert_eq!(p.result_code(), -1);
    assert_eq!(p.result_desc(), "boom");
}

#[test]
fn request_packet_field_accessors() {
    let p = RequestPacket::new_tup3();
    assert_eq!(p.i_version, PACKET_TYPE_TUP3);
    assert_eq!(p.c_packet_type, slive_core::tars::PACKET_TYPE_TARSNORMAL);
    assert_eq!(p.s_buffer, vec![0u8], "Dart cache_sBuffer = [0x0]");
    assert!(p.s_servant_name.is_empty());
    assert!(p.s_func_name.is_empty());
}
