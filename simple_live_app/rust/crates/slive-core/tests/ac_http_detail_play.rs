//! 详情 / 清晰度 / 取流 / 状态 / SC 类 AC（AC-06~AC-10、AC-22、AC-23、AC-29）。

mod common;

use common::{detail, harness, quality, sample, variant_response, Harness};
use slive_core::error::SliveError;
use slive_core::platforms::bilibili::danmaku::args::BiliBiliDanmakuArgs;

const INFO_KEY: &str = "api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom";
const DANMU_KEY: &str = "api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo";

fn stub_detail(h: &Harness, info: &str, danmu: &str) {
    h.stub_wbi_keys();
    h.mock.stub(INFO_KEY, info);
    h.mock.stub(DANMU_KEY, danmu);
}

fn sample_part(key: &str, part: &str) -> String {
    serde_json::to_string(&sample(key)["response"][part]).expect("序列化样本分段")
}

#[tokio::test]
async fn ac06_room_detail_fields_and_danmaku_args() {
    let h = harness();
    stub_detail(
        &h,
        &sample_part("getInfoByRoom_plus_getDanmuInfo", "getInfoByRoom"),
        &sample_part("getInfoByRoom_plus_getDanmuInfo", "getDanmuInfo"),
    );

    let detail = h.site.get_room_detail("545068".into()).await.expect("详情应成功");
    assert_eq!(detail.room_id, "545068", "roomId 应为真实房间号");
    assert_eq!(detail.title, "T");
    assert!(detail.status, "live_status=1 -> status=true");
    assert_eq!(
        detail.user_avatar, "https://i0.hdslb.com/bfs/face/f.jpg@100w.jpg",
        "头像应追加 @100w.jpg"
    );
    assert_eq!(detail.url, "https://live.bilibili.com/545068", "url 用请求房间号");
    assert!(detail.data.is_none(), "B站本轮 data 保持为 None（§3.3(a)）");

    let json = detail.danmaku_data.expect("danmakuData 应存在");
    let args = BiliBiliDanmakuArgs::from_json(&json).expect("danmakuData 应可反序列化");
    assert_eq!(args.schema_version, 1);
    assert_eq!(args.room_id, 545068);
    assert_eq!(args.uid, 0, "未登录 uid 为 0");
    assert_eq!(args.token, "tok");
    assert_eq!(args.server_host, "broadcastlv.chat.bilibili.com");
}

#[tokio::test]
async fn ac22_not_live_returns_detail_and_host_fallback() {
    let h = harness();
    let info = variant_response("getInfoByRoom_plus_getDanmuInfo", 0);
    let info_part = serde_json::to_string(&serde_json::from_str::<serde_json::Value>(&info).unwrap()["getInfoByRoom"]).unwrap();
    let danmu_part = serde_json::to_string(&serde_json::from_str::<serde_json::Value>(&info).unwrap()["getDanmuInfo"]).unwrap();
    stub_detail(&h, &info_part, &danmu_part);

    let detail = h.site.get_room_detail("545068".into()).await.expect("未开播不应抛");
    assert!(!detail.status, "live_status=0 -> status=false");
    let json = detail.danmaku_data.expect("未开播仍应返回弹幕参数");
    let args = BiliBiliDanmakuArgs::from_json(&json).unwrap();
    assert_eq!(
        args.server_host, "broadcastlv.chat.bilibili.com",
        "host_list 空 -> 兜底主机"
    );
}

