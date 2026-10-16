//! 列表 / 搜索类 AC（AC-01~AC-05、AC-27）。

mod common;

use common::{harness, sample, sample_response, variant_response};
use slive_core::models::LiveSubCategory;

#[tokio::test]
async fn ac01_get_categories_and_pic_suffix() {
    let h = harness();
    h.stub_sample("room_v1_Area_getList");

    let categories = h.site.get_categories().await.expect("分类接口应成功");

    assert_eq!(categories.len(), 1, "分类条数，实际 {}", categories.len());
    assert_eq!(categories[0].id, "1");
    assert_eq!(categories[0].name, "娱乐");
    assert_eq!(categories[0].children.len(), 1);
    let sub = &categories[0].children[0];
    assert_eq!(sub.id, "101");
    assert_eq!(sub.parent_id, "1");
    assert_eq!(
        sub.pic.as_deref(),
        Some("https://i0.hdslb.com/bfs/activity-plat/a.png@100w.png"),
        "子类 pic 必须以 @100w.png 结尾，实际 {:?}",
        sub.pic
    );
}

#[tokio::test]
async fn ac02_category_rooms_has_more_and_cover() {
    let h = harness();
    h.stub_wbi_keys();
    h.stub_access_id();
    h.stub_sample("xlive_web-interface_v1_second_getList");

    let category = LiveSubCategory {
        name: "视频唱见".into(),
        pic: None,
        id: "101".into(),
        parent_id: "1".into(),
    };
    let result = h
        .site
        .get_category_rooms(category, 1, None)
        .await
        .expect("分类下房间应成功");

    assert!(result.has_more, "has_more==1 应为 true，实际 {}", result.has_more);
    assert_eq!(result.items.len(), 1);
    assert_eq!(result.items[0].room_id, "6");
    assert_eq!(
        result.items[0].cover, "https://i0.hdslb.com/bfs/cover/x.jpg@400w.jpg",
        "cover 必须以 @400w.jpg 结尾"
    );
    assert_eq!(result.items[0].online, 123);
}

#[tokio::test]
async fn ac02_category_rooms_empty_page() {
    let h = harness();
    h.stub_wbi_keys();
    h.stub_access_id();
    let endpoint = common::endpoint_key(
        sample("xlive_web-interface_v1_second_getList")["endpoint"]
            .as_str()
            .unwrap(),
    );
    h.mock.stub(&endpoint, &variant_response("xlive_web-interface_v1_second_getList", 0));

    let category = LiveSubCategory {
        name: "x".into(),
        pic: None,
        id: "1".into(),
        parent_id: "0".into(),
    };
    let result = h.site.get_category_rooms(category, 1, None).await.expect("空页不应抛");
    assert!(result.items.is_empty(), "空页应返回空 items");
    assert!(!result.has_more, "空页 has_more 应为 false");
}

#[tokio::test]
async fn ac03_recommend_has_more_from_nonempty_page() {
    let h = harness();
    h.stub_wbi_keys();
    h.stub_sample("xlive_web-interface_v1_second_getListByArea");

    let result = h.site.get_recommend_rooms(1, Some(30)).await.expect("推荐应成功");
    assert!(result.has_more, "list 非空 -> hasMore=true，实际 {}", result.has_more);
    assert_eq!(result.items.len(), 1, "items 条数");
    assert_eq!(
        result.items[0].cover, "https://i0.hdslb.com/bfs/cover/y.jpg@400w.jpg",
        "cover 后缀"
    );
}

#[tokio::test]
async fn ac03_recommend_empty_page() {
    let h = harness();
    h.stub_wbi_keys();
    let endpoint = common::endpoint_key(
        sample("xlive_web-interface_v1_second_getListByArea")["endpoint"]
            .as_str()
            .unwrap(),
    );
    h.mock.stub(
        &endpoint,
        &variant_response("xlive_web-interface_v1_second_getListByArea", 0),
    );

    let result = h.site.get_recommend_rooms(1, None).await.expect("空页不应抛");
    assert!(!result.has_more, "空 list -> hasMore=false");
    assert!(result.items.is_empty());
}

