//! 房间列表：分类下房间 + 推荐（对照 Dart `getCategoryRooms` / `getRecommendRooms`，
//! `douyin_site.dart:109-492`）。
//!
//! 两个接口、两种翻页语义（**不可互换**，照抄 Dart 的实测结论）：
//! - **分区接口** `webcast/web/partition/detail/room/v2/`：**真分页**（offset 0/15/30/…
//!   实测零重复，单分区约 120 条深度）。服务端在 `count <= 20` 时严格返回 `count` 条，
//!   `count >= 25` 时只给 20 条 —— 后者会让「本页满不满」的判据恒为 false 而把列表
//!   误判成已到底，故 `count` 固定 15（`_fetchPartitionPage` 的调用点传值）。
//! - **推荐流** `webcast/feed/`：**无翻页能力**（count/offset/cursor 全部被忽略，
//!   固定随机 20 条）。因此首屏靠「一轮并发扇出 N 路」把热门池收齐，
//!   第 2 页起必须换到分区接口。
//!
//! `has_more` 一律用**服务端原始条数**（`raw_count`）判定，不能用过滤后的 `items.len()`：
//! 脏条目被跳过不该让「本页满不满」失真、提前把列表判成到底。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveCategoryResult, LiveRoomItem, LiveSubCategory};

use super::signing::build_signed_url;

mod items;

use items::{data_array, room_item_of_feed, room_item_of_partition};
use super::site::DouyinSite;
use super::util::QueryParams;

/// 分区接口 URL。
pub const PARTITION_URL: &str =
    "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
/// 推荐流接口 URL。
pub const FEED_URL: &str = "https://live.douyin.com/webcast/feed/";
/// 分区接口单页条数（服务端能严格兑现的上限 20；分类页实际用 15）。
pub const PARTITION_PAGE_SIZE: i32 = 15;
/// 推荐流单次返回条数（服务端固定 20，参数无效）。
pub const FEED_SLICE_SIZE: i32 = 20;
/// 单次推荐请求内部并发路数下限。
pub const MIN_FEED_FANOUT: i32 = 4;
/// 并发路数上限（兜住 `page_size` 异常大）。
pub const MAX_FEED_FANOUT: i32 = 6;
/// 「推荐」第 2 页起的续接分区（按实测人气中位数降序；生活(107,4) 中位人气为 0 被剔除）。
pub const RECOMMEND_PARTITIONS: [&str; 7] = [
    "106,4", // 文化
    "103,4", // 游戏
    "101,4", // 聊天
    "102,4", // 音乐
    "108,4", // 运动
    "104,4", // 二次元
    "105,4", // 舞蹈
];

/// 一页分区/推荐结果：过滤后的条目 + **服务端原始条数**（判 `has_more` 用）。
pub struct PartitionPage {
    /// 可用条目（脏数据已跳过）。
    pub items: Vec<LiveRoomItem>,
    /// 服务端这一页实际返回的条数。
    pub raw_count: usize,
}

/// 分类下房间。`page_size` 被忽略（Dart 明确维持 15）。
pub(crate) async fn fetch_category_rooms(
    site: &DouyinSite,
    category: &LiveSubCategory,
    page: i32,
    _page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    super::header::ensure_ttwid(site).await?;
    let offset = (page - 1) * PARTITION_PAGE_SIZE;
    let result = fetch_partition_page(site, &category.id, offset).await?;
    Ok(LiveCategoryResult {
        has_more: result.raw_count >= PARTITION_PAGE_SIZE as usize,
        items: result.items,
    })
}

/// 推荐房间：第 1 页走真实推荐流（并发扇出），第 2 页起走分区接口续接。
pub(crate) async fn fetch_recommend_rooms(
    site: &DouyinSite,
    page: i32,
    page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    super::header::ensure_ttwid(site).await?;
    if page <= 1 {
        return fetch_recommend_feed(site, page_size).await;
    }
    fetch_recommend_continuation(site, page).await
}

