//! 抖音房间详情 / 清晰度 / 取流 / 状态 AC（含三段降级链路）。
//!
//! 覆盖：19 位 roomId 直连、web/enter、`web/enter` 降级骨架补救、页面 HTML 兜底、
//! 未开播、房间不存在、清晰度三分支、hlsFirst、非法通道。

mod douyin_common;

use douyin_common::harness;
use slive_core::error::SliveError;

/// 首页 ttwid 夹具（`ensure_ttwid` 与分类共用同一 URL）。
fn stub_ttwid(h: &douyin_common::Harness) {
    h.stub_home_html("home_categories");
}

#[tokio::test]
async fn ac_douyin_detail_by_web_rid_from_enter() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("webRid 应走 web/enter 成功");

    assert!(detail.status, "status=2 即在播");
    assert_eq!(detail.room_id, "416144012050");
    assert_eq!(detail.title, "音乐直播间");
    assert_eq!(detail.user_name, "主播A");
    assert_eq!(detail.user_avatar, "https://p3.douyinpic.com/avatar-a.jpeg");
    assert_eq!(detail.online, 12345);
    assert_eq!(detail.cover, "https://p3.douyinpic.com/cover-a.jpeg");
    assert_eq!(detail.introduction.as_deref(), Some("欢迎来到直播间"));
    assert_eq!(detail.url, "https://live.douyin.com/416144012050");
    assert_eq!(h.request_count("room/web/enter/"), 1, "webRid 只打一次 enter");
    assert_eq!(h.request_count("reflow/info/"), 0, "stream_url 非空时不打 reflow");
}

#[tokio::test]
async fn ac_douyin_detail_data_channel_is_json_string() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("应成功");

    let raw = detail.data.expect("data 通道必须有值");
    let parsed: serde_json::Value = serde_json::from_str(&raw).expect("data 必须是合法 JSON 串");
    assert!(
        parsed.get("live_core_sdk_data").is_some(),
        "data 应是 stream_url 对象，实际 {parsed}"
    );
}

#[tokio::test]
async fn ac_douyin_danmaku_data_is_json_with_snake_case_keys() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("应成功");

    let raw = detail.danmaku_data.expect("danmaku_data 必须有值");
    let args = slive_core::platforms::douyin::danmaku::DouyinDanmakuArgs::from_json(&raw)
        .expect("契约往返必须成立");
    assert_eq!(args.schema_version, 1);
    assert_eq!(args.web_rid, "416144012050");
    assert_eq!(args.room_id, "7382735338101328680");
    assert_eq!(args.user_id.len(), 12, "观众 ID 为 12 位随机数字");
    assert_eq!(args.cookie, h.cookie(), "cookie 来自请求头（含 ttwid）");
}

#[tokio::test]
async fn ac_douyin_detail_by_room_id_uses_reflow_first() {
    let h = harness();
    h.stub_json("reflow/info/", "reflow_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("7382735338101328680".into())
        .await
        .expect("19 位 roomId 应走 reflow/info");

    assert!(detail.status);
    assert_eq!(detail.title, "连麦直播间");
    assert_eq!(detail.room_id, "416144012050", "room_id 优先 webRid");
    assert_eq!(
        h.request_count("reflow/info/"),
        1,
        "19 位 roomId 不应先转 webRid（连麦房间会拿不到 stream_url）"
    );
    assert_eq!(h.request_count("room/web/enter/"), 0, "不应打 enter");
}

#[tokio::test]
async fn ac_douyin_enter_degraded_skeleton_falls_back_to_reflow() {
    let h = harness();
    // enter 返回降级骨架：room 在、status=4、无 stream_url
    h.stub_json_inline(
        "room/web/enter/",
        r#"{"status_code":0,"data":{"data":[{"id_str":"7382735338101328680",
            "title":"降级骨架","status":4,"owner":{"nickname":"主播A","web_rid":"416144012050"}}],
            "user":{"nickname":"用户昵称"}}}"#,
    );
    h.stub_json("reflow/info/", "reflow_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("降级骨架应被 reflow 补救");

    assert!(
        detail.status,
        "整体采信 reflow/info 后应判为在播（Dart 口径）"
    );
    assert_eq!(detail.title, "连麦直播间", "应是 reflow 的标题，不是骨架的");
    assert_eq!(
        h.request_count("reflow/info/"),
        1,
        "补救只应打一次 reflow（Dart 口径）"
    );
}

