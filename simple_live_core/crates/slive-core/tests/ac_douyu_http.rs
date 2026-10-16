//! IP-3 斗鱼 HTTP 读链路：分类 / 分类下房间 / 推荐 / 详情 / 状态（QA 夹具驱动）。
//!
//! 夹具：`tests/fixtures/douyu/http/http-samples.json`（QA 合成样本，`_meta.synthetic=true`）。
//! 本文件是「实现 vs 夹具」的分离点（AC-35 反作弊：实现与测试 diff 分离）。

mod douyu_common;

use douyu_common::{endpoint_key, expected, harness, sample, variant_response};
use slive_core::error::SliveError;
use slive_core::models::LiveSubCategory;

#[tokio::test]
async fn categories_match_fixture_tree() {
    let h = harness();
    h.stub_sample("m_douyu_com_api_cate_list");

    let categories = h.site.get_categories().await.expect("分类应成功");
    let want = &expected("m_douyu_com_api_cate_list")["categories"];
    assert_eq!(categories.len(), want.as_array().expect("categories 数组").len());
    assert_eq!(categories.len(), 2, "两条一级分类");

    assert_eq!(categories[0].id, want[0]["id"].as_str().unwrap());
    assert_eq!(categories[0].name, want[0]["name"].as_str().unwrap());
    assert_eq!(categories[0].children.len(), 2);
    assert_eq!(
        categories[0].children[0].id,
        want[0]["children"][0]["id"].as_str().unwrap()
    );
    assert_eq!(
        categories[0].children[1].name,
        want[0]["children"][1]["name"].as_str().unwrap()
    );
    assert_eq!(categories[1].id, "9");
    assert_eq!(
        categories[1].children[0].parent_id, "9",
        "二级分类的 parent_id 必须是所属一级分类"
    );
    assert_eq!(
        categories[1].children[0].pic.as_deref(),
        Some(want[1]["children"][0]["pic"].as_str().unwrap())
    );
}

#[tokio::test]
async fn categories_are_sorted_by_id_not_server_order() {
    let h = harness();
    // 变体 0：服务端返回乱序（9 在 1 前面）
    let key = endpoint_key(sample("m_douyu_com_api_cate_list")["endpoint"].as_str().unwrap());
    h.get.stub(&key, &variant_response("m_douyu_com_api_cate_list", 0));

    let categories = h.site.get_categories().await.expect("乱序不应抛");
    let ids: Vec<&str> = categories.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(
        ids,
        vec!["1", "9"],
        "必须按 cate1Id 数值升序（Dart:53），不能沿用服务端顺序"
    );
}

#[tokio::test]
async fn empty_categories_do_not_throw() {
    let h = harness();
    let key = endpoint_key(sample("m_douyu_com_api_cate_list")["endpoint"].as_str().unwrap());
    h.get.stub(&key, &variant_response("m_douyu_com_api_cate_list", 1));

    let categories = h.site.get_categories().await.expect("空分类不应抛");
    assert!(categories.is_empty(), "空 cate1Info -> 空列表");
}

#[tokio::test]
async fn category_rooms_use_pgcnt_and_filter_ads() {
    let h = harness();
    h.stub_sample("www_douyu_com_gapi_rkc_directory_mixList");

    let result = h
        .site
        .get_category_rooms(category(), 1, None)
        .await
        .expect("分类房间应成功");
    let want = &expected("www_douyu_com_gapi_rkc_directory_mixList");
    assert_eq!(result.has_more, want["has_more"].as_bool().unwrap());
    assert_eq!(result.items.len(), want["items"].as_array().unwrap().len());
    assert_eq!(result.items[0].room_id, "252140");
    assert_eq!(result.items[0].online, 12345);
    assert_eq!(
        result.items[0].cover,
        "https://example.douyu.com/cover/252140.jpg"
    );
    assert!(
        h.get
            .request_urls()
            .iter()
            .any(|u| u.contains("/mixList/2_1001/1")),
        "URL 路径必须带 cate2Id 与页码，实际 {:?}",
        h.get.request_urls()
    );
}

