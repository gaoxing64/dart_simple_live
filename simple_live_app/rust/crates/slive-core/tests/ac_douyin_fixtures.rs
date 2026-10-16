//! 抖音夹具契约用例（IP-6 夹具基线 · QA 产出）。
//!
//! 本文件只保留**夹具自身契约**（元数据/字节布局/转义/过滤等）；「平台行为」断言已由
//! 各平台实现测试取代（`ac_douyu_http.rs` 等）；原「待 IP-x 接入后解除」的 `#[ignore]`
//! 骨架已于 2026-10-17 合并前评审移除（理由已失真且被取代）。
//! 本文件**不 import 平台函数**，只读夹具 + 校验 protobuf 帧结构；
//! golden 与 HTTP quirks 见 `ac_douyin_golden.rs`。本文件锁住：
//! `PushFrame` 字段号与 gzip 载荷、`room_id` 的webRid/roomId 两形态、
//! 弹幕颜色恒为白色（Q9）。

mod fxcommon;

use fxcommon::{
    assert_hex_matches_bin, assert_http_samples_meta, assert_ws_meta, read_bytes, read_text,
    ws_expected_files,
};
use serde_json::Value;

const PLATFORM: &str = "douyin";

fn expected_doc(stem: &str) -> Value {
    serde_json::from_str(&read_text(PLATFORM, &format!("ws/{stem}.expected.json")))
        .unwrap_or_else(|e| panic!("解析 {stem} 失败: {e}"))
}

/// 最小 protobuf 读取器：返回 `(字段号, 值)` 序列。
/// bytes/str 以字节数组承载（serde_json 无bytes 类型）。
fn parse_pb(b: &[u8]) -> Vec<(u64, Vec<u8>)> {
    fn varint(b: &[u8], p: &mut usize) -> u64 {
        let (mut v, mut shift) = (0u64, 0u32);
        loop {
            let x = b[*p];
            *p += 1;
            v |= ((x & 0x7F) as u64) << shift;
            if x & 0x80 == 0 {
                return v;
            }
            shift += 7;
        }
    }
    let mut out = Vec::new();
    let mut p = 0usize;
    while p < b.len() {
        let key = varint(b, &mut p);
        let (field, wire) = (key >> 3, key & 7);
        match wire {
            0 => {
                let v = varint(b, &mut p);
                out.push((field, v.to_le_bytes().to_vec()));
            }
            2 => {
                let len = varint(b, &mut p) as usize;
                out.push((field, b[p..p + len].to_vec()));
                p += len;
            }
            5 => {
                out.push((field, b[p..p + 4].to_vec()));
                p += 4;
            }
            1 => {
                out.push((field, b[p..p + 8].to_vec()));
                p += 8;
            }
            other => panic!("未处理的 wire type {other}"),
        }
    }
    out
}

fn pb_get(fields: &[(u64, Vec<u8>)], no: u64) -> Option<&[u8]> {
    fields.iter().find(|(f, _)| *f == no).map(|(_, v)| v.as_slice())
}

// =====================================================================
// 一、夹具元数据契约
// =====================================================================
#[test]
fn fixture_meta_declares_required_fields() {
    let count = assert_http_samples_meta(PLATFORM);
    assert!(count >= 6, "抖音 HTTP 样本数量异常少：{count}");
}

#[test]
fn ws_frames_meta_and_hex_are_consistent() {
    let names = ws_expected_files(PLATFORM);
    assert!(names.len() >= 6, "抖音 WS 帧数量异常少：{}", names.len());
    for name in names {
        let stem = name.trim_end_matches(".expected.json");
        let doc = expected_doc(stem);
        assert_ws_meta(PLATFORM, &name, &doc);
        assert_hex_matches_bin(PLATFORM, stem, &doc);
    }
}

#[test]
fn room_id_two_forms_are_documented() {
    // douyin_site.dart:496-504：按长度 <= 16 分流。
    let conv = &fxcommon::http_samples(PLATFORM)["_meta"]["room_id_convention"];
    assert!(conv["webRid"].as_str().is_some_and(|v| v.contains("11-12")));
    assert!(conv["roomId"].as_str().is_some_and(|v| v.contains("19")));
    assert!(
        conv["dispatch"].as_str().is_some_and(|v| v.contains("length <= 16")),
        "缺长度判别规则说明"
    );
}

#[test]
fn unsupported_capabilities_are_documented() {
    let un = &fxcommon::http_samples(PLATFORM)["_meta"]["unsupported_by_dart"];
    assert!(un["search_anchors"].as_str().is_some());
    assert!(un["get_super_chat_message"].as_str().is_some());
    assert!(un["note"].as_str().is_some_and(|v| v.contains("不得")));
}

