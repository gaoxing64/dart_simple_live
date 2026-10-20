//! 抖音搜索 / 账号 / 凭证注入 AC。
//!
//! 覆盖：搜索成功流（含 `rawdata` 双层 JSON）、搜索被限流、账号校验成功/失效、
//! `setSiteAttrs` 的 cookie 与 hlsFirst、**错误消息不含 cookie 明文**（AC-40）。

mod douyin_common;

use douyin_common::harness;
use slive_core::error::SliveError;

/// 一条搜索结果（`lives.rawdata` 是又一层 JSON 串）。
fn search_item(web_rid: &str, title: &str, total_user: &str) -> String {
    let raw = serde_json::json!({
        "owner": {"web_rid": web_rid, "nickname": "主播X"},
        "title": title,
        "cover": {"url_list": ["https://c1", "https://c2"]},
        "stats": {"total_user": total_user},
    });
    serde_json::json!({ "data": [{ "lives": { "rawdata": raw.to_string() } }] }).to_string()
}

#[tokio::test]
async fn ac_douyin_search_rooms_parses_nested_rawdata() {
    let h = harness();
    h.stub_json_inline(
        "aweme/v1/web/live/search/",
        &search_item("416144012050", "搜索到的直播间", "8888"),
    );

    let result = h
        .site
        .search_rooms("主播".into(), 1)
        .await
        .expect("搜索应成功");

    assert_eq!(result.items.len(), 1);
    let item = &result.items[0];
    assert_eq!(item.room_id, "416144012050");
    assert_eq!(item.title, "搜索到的直播间");
    assert_eq!(item.cover, "https://c1", "取 url_list[0]");
    assert_eq!(item.user_name, "主播X");
    assert_eq!(item.online, 8888);
    assert!(
        !result.has_more,
        "items.len()=1 < 10 -> has_more=false（Dart 口径）"
    );
}

#[tokio::test]
async fn ac_douyin_search_has_more_when_page_is_full() {
    let h = harness();
    let items: Vec<serde_json::Value> = (0..10)
        .map(|i| {
            serde_json::json!({
                "lives": {"rawdata": serde_json::json!({
                    "owner": {"web_rid": format!("{i}"), "nickname": "n"},
                    "title": "t",
                    "stats": {"total_user": "1"}
                }).to_string()}
            })
        })
        .collect();
    h.stub_json_inline(
        "aweme/v1/web/live/search/",
        &serde_json::json!({"data": items}).to_string(),
    );
    h.stub_home_html("home_categories");

    let result = h.site.search_rooms("k".into(), 1).await.expect("应成功");
    assert_eq!(result.items.len(), 10);
    assert!(result.has_more, "满 10 条 -> has_more=true");
}

