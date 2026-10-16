//! B站解析辅助（私有）。
//!
//! 与 crate 级 [`crate::util`] 区分：本模块只放 B站响应解析用到的字符串/字段取值。

use once_cell::sync::Lazy;
use regex::Regex;
use serde_json::Value;

use crate::models::LiveRoomItem;
use crate::util::{as_i32, value_to_string};

static EM_TAG: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"<.*?em.*?>").expect("em 正则字面量合法"));

/// 去除标题/昵称中的 `<em>` 高亮标签（对齐 Dart `RegExp(r"<.*?em.*?>")`）。
pub(crate) fn strip_em_tags(text: &str) -> String {
    EM_TAG.replace_all(text, "").into_owned()
}

/// 取直接键的字符串值（缺失 -> 空串）。
pub(crate) fn text(item: &Value, key: &str) -> String {
    item.get(key).map(value_to_string).unwrap_or_default()
}

/// 取 JSON Pointer 指向的字符串值（缺失 -> 空串）。
pub(crate) fn text_ptr(value: &Value, pointer: &str) -> String {
    value.pointer(pointer).map(value_to_string).unwrap_or_default()
}

/// 由房间列表项 + 已处理的封面构造 [`LiveRoomItem`]。
pub(crate) fn room_item(item: &Value, cover: String) -> LiveRoomItem {
    LiveRoomItem {
        room_id: text(item, "roomid"),
        title: text(item, "title"),
        cover,
        user_name: text(item, "uname"),
        online: as_i32(item.get("online")).unwrap_or(0),
    }
}

/// 解析 `/data/list` 形态的房间列表（封面统一追加 `@400w.jpg`）。
pub(crate) fn room_items(value: &Value, pointer: &str) -> Vec<LiveRoomItem> {
    crate::util::array_at(value, pointer)
        .iter()
        .map(|item| room_item(item, format!("{}@400w.jpg", text(item, "cover"))))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn strip_em_removes_highlight_tags() {
        assert_eq!(strip_em_tags("<em class=\"keyword\">LOL</em>直播"), "LOL直播");
        assert_eq!(strip_em_tags("无标签"), "无标签");
    }

    #[test]
    fn room_item_reads_expected_fields() {
        let item = json!({"roomid": 6, "title": "t", "uname": "u", "online": "123"});
        let parsed = room_item(&item, "c@400w.jpg".to_string());
        assert_eq!(parsed.room_id, "6");
        assert_eq!(parsed.online, 123, "online 应可解析数字字符串");
        assert_eq!(parsed.cover, "c@400w.jpg");
    }
}
