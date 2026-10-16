//! IP-3 斗鱼弹幕：QA WS 夹具驱动的端到端解码断言（`tests/fixtures/douyu/ws/`）。
//!
//! 夹具是 QA 按 Dart `douyu_danmaku.dart` 逐字节推导的**合成**样本
//! （`_meta.synthetic = true`，标注 `needs_realtime_validation`）：
//! - 入站帧 `frame-*.bin` + `frame-*.expected.json`（STT 载荷 + 期望 `LiveMessage`）
//! - 出站包 `req-*.bin`（客户端封包 golden）
//!
//! 本文件是「实现 vs 夹具」的分离点（AC-35反作弊：实现与测试 diff 分离）。

use serde_json::Value;
use slive_core::models::{LiveMessageData, LiveMessageType};
use slive_core::platforms::douyu::danmaku::parse::decode_frame;
use slive_core::platforms::douyu::danmaku::protocol::{
    deserialize, join_payload, login_payload, serialize,
};

fn fixtures_dir() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/douyu/ws")
}

fn fixture_bytes(name: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(format!("{name}.bin")))
        .unwrap_or_else(|e| panic!("读取斗鱼夹具 {name}.bin 失败: {e}"))
}

fn fixture_json(name: &str) -> Value {
    let path = fixtures_dir().join(format!("{name}.expected.json"));
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("读取斗鱼夹具 {name}.expected.json 失败: {e}"));
    serde_json::from_str(&text).expect("夹具 JSON 合法")
}

/// 把夹具里的 `bytes_hex` 断言成二进制（防止 .bin 与 .json 漂移）。
fn assert_hex_matches_json(name: &str) {
    let json = fixture_json(name);
    let expected_hex: String = json["bytes_hex"]
        .as_str()
        .unwrap_or_else(|| panic!("{name} 夹具缺 bytes_hex"))
        .split_whitespace()
        .collect();
    let actual = hex_bytes(&expected_hex);
    assert_eq!(
        actual,
        fixture_bytes(name),
        "{name}: .bin 与 .expected.json 的 bytes_hex 不一致"
    );
}

fn hex_bytes(hex: &str) -> Vec<u8> {
    hex.as_bytes()
        .chunks(2)
        .map(|pair| {
            std::str::from_utf8(pair)
                .ok()
                .and_then(|s| u8::from_str_radix(s, 16).ok())
                .unwrap_or_else(|| panic!("非法 hex: {}", String::from_utf8_lossy(pair)))
        })
        .collect()
}

fn super_chat_data(
    message: &slive_core::models::LiveMessage,
) -> (String, String, i32, i64, i64, String) {
    let Some(LiveMessageData::SuperChat(sc)) = message.data.clone() else {
        panic!("期望 SuperChat，实际 {:?}", message.data);
    };
    (
        sc.user_name,
        sc.message,
        sc.price,
        sc.start_time.timestamp_millis(),
        sc.end_time.timestamp_millis(),
        sc.face,
    )
}

/// 出站封包 golden：loginreq（client->server）。
#[test]
fn client_loginreq_frame_matches_golden() {
    assert_hex_matches_json("req-loginreq");
    let json = fixture_json("req-loginreq");
    let body = json["stt_body"].as_str().expect("stt_body");
    assert_eq!(body, login_payload("252140"));
    assert_eq!(serialize(body), fixture_bytes("req-loginreq"));
}

/// 出站封包 golden：joingroup（client->server）。
#[test]
fn client_joingroup_frame_matches_golden() {
    assert_hex_matches_json("req-joingroup");
    let json = fixture_json("req-joingroup");
    let body = json["stt_body"].as_str().expect("stt_body");
    assert_eq!(body, join_payload("252140"));
    assert_eq!(serialize(body), fixture_bytes("req-joingroup"));
}

/// 入站帧：粉丝发言（`if=1`）产出 1 条聊天消息，颜色按 col 映射。
///
/// ⚠️ **夹具缺陷（已回传QA）**：`frame-chatmsg-fans1.bin` 的 STT 载荷里**没有 `if` 字段**
/// （`type@=chatmsg/nn@=观众A/txt@=你好世界/col@=3/`），但它的 `expected` 却要求产出 1 条消息，
/// 且 note 写明「type=chatmsg 且 if='1'（fans）才产出」。按 Dart
/// （`fans = jsonData["if"] ?? '0'` -> `'0'` -> 非粉丝 -> 丢弃）**该帧必须无产出**。
/// 故此处分两段断言：① 现存夹具按 Dart 口径丢弃；② 按 note 的意图补一个带 `if@=1` 的帧，
/// 断言值取自夹具的 `expected`，等QA 修正夹具 后两段自然合并。
#[test]
fn fan_chatmsg_shipped_fixture_is_dropped_because_if_field_is_absent() {
    assert_hex_matches_json("frame-chatmsg-fans1");
    let body = std::str::from_utf8(&fixture_bytes("frame-chatmsg-fans1")[12..])
        .expect("载荷是 UTF-8")
        .to_string();
    assert!(
        !body.contains("if@="),
        "夹具现状：载荷缺 if 字段（若QA 已修正，本用例需同步改写）"
    );
    assert!(
        decode_frame(&fixture_bytes("frame-chatmsg-fans1")).is_empty(),
        "缺 if -> 视为非粉丝 -> 必须丢弃（对齐 Dart douyu_danmaku.dart:76-81）"
    );
}

