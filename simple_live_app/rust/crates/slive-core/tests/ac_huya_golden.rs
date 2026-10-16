//! 虎牙 anticode golden 与 HTTP quirks 契约用例（IP-4 夹具基线 · QA 产出）。
//!
//! 拆成独立文件是为守住**单文件 ≤ 300 行**门禁（`13-spec.md §9`）；
//! 夹具与 TARS 字节布局契约在 `ac_huya_fixtures.rs`。同样**不 import 平台函数**。

mod fxcommon;

use fxcommon::{read_text, sample};
use serde_json::Value;

const PLATFORM: &str = "huya";

fn anticode_golden() -> Value {
    serde_json::from_str(&read_text(PLATFORM, "golden/golden-anticode.json"))
        .unwrap_or_else(|e| panic!("解析 golden-anticode.json 失败: {e}"))
}

// =====================================================================
// 一、anticode golden：随机字段必须显式登记
// =====================================================================
#[test]
fn anticode_golden_declares_nondeterministic_fields() {
    let doc = anticode_golden();
    assert_eq!(doc["_meta"]["platform"], PLATFORM);
    assert_eq!(doc["_meta"]["needs_realtime_validation"], false);
    // ct/uuid 走 Random()（Dart:374-376），必须显式登记为不可 golden，
    // 否则会有人把它们写死成期望值。
    let nd = doc["_meta"]["nondeterministic_fields"].as_array().expect("字段");
    assert!(nd.iter().any(|v| v == "ct"));
    assert!(nd.iter().any(|v| v == "uuid"));
    assert!(!doc["cases"].as_array().expect("cases").is_empty());
}

#[test]
fn anticode_golden_covers_wap_and_pc_branches() {
    // Dart:357 `isWap = platformId == 103`；两条分支输出的键不同。
    let cases = anticode_golden()["cases"].as_array().expect("cases").clone();
    let wap = cases
        .iter()
        .find(|c| c["name"].as_str().is_some_and(|n| n.contains("wap")))
        .expect("缺 wap 分支");
    assert_eq!(wap["expect"]["_wap_branch"], true);
    assert!(wap["expect"]["uid"].is_i64(), "wap 分支用原始 uid");
    assert!(wap["expect"]["u"].is_null(), "wap 分支不应有 u");

    let pc = cases
        .iter()
        .find(|c| c["name"].as_str().is_some_and(|n| n.contains("pc-branch")))
        .expect("缺 pc 分支");
    assert!(pc["expect"]["u"].is_i64(), "pc 分支用 rotl64 后的 u");
    assert!(pc["expect"]["uid"].is_null(), "pc 分支不应有 uid");

    let pass = cases
        .iter()
        .find(|c| c["name"].as_str().is_some_and(|n| n.contains("no-fm")))
        .expect("缺无 fm 兜底变体");
    assert!(
        pass["expect"]["passthrough"].as_str().is_some(),
        "无 fm 时应原样返回 antiCode（Dart:350-352）"
    );
}

#[test]
fn anticode_golden_values_are_hex_md5_and_ws_time() {
    // wsSecret 是 32 位小写 hex；wsTime 原样透传（Dart:369）。
    // 注意：无 fm 的兜底分支**提前返回**（Dart:350-352），故没有这些字段。
    let cases = anticode_golden()["cases"].as_array().expect("cases").clone();
    let mut checked = 0;
    for c in &cases {
        let expect = &c["expect"];
        if let Some(passthrough) = expect["passthrough"].as_str() {
            assert!(!passthrough.is_empty(), "{}的 passthrough 为空", c["name"]);
            assert!(
                expect.get("wsSecret").is_none(),
                "{}是提前返回分支，不应有 wsSecret",
                c["name"]
            );
            continue;
        }
        let secret = expect["wsSecret"].as_str().expect("wsSecret");
        assert_eq!(secret.len(), 32, "{}的 wsSecret 应为 32 位 hex", c["name"]);
        assert!(secret.chars().all(|ch| ch.is_ascii_hexdigit()), "含非 hex 字符");
        assert!(
            expect["wsTime"].as_str().is_some_and(|w| !w.is_empty()),
            "{}缺 wsTime",
            c["name"]
        );
        checked += 1;
    }
    assert!(checked >= 2, "实际校验的分支过少：{checked}");
}

#[test]
fn anticode_golden_fixes_the_clock() {
    // seqid = presenterUid + clacStartTime（Dart:362），必须钉住毫秒时间戳，
    // 否则 golden 不可重放。
    let cases = anticode_golden()["cases"].as_array().expect("cases").clone();
    for c in &cases {
        assert!(
            c["input"]["clac_start_ms"].as_i64().expect("clac_start_ms") > 0,
            "{} 未固定毫秒时间戳",
            c["name"]
        );
        assert!(c["input"]["anti_code"].as_str().is_some_and(|a| !a.is_empty()));
        assert!(c["input"]["stream"].as_str().is_some_and(|s| !s.is_empty()));
    }
}

