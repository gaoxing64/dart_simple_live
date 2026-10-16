//! 房间条目的两种响应形态解析，从 `rooms.rs` 拆出（单文件 ≤300 行门禁）。
//!
//! 两个接口的房间挂在**不同路径**（这是 Dart 两套 `_roomItemOf` 的原因）：
//! - 分区接口：`item["room"]`，web_rid 在 `item["web_rid"]`；
//! - 推荐流：`item["data"]`，web_rid 在 `data.owner.web_rid`。
//!
//! 两条路径共用同一套「逐字段判空、脏条目跳过」口径：单条畸形只丢自己，
//! 不拖垮整页（调用方用 `filter_map` 收集）。

use serde_json::Value;

use crate::models::LiveRoomItem;

use super::super::util::as_object;
use super::super::util::first_url;

/// 取 `result["data"]["data"]` 数组；形状不对一律降级为空切片（对齐 Dart 的逐层判空）。
pub(super) fn data_array(value: &Value) -> Vec<Value> {
    value
        .pointer("/data/data")
        .and_then(Value::as_array)
        .map(|a| a.to_vec())
        .unwrap_or_default()
}

/// 分区接口条目 -> `LiveRoomItem`（房间挂在 `item["room"]`）。
pub(super) fn room_item_of_partition(item: &Value) -> Option<LiveRoomItem> {
    let room = as_object(item.get("room"))?;
    // 没有 web_rid 就没法去重也没法进房，直接跳过
    let web_rid = item.get("web_rid")?;
    Some(build_room_item(
        web_rid,
        room.get("title"),
        room.get("cover"),
        as_object(room.get("owner")).and_then(|o| o.get("nickname")),
        room.get("room_view_stats"),
    ))
}

/// 推荐流条目 -> `LiveRoomItem`（房间挂在 `item["data"]`，web_rid 在 `data.owner.web_rid`）。
pub(super) fn room_item_of_feed(item: &Value) -> Option<LiveRoomItem> {
    let data = as_object(item.get("data"))?;
    let owner = as_object(data.get("owner"))?;
    let web_rid = owner.get("web_rid")?;
    Some(build_room_item(
        web_rid,
        data.get("title"),
        data.get("cover"),
        owner.get("nickname"),
        data.get("room_view_stats"),
    ))
}

/// 组装 `LiveRoomItem`。`online` 走 `int.tryParse(display_value)`（解析失败为 0）。
fn build_room_item(
    web_rid: &Value,
    title: Option<&Value>,
    cover: Option<&Value>,
    nickname: Option<&Value>,
    stats: Option<&Value>,
) -> LiveRoomItem {
    LiveRoomItem {
        room_id: crate::util::value_to_string(web_rid),
        title: title.map(crate::util::value_to_string).unwrap_or_default(),
        cover: first_url(cover),
        user_name: nickname
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        online: stats
            .and_then(|s| as_object(Some(s)))
            .and_then(|o| o.get("display_value"))
            .map(crate::util::value_to_string)
            .and_then(|s| s.parse::<i32>().ok())
            .unwrap_or(0),
    }
}
