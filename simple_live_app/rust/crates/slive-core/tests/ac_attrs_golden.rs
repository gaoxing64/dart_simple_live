//! 凭证注入 / 日志安全 / ws golden（AC-17、AC-40、AC-11）。

mod common;

use common::{capture_logger, harness, read_text};
use serde_json::Value;
use slive_core::error::SliveError;
use slive_core::platforms::bilibili::danmaku::args::{BiliBiliDanmakuArgs, DEFAULT_SERVER_HOST};

#[tokio::test]
async fn ac17_set_site_attrs_three_cases() {
    let h = harness();
    h.stub_buvid();
    h.stub_sample("room_v1_Area_getList");

    // ① {"cookie":X} -> 站点 cookie == X（非整串 JSON）
    h.site
        .set_site_attrs(r#"{"cookie":"SESSDATA=abc"}"#)
        .expect("合法注入应成功");
    assert_eq!(h.site.cookie(), "SESSDATA=abc", "应写入 cookie 值本身");
    let _ = h.site.get_categories().await.expect("分类应成功");
    let cookie_header = h
        .mock
        .requests()
        .into_iter()
        .find(|r| r.url.contains("room/v1/Area/getList"))
        .and_then(|r| r.headers.into_iter().find(|(k, _)| k == "cookie"))
        .map(|(_, v)| v)
        .unwrap();
    assert!(
        !cookie_header.contains("{\"cookie\""),
        "请求头 Cookie 不得含整串 JSON 字面量，实际 {cookie_header}"
    );

    // ② 非法 JSON -> SliveError::InvalidInput
    let err = h.site.set_site_attrs("{不是 json").expect_err("非法 JSON 应报错");
    assert!(
        matches!(err, SliveError::InvalidInput(_)),
        "应为 InvalidInput，实际 {err:?}"
    );

    // ③ JSON 合法但缺 cookie 键 -> 保留旧值
    h.site
        .set_site_attrs(r#"{"other":"x"}"#)
        .expect("缺 cookie 键不应抛");
    assert_eq!(h.site.cookie(), "SESSDATA=abc", "缺 cookie 键应保留旧值");
}

#[tokio::test]
async fn ac40_credential_never_logged_in_plaintext() {
    let logger = capture_logger();
    let h = harness();

    h.site
        .set_site_attrs(r#"{"cookie":"SESSDATA=supersecret"}"#)
        .expect("注入应成功");

    let joined = logger.messages().join("\n");
    assert!(
        !joined.contains("SESSDATA"),
        "日志不得出现 cookie 明文，实际日志：{joined}"
    );
    assert!(
        !joined.contains("supersecret"),
        "日志不得出现凭证明文，实际日志：{joined}"
    );
}

#[test]
fn ac11_join_packet_byte_golden() {
    let golden: Value =
        serde_json::from_str(&read_text("golden/golden-join-packet.json")).expect("解析 golden");
    let args = BiliBiliDanmakuArgs::new(
        6,
        0,
        "test-token-abc".to_string(),
        DEFAULT_SERVER_HOST.to_string(),
        "buvid3-FIXED".to_string(),
        String::new(),
    );

    assert_eq!(
        args.join_payload(),
        golden["join_packet"]["body_utf8"].as_str().unwrap(),
        "join body JSON 应逐字符一致"
    );

    let expected: Vec<u8> = golden["join_packet"]["bytes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_u64().unwrap() as u8)
        .collect();
    let packet = slive_core::ws::frame::encode_packet(args.join_payload().as_bytes(), 7);
    assert_eq!(packet, expected, "join 包应逐字节等于 golden");

    let hb_expected: Vec<u8> = golden["heartbeat_packet"]["bytes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_u64().unwrap() as u8)
        .collect();
    assert_eq!(
        slive_core::ws::frame::heartbeat_packet(),
        hb_expected,
        "心跳包应逐字节等于 golden"
    );
}