/// 首屏：一轮并发扇出拉取推荐切片。
///
/// 并发的意义是把热门池在**一次等待**里尽量收齐，而不是「靠多等几轮让池自己转出新东西」，
/// 所以墙钟耗时 ≈ 单次请求；串行 N 次会让首屏延迟翻 N 倍（此处 N = 4~6）。
/// 任何一路失败都不影响其余切片；**全部**失败才上抛（部分失败容忍，避免偶发单路
/// 限流把整页打成错误页 —— 此时应展示空页/残页而非错误）。
pub(crate) async fn fetch_recommend_feed(
    site: &DouyinSite,
    page_size: Option<i32>,
) -> Result<LiveCategoryResult, SliveError> {
    // 第 1 页 = 新一轮推荐，续接游标归零
    site.set_last_served_slot(-1);
    let fanout = recommend_fanout(page_size);
    let header = super::header::build_header(site);

    // 全部起飞再统一收集：任一路的失败都在下面按切片处理
    let slices = futures_util::future::join_all(
        (0..fanout).map(|slice_index| fetch_feed_slice(site, header.clone(), slice_index)),
    )
    .await;

    let mut items: Vec<LiveRoomItem> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut succeeded = 0usize;
    let mut first_error: Option<SliveError> = None;
    for slice in slices {
        match slice {
            Ok(slice) => {
                succeeded += 1;
                for item in slice {
                    if seen.insert(item.room_id.clone()) {
                        items.push(item);
                    }
                }
            }
            Err(e) => {
                log::warn!("抖音推荐流切片失败（其余切片继续）: {e}");
                first_error.get_or_insert(e);
            }
        }
    }

    if succeeded == 0 {
        return Err(first_error.unwrap_or_else(|| {
            SliveError::decode("抖音推荐流全部切片均无数据".to_string())
        }));
    }
    // 首屏只负责把热门池收满，「还有更多」恒为 true（真正到底由分区接口判定）
    Ok(LiveCategoryResult {
        has_more: !items.is_empty(),
        items,
    })
}

/// 第 2 页起：官方分区接口真分页。
///
/// 把「页号」映射成一条虚拟无限序列：第 2 页 -> slot 0、第 3 页 -> slot 1……
/// 起点取「页号对应 slot」与「上次命中 slot + 1」的较大者 —— 后者保证相邻页号不会
/// 重复命中同一个 `(分区, offset)`（那会让同一份内容被连续两页原样返回，
/// 而 App 判「到底」的依据是**连续 2 页零新增**，列表会提前收尾）。
pub(crate) async fn fetch_recommend_continuation(
    site: &DouyinSite,
    page: i32,
) -> Result<LiveCategoryResult, SliveError> {
    let slots = RECOMMEND_PARTITIONS.len() as i32;
    // 起点 = 「页号对应 slot」与「上次命中 slot + 1」的较大者（见模块文档的相邻页重复分析）
    let start = (page - 2).max(site.last_served_slot() + 1);
    for slot in start..start + slots {
        let partition = RECOMMEND_PARTITIONS[(slot.rem_euclid(slots)) as usize];
        let offset = slot / slots * PARTITION_PAGE_SIZE;
        let result = fetch_partition_page(site, partition, offset).await?;
        if !result.items.is_empty() {
            site.set_last_served_slot(slot);
            return Ok(LiveCategoryResult {
                has_more: true,
                items: result.items,
            });
        }
        // 某分区翻到底 -> 顺延到下一个分区（for 的下一轮即 slot+1），
        // 避免先耗尽的分区把整条列表卡死
    }
    Ok(LiveCategoryResult {
        has_more: false,
        items: Vec::new(),
    })
}

