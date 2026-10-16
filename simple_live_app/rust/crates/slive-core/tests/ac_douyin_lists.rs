//! 抖音分类 / 房间列表 AC（分类、分类下房间、推荐首屏与续接）。
//!
//! 覆盖：成功流 + 错误流 + 请求数口径（§9「不得引入额外串行往返」）。

mod douyin_common;

use douyin_common::{harness, read_text};
use slive_core::models::LiveSubCategory;

/// 一级分类（含自身 + 2 个子分类）。
fn culture_category() -> LiveSubCategory {
    LiveSubCategory {
        name: "文化".into(),
        pic: Some(String::new()),
        id: "106,4".into(),
        parent_id: "106,4".into(),
    }
}

#[tokio::test]
async fn ac_douyin_categories_from_home_render_data() {
    let h = harness();
    h.stub_home_html("home_categories");

    let categories = h.site.get_categories().await.expect("分类应成功");

    assert_eq!(categories.len(), 2, "一级分类条数");
    assert_eq!(categories[0].id, "106,4");
    assert_eq!(categories[0].name, "文化");
    assert_eq!(
        categories[0].children.len(),
        3,
        "children[0] 是自身（Dart subs.insert(0,...)），另有 2 个子分类"
    );
    assert_eq!(categories[0].children[0].id, "106,4");
    assert_eq!(categories[0].children[0].name, "文化");
    assert_eq!(categories[0].children[1].id, "1061,4");
    assert_eq!(categories[0].children[1].parent_id, "106,4");
    assert_eq!(categories[1].id, "103,4");
    assert_eq!(categories[1].children.len(), 1, "无子分类时仍只有自身");
}

#[tokio::test]
async fn ac_douyin_categories_absorbs_ttwid_cookie() {
    let h = harness();
    h.stub_home_html("home_categories");

    h.site.get_categories().await.expect("分类应成功");

    assert!(
        h.cookie().contains(douyin_common::TTWID_VALUE),
        "首页请求应把 ttwid 吸收进 cookie，实际 {}",
        h.cookie()
    );
}

#[tokio::test]
async fn ac_douyin_categories_missing_render_data_is_decode_error() {
    let h = harness();
    h.stub_text_inline("live.douyin.com", "<html>无内嵌数据</html>");

    let err = h
        .site
        .get_categories()
        .await
        .expect_err("页面结构变更必须报错而不是返回空分类页");
    assert!(
        matches!(err, slive_core::error::SliveError::Decode(_)),
        "实际 {err:?}"
    );
}

#[tokio::test]
async fn ac_douyin_category_rooms_has_more_and_skips_dirty() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_category_rooms(culture_category(), 1, None)
        .await
        .expect("分类下房间应成功");

    assert!(
        !result.has_more,
        "raw_count(3) < count(15) -> has_more 应为 false，实际 {}",
        result.has_more
    );
    assert_eq!(result.items.len(), 2, "缺 web_rid 的脏条目应被跳过");
    assert_eq!(result.items[0].room_id, "416144012050");
    assert_eq!(result.items[0].title, "音乐直播间");
    assert_eq!(result.items[0].cover, "https://p3.douyinpic.com/cover-a.jpeg");
    assert_eq!(result.items[0].user_name, "主播A");
    assert_eq!(result.items[0].online, 12345);
}

#[tokio::test]
async fn ac_douyin_category_rooms_signs_url_with_a_bogus() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    h.stub_home_html("home_categories");

    h.site
        .get_category_rooms(culture_category(), 1, None)
        .await
        .expect("应成功");

    let urls = h.request_urls();
    let signed = urls
        .iter()
        .find(|u| u.contains("partition/detail/room/v2"))
        .expect("应请求过分区接口");
    assert!(signed.contains("a_bogus="), "分区 URL 必须带签名：{signed}");
    assert!(signed.contains("partition=106"), "分区 id 须在 query 里");
    assert!(signed.contains("partition_type=4"));
    assert!(signed.contains("offset=0"), "第 1 页 offset=0");
    assert!(signed.contains("count=15"), "count 固定 15");
    assert!(signed.contains("msToken="), "缺失时须补 msToken");
}

#[tokio::test]
async fn ac_douyin_category_rooms_page_two_shifts_offset() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    h.stub_home_html("home_categories");

    h.site
        .get_category_rooms(culture_category(), 2, None)
        .await
        .expect("应成功");

    let urls = h.request_urls();
    let signed = urls
        .iter()
        .find(|u| u.contains("partition/detail/room/v2"))
        .expect("应请求过分区接口");
    assert!(signed.contains("offset=15"), "第 2 页 offset=(2-1)*15：{signed}");
}

