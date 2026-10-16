//! F-16 表情包解析 AC（AC-16）：Dart 31 条契约的行为镜像（从单测迁移为集成用例）。

use serde_json::{json, Value};
use slive_core::models::LiveMessageEmoticon;
use slive_core::platforms::bilibili::emoticon::parse_bilibili_emoticons;

fn parse_from_info(info: Value, message: &str) -> Option<Vec<LiveMessageEmoticon>> {
    let info = info.as_array().expect("info 应为数组").clone();
    parse_bilibili_emoticons(&info, message)
}

#[test]
fn ac16_single_emoticon_is_large_and_standalone_named() {
    // 整条弹幕就是 [doge]：info[0][13] 带图 → large=true，name=整条 message
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "",
        {"url": "//i0.hdslb.com/doge.png", "width": 200, "height": 200},
        "", "{}"],
        "[doge]"]);
    let got = parse_from_info(info, "[doge]").expect("应解析出表情");
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].url, "https://i0.hdslb.com/doge.png", "// → https:");
    assert!(got[0].large);
    assert_eq!(got[0].name.as_deref(), Some("[doge]"));
}

#[test]
fn ac16_extra_emots_parse_mixed_content() {
    // 混排：[doge] 哈哈 → extra.emots 命中 [doge]（占位符 contains）
    let extra =
        r#"{"emots":{"[doge]":{"url":"https://i0.hdslb.com/doge.png","width":90,"height":90}}}"#;
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "", "{}",
        "", {"extra": extra}],
        "[doge] 哈哈"]);
    let got = parse_from_info(info, "[doge] 哈哈").expect("应解析出表情");
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].name.as_deref(), Some("[doge]"));
    assert!(!got[0].large, "行内小表情不是大表情");
}

#[test]
fn ac16_bare_name_key_only_replaces_standalone_message() {
    // 裸名「冲鸭」单独发送 → 命中且 large；夹带正文则不可替换
    let extra = r#"{"emots":{"冲鸭":{"url":"https://i0.hdslb.com/cha.png"}}}"#;
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "", "{}",
        "", {"extra": extra}], "冲鸭"]);
    let got = parse_from_info(info.clone(), "冲鸭").expect("单独发送应命中");
    assert_eq!(got[0].name.as_deref(), Some("冲鸭"));
    assert!(got[0].large, "裸名整串 = 单独发送的大表情");
    // 「冲鸭啦」夹带正文 → 不可替换 → None
    assert!(parse_from_info(info, "冲鸭啦").is_none());
}

#[test]
fn ac16_same_image_from_both_entries_dedupes_by_url() {
    // info[0][13] 与 extra.emots 同图 → 只保留 1 条
    let extra =
        r#"{"emots":{"[doge]":{"url":"https://i0.hdslb.com/doge.png","width":90,"height":90}}}"#;
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "",
        {"url": "https://i0.hdslb.com/doge.png", "width": 200, "height": 200},
        "", {"extra": extra}],
        "[doge]"]);
    let got = parse_from_info(info, "[doge]").expect("应解析出表情");
    assert_eq!(got.len(), 1, "同图两入口应去重为 1 条");
    assert!(got[0].large, "任一入口判定为大表情都应保留 large");
}

#[test]
fn ac16_cap_eight_truncates_at_entry() {
    // 9 个占位符命中 → 只保留前 8 个（入口截断，消息里出现的顺序）
    let mut emots = serde_json::Map::new();
    for i in 0..9 {
        emots.insert(
            format!("[e{i}]"),
            json!({"url": format!("https://i0.hdslb.com/e{i}.png")}),
        );
    }
    let message: String = (0..9).map(|i| format!("[e{i}]")).collect();
    let extra = serde_json::to_string(&json!({"emots": emots})).unwrap();
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "", "{}",
        "", {"extra": extra}], message]);
    let got = parse_from_info(info, &message).expect("应解析出表情");
    assert_eq!(got.len(), 8, "上限 8 入口截断");
    assert_eq!(got[0].name.as_deref(), Some("[e0]"));
    assert_eq!(got[7].name.as_deref(), Some("[e7]"));
}

#[test]
fn ac16_http_url_upgrades_and_relative_dropped() {
    let extra =
        r#"{"emots":{"[a]":{"url":"http://i0.hdslb.com/a.png"},"[b]":{"url":"i0.hdslb.com/b.png"}}}"#;
    let info = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "", "{}",
        "", {"extra": extra}], "[a][b]"]);
    let got = parse_from_info(info, "[a][b]").expect("应解析出 [a]");
    assert_eq!(got.len(), 1, "相对路径应被丢弃");
    assert_eq!(got[0].url, "https://i0.hdslb.com/a.png");
}

#[test]
fn ac16_abnormal_payloads_return_none() {
    // meta 过短 / 无 url / message 无命中 / extra 非 JSON
    assert!(parse_from_info(json!([["x"]]), "hi").is_none());
    let no_url = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "",
        {"width": 20}, "", "{}"], "[doge]"]);
    assert!(parse_from_info(no_url, "[doge]").is_none());
    let bad_extra = json!([[0, 0, 0, 0, "", "", "", "", "", "", "", "", "", "{}",
        "", {"extra": "not json"}], "[doge]"]);
    assert!(parse_from_info(bad_extra, "[doge]").is_none());
}