/// 拉取某分区的一页（分类页与推荐续接页共用）。
/// 分区页的 query 参数（与 Dart `_fetchRecommendContinuation` 逐键一致）。
///
/// ⚠️ **`aid=6383` 与 `device_platform=web` 是硬约束**：缺 aid 服务端 400
/// （2026-10-16 真机复现）。离线夹具校验不到参数级差异，故由
/// `partition_params_carries_aid` 钉住。
pub fn partition_params(partition: &str, offset: i32) -> QueryParams {
    let ids: Vec<&str> = partition.split(',').collect();
    let mut params = QueryParams::new();
    params
        .put("aid", "6383")
        .put("app_name", "douyin_web")
        .put("live_id", "1")
        .put("device_platform", "web")
        .put("language", "zh-CN")
        .put("enter_from", "link_share")
        .put("cookie_enabled", "true")
        .put("screen_width", "1980")
        .put("screen_height", "1080")
        .put("browser_language", "zh-CN")
        .put("browser_platform", "Win32")
        .put("browser_name", "Edge")
        .put("browser_version", "125.0.0.0")
        .put("browser_online", "true")
        .put("count", PARTITION_PAGE_SIZE.to_string())
        .put("offset", offset.to_string())
        .put("partition", ids.first().copied().unwrap_or(""))
        .put(
            "partition_type",
            ids.get(1).copied().unwrap_or("4").to_string(),
        )
        .put("req_from", "2");
    params
}

pub(crate) async fn fetch_partition_page(
    site: &DouyinSite,
    partition: &str,
    offset: i32,
) -> Result<PartitionPage, SliveError> {
    let params = partition_params(partition, offset);

    let url = build_signed_url(PARTITION_URL, &params)?;
    let value = site
        .get_json(&url, Vec::new(), super::header::build_header(site))
        .await?;

    // 翻到底时服务端返回空数组；`data` 也可能是 List（错误响应）—— 一律降级成空页
    let data_list = data_array(&value);
    let items = data_list.iter().filter_map(room_item_of_partition).collect();
    Ok(PartitionPage {
        items,
        raw_count: data_list.len(),
    })
}

/// 拉取一份推荐切片（一次 `webcast/feed/` 请求）。
///
/// `slice_index` 只用来让每份切片的 `count` 不同：服务端忽略 `count`，但**参数不同的
/// 并发请求**抽到的房间重叠更少（实测 6 路同参数去重 32 条、每路换 count 则 38 条）。
pub(crate) async fn fetch_feed_slice(
    site: &DouyinSite,
    header: Vec<(String, String)>,
    slice_index: i32,
) -> Result<Vec<LiveRoomItem>, SliveError> {
    let params = feed_slice_params(slice_index);
    // feed 接口不带 a_bogus（Dart 直接 `getJson` + queryParameters，未过 buildRequestUrl）
    let url = format!("{FEED_URL}?{}", params.to_query());
    let value = site.get_json(&url, Vec::new(), header).await?;

    let data_list = match value.get("data") {
        Some(Value::Array(a)) => a.clone(),
        _ => Vec::new(),
    };
    Ok(data_list.iter().filter_map(room_item_of_feed).collect())
}

/// feed 切片的 query 参数（与 Dart `_fetchFeedSlice` 逐键一致）。
///
/// ⚠️ **`aid=6383` 是硬约束**：缺它服务端直接 400 空 body（2026-10-16 真机
/// 复现：无 aid → 400，补 aid → 200）。离线夹具校验不到参数级差异，
/// 故由 `feed_slice_params_carries_aid` 钉住。
pub fn feed_slice_params(slice_index: i32) -> QueryParams {
    let mut params = QueryParams::new();
    params
        .put("aid", "6383")
        .put("app_name", "douyin_web")
        .put("need_map", "1")
        .put("is_draw", "1")
        .put("inner_from_drawer", "0")
        .put("enter_source", "web_homepage_hot_web_live_card")
        .put("source_key", "web_homepage_hot_web_live_card")
        .put("count", (FEED_SLICE_SIZE * (slice_index + 1)).to_string());
    params
}

