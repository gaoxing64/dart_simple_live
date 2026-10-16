//! 账号三接口 AC（AC-18 / AC-19 / AC-20 / AC-24 / AC-40）：MockTransport 离线驱动。

mod common;

use common::harness;
use slive_core::models::QrStatus;

const MARKER_COOKIE: &str = "SESSDATA=secret-marker-12345;bili_jct=marker-67890";

#[tokio::test]
async fn ac18_qr_code_parses_key_and_url() {
    let h = harness();
    h.mock.stub(
        "qrcode/generate",
        r#"{"code":0,"data":{"qrcode_key":"key-1","url":"https://passport.bilibili.com/h5-app/passport/login/qr?qrcode_key=key-1"}}"#,
    );

    let qr = h.site.get_qr_code().await.expect("code=0 应成功");

    assert_eq!(qr.key, "key-1");
    assert_eq!(
        qr.url,
        "https://passport.bilibili.com/h5-app/passport/login/qr?qrcode_key=key-1"
    );
    assert_eq!(h.mock.request_count("qrcode/generate"), 1, "只发一次请求");
}

#[tokio::test]
async fn ac18_qr_code_api_error_throws() {
    let h = harness();
    h.mock.stub(
        "qrcode/generate",
        r#"{"code":-400,"message":"请求错误"}"#,
    );

    let err = h
        .site
        .get_qr_code()
        .await
        .expect_err("code!=0 必须抛错，不得返回空码");
    assert!(
        err.to_string().contains("请求错误"),
        "错误应携带服务端 message，实际 {err}"
    );
}

#[tokio::test]
async fn ac19_poll_success_builds_credential_from_set_cookie() {
    let h = harness();
    h.mock.stub_with_cookie(
        "qrcode/poll",
        r#"{"code":0,"data":{"code":0}}"#,
        vec![
            "SESSDATA=abc123; Path=/; HttpOnly".to_string(),
            "bili_jct=xyz789; Path=/".to_string(),
            "DedeUserID=42; Path=/".to_string(),
        ],
    );

    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");

    assert_eq!(qr.status, QrStatus::Scanned);
    assert_eq!(
        qr.credential,
        r#"{"cookie":"SESSDATA=abc123;bili_jct=xyz789;DedeUserID=42"}"#,
        "各条取 `;` 前段再以 `;` 连接后包成 JSON"
    );
}

#[tokio::test]
async fn ac19_poll_without_set_cookie_stays_unscanned() {
    let h = harness();
    h.mock.stub("qrcode/poll", r#"{"code":0,"data":{"code":0}}"#);

    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");

    assert_eq!(qr.status, QrStatus::Unscanned, "set-cookie 为空不产 credential");
    assert!(qr.credential.is_empty());
}

#[tokio::test]
async fn ac19_poll_maps_expired_and_scanned_codes() {
    // 86038 → expired
    let h = harness();
    h.mock.stub("qrcode/poll", r#"{"code":0,"data":{"code":86038}}"#);
    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");
    assert_eq!(qr.status, QrStatus::Expired);

    // 86090 → scanned（已扫未确认，无 credential）
    let h = harness();
    h.mock.stub("qrcode/poll", r#"{"code":0,"data":{"code":86090}}"#);
    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");
    assert_eq!(qr.status, QrStatus::Scanned);
    assert!(qr.credential.is_empty());

    // 其他 code → 保持 unscanned
    let h = harness();
    h.mock.stub("qrcode/poll", r#"{"code":0,"data":{"code":-101}}"#);
    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");
    assert_eq!(qr.status, QrStatus::Unscanned);
}

#[tokio::test]
async fn ac20_account_info_fills_and_backfills_user_id() {
    let h = harness();
    h.mock.stub(
        "member/web/account",
        r#"{"code":0,"data":{"mid":12345,"uname":"测试者","face":"https://i0.hdslb.com/face.png","userid":"12345"}}"#,
    );

    let info = h
        .site
        .get_account_info(r#"{"cookie":"SESSDATA=abc"}"#.into())
        .await
        .expect("不抛");

    assert!(info.is_valid, "code=0 应有效");
    assert_eq!(info.name.as_deref(), Some("测试者"));
    assert_eq!(info.avatar.as_deref(), Some("https://i0.hdslb.com/face.png"));
    assert_eq!(info.uid.as_deref(), Some("12345"));
    assert_eq!(h.site.user_id(), 12345, "userId 回填副作用（弹幕 uid 配对）");
}

#[tokio::test]
async fn ac20_account_api_error_returns_not_valid_without_throw() {
    let h = harness();
    h.mock.stub("member/web/account", r#"{"code":-101,"message":"账号未登录"}"#);

    let info = h.site.get_account_info(r#"{"cookie":"x"}"#.into()).await.expect("不抛");
    assert!(!info.is_valid, "code!=0 → is_valid=false");
    assert!(info.name.is_none());
}

#[tokio::test]
async fn ac24_account_failures_return_not_valid_without_throw() {
    // 网络失败
    let h = harness();
    h.mock.stub_network_error("member/web/account", "连接被重置");
    let info = h.site.get_account_info(r#"{"cookie":"x"}"#.into()).await.expect("不抛");
    assert!(!info.is_valid);

    // credential 不是 JSON（Dart jsonDecode 抛 → catch → 空 AccountInfo）
    let h = harness();
    let info = h.site.get_account_info("not json".into()).await.expect("不抛");
    assert!(!info.is_valid);

    // mid 缺失（Dart `info.mid!` 抛 → catch → 空 AccountInfo，AC-20）
    let h = harness();
    h.mock.stub("member/web/account", r#"{"code":0,"data":{"uname":"u"}}"#);
    let info = h.site.get_account_info(r#"{"cookie":"x"}"#.into()).await.expect("不抛");
    assert!(!info.is_valid);
}

#[tokio::test]
async fn ac40_logs_never_contain_cookie_plain_text() {
    let logger = common::capture_logger();
    let h = harness();
    h.mock.stub_with_cookie(
        "qrcode/poll",
        r#"{"code":0,"data":{"code":0}}"#,
        vec![format!("{MARKER_COOKIE}; Path=/")],
    );

    let qr = h.site.get_qr_poll_result("k".into()).await.expect("应成功");
    assert_eq!(qr.status, QrStatus::Scanned, "前置：credential 已产出");

    for message in logger.messages() {
        assert!(
            !message.contains(MARKER_COOKIE),
            "日志不得出现 credential/cookie 明文，违规日志：{message}"
        );
    }
}
