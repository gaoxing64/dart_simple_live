//! 虎牙夹具契约用例（IP-4 夹具基线 · QA 产出）。
//!
//! 本文件只保留**夹具自身契约**（元数据/字节布局/转义/过滤等）；「平台行为」断言已由
//! 各平台实现测试取代（`ac_douyu_http.rs` 等）；原「待 IP-x 接入后解除」的 `#[ignore]`
//! 骨架已于 2026-10-17 合并前评审移除（理由已失真且被取代）。
//!
//! 本文件**不 import 任何平台函数**，只读夹具 + 校验 TARS 字节布局。
//! 因此 IP-4 调整 `site.rs` / `danmaku` 的内部签名时本文件不会连带编译失败。
//! golden 与 HTTP quirks 见 `ac_huya_golden.rs`。

mod fxcommon;

use fxcommon::tars::{tars_read_head, assert_tars_fully_consumable};
use fxcommon::{
    assert_hex_matches_bin, assert_http_samples_meta, assert_ws_meta, read_bytes, read_text,
    sample, ws_expected_files,
};
use serde_json::Value;

const PLATFORM: &str = "huya";

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
    assert!(count >= 6, "虎牙 HTTP 样本数量异常少：{count}");
}

#[test]
fn ws_frames_meta_and_hex_are_consistent() {
    let names = ws_expected_files(PLATFORM);
    assert!(names.len() >= 8, "虎牙 WS 帧数量异常少：{}", names.len());
    for name in names {
        let stem = name.trim_end_matches(".expected.json");
        let doc = expected_doc(stem);
        assert_ws_meta(PLATFORM, &name, &doc);
        assert_hex_matches_bin(PLATFORM, stem, &doc);
    }
}

// =====================================================================
// 二、TARS 字节布局契约（对齐 tars_output_stream.dart）
// =====================================================================

#[test]
fn websocket_command_frames_have_expected_cmd_types() {
    // cmdType 取值来自 huya/model/huya_damaku_model.dart 的 EWebSocketCommandType。
    for (stem, want) in [
        ("frame-push-uri1400-chat", 7u8),
        ("frame-push-uri8006-online", 7),
        ("frame-push-v2-uri2001317-superchat-trigger", 22),
        ("frame-push-v2-uri2001314-ignored", 22),
        ("req-register-group", 16),
        ("req-heartbeat", 20),
    ] {
        let b = read_bytes(PLATFORM, &format!("ws/{stem}.bin"));
        let mut p = 0usize;
        let (tag, typ) = tars_read_head(&b, &mut p);
        assert_eq!(tag, 0, "{stem} 首字段应为 tag 0（cmdType）");
        assert_eq!(typ, 0, "{stem} 的 cmdType 应编码为 BYTE");
        assert_eq!(b[p], want, "{stem} 的 cmdType 不符");
    }
}

#[test]
fn websocket_command_is_fully_consumable() {
    // 帧必须恰好被读完（不多不少），否则解码器会读到越界数据。
    for stem in [
        "frame-push-uri1400-chat",
        "frame-push-uri8006-online",
        "frame-push-v2-uri2001317-superchat-trigger",
        "frame-push-v2-uri2001314-ignored",
        "req-register-group",
        "req-heartbeat",
    ] {
        assert_tars_fully_consumable(&read_bytes(PLATFORM, &format!("ws/{stem}.bin")), stem);
    }
}

