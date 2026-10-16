//! Twitch 清晰度阈值表 golden（IP-5-PLAY-QUALITY）。
//!
//! 夹具：`tests/fixtures/twitch/golden/golden-quality-name.json` —— 照 Dart
//! `twitch_site.dart:182-188` 的阈值逐档枚举（含边界值与 ±1），共 11 例。
//! 全部阈值都是**严格大于**（`>`），故恰好等于阈值时归入下一档 —— 本测试守住该语义。

mod twitch_common;

use serde_json::Value;
use slive_core::platforms::twitch::m3u8::{parse_variants, quality_name};

use twitch_common::read_text;

fn cases() -> Vec<Value> {
    serde_json::from_str::<Value>(&read_text("golden/golden-quality-name.json"))
        .expect("解析 golden-quality-name.json")["cases"]
        .as_array()
        .expect("cases 数组")
        .clone()
}

#[test]
fn golden_quality_name_thresholds_match_dart() {
    let mut count = 0;
    for case in cases() {
        let bandwidth = case["bandwidth"].as_i64().expect("bandwidth");
        assert_eq!(
            quality_name(bandwidth),
            case["expected_name"].as_str().expect("expected_name"),
            "bandwidth={bandwidth} 的清晰度名不符"
        );
        count += 1;
    }
    assert!(count >= 11, "边界用例应至少 11 条，实际 {count}");
}

#[test]
fn golden_quality_name_is_strictly_greater_at_boundaries() {
    // 显式复核「等于阈值归下一档」：阈值 500000/1000000/2500000/5000000。
    for (bandwidth, expect) in [
        (500_000i64, "自动"),
        (500_001, "360P"),
        (1_000_000, "360P"),
        (1_000_001, "480P"),
        (2_500_000, "480P"),
        (2_500_001, "720P"),
        (5_000_000, "720P"),
        (5_000_001, "1080P"),
    ] {
        assert_eq!(quality_name(bandwidth), expect, "bandwidth={bandwidth}");
    }
}

#[test]
fn negative_and_missing_bandwidth_are_treated_as_auto() {
    // 畸形输入（BANDWIDTH 解析失败 -> 0，或负值）不应 panic，且归入最低档。
    assert_eq!(quality_name(0), "自动");
    assert_eq!(quality_name(-1), "自动");
}

#[test]
fn parse_variants_does_not_infer_quality_from_resolution() {
    // 防「特判式实现」：只按 BANDWIDTH 映射，不得看 RESOLUTION 字段。
    let content = "#EXTM3U\n\
        #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1920x1080\n\
        https://edge/low-bandwidth-high-res.m3u8\n";
    let got = parse_variants(content);
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].bandwidth, 900_000);
    assert_eq!(quality_name(got[0].bandwidth), "360P", "按带宽而非分辨率");
}

#[test]
fn golden_fixture_is_marked_synthetic_with_provenance() {
    let doc: Value =
        serde_json::from_str(&read_text("golden/golden-quality-name.json")).expect("解析");
    assert_eq!(doc["_meta"]["synthetic"], true, "阈值表应标注为合成夹具");
    assert_eq!(doc["_meta"]["platform"], "twitch");
    // `target_rust_fn` 由 QA 维护（`fxcommon::assert_ws_meta` 只要求非空）。
    // QA 快照里的路径是 `...::site::quality_name`，而实现落在 `m3u8::quality_name`
    // （职责拆分：阈值表与 m3u8 解析同属一个能力模块）。**不擅自改 QA 字段**，
    // 只断言其存在；路径同步已列入回传清单交 QA 更新。
    assert!(
        doc["_meta"]["target_rust_fn"]
            .as_str()
            .is_some_and(|s| !s.is_empty()),
        "target_rust_fn 须非空（QA 契约）"
    );
    // 真正的落点核对：实现确实提供该函数（编译期可见）。
    assert_eq!(quality_name(6_000_000), "1080P");
}