#[tokio::test]
async fn ac_douyin_enter_failure_falls_back_to_page_html() {
    let h = harness();
    // 页面夹具必须先注册：`stub_ttwid` 的 key 是 `live.douyin.com`（所有抖音端点的
    // 公共前缀），先注册会遮蔽本用例的页面 HTML 夹具（表现为「未能获取房间信息」）。
    h.stub_json_inline(
        "live.douyin.com/416144012050",
        r#"<html><script>{\"state\":{\"appStore\":{\"x\":1},\"roomStore\":{\"roomInfo\":{\"room\":{\"id_str\":\"7382735338101328680\",\"title\":\"页面直播间\",\"status\":2,\"owner\":{\"nickname\":\"主播A\",\"signature\":\"签名\",\"avatar_thumb\":{\"url_list\":[\"https://a\"]}},\"room_view_stats\":{\"display_value\":7},\"stream_url\":{\"hls_pull_url_map\":{}}},\"anchor\":{\"nickname\":\"主播A\",\"avatar_thumb\":{\"url_list\":[\"https://b\"]}}}},\"userStore\":{\"odin\":{\"user_unique_id\":\"1234567890123\"}}}}</script></html>"#,
    );
    stub_ttwid(&h);
    h.stub_http_error("room/web/enter/", 403);

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("enter 403 时应回退页面 HTML");

    assert!(detail.status);
    assert_eq!(detail.title, "页面直播间");
    assert_eq!(detail.online, 7);
    assert_eq!(
        h.request_count("reflow/info/"),
        0,
        "enter 失败时不该再打 reflow（Dart 同口径）"
    );
}

#[tokio::test]
async fn ac_douyin_page_html_offline_uses_anchor_identity() {
    let h = harness();
    h.stub_http_error("room/web/enter/", 403);
    h.stub_json_inline(
        "live.douyin.com/416144012050",
        r#"<html><script>{\"state\":{\"appStore\":{\"x\":1},\"roomStore\":{\"roomInfo\":{\"room\":{\"id_str\":\"7382735338101328680\",\"title\":\"已下播\",\"status\":4,\"owner\":{\"nickname\":\"主播A\"}},\"anchor\":{\"nickname\":\"主播A(离线态)\",\"avatar_thumb\":{\"url_list\":[\"https://b\"]}}}},\"userStore\":{\"odin\":{\"user_unique_id\":\"1234567890123\"}}}}</script></html>"#,
    );

    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("未播页面也应返回详情");

    assert!(!detail.status);
    assert_eq!(
        detail.user_name, "主播A(离线态)",
        "未播时应降级到 roomInfo.anchor.nickname"
    );
    assert_eq!(detail.user_avatar, "https://b");
    assert_eq!(detail.online, 0);
    assert_eq!(detail.cover, "", "未播封面为空");
}

#[tokio::test]
async fn ac_douyin_offline_room_reports_readable_error() {
    let h = harness();
    h.stub_http_error("room/web/enter/", 403);
    // 页面里只有骨架 + 服务端错误提示
    h.stub_json_inline(
        "live.douyin.com/416144012050",
        r#"<html><script>{\"state\":{\"appStore\":{\"x\":1},\"roomStore\":{\"roomInfo\":{\"room\":{}}},\"detailExtra\":{\"errorPrompts\":[\"房间不存在或已下播\"]},\"userStore\":{\"odin\":{\"user_unique_id\":\"1234567890123\"}}}}</script></html>"#,
    );

    let err = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect_err("房间不存在必须报错");

    match err {
        SliveError::Decode(msg) => {
            assert!(msg.contains("房间不存在或已下播"), "应带服务端原文：{msg}");
        }
        other => panic!("期望 Decode，实际 {other:?}"),
    }
}

#[tokio::test]
async fn ac_douyin_network_failure_on_room_id_falls_back_to_web_rid() {
    let h = harness();
    // reflow/info 传输层失败（属「意外」而非「刻意业务错误」）-> 兜底 webRid 链路
    h.stub_network_error("reflow/info/", "连接被重置");
    h.stub_json_inline(
        "douyin/webcast/reflow/",
        r#"{\"mysteryMan\":1,\"webRid\":\"416144012050\",\"desensitizedNickname\":\"x\"}"#,
    );
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);

    let detail = h
        .site
        .get_room_detail("7382735338101328680".into())
        .await
        .expect("传输失败应兜底而不是直接报错");

    assert_eq!(detail.room_id, "416144012050", "走 webRid 链路");
    assert!(detail.status);
}

#[tokio::test]
async fn ac_douyin_qualities_from_stream_data_descending() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);
    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("应成功");

    let qualities = h
        .site
        .get_play_qualities(detail)
        .await
        .expect("清晰度应成功");

    assert_eq!(qualities.len(), 3);
    assert_eq!(qualities[0].quality, "标清", "level 大者排前");
    assert_eq!(qualities[0].sort, 3);
    assert_eq!(qualities[2].quality, "原画");
    assert_eq!(
        qualities[2].data,
        r#"["https://flv-full.flv","https://hls-full.m3u8"]"#,
        "flv 在前（hlsFirst 默认 false）"
    );
}

#[tokio::test]
async fn ac_douyin_qualities_hls_first_swaps_order() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);
    let detail = h
        .site
        .get_room_detail("416144012050".into())
        .await
        .expect("应成功");

    h.site
        .set_site_attrs(r#"{"hlsFirst":true}"#)
        .expect("注入 hlsFirst");
    let qualities = h
        .site
        .get_play_qualities(detail)
        .await
        .expect("清晰度应成功");

    assert_eq!(
        qualities[2].data,
        r#"["https://hls-full.m3u8","https://flv-full.flv"]"#,
        "hlsFirst=true 时 hls 在前"
    );
}