// =====================================================================
// 三、弹幕消息分派契约
// =====================================================================
#[test]
fn uri1400_chat_and_color_zero_fallback_are_pinned() {
    let chat = expected_doc("frame-push-uri1400-chat");
    let msgs = chat["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs.len(), 1);
    assert_eq!(msgs[0]["type"], "chat");
    assert_eq!(msgs[0]["user_name"], "观众A");
    assert_eq!(msgs[0]["color"]["r"], 255, "fontColor 0xFF0000 -> r=255");
    assert_eq!(msgs[0]["color"]["g"], 0);
    assert_eq!(msgs[0]["color"]["b"], 0);

    // fontColor=0 -> Dart:234 回退白色
    let white = expected_doc("frame-push-uri1400-color0");
    let wm = white["expected"]["messages"].as_array().expect("messages");
    for ch in ["r", "g", "b"] {
        assert_eq!(wm[0]["color"][ch], 255, "color<=0 时 {ch} 必须是 255");
    }
}

#[test]
fn uri8006_is_online_count() {
    let doc = expected_doc("frame-push-uri8006-online");
    let msgs = doc["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs[0]["type"], "online");
    assert_eq!(msgs[0]["data_int"], 12345);
    assert_eq!(msgs[0]["user_name"], "");
}

#[test]
fn v2_frame_only_triggers_sc_and_emits_nothing() {
    // 钉死「不过度解码」：cmdType=22 只触发 SC 拉取，本帧不产出 LiveMessage。
    let doc = expected_doc("frame-push-v2-uri2001317-superchat-trigger");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0
    );
    let triggers = doc["expected"]["triggers"].as_array().expect("triggers");
    assert_eq!(triggers.len(), 1);
    assert_eq!(triggers[0]["iUri"], 2001317);
    // 旧 uri 反例（上游 97413c60）：2001314 不再触发
    let old = expected_doc("frame-push-v2-uri2001314-ignored");
    assert_eq!(
        old["expected"]["triggers"].as_array().expect("triggers").len(),
        0,
        "旧 uri 2001314 不得触发（上游 97413c60 口径）"
    );
    assert_eq!(doc["_meta"]["cmd_type"], 22);

    // V2 帧里的 iUri=1400 也不产出（Dart 只在 V1 分支处理聊天）
    let ignored = expected_doc("frame-push-v2-uri1400-ignored");
    assert_eq!(
        ignored["expected"]["messages"].as_array().expect("messages").len(),
        0
    );
}

#[test]
fn unknown_cmd_type_yields_nothing() {
    let doc = expected_doc("frame-unknown-cmdtype");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "未知 cmdType 走 Dart 的 else 空分支"
    );
}

#[test]
fn dirty_tag_frame_declares_silent_failure() {
    let doc = expected_doc("frame-dirty-tag");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "脏帧不得期望任何消息产出"
    );
    assert!(doc["_meta"]["corruption"].as_str().is_some());
}

// =====================================================================
// 四、房间页 HTML 契约（Dart 两条正则的输入前提）
// =====================================================================
#[test]
fn room_html_sample_supports_dart_regexes() {
    // huya_site.dart:240-241 依赖两个前提，缺一即解析失败：
    //   ①存在字面量 `var TT_ROOM_DATA = {...};`
    //   ②存在 `stream: {...}` 且 JSON **单行**（否则 split('\n')[0] 只拿到半截）
    let doc = sample(PLATFORM, "www_huya_com_room_html");
    let html = doc["response"]["__raw_html"].as_str().expect("__raw_html");
    assert!(html.contains("var TT_ROOM_DATA = "), "缺 TT_ROOM_DATA");
    assert!(html.contains("stream: {"), "缺 stream: 前缀");
    assert!(html.contains("\"state\":\"ON\""), "缺直播状态");
    assert!(html.contains("\"isReplay\":false"), "缺 isReplay");
    assert!(html.contains("vMultiStreamInfo"), "缺清晰度列表");
}

#[test]
fn room_html_variants_are_applied_not_described() {
    // 变体必须是**改好的真实 HTML**，否则用例无法消费。
    let variants = sample(PLATFORM, "www_huya_com_room_html")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    assert!(variants.len() >= 4, "房间页变体过少");
    for v in &variants {
        assert!(
            v["response"]["__raw_html"].as_str().is_some_and(|h| !h.is_empty()),
            "变体 {} 缺 __raw_html",
            v["name"]
        );
    }
    let off = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("未开播")))
        .expect("存在未开播变体");
    assert!(off["response"]["__raw_html"]
        .as_str()
        .expect("html")
        .contains("\"state\":\"OFF\""));
    let miss = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("缺少 TT_ROOM_DATA")))
        .expect("存在缺 TT_ROOM_DATA 变体");
    assert!(!miss["response"]["__raw_html"]
        .as_str()
        .expect("html")
        .contains("TT_ROOM_DATA"));
}

#[test]
fn hdr_and_4k_qualities_are_excluded_from_expectation() {
    // Dart:308（getRoomDetail 里含 HDR 的 continue）与 :149（getPlayQualities 里 4K continue）
    let exp = sample(PLATFORM, "www_huya_com_room_html")["expected"].clone();
    let names: Vec<&str> = exp["qualities"]
        .as_array()
        .expect("qualities")
        .iter()
        .filter_map(|q| q.as_str())
        .collect();
    assert!(!names.contains(&"HDR 超清"), "HDR 必须被跳过");
    assert!(!names.iter().any(|n| n.contains("4K")), "4K 必须被跳过");
    assert_eq!(
        exp["data"]["lines"].as_array().expect("lines").len(),
        2,
        "flv 与 hls 都非空时应产出 2 条线路"
    );
}
