//! Twitch HTTP 读链路离线用例（IP-5-HTTP-DETAIL / IP-5-HTTP-PLAY / IP-5-HTTP-STATUS）。
//!
//! 夹具：`tests/fixtures/twitch/http/http-samples.json`（合成，逐字段标注 Dart 行号）。
//! 覆盖：成功流（在线详情 / 离线详情 / 清晰度 / 取流）+ 错误流（用户不存在 / 缺字段 /
//! 短批量 / 非法 JSON / HTTP 失败 / 缺 token）+ 未实现能力 + 无重试断言。
//!
//! 断言口径：字段期望值直接读夹具的 `expected` 段（避免「实现与夹具同源」的
//! 自证循环 —— 夹具是先前按 Dart 行号独立写出的）。

mod twitch_common;

use serde_json::Value;
use slive_core::error::SliveError;
use slive_core::platforms::twitch::gql::{
    CHANNEL_SHELL_HASH, PLAYBACK_ACCESS_TOKEN_HASH, STREAM_METADATA_HASH,
};
use twitch_common::{harness, sample, variant_name, GQL_KEY, PLAYLIST_KEY};

const SHELL: &str = "gql_twitch_tv_room_shell";
const TOKEN: &str = "gql_twitch_tv_playback_access_token";
const PLAYLIST: &str = "usher_ttvnw_net_master_m3u8";

/// 夹具 `expected` 段。
fn expected(key: &str) -> Value {
    sample(key)["expected"].clone()
}

fn expect_str(key: &str, field: &str) -> String {
    expected(key)[field]
        .as_str()
        .unwrap_or_else(|| panic!("夹具 {key}.expected 缺字段 {field}"))
        .to_string()
}

// ------------------------------------------------------------------ 房间详情

#[tokio::test]
async fn room_detail_online_matches_fixture_expectations() {
    let h = harness();
    h.stub_gql_sample(SHELL);

    let detail = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect("在线详情应成功");
    let want = expected(SHELL);

    assert_eq!(detail.room_id, want["room_id"]);
    assert_eq!(detail.title, want["title"]);
    assert_eq!(detail.cover, want["cover"]);
    assert_eq!(detail.user_name, want["user_name"]);
    assert_eq!(detail.user_avatar, want["user_avatar"]);
    assert_eq!(detail.online, want["online"].as_i64().expect("online") as i32);
    assert_eq!(detail.status, want["status"].as_bool().expect("status"));
    assert_eq!(detail.url, want["url"]);
    assert_eq!(detail.introduction.as_deref(), Some(""));
    assert_eq!(detail.notice.as_deref(), Some(""));
    assert!(detail.data.is_none(), "Twitch 不走取流接口拼 URL");
    assert!(!detail.is_record);

    // danmaku_data：照搬 Dart `twitch_site.dart:241` —— 就是 roomId 字符串。
    assert_eq!(
        detail.danmaku_data.as_deref(),
        Some(want["danmaku_data"].as_str().expect("danmaku_data")),
        "danmaku_data 应原样是 roomId（Dart 口径，非 JSON 包装）"
    );
}

#[tokio::test]
async fn room_detail_uses_single_batch_request_with_pinned_hashes() {
    let h = harness();
    h.stub_gql_sample(SHELL);
    h.site
        .get_room_detail("alice".to_string())
        .await
        .expect("详情");

    assert_eq!(
        h.gql.request_count(GQL_KEY),
        1,
        "ChannelShell + StreamMetadata 必须合成一次批量请求（请求数不得增加）"
    );
    let bodies = h.gql_bodies();
    let batch = bodies[0].as_array().expect("批量请求体应为数组");
    assert_eq!(batch.len(), 2);
    // 顺序固定：_getRoomInfo 取 first 与 [1]，颠倒会取错对象
    assert_eq!(batch[0]["operationName"], "ChannelShell");
    assert_eq!(
        batch[0]["extensions"]["persistedQuery"]["sha256Hash"],
        CHANNEL_SHELL_HASH
    );
    assert_eq!(batch[0]["variables"]["login"], "alice");
    assert_eq!(batch[1]["operationName"], "StreamMetadata");
    assert_eq!(
        batch[1]["extensions"]["persistedQuery"]["sha256Hash"],
        STREAM_METADATA_HASH
    );
    assert_eq!(batch[1]["variables"]["channelLogin"], "alice");
    assert_eq!(batch[1]["variables"]["includeIsDJ"], true);
    assert_eq!(batch[0]["extensions"]["persistedQuery"]["version"], 1);
}

