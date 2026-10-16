//! 直播间页面 HTML 链路（风控拦截 `web/enter` 时的兜底）。
//!
//! 对照 Dart `_getRoomDetailByWebRidHtml` + `_getRoomDataByHtml`
//! （`douyin_site.dart:747-800`、`881-907`）。
//!
//! 数据来自页面内嵌的转义 JSON（`{"state":{"appStore"...`），不是独立接口。
//! 页面链路与 API 链路的差异只在**未播时**的昵称/头像来源：页面额外提供
//! `roomStore.roomInfo.anchor`，于是已下播房间仍能显示主播信息（API 链路降级到
//! `data.user`）。
//!
//! 房间已下播 / 不存在时页面只有骨架（`roomInfo.room` 为空）—— Dart 曾在此抛
//! `NoSuchMethodError`，现已改为带 `detailExtra.errorPrompts` 原文的可读提示。

use crate::error::SliveError;
use crate::models::LiveRoomDetail;
use serde_json::Value;

use super::super::danmaku::args::DouyinDanmakuArgs;
use super::super::site::DouyinSite;
use super::super::util::{as_object, error_prompt, safe_json_decode};
use super::builder::{online_of, stream_data_json, text_of};
use super::ROOM_PAGE_URL;

/// 房间数据缺失时的统一提示（带服务端原文提示）。
fn missing_room_error(room_data: &Value) -> SliveError {
    let prompt = error_prompt(room_data);
    SliveError::decode(format!(
        "抖音直播间数据异常，未能获取房间信息{}",
        if prompt.is_empty() {
            String::new()
        } else {
            format!("（{prompt}）")
        }
    ))
}

/// 通过页面 HTML 获取详情。
pub(crate) async fn fetch_by_web_rid_html(
    site: &DouyinSite,
    web_rid: &str,
) -> Result<LiveRoomDetail, SliveError> {
    super::super::header::ensure_ttwid(site).await?;
    // Dart `_getRoomDataByHtml` 的前置：先取房间页 cookie（ttwid + __ac_nonce + msToken）。
    // 这条链路是 `web/enter` 被风控拦下时的兜底，最需要完整 cookie。
    let web_cookie = super::super::header::room_page_cookie(site, web_rid).await;
    let mut headers = super::super::header::base_headers();
    if !web_cookie.is_empty() {
        headers.push(("cookie".to_string(), web_cookie));
    }
    let html = site
        .get_text(&format!("{ROOM_PAGE_URL}{web_rid}"), Vec::new(), headers)
        .await?;

    let room_data =
        parse_room_page_state(&html).ok_or_else(|| missing_room_error(&Value::Null))?;
    let room = room_data
        .pointer("/roomStore/roomInfo/room")
        .and_then(|v| as_object(Some(v)))
        .filter(|r| !r.is_empty())
        .ok_or_else(|| missing_room_error(&room_data))?;

    let room_id = room
        .get("id_str")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    // 页面能给出真实的 user_unique_id；取不到才退回 12 位随机数
    let user_unique_id = room_data
        .pointer("/userStore/odin/user_unique_id")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| super::super::util::random_digits(12));

    let owner = as_object(room.get("owner"));
    let anchor = room_data
        .pointer("/roomStore/roomInfo/anchor")
        .and_then(|v| as_object(Some(v)));
    let room_status = crate::util::as_i32(room.get("status")).unwrap_or(0) == 2;

    let (user_name, user_avatar) = if room_status {
        (
            owner
                .and_then(|o| o.get("nickname"))
                .map(crate::util::value_to_string)
                .unwrap_or_default(),
            super::super::util::first_url(owner.and_then(|o| o.get("avatar_thumb"))),
        )
    } else {
        (
            anchor
                .and_then(|a| a.get("nickname"))
                .map(crate::util::value_to_string)
                .unwrap_or_default(),
            super::super::util::first_url(anchor.and_then(|a| a.get("avatar_thumb"))),
        )
    };

    Ok(LiveRoomDetail {
        room_id: web_rid.to_string(),
        title: text_of(room.get("title")),
        cover: if room_status {
            super::super::util::first_url(room.get("cover"))
        } else {
            String::new()
        },
        user_name,
        user_avatar,
        online: if room_status { online_of(room) } else { 0 },
        introduction: Some(
            owner
                .and_then(|o| o.get("signature"))
                .map(crate::util::value_to_string)
                .unwrap_or_default(),
        ),
        notice: Some(String::new()),
        status: room_status,
        data: stream_data_json(room, room_status)?,
        danmaku_data: Some(
            DouyinDanmakuArgs::new(
                web_rid.to_string(),
                room_id,
                user_unique_id,
                site.header_cookie(),
            )
            .to_json()?,
        ),
        is_record: false,
        url: format!("{ROOM_PAGE_URL}{web_rid}"),
    })
}

