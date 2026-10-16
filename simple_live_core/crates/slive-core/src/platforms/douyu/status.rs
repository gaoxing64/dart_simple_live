//! F-09 直播状态（对照 `douyu_site.dart:336-340`）。
//!
//! 与 F-06 共用 `betard` 请求与判定式，避免两处各写一套（口径漂移的高发点）。

use crate::error::SliveError;

use super::detail::{fetch_room_info, is_room_live};
use super::site::DouyuSite;

/// 房间是否在播。
pub(crate) async fn fetch(site: &DouyuSite, room_id: &str) -> Result<bool, SliveError> {
    let room = fetch_room_info(site, room_id).await?;
    Ok(is_room_live(&room))
}