#[tokio::test]
async fn ac_douyin_search_offset_shifts_with_page() {
    let h = harness();
    h.stub_json_inline("aweme/v1/web/live/search/", r#"{"data":[]}"#);
    h.stub_home_html("home_categories");

    h.site.search_rooms("k".into(), 3).await.expect("应成功");

    let url = h
        .request_urls()
        .into_iter()
        .find(|u| u.contains("aweme/v1/web/live/search/"))
        .expect("应请求过搜索接口");
    assert!(url.contains("offset=20"), "第 3 页 offset=(3-1)*10：{url}");
    assert!(url.contains("count=10"));
}

#[tokio::test]
async fn ac_douyin_search_is_not_signed_with_a_bogus() {
    let h = harness();
    h.stub_json_inline("aweme/v1/web/live/search/", r#"{"data":[]}"#);
    h.stub_home_html("home_categories");

    h.site.search_rooms("k".into(), 1).await.expect("应成功");

    let url = h
        .request_urls()
        .into_iter()
        .find(|u| u.contains("aweme/v1/web/live/search/"))
        .expect("应请求过搜索接口");
    assert!(
        !url.contains("a_bogus"),
        "Dart 的 searchRooms 未过 buildRequestUrl，不加签名：{url}"
    );
}

#[tokio::test]
async fn ac_douyin_search_rate_limited_returns_empty_not_error() {
    let h = harness();
    h.stub_home_html("home_categories");
    // 限流的真实表现：data 缺失
    h.stub_json_inline("aweme/v1/web/live/search/", r#"{"status_code":2154}"#);

    let result = h
        .site
        .search_rooms("k".into(), 1)
        .await
        .expect("限流应返回空页而非报错（Dart 同口径）");
    assert!(result.items.is_empty());
    assert!(!result.has_more);
}

#[tokio::test]
async fn ac_douyin_search_dirty_rawdata_skipped() {
    let h = harness();
    h.stub_json_inline(
        "aweme/v1/web/live/search/",
        r#"{"data":[{"lives":{"rawdata":"不是 JSON"}},{"no_lives":true}]}"#,
    );

    let result = h
        .site
        .search_rooms("k".into(), 1)
        .await
        .expect("脏条目应被跳过");
    assert!(result.items.is_empty());
}

#[tokio::test]
async fn ac_douyin_search_anchors_is_unsupported() {
    let h = harness();
    let err = h
        .site
        .search_anchors("k".into(), 1)
        .await
        .expect_err("抖音不支持搜索主播");
    match err {
        SliveError::Api { message, .. } => {
            assert!(message.contains("暂不支持搜索主播"), "实际 {message}");
        }
        other => panic!("期望 Api，实际 {other:?}"),
    }
    assert_eq!(
        h.request_count("aweme/v1/web/live/search/"),
        0,
        "不支持的能力不得发请求"
    );
}

#[tokio::test]
async fn ac_douyin_qr_methods_are_unsupported() {
    let h = harness();
    h.stub_home_html("home_categories");
    assert!(matches!(
        h.site.get_qr_code().await,
        Err(SliveError::NotFound(_))
    ));
    assert!(matches!(
        h.site.get_qr_poll_result("k".into()).await,
        Err(SliveError::NotFound(_))
    ));
    assert_eq!(h.request_count("live.douyin.com"), 0, "不得发请求");
}

#[tokio::test]
async fn ac_douyin_account_info_valid_cookie() {
    let h = harness();
    h.stub_json_inline(
        "webcast/user/me/",
        r#"{"status_code":0,"data":{"id_str":"1234567890","nickname":"测试用户",
            "short_id":"123","sign":"签名","birthday":"1990-01-01","gender":"1",
            "avatar_thumb":{"url_list":["https://a","https://b"]}}}"#,
    );

    let info = h
        .site
        .get_account_info(r#"{"cookie":"ttwid=valid"}"#.into())
        .await
        .expect("账号校验应成功");

    assert!(info.is_valid);
    assert_eq!(info.name.as_deref(), Some("测试用户"));
    assert_eq!(info.uid.as_deref(), Some("1234567890"));
    assert_eq!(info.avatar.as_deref(), Some("https://a"));
    assert_eq!(info.credential, r#"{"cookie":"ttwid=valid"}"#);
}

#[tokio::test]
async fn ac_douyin_account_info_empty_cookie_is_unverified_without_request() {
    let h = harness();
    let info = h
        .site
        .get_account_info(r#"{"cookie":""}"#.into())
        .await
        .expect("不应报错");
    assert!(!info.is_valid, "没配 cookie -> 未校验");
    assert_eq!(
        info.credential, r#"{"cookie":""}"#,
        "未校验必须回传入参 credential，否则 App 写回时会把已存 cookie 抹掉"
    );
    assert_eq!(
        h.request_count("webcast/user/me/"),
        0,
        "空 cookie 不该发请求（Dart 同口径）"
    );
}

#[tokio::test]
async fn ac_douyin_account_info_expired_cookie_is_unverified_not_error() {
    let h = harness();
    h.stub_http_error("webcast/user/me/", 401);

    let info = h
        .site
        .get_account_info(r#"{"cookie":"ttwid=expired"}"#.into())
        .await
        .expect("cookie 失效应返回未校验对象而不是抛错（对齐 Dart）");
    assert!(!info.is_valid);
}

#[tokio::test]
async fn ac_douyin_account_info_unexpected_shape_is_unverified() {
    let h = harness();
    h.stub_json_inline("webcast/user/me/", r#"{"status_code":0}"#);

    let info = h
        .site
        .get_account_info(r#"{"cookie":"a=1"}"#.into())
        .await
        .expect("应返回未校验");
    assert!(!info.is_valid);
}

#[tokio::test]
async fn ac_douyin_account_info_malformed_credential_is_unverified() {
    let h = harness();
    h.stub_home_html("home_categories");
    let info = h
        .site
        .get_account_info("not json".into())
        .await
        .expect("非法 JSON 按未校验处理，不抛（App 启动会对所有账号行跑校验）");
    assert!(!info.is_valid);
    assert_eq!(info.credential, "not json", "原样回传，避免抹掉用户数据");
}

#[test]
fn ac_douyin_set_site_attrs_cookie_lifecycle() {
    let h = harness();
    let site = &h.site;

    site.set_site_attrs(r#"{"cookie":"odin_tt=abc"}"#)
        .expect("注入");
    assert_eq!(site.header_cookie(), "odin_tt=abc");

    site.set_site_attrs(r#"{"cookie":""}"#).expect("清空");
    assert_eq!(site.header_cookie(), "", "空串 = 移除（Dart 同口径）");
}

#[test]
fn ac_douyin_set_site_attrs_hls_first() {
    let h = harness();
    h.stub_home_html("home_categories");
    assert!(!h.site.hls_first(), "Dart 默认 false");
    h.site
        .set_site_attrs(r#"{"hlsFirst":true}"#)
        .expect("注入");
    assert!(h.site.hls_first());
}

#[test]
fn ac_douyin_set_site_attrs_keeps_old_value_when_key_absent() {
    let h = harness();
    h.stub_home_html("home_categories");
    h.site.set_site_attrs(r#"{"cookie":"keep=1","hlsFirst":true}"#)
        .expect("注入");
    h.site.set_site_attrs("{}").expect("空对象");
    assert_eq!(h.site.header_cookie(), "keep=1", "缺键应保留旧值");
    assert!(h.site.hls_first(), "缺键应保留旧值");
}

#[test]
fn ac_douyin_set_site_attrs_rejects_non_object() {
    let h = harness();
    h.stub_home_html("home_categories");
    for bad in ["not json", "[1,2]", "\"str\""] {
        assert!(
            matches!(
                h.site.set_site_attrs(bad),
                Err(SliveError::InvalidInput(_))
            ),
            "输入 {bad} 应报错"
        );
    }
}

#[test]
fn ac_douyin_set_site_attrs_ttwid_is_prepended_to_injected_cookie() {
    let h = harness();
    h.stub_home_html("home_categories");
    h.site.merge_ttwid("ttwid=1%2Cabc");
    h.site.set_site_attrs(r#"{"cookie":"odin_tt=xyz"}"#)
        .expect("注入");
    assert_eq!(
        h.site.header_cookie(),
        "ttwid=1%2Cabc; odin_tt=xyz",
        "拼接顺序对齐 Dart '$cookie; $existCookies'"
    );
}

#[tokio::test]
async fn ac40_cookie_never_appears_in_error_messages() {
    let h = harness();
    h.stub_network_error("webcast/user/me/", "连接被重置");
    h.stub_home_html("home_categories");

    // 触发各条错误路径，收集错误文本
    let mut messages: Vec<String> = Vec::new();
    if let Err(e) = h.site.get_account_info(r#"{"cookie":"SESSDATA=SECRET1"}"#.into()).await {
        messages.push(e.to_string());
    }
    if let Err(e) = h.site.get_room_detail("416144012050".into()).await {
        messages.push(e.to_string());
    }
    if let Err(e) = h.site.set_site_attrs("{") {
        messages.push(e.to_string());
    }
    assert!(!messages.is_empty(), "本用例应至少收集到一条错误");

    for msg in &messages {
        for secret in ["SESSDATA", "SECRET1", "ttwid=1%2Cabc"] {
            assert!(
                !msg.contains(secret),
                "错误消息泄漏了凭证片段 {secret}：{msg}"
            );
        }
    }
}

#[test]
fn ac40_cookie_only_reachable_through_header_cookie() {
    // 站点句柄**刻意不实现** Debug/Display：内部 `SiteState` 持 cookie 明文，
    // 一旦有人 `{:?}` 打日志就会泄漏（`bilibili_site.dart:598` 的教训，Spec §9）。
    // 因此本模块只保留「正向可取用」的断言；「不存在 Debug 实现」由 clippy 与
    // 代码审查保证，不写成运行时断言（负向 trait 断言需要 compile-fail 测试，
    // 成本高于收益 —— 门禁改为：新增 `#[derive(Debug)]` 到 DouyinSite 时人工复核）。
    let h = harness();
    h.stub_home_html("home_categories");
    h.site
        .set_site_attrs(r#"{"cookie":"SESSDATA=SECRET1"}"#)
        .expect("注入");
    assert!(
        h.site.header_cookie().contains("SECRET1"),
        "cookie 必须可经 header_cookie 取用（请求需要它）"
    );
}