#[tokio::test]
async fn ac04_search_rooms_strip_em_prefix_cover() {
    let h = harness();
    h.stub_sample("www.bilibili.com_x_web-interface_search_type_live");

    let result = h.site.search_rooms("LOL".into(), 1).await.expect("搜索应成功");
    assert_eq!(result.items.len(), 1);
    assert_eq!(result.items[0].title, "LOL直播", "标题应去除 <em> 标签");
    assert_eq!(
        result.items[0].cover, "https://i0.hdslb.com/bfs/live/cover.jpg@400w.jpg",
        "相对协议封面应补 https: 并追加 @400w.jpg"
    );
    // 1 条 < 40 -> hasMore=false
    assert!(!result.has_more, "items<40 -> hasMore=false");
}

#[tokio::test]
async fn ac04_search_rooms_full_page_has_more() {
    let h = harness();
    let mut response = serde_json::from_str::<serde_json::Value>(&sample_response(
        "www.bilibili.com_x_web-interface_search_type_live",
    ))
    .unwrap();
    let item = response["data"]["result"]["live_room"][0].clone();
    let rooms: Vec<serde_json::Value> = (0..40).map(|_| item.clone()).collect();
    response["data"]["result"]["live_room"] = serde_json::Value::Array(rooms);
    h.mock.stub(
        "api.bilibili.com/x/web-interface/search/type",
        &serde_json::to_string(&response).unwrap(),
    );

    let result = h.site.search_rooms("LOL".into(), 1).await.expect("搜索应成功");
    assert_eq!(result.items.len(), 40);
    assert!(result.has_more, "items>=40 -> hasMore=true");
}

#[tokio::test]
async fn ac05_search_anchors_avatar_and_uname() {
    let h = harness();
    h.stub_sample("www.bilibili.com_x_web-interface_search_type_live_user");

    let result = h.site.search_anchors("联盟".into(), 1).await.expect("搜索主播应成功");
    assert_eq!(result.items.len(), 1);
    assert_eq!(result.items[0].user_name, "联盟主播", "uname 应去 <em>");
    assert_eq!(
        result.items[0].avatar, "https://i0.hdslb.com/bfs/face/a.jpg@400w.jpg",
        "avatar 应补 https: 并追加 @400w.jpg"
    );
    assert!(result.items[0].live_status, "is_live=true 应透传");
}

#[tokio::test]
async fn ac05_search_anchors_normalizes_int_is_live() {
    // G-4：服务端可能返 int 的 is_live，必须显式归一化（不照抄 Dart 裸赋 bool）。
    let h = harness();
    let body = r#"{"code":0,"data":{"result":[{"roomid":7,"uname":"a","uface":"//x/a.jpg","is_live":1},{"roomid":8,"uname":"b","uface":"//x/b.jpg","is_live":0}]}}"#;
    h.mock.stub("api.bilibili.com/x/web-interface/search/type", body);

    let result = h.site.search_anchors("a".into(), 1).await.expect("应成功");
    assert_eq!(result.items.len(), 2);
    assert!(result.items[0].live_status, "is_live=1 应归一化为 true");
    assert!(!result.items[1].live_status, "is_live=0 应归一化为 false");
}

#[tokio::test]
async fn ac27_empty_pages_return_empty_without_throw() {
    let h = harness();
    // 分类：data 缺失 -> 空列表
    h.mock.stub("api.live.bilibili.com/room/v1/Area/getList", r#"{"code":0}"#);
    let categories = h.site.get_categories().await.expect("缺 data 不应抛");
    assert!(categories.is_empty(), "缺 data -> 空分类");

    // 搜索：result 缺失 -> 空列表
    h.mock
        .stub("api.bilibili.com/x/web-interface/search/type", r#"{"code":0,"data":{}}"#);
    let rooms = h.site.search_rooms("x".into(), 1).await.expect("缺 result 不应抛");
    assert!(rooms.items.is_empty());
    assert!(!rooms.has_more);
    let anchors = h.site.search_anchors("x".into(), 1).await.expect("缺 result 不应抛");
    assert!(anchors.items.is_empty());

    // SC：data 缺失 -> 空列表
    h.mock.stub(
        "api.live.bilibili.com/av/v1/SuperChat/getMessageList",
        &variant_response("av_v1_SuperChat_getMessageList", 0),
    );
    let sc = h.site.get_super_chat_messages("6".into()).await.expect("缺 list 不应抛");
    assert!(sc.is_empty());
}
