//! IP-3 斗鱼：搜索房间 / 搜索主播 / 签名 / 取流 / 账号（QA 夹具驱动）。

mod douyu_common;

use douyu_common::{
    detail, endpoint_key, expected, harness, sample, sample_response, variant_expected,
    variant_response,
};
use serde_json::Value;
use slive_core::error::SliveError;
use slive_core::models::LivePlayQuality;

fn play_data(rate: i32, cdns: &[&str]) -> String {
    serde_json::json!({
        "rate": rate,
        "cdns": cdns.iter().collect::<Vec<_>>(),
    })
    .to_string()
}

// ---------------------------------------------------------------- 搜索房间

#[tokio::test]
async fn search_rooms_matches_fixture() {
    let h = harness();
    h.stub_sample("www_douyu_com_japi_search_api_searchShow");

    let result = h
        .site
        .search_rooms("英雄联盟".to_string(), 1)
        .await
        .expect("搜索房间应成功");
    let want = &expected("www_douyu_com_japi_search_api_searchShow");

    assert_eq!(result.has_more, want["has_more"].as_bool().unwrap());
    assert_eq!(result.items.len(), want["items"].as_array().unwrap().len());
    assert_eq!(result.items[0].room_id, "252140");
    assert_eq!(result.items[0].title, "英雄联盟教学");
    assert_eq!(result.items[0].user_name, "某主播");
    assert_eq!(
        result.items[0].online, 123000,
        "12.3万 -> 123000（Dart parseHotNum）"
    );
    assert_eq!(result.items[1].online, 1000);
}

#[tokio::test]
async fn search_rooms_sends_random_did_and_query() {
    let h = harness();
    h.stub_sample("www_douyu_com_japi_search_api_searchShow");
    h.site
        .search_rooms("英雄联盟".to_string(), 2)
        .await
        .expect("搜索应成功");

    // query 以原值交给 HttpRequest（百分号编码由 reqwest 负责，见 http.rs）
    let query = &h.get.requests()[0].query;
    assert_eq!(
        query,
        &vec![
            ("kw".to_string(), "英雄联盟".to_string()),
            ("page".to_string(), "2".to_string()),
            ("pageSize".to_string(), "20".to_string()),
        ],
        "Dart 固定 pageSize=20，kw 原样透传（不做 trim/编码，那是 reqwest 的职责）"
    );

    let cookie = h.get.requests()[0]
        .headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case("cookie"))
        .map(|(_, v)| v.clone())
        .expect("搜索必须带随机 did cookie");
    assert!(cookie.contains("dy_did="), "实际 {cookie}");
    assert!(cookie.contains("acf_did="), "实际 {cookie}");
    assert_eq!(cookie.matches("dy_did=").count(), 1, "did 只出现一次");
}

#[tokio::test]
async fn search_rooms_hot_unparsable_is_minus_999() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_search_api_searchShow")["endpoint"].as_str().unwrap());
    h.get
        .stub(&key, &variant_response("www_douyu_com_japi_search_api_searchShow", 2));

    let result = h
        .site
        .search_rooms("x".to_string(), 1)
        .await
        .expect("不应抛");
    assert_eq!(
        result.items[0].online, -999,
        "无法解析的人气回落 -999（Dart:350），不能是 0"
    );
    assert!(result.has_more);
}

#[tokio::test]
async fn search_rooms_empty_result() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_search_api_searchShow")["endpoint"].as_str().unwrap());
    h.get
        .stub(&key, &variant_response("www_douyu_com_japi_search_api_searchShow", 1));

    let result = h.site.search_rooms("x".to_string(), 1).await.expect("不应抛");
    assert!(!result.has_more);
    assert!(result.items.is_empty());
}

