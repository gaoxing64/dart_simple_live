//! `reflow/info` 链路（19 位 roomId；连麦房间唯一可靠的来源）。
//!
//! 对照 Dart `_getRoomDataByRoomId` / `_getReflowRoom` / `_getWebRid`
//! （`douyin_site.dart:535-549`、`726-742`、`930-946`）。
//!
//! 两条子路径：
//! - [`fetch_by_room_id`]：roomId 直连。`status == 4` 说明该 roomId 已失效
//!   （主播重开播换了房间号），此时改用房间里的 `web_rid` 重新查询；
//! - [`fetch_reflow_room`]：给 `web/enter` 的降级骨架补救用，**取不到返回 `None`
//!   而不抛**（让上层继续走正常分支，而不是把整页打成错误）。

use crate::error::SliveError;
use crate::models::LiveRoomDetail;

use super::super::site::DouyinSite;
use super::super::util::as_object;
use super::builder::build_detail_from_reflow_room;
use super::fetch_by_web_rid;

/// `reflow/info` 接口（roomId -> 房间；连麦房间唯一可靠的来源）。
pub const REFLOW_INFO_URL: &str = "https://webcast.amemv.com/webcast/room/reflow/info/";
/// `reflow/` 页面（roomId -> webRid 的正则兜底）。
pub const REFLOW_PAGE_URL: &str = "https://webcast.amemv.com/douyin/webcast/reflow/";
/// `room.status == 4` 表示该 roomId 已结束（主播重开播换了房间号）。
const STATUS_ENDED: i32 = 4;

/// 通过 19 位 roomId 获取详情。
pub(crate) async fn fetch_by_room_id(
    site: &DouyinSite,
    room_id: &str,
) -> Result<LiveRoomDetail, SliveError> {
    let room_data = fetch_room_data_by_room_id(site, room_id).await?;
    let room = room_object(&room_data).ok_or_else(|| {
        SliveError::decode("抖音直播间数据异常，未能获取房间信息".to_string())
    })?;
    let web_rid = as_object(room.get("owner"))
        .and_then(|o| o.get("web_rid"))
        .map(crate::util::value_to_string)
        .unwrap_or_default();

    // roomId 是一次性的：状态为「已结束」时改用 webRid 重新查询
    if crate::util::as_i32(room.get("status")).unwrap_or(0) == STATUS_ENDED {
        if web_rid.is_empty() {
            return Err(SliveError::decode(
                "抖音直播间数据异常，未能获取主播 webRid".to_string(),
            ));
        }
        return fetch_by_web_rid(site, &web_rid).await;
    }

    super::super::header::ensure_ttwid(site).await?;
    Ok(build_detail_from_reflow_room(
        site,
        &room,
        room_id,
        &web_rid,
    ))
}

/// 按 roomId 从 `reflow/info` 取房间数据（取不到返回 `None`，下播只给骨架）。
pub(crate) async fn fetch_reflow_room(
    site: &DouyinSite,
    room_id: &str,
) -> Option<serde_json::Map<String, serde_json::Value>> {
    match fetch_room_data_by_room_id(site, room_id).await {
        Ok(room_data) => room_object(&room_data),
        Err(e) => {
            log::warn!("抖音 reflow/info 查询失败（按无房间处理）: {e}");
            None
        }
    }
}

/// roomId -> webRid（Dart `_getWebRid`：正则抓页面里的 `webRid`，抓不到回退原值）。
pub(crate) async fn resolve_web_rid(site: &DouyinSite, room_id: &str) -> String {
    let url = format!("{REFLOW_PAGE_URL}{room_id}");
    match site.get_text(&url, Vec::new(), Vec::new()).await {
        Ok(html) => match web_rid_re()
            .captures(&html)
            .and_then(|c| c.get(1))
            .map(|m| m.as_str().to_string())
        {
            Some(found) if !found.is_empty() => found,
            _ => room_id.to_string(),
        },
        Err(e) => {
            log::warn!("抖音 webRid 反查失败（沿用原 roomId）: {e}");
            room_id.to_string()
        }
    }
}