/// 从直播间页面 HTML 解析内嵌 `state`（转义 JSON）。
///
/// 与 `categories` 同源的坑（故同样**不**照抄 Dart 的正则截取）：
/// Dart 是「正则截到 `]\n` → 去掉 `]\n` → decode」，页面若不含字面 `]\n`
/// 就整页失败。这里改为「定位 `\"state\":{` → 从 `{` 起做**括号配平**扫描截出对象原文
/// → 反转义 → 解析」，对截断形态更耐受，且不受结尾标记位置影响。
fn parse_room_page_state(html: &str) -> Option<Value> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r#"\{\\"state\\":\{"#)
            .expect("房间页内嵌数据正则是常量，编译期即合法")
    });
    let start = re.find(html)?.end() - 1; // 指向 `{`
    let end = super::super::categories::scan_json_object_end(html.as_bytes(), start)?;
    safe_json_decode(&super::super::categories::unescape(&html[start..end]))
}

#[cfg(test)]
mod tests {
    use super::*;

    use serde_json::json;

    /// 构造与抖音直播间页同构的转义内嵌文本。
    ///
    /// 真实页面里整段 `{"state":{...}}` 被 JS 字符串转义（`"` -> `\"`），
    /// 所以夹具也必须是**单一转义 JSON 串**，不能在前面再手工拼一段
    /// `{\"state\":{\"appStore\"...` —— 那会拼出两个并列的 JSON 对象，
    /// 括号配平扫到的是第一个（不完整）对象，必然解析失败。
    fn page_html(state: &Value) -> String {
        let inner = serde_json::to_string(&json!({"state": state})).expect("序列化");
        let escaped = inner.replace('\\', "\\\\").replace('"', "\\\"");
        format!("<html><script>{escaped}</script></html>")
    }

    fn state_payload() -> Value {
        json!({
            "roomStore": {"roomInfo": {
                "room": {
                    "id_str": "7382735338101328680",
                    "title": "页面直播间",
                    "status": 2,
                    "owner": {"nickname": "主播", "signature": "签名",
                              "avatar_thumb": {"url_list": ["https://a"]}},
                    "room_view_stats": {"display_value": 7},
                    "stream_url": {"hls_pull_url_map": {}},
                },
                "anchor": {"nickname": "主播(离线态)", "avatar_thumb": {"url_list": ["https://b"]}},
            }},
            "userStore": {"odin": {"user_unique_id": "1234567890123"}},
        })
    }

    #[test]
    fn parses_embedded_state() {
        let parsed = parse_room_page_state(&page_html(&state_payload())).expect("应能解析");
        assert_eq!(
            parsed
                .pointer("/roomStore/roomInfo/room/title")
                .and_then(Value::as_str),
            Some("页面直播间")
        );
    }

    #[test]
    fn returns_none_on_unexpected_html() {
        assert!(parse_room_page_state("<html>无内嵌数据</html>").is_none());
    }

    #[test]
    fn missing_room_error_includes_server_prompt() {
        let data = json!({"detailExtra": {"errorPrompts": ["房间不存在"]}});
        let msg = missing_room_error(&data).to_string();
        assert!(msg.contains("未能获取房间信息"), "实际 {msg}");
        assert!(msg.contains("房间不存在"), "应带服务端原文提示：{msg}");

        let no_prompt = missing_room_error(&json!({})).to_string();
        assert!(no_prompt.ends_with("未能获取房间信息"), "无提示时不加括号：{no_prompt}");
    }

    #[test]
    fn missing_room_error_on_unparsable_page_has_no_parens() {
        let msg = missing_room_error(&Value::Null).to_string();
        assert!(msg.contains("未能获取房间信息"));
        assert!(!msg.contains('（'), "无 detailExtra 时不应留空括号：{msg}");
    }
}
