//! 斗鱼签名 golden 与 HTTP quirks 契约用例（IP-3 夹具基线 · QA 产出）。
//!
//! 拆成独立文件是为守住**单文件 ≤ 300 行**门禁（`13-spec.md §9`）；
//! 夹具契约的另一半在 `ac_douyu_fixtures.rs`。同样**不 import 平台函数**。

mod fxcommon;

use fxcommon::{md5_hex, read_text, sample};
use serde_json::Value;

const PLATFORM: &str = "douyu";

fn golden_sign() -> Value {
    serde_json::from_str(&read_text(PLATFORM, "golden/golden-sign.json"))
        .unwrap_or_else(|e| panic!("解析 golden-sign.json 失败: {e}"))
}

// =====================================================================
// 一、签名 golden：期望值由**独立 MD5** 重算（AC-35「不自证」）
// =====================================================================

#[test]
fn sign_golden_md5_chain_is_self_consistent() {
    let doc = golden_sign();
    assert_eq!(doc["_meta"]["platform"], PLATFORM);
    assert_eq!(doc["_meta"]["needs_realtime_validation"], false, "算法确定性，无需抓包");
    let cases = doc["cases"].as_array().expect("cases");
    assert!(!cases.is_empty());
    for case in cases {
        let name = case["name"].as_str().expect("name");
        let inp = &case["input"];
        let key = inp["enc_key"]["key"].as_str().expect("key");
        let rand = inp["enc_key"]["rand_str"].as_str().expect("rand_str");
        let enc_time = inp["enc_key"]["enc_time"].as_u64().expect("enc_time");
        let is_special = inp["enc_key"]["is_special"].as_u64().expect("is_special") == 1;
        let rid = inp["room_id"].as_str().expect("room_id");
        let ts = inp["ts"].as_u64().expect("ts");

        // douyu_utils.dart:129-158：salt = is_special ? "" : "$rid$ts"
        let salt = if is_special { String::new() } else { format!("{rid}{ts}") };
        let mut secret = rand.to_string();
        for _ in 0..enc_time {
            secret = md5_hex(&format!("{secret}{key}"));
        }
        assert_eq!(
            secret,
            case["expect"]["secret_after_iterations"].as_str().expect("secret"),
            "{name}：md5 迭代结果与 golden 不符"
        );
        assert_eq!(
            md5_hex(&format!("{secret}{key}{salt}")),
            case["expect"]["auth"].as_str().expect("auth"),
            "{name}：auth 与独立重算不符（golden 不得由实现自证）"
        );
    }
}

#[test]
fn sign_golden_body_key_order_is_pinned() {
    // Dart 用 Uri(queryParameters: {...}) 的**字面量顺序**（douyu_utils.dart:143-156），
    // 键序变了服务端会拒签。
    let doc = golden_sign();
    let order = doc["_meta"]["key_order_pinned"].as_array().expect("key_order_pinned");
    let actual: Vec<&str> = order.iter().map(|s| s.as_str().expect("字符串")).collect();
    let expected = [
        "enc_data", "tt", "did", "auth", "cdn", "ver", "rate", "hevc", "fa", "ive",
    ];
    assert_eq!(actual, expected, "签名请求体的键序被改动");

    for case in doc["cases"].as_array().expect("cases") {
        let body = case["expect"]["request_body"].as_str().expect("request_body");
        let mut pos = 0usize;
        for key in expected {
            let pat = format!("{key}=");
            let at = body[pos..]
                .find(&pat)
                .unwrap_or_else(|| panic!("请求体缺键 {key}"));
            pos += at + pat.len();
        }
    }
}

#[test]
fn sign_golden_covers_easy_to_miss_branches() {
    // 易漏分支：is_special==1 -> salt 为空；enc_time>1 -> 多次 md5；rate=0。
    let doc = golden_sign();
    let names: Vec<&str> = doc["cases"]
        .as_array()
        .expect("cases")
        .iter()
        .filter_map(|c| c["name"].as_str())
        .collect();
    assert!(
        names.iter().any(|n| n.contains("is-special")),
        "缺 is_special=1（空 salt）向量"
    );
    assert!(
        names.iter().any(|n| n.contains("enc-time-3")),
        "缺 enc_time=3（多次迭代）向量"
    );
    assert!(
        names.iter().any(|n| n.contains("rate-0")),
        "缺 rate=0（原画）向量"
    );
}

// =====================================================================
// 二、HTTP quirks：Q1 推荐流 vs 类目流的 pgcnt 口径相反
// =====================================================================
#[test]
fn recommend_uses_nonempty_rule_while_category_uses_pgcnt() {
    // Q1（douyu_site.dart:82 vs :214）：**不要把两条接口统一**。
    let rec = sample(PLATFORM, "www_douyu_com_japi_weblist_apinc_allpage");
    assert_eq!(
        rec["response"]["data"]["pgcnt"], 0,
        "样本须复现推荐流 pgcnt 恒 0"
    );
    assert_eq!(
        rec["expected"]["has_more"], true,
        "推荐流 pgcnt=0 时非空页仍须判「还有更多」"
    );

    let cat = sample(PLATFORM, "www_douyu_com_gapi_rkc_directory_mixList");
    assert_eq!(
        cat["response"]["data"]["pgcnt"], 3,
        "类目流的 pgcnt 是有效的"
    );
    assert_eq!(cat["expected"]["has_more"], true);
}