#[tokio::test]
async fn search_rooms_business_error_throws_not_empty_list() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_search_api_searchShow")["endpoint"].as_str().unwrap());
    h.get
        .stub(&key, &variant_response("www_douyu_com_japi_search_api_searchShow", 0));

    let err = h
        .site
        .search_rooms("x".to_string(), 1)
        .await
        .expect_err("error!=0 必须抛错");
    match err {
        SliveError::Api { message, .. } => {
            assert!(
                message.contains("搜索过于频繁"),
                "错误消息应带服务端原文，实际 {message}"
            );
        }
        other => panic!("期望 SliveError::Api，实际 {other:?}"),
    }
    assert_eq!(
        h.get.request_count("searchShow"),
        1,
        "风控/频率错误不得自动重试"
    );
}

// ---------------------------------------------------------------- 搜索主播

#[tokio::test]
async fn search_anchors_applies_double_condition() {
    let h = harness();
    h.stub_sample("www_douyu_com_japi_search_api_searchUser");

    let result = h
        .site
        .search_anchors("主播".to_string(), 1)
        .await
        .expect("搜索主播应成功");
    let want = &expected("www_douyu_com_japi_search_api_searchUser");

    assert_eq!(result.has_more, want["has_more"].as_bool().unwrap());
    assert_eq!(result.items.len(), 2);
    assert_eq!(result.items[0].room_id, "252140");
    assert_eq!(result.items[0].avatar, "https://example.douyu.com/a.jpg");
    assert!(result.items[0].live_status);
    assert!(
        !result.items[1].live_status,
        "第二个样本未开播"
    );
    assert!(
        h.get
            .request_urls()
            .iter()
            .any(|u| u.contains("filterType=1")),
        "主播搜索必须带 filterType=1"
    );
}

#[tokio::test]
async fn search_anchors_room_type_blocks_live_status() {
    // 夹具 note 明确：isLive=1 但 roomType=1 -> live_status=false（两个条件缺一不可）
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_search_api_searchUser")["endpoint"].as_str().unwrap());
    h.get.stub(
        &key,
        r#"{"error":0,"data":{"relateUser":[
            {"anchorInfo":{"rid":"1","avatar":"a","nickName":"A","isLive":"1","roomType":"1"}},
            {"anchorInfo":{"rid":"2","avatar":"b","nickName":"B","isLive":"0","roomType":"0"}},
            {"anchorInfo":{"rid":"3","avatar":"c","nickName":"C","isLive":"1","roomType":"0"}}
        ]}}"#,
    );

    let result = h.site.search_anchors("x".to_string(), 1).await.expect("不应抛");
    assert!(
        !result.items[0].live_status,
        "roomType=1（游戏直播间）不算在播"
    );
    assert!(!result.items[1].live_status, "isLive=0 不算在播");
    assert!(result.items[2].live_status, "isLive=1 && roomType=0 才算在播");
}

#[tokio::test]
async fn search_anchors_empty_result() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_search_api_searchUser")["endpoint"].as_str().unwrap());
    h.get
        .stub(&key, &variant_response("www_douyu_com_japi_search_api_searchUser", 0));

    let result = h.site.search_anchors("x".to_string(), 1).await.expect("不应抛");
    assert!(!result.has_more);
    assert!(result.items.is_empty());
}

// ---------------------------------------------------------------- 签名

#[tokio::test]
async fn sign_uses_encryption_material_and_fixed_key_order() {
    let h = harness();
    h.stub_encryption();
    h.stub_post_sample("www_douyu_com_lapi_live_getH5PlayV1");

    h.site.get_play_qualities(detail("252140")).await.expect("取清晰度");

    let body = &h.post.requests()[0].body;
    let keys: Vec<&str> = body.split('&').map(|kv| kv.split('=').next().unwrap()).collect();
    assert_eq!(
        keys,
        vec!["enc_data", "tt", "did", "auth", "cdn", "ver", "rate", "hevc", "fa", "ive"],
        "签名键序必须固定（Dart Uri(queryParameters) 的字面量顺序）"
    );
    assert!(body.contains("ver=Douyu_new"));
    assert!(body.contains("rate=-1"), "清晰度列表请求用 rate=-1");
    assert!(body.contains("cdn=hw-h5"));
    assert!(body.contains("hevc=1"));
    assert!(body.contains("fa=0"));
    assert!(body.contains("ive=0"));
    assert_eq!(
        h.get.request_count("getEncryption"),
        1,
        "加密材料必须按需回源"
    );
}