#[tokio::test]
async fn room_detail_request_carries_twitch_headers_without_cookie() {
    let h = harness();
    h.stub_gql_sample(SHELL);
    h.site
        .get_room_detail("alice".to_string())
        .await
        .expect("详情");

    let headers = &h.gql.requests()[0].headers;
    let get = |key: &str| {
        headers
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    };
    assert_eq!(get("client-id"), "kimne78kx3ncx6brgo4mv6wki5h1ko");
    assert!(get("user-agent").contains("Chrome/137"));
    assert_eq!(get("accept"), "application/vnd.twitchtv.v5+json");
    assert_eq!(get("accept-language"), "en-US,en;q=0.9");
    assert!(
        get("device-id").parse::<u64>().is_ok(),
        "device-id 应为数字串，实际 {:?}",
        get("device-id")
    );
    assert!(
        !headers.iter().any(|(k, _)| k == "cookie"),
        "匿名链路不注入 cookie（Dart:38 注释 'no cookie'）"
    );
    assert!(
        !headers.iter().any(|(k, _)| k == "accept-encoding"),
        "不手写 accept-encoding（交给 reqwest，避免声明与解码器不匹配）"
    );
}

#[tokio::test]
async fn room_detail_offline_variant_reports_not_live() {
    let h = harness();
    h.stub_gql_variant(SHELL, 0); // 未开播（stream 为 null）
    let name = variant_name(SHELL, 0);

    let detail = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .unwrap_or_else(|e| panic!("变体「{name}」不应抛错: {e}"));

    assert!(!detail.status, "变体「{name}」: stream==null -> 不在播");
    assert_eq!(detail.online, 0, "未开播人气为 0（Dart:236 只在播时取 viewersCount）");
}

#[tokio::test]
async fn room_detail_missing_last_broadcast_falls_back_to_literal_null() {
    let h = harness();
    h.stub_gql_variant(SHELL, 1); // 无 lastBroadcast
    let detail = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect("缺 lastBroadcast 不应抛");
    assert_eq!(
        detail.title, "null",
        "Dart:229 的 `?? \"null\"` 是字面量字符串，保持一致以免 UI 显示变化"
    );
}

// ------------------------------------------------------------------ 错误流

#[tokio::test]
async fn error_variants_map_to_typed_errors() {
    // 变体 2: UserNotFoundError -> NotFound
    let h = harness();
    h.stub_gql_variant(SHELL, 2);
    let name = variant_name(SHELL, 2);
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("UserNotFoundError 必须报错");
    assert!(
        matches!(err, SliveError::NotFound(_)),
        "变体「{name}」应为 NotFound，实际 {err:?}"
    );

    // 变体 3: user 为 null -> NotFound（Dart 抛 'Could not find user'）
    let h = harness();
    h.stub_gql_variant(SHELL, 3);
    let name = variant_name(SHELL, 3);
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("user=null 必须报错");
    match err {
        SliveError::NotFound(msg) => assert!(
            msg.contains("Could not find user") || msg.contains("user"),
            "变体「{name}」消息应指明 user 缺失，实际 {msg}"
        ),
        other => panic!("变体「{name}」应为 NotFound，实际 {other:?}"),
    }

    // 变体 4: 响应数组长度 < 2 -> Decode
    let h = harness();
    h.stub_gql_variant(SHELL, 4);
    let name = variant_name(SHELL, 4);
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("短批量必须报错");
    assert!(
        matches!(err, SliveError::Decode(_)),
        "变体「{name}」应为 Decode，实际 {err:?}"
    );
}