#[test]
fn ad_items_are_filtered_without_affecting_has_more() {
    let variants = sample(PLATFORM, "www_douyu_com_gapi_rkc_directory_mixList")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let ad = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("广告位")))
        .expect("缺广告位变体");
    assert_eq!(
        ad["expected"]["items"].as_array().expect("items").len(),
        1,
        "type!=1 的广告位须被过滤"
    );
    assert_eq!(ad["expected"]["has_more"], true, "过滤不应影响 hasMore");
}

#[test]
fn recommend_empty_and_missing_rl_are_handled() {
    let key = "www_douyu_com_japi_weblist_apinc_allpage";
    let variants = sample(PLATFORM, key)["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let empty = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("空页")))
        .expect("缺空页变体");
    assert_eq!(empty["expected"]["has_more"], false, "空页是唯一的停止条件");

    let missing = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("缺 rl")))
        .expect("缺 rl 缺失变体");
    assert!(missing["response"]["data"]
        .as_object()
        .expect("data 是对象")
        .get("rl")
        .is_none());
    assert_eq!(missing["expected"]["has_more"], false);
}

// =====================================================================
// 三、HTTP quirks：Q2 格式化热度 / Q3 hot 解析失败 -999
// =====================================================================
#[test]
fn betard_hot_wan_falls_back_to_zero() {
    // Q2（:224）：'12.3万' 不是合法整数 -> int.tryParse 失败 -> online=0
    let s = sample(PLATFORM, "www_douyu_com_betard");
    assert_eq!(
        s["response"]["room"]["room_biz_all"]["hot"], "12.3万",
        "样本须复现格式化热度"
    );
    assert_eq!(s["expected"]["online"], 0, "'12.3万' tryParse 失败 -> 0");
    assert_eq!(
        s["expected"]["danmaku_data"], "252140",
        "斗鱼弹幕参数就是房间号（Dart:232）"
    );
}

#[test]
fn betard_replay_and_offline_variants_are_applied() {
    // 变体必须是**改好的真实响应**，不能只是文字描述。
    let variants = sample(PLATFORM, "www_douyu_com_betard")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    assert!(variants.len() >= 5, "betard 变体过少");

    let offline = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("未开播")))
        .expect("缺未开播变体");
    assert_eq!(offline["response"]["room"]["show_status"], 0);
    assert_eq!(offline["expected"]["status"], false);

    let replay = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("回放")))
        .expect("缺回放变体");
    assert_eq!(replay["response"]["room"]["videoLoop"], 1);
    assert_eq!(replay["expected"]["status"], false);
    assert_eq!(replay["expected"]["is_record"], true);
}

#[test]
fn search_hot_parse_failure_returns_minus_999() {
    // Q3（:342-352）：parseHotNum 失败返回 -999，不是 0。
    let s = sample(PLATFORM, "www_douyu_com_japi_search_api_searchShow");
    assert_eq!(s["expected"]["items"][0]["online"], 123000, "12.3万 -> 123000");

    let bad = s["variants"]
        .as_array()
        .expect("variants")
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("-999")))
        .expect("缺 hot 解析失败变体");
    assert_eq!(bad["expected"]["items"][0]["online"], -999);
}

#[test]
fn search_anchor_live_status_requires_both_conditions() {
    // liveStatus = isLive==1 && roomType==0（:322-328）
    let items = sample(PLATFORM, "www_douyu_com_japi_search_api_searchUser")["expected"]["items"]
        .as_array()
        .expect("items")
        .clone();
    assert_eq!(items[0]["live_status"], true, "isLive=1 且 roomType=0");
    assert_eq!(
        items[1]["live_status"], false,
        "isLive=1 但 roomType=1 -> false（两条件缺一不可）"
    );
}

// =====================================================================
// 四、错误流覆盖度
// =====================================================================
#[test]
fn error_flow_variants_exist_for_key_endpoints() {
    for key in [
        "www_douyu_com_japi_search_api_searchShow",
        "www_douyu_com_japi_search_api_searchUser",
        "passport_douyu_com_japi_scan_auth",
    ] {
        let doc = sample(PLATFORM, key);
        let variants = doc["variants"].as_array().expect("variants");
        assert!(
            variants.iter().any(|v| v["expected"]["error"].as_str().is_some()),
            "{key} 缺错误流变体"
        );
    }
}

#[test]
fn qr_poll_covers_four_status_codes() {
    // -2 unscanned / 1 scanned / -1 expired / 0 已确认（:445-471）
    let variants = sample(PLATFORM, "passport_douyu_com_japi_scan_auth")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let statuses: Vec<&str> = variants
        .iter()
        .filter_map(|v| v["expected"]["status"].as_str())
        .collect();
    for want in ["unscanned", "scanned", "expired"] {
        assert!(statuses.contains(&want), "缺扫码状态 {want}");
    }
    // error=0 但缺 data.url -> StateError（Dart:458）
    assert!(
        variants
            .iter()
            .any(|v| v["name"].as_str().is_some_and(|n| n.contains("缺失"))),
        "缺 error=0 但 data.url 缺失的变体"
    );
}

#[test]
fn get_encryption_sample_uses_real_capture_fields() {
    // 该样本的 enc_data/key/rand_str 来自真实抓包
    // （simple_live_core/test/douyu_enc.json），仅裁剪 sign() 不读的 cpp 字段。
    let s = sample(PLATFORM, "www_douyu_com_wgapi_livenc_liveweb_websec_getEncryption");
    let data = &s["response"]["data"];
    for field in ["key", "rand_str", "enc_time", "is_special", "enc_data"] {
        assert!(data.get(field).is_some(), "缺字段 {field}");
    }
    assert!(
        data["enc_data"].as_str().expect("enc_data").starts_with("eyJ"),
        "enc_data 应为真实抓包的 base64"
    );
}