#[tokio::test]
async fn sign_encryption_is_cached_for_ttl() {
    let h = harness();
    h.stub_encryption();
    h.stub_post_sample("www_douyu_com_lapi_live_getH5PlayV1");

    let quality = |_h: &douyu_common::Harness| LivePlayQuality {
        quality: "原画".into(),
        data: play_data(0, &["hw-h5"]),
        sort: 0,
    };
    h.site.get_play_qualities(detail("252140")).await.expect("首次");
    h.site
        .get_play_urls(detail("252140"), quality(&h))
        .await
        .expect("取流");
    assert_eq!(
        h.get.request_count("getEncryption"),
        1,
        "5 分钟 TTL 内不得重复回源加密材料"
    );

    h.time.advance(5 * 60 + 1);
    h.site.get_play_qualities(detail("252140")).await.expect("过期后");
    assert_eq!(h.get.request_count("getEncryption"), 2, "过期后应重新回源");
}

#[tokio::test]
async fn sign_encryption_error_is_typed() {
    let h = harness();
    let key = endpoint_key(
        sample("www_douyu_com_wgapi_livenc_liveweb_websec_getEncryption")["endpoint"]
            .as_str()
            .unwrap(),
    );
    h.get
        .stub(&key, &variant_response("www_douyu_com_wgapi_livenc_liveweb_websec_getEncryption", 0));
    h.stub_post_sample("www_douyu_com_lapi_live_getH5PlayV1");

    let err = h
        .site
        .get_play_qualities(detail("252140"))
        .await
        .expect_err("加密材料失败必须抛类型化错误");
    match err {
        SliveError::Api { code, message } => {
            assert_eq!(code, 1001, "斗鱼业务码原样带出");
            assert_eq!(message, "系统繁忙");
        }
        other => panic!(
            "期望 SliveError::Api（不得静默当空 key），实际 {other:?}"
        ),
    }
    assert_eq!(
        h.post.request_count("getH5PlayV1"),
        0,
        "拿不到签名材料时不得继续请求取流接口"
    );
}

// ---------------------------------------------------------------- 取流

#[tokio::test]
async fn qualities_match_fixture_with_sorted_cdns() {
    let h = harness();
    h.stub_encryption();
    h.stub_post_sample("www_douyu_com_lapi_live_getH5PlayV1");

    let qualities = h
        .site
        .get_play_qualities(detail("252140"))
        .await
        .expect("清晰度应成功");
    let want = &expected("www_douyu_com_lapi_live_getH5PlayV1");

    assert_eq!(qualities.len(), want["qualities"].as_array().unwrap().len());
    assert_eq!(qualities.len(), 3);
    assert_eq!(qualities[0].quality, "原画");
    assert_eq!(qualities[1].quality, "高清");
    assert_eq!(qualities[2].quality, "蓝光");
    for (index, want_quality) in want["qualities"].as_array().unwrap().iter().enumerate() {
        let data: Value = serde_json::from_str(&qualities[index].data).expect("data 是 JSON 串");
        assert_eq!(
            data["rate"].as_i64().unwrap(),
            want_quality["rate"].as_i64().unwrap(),
            "清晰度 {index} 的 rate 必须原样带出"
        );
        let want_cdns = want["cdns_sorted"].as_array().expect("cdns_sorted");
        assert_eq!(
            data["cdns"].as_array().expect("cdns"),
            want_cdns.as_slice(),
            "清晰度 {index} 必须带上排好序的线路列表（scdn 在后）"
        );
    }
}