#[tokio::test]
async fn ac23_room_not_found_typed_error() {
    let h = harness();
    h.stub_wbi_keys();
    h.mock.stub(INFO_KEY, r#"{"code":0,"data":null}"#);

    let err = h.site.get_room_detail("999".into()).await.expect_err("房间不存在应抛错");
    assert!(
        matches!(err, SliveError::NotFound(_)),
        "应为 NotFound 类型化错误，实际 {err:?}"
    );
}

#[tokio::test]
async fn ac07_play_qualities_map_and_unknown() {
    let h = harness();
    h.stub_sample("xlive_web-room_v2_index_getRoomPlayInfo");

    let qualities = h
        .site
        .get_play_qualities(detail("6"))
        .await
        .expect("清晰度应成功");

    let got: Vec<(String, String)> = qualities
        .iter()
        .map(|q| (q.quality.clone(), q.data.clone()))
        .collect();
    assert_eq!(
        got,
        vec![
            ("原画".to_string(), "10000".to_string()),
            ("蓝光".to_string(), "400".to_string()),
            ("未知清晰度".to_string(), "99999".to_string()),
        ],
        "g_qn_desc 映射结果"
    );
}

#[tokio::test]
async fn ac08_play_urls_mcdn_last_and_headers() {
    let h = harness();
    h.stub_sample("xlive_web-room_v2_index_getRoomPlayInfo");

    let play = h
        .site
        .get_play_urls(detail("6"), quality("10000"))
        .await
        .expect("取流应成功");

    assert_eq!(play.urls.len(), 3, "线路条数");
    assert_eq!(
        play.urls[0], "https://cn-hbxy-cu-01.live-play.acgvideo.com/live-bvc/x.flv?a=1",
        "URL = host+base_url+extra"
    );
    assert!(
        play.urls.last().unwrap().contains("mcdn"),
        "含 mcdn 的线路必须排在最后，实际 {:?}",
        play.urls
    );
    let headers = play.headers.expect("headers 应存在");
    assert_eq!(
        headers.get("referer").map(String::as_str),
        Some("https://live.bilibili.com"),
        "固定 referer"
    );
    assert!(
        headers.get("user-agent").map(|u| u.contains("Edg/115.0.1901.188")).unwrap_or(false),
        "固定 user-agent，实际 {:?}",
        headers.get("user-agent")
    );
}

#[tokio::test]
async fn ac29_unknown_quality_no_throw() {
    let h = harness();
    // accept_qn 为空 -> 空列表
    h.mock.stub(
        "api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
        r#"{"code":0,"data":{"playurl_info":{"playurl":{"g_qn_desc":[],"stream":[]}}}}"#,
    );
    let qualities = h.site.get_play_qualities(detail("6")).await.expect("空 accept_qn 不应抛");
    assert!(qualities.is_empty(), "空 accept_qn -> 空列表");
}

#[tokio::test]
async fn ac09_live_status_bool() {
    let h = harness();
    h.stub_sample("room_v1_Room_get_info");
    assert!(h.site.get_live_status("6".into()).await.expect("状态应成功"), "live_status=1 -> true");

    let h2 = harness();
    h2.mock.stub(
        "api.live.bilibili.com/room/v1/Room/get_info",
        &variant_response("room_v1_Room_get_info", 0),
    );
    assert!(!h2.site.get_live_status("6".into()).await.expect("状态应成功"), "live_status=0 -> false");

    let h3 = harness();
    h3.mock
        .stub("api.live.bilibili.com/room/v1/Room/get_info", r#"{"code":0}"#);
    assert!(!h3.site.get_live_status("6".into()).await.expect("缺 data 不应抛"), "缺 data -> false");
}

#[tokio::test]
async fn ac10_super_chat_time_ms_and_face() {
    let h = harness();
    h.stub_sample("av_v1_SuperChat_getMessageList");

    let list = h.site.get_super_chat_messages("6".into()).await.expect("SC 应成功");
    assert_eq!(list.len(), 1);
    let sc = &list[0];
    assert_eq!(sc.user_name, "u");
    assert_eq!(sc.message, "sc");
    assert_eq!(sc.price, 30);
    assert_eq!(
        sc.face, "https://i0.hdslb.com/bfs/face/x.jpg@200w.jpg",
        "face 应追加 @200w.jpg"
    );
    assert_eq!(sc.start_time.timestamp_millis(), 1_700_000_000_000, "秒 -> 毫秒");
    assert_eq!(sc.end_time.timestamp_millis(), 1_700_000_060_000);
    assert_eq!(sc.background_color, "#EDF5FF");
    assert_eq!(sc.background_bottom_color, "#2A60B2");
}

#[tokio::test]
async fn ac25_risk_control_error_no_retry() {
    let h = harness();
    let list_key = common::endpoint_key(
        sample("room_v1_Area_getList")["endpoint"].as_str().unwrap(),
    );
    h.mock.stub(&list_key, r#"{"code":-352,"message":"风控校验失败"}"#);

    let err = h.site.get_categories().await.expect_err("风控码必须抛错，不得静默空列表");
    match err {
        SliveError::Api { code, message } => {
            assert_eq!(code, -352, "错误码应为服务端 code，实际 {code}");
            assert_eq!(message, "风控校验失败", "应带服务端 message");
        }
        other => panic!("期望 SliveError::Api，实际 {other:?}"),
    }
    assert_eq!(
        h.mock.request_count(&list_key),
        1,
        "风控错误不得自动重试（请求次数应 == 1）"
    );
}

#[tokio::test]
async fn ac26_http_failure_maps_to_typed_error() {
    let h = harness();
    h.mock
        .stub_http_error("api.live.bilibili.com/room/v1/Room/get_info", 503);
    let err = h.site.get_live_status("6".into()).await.expect_err("HTTP 失败应抛错");
    match err {
        SliveError::Http { status, .. } => assert_eq!(status, 503, "状态码应透传"),
        other => panic!("期望 SliveError::Http，实际 {other:?}"),
    }
}

#[tokio::test]
async fn ac21_header_injects_buvid_and_wbi_golden() {
    let h = harness();
    h.stub_buvid();
    h.stub_sample("room_v1_Area_getList");
    // 触发一次请求以捕获请求头
    let _ = h.site.get_categories().await.expect("分类应成功");

    let request = h
        .mock
        .requests()
        .into_iter()
        .find(|r| r.url.contains("room/v1/Area/getList"))
        .expect("应捕获分类请求");
    let cookie = request
        .headers
        .iter()
        .find(|(k, _)| k == "cookie")
        .map(|(_, v)| v.clone())
        .expect("请求头应含 cookie");
    assert!(
        cookie.contains("buvid3=BUV3") && cookie.contains("buvid4=BUV4"),
        "无 cookie 时须注入 buvid3/buvid4，实际 {cookie}"
    );

    // wbi 签名确定性 golden（AC-21）
    let mixin = slive_core::wbi::get_mixin_key(
        "7cd084941338484aae1ad9425b84077c4932caff0ff746eab6f01bf08b70ac45",
    );
    assert_eq!(mixin, "ea1db124af3c7062474693fa704f4ff8", "mixin_key golden");
    let params = vec![
        ("room_id".to_string(), "6".to_string()),
        ("wts".to_string(), "1700000000".to_string()),
    ];
    assert_eq!(
        slive_core::wbi::get_wbi_sign(&params, &mixin),
        "46e0afca2af785f6dbdc24935d856d79",
        "w_rid golden"
    );
}

#[tokio::test]
async fn ac21_cookie_without_buvid3_is_appended() {
    let h = harness();
    h.stub_buvid();
    h.stub_sample("room_v1_Area_getList");
    h.site
        .set_site_attrs(r#"{"cookie":"SESSDATA=keepme"}"#)
        .expect("注入 cookie");
    let _ = h.site.get_categories().await.expect("分类应成功");

    let request = h
        .mock
        .requests()
        .into_iter()
        .find(|r| r.url.contains("room/v1/Area/getList"))
        .expect("应捕获请求");
    let cookie = request
        .headers
        .iter()
        .find(|(k, _)| k == "cookie")
        .map(|(_, v)| v.clone())
        .unwrap();
    assert!(cookie.contains("SESSDATA=keepme"), "应保留原 cookie");
    assert!(
        cookie.contains("buvid3=BUV3"),
        "有 cookie 但缺 buvid3 时应追加，实际 {cookie}"
    );
}
