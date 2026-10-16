//! F-02 分类下房间 / F-03 推荐房间（对照 `bilibili_site.dart:82-114` / `:195-222`）。

use serde_json::Value;

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::models::{LiveCategoryResult, LiveSubCategory};
use crate::util::as_i64;

use super::site::BilibiliSite;
use super::util::room_items;
use super::wbi;

const LIST_URL: &str = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList";
const RECOMMEND_URL: &str =
    "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea";
/// 推荐接口默认每页条数（`pageSize ?? 30`）。
const DEFAULT_PAGE_SIZE: i32 = 30;

/// F-02 分类下房间。
///
/// 说明：该接口固定 30 条/页，`page_size` **仅为统一签名占位、接口忽略**（保留 fork 语义，J-3）。
pub(crate) async fn fetch_category_rooms(
    site: &BilibiliSite,
    category: &LiveSubCategory,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let access_id = wbi::access_id(site).await?;
    let full = format!(
        "{LIST_URL}?platform=web&parent_area_id={}&area_id={}&sort_type=&page={page}&w_webid={access_id}",
        category.parent_id, category.id
    );
    let query = wbi::sign(site, &full).await?;
    let value = site.get_json(LIST_URL, query).await?;
    check_api_code(&value)?;

    Ok(LiveCategoryResult {
        has_more: has_more_flag(&value),
        items: room_items(&value, "/data/list"),
    })
}

/// F-03 推荐房间（`sort=online`，真用 `page_size`）。
pub(crate) async fn fetch_recommend_rooms(
    site: &BilibiliSite,
    page: i32,
    page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    let full = format!(
        "{RECOMMEND_URL}?platform=web&sort=online&page_size={}&page={page}",
        page_size.unwrap_or(DEFAULT_PAGE_SIZE)
    );
    let query = wbi::sign(site, &full).await?;
    let value = site.get_json(RECOMMEND_URL, query).await?;
    check_api_code(&value)?;

    let items = room_items(&value, "/data/list");
    // hasMore = 本页非空（**不采信任何服务端分页字段**，AC-03）。
    let has_more = !items.is_empty();
    Ok(LiveCategoryResult { has_more, items })
}

/// `data.has_more == 1`（对齐 Dart；缺省为 0 -> false）。
fn has_more_flag(value: &Value) -> bool {
    as_i64(value.pointer("/data/has_more")).unwrap_or(0) == 1
}