#[tokio::test]
async fn urls_are_fetched_per_cdn() {
    let h = harness();
    h.stub_encryption();
    h.post.stub(
        "getH5PlayV1",
        r#"{"error":0,"data":{"rtmp_url":"https://cdn.example.com/live","rtmp_live":"252140.flv?wsAuth=a1"}}"#,
    );

    let quality = LivePlayQuality {
        quality: "原画".into(),
        data: play_data(0, &["hw-h5", "tct-h5"]),
        sort: 0,
    };
    let result = h
        .site
        .get_play_urls(detail("252140"), quality)
        .await
        .expect("取流应成功");

    assert_eq!(
        result.urls,
        vec![
            "https://cdn.example.com/live/252140.flv?wsAuth=a1".to_string(),
            "https://cdn.example.com/live/252140.flv?wsAuth=a1".to_string(),
        ],
        "每条线路各取一次直链"
    );
    assert_eq!(h.post.request_count("getH5PlayV1"), 2);
    let second_body = &h.post.requests()[1].body;
    assert!(second_body.contains("cdn=tct-h5"), "实际 {second_body}");
    assert!(second_body.contains("rate=0"));
}

#[tokio::test]
async fn oversea_expire_workaround_appended_for_ws_cdn() {
    let h = harness();
    h.stub_encryption();
    h.post.stub(
        "getH5PlayV1",
        r#"{"error":0,"data":{"rtmp_url":"https://cdn.example.com/live","rtmp_live":"252140.flv?wsAuth=ws&expire=300&fcdn=ws"}}"#,
    );

    let quality = LivePlayQuality {
        quality: "原画".into(),
        data: play_data(0, &["ws-h5"]),
        sort: 0,
    };
    let result = h
        .site
        .get_play_urls(detail("252140"), quality)
        .await
        .expect("取流应成功");

    assert_eq!(
        result.urls[0],
        "https://cdn.example.com/live/252140.flv?wsAuth=ws&expire=300&fcdn=ws&expire=0",
        "海外 ws 线路必须追加 expire=0（游客模式否则 5 分钟断流）"
    );
}

/// 变体 1：海外 ws 线路 + `expire=300` -> 追加 `expire=0`。
///
/// 夹具的 `expected.urls` 描述的是**第二次请求**（逐线路取直链）的返回，
/// 而 `variants[].response` 只是清晰度响应 —— 故这里按 expected 反推 `rtmp_live`。
#[tokio::test]
async fn urls_oversea_variant_appends_expire_zero() {
    let h = harness();
    h.stub_encryption();
    let want = variant_expected("www_douyu_com_lapi_live_getH5PlayV1", 1);
    let url = want["urls"][0].as_str().expect("urls[0]");
    // expected 形如 "{rtmp_url}/{rtmp_live}"，按最后一个 '/' 拆回两个字段
    let (base, live) = url
        .rsplit_once('/')
        .expect("expected URL 含 rtmp_live 段");
    h.post.stub(
        "getH5PlayV1",
        &serde_json::json!({
            "error": 0,
            "data": {
                "rtmp_url": base,
                "rtmp_live": live.split_once("&expire=0").map(|(head, _)| head).unwrap_or(live),
            }
        })
        .to_string(),
    );

    let quality = LivePlayQuality {
        quality: "高清".into(),
        data: play_data(900, &["hw-h5"]),
        sort: 0,
    };
    let result = h
        .site
        .get_play_urls(detail("252140"), quality)
        .await
        .expect("取流应成功");
    assert_eq!(
        result.urls[0], url,
        "海外 ws 线路必须追加 expire=0（夹具 expected.urls[0]）"
    );
}

