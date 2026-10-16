//! 详情字段组装（三条链路共用，保证字段口径一致）。
//!
//! 对照 Dart `_buildDetailFromReflowRoom` / `_getRoomDetailByWebRidApi` /
//! `_getRoomDetailByWebRidHtml` 里三段结构相同的 `LiveRoomDetail(...)` 构造。
//!
//! # 字段口径要点
//! - `status`：服务端 `room.status == 2` 即在播；
//! - `room_id`：优先 `webRid`，缺失时回退传入的 roomId；
//! - `data`：`stream_url` 对象的 **JSON String 通道**（§4.4），未开播给 `{}`；
//! - `danmaku_data`：[`DouyinDanmakuArgs`] 的 JSON 串（键 `web_rid/room_id/user_id/cookie`），
//!   观众 ID 为 12 位随机数字（Dart 注释：服务端并不校验这个参数）；
//! - `online` / `cover`：仅在播时取值，未播为 0 / 空串；
//! - `introduction` / `notice`：抖音不返回公告，恒空串（保持字段存在）。

use serde_json::{Map, Value};

use crate::error::SliveError;
use crate::models::LiveRoomDetail;

use super::super::danmaku::args::DouyinDanmakuArgs;
use super::super::site::DouyinSite;
use super::super::util::{as_object, first_url, to_json_string};
use super::ROOM_PAGE_URL;

/// `stream_url` 序列化为 JSON String 通道（未开播给空对象，对齐 Dart 的 `const {}`）。
pub(crate) fn stream_data_json(
    room: &Map<String, Value>,
    room_status: bool,
) -> Result<Option<String>, SliveError> {
    if !room_status {
        return Ok(Some(to_json_string(&Value::Object(Map::new()))?));
    }
    let stream = room
        .get("stream_url")
        .and_then(|v| as_object(Some(v)))
        .cloned()
        .unwrap_or_default();
    Ok(Some(to_json_string(&Value::Object(stream))?))
}

/// 在播时的在线人数（`room_view_stats.display_value`）。
pub(crate) fn online_of(room: &Map<String, Value>) -> i32 {
    room.get("room_view_stats")
        .and_then(|v| as_object(Some(v)))
        .and_then(|o| o.get("display_value"))
        .and_then(|v| crate::util::as_i32(Some(v)))
        .unwrap_or(0)
}

/// 文本字段（`None`/非字符串 -> 空串）。
pub(crate) fn text_of(value: Option<&Value>) -> String {
    value.map(crate::util::value_to_string).unwrap_or_default()
}

/// 简介（`owner.signature`，缺失 -> 空串）。
fn introduction_of(owner: Option<&Map<String, Value>>) -> Option<String> {
    Some(
        owner
            .and_then(|o| o.get("signature"))
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
    )
}

/// 直播间 URL（`https://live.douyin.com/{web_rid}`）。
fn room_page_url(web_rid: &str) -> String {
    format!("{ROOM_PAGE_URL}{web_rid}")
}

/// 在播时的 (昵称, 头像) —— 取 `room.owner`。
fn live_identity(room: &Map<String, Value>) -> (String, String) {
    let owner = as_object(room.get("owner"));
    (
        owner
            .and_then(|o| o.get("nickname"))
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        first_url(owner.and_then(|o| o.get("avatar_thumb"))),
    )
}

/// 未播时的 (昵称, 头像) —— 降级到备用来源（`data.user` 或页面 `anchor`）。
fn offline_identity(fallback: Option<&Map<String, Value>>) -> (String, String) {
    (
        fallback
            .and_then(|u| u.get("nickname"))
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        first_url(fallback.and_then(|u| u.get("avatar_thumb"))),
    )
}