// =====================================================================
// 二、protobuf 帧契约
// =====================================================================
#[test]
fn push_frame_header_is_well_formed() {
    // PushFrame（douyin.proto:502-512）：seqId=1 logId=2 payloadEncoding=6
    //                               payloadType=7 payload=8
    for stem in ["frame-push-chat", "frame-push-room-user-seq", "frame-push-multi-need-ack"] {
        let fields = parse_pb(&read_bytes(PLATFORM, &format!("ws/{stem}.bin")));
        assert!(pb_get(&fields, 1).is_some(), "{stem} 缺 seqId");
        let ptype = pb_get(&fields, 7).expect("缺 payloadType");
        assert_eq!(ptype, b"msg", "{stem} 的 payloadType 应为 msg");
        let enc = pb_get(&fields, 6).expect("缺 payloadEncoding");
        assert_eq!(enc, b"gzip", "{stem} 的 payloadEncoding 应为 gzip");

        let payload = pb_get(&fields, 8).expect("缺 payload");
        assert!(payload.len() > 2, "{stem} 的 payload 过短");
        assert_eq!(payload[0], 0x1F, "{stem} 的 payload 应以 gzip 魔数开头");
        assert_eq!(payload[1], 0x8B, "{stem} 的 gzip 魔数次字节不符");
    }
}

#[test]
fn client_hb_frames_carry_payload_type_hb() {
    // Dart:127-131 / 192-196：心跳与进房都是 payloadType='hb' 的空 PushFrame。
    for stem in ["req-heartbeat-hb", "req-ack"] {
        let fields = parse_pb(&read_bytes(PLATFORM, &format!("ws/{stem}.bin")));
        let ptype = pb_get(&fields, 7).expect("缺 payloadType");
        assert_eq!(ptype, b"hb", "{stem} 的 payloadType 应为 hb");
        assert!(
            pb_get(&fields, 8).is_none(),
            "{stem} 是空帧，不应有 payload"
        );
    }
}

#[test]
fn chat_expectation_pins_white_color() {
    // Q9（Dart:158-162）：颜色**写死白色**（注释「暂不知道怎么转换颜色」），
    // 实现不得自行按 fullScreenTextColor 上色。
    let doc = expected_doc("frame-push-chat");
    let msgs = doc["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs.len(), 1);
    assert_eq!(msgs[0]["type"], "chat");
    assert_eq!(msgs[0]["user_name"], "观众甲");
    assert_eq!(msgs[0]["message"], "你好，抖音");
    assert_eq!(msgs[0]["color"]["r"], 255);
    assert_eq!(msgs[0]["color"]["g"], 255);
    assert_eq!(msgs[0]["color"]["b"], 255);
    assert!(
        doc["_meta"]["color_note"].as_str().is_some_and(|v| v.contains("写死")),
        "必须写明「颜色写死白色」的依据"
    );
}

#[test]
fn room_user_seq_frame_exposes_online_count() {
    let doc = expected_doc("frame-push-room-user-seq");
    let msgs = doc["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs[0]["type"], "online");
    assert_eq!(msgs[0]["data_int"], 88888, "取 RoomUserSeqMessage.totalUser");
    assert_eq!(msgs[0]["user_name"], "");
}

#[test]
fn multi_need_ack_frame_expects_ordered_messages() {
    let doc = expected_doc("frame-push-multi-need-ack");
    assert_eq!(doc["expected"]["need_ack"], true);
    let msgs = doc["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs.len(), 3, "2 聊天 + 1 在线，按序产出");
    assert_eq!(msgs[0]["message"], "第一条");
    assert_eq!(msgs[1]["message"], "第二条");
    assert_eq!(msgs[2]["type"], "online");
    assert_eq!(msgs[2]["data_int"], 12345);

    // Q11：ack 段的 Dart 笔误必须留痕（payloadType 被连写两次，第二次覆盖）。
    let ack = &doc["expected"]["ack"];
    assert!(ack["dart_quirk"].as_str().is_some(), "ack 的 Dart 笔误须留痕");
    assert_eq!(ack["payload_type"], "internalExt");
}

#[test]
fn unknown_method_yields_nothing() {
    // douyin_danmaku.dart:145-151：if/else if 无 else -> 静默忽略。
    let doc = expected_doc("frame-push-unknown-method");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "未知 method 必须静默忽略"
    );
}

#[test]
fn two_dirty_frames_cover_both_failure_layers() {
    // 一条卡在 gzip 层、一条卡在 protobuf 层：避免实现只挡住一层。
    let g = expected_doc("frame-dirty-not-gzip");
    assert_eq!(g["expected"]["error"].as_str().expect("error"), "gzip 解压失败");
    let p = expected_doc("frame-dirty-bad-protobuf");
    assert_eq!(
        p["expected"]["error"].as_str().expect("error"),
        "Response protobuf 解码失败"
    );
    for stem in ["frame-dirty-not-gzip", "frame-dirty-bad-protobuf"] {
        let doc = expected_doc(stem);
        assert_eq!(
            doc["expected"]["messages"].as_array().expect("messages").len(),
            0,
            "{stem} 不得期望任何产出"
        );
        assert!(doc["_meta"]["note"].as_str().is_some(), "{stem} 缺说明");
    }
}

#[test]
fn gzip_payload_is_deterministic() {
    // mtime=0 保证重复生成字节一致，夹具才能入版本库做 diff 比对。
    let doc = expected_doc("frame-push-chat");
    assert!(
        doc["_meta"]["gzip_determinism"].as_str().is_some_and(|v| v.contains("mtime=0")),
        "须写明 gzip 的确定性保障"
    );
    let a = read_bytes(PLATFORM, "ws/frame-push-chat.bin");
    let b = read_bytes(PLATFORM, "ws/frame-push-chat.bin");
    assert_eq!(a, b);
}
