//! `packet.rs`（`RequestPacket` / `TarsMessage`）的单元测试。
//!
//! 外置到独立文件，避免主文件超过 300 行门禁；由 `packet.rs` 的
//! `#[path = "packet_tests.rs"] mod tests;` 引入。

use super::*;

#[cfg(test)]
fn demo_packet() -> RequestPacket {
    let mut p = RequestPacket::new_tup3();
    p.i_request_id = 7;
    p.s_servant_name = "Obj".into();
    p.s_func_name = "getCdnToken".into();
    p.s_buffer = vec![1, 2, 3];
    p.context = vec![("a".into(), "b".into())];
    p.status = vec![(super::super::consts::STATUS_RESULT_CODE.into(), "0".into())];
    p
}

#[test]
fn request_packet_roundtrip() {
    let p = demo_packet();
    let bytes = p.encode().unwrap();
    assert_eq!(bytes[0], 0x0A, "STRUCT_BEGIN");
    assert_eq!(*bytes.last().unwrap(), 0x0B, "STRUCT_END");
    assert_eq!(RequestPacket::decode(&bytes).unwrap(), p);
}

#[test]
fn request_packet_flat_fields_roundtrip() {
    // 平铺形态（UniPacket 包体用）：无 STRUCT_BEGIN 包裹
    let p = demo_packet();
    let mut e = TarsEncoder::new();
    p.write_fields_flat(&mut e).unwrap();
    let bytes = e.into_bytes();
    let mut d = TarsDecoder::new(&bytes);
    assert_eq!(RequestPacket::read_fields_flat(&mut d).unwrap(), p);
}

#[test]
fn request_packet_status_accessors() {
    let mut p = RequestPacket::default();
    assert_eq!(p.result_code(), 0, "缺失时为 0");
    assert_eq!(p.result_desc(), "");
    p.status = vec![
        (super::super::consts::STATUS_RESULT_CODE.into(), "-1".into()),
        (super::super::consts::STATUS_RESULT_DESC.into(), "boom".into()),
    ];
    assert_eq!(p.result_code(), -1);
    assert_eq!(p.result_desc(), "boom");
    // 非法返回码不应 panic
    p.status = vec![(super::super::consts::STATUS_RESULT_CODE.into(), "x".into())];
    assert_eq!(p.result_code(), 0);
}

#[test]
fn new_tup3_defaults_match_dart() {
    let p = RequestPacket::new_tup3();
    assert_eq!(p.i_version, PACKET_TYPE_TUP3);
    assert_eq!(p.c_packet_type, PACKET_TYPE_TARSNORMAL);
    assert_eq!(p.s_buffer, vec![0u8], "Dart cache_sBuffer = [0x0]");
    assert!(p.context.is_empty());
    assert!(p.status.is_empty());
}

#[test]
fn tars_message_roundtrip() {
    let mut m = TarsMessage {
        header: RequestPacket::new_tup3(),
        ..Default::default()
    };
    m.header.i_request_id = 3;
    m.header.s_servant_name = "S".into();
    m.body.insert("tReq".into(), vec![9, 9]);
    let bytes = m.encode().unwrap();
    let got = TarsMessage::decode(&bytes).unwrap();
    assert_eq!(got.header.i_request_id, 3);
    assert_eq!(got.header.s_servant_name, "S");
    assert_eq!(got.get("tReq"), &[9, 9]);
    assert!(got.get("tRsp").is_empty());
}

#[test]
fn pairs_to_tars_map_keeps_values_as_strings() {
    let m = pairs_to_tars_map(&[("k".into(), "v".into())]);
    assert_eq!(m.len(), 1);
    assert_eq!(m[0].0.as_str(), Some("k"));
    assert_eq!(m[0].1.as_str(), Some("v"), "值必须是字符串而非 bytes");
    assert!(pairs_to_tars_map(&[]).is_empty());
}