#[tokio::test]
async fn ac_douyin_qualities_from_url_tables_when_no_quality_list() {
    let h = harness();
    stub_ttwid(&h);
    let detail = slive_core::models::LiveRoomDetail {
        room_id: "r".into(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: Some(
            r#"{"flv_pull_url":{"FULL_HD1":"https://f1","HD1":"https://f2"},
                "hls_pull_url_map":{"FULL_HD1":"https://h1","HD1":"https://h2"}}"#
                .to_string(),
        ),
        danmaku_data: None,
        is_record: false,
        url: String::new(),
    };

    let qualities = h.site.get_play_qualities(detail).await.expect("应成功");
    assert_eq!(qualities.len(), 2);
    assert_eq!(qualities[0].quality, "FULL_HD1", "键序在前者档位更高");
    assert_eq!(qualities[0].sort, 2);
    assert_eq!(qualities[0].data, r#"["https://f1","https://h1"]"#);
}

#[tokio::test]
async fn ac_douyin_qualities_from_level_index_when_stream_data_not_json() {
    let h = harness();
    stub_ttwid(&h);
    let detail = slive_core::models::LiveRoomDetail {
        room_id: "r".into(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: Some(
            r#"{"live_core_sdk_data":{"pull_data":{
                "options":{"qualities":[{"name":"原画","level":1},{"name":"高清","level":2}]},
                "stream_data":"not-json"}},
                "flv_pull_url":{"A":"https://f1","B":"https://f2"},
                "hls_pull_url_map":{"A":"https://h1","B":"https://h2"}}"#
                .to_string(),
        ),
        danmaku_data: None,
        is_record: false,
        url: String::new(),
    };

    let qualities = h.site.get_play_qualities(detail).await.expect("应成功");
    assert_eq!(qualities.len(), 2);
    assert_eq!(qualities[0].quality, "高清");
    assert_eq!(qualities[0].data, r#"["https://f1","https://h1"]"#);
    assert_eq!(qualities[1].quality, "原画");
    assert_eq!(qualities[1].data, r#"["https://f2","https://h2"]"#);
}

#[tokio::test]
async fn ac_douyin_qualities_empty_data_returns_empty_list() {
    let h = harness();
    stub_ttwid(&h);
    let mut detail = slive_core::models::LiveRoomDetail {
        room_id: "r".into(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: Some("{}".to_string()),
        danmaku_data: None,
        is_record: false,
        url: String::new(),
    };
    assert_eq!(
        h.site.get_play_qualities(detail.clone()).await.expect("空数据应返回空列表"),
        Vec::new(),
        "下播/降级时 data 是空对象 -> 空列表而非报错"
    );

    detail.data = Some("not-json".to_string());
    assert_eq!(
        h.site.get_play_qualities(detail).await.expect("风控截断应降级"),
        Vec::new()
    );
}

#[tokio::test]
async fn ac_douyin_play_urls_roundtrip_quality_data() {
    let h = harness();
    let quality = slive_core::models::LivePlayQuality {
        quality: "原画".into(),
        data: r#"["https://flv-full.flv","https://hls-full.m3u8"]"#.into(),
        sort: 1,
    };
    let detail = slive_core::models::LiveRoomDetail {
        room_id: "r".into(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: None,
        danmaku_data: None,
        is_record: false,
        url: String::new(),
    };

    let url = h
        .site
        .get_play_urls(detail, quality)
        .await
        .expect("取流应成功");

    assert_eq!(url.urls, vec!["https://flv-full.flv", "https://hls-full.m3u8"]);
    assert!(url.headers.is_none(), "抖音取流不带自定义头（Dart 同口径）");
    assert_eq!(
        h.request_count("live.douyin.com"),
        0,
        "取流是纯本地计算，不得发请求（§9 性能口径）"
    );
}

#[tokio::test]
async fn ac_douyin_play_urls_rejects_malformed_channel() {
    let h = harness();
    stub_ttwid(&h);
    let quality = slive_core::models::LivePlayQuality {
        quality: "原画".into(),
        data: "not-json".into(),
        sort: 1,
    };
    let detail = slive_core::models::LiveRoomDetail {
        room_id: "r".into(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: None,
        danmaku_data: None,
        is_record: false,
        url: String::new(),
    };

    assert!(matches!(
        h.site.get_play_urls(detail, quality).await,
        Err(SliveError::Decode(_))
    ));
}

#[tokio::test]
async fn ac_douyin_live_status_reuses_detail_chain() {
    let h = harness();
    h.stub_json("room/web/enter/", "enter_live");
    stub_ttwid(&h);

    assert!(
        h.site
            .get_live_status("416144012050".into())
            .await
            .expect("状态应成功")
    );
    assert_eq!(
        h.request_count("room/web/enter/"),
        1,
        "getLiveStatus 复用详情链路，不得额外打接口"
    );
}

#[tokio::test]
async fn ac_douyin_super_chat_is_always_empty() {
    let h = harness();
    let sc = h
        .site
        .get_super_chat_messages("416144012050".into())
        .await
        .expect("抖音无 SC，应返回空");
    assert!(sc.is_empty());
    assert_eq!(h.request_count("live.douyin.com"), 0, "不得发请求");
}
