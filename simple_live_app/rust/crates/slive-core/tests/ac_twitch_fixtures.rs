//! Twitch 夹具契约用例（IP-5 夹具基线 · QA 产出）。
//!
//! 本文件只保留**夹具自身契约**（元数据/字节布局/转义/过滤等）；「平台行为」断言已由
//! 各平台实现测试取代（`ac_douyu_http.rs` 等）；原「待 IP-x 接入后解除」的 `#[ignore]`
//! 骨架已于 2026-10-17 合并前评审移除（理由已失真且被取代）。
//! 本文件**不 import 平台函数**；golden 与 HTTP quirks 见 `ac_twitch_golden.rs`。
//!
//! 纪律：**Dart 现状即「不支持」的能力，迁移必须同样不支持**（见
//! `_meta.unsupported_by_dart`）——顺手实现会破坏 AC-30「回归为零」。

mod fxcommon;

use fxcommon::{
    assert_hex_matches_bin, assert_http_samples_meta, assert_ws_meta, read_bytes, read_text,
    sample, ws_expected_files,
};
use serde_json::Value;

const PLATFORM: &str = "twitch";

fn expected_doc(stem: &str) -> Value {
    serde_json::from_str(&read_text(PLATFORM, &format!("ws/{stem}.expected.json")))
        .unwrap_or_else(|e| panic!("解析 {stem} 失败: {e}"))
}

// =====================================================================
// 一、夹具元数据契约
// =====================================================================
#[test]
fn room_detail_batch_shape_is_two_elements() {
    // _getRoomInfo 一次性 POST 两个 persisted query，按**下标**取 first 与 [1]（:208-210）。
    let resp = sample(PLATFORM, "gql_twitch_tv_room_shell")["response"]
        .as_array()
        .expect("响应必须是数组")
        .clone();
    assert_eq!(resp.len(), 2, "须有 ChannelShell + StreamMetadata 两项");
    assert!(resp[0]["data"]["userOrError"].is_object(), "[0] 须含 userOrError");
    assert!(resp[1]["data"]["user"].is_object(), "[1] 须含 user");
    // 字段名是 profileImageURL（大写 URL）
    assert!(resp[0]["data"]["userOrError"]["profileImageURL"].is_string());
    assert!(resp[0]["data"]["userOrError"].get("profileImageUrl").is_none());
}

#[test]
fn fixture_meta_declares_required_fields() {
    let count = assert_http_samples_meta(PLATFORM);
    assert!(count >= 3, "Twitch HTTP 样本数量异常少：{count}");
}

#[test]
fn ws_frames_meta_and_hex_are_consistent() {
    let names = ws_expected_files(PLATFORM);
    assert!(names.len() >= 10, "Twitch WS 帧数量异常少：{}", names.len());
    for name in names {
        let stem = name.trim_end_matches(".expected.json");
        let doc = expected_doc(stem);
        assert_ws_meta(PLATFORM, &name, &doc);
        assert_hex_matches_bin(PLATFORM, stem, &doc);
    }
}

#[test]
fn unsupported_capabilities_are_documented_not_silently_dropped() {
    // 「Dart 不支持」必须留痕，否则实现者会以为漏了夹具而去实现它。
    let un = &fxcommon::http_samples(PLATFORM)["_meta"]["unsupported_by_dart"];
    for cap in [
        "get_categories",
        "get_category_rooms",
        "get_recommend_rooms",
        "search_rooms",
        "search_anchors",
        "get_super_chat_message",
        "get_account_info/get_qr_code/get_qr_poll_result",
        "set_site_attrs",
    ] {
        assert!(
            un[cap].as_str().is_some_and(|v| !v.is_empty()),
            "未登记不支持的能力：{cap}"
        );
    }
    assert!(
        un["note"].as_str().is_some_and(|v| v.contains("不得")),
        "缺「不得顺手实现」的纪律说明"
    );
}