/// 非海外线路（无 `expire=300`）-> 原样返回，不追加任何参数。
#[tokio::test]
async fn urls_non_oversea_line_is_untouched() {
    let h = harness();
    h.stub_encryption();
    h.post.stub(
        "getH5PlayV1",
        r#"{"error":0,"data":{"rtmp_url":"https://cdn.example.com/live","rtmp_live":"252140.m3u8?wsAuth=hls"}}"#,
    );

    let quality = LivePlayQuality {
        quality: "高清".into(),
        data: play_data(900, &["hw-h5"]),
        sort: 0,
    };
    let result = h
        .site
        .get_play_urls(detail("252140"), quality)
        .await
        .expect("取流应成功");
    assert_eq!(
        result.urls,
        vec!["https://cdn.example.com/live/252140.m3u8?wsAuth=hls".to_string()],
        "非海外线路不得追加 expire=0"
    );
}

#[tokio::test]
async fn urls_malformed_quality_data_is_invalid_input() {
    let h = harness();
    h.stub_encryption();
    let quality = LivePlayQuality {
        quality: "坏数据".into(),
        data: "not-json".into(),
        sort: 0,
    };
    let err = h
        .site
        .get_play_urls(detail("252140"), quality)
        .await
        .expect_err("非法 quality.data 必须报错");
    assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
}

// ---------------------------------------------------------------- 账号

