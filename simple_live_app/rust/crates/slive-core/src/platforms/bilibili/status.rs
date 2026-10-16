//! F-09 直播状态（对照 `bilibili_site.dart:340-349`，取 `room/v1/Room/get_info`）。

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::util::as_i32;

use super::site::BilibiliSite;

const URL: &str = "https://api.live.bilibili.com/room/v1/Room/get_info";

/// 查询是否在播（`data.live_status == 1`；`data` 缺失 -> false，AC-09）。
pub(crate) async fn fetch(site: &BilibiliSite, room_id: &str) -> Result<bool, SliveError> {
    let query = vec![("room_id".to_string(), room_id.to_string())];
    let value = site.get_json(URL, query).await?;
    check_api_code(&value)?;
    Ok(as_i32(value.pointer("/data/live_status")).unwrap_or(0) == 1)
}