#[tokio::test]
async fn category_rooms_filter_ad_slots() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_gapi_rkc_directory_mixList")["endpoint"].as_str().unwrap());
    h.get.stub(&key, &variant_response("www_douyu_com_gapi_rkc_directory_mixList", 0));

    let result = h
        .site
        .get_category_rooms(category(), 1, None)
        .await
        .expect("含广告位不应抛");
    assert_eq!(
        result.items.len(),
        1,
        "type!=1 的广告位必须过滤（Dart:70-72）"
    );
    assert!(
        result.has_more,
        "过滤广告位不得影响 hasMore 判定"
    );
}

#[tokio::test]
async fn category_rooms_last_page_reports_no_more() {
    let h = harness();
    let key = endpoint_key(
        sample("www_douyu_com_gapi_rkc_directory_mixList")["endpoint"].as_str().unwrap(),
    );
    h.get
        .stub(&key, &variant_response("www_douyu_com_gapi_rkc_directory_mixList", 2));
    // 夹具变体 2 的 pgcnt=3
    let pgcnt = sample("www_douyu_com_gapi_rkc_directory_mixList")["variants"][2]["response"]
        ["data"]["pgcnt"]
        .as_i64()
        .expect("pgcnt");

    let last = h
        .site
        .get_category_rooms(category(), pgcnt as i32, None)
        .await
        .expect("末页不应抛");
    assert!(
        !last.has_more,
        "分类流的 pgcnt 有效：page == pgcnt({pgcnt}) -> hasMore=false"
    );
    assert_eq!(last.items.len(), 1);

    let before = h
        .site
        .get_category_rooms(category(), pgcnt as i32 - 1, None)
        .await
        .expect("非末页不应抛");
    assert!(
        before.has_more,
        "page < pgcnt -> 仍有更多（与推荐流的「非空即有更多」口径不同）"
    );
}

#[tokio::test]
async fn recommend_uses_non_empty_page_not_pgcnt() {
    let h = harness();
    h.stub_sample("www_douyu_com_japi_weblist_apinc_allpage");

    let result = h
        .site
        .get_recommend_rooms(1, None)
        .await
        .expect("推荐应成功");
    assert!(
        result.has_more,
        "推荐流 pgcnt 恒 0，但本页非空 -> hasMore=true（Dart:214）"
    );
    assert_eq!(result.items[0].room_id, "252140");
    assert_eq!(result.items.len(), 1);
    assert!(
        h.get
            .request_urls()
            .iter()
            .any(|u| u.contains("/allpage/6/1")),
        "URL 路径必须带固定分区 6 与页码"
    );
}

#[tokio::test]
async fn recommend_empty_page_stops_paging() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_weblist_apinc_allpage")["endpoint"].as_str().unwrap());
    for (index, expect_empty) in [(0usize, true), (1, true), (2, true)] {
        h.get
            .stub(&key, &variant_response("www_douyu_com_japi_weblist_apinc_allpage", index));
        let result = h
            .site
            .get_recommend_rooms(9, None)
            .await
            .expect("空页不应抛");
        assert_eq!(result.items.is_empty(), expect_empty, "变体 {index}");
        assert!(
            !result.has_more,
            "变体 {index}: 空页必须停止加载（这是推荐流唯一的停止条件）"
        );
    }
}

#[tokio::test]
async fn room_detail_matches_fixture() {
    let h = harness();
    h.stub_sample("www_douyu_com_betard");

    let detail = h
        .site
        .get_room_detail("252140".to_string())
        .await
        .expect("详情应成功");
    let want = expected("www_douyu_com_betard");

    assert_eq!(detail.room_id, want["room_id"].as_str().unwrap());
    assert_eq!(detail.title, want["title"].as_str().unwrap());
    assert_eq!(detail.cover, want["cover"].as_str().unwrap());
    assert_eq!(detail.user_name, want["user_name"].as_str().unwrap());
    assert_eq!(detail.user_avatar, want["user_avatar"].as_str().unwrap());
    assert_eq!(
        detail.introduction.as_deref(),
        want["introduction"].as_str()
    );
    assert_eq!(detail.notice.as_deref(), want["notice"].as_str());
    assert_eq!(detail.status, want["status"].as_bool().unwrap());
    assert_eq!(detail.is_record, want["is_record"].as_bool().unwrap());
    assert_eq!(detail.url, want["url"].as_str().unwrap());
    assert_eq!(
        detail.danmaku_data.as_deref(),
        want["danmaku_data"].as_str(),
        "斗鱼弹幕参数就是房间号"
    );
    assert_eq!(detail.data.as_deref(), want["data"].as_str());
    // ⚠️ 夹具主样本写 online=123000，但其自身 note 与变体 3 明确要求「12.3万」按
    // Dart `int.tryParse` 失败 -> 0。**以 Dart 行为为准**（详见回传清单的夹具不一致项）。
    assert_eq!(
        detail.online, 0,
        "hot='12.3万' 不是合法整数字面量，Dart int.tryParse 失败回落 0（不得顺手'修好'）"
    );
}