#[tokio::test]
async fn non_array_batch_is_decode_error() {
    let h = harness();
    h.stub_gql_raw(r#"{"data":{"userOrError":null}}"#);
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("非数组响应必须报错");
    assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
}

#[tokio::test]
async fn invalid_json_is_decode_error() {
    let h = harness();
    h.stub_gql_raw("not json at all");
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("非法 JSON 必须报错");
    assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
}

#[tokio::test]
async fn http_error_status_is_propagated_without_retry() {
    let h = harness();
    h.gql.stub_http_error(GQL_KEY, 400);
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("HTTP 400 必须报错");
    match err {
        SliveError::Http { status, .. } => assert_eq!(status, 400),
        other => panic!("期望 Http(400)，实际 {other:?}"),
    }
    assert_eq!(h.gql.request_count(GQL_KEY), 1, "不自动重试（Spec §9）");
}

#[tokio::test]
async fn network_failure_is_propagated() {
    let h = harness();
    h.gql.stub_network_error(GQL_KEY, "dns fail");
    let err = h
        .site
        .get_room_detail("alice".to_string())
        .await
        .expect_err("网络失败必须报错");
    assert!(matches!(err, SliveError::Network(_)), "实际 {err:?}");
}

// ------------------------------------------------------------------ 直播状态

#[tokio::test]
async fn live_status_reflects_stream_type() {
    let h = harness();
    h.stub_gql_sample(SHELL);
    assert!(
        h.site
            .get_live_status("alice".to_string())
            .await
            .expect("在线状态")
    );
    assert_eq!(h.gql.request_count(GQL_KEY), 1, "只请求一次");

    let h2 = harness();
    h2.stub_gql_variant(SHELL, 0);
    assert!(
        !h2.site
            .get_live_status("alice".to_string())
            .await
            .expect("离线状态")
    );
}

// ------------------------------------------------------------------ 清晰度 / 取流

#[tokio::test]
async fn play_qualities_match_fixture_expectations() {
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist();

    let qualities = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .expect("清晰度应成功");
    let want = expected(PLAYLIST)["qualities"]
        .as_array()
        .expect("qualities 数组")
        .clone();

    assert_eq!(qualities.len(), want.len(), "线路数应与夹具一致");
    for (got, expect) in qualities.iter().zip(want.iter()) {
        assert_eq!(got.quality, expect["quality"], "清晰度名");
        assert_eq!(got.data, expect["url"], "quality.data 存播放 URL（Dart 口径）");
        assert_eq!(
            i64::from(got.sort),
            expect["sort"].as_i64().expect("sort"),
            "sort 为带宽"
        );
    }
    // 降序（与 Dart `_playUrlList.sort` 一致）
    assert!(qualities.windows(2).all(|w| w[0].sort > w[1].sort));

    assert_eq!(h.gql.request_count(GQL_KEY), 1);
    assert_eq!(h.http.request_count(PLAYLIST_KEY), 1);
    let body = h.gql_bodies()[0].clone();
    assert_eq!(body["operationName"], "PlaybackAccessToken");
    assert_eq!(
        body["extensions"]["persistedQuery"]["sha256Hash"],
        PLAYBACK_ACCESS_TOKEN_HASH
    );
    assert_eq!(body["variables"]["login"], "alice");
    assert_eq!(body["variables"]["isLive"], true);
    assert_eq!(body["variables"]["playerType"], "site");
    assert_eq!(body["variables"]["isVod"], false);
}

#[tokio::test]
async fn play_qualities_pass_token_signature_and_session_to_usher() {
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist();
    h.site
        .get_play_qualities(h.detail("alice", true))
        .await
        .expect("清晰度");

    let req = &h.http.requests()[0];
    let param = |key: &str| {
        req.query
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    };
    assert!(req.url.starts_with("https://usher.ttvnw.net/api/channel/hls/"));
    assert!(req.url.ends_with("/alice.m3u8"));
    assert_eq!(param("platform"), "web");
    assert_eq!(param("player_backend"), "mediaplayer");
    assert_eq!(param("player_version"), "1.28.0-rc.1");
    assert_eq!(param("transcode_mode"), "cbr_v1");
    assert_eq!(param("acmb"), "e30=");
    assert_eq!(param("cdm"), "wv");
    assert_eq!(param("allow_source"), "true");
    assert_eq!(param("fast_bread"), "true");
    assert_eq!(param("playlist_include_framerate"), "true");
    assert_eq!(param("reassignments_supported"), "true");
    assert!(!param("sig").is_empty(), "必须带签名");
    assert!(!param("token").is_empty(), "必须带 token");
    assert!(
        ["bdd22331a986c7f1073628f2fc5b19da", "064bc3ff1722b6f53b0b5b8c01e46ca5"]
            .contains(&param("play_session_id").as_str()),
        "play_session_id 必须取自两个候选，实际 {}",
        param("play_session_id")
    );
    assert_eq!(
        param("p"),
        twitch_common::FIXED_WTS.to_string(),
        "p 取注入时间源（Dart 写的是 DateTime.timestamp().second 的 0~59 秒字段，\
Rust 用 Unix 秒 —— 仅为缓存击穿参数，差异已在 play.rs 登记）"
    );
    assert_eq!(
        req.headers
            .iter()
            .find(|(k, _)| k == "client-id")
            .map(|(_, v)| v.as_str()),
        Some("kimne78kx3ncx6brgo4mv6wki5h1ko"),
        "匿名播放仍需 client-id"
    );
}

#[tokio::test]
async fn play_qualities_empty_when_offline_but_token_still_fetched() {
    let h = harness();
    h.stub_gql_sample(TOKEN);

    let qualities = h
        .site
        .get_play_qualities(h.detail("alice", false))
        .await
        .expect("未开播应返回空列表而非报错");

    assert!(qualities.is_empty(), "未开播无清晰度");
    assert_eq!(
        h.gql.request_count(GQL_KEY),
        1,
        "Dart 无条件先取 token（:106 在 if(liveStatus) 之前），保持同请求序列"
    );
    assert_eq!(h.http.request_count(PLAYLIST_KEY), 0, "未开播不请求 m3u8");
}

#[tokio::test]
async fn playlist_variants_cover_fallback_and_boundary_cases() {
    // 变体 0：无 https:// 行 -> 走 m3u8 结尾兜底
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist_variant(0);
    let name = variant_name(PLAYLIST, 0);
    let got = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .unwrap_or_else(|e| panic!("变体「{name}」不应抛错: {e}"));
    assert!(!got.is_empty(), "变体「{name}」: 兜底分支仍应取到线路");

    // 变体 1：只有一条线路
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist_variant(1);
    let name = variant_name(PLAYLIST, 1);
    let got = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .unwrap_or_else(|e| panic!("变体「{name}」不应抛错: {e}"));
    assert_eq!(got.len(), 1, "变体「{name}」应只有一条线路");
    assert_eq!(got[0].quality, "1080P");

    // 变体 2：空清单 -> 不抛，App 侧表现为无清晰度
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist_variant(2);
    let name = variant_name(PLAYLIST, 2);
    let got = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .unwrap_or_else(|e| panic!("变体「{name}」不应抛错: {e}"));
    assert!(got.is_empty(), "变体「{name}」应为空清晰度");

    // 变体 3：BANDWIDTH 少于 URL 数 -> 缺带宽者兜底 0 -> 「自动」且排最后
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.stub_playlist_variant(3);
    let name = variant_name(PLAYLIST, 3);
    let got = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .unwrap_or_else(|e| panic!("变体「{name}」不应抛错: {e}"));
    assert!(
        got.last().is_some_and(|q| q.sort == 0 && q.quality == "自动"),
        "变体「{name}」: 缺带宽的线路应兜底 0/自动 并排最后，实际 {got:?}"
    );
}

#[tokio::test]
async fn missing_playback_token_variant_is_decode_error() {
    let h = harness();
    h.stub_gql_variant(TOKEN, 0); // 错误流：字段缺失
    let name = variant_name(TOKEN, 0);
    let err = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .expect_err("变体「{name}」必须报错");
    assert!(
        matches!(err, SliveError::Decode(_)),
        "变体「{name}」应为 Decode，实际 {err:?}"
    );
}

#[tokio::test]
async fn playlist_http_failure_is_propagated_without_retry() {
    let h = harness();
    h.stub_gql_sample(TOKEN);
    h.http.stub_http_error(PLAYLIST_KEY, 403);
    let err = h
        .site
        .get_play_qualities(h.detail("alice", true))
        .await
        .expect_err("m3u8 403 必须报错");
    match err {
        SliveError::Http { status, .. } => assert_eq!(status, 403),
        other => panic!("期望 Http(403)，实际 {other:?}"),
    }
    assert_eq!(h.http.request_count(PLAYLIST_KEY), 1, "不重试");
}

#[tokio::test]
async fn play_urls_wrap_quality_url_with_headers() {
    let h = harness();
    let url_in = "https://video-edge-1.example.chuigo.tvlive.tv/chunked/index-dvr.m3u8";
    let url = h
        .site
        .get_play_urls(h.detail("alice", true), h.quality(url_in))
        .await
        .expect("取流应成功");

    assert_eq!(url.urls, vec![url_in.to_string()]);
    let headers = url.headers.expect("应带播放头");
    assert_eq!(
        headers.get("client-id").map(String::as_str),
        Some("kimne78kx3ncx6brgo4mv6wki5h1ko")
    );
    assert!(headers
        .get("user-agent")
        .is_some_and(|ua| ua.contains("Chrome")));
    assert_eq!(h.gql.request_count(GQL_KEY), 0, "取流不再发网络请求");
}

#[tokio::test]
async fn play_urls_rejects_empty_quality_data() {
    let h = harness();
    let err = h
        .site
        .get_play_urls(h.detail("alice", true), h.quality("   "))
        .await
        .expect_err("空清晰度数据应报错");
    assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
}

// ------------------------------------------------------------------ 未实现能力

#[tokio::test]
async fn unsupported_capabilities_match_dart_semantics() {
    let h = harness();

    // 恒空（Dart:67-70 / :73-77 / :282-285）
    assert!(h.site.get_categories().await.expect("分类恒空").is_empty());
    let rooms = h
        .site
        .get_category_rooms(
            slive_core::models::LiveSubCategory {
                id: "x".into(),
                name: "x".into(),
                parent_id: String::new(),
                pic: None,
            },
            1,
            Some(20),
        )
        .await
        .expect("分类房间恒空");
    assert!(!rooms.has_more && rooms.items.is_empty());
    assert!(h
        .site
        .get_super_chat_messages("alice".to_string())
        .await
        .expect("SC 恒空")
        .is_empty());

    // 恒报错（Dart:202-204 / :293-319 的 UnimplementedError -> InvalidInput）
    for err in [
        h.site.get_recommend_rooms(1, None).await.err(),
        h.site.set_site_attrs("{}").err(),
        h.site.get_qr_code().await.err(),
        h.site.get_qr_poll_result("k".to_string()).await.err(),
        h.site
            .get_account_info("credential".to_string())
            .await
            .err(),
    ] {
        assert!(
            matches!(err, Some(SliveError::InvalidInput(_))),
            "未实现应为 InvalidInput，实际 {err:?}"
        );
    }
    assert_eq!(h.gql.requests().len(), 0, "不支持的能力不发请求");
}

#[tokio::test]
async fn search_reports_api_error_with_dart_message() {
    let h = harness();
    for err in [
        h.site.search_rooms("k".to_string(), 1).await.err(),
        h.site.search_anchors("k".to_string(), 1).await.err(),
    ] {
        match err.expect("搜索必须报错") {
            SliveError::Api { code, message } => {
                assert_eq!(code, -1);
                assert!(message.contains("twitch暂不支持搜索"), "实际 {message}");
            }
            other => panic!("期望 Api(-1)，实际 {other:?}"),
        }
    }
}

// ------------------------------------------------------------------ 站点属性 / 夹具自检

#[test]
fn site_id_and_name_match_dart() {
    let h = harness();
    assert_eq!(h.site.id(), "twitch");
    assert_eq!(h.site.name(), "Twitch");
    assert_eq!(h.site.device_id(), h.site.device_id(), "device-id 句柄级稳定");
    assert_eq!(
        h.site.now_secs(),
        twitch_common::FIXED_WTS,
        "时间来自注入源"
    );
}

#[test]
fn fixture_samples_are_present_and_synthetic() {
    for key in [SHELL, TOKEN, PLAYLIST] {
        assert!(
            sample(key)["endpoint"].as_str().is_some(),
            "{key} 缺 endpoint"
        );
        assert_eq!(
            sample(key)["synthetic"], true,
            "{key} 应显式标注为合成夹具"
        );
    }
    // 夹具 `expected` 的 danmaku_data 必须是裸 roomId（QA 钉死，防擅自改回 JSON 包装）
    assert_eq!(expected(SHELL)["danmaku_data"].as_str(), Some("alice"));
    assert_eq!(expect_str(SHELL, "url"), "https://www.twitch.tv/alice");
}