/// 从 `reflow/info` 的 room 对象组装详情（roomId 链路 + `web/enter` 补救链路共用）。
pub(crate) fn build_detail_from_reflow_room(
    site: &DouyinSite,
    room: &Map<String, Value>,
    room_id: &str,
    fallback_web_rid: &str,
) -> LiveRoomDetail {
    let owner = as_object(room.get("owner"));
    let web_rid = owner
        .and_then(|o| o.get("web_rid"))
        .map(crate::util::value_to_string)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| fallback_web_rid.to_string());
    let room_status = crate::util::as_i32(room.get("status")).unwrap_or(0) == 2;
    let (user_name, user_avatar) = live_identity(room);

    LiveRoomDetail {
        room_id: if web_rid.is_empty() {
            room_id.to_string()
        } else {
            web_rid.clone()
        },
        title: text_of(room.get("title")),
        cover: if room_status { first_url(room.get("cover")) } else { String::new() },
        user_name,
        user_avatar,
        online: if room_status { online_of(room) } else { 0 },
        introduction: introduction_of(owner),
        notice: Some(String::new()),
        status: room_status,
        data: stream_data_json(room, room_status).unwrap_or(None),
        danmaku_data: DouyinDanmakuArgs::new(
            web_rid.clone(),
            room_id.to_string(),
            super::super::util::random_digits(12),
            site.header_cookie(),
        )
        .to_json()
        .ok(),
        is_record: false,
        url: room_page_url(&web_rid),
    }
}