/// 按期望条数换算并发路数。
///
/// `page_size` 在这里**不是**服务端的 count（服务端不认），而是「这一页大概要给多少条」
/// 的期望值。切片之间约有 1/3 重叠，要拿 N 条得拉不止 N/20 路，故给下限
/// [`MIN_FEED_FANOUT`] 兜底（App 为填满视口传 30 -> 4 路 ≈ 43 条）。
pub fn recommend_fanout(page_size: Option<i32>) -> i32 {
    let target = page_size.unwrap_or(FEED_SLICE_SIZE);
    if target <= 0 {
        return MIN_FEED_FANOUT;
    }
    let want = (target as f64 / FEED_SLICE_SIZE as f64).ceil() as i32;
    want.clamp(MIN_FEED_FANOUT, MAX_FEED_FANOUT)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn feed_slice_params_carries_aid() {
        // 缺 aid -> 服务端 400 空 body（2026-10-16 真机复现）；参数级回归防线
        let q = feed_slice_params(0).to_query();
        assert!(q.contains("aid=6383"), "feed 参数必须带 aid=6383: {q}");
        assert!(q.contains("app_name=douyin_web"));
        assert!(q.contains("count=20"), "slice 0 的 count=20: {q}");
        assert!(feed_slice_params(1).to_query().contains("count=40"));
    }

    #[test]
    fn partition_params_carries_aid() {
        let q = partition_params("7,1", 0).to_query();
        assert!(q.contains("aid=6383"), "分区参数必须带 aid=6383: {q}");
        assert!(q.contains("device_platform=web"));
        assert!(q.contains("partition=7"));
        assert!(q.contains("partition_type=1"));
        assert!(q.contains("offset=0"));
    }

    #[test]
    fn fanout_clamps_to_bounds() {
        assert_eq!(recommend_fanout(None), MIN_FEED_FANOUT);
        assert_eq!(recommend_fanout(Some(0)), MIN_FEED_FANOUT);
        assert_eq!(recommend_fanout(Some(-5)), MIN_FEED_FANOUT);
        assert_eq!(recommend_fanout(Some(30)), 4, "30/20 -> 2，下限兜到 4");
        assert_eq!(recommend_fanout(Some(200)), MAX_FEED_FANOUT, "上限 6");
    }

    #[test]
    fn partition_page_reads_room_shape() {
        let value = json!({"data": {"data": [{
            "web_rid": "416144012050",
            "room": {
                "title": "直播间",
                "cover": {"url_list": ["https://cover"]},
                "owner": {"nickname": "主播"},
                "room_view_stats": {"display_value": "1.2万"},
            },
        }]}});
        let list = data_array(&value);
        assert_eq!(list.len(), 1);
        let item = room_item_of_partition(&list[0]).expect("应能组装");
        assert_eq!(item.room_id, "416144012050");
        assert_eq!(item.title, "直播间");
        assert_eq!(item.cover, "https://cover");
        assert_eq!(item.user_name, "主播");
        assert_eq!(item.online, 0, "「1.2万」不是 int，parse 失败为 0（Dart 同口径）");
    }

    #[test]
    fn feed_item_reads_data_shape() {
        let value = json!([{
            "data": {
                "title": "推荐间",
                "cover": {"url_list": ["https://c"]},
                "owner": {"web_rid": "999", "nickname": "主播A"},
                "room_view_stats": {"display_value": 4321},
            }
        }]);
        let item = room_item_of_feed(&value[0]).expect("应能组装");
        assert_eq!(item.room_id, "999");
        assert_eq!(item.user_name, "主播A");
        assert_eq!(item.online, 4321);
    }

    #[test]
    fn dirty_entries_are_skipped_not_fatal() {
        assert!(room_item_of_partition(&json!({})).is_none(), "缺 room 应跳过");
        assert!(room_item_of_partition(&json!({"room": {}})).is_none(), "缺 web_rid 应跳过");
        assert!(room_item_of_feed(&json!({"data": {}})).is_none());
        // 数字型 display_value 可解析
        assert_eq!(
            room_item_of_partition(&json!({
                "web_rid": "1",
                "room": {"room_view_stats": {"display_value": 88}}
            }))
            .expect("应能组装")
            .online,
            88
        );
    }

    #[test]
    fn data_array_degrades_on_unexpected_shapes() {
        assert_eq!(data_array(&json!({"data": []})).len(), 0, "错误响应降级为空");
        assert_eq!(data_array(&json!({})).len(), 0);
        assert_eq!(data_array(&json!({"data": {"data": {}}})).len(), 0);
    }

    #[test]
    fn recommend_partitions_exclude_zero_popularity_life() {
        assert!(!RECOMMEND_PARTITIONS.contains(&"107,4"), "生活(107,4) 应被剔除");
        assert_eq!(RECOMMEND_PARTITIONS.len(), 7);
    }
}