#[tokio::test]
async fn ac_douyin_category_rooms_empty_page_degrades_to_has_more_false() {
    let h = harness();
    h.stub_json_inline("partition/detail/room/v2", r#"{"status_code":0,"data":{"data":[]}}"#);
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_category_rooms(culture_category(), 9, None)
        .await
        .expect("翻到底应返回空页而不是报错");

    assert!(!result.has_more, "空页 -> has_more=false");
    assert!(result.items.is_empty());
}

#[tokio::test]
async fn ac_douyin_recommend_feed_fans_out_and_dedupes() {
    let h = harness();
    h.stub_json("webcast/feed/", "feed_slice");
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_recommend_rooms(1, None)
        .await
        .expect("推荐首屏应成功");

    assert!(result.has_more, "首屏恒有更多（Dart 口径）");
    assert_eq!(result.items.len(), 1, "多路切片去重后只剩 1 条");
    assert_eq!(result.items[0].room_id, "416144012050");
    assert_eq!(result.items[0].user_name, "主播A");
    assert_eq!(result.items[0].online, 3210);

    let feed_calls = h.request_count("webcast/feed/");
    assert_eq!(
        feed_calls, 4,
        "page_size=None -> 下限 4 路并发扇出（Dart kMinFeedFanout）"
    );
}

#[tokio::test]
async fn ac_douyin_recommend_feed_partial_failure_tolerated() {
    let h = harness();
    // feed 夹具必须先注册：`stub_home_html` 的 key 是 `live.douyin.com`（所有抖音端点的
    // 公共前缀），先注册会遮蔽 feed 夹具（表现为 Decode 错误）。
    h.stub_json("webcast/feed/", "feed_slice");
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_recommend_rooms(1, Some(200))
        .await
        .expect("pageSize=200 应被夹到 6 路上限而非报错");
    assert!(!result.items.is_empty());
    assert_eq!(h.request_count("webcast/feed/"), 6, "上限 6 路");
}

#[tokio::test]
async fn ac_douyin_recommend_all_slices_failing_raises() {
    let h = harness();
    h.stub_network_error("webcast/feed/", "连接被重置");
    h.stub_home_html("home_categories");

    let err = h
        .site
        .get_recommend_rooms(1, None)
        .await
        .expect_err("全部切片失败必须上抛");
    assert!(
        matches!(err, slive_core::error::SliveError::Network(_)),
        "实际 {err:?}"
    );
}

#[tokio::test]
async fn ac_douyin_recommend_continuation_uses_partition_and_advances_slot() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_recommend_rooms(2, None)
        .await
        .expect("第 2 页应走分区接口");

    assert!(result.has_more, "分区未耗尽 -> has_more=true");
    assert_eq!(result.items.len(), 2);
    assert_eq!(
        h.request_count("webcast/feed/"),
        0,
        "第 2 页起不得再打推荐流（Dart 口径）"
    );
    assert_eq!(
        h.request_count("partition/detail/room/v2"),
        1,
        "首个非空 slot 即返回，不多打"
    );
}

#[tokio::test]
async fn ac_douyin_recommend_continuation_all_partitions_empty_means_end() {
    let h = harness();
    h.stub_json_inline("partition/detail/room/v2", r#"{"status_code":0,"data":{"data":[]}}"#);
    h.stub_home_html("home_categories");

    let result = h
        .site
        .get_recommend_rooms(3, None)
        .await
        .expect("全部分区空 -> 空列表而非报错");

    assert!(!result.has_more, "一圈分区全空 -> 到底");
    assert!(result.items.is_empty());
    assert_eq!(
        h.request_count("partition/detail/room/v2"),
        7,
        "应顺延扫完 7 个分区才判定到底"
    );
}

#[tokio::test]
async fn ac_douyin_recommend_page_refresh_resets_slot_cursor() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    // feed 夹具要在首页兜底**之前**注册（见 partial_failure 用例的同序注释）
    h.stub_json("webcast/feed/", "feed_slice");
    h.stub_home_html("home_categories");

    h.site.get_recommend_rooms(2, None).await.expect("第 2 页");
    assert_eq!(h.site.last_served_slot(), 0, "第 2 页命中 slot 0");

    h.site.get_recommend_rooms(1, None).await.expect("刷新");
    assert_eq!(
        h.site.last_served_slot(),
        -1,
        "刷新必须把续接游标归零（Dart _lastServedSlot = -1）"
    );
}

#[tokio::test]
async fn ac_douyin_recommend_page_two_and_three_use_different_offsets() {
    let h = harness();
    h.stub_json("partition/detail/room/v2", "partition_page");
    h.stub_home_html("home_categories");

    h.site.get_recommend_rooms(2, None).await.expect("第 2 页");
    h.site.get_recommend_rooms(3, None).await.expect("第 3 页");

    // 收集 (分区, offset) 对：Dart 的 slot->offset 映射是 `(slot ~/ slots) * 15`，
    // 前 7 个 slot 的 offset 全是 0（靠**轮转分区**区分），第 8 个才开始翻 offset。
    // 所以判据必须是「(分区, offset) 二元组不重复」，单看 offset 会误判。
    let pairs: Vec<(String, String)> = h
        .request_urls()
        .into_iter()
        .filter(|u| u.contains("partition/detail/room/v2"))
        .map(|u| {
            let q = slive_core::util::parse_query(&u);
            let get = |k: &str| {
                q.iter()
                    .find(|(qk, _)| qk == k)
                    .map(|(_, v)| v.clone())
                    .unwrap_or_default()
            };
            (get("partition"), get("offset"))
        })
        .collect();
    assert_eq!(pairs.len(), 2, "两页各打一次分区接口");
    assert_ne!(
        pairs[0], pairs[1],
        "相邻页不得命中同一 (分区, offset)，否则 App 判「连续 2 页零新增」会提前收尾，实际 {pairs:?}"
    );
}

#[tokio::test]
async fn ac_douyin_fixture_home_html_matches_parser_contract() {
    // 夹具自身的形态守卫：若有人改动夹具转义方式，用例会先在这里失败
    let html = read_text("http/home_categories.html");
    assert!(
        html.contains(r#"{\"pathname\":\"\/\",\"categoryData"#),
        "夹具必须保持 RENDER_DATA 的转义形态，否则分类解析用例失去意义"
    );
}
