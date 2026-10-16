//! 斗鱼夹具契约用例（IP-3 夹具基线 · QA 产出）。
//!
//! 本文件只保留**夹具自身契约**（元数据/字节布局/转义/过滤等）；「平台行为」断言已由
//! 各平台实现测试取代（`ac_douyu_http.rs` 等）；原「待 IP-x 接入后解除」的 `#[ignore]`
//! 骨架已于 2026-10-17 合并前评审移除（理由已失真且被取代）。
//!
//! 本文件**不 import 任何平台函数**：只读夹具 + 校验字节布局。
//! 这样 IP-3 正在改 `site.rs` / `sign.rs` 的签名时，本文件不会连带编译失败。
//!
//! 纪律：断言只钉「夹具 → 期望」的方向；期望值来自 `.expected.json`
//! （QA 照 Dart 解析代码独立推导）。**禁止**为了让实现通过而改夹具。

mod fxcommon;

use fxcommon::{
    assert_hex_matches_bin, assert_http_samples_meta, assert_ws_meta, read_bytes, read_text,
    sample, ws_expected_files,
};
use serde_json::Value;

const PLATFORM: &str = "douyu";

fn expected_doc(stem: &str) -> Value {
    serde_json::from_str(&read_text(PLATFORM, &format!("ws/{stem}.expected.json")))
        .unwrap_or_else(|e| panic!("解析 {stem} 失败: {e}"))
}

// =====================================================================
// 一、夹具元数据契约
// =====================================================================

#[test]
fn fixture_meta_declares_required_fields() {
    let count = assert_http_samples_meta(PLATFORM);
    assert!(count >= 10, "斗鱼 HTTP 样本数量异常少：{count}");
}

#[test]
fn ws_frames_meta_and_hex_are_consistent() {
    let names = ws_expected_files(PLATFORM);
    assert!(names.len() >= 10, "斗鱼 WS 帧数量异常少：{}", names.len());
    for name in names {
        let stem = name.trim_end_matches(".expected.json");
        let doc = expected_doc(stem);
        assert_ws_meta(PLATFORM, &name, &doc);
        assert_hex_matches_bin(PLATFORM, stem, &doc);
    }
}

#[test]
fn dirty_frames_declare_no_output() {
    // 脏帧必须钉「无产出」，否则实现可以随意抛错而不被夹具发现。
    {
        let stem = "frame-dirty-length";
        let doc = expected_doc(stem);
        assert_eq!(
            doc["expected"]["messages"].as_array().expect("messages").len(),
            0,
            "{stem} 不得期望任何消息产出"
        );
        assert!(
            doc["_meta"]["corruption"].as_str().is_some(),
            "{stem} 必须写明破坏方式"
        );
    }
}

// =====================================================================
// 二、STT 包头契约（12 字节小端 + 定长尾 0）
// =====================================================================

#[test]
fn stt_frame_header_layout_matches_dart() {
    // 推导依据 douyu_danmaku.dart:152-193：
    //   [0..4)   fullMsgLength(i32 LE)
    //   [4..8)   fullMsgLength2(i32 LE) 同值
    //   [8..10)  packType(i16 LE) = 689
    //   [10]     encrypted = 0
    //   [11]     reserved  = 0
    //   [12..12+n) body
    //   [12+n]   固定 0
    //   总长 = 12 + n + 1
    for stem in ["frame-chatmsg-fans1", "frame-uenter-ignored", "req-loginreq"] {
        let b = read_bytes(PLATFORM, &format!("ws/{stem}.bin"));
        assert!(b.len() >= 13, "{stem} 长度不足一个最小帧");

        let full = i32::from_le_bytes([b[0], b[1], b[2], b[3]]);
        let full2 = i32::from_le_bytes([b[4], b[5], b[6], b[7]]);
        assert_eq!(full, full2, "{stem} 的两个 fullMsgLength 必须相等");
        assert_eq!(
            full as usize,
            b.len() - 4,
            "{stem}：fullMsgLength 应等于「实际长度 - 4」"
        );
        assert_eq!(
            i16::from_le_bytes([b[8], b[9]]),
            689,
            "{stem} 的 packType 应为 689"
        );
        assert_eq!(b[10], 0, "{stem} 的 encrypted 应为 0");
        assert_eq!(b[11], 0, "{stem} 的 reserved 应为 0");
        assert_eq!(*b.last().expect("非空"), 0, "{stem} 的帧尾应为 0");

        let body = std::str::from_utf8(&b[12..b.len() - 1]).expect("body 是 UTF-8");
        assert!(body.starts_with("type@="), "{stem} 的 body 应以 type@= 开头");
    }
}