// =====================================================================
// 二、IRC 帧契约（三正则必须同时命中）
// =====================================================================
#[test]
fn privmsg_requires_all_three_tags() {
    // twitch_danmaku.dart:86-90：content / display-name / color 三者缺一即无产出。
    for stem in ["irc-privmsg-no-color", "irc-privmsg-no-display-name"] {
        let doc = expected_doc(stem);
        assert_eq!(
            doc["expected"]["messages"].as_array().expect("messages").len(),
            0,
            "{stem} 三正则不全命中，必须无产出"
        );
    }
    let ok = expected_doc("irc-privmsg-color");
    let msgs = ok["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs.len(), 1, "三标签齐全必须产出 1 条");
    assert_eq!(msgs[0]["user_name"], "Alice");
    assert_eq!(msgs[0]["message"], "Hello Twitch!");
    assert_eq!(msgs[0]["color"]["r"], 30, "1E90FF -> r=0x1E=30");
    assert_eq!(msgs[0]["color"]["g"], 144);
    assert_eq!(msgs[0]["color"]["b"], 255);
}

#[test]
fn system_notices_produce_nothing() {
    let doc = expected_doc("irc-notice-reconnect");
    assert_eq!(
        doc["expected"]["messages"].as_array().expect("messages").len(),
        0,
        "HOST_ON / RECONNECT 等系统消息不得包装成 chat"
    );
}

#[test]
fn ping_must_be_answered_and_produce_nothing() {
    // PING -> PONG，且不产出任何消息（Dart:77-80）。
    let doc = expected_doc("irc-ping");
    assert_eq!(doc["expected"]["messages"].as_array().expect("messages").len(), 0);
    let replies = doc["expected"]["replies"].as_array().expect("replies");
    assert_eq!(replies.len(), 1);
    assert!(
        replies[0].as_str().expect("reply").starts_with("PONG :"),
        "PING 必须回 PONG"
    );
}

#[test]
fn mixed_ping_privmsg_pins_dart_whole_frame_replace() {
    // Q8（Dart:79）：对**整帧** replaceFirst，混帧时回包会带上后续行——
    // 看着像 bug，但属既有行为，迁移必须一致（改动会破坏 AC-30）。
    let doc = expected_doc("irc-ping-privmsg-mixed");
    assert_eq!(doc["_meta"]["pinned_dart_behavior"], true);
    let replies = doc["expected"]["replies"].as_array().expect("replies");
    assert_eq!(replies.len(), 1);
    let reply = replies[0].as_str().expect("reply");
    assert!(reply.starts_with("PONG :"), "首词应被替换为 PONG");
    assert!(
        reply.contains("PRIVMSG"),
        "Dart 现状是把整帧带回（含后续 PRIVMSG 行），夹具须如实记录"
    );
    assert_eq!(doc["expected"]["messages"].as_array().expect("messages").len(), 1);
}

#[test]
fn multi_line_batch_expects_all_lines_in_order() {
    let doc = expected_doc("irc-multi-line-batch");
    let msgs = doc["expected"]["messages"].as_array().expect("messages");
    assert_eq!(msgs.len(), 3, "一帧三行须产出三条");
    let names: Vec<&str> = msgs.iter().filter_map(|m| m["user_name"].as_str()).collect();
    assert_eq!(names, ["Dave", "Eve", "Fox"], "产出顺序须与帧内顺序一致");
    // 内容里的冒号不得把消息从中间截断
    let colon = expected_doc("irc-privmsg-content-with-colon");
    let m = &colon["expected"]["messages"][0];
    assert_eq!(m["message"], "time is 12:30 now");
}

#[test]
fn crlf_boundary_expectation_is_pending_not_faked() {
    // Q-C 已裁决（照搬 Dart 不 trim），期望值仍等真实抓包（P-11）。
    let doc = expected_doc("irc-crlf-boundary");
    // 行为口径已裁决（照搬 Dart 不 trim），期望值仍等真实抓包（P-11）。
    assert_eq!(
        doc["expected"]["assertion"], "PENDING_REAL_CAPTURE",
        "已裁决但待抓包的项必须显式标记，不能伪装成已断言"
    );
    assert!(doc["expected"]["messages"].is_null(), "待抓包项不得写期望值");
    assert_eq!(doc["_meta"]["decision_pending"], true);
    assert_eq!(doc["expected"]["ruled"], true, "行为口径必须已裁决");
    assert!(
        doc["expected"]["ruling"].as_str().is_some_and(|r| r.contains("不 trim")),
        "裁决结论须写明方向"
    );
}

#[test]
fn client_requests_are_golden_bytes() {
    for (stem, must_contain) in [
        ("req-cap-req", "CAP REQ"),
        ("req-pass", "PASS SCHMOOPIIE"),
        ("req-join", "JOIN #"),
        ("req-pong-heartbeat", "PONG"),
    ] {
        let text = String::from_utf8(read_bytes(PLATFORM, &format!("ws/{stem}.bin")))
            .expect("UTF-8");
        assert!(text.contains(must_contain), "{stem} 内容不符：{text}");
        let doc = expected_doc(stem);
        assert_eq!(doc["_meta"]["direction"], "client->server");
    }
}

// =====================================================================
// 三、m3u8 清晰度契约
// =====================================================================
#[test]
fn m3u8_sample_has_aligned_bandwidth_and_urls() {
    // twitch_site.dart:163-166 按**下标**把 BANDWIDTH 与 URL 配对，
    // 两者数量/顺序必须严格对应，否则清晰度整体错位。
    let doc = sample(PLATFORM, "usher_ttvnw_net_master_m3u8");
    let content = doc["response"]["__raw_m3u8"].as_str().expect("__raw_m3u8");
    let bandwidths = content.matches("BANDWIDTH=").count();
    let urls = content.lines().filter(|l| l.starts_with("https://")).count();
    assert!(bandwidths >= 3, "样本应含多档清晰度");
    assert_eq!(bandwidths, urls, "BANDWIDTH 与 URL 数量必须 1:1（下标配对依赖它）");
    assert!(content.starts_with("#EXTM3U"), "m3u8 应以 #EXTM3U 开头");
}

#[test]
fn m3u8_variants_are_applied_not_described() {
    let variants = sample(PLATFORM, "usher_ttvnw_net_master_m3u8")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    assert!(variants.len() >= 4);
    for v in &variants {
        assert!(
            v["response"]["__raw_m3u8"].as_str().is_some_and(|m| !m.is_empty()),
            "变体 {} 缺 __raw_m3u8",
            v["name"]
        );
    }
    let names: Vec<&str> = variants.iter().filter_map(|v| v["name"].as_str()).collect();
    assert!(names.iter().any(|n| n.contains("相对路径")), "缺兜底分支变体");
    assert!(names.iter().any(|n| n.contains("错位")), "缺 BANDWIDTH 错位边界");
}

#[test]
fn m3u8_base_expectation_is_bandwidth_descending() {
    let qs = sample(PLATFORM, "usher_ttvnw_net_master_m3u8")["expected"]["qualities"]
        .as_array()
        .expect("qualities")
        .clone();
    assert_eq!(qs.len(), 4);
    assert_eq!(qs[0]["quality"], "1080P", "最高带宽须排最前");
    assert_eq!(qs[0]["sort"], 6000000);
    assert_eq!(qs[3]["quality"], "360P");
    for q in &qs {
        assert!(q["url"].as_str().is_some_and(|u| !u.is_empty()));
    }
}
