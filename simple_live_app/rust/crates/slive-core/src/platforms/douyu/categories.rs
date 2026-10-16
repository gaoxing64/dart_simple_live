//! F-01 分类列表（对照 `douyu_site.dart:28-56`）。
//!
//! 走 `m.douyu.com/api/cate/list`：一次返回一级分类（`cate1Info`）与二级分类（`cate2Info`），
//! 二级按 `cate1Id` 挂到一级下，最后**按 ID 数值升序**排序（Dart 用 `int.parse` 比较）。

use crate::error::SliveError;
use crate::models::{LiveCategory, LiveSubCategory};

use super::api_code::check_error_code;
use super::site::DouyuSite;
use super::util::value_or_empty;

/// 分类端点（移动端 API，与 Web 端 `japi` 不同）。
const CATE_URL: &str = "https://m.douyu.com/api/cate/list";

/// 拉取分类树。
pub(crate) async fn fetch(site: &DouyuSite) -> Result<Vec<LiveCategory>, SliveError> {
    let value = site
        .get_json_with(
            CATE_URL,
            Vec::new(),
            super::header::request_header(site, "", &site.cookie(), false),
        )
        .await?;
    check_error_code(&value)?;

    let cate1_list = crate::util::array_at(&value, "/data/cate1Info");
    let cate2_list = crate::util::array_at(&value, "/data/cate2Info");

    let mut categories: Vec<LiveCategory> = cate1_list
        .iter()
        .map(|item| {
            let cate1_id = value_or_empty(item, "cate1Id");
            let children: Vec<LiveSubCategory> = cate2_list
                .iter()
                .filter(|sub| value_or_empty(sub, "cate1Id") == cate1_id)
                .map(|sub| LiveSubCategory {
                    id: value_or_empty(sub, "cate2Id"),
                    name: value_or_empty(sub, "cate2Name"),
                    parent_id: cate1_id.clone(),
                    pic: Some(value_or_empty(sub, "icon")),
                })
                .collect();
            LiveCategory {
                id: cate1_id,
                name: value_or_empty(item, "cate1Name"),
                children,
            }
        })
        .collect();

    // 按 ID 数值升序（对齐 Dart `categories.sort(int.parse(a.id)…)`）。
    // 非法 ID 排到末尾而非 panic —— 分类列表是首页强依赖，不能因单个脏数据整体失败。
    categories.sort_by_key(|a| numeric_id(&a.id));

    Ok(categories)
}

/// 分类 ID 的数值排序键：合法数字取其值，非法数字取 `i64::MAX`（排到末尾，不 panic）。
fn numeric_id(id: &str) -> i64 {
    id.trim().parse::<i64>().unwrap_or(i64::MAX)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use super::super::transport::MockDouyuPost;

    const FIXTURE: &str = r#"{"error":0,"data":{
        "cate1Info":[{"cate1Id":9,"cate1Name":"游戏"},{"cate1Id":2,"cate1Name":"娱乐"}],
        "cate2Info":[
            {"cate1Id":2,"cate2Id":201,"cate2Name":"户外","icon":"http://i1.png"},
            {"cate1Id":9,"cate2Id":901,"cate2Name":"LOL","icon":"http://i2.png"},
            {"cate1Id":9,"cate2Id":902,"cate2Name":"DOTA2","icon":"http://i3.png"}
        ]}}"#;

    fn site() -> (DouyuSite, Arc<MockTransport>) {
        let mock = Arc::new(MockTransport::new());
        mock.stub("m.douyu.com/api/cate/list", FIXTURE);
        let site = DouyuSite::with_deps(
            mock.clone(),
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        (site, mock)
    }

    #[tokio::test]
    async fn builds_tree_sorted_by_id_and_keeps_request_count() {
        let (s, mock) = site();
        let categories = s.get_categories().await.expect("分类应成功");

        assert_eq!(categories.len(), 2);
        assert_eq!(categories[0].id, "2", "按 ID 升序，娱乐在前");
        assert_eq!(categories[0].name, "娱乐");
        assert_eq!(categories[1].id, "9");
        assert_eq!(categories[1].children.len(), 2, "LOL/DOTA2 挂到游戏下");
        assert_eq!(categories[1].children[0].id, "901");
        assert_eq!(categories[1].children[0].parent_id, "9");
        assert_eq!(
            categories[1].children[0].pic.as_deref(),
            Some("http://i2.png")
        );
        assert_eq!(categories[0].children.len(), 1);
        assert_eq!(mock.request_count("cate/list"), 1, "不得重复请求");
    }

    #[tokio::test]
    async fn business_error_is_api_error() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("m.douyu.com/api/cate/list", r#"{"error":-1,"msg":"风控"}"#);
        let s = DouyuSite::with_deps(
            mock,
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        let err = s.get_categories().await.expect_err("error!=0 必须抛错");
        match err {
            SliveError::Api { code, .. } => assert_eq!(code, -1),
            other => panic!("期望 SliveError::Api，实际 {other:?}"),
        }
    }
}