//! 抖音 golden 与 HTTP quirks 契约用例（IP-6 夹具基线 · QA 产出）。
//!
//! 拆成独立文件是为守住**单文件 ≤ 300 行**门禁（`13-spec.md §9`）；
//! 夹具与 protobuf 帧契约在 `ac_douyin_fixtures.rs`。同样**不 import 平台函数**。

mod fxcommon;

use fxcommon::{read_text, sample};
use serde_json::Value;

const PLATFORM: &str = "douyin";

fn signature_golden() -> Value {
    serde_json::from_str(&read_text(PLATFORM, "golden/golden-signature-params.json"))
        .unwrap_or_else(|e| panic!("解析 golden-signature-params.json 失败: {e}"))
}

// =====================================================================
// 一、签名 golden：参数键序 + 随机字段登记
// =====================================================================
#[test]
fn signature_golden_pins_param_order() {
    // douyin_danmaku.dart:212-226 的字面量顺序，sigParam 用**逗号**连接。
    let doc = signature_golden();
    assert_eq!(doc["_meta"]["platform"], PLATFORM);
    let order = doc["_meta"]["key_order_pinned"].as_array().expect("key_order_pinned");
    let actual: Vec<&str> = order.iter().map(|s| s.as_str().expect("字符串")).collect();
    assert_eq!(
        actual,
        [
            "live_id",
            "aid",
            "version_code",
            "webcast_sdk_version",
            "room_id",
            "sub_room_id",
            "sub_channel_id",
            "did_rule",
            "user_unique_id",
            "device_platform",
            "device_type",
            "ac",
            "identity"
        ],
        "sigParam 的键序被改动"
    );
}

#[test]
fn signature_golden_marks_xbogus_as_nondeterministic() {
    // xbogus.dart:92用 Random.secure() 生成 random1/random2 -> 输出不可 golden。
    let doc = signature_golden();
    let nd = doc["_meta"]["nondeterministic_fields"].as_array().expect("字段");
    assert_eq!(nd[0], "signature(X-Bogus)", "必须登记 X-Bogus 不可 golden");
    assert!(doc["expect"]["sig_param"].as_str().is_some());
    assert!(doc["expect"]["md5_sig_param"].as_str().is_some());
    let shape = &doc["expect"]["signature_shape"];
    assert!(shape["min_len"].as_u64().expect("min_len") > 0);
}

#[test]
fn sig_param_is_comma_joined_in_pinned_order() {
    // Dart:227 `entries.map('${k}=${v}').join(',')` —— 逗号，不是 &。
    let doc = signature_golden();
    let params = &doc["input"]["params"];
    let order = doc["_meta"]["key_order_pinned"].as_array().expect("键序");
    let mut expect = String::new();
    for (i, k) in order.iter().enumerate() {
        let k = k.as_str().expect("字符串");
        if i > 0 {
            expect.push(',');
        }
        expect.push_str(&format!("{k}={}", params[k].as_str().expect("值")));
    }
    assert_eq!(doc["expect"]["sig_param"], expect, "sigParam 拼接方式不符");
}

#[test]
fn request_url_golden_pins_fixed_params() {
    // douyin_utils.dart:29-36 在调用方参数后追加的固定项。
    let doc: Value = serde_json::from_str(&read_text(PLATFORM, "golden/golden-request-url.json"))
        .expect("解析");
    let fixed = &doc["fixed_params_appended"];
    for (k, v) in [
        ("aid", "6383"),
        ("compress", "gzip"),
        ("device_platform", "web"),
        ("browser_language", "zh-CN"),
        ("browser_platform", "Win32"),
        ("browser_name", "Edge"),
        ("browser_version", "125.0.0.0"),
    ] {
        assert_eq!(fixed[k], v, "固定参数 {k} 被改动");
    }
    assert!(
        doc["_meta"]["nondeterministic_fields"].is_array(),
        "msToken / a_bogus 必须登记为不可 golden"
    );
    assert!(doc["msToken_note"].as_str().is_some_and(|v| v.contains("184")));
}

