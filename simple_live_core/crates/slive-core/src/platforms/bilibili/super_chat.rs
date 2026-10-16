//! F-10 房间 SC 列表（对照 `bilibili_site.dart:352-379`，DTV/上游均缺，须重实现）。

use chrono::{Local, TimeZone};
use serde_json::Value;

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::models::LiveSuperChatMessage;
use crate::util::as_i64;

use super::site::BilibiliSite;
use super::util::{text, text_ptr};

const URL: &str = "https://api.live.bilibili.com/av/v1/SuperChat/getMessageList";

/// 拉取房间 SC 列表（`data.list` 缺失 -> 空列表，AC-27）。
pub(crate) async fn fetch(
    site: &BilibiliSite,
    room_id: &str,
) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
    let query = vec![("room_id".to_string(), room_id.to_string())];
    let value = site.get_json(URL, query).await?;
    check_api_code(&value)?;
    Ok(crate::util::array_at(&value, "/data/list")
        .iter()
        .map(parse_one)
        .collect())
}

fn parse_one(item: &Value) -> LiveSuperChatMessage {
    // 秒 -> 毫秒（对齐 Dart `DateTime.fromMillisecondsSinceEpoch(sec * 1000)`）。
    let start_ms = as_i64(item.get("start_time")).unwrap_or(0) * 1000;
    let end_ms = as_i64(item.get("end_time")).unwrap_or(0) * 1000;
    LiveSuperChatMessage {
        user_name: text_ptr(item, "/user_info/uname"),
        face: format!("{}@200w.jpg", text_ptr(item, "/user_info/face")),
        message: text(item, "message"),
        price: crate::util::as_i32(item.get("price")).unwrap_or(0),
        start_time: to_local(start_ms),
        end_time: to_local(end_ms),
        background_color: text(item, "background_color"),
        background_bottom_color: text(item, "background_bottom_color"),
    }
}

fn to_local(millis: i64) -> chrono::DateTime<Local> {
    Local.timestamp_millis_opt(millis).single().unwrap_or_else(Local::now)
}