#[test]
fn fan_chatmsg_with_if_field_yields_chat_message() {
    let expected = fixture_json("frame-chatmsg-fans1");
    let want = &expected["expected"]["messages"][0];
    let body = "type@=chatmsg/if@=1/nn@=观众A/txt@=你好世界/col@=3/";
    let messages = decode_frame(&serialize(body));

    assert_eq!(messages.len(), 1, "带 if=1 的粉丝发言应产出恰 1 条");
    let got = &messages[0];
    assert_eq!(got.message_type, LiveMessageType::Chat);
    assert_eq!(got.user_name, want["user_name"].as_str().unwrap());
    assert_eq!(got.message, want["message"].as_str().unwrap());
    assert_eq!(got.color.r, want["color"]["r"].as_i64().unwrap() as i32);
    assert_eq!(got.color.g, want["color"]["g"].as_i64().unwrap() as i32);
    assert_eq!(got.color.b, want["color"]["b"].as_i64().unwrap() as i32);
}

/// 入站帧：非粉丝发言（`if=0`）**必须无产出且不抛**（Dart 只显示粉丝发言）。
#[test]
fn non_fan_chatmsg_frame_is_dropped() {
    assert_hex_matches_json("frame-chatmsg-fans0");
    let expected = fixture_json("frame-chatmsg-fans0");
    assert!(
        expected["expected"]["messages"]
            .as_array()
            .expect("messages 数组")
            .is_empty(),
        "夹具本身应声明无产出"
    );
    assert!(
        decode_frame(&fixture_bytes("frame-chatmsg-fans0")).is_empty(),
        "if!=1 的弹幕必须被丢弃"
    );
}

/// 入站帧：`@S` / `@A` 转义必须还原为 `/` 与 `@`。
#[test]
fn escaped_chatmsg_frame_decodes_escapes() {
    assert_hex_matches_json("frame-chatmsg-escaped");
    let expected = fixture_json("frame-chatmsg-escaped");
    let messages = decode_frame(&fixture_bytes("frame-chatmsg-escaped"));
    assert_eq!(messages.len(), 1);
    let want = &expected["expected"]["messages"][0];
    assert_eq!(messages[0].user_name, want["user_name"].as_str().unwrap());
    assert_eq!(messages[0].message, want["message"].as_str().unwrap());
}

/// 入站帧：醒目留言（`comm_chatmsg`）产出 SC，价格分转元。
#[test]
fn comm_chatmsg_frame_yields_super_chat() {
    assert_hex_matches_json("frame-comm-chatmsg-superchat");
    let expected = fixture_json("frame-comm-chatmsg-superchat");
    let messages = decode_frame(&fixture_bytes("frame-comm-chatmsg-superchat"));
    assert_eq!(messages.len(), 1, "应产出恰 1 条 SC");

    let got = &messages[0];
    let want = &expected["expected"]["messages"][0]["data"];
    assert_eq!(got.message_type, LiveMessageType::SuperChat);
    assert_eq!(
        got.user_name, "SUPER_CHAT_MESSAGE",
        "外层消息固定用占位文本承载 SC（App 侧靠它识别卡片，对齐 Dart）"
    );
    let (user_name, message, price, start_ms, end_ms, face) = super_chat_data(got);
    assert_eq!(user_name, want["user_name"].as_str().unwrap());
    assert_eq!(message, want["message"].as_str().unwrap());
    assert_eq!(price, want["price"].as_i64().unwrap() as i32);
    assert_eq!(start_ms, want["start_time_ms"].as_i64().unwrap());
    assert_eq!(end_ms, want["end_time_ms"].as_i64().unwrap());
    assert_eq!(face, want["face"].as_str().unwrap());
}

/// 入站帧：高能弹幕（`voice_trlt`）产出 SC，秒级时间戳换算为毫秒。
#[test]
fn voice_trlt_frame_yields_super_chat() {
    assert_hex_matches_json("frame-voice-trlt-superchat");
    let expected = fixture_json("frame-voice-trlt-superchat");
    let messages = decode_frame(&fixture_bytes("frame-voice-trlt-superchat"));
    assert_eq!(messages.len(), 1, "应产出恰 1 条高能弹幕");

    let got = &messages[0];
    let want = &expected["expected"]["messages"][0]["data"];
    assert_eq!(got.message_type, LiveMessageType::SuperChat);
    let (user_name, message, price, start_ms, end_ms, face) = super_chat_data(got);
    assert_eq!(user_name, want["user_name"].as_str().unwrap());
    assert_eq!(message, want["message"].as_str().unwrap());
    assert_eq!(price, want["price"].as_i64().unwrap() as i32);
    assert_eq!(
        start_ms, want["start_time_ms"].as_i64().unwrap(),
        "acptime(秒) 必须换算为毫秒"
    );
    assert_eq!(end_ms, want["end_time_ms"].as_i64().unwrap());
    assert_eq!(face, want["face"].as_str().unwrap());
}

/// 入站帧：`uenter`（进入直播间）显式忽略。
#[test]
fn uenter_frame_is_ignored() {
    assert_hex_matches_json("frame-uenter-ignored");
    assert!(
        decode_frame(&fixture_bytes("frame-uenter-ignored")).is_empty(),
        "uenter 必须无产出（Dart 显式空分支）"
    );
}

/// 入站帧：声明长度越界的脏帧 -> 解包失败 -> 无产出、不抛（AC-28）。
#[test]
fn dirty_length_frame_is_swallowed() {
    assert_hex_matches_json("frame-dirty-length");
    let bytes = fixture_bytes("frame-dirty-length");
    assert!(
        deserialize(&bytes).is_none(),
        "声明长度超出实际长度时必须解包失败"
    );
    assert!(
        decode_frame(&bytes).is_empty(),
        "脏帧不得产出消息，也不得 panic"
    );
}