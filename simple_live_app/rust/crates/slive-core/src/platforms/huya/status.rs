//! F-09 直播状态（对照 `huya_site.dart:484-505`）。
//!
//! 与 F-06 详情同源（同一房间页），但**只取 `TT_ROOM_DATA`**：
//! `state == "ON" && isReplay == false` 即在播。解析失败/缺字段 -> `false`
//! （对齐 Dart：catch 后返回 false，不抛错）。

use once_cell::sync::Lazy;
use regex::Regex;
use serde_json::Value;

use crate::error::SliveError;

use super::common::{BASE_URL, ROOM_DATA_REGEX};
use super::site::HuyaSite;

static ROOM_DATA: Lazy<Regex> =
    Lazy::new(|| Regex::new(ROOM_DATA_REGEX).expect("房间数据正则字面量合法"));

/// F-09 直播状态。
pub(crate) async fn fetch(site: &HuyaSite, room_id: &str) -> Result<bool, SliveError> {
    let text = site
        .get_text(&format!("{BASE_URL}/{room_id}"), Vec::new())
        .await?;
    Ok(parse_live_status(&text))
}

/// 从房间页文本解析在播状态；缺 `TT_ROOM_DATA` 或非法 -> `false`。
pub(crate) fn parse_live_status(page: &str) -> bool {
    extract_room_data(page)
        .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
        .map(|value| is_live(&value))
        .unwrap_or(false)
}

/// `state == "ON" && isReplay == false`。
pub(crate) fn is_live(room_data: &Value) -> bool {
    room_data.get("state").and_then(Value::as_str) == Some("ON")
        && room_data.get("isReplay").and_then(Value::as_bool) == Some(false)
}

/// 抓取并返回 `TT_ROOM_DATA` 的 JSON 文本（已剥掉 `var TT_ROOM_DATA = ` 前缀）。
pub(crate) fn extract_room_data(page: &str) -> Option<String> {
    let captures = ROOM_DATA.captures(page)?;
    captures.get(1).map(|m| m.as_str().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn page_with_room_data(json: &str) -> String {
        format!("<html><script>var TT_ROOM_DATA = {json};</script></html>")
    }

    #[test]
    fn live_room_reports_on() {
        let page = page_with_room_data(r#"{"state":"ON","isReplay":false}"#);
        assert!(parse_live_status(&page));
    }

    #[test]
    fn replay_or_offline_reports_off() {
        assert!(!parse_live_status(&page_with_room_data(
            r#"{"state":"ON","isReplay":true}"#
        )));
        assert!(!parse_live_status(&page_with_room_data(
            r#"{"state":"OFF","isReplay":false}"#
        )));
    }

    #[test]
    fn missing_block_reports_off() {
        assert!(!parse_live_status("<html>404</html>"));
    }

    #[test]
    fn malformed_json_reports_off() {
        assert!(!parse_live_status(&page_with_room_data("{not json")));
    }

    #[test]
    fn missing_fields_report_off() {
        assert!(!parse_live_status(&page_with_room_data(r#"{"state":"ON"}"#)));
    }

    #[test]
    fn extract_returns_json_without_prefix() {
        let raw = extract_room_data(&page_with_room_data(r#"{"state":"ON"}"#)).expect("抓到");
        assert_eq!(raw, r#"{"state":"ON"}"#);
    }

    #[test]
    fn multiline_json_is_captured() {
        let page = page_with_room_data("{\n  \"state\": \"ON\",\n  \"isReplay\": false\n}");
        assert!(parse_live_status(&page), "多行 JSON 也要能抓");
    }
}