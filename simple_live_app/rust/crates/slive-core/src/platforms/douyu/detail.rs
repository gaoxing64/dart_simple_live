//! F-06 房间详情 / F-09 直播状态（对照 `douyu_site.dart:218-237` / `:336-340` / `:274-288`）。
//!
//! 斗鱼详情是**单请求**（`betard/{roomId}` 一次取全），与 B站的两步不同 —— 以 Dart 为准。
//! `betard` 在部分响应头下会返回「JSON 字符串套 JSON」，此处的双层解析对齐 Dart 的
//! `if (result is String) json.decode(result)["room"]`。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::LiveRoomDetail;
use crate::util::value_to_string;

use super::header::{room_info_header, DOUYU_ORIGIN};
use super::site::DouyuSite;

/// 回放房间的标题前缀（Dart 用它与 `videoLoop` 一起判定「非直播」）。
const REPLAY_TITLE_PREFIX: &str = "【回放】";

/// 取 `betard` 响应里的 `room` 对象。
pub(crate) async fn fetch_room_info(site: &DouyuSite, room_id: &str) -> Result<Value, SliveError> {
    let url = format!("{DOUYU_ORIGIN}/betard/{room_id}");
    let value = site
        .get_json_with(url, Vec::new(), room_info_header(room_id))
        .await?;
    let root = match value {
        // 双层编码：服务端把 JSON 放在了 JSON 字符串里。
        Value::String(inner) => serde_json::from_str::<Value>(&inner)
            .map_err(|e| SliveError::decode(format!("房间信息二次解析失败: {e}")))?,
        other => other,
    };
    root.get("room")
        .cloned()
        .ok_or_else(|| SliveError::decode(format!("房间 {room_id} 不存在（响应缺 room 字段）")))
}

/// 是否在播：`show_status == 1 && videoLoop != 1 && !标题以【回放】开头`（对齐 Dart 三元表达式）。
pub(crate) fn is_room_live(room: &Value) -> bool {
    let show_status = room
        .get("show_status")
        .map(value_to_string)
        .unwrap_or_default();
    let video_loop = room.get("videoLoop").map(value_to_string).unwrap_or_default();
    let title = room.get("room_name").map(value_to_string).unwrap_or_default();
    show_status == "1" && video_loop != "1" && !title.starts_with(REPLAY_TITLE_PREFIX)
}

/// F-06 房间详情。
pub(crate) async fn fetch(
    site: &DouyuSite,
    room_id: &str,
) -> Result<LiveRoomDetail, SliveError> {
    let room = fetch_room_info(site, room_id).await?;
    let name = room.get("room_name").map(value_to_string).unwrap_or_default();
    let video_loop = room.get("videoLoop").and_then(Value::as_i64).unwrap_or(0);
    // Dart: `int.tryParse(room_biz_all.hot)` —— 缺失/非数字 -> 0
    let hot = room
        .pointer("/room_biz_all/hot")
        .map(value_to_string)
        .and_then(|raw| raw.trim().parse::<i32>().ok())
        .unwrap_or(0);

    Ok(LiveRoomDetail {
        // 注意：Dart 用的是**响应里的** room_id，而 url 用的是**请求的** roomId
        // （虚拟房间 / 短号场景两者不同），此处照搬。
        room_id: room.get("room_id").map(value_to_string).unwrap_or_default(),
        title: name,
        cover: room.get("room_pic").map(value_to_string).unwrap_or_default(),
        user_name: room.get("owner_name").map(value_to_string).unwrap_or_default(),
        user_avatar: room
            .get("owner_avatar")
            .map(value_to_string)
            .unwrap_or_default(),
        online: hot,
        introduction: room.get("show_details").map(value_to_string),
        // Dart 固定传空串（非 null），保持一致。
        notice: Some(String::new()),
        status: is_room_live(&room),
        // Dart: data = ""，danmakuData = room_id（斗鱼弹幕只需房间号）
        data: Some(String::new()),
        danmaku_data: Some(
            room.get("room_id")
                .map(value_to_string)
                .unwrap_or_default(),
        ),
        is_record: video_loop == 1,
        url: format!("{DOUYU_ORIGIN}/{room_id}"),
    })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn room_of(show_status: i32, video_loop: i32, title: &str) -> Value {
        json!({
            "room_id": 999,
            "room_name": title,
            "show_status": show_status,
            "videoLoop": video_loop
        })
    }

    #[test]
    fn live_predicate_matches_dart_triple_condition() {
        assert!(is_room_live(&room_of(1, 0, "正常直播")));
        assert!(!is_room_live(&room_of(0, 0, "未开播")), "show_status!=1 -> 未开播");
        assert!(!is_room_live(&room_of(1, 1, "录制中")), "videoLoop==1 -> 录播");
        assert!(
            !is_room_live(&room_of(1, 0, "【回放】昨天的直播")),
            "标题含【回放】-> 未开播"
        );
    }

    #[test]
    fn missing_show_status_is_not_live() {
        assert!(!is_room_live(&json!({})), "缺字段一律判未开播，不能默认在播");
    }
}