// =====================================================================
// 二、HTTP quirks（Q5 gid 四类型 / Q6 roomId 前缀）
// =====================================================================
#[test]
fn gid_base_sample_covers_map_double_and_int() {
    // huya_site.dart:76-84 对 gid 有 Map/double/int/其他 四条分支。
    let s = sample(PLATFORM, "live_cdn_huya_com_liveconfig_game_bussLive");
    let data = s["response"]["data"].as_array().expect("data 是数组");
    assert!(data[0]["gid"].is_object(), "第 1 条应是 Map 形态");
    assert!(
        data[0]["gid"]["value"].as_str().expect("value").contains(','),
        "Map 形态的 value 应是逗号分隔串（取 first）"
    );
    assert!(data[1]["gid"].is_number(), "第 2 条应是数字形态");
    assert!(data[2]["gid"].is_i64() || data[2]["gid"].is_u64());
    assert_eq!(
        s["expected"]["sub_categories"][0]["id"], "1001",
        "逗号串应取 first"
    );
    // pic 由 gid 拼接（Dart:90）
    assert_eq!(
        s["expected"]["sub_categories"][0]["pic"],
        "https://huyaimg.msstatic.com/cdnimage/game/1001-MS.jpg"
    );
}

#[test]
fn search_rooms_use_yy_prefixed_room_id() {
    // Q6（:441）：roomId = "yy/{yyid}"，不是纯 yyid。
    let s = sample(PLATFORM, "search_cdn_huya_com_rooms");
    assert_eq!(s["expected"]["items"][0]["room_id"], "yy/660000");
    // 搜索与主播搜索取不同维度：v=4 -> response["3"]，v=1 -> response["1"]
    assert!(s["response"]["response"]["3"].is_object());
    let anchors = sample(PLATFORM, "search_cdn_huya_com_anchors");
    assert!(anchors["response"]["response"]["1"].is_object());
}

#[test]
fn cover_query_suffix_is_appended_only_when_absent() {
    // huya_site.dart:110-113：不含 '?' 才追加，且**带尾随 &**。
    let exp = sample(PLATFORM, "www_huya_com_cache_php")["expected"].clone();
    assert_eq!(
        exp["items"][0]["cover"],
        "https://example.huya.com/shot.jpg?x-oss-process=style/w338_h190&"
    );
    let variants = sample(PLATFORM, "www_huya_com_cache_php")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let has_q = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("已含 ?")))
        .expect("缺已含 query 的变体");
    assert_eq!(
        has_q["expected"]["items"][0]["cover"],
        "https://x.com/a.jpg?w=1",
        "已含 ? 时不得再追加"
    );
}

#[test]
fn cache_php_introduction_falls_back_to_room_name() {
    // huya_site.dart:114-117：introduction 为空则回落 roomName。
    let variants = sample(PLATFORM, "www_huya_com_cache_php")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("introduction")))
        .expect("缺 introduction 为空的变体");
    assert_eq!(v["expected"]["items"][0]["title"], "房间名");
}

#[test]
fn total_count_is_string_and_parses_leniently() {
    // huya_site.dart:124 用 int.tryParse(toString())，两种类型都要兼容。
    let s = sample(PLATFORM, "www_huya_com_cache_php");
    assert!(
        s["response"]["data"]["datas"][0]["totalCount"].is_string(),
        "样本须复现 totalCount 是字符串"
    );
    assert_eq!(s["expected"]["items"][0]["online"], 12345);
    let variants = s["variants"].as_array().expect("variants").clone();
    let bad = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("非数字")))
        .expect("缺非数字变体");
    assert_eq!(bad["expected"]["items"][0]["online"], 0);
}

#[test]
fn recommend_and_category_share_response_shape_but_differ_in_query() {
    // 两者打同一端点（cache.php），区别只在是否带 gameId（Dart:105 vs :198）。
    let rooms = sample(PLATFORM, "www_huya_com_cache_php");
    assert!(rooms["endpoint"].as_str().expect("endpoint").contains("gameId={gid}"));
    // hasMore = page < totalPage（Dart:128/:221）
    let last = rooms["variants"]
        .as_array()
        .expect("variants")
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("最后一页")))
        .expect("缺最后一页变体");
    assert_eq!(last["expected"]["has_more"], false);
}

// =====================================================================
// 三、错误流覆盖度
// =====================================================================
#[test]
fn error_flow_variants_exist_for_key_endpoints() {
    {
        let key = "udblgn_huya_com_web_anonymousLogin";
        let doc = sample(PLATFORM, key);
        let variants = doc["variants"].as_array().expect("variants");
        assert!(
            variants.iter().any(|v| v["expected"]["error"].as_str().is_some()),
            "{key} 缺错误流变体"
        );
    }
}

#[test]
fn html_samples_note_declares_text_carrier() {
    // 响应体为 HTML 的样本用 __raw_html 承载，加载时按文本注入 mock。
    let meta = &fxcommon::http_samples(PLATFORM)["_meta"];
    assert!(
        meta["html_samples_note"].as_str().is_some_and(|v| v.contains("__raw_html")),
        "须说明 HTML 样本的承载字段"
    );
    assert!(
        meta["realtime_validation_plan"].as_str().is_some_and(|v| v.contains("正则")),
        "须说明详情页正则的抓包校验重点"
    );
}