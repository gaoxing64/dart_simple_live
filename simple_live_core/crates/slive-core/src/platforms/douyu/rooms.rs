//! F-02 分类下房间 / F-03 推荐房间（对照 `douyu_site.dart:58-84` / `:176-216`）。
//!
//! ⚠️ 两个接口的**分页判据不同**，不可"统一"（Dart 源码有明确注释）：
//! - 分类流 `gapi/rkc/directory/mixList`：`pgcnt` **有效** -> `hasMore = page < pgcnt`；
//! - 推荐流 `japi/weblist/apinc/allpage`：`pgcnt` **恒为 0**（2026-09 实测），
//!   用它会让 `hasMore` 恒 false，表现为「内容不满一屏却不再加载」；
//!   该接口实为页间零交集的无限榜单，故按「本页非空即还有更多」处理。
//!
//! 两个接口的单页条数都写死在 URL 路径里，`page_size` 仅为统一签名占位（Dart 明确忽略）。

use crate::error::SliveError;
use crate::models::{LiveCategoryResult, LiveSubCategory};
use crate::util::as_i64;

use super::api_code::check_error_code;
use super::header::request_header;
use super::site::DouyuSite;
use super::util::{is_live_room, room_item};

/// 分类房间端点模板（`{cate2Id}` 与 `{page}` 在路径里）。
const MIX_LIST_URL: &str = "https://www.douyu.com/gapi/rkc/directory/mixList";
/// 推荐房间端点模板（`6` 为固定分区号）。
const RECOMMEND_URL: &str = "https://www.douyu.com/japi/weblist/apinc/allpage";

/// F-02 分类下房间。
pub(crate) async fn fetch_category_rooms(
    site: &DouyuSite,
    category: &LiveSubCategory,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let url = format!("{MIX_LIST_URL}/2_{}/{}", category.id, page.max(1));
    let value = site
        .get_json_with(url, Vec::new(), request_header(site, "", &site.cookie(), false))
        .await?;
    check_error_code(&value)?;

    let items: Vec<_> = crate::util::array_at(&value, "/data/rl")
        .iter()
        .filter(|item| is_live_room(item))
        .map(room_item)
        .collect();
    // 该接口 pgcnt 有效（与推荐流不同！）
    let pgcnt = as_i64(value.pointer("/data/pgcnt")).unwrap_or(0);
    Ok(LiveCategoryResult {
        has_more: (page as i64) < pgcnt,
        items,
    })
}

/// F-03 推荐房间。
pub(crate) async fn fetch_recommend_rooms(
    site: &DouyuSite,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let url = format!("{RECOMMEND_URL}/6/{}", page.max(1));
    let value = site
        .get_json_with(url, Vec::new(), request_header(site, "", &site.cookie(), false))
        .await?;
    check_error_code(&value)?;

    let items: Vec<_> = crate::util::array_at(&value, "/data/rl")
        .iter()
        .filter(|item| is_live_room(item))
        .map(room_item)
        .collect();
    Ok(LiveCategoryResult {
        has_more: !items.is_empty(),
        items,
    })
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use super::super::transport::MockDouyuPost;

    const MIX_FIXTURE: &str = r#"{"code":0,"data":{"pgcnt":3,"rl":[
        {"rid":11,"rn":"A","nn":"主播A","ol":10,"rs16":"http://a.jpg","type":1},
        {"rid":12,"rn":"B","nn":"主播B","ol":0,"rs16":"http://b.jpg","type":0}
    ]}}"#;
    const REC_FIXTURE: &str = r#"{"error":0,"data":{"pgcnt":0,"rl":[
        {"rid":21,"rn":"C","nn":"主播C","ol":99,"rs16":"http://c.jpg","type":1}
    ]}}"#;

    fn site() -> (DouyuSite, Arc<MockTransport>) {
        let mock = Arc::new(MockTransport::new());
        mock.stub("directory/mixList", MIX_FIXTURE);
        mock.stub("weblist/apinc/allpage", REC_FIXTURE);
        let s = DouyuSite::with_deps(
            mock.clone(),
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        (s, mock)
    }

    fn category() -> LiveSubCategory {
        LiveSubCategory {
            id: "201".into(),
            name: "户外".into(),
            parent_id: "2".into(),
            pic: None,
        }
    }

    #[tokio::test]
    async fn category_rooms_use_pgcnt_and_filter_non_live() {
        let (s, _mock) = site();
        let page1 = s
            .get_category_rooms(category(), 1, None)
            .await
            .expect("分类房间应成功");
        assert!(page1.has_more, "page(1) < pgcnt(3)");
        assert_eq!(page1.items.len(), 1, "type!=1 的房间必须过滤掉");
        assert_eq!(page1.items[0].room_id, "11");

        let page3 = s
            .get_category_rooms(category(), 3, None)
            .await
            .expect("末页不应抛");
        assert!(!page3.has_more, "page(3) == pgcnt(3) -> 没有更多");
    }

    #[tokio::test]
    async fn recommend_ignores_pgcnt_and_uses_non_empty_page() {
        let (s, mock) = site();
        let result = s.get_recommend_rooms(1, None).await.expect("推荐应成功");
        assert!(
            result.has_more,
            "pgcnt 恒 0 也不得让 hasMore 为 false（本页非空即有更多）"
        );
        assert_eq!(result.items.len(), 1);
        assert_eq!(result.items[0].online, 99);
        assert!(mock.request_urls()[0].contains("/allpage/6/1"));
    }

    #[tokio::test]
    async fn empty_page_reports_no_more() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("weblist/apinc/allpage", r#"{"error":0,"data":{"rl":[]}}"#);
        let s = DouyuSite::with_deps(
            mock,
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        let result = s.get_recommend_rooms(9, None).await.expect("空页不应抛");
        assert!(!result.has_more);
        assert!(result.items.is_empty());
    }

    #[tokio::test]
    async fn business_error_propagates_as_api_error() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("weblist/apinc/allpage", r#"{"error":-101,"msg":"需要验证"}"#);
        let s = DouyuSite::with_deps(
            mock,
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        let err = s.get_recommend_rooms(1, None).await.expect_err("必须抛错");
        assert!(matches!(err, SliveError::Api { code: -101, .. }), "实际 {err:?}");
    }
}