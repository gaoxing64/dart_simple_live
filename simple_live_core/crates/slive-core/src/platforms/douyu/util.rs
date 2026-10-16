//! 斗鱼解析工具：房间列表项、人气数、HTML 实体反转义（纯函数，无业务副作用）。

use serde_json::Value;

use crate::models::LiveRoomItem;
use crate::util::{as_i32, value_to_string};

/// 取字段为字符串（缺失/空 -> 空串），对齐 Dart `.toString()` 的兜底口径。
pub(crate) fn value_or_empty(value: &Value, field: &str) -> String {
    value.get(field).map(value_to_string).unwrap_or_default()
}

/// 从 `rl` 列表项构造 [`LiveRoomItem`]（`rid/rn/nn/ol/rs16`）。
///
/// 对齐 `douyu_site.dart:73-79`：字段缺失一律走 `.toString()` 的空串/0 口径，不抛错。
pub(crate) fn room_item(value: &Value) -> LiveRoomItem {
    LiveRoomItem {
        room_id: value_to_string(value.get("rid").unwrap_or(&Value::Null)),
        title: value_to_string(value.get("rn").unwrap_or(&Value::Null)),
        cover: value_to_string(value.get("rs16").unwrap_or(&Value::Null)),
        user_name: value_to_string(value.get("nn").unwrap_or(&Value::Null)),
        online: as_i32(value.get("ol")).unwrap_or(0),
    }
}

/// 斗鱼房间列表项的「是否直播」过滤（`type == 1`，对齐两处 `if (item["type"] != 1) continue`）。
pub(crate) fn is_live_room(value: &Value) -> bool {
    as_i32(value.get("type")) == Some(1)
}

/// 解析斗鱼人气串：`"1.2万"` -> `12000`；无法解析 -> `-999`（对齐 `parseHotNum`）。
pub(crate) fn parse_hot_num(raw: &str) -> i32 {
    let trimmed = raw.trim();
    let has_wan = trimmed.contains('万');
    let numeric = trimmed.replace('万', "");
    match numeric.parse::<f64>() {
        Ok(value) => {
            let scaled = if has_wan { value * 10000.0 } else { value };
            scaled.round() as i32
        }
        Err(_) => -999,
    }
}

/// HTML 实体反转义（对齐 Dart `HtmlUnescape().convert`）。
///
/// 只覆盖斗鱼 `rtmp_live` 实际会出现的实体：`&amp; &lt; &gt; &quot; &#39; &apos;` 与数字实体。
/// **未覆盖的实体保持原样**（与 Dart 的全量表不同，此处按实际用到的子集实现，见映射文档差异登记）。
pub(crate) fn html_unescape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let bytes: Vec<char> = input.chars().collect();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] != '&' {
            out.push(bytes[index]);
            index += 1;
            continue;
        }
        match bytes[index..].iter().position(|c| *c == ';') {
            Some(offset) if offset <= 10 => {
                let entity: String = bytes[index + 1..index + offset].iter().collect();
                match decode_entity(&entity) {
                    Some(decoded) => {
                        out.push(decoded);
                        index += offset + 1;
                    }
                    None => {
                        out.push(bytes[index]);
                        index += 1;
                    }
                }
            }
            _ => {
                out.push(bytes[index]);
                index += 1;
            }
        }
    }
    out
}

fn decode_entity(entity: &str) -> Option<char> {
    match entity {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        "nbsp" => Some(' '),
        other => {
            let digits = other.strip_prefix('#')?;
            let code = if let Some(hex) = digits.strip_prefix('x').or_else(|| digits.strip_prefix('X')) {
                u32::from_str_radix(hex, 16).ok()?
            } else {
                digits.parse::<u32>().ok()?
            };
            char::from_u32(code)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn room_item_maps_douyu_fields() {
        let item = room_item(&json!({
            "rid": 999, "rn": "标题", "nn": "主播", "ol": 1234, "rs16": "http://c.jpg"
        }));
        assert_eq!(item.room_id, "999");
        assert_eq!(item.title, "标题");
        assert_eq!(item.user_name, "主播");
        assert_eq!(item.online, 1234);
        assert_eq!(item.cover, "http://c.jpg");
        assert!(is_live_room(&json!({"type": 1})));
        assert!(!is_live_room(&json!({"type": 0})));
    }

    #[test]
    fn missing_fields_degrade_to_empty_and_zero() {
        let item = room_item(&json!({}));
        assert_eq!(item.room_id, "");
        assert_eq!(item.online, 0);
        assert!(!is_live_room(&json!({})), "缺 type 一律不判为直播");
    }

    #[test]
    fn hot_num_handles_wan_and_invalid() {
        assert_eq!(parse_hot_num("1.2万"), 12000);
        assert_eq!(parse_hot_num("1234"), 1234);
        assert_eq!(parse_hot_num("0.5万"), 5000);
        assert_eq!(parse_hot_num("abc"), -999, "无法解析对齐 Dart 的 -999");
        assert_eq!(parse_hot_num(""), -999);
    }

    #[test]
    fn html_unescape_covers_used_entities() {
        assert_eq!(html_unescape("a&amp;b"), "a&b");
        assert_eq!(html_unescape("&lt;tag&gt;"), "<tag>");
        assert_eq!(html_unescape("it&#39;s"), "it's");
        assert_eq!(html_unescape("&#x4E2D;"), "中");
        assert_eq!(html_unescape("plain"), "plain");
        assert_eq!(html_unescape("&unknown;"), "&unknown;", "未知实体原样保留");
        assert_eq!(html_unescape("a&b"), "a&b", "非实体的 & 不吞字符");
        assert_eq!(html_unescape("100%&amp;"), "100%&");
    }
}