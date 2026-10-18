//! F-06 房间详情（对照 `twitch_site.dart:207-279`：`ChannelShell` + `StreamMetadata` 一次批量）。
//!
//! Dart 用**一个批量请求**取两份数据（`[q1, q2]`），Rust 保持同构：请求数不增加（Spec §9）。
//!
//! 错误口径（对齐 Dart 的三处显式抛错，改为类型化错误）：
//! - `userOrError` 为 `UserNotFoundError` 或缺失 -> [`SliveError::NotFound`]（Dart 抛 `Exception`）；
//! - `user` 缺失 -> [`SliveError::NotFound`]（Dart 抛 `Exception('Could not find user')`）；
//! - 批量响应元素不足 2 个 -> [`SliveError::Decode`]（Dart 只打日志后继续，会在后续取值时崩）。
//!
//! **不静默兜底**：任一分支失败都返回错误，不返回「全 0 的假详情」。

use crate::error::SliveError;
use crate::models::LiveRoomDetail;

use super::gql::{build_batch, build_persisted_request, CHANNEL_SHELL_HASH, STREAM_METADATA_HASH};
use super::header::TWITCH_BASE_URL;
use super::models::{TwitchResponse, UserOrError};
use super::site::TwitchSite;

/// 拉取房间详情（在线状态 / 标题 / 封面 / 人气）。
pub(crate) async fn fetch(site: &TwitchSite, room_id: &str) -> Result<LiveRoomDetail, SliveError> {
    let responses = fetch_room_info(site, room_id).await?;
    if responses.len() < 2 {
        return Err(SliveError::decode(format!(
            "Twitch GQL 返回元素不足：期望 2，实际 {}（room_id={room_id}）",
            responses.len()
        )));
    }

    // [0] = ChannelShell -> userOrError（展示名）；[1] = StreamMetadata -> user（直播态）
    let user_or_error: &UserOrError = responses[0]
        .data
        .user_or_error
        .as_ref()
        .ok_or_else(|| SliveError::not_found(format!("Could not find user_or_error: {room_id}")))?;
    if user_or_error.is_user_not_found() {
        return Err(SliveError::not_found(format!(
            "Twitch 用户不存在: {}",
            user_or_error.display_name
        )));
    }

    let user = responses[1]
        .data
        .user
        .as_ref()
        .ok_or_else(|| SliveError::not_found(format!("Could not find user: {room_id}")))?;

    let live = user.stream.as_ref().is_some_and(|s| s.is_live());
    let viewers = user
        .stream
        .as_ref()
        .map(|s| s.viewers_count)
        .unwrap_or(0);

    Ok(LiveRoomDetail {
        room_id: room_id.to_string(),
        // Dart: `user.lastBroadcast?.title ?? "null"` —— 字面量 "null"，保持一致以免 UI 显示变化。
        title: user
            .last_broadcast
            .as_ref()
            .map(|b| b.title.clone())
            .unwrap_or_else(|| "null".to_string()),
        cover: user.profile_image_url.clone(),
        user_name: user_or_error.display_name.clone(),
        user_avatar: user.profile_image_url.clone(),
        online: if live {
            i32::try_from(viewers).unwrap_or(0)
        } else {
            0
        },
        introduction: Some(String::new()),
        notice: Some(String::new()),
        status: live,
        data: None,
        // Q-13（照搬 Dart `:241`）：`danmakuData` 就是 **roomId 字符串**，不带 JSON 包装。
        // Twitch 弹幕唯一入参即频道名，无需版本化契约 —— 故 `TwitchDanmakuArgs::from_json`
        // 不用于本字段；桥层 `TwitchDanmakuConnection::start` 直接以频道名构造 args（见 `twitch/danmaku.rs`）。
        danmaku_data: Some(room_id.to_string()),
        is_record: false,
        url: format!("{TWITCH_BASE_URL}/{room_id}"),
    })
}

/// 一次批量 GQL 请求，返回按顺序解析的响应数组。
async fn fetch_room_info(
    site: &TwitchSite,
    room_id: &str,
) -> Result<Vec<TwitchResponse>, SliveError> {
    let batch = build_batch(&[
        build_persisted_request("ChannelShell", CHANNEL_SHELL_HASH, serde_json::json!({
            "login": room_id,
        })),
        build_persisted_request(
            "StreamMetadata",
            STREAM_METADATA_HASH,
            serde_json::json!({
                "channelLogin": room_id,
                "includeIsDJ": true,
            }),
        ),
    ]);
    let value = site.post_gql(&batch).await?;

    value
        .as_array()
        .ok_or_else(|| SliveError::decode("Twitch GQL 批量响应不是数组".to_string()))?
        .iter()
        .map(|item| {
            serde_json::from_value(item.clone())
                .map_err(|e| SliveError::decode(format!("解析 Twitch GQL 响应失败: {e}")))
        })
        .collect()
}