// =====================================================================
// 二、HTTP quirks：Q10 display_value 格式化 / Q12 清晰度错位
// =====================================================================
#[test]
fn partition_sample_has_double_nesting() {
    // douyin_site.dart:194-196：data.data 才是 List（外层 data 是 Map）。
    let resp = sample(PLATFORM, "live_douyin_com_webcast_web_partition_detail_room_v2")["response"]
        .clone();
    assert!(resp["data"].is_object(), "外层 data 应为 Map");
    assert!(resp["data"]["data"].is_array(), "内层 data.data 应为 List");
    let items = resp["data"]["data"].as_array().expect("数组");
    assert!(items[0]["room"].is_object(), "分区接口的房间挂在 item['room']");
    assert!(items[0]["web_rid"].is_string(), "web_rid 与 room 是兄弟字段");
}

#[test]
fn feed_and_partition_use_different_room_mount_points() {
    // feed -> item['data']（:469）；partition -> item['room']（:211）。
    let feed = sample(PLATFORM, "live_douyin_com_webcast_feed")["response"]["data"]
        .as_array()
        .expect("feed.data 是数组")
        .clone();
    assert!(feed[0]["data"].is_object(), "feed 的房间挂在 item['data']");
    assert!(
        feed[0].get("room").is_none(),
        "feed 不应使用 item['room']（两接口结构不同）"
    );
}

#[test]
fn display_value_wan_falls_back_to_zero() {
    // Q10（:232）：`display_value` 是'1.2万' 这类格式化串 -> tryParse 失败 -> 0。
    let exp = sample(PLATFORM, "live_douyin_com_webcast_web_partition_detail_room_v2")["expected"]
        .clone();
    assert_eq!(exp["items"][0]["online"], 0, "格式化数字解析失败回落 0");
    assert_eq!(exp["items"][1]["online"], 3000, "纯数字应正常解析");
}

#[test]
fn malformed_items_do_not_affect_has_more_basis() {
    // hasMore 用 `rawCount >= count`（服务端原始条数），不是过滤后的 items.len()
    // （Dart:125 + :136-138 注释）。
    let variants = sample(PLATFORM, "live_douyin_com_webcast_web_partition_detail_room_v2")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("畸形")))
        .expect("缺畸形条目变体");
    assert_eq!(v["expected"]["items"].as_array().expect("items").len(), 1);
    let items = v["response"]["data"]["data"].as_array().expect("数组");
    assert_eq!(items.len(), 3, "服务端原始条数是 3（含2 条畸形）");
    assert!(items[0].get("room").is_none(), "第 1 条缺 room -> 跳过");
    assert!(items[1]["web_rid"].is_null(), "第 2 条缺 web_rid -> 跳过");
}

#[test]
fn data_shape_variants_cover_malformed_responses() {
    // Dart:191-193 注释：曾直接取 result['data']['data'] 抛 TypeError 带崩整页。
    let variants = sample(PLATFORM, "live_douyin_com_webcast_web_partition_detail_room_v2")["variants"]
        .as_array()
        .expect("variants")
        .clone();
    let errs: Vec<&Value> = variants
        .iter()
        .filter(|v| {
            v["response"]["data"].is_array()
                || v["response"]["data"].is_null()
                || v["response"].as_object().is_some_and(|o| o.is_empty())
        })
        .collect();
    assert!(errs.len() >= 3, "畸形 data 形态覆盖不足（List / null / 缺失）");
}

#[test]
fn quality_variant_pins_the_misalignment_behavior() {
    // Q12：分支② 按 `flvList[len - level]` 取值，档位与地址**整体错位一档**。
    // 已用独立复算确认：level=0 越界被丢弃，标清拿到原画地址。
    let key = "live_douyin_com_stream_url_quality";
    let variants = sample(PLATFORM, key)["variants"].as_array().expect("variants").clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("分支②")))
        .expect("缺分支②（stream_data 为空 -> 地址表索引）");
    assert!(v["expected"]["dropped"].is_array(), "必须显式登记被丢弃的档位");
    assert_eq!(v["expected"]["dropped"][0]["quality"], "原画");
    assert!(
        v["expected"]["note"].as_str().is_some_and(|n| n.contains("错位")),
        "必须写明这是既有错位行为、不得顺手修正"
    );
    assert!(
        v["expected"]["note"].as_str().is_some_and(|n| n.contains("AC-30")),
        "须关联回归约束"
    );
}

#[test]
fn empty_detail_data_returns_empty_qualities_without_throw() {
    // Dart:957-959：detail.data 为空/缺字段时安全返回空列表（连麦降级场景）。
    let key = "live_douyin_com_stream_url_quality";
    let variants = sample(PLATFORM, key)["variants"].as_array().expect("variants").clone();
    let v = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("detail.data 为空")))
        .expect("缺 detail.data 为空变体");
    assert_eq!(v["expected"]["qualities"].as_array().expect("qualities").len(), 0);
    assert!(v["response"]["__detail_data"].as_object().expect("对象").is_empty());
}