#[test]
fn stt_escape_pairs_round_trip() {
    // @S -> '/'、@A -> '@'（douyu_danmaku.dart:226-228）。
    let doc = expected_doc("frame-chatmsg-escaped");
    let body = doc["stt_body"].as_str().expect("stt_body");
    assert!(body.contains("@A"), "转义夹具应含 @A");
    assert!(!body.contains("nn@=a@b/"), "用户名里的 @ 必须已转义，否则解码歧义");

    let msg = &doc["expected"]["messages"][0];
    assert_eq!(msg["user_name"], "a@b", "@A 应还原为 @");
    assert!(
        msg["message"].as_str().expect("message").contains('/'),
        "@S 应还原为 /"
    );
}

#[test]
fn fans_filter_is_pinned() {
    // Q4：chatmsg 仅 `if=='1'` 才产出（阴间弹幕过滤，douyu_danmaku.dart:81）。
    let dropped = expected_doc("frame-chatmsg-fans0");
    assert_eq!(
        dropped["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "if='0' 必须无产出"
    );
    let kept = expected_doc("frame-chatmsg-fans1");
    assert_eq!(
        kept["expected"]["messages"].as_array().expect("messages").len(),
        1,
        "if='1' 必须产出 1 条"
    );
}

#[test]
fn uenter_must_be_ignored() {
    // douyu_danmaku.dart:143 `else if (type != "uenter") {}`
    let doc = expected_doc("frame-uenter-ignored");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "uenter 必须被忽略"
    );
}

#[test]
fn superchat_price_and_time_units_are_pinned() {
    // comm_chatmsg：cprice 分 -> 元；now(ms) 起点 + cet(秒) 时长（:89-117）
    let a = expected_doc("frame-comm-chatmsg-superchat");
    let da = &a["expected"]["messages"][0]["data"];
    assert_eq!(da["price"], 50, "cprice=5000 分 -> 50 元");
    assert_eq!(da["start_time_ms"], 1768936072000i64);
    assert_eq!(da["end_time_ms"], 1768936372000i64, "cet=300 秒");

    // voice_trlt：acptime/etime 单位为**秒** -> *1000（:118-142）
    let b = expected_doc("frame-voice-trlt-superchat");
    let db = &b["expected"]["messages"][0]["data"];
    assert_eq!(db["price"], 50, "realPrice=5000 分 -> 50 元");
    assert_eq!(db["start_time_ms"], 1768936072000i64, "acptime 秒 -> 毫秒");
    assert_eq!(db["end_time_ms"], 1768936192000i64, "etime 秒 -> 毫秒");
}

// =====================================================================
// 四、MockTransport 可承载斗鱼样本（seam 就绪检查）
// =====================================================================

#[test]
fn mock_transport_can_serve_douyu_samples() {
    use slive_core::testing::{FakeTime, MockTransport};
    use std::sync::Arc;

    let mock = Arc::new(MockTransport::new());
    let body = serde_json::to_string(&sample(PLATFORM, "www_douyu_com_betard")["response"])
        .expect("序列化");
    mock.stub("www.douyu.com/betard", &body);

    let _time = FakeTime::new(1_700_000_000);
    assert_eq!(
        mock.request_count("www.douyu.com/betard"),
        0,
        "尚未发起请求时计数应为 0"
    );
    assert!(mock.requests().is_empty());
}