/// 抓 `reflow/` 页面里的 `webRid`（Dart 的字面正则，逐字符转义到 Rust）。
fn web_rid_re() -> &'static regex::Regex {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    RE.get_or_init(|| {
        regex::Regex::new(r#"\\"webRid\\":\\"([^\\"]+)\\""#)
            .expect("webRid 正则是常量，编译期即合法")
    })
}

/// `reflow/info` 的 query 参数（与 Dart `_getRoomDataByRoomId` 逐键一致）。
///
/// ⚠️ 这个接口**不过** `buildRequestUrl`（Dart 直接 `getJson` + `queryParameters`），
/// 所以**没有** a_bogus / msToken / 那 7 个公共键 —— 加了反而与 Dart 不一致。
/// `app_id=6383` 是它的 aid 等价物，由 `reflow_params_carry_app_id` 钉住。
pub fn reflow_params(room_id: &str) -> Vec<(String, String)> {
    vec![
        ("type_id".to_string(), "0".to_string()),
        ("live_id".to_string(), "1".to_string()),
        ("room_id".to_string(), room_id.to_string()),
        ("sec_user_id".to_string(), String::new()),
        ("version_code".to_string(), "99.99.99".to_string()),
        ("app_id".to_string(), "6383".to_string()),
    ]
}

/// `reflow/info` 请求（roomId 链路唯一的 HTTP 调用）。
async fn fetch_room_data_by_room_id(
    site: &DouyinSite,
    room_id: &str,
) -> Result<serde_json::Value, SliveError> {
    site.get_json(
        REFLOW_INFO_URL,
        reflow_params(room_id),
        super::super::header::build_header(site),
    )
    .await
}

/// `reflow/info` 响应里的 `data.room`；缺失/空 -> `None`（下播只给骨架）。
pub(crate) fn room_object(
    room_data: &serde_json::Value,
) -> Option<serde_json::Map<String, serde_json::Value>> {
    room_data
        .pointer("/data/room")
        .and_then(|v| as_object(Some(v)))
        .filter(|r| !r.is_empty())
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn room_object_returns_none_for_offline_skeleton() {
        assert!(room_object(&json!({"data": {"room": {}}})).is_none());
        assert!(room_object(&json!({"data": {}})).is_none());
        assert!(room_object(&json!({})).is_none());
        assert!(room_object(&json!("not-object")).is_none());
        assert!(room_object(&json!({"data": {"room": {"id_str": "1"}}})).is_some());
    }

    #[test]
    fn reflow_params_carry_app_id_and_exact_dart_keys() {
        let params = reflow_params("7382735338101328680");
        let map: std::collections::HashMap<_, _> = params.iter().cloned().collect();
        // Dart 的 6 个键，一个不多一个不少
        assert_eq!(params.len(), 6, "reflow 参数表必须与 Dart 完全一致");
        assert_eq!(map["type_id"], "0");
        assert_eq!(map["live_id"], "1");
        assert_eq!(map["room_id"], "7382735338101328680");
        assert_eq!(map["sec_user_id"], "");
        assert_eq!(map["version_code"], "99.99.99");
        assert_eq!(
            map["app_id"], "6383",
            "app_id 是这个接口的 aid 等价物，缺失会被服务端拒"
        );
        // 该接口不走 buildRequestUrl，故不应出现这些键
        for absent in ["compress", "device_platform", "msToken", "a_bogus", "browser_name"] {
            assert!(
                !map.contains_key(absent),
                "reflow 不该带 {absent}（Dart 未过 buildRequestUrl）"
            );
        }
    }

    #[test]
    fn web_rid_regex_captures_escaped_page_payload() {
        let html = r#"{\"mysteryMan\":1,\"webRid\":\"416144012050\",\"desensitizedNickname":"x"}"#;
        let got = web_rid_re()
            .captures(html)
            .and_then(|c| c.get(1))
            .map(|m| m.as_str().to_string());
        assert_eq!(got.as_deref(), Some("416144012050"));
    }

    #[test]
    fn web_rid_regex_returns_none_when_absent() {
        assert!(web_rid_re().captures(r#"{\"other\":1}"#).is_none());
    }
}
