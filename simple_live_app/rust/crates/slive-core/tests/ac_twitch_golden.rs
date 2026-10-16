//! Twitch golden 与 HTTP quirks 契约用例（IP-5 夹具基线 · QA 产出）。
//!
//! 拆成独立文件是为守住**单文件 ≤ 300 行**门禁（`13-spec.md §9`）；
//! 夹具与 IRC/m3u8 契约在 `ac_twitch_fixtures.rs`。同样**不 import 平台函数**。

mod fxcommon;

use fxcommon::{read_text, sample};
use serde_json::Value;

const PLATFORM: &str = "twitch";

fn quality_golden() -> Value {
    serde_json::from_str(&read_text(PLATFORM, "golden/golden-quality-name.json"))
        .unwrap_or_else(|e| panic!("解析 golden-quality-name.json 失败: {e}"))
}

// =====================================================================
// 一、清晰度阈值 golden
// =====================================================================
#[test]
fn quality_golden_needs_no_packet_capture() {
    let doc = quality_golden();
    assert_eq!(doc["_meta"]["platform"], PLATFORM);
    assert_eq!(
        doc["_meta"]["needs_realtime_validation"], false,
        "阈值表在 Dart 里是硬编码常量，无需抓包"
    );
    assert!(
        doc["_meta"]["boundary_note"].as_str().is_some_and(|v| v.contains("严格大于")),
        "须写明阈值是严格大于"
    );
}

#[test]
fn quality_golden_covers_every_boundary_and_boundary_plus_one() {
    // 阈值全是 `>`，故每档边界值与其 +1 都必须在场，否则「恰好等于阈值」的
    // 归属无被钉住。
    let cases = quality_golden()["cases"].as_array().expect("cases").clone();
    let bws: Vec<i64> = cases.iter().filter_map(|c| c["bandwidth"].as_i64()).collect();
    for boundary in [500_000i64, 1_000_000, 2_500_000, 5_000_000] {
        assert!(bws.contains(&boundary), "缺边界值 {boundary}");
        assert!(bws.contains(&(boundary + 1)), "缺边界+1 {boundary}");
    }
    assert!(bws.contains(&0), "缺 0（最低档兜底）");
}

#[test]
fn quality_golden_threshold_table_is_recomputed() {
    // 逐档独立复算阈值表（twitch_site.dart:182-188），确认 golden 未被篡改。
    let cases = quality_golden()["cases"].as_array().expect("cases").clone();
    for c in &cases {
        let bw = c["bandwidth"].as_i64().expect("bandwidth");
        let want = if bw > 5_000_000 {
            "1080P"
        } else if bw > 2_500_000 {
            "720P"
        } else if bw > 1_000_000 {
            "480P"
        } else if bw > 500_000 {
            "360P"
        } else {
            "自动"
        };
        assert_eq!(c["expected_name"], want, "bandwidth={bw} 的档位名不符");
        assert_eq!(c["expected_sort"], bw, "sort 应等于 bandwidth");
    }
}

// =====================================================================
// 二、HTTP quirks：Q7 title 回落成字符串 "null"
// =====================================================================
#[test]
fn title_fallback_to_literal_null_is_pinned() {
    // Dart:229 `?? "null"` 回落成**字符串 "null"**，不是空串。
    // 不得「顺手改成空串」——会与 Dart 行为不一致。
    let variants = sample(PLATFORM, "gql_twitch_tv_room_shell")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("lastBroadcast")))
        .expect("缺 lastBroadcast 缺失变体");
    assert_eq!(v["expected"]["title"], "null");
    assert!(
        v["expected"]["note"].as_str().is_some_and(|n| n.contains("字符串")),
        "须写明回落成字符串"
    );
}

#[test]
fn offline_variant_forces_zero_online() {
    // Twitch 未开播时 online 强制 0（Dart:236 `online ? viewersCount : 0`）。
    let variants = sample(PLATFORM, "gql_twitch_tv_room_shell")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("stream 为 null")))
        .expect("缺未开播（stream=null）变体");
    assert!(v["response"][0]["data"]["userOrError"]["stream"].is_null());
    assert_eq!(v["expected"]["status"], false);
    assert_eq!(v["expected"]["online"], 0, "未播时 online 强制 0");
    assert!(
        v["expected"]["note"].as_str().is_some_and(|n| n.contains("online")),
        "须写明 online 的取值口径"
    );
}