#[tokio::test]
async fn room_detail_status_variants() {
    // 变体 0 未开播 / 1 回放 / 2【回放】前缀 / 3 hot 非数字 / 4 hot 纯数字
    let cases: [(usize, bool, bool); 5] = [
        (0, false, false),
        (1, false, true),
        (2, false, false),
        (3, true, false),
        (4, true, false),
    ];
    for (index, status, is_record) in cases {
        let h = harness();
        let key = endpoint_key(sample("www_douyu_com_betard")["endpoint"].as_str().unwrap());
        h.get.stub(&key, &variant_response("www_douyu_com_betard", index));

        let detail = h
            .site
            .get_room_detail("252140".to_string())
            .await
            .unwrap_or_else(|e| panic!("变体 {index} 不应抛: {e}"));
        assert_eq!(detail.status, status, "变体 {index} 的 status");
        assert_eq!(detail.is_record, is_record, "变体 {index} 的 is_record");
        assert_eq!(
            detail.danmaku_data.as_deref(),
            Some("252140"),
            "变体 {index}: 未开播也要给出可用弹幕参数"
        );
    }
}

#[tokio::test]
async fn room_detail_parses_numeric_hot() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_betard")["endpoint"].as_str().unwrap());
    h.get.stub(&key, &variant_response("www_douyu_com_betard", 4));

    let detail = h
        .site
        .get_room_detail("252140".to_string())
        .await
        .expect("纯数字 hot 应成功");
    assert_eq!(
        detail.online, 12345,
        "hot 为纯数字串时正常解析（变体 4）"
    );
}

#[tokio::test]
async fn live_status_shares_detail_predicate() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_betard")["endpoint"].as_str().unwrap());
    h.get.stub(&key, &variant_response("www_douyu_com_betard", 1));
    assert!(
        !h.site
            .get_live_status("252140".to_string())
            .await
            .expect("状态应成功"),
        "videoLoop=1（回放）-> 不在播"
    );

    let h2 = harness();
    h2.stub_sample("www_douyu_com_betard");
    assert!(
        h2.site
            .get_live_status("252140".to_string())
            .await
            .expect("状态应成功"),
        "正常样本 -> 在播"
    );
}

#[tokio::test]
async fn missing_room_key_is_typed_decode_error() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_betard")["endpoint"].as_str().unwrap());
    h.get.stub(&key, r#"{"error":0}"#);

    let err = h
        .site
        .get_room_detail("252140".to_string())
        .await
        .expect_err("缺 room 必须抛类型化错误而非 panic");
    assert!(
        matches!(err, SliveError::Decode(_)),
        "实际 {err:?}"
    );
}

#[tokio::test]
async fn business_error_on_recommend_is_api_error_without_retry() {
    let h = harness();
    let key = endpoint_key(sample("www_douyu_com_japi_weblist_apinc_allpage")["endpoint"].as_str().unwrap());
    h.get.stub(&key, r#"{"error":-101,"msg":"需要验证"}"#);

    let err = h
        .site
        .get_recommend_rooms(1, None)
        .await
        .expect_err("error!=0 必须抛错");
    match err {
        SliveError::Api { code, message } => {
            assert_eq!(code, -101);
            assert_eq!(message, "需要验证");
        }
        other => panic!("期望 SliveError::Api，实际 {other:?}"),
    }
    assert_eq!(
        h.get.request_count("allpage"),
        1,
        "业务错误不得自动重试"
    );
}

fn category() -> LiveSubCategory {
    LiveSubCategory {
        id: "1001".into(),
        name: "英雄联盟".into(),
        parent_id: "1".into(),
        pic: None,
    }
}