#[test]
fn enter_variants_cover_offline_and_degraded() {
    let key = "live_douyin_com_webcast_room_web_enter";
    let variants = sample(PLATFORM, key)["variants"].as_array().expect("variants").clone();
    let names: Vec<&str> = variants.iter().filter_map(|v| v["name"].as_str()).collect();
    assert!(names.iter().any(|n| n.contains("未开播")), "缺未开播变体");
    assert!(names.iter().any(|n| n.contains("降级")), "缺降级骨架变体（连麦房间）");
    assert!(names.iter().any(|n| n.contains("data 为空")), "缺 data 为空的错误流");

    // status==4 时须用 owner.web_rid 再查一次（Dart:572-578）
    let s4 = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("status=4")))
        .expect("缺 status=4 变体");
    assert_eq!(s4["response"]["data"][0]["status"], 4, "该变体须真的改了 status");
    assert_eq!(s4["expected"]["request_count"], 2, "status=4 须发第二次请求");
}

// =====================================================================
// 三、搜索：双层编码 + 风控非 JSON
// =====================================================================
#[test]
fn search_sample_uses_double_encoded_rawdata() {
    // douyin_site.dart:1158：lives.rawdata 是**字符串化的 JSON**。
    let item = &sample(PLATFORM, "www_douyin_com_aweme_v1_web_live_search")["response"]["data"][0];
    let raw = item["lives"]["rawdata"].as_str().expect("rawdata 应为字符串");
    let inner: Value = serde_json::from_str(raw).expect("rawdata 应能被二次解析");
    assert!(inner["owner"]["web_rid"].is_string());
    assert!(inner["title"].is_string());
    assert!(inner["stats"]["total_user"].is_string());
}

#[test]
fn search_variants_cover_text_fallback_responses() {
    // 风控时响应体是纯文本 `blocked`（非 JSON），mock 必须能返回非 JSON。
    let key = "www_douyin_com_aweme_v1_web_live_search";
    let variants = sample(PLATFORM, key)["variants"].as_array().expect("variants").clone();
    let blocked = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("blocked")))
        .expect("缺 blocked 风控变体");
    assert_eq!(blocked["__mock_text"], "blocked", "风控响应须以纯文本形式提供");
    let empty = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("空响应")))
        .expect("缺空响应变体");
    assert_eq!(empty["__mock_text"], "");
}

// =====================================================================
// 四、账号与抓包优先级
// =====================================================================
#[test]
fn account_sample_uses_id_str_not_id() {
    // model/douyin_user_info.dart:22 取的是 `id_str`。
    let data = &sample(PLATFORM, "live_douyin_com_webcast_user_me")["response"]["data"];
    assert!(data["id_str"].is_string(), "字段名是 id_str");
    assert!(data.get("id").is_none(), "不应出现 id 变体");
    assert!(data["avatar_thumb"]["url_list"].is_array(), "头像取 url_list[0]");
}

#[test]
fn account_variants_cover_invalid_without_throw() {
    let key = "live_douyin_com_webcast_user_me";
    let variants = sample(PLATFORM, key)["variants"].as_array().expect("variants").clone();
    let bad = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("data 不是 Map")))
        .expect("缺 data 非Map 变体");
    assert_eq!(bad["expected"]["is_valid"], false, "无效凭证不得抛");
    let no_cookie = variants
        .iter()
        .find(|v| v["name"].as_str().is_some_and(|n| n.contains("cookie 为空")))
        .expect("缺 cookie 为空变体");
    assert_eq!(no_cookie["expected"]["request_count"], 0, "cookie 空则不发请求");
}

#[test]
fn realtime_plan_flags_douyin_as_hardest_to_capture() {
    let meta = &fxcommon::http_samples(PLATFORM)["_meta"];
    assert!(
        meta["difficulty_note"].as_str().is_some_and(|v| v.contains("最难抓包")),
        "须标注抖音抓包难度最高"
    );
    assert!(
        meta["realtime_validation_plan"].as_str().is_some_and(|v| v.contains("A-Bogus")),
        "抓包计划须写明签名要求"
    );
}