#[tokio::test]
async fn set_site_attrs_is_json_validated_and_partial_tolerant() {
    let h = harness();
    let err = h
        .site
        .set_site_attrs("not-json")
        .expect_err("非法 JSON 必须报错");
    assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");

    h.site
        .set_site_attrs(r#"{"cookie":"acf_uid=1","dy_did":"DID-1","LTP0":"LTP1"}"#)
        .expect("合法 JSON 应成功");
    assert_eq!(h.site.cookie(), "acf_uid=1");
    assert_eq!(h.site.dy_did(), "DID-1");
    assert_eq!(h.site.ltp0(), "LTP1");

    // 缺键 -> 保留旧值（Spec J-5）
    h.site.set_site_attrs(r#"{"foo":"bar"}"#).expect("缺键不应抛");
    assert_eq!(h.site.cookie(), "acf_uid=1", "缺 cookie 键必须保留旧值");
    assert_eq!(h.site.dy_did(), "DID-1");
}

#[tokio::test]
async fn qr_code_generation_matches_fixture() {
    let h = harness();
    h.get.stub("passport.douyu.com/lapi/did/api/get", r#"cb({"data":{"did":"DID-FIXED"}})"#);
    h.stub_post_sample("passport_douyu_com_scan_generateCode");

    let qr = h.site.get_qr_code().await.expect("二维码应成功");
    let want = expected("passport_douyu_com_scan_generateCode");
    assert_eq!(qr.key, want["key"].as_str().unwrap());
    assert_eq!(qr.url, want["url"].as_str().unwrap());
    assert_eq!(
        qr.expire_at,
        Some(douyu_common::FIXED_TS as i64 + 300),
        "有效期 = now + 300 秒"
    );
    assert_eq!(
        h.site.dy_did(),
        "DID-FIXED",
        "生成二维码前必须先取 dy_did 并写入句柄"
    );
    assert_eq!(
        h.post.requests()[0].body,
        "client_id=1&isMultiAccount=0",
        "表单键序固定（Dart:415）"
    );
}

#[tokio::test]
async fn qr_code_business_error_throws() {
    let h = harness();
    h.get.stub("passport.douyu.com/lapi/did/api/get", r#"cb({"data":{"did":"D"}})"#);
    let key = endpoint_key(sample("passport_douyu_com_scan_generateCode")["endpoint"].as_str().unwrap());
    h.post
        .stub(&key, &variant_response("passport_douyu_com_scan_generateCode", 0));

    let err = h.site.get_qr_code().await.expect_err("error!=0 必须抛错");
    match err {
        SliveError::Api { message, .. } => assert!(
            message.contains("生成失败"),
            "错误消息应带服务端原文，实际 {message}"
        ),
        other => panic!("期望 SliveError::Api，实际 {other:?}"),
    }
}

#[tokio::test]
async fn qr_poll_status_mapping() {
    // 变体 0 未扫码 / 1 已扫码待确认 / 2 已过期
    let cases = [(0usize, "unscanned"), (1, "scanned"), (2, "expired")];
    for (index, want_status) in cases {
        let h = harness();
        let key = endpoint_key(sample("passport_douyu_com_japi_scan_auth")["endpoint"].as_str().unwrap());
        h.get
            .stub(&key, &variant_response("passport_douyu_com_japi_scan_auth", index));

        let result = h
            .site
            .get_qr_poll_result("qr-key".to_string())
            .await
            .unwrap_or_else(|e| panic!("变体 {index} 不应抛: {e}"));
        assert_eq!(
            format!("{:?}", result.status).to_lowercase(),
            want_status,
            "变体 {index} 的状态映射"
        );
        assert_eq!(
            result.credential, "",
            "变体 {index}: 未拿到登录凭据时不得产出 credential"
        );
    }
}

#[tokio::test]
async fn qr_poll_success_produces_credential_from_set_cookie() {
    let h = harness();
    let key = endpoint_key(sample("passport_douyu_com_japi_scan_auth")["endpoint"].as_str().unwrap());
    let variant: Value = sample("passport_douyu_com_japi_scan_auth")["variants"][3].clone();
    let set_cookie: Vec<String> = variant["mock_set_cookie"]
        .as_array()
        .expect("mock_set_cookie")
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    h.get.stub_with_cookie(
        &key,
        &serde_json::to_string(&variant["response"]).expect("序列化"),
        set_cookie,
    );
    // cookie 续期会打 safeAuth（未过期则不打）
    h.get.stub(
        "passport.douyu.com/lapi/passport/iframe/safeAuth",
        &sample_response("passport_douyu_com_lapi_passport_iframe_safeAuth"),
    );

    let result = h
        .site
        .get_qr_poll_result("qr-key".to_string())
        .await
        .expect("轮询应成功");
    assert_eq!(format!("{:?}", result.status).to_lowercase(), "scanned");

    let credential: Value =
        serde_json::from_str(&result.credential).expect("credential 是 JSON 串");
    let want_keys = variant_expected("passport_douyu_com_japi_scan_auth", 3)["credential_keys"]
        .as_array()
        .expect("credential_keys")
        .clone();
    for key in &want_keys {
        assert!(
            credential.get(key.as_str().unwrap()).is_some(),
            "credential 必须含键 {}",
            key.as_str().unwrap()
        );
    }
    assert_eq!(
        credential["LTP0"].as_str().unwrap(),
        "ltp0-value",
        "LTP0 从 set-cookie 提取"
    );
    assert_eq!(h.site.ltp0(), "ltp0-value", "LTP0 必须回填句柄");
}

#[tokio::test]
async fn qr_poll_missing_url_and_unknown_code_throw() {
    // 变体 4：error=0 但 data.url 缺失
    let h = harness();
    let key = endpoint_key(sample("passport_douyu_com_japi_scan_auth")["endpoint"].as_str().unwrap());
    h.get
        .stub(&key, &variant_response("passport_douyu_com_japi_scan_auth", 4));
    let err = h
        .site
        .get_qr_poll_result("k".to_string())
        .await
        .expect_err("缺确认地址必须抛错");
    assert!(err.to_string().contains("登录确认地址"), "实际 {err}");

    // 变体 5：未知 error 码
    let h2 = harness();
    h2.get
        .stub(&key, &variant_response("passport_douyu_com_japi_scan_auth", 5));
    let err = h2
        .site
        .get_qr_poll_result("k".to_string())
        .await
        .expect_err("未知错误码必须抛错");
    assert!(err.to_string().contains("无法确认登录"), "实际 {err}");
}

#[tokio::test]
async fn account_info_reads_acf_fields_from_cookie() {
    let h = harness();
    h.get.stub_with_cookie(
        "passport.douyu.com/lapi/passport/iframe/safeAuth",
        &sample_response("passport_douyu_com_lapi_passport_iframe_safeAuth"),
        vec![
            "acf_uid=998877; Path=/".to_string(),
            "acf_nickname=%E4%B8%80%E4%B8%AA%E4%BA%BA; Path=/".to_string(),
            format!("acf_jwt_token={}; Path=/", valid_jwt(4_102_444_800)),
            "acf_avatar=https://example.douyu.com/av.jpg; Path=/".to_string(),
        ],
    );

    // 注入一个**已过期**的 cookie，迫使走 refreshCookie
    let expired = format!(
        "acf_uid=998877; acf_jwt_token={}",
        valid_jwt(1_600_000_000)
    );
    let credential = serde_json::json!({
        "cookie": expired,
        "dy_did": "DID-1",
        "LTP0": "ltp0-value",
    })
    .to_string();

    let info = h
        .site
        .get_account_info(credential)
        .await
        .expect("账号信息不应抛（Dart 全吞异常）");
    assert!(info.is_valid, "续期成功后应有效");
    assert_eq!(info.uid.as_deref(), Some("998877"));
    assert_eq!(info.name.as_deref(), Some("一个人"), "昵称需 URL 解码");
    assert_eq!(
        info.avatar.as_deref(),
        Some("https://example.douyu.com/av.jpgmiddle.jpg"),
        "头像需解码并补 middle.jpg"
    );
    assert!(
        h.get.request_count("safeAuth") >= 1,
        "过期 cookie 必须走 safeAuth 续期"
    );
    // 写回凭证必须保留续期材料（dy_did/LTP0），只换 cookie
    let written: serde_json::Value =
        serde_json::from_str(&info.credential).expect("credential 应是合法 JSON");
    assert_eq!(written["dy_did"], "DID-1", "dy_did 丢了到期就续不了期");
    assert_eq!(written["LTP0"], "ltp0-value", "LTP0 丢了到期就续不了期");
    assert!(
        written["cookie"].as_str().unwrap_or("").contains("acf_uid=998877"),
        "cookie 应为续期后的新值，实际 {}",
        written["cookie"]
    );
}

#[tokio::test]
async fn account_info_invalid_when_refresh_fails() {
    let h = harness();
    // safeAuth 返回空 set-cookie -> 续期结果为空 -> isValid=false
    h.get.stub_with_cookie(
        "passport.douyu.com/lapi/passport/iframe/safeAuth",
        &sample_response("passport_douyu_com_lapi_passport_iframe_safeAuth"),
        vec![],
    );
    let credential = serde_json::json!({
        "cookie": format!("acf_jwt_token={}", valid_jwt(1_600_000_000)),
        "dy_did": "DID-1",
        "LTP0": "ltp0-value",
    })
    .to_string();

    let info = h.site.get_account_info(credential).await.expect("不应抛");
    assert!(!info.is_valid, "续期失败必须 isValid=false 而非抛错");
    assert!(info.uid.is_none());
}

/// 构造一个 payload 为 `{"exp":<exp>}` 的 JWT（base64url 手写，测试内自足）。
fn valid_jwt(exp: i64) -> String {
    let payload = format!("{{\"exp\":{exp}}}");
    let encoded = base64url(payload.as_bytes());
    format!("aaa.{encoded}.ccc")
}

fn base64url(input: &[u8]) -> String {
    const TABLE: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    for chunk in input.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        let indexes = [
            (n >> 18) & 63,
            (n >> 12) & 63,
            if chunk.len() > 1 { (n >> 6) & 63 } else { 64 },
            if chunk.len() > 2 { n & 63 } else { 64 },
        ];
        for index in indexes {
            if index != 64 {
                out.push(TABLE[index as usize] as char);
            }
        }
    }
    out
}