#[test]
fn room_detail_base_expectation_uses_stream_viewers() {
    let exp = sample(PLATFORM, "gql_twitch_tv_room_shell")["expected"].clone();
    // roomId 就是 login（Twitch 用 login 作房间号）
    assert_eq!(exp["room_id"], "alice");
    assert_eq!(exp["url"], "https://www.twitch.tv/alice");
    assert_eq!(exp["danmaku_data"], "alice", "IRC JOIN 用的就是 login");
    assert_eq!(exp["data"], Value::Null, "Twitch 不走取流接口拼 URL");
    assert_eq!(exp["online"], 12345, "在播时 online = viewersCount");
}

// =====================================================================
// 三、m3u8 错位边界
// =====================================================================
#[test]
fn bandwidth_shortage_makes_trailing_url_automatic_quality() {
    // Dart:164 `i < bandwidthList.length ? parse : 0` —— 多出的 URL 拿 bandwidth=0
    // -> quality='自动'、sort=0，且因降序排序排到最后。
    let variants = sample(PLATFORM, "usher_ttvnw_net_master_m3u8")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("错位")))
        .expect("缺错位变体");
    assert!(
        v["expected"]["note"].as_str().is_some_and(|n| n.contains("自动")),
        "须写明多出的 URL 归入「自动」档"
    );
    // 该变体确实少了一个 BANDWIDTH（3 个 URL + 3 个 BW，但少了一个 EXT-X-STREAM-INF）
    let content = v["response"]["__raw_m3u8"].as_str().expect("__raw_m3u8");
    let bw = content.matches("BANDWIDTH=").count();
    let urls = content.lines().filter(|l| l.starts_with("https://")).count();
    assert!(bw < urls, "错位变体应满足 BANDWIDTH 少于 URL 数（{bw} < {urls}）");
}

#[test]
fn relative_urls_variant_exercises_m3u8_suffix_fallback() {
    // Dart:151-157：无 'https://' 行时改取以 'm3u8' 结尾的行。
    let variants = sample(PLATFORM, "usher_ttvnw_net_master_m3u8")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("相对路径")))
        .expect("缺相对路径变体");
    let content = v["response"]["__raw_m3u8"].as_str().expect("__raw_m3u8");
    assert!(
        !content.lines().any(|l| l.starts_with("https://")),
        "该变体不应含 https:// 行，否则走不到兜底分支"
    );
    assert!(content.contains("index-dvr.m3u8"), "仍须有 m3u8 结尾的行");
}

#[test]
fn empty_master_playlist_yields_no_qualities() {
    // 未开播/断流时返回空清单，不抛（Dart:151）。
    let variants = sample(PLATFORM, "usher_ttvnw_net_master_m3u8")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("空清单")))
        .expect("缺空清单变体");
    assert_eq!(v["response"]["__raw_m3u8"].as_str(), Some("#EXTM3U\n"));
    assert_eq!(v["expected"]["qualities"].as_array().expect("qualities").len(), 0);
}

// =====================================================================
// 四、抓包优先级与错误流
// =====================================================================
#[test]
fn persisted_query_hash_is_flagged_for_revalidation() {
    // Twitch 会轮换 persisted query 的 sha256Hash（Dart:249/:256 硬编码），
    // 失效则整个详情链路挂 —— 必须在夹具元数据里显式登记。
    let s = sample(PLATFORM, "gql_twitch_tv_room_shell");
    assert!(
        s["verify_note"].as_str().is_some_and(|v| v.contains("sha256Hash")),
        "须登记 persisted query hash 需抓包确认"
    );
}

#[test]
fn playback_token_sample_shape_is_pinned() {
    let s = sample(PLATFORM, "gql_twitch_tv_playback_access_token");
    let token = &s["response"]["data"]["streamPlaybackAccessToken"];
    assert!(token["value"].as_str().is_some(), "缺 token value");
    assert!(token["signature"].as_str().is_some(), "缺 token signature");
    let variants = s["variants"].as_array().expect("variants");
    assert!(
        variants.iter().any(|v| v["expected"]["error"].as_str().is_some()),
        "缺字段缺失的错误流"
    );
}

#[test]
fn short_response_variant_is_documented_as_dart_hazard() {
    // Dart:275-277 只记日志后继续，随后 roomInfo[1] 会 RangeError。
    let variants = sample(PLATFORM, "gql_twitch_tv_room_shell")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("长度")))
        .expect("缺长度不足变体");
    assert_eq!(
        v["response"].as_array().expect("数组").len(),
        1,
        "该变体只返回一项"
    );
    assert!(
        v["expected"]["error"].as_str().is_some_and(|e| e.contains("CoreError")),
        "须写明实现应抛 CoreError 而非 RangeError"
    );
}