/// 从 `web/enter` 的 room 对象组装详情（未播时昵称/头像降级到 `data.user`）。
pub(crate) fn build_detail_from_enter(
    site: &DouyinSite,
    room: &Map<String, Value>,
    user: Option<&Map<String, Value>>,
    web_rid: &str,
    room_id: &str,
) -> LiveRoomDetail {
    let owner = as_object(room.get("owner"));
    let room_status = crate::util::as_i32(room.get("status")).unwrap_or(0) == 2;
    let (user_name, user_avatar) = if room_status {
        live_identity(room)
    } else {
        offline_identity(user)
    };

    LiveRoomDetail {
        room_id: web_rid.to_string(),
        title: text_of(room.get("title")),
        cover: if room_status { first_url(room.get("cover")) } else { String::new() },
        user_name,
        user_avatar,
        online: if room_status { online_of(room) } else { 0 },
        introduction: introduction_of(owner),
        notice: Some(String::new()),
        status: room_status,
        data: stream_data_json(room, room_status).unwrap_or(None),
        danmaku_data: DouyinDanmakuArgs::new(
            web_rid.to_string(),
            room_id.to_string(),
            super::super::util::random_digits(12),
            site.header_cookie(),
        )
        .to_json()
        .ok(),
        is_record: false,
        url: room_page_url(web_rid),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn live_room() -> Map<String, Value> {
        json!({
            "id_str": "7382735338101328680",
            "title": "测试直播间",
            "status": 2,
            "cover": {"url_list": ["https://cover"]},
            "owner": {
                "nickname": "主播",
                "signature": "签名",
                "web_rid": "416144012050",
                "avatar_thumb": {"url_list": ["https://ava"]}
            },
            "room_view_stats": {"display_value": 4321},
            "stream_url": {"flv_pull_url": {"FULL_HD1": "https://flv"}},
        })
        .as_object()
        .cloned()
        .expect("对象")
    }

    fn offline_room() -> Map<String, Value> {
        let mut room = live_room();
        room.insert("status".into(), json!(4));
        room
    }

    #[test]
    fn reflow_detail_marks_live_and_serializes_stream_url() {
        let site = DouyinSite::new();
        let detail =
            build_detail_from_reflow_room(&site, &live_room(), "7382735338101328680", "fallback");
        assert_eq!(detail.room_id, "416144012050", "优先 webRid");
        assert!(detail.status);
        assert_eq!(detail.online, 4321);
        assert_eq!(detail.cover, "https://cover");
        assert_eq!(detail.user_name, "主播");
        assert_eq!(detail.user_avatar, "https://ava");
        assert_eq!(detail.introduction.as_deref(), Some("签名"));
        assert_eq!(detail.notice.as_deref(), Some(""));
        assert_eq!(detail.url, "https://live.douyin.com/416144012050");

        let data = detail.data.expect("data 通道");
        let parsed = super::super::super::util::safe_json_object(&data).expect("应是对象");
        assert_eq!(
            parsed
                .get("flv_pull_url")
                .and_then(|v| v.get("FULL_HD1"))
                .and_then(Value::as_str),
            Some("https://flv")
        );
    }

    #[test]
    fn reflow_detail_falls_back_to_given_room_id_and_web_rid() {
        let site = DouyinSite::new();
        let mut room = live_room();
        // owner 无 web_rid（页面降级骨架）
        room.insert("owner".into(), json!({"nickname": "主播"}));
        let detail = build_detail_from_reflow_room(&site, &room, "7382735338101328680", "fb-web-rid");
        assert_eq!(detail.room_id, "fb-web-rid", "owner 缺 web_rid 时用传入的");
    }

    #[test]
    fn offline_room_zeroes_online_and_cover_but_keeps_owner_name() {
        let site = DouyinSite::new();
        let detail =
            build_detail_from_reflow_room(&site, &offline_room(), "1234567890123456789", "w");
        assert!(!detail.status);
        assert_eq!(detail.online, 0, "未播人气为 0");
        assert_eq!(detail.cover, "", "未播封面为空（Dart 同口径）");
        assert_eq!(detail.user_name, "主播", "未播仍显示主播名");
    }

    #[test]
    fn enter_detail_offline_falls_back_to_data_user() {
        let site = DouyinSite::new();
        let user = json!({"nickname": "用户昵称", "avatar_thumb": {"url_list": ["https://u"]}});
        let detail = build_detail_from_enter(
            &site,
            &offline_room(),
            user.as_object(),
            "416144012050",
            "7382735338101328680",
        );
        assert_eq!(detail.user_name, "用户昵称", "未播降级到 data.user.nickname");
        assert_eq!(detail.user_avatar, "https://u");
        assert_eq!(detail.room_id, "416144012050");
    }

    #[test]
    fn enter_detail_online_ignores_data_user() {
        let site = DouyinSite::new();
        let user = json!({"nickname": "不该出现"});
        let detail =
            build_detail_from_enter(&site, &live_room(), user.as_object(), "w", "r");
        assert_eq!(detail.user_name, "主播", "在播时只认 room.owner");
    }

    #[test]
    fn danmaku_data_roundtrips_with_snake_case_keys() {
        let site = DouyinSite::new();
        let detail =
            build_detail_from_reflow_room(&site, &live_room(), "7382735338101328680", "w");
        let raw = detail.danmaku_data.expect("danmaku_data");
        let parsed = DouyinDanmakuArgs::from_json(&raw).expect("应能反序列化");
        assert_eq!(parsed.schema_version, 1);
        assert_eq!(parsed.room_id, "7382735338101328680");
        assert_eq!(parsed.web_rid, "416144012050");
        assert_eq!(parsed.user_id.len(), 12, "观众 ID 是 12 位随机数字");
        assert!(parsed.user_id.chars().all(|c| c.is_ascii_digit()));
        for key in ["web_rid", "room_id", "user_id", "cookie"] {
            assert!(raw.contains(&format!("\"{key}\"")), "缺少键 {key}：{raw}");
        }
    }

    #[test]
    fn online_and_stream_helpers_tolerate_missing_fields() {
        let empty = Map::new();
        assert_eq!(online_of(&empty), 0);
        assert_eq!(text_of(None), "");
        let offline = stream_data_json(&empty, false).expect("未播");
        assert_eq!(offline.as_deref(), Some("{}"), "未播 data 是空对象");
        let no_stream = stream_data_json(&empty, true).expect("在播但无 stream_url");
        assert_eq!(no_stream.as_deref(), Some("{}"));
    }
}
