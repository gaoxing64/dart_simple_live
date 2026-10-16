//! 纯工具函数（无业务、无副作用）。
//!
//! 提供 JSON 取值（对齐 Dart `asT<T>` / `.toString()` 的健壮化口径）与 URL query 编解码。
//! URL 编码严格对齐 Dart `Uri.encodeQueryComponent`（unreserved = `A-Za-z0-9-._~`，
//! 空格 -> `+`，其余按 UTF-8 百分号编码），以保证 wbi 签名参数编码一致。

use serde_json::Value;

/// `Value` -> `String`，对齐 Dart `.toString()` 的常见口径。
///
/// 差异说明：`null` 渲染为空串（Dart `null.toString()` 为 `"null"`）；仅在畸形载荷下不同，
/// 正常响应不受影响（已在回传中标注）。
pub fn value_to_string(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        other => other.to_string(),
    }
}

/// `Option<&Value>` -> `Option<String>`（仅字符串）。
pub fn as_string(value: Option<&Value>) -> Option<String> {
    value.and_then(|v| v.as_str()).map(str::to_string)
}

/// `Option<&Value>` -> `Option<i32>`（接受数字与可解析字符串）。
pub fn as_i32(value: Option<&Value>) -> Option<i32> {
    as_i64(value).and_then(|n| i32::try_from(n).ok())
}

/// `Option<&Value>` -> `Option<i64>`（接受数字与可解析字符串）。
pub fn as_i64(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::String(s) => s.trim().parse::<i64>().ok(),
        _ => None,
    }
}

/// 宽松布尔归一化（G-4）：接受 `bool` 与 `int`（非 0 为 true）/ 字符串。
///
/// 背景：`search_anchors` 的 `is_live` 服务端可能返 int；Dart 现状裸赋 `bool`，
/// 服务端返 int 即抛 TypeError —— 本实现显式归一化，**不照抄**该缺陷。
pub fn as_bool_lenient(value: Option<&Value>) -> Option<bool> {
    match value? {
        Value::Bool(b) => Some(*b),
        Value::Number(n) => Some(n.as_i64().unwrap_or(0) != 0),
        Value::String(s) => match s.trim() {
            "true" | "1" => Some(true),
            "false" | "0" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

/// 取 JSON Pointer 指向的数组；缺失/类型不符 -> 空切片。
pub fn array_at<'a>(value: &'a Value, pointer: &str) -> &'a [Value] {
    value
        .pointer(pointer)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[])
}

/// 取 JSON Pointer 指向的对象。
pub fn object_at<'a>(value: &'a Value, pointer: &str) -> Option<&'a serde_json::Map<String, Value>> {
    value.pointer(pointer).and_then(Value::as_object)
}

/// 解析 URL 中的 query 为键值对（不做百分号解码，保持 Dart `Uri.parse(url).queryParameters` 的可用子集）。
pub fn parse_query(url: &str) -> Vec<(String, String)> {
    let Some((_, query)) = url.split_once('?') else {
        return Vec::new();
    };
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((k, v)) => (k.to_string(), v.to_string()),
            None => (pair.to_string(), String::new()),
        })
        .collect()
}

/// 对齐 Dart `Uri.encodeQueryComponent`：保留 `A-Za-z0-9-._~`，空格 -> `+`，其余 %XX（大写）。
pub fn encode_query_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*byte as char)
            }
            b' ' => out.push('+'),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn as_bool_lenient_normalizes_int_and_bool() {
        assert_eq!(as_bool_lenient(Some(&json!(true))), Some(true));
        assert_eq!(as_bool_lenient(Some(&json!(1))), Some(true));
        assert_eq!(as_bool_lenient(Some(&json!(0))), Some(false));
        assert_eq!(as_bool_lenient(Some(&json!("1"))), Some(true));
        assert_eq!(as_bool_lenient(None), None);
    }

    #[test]
    fn encode_query_component_matches_dart_unreserved_set() {
        assert_eq!(encode_query_component("room_id"), "room_id");
        assert_eq!(encode_query_component("a b"), "a+b");
        assert_eq!(encode_query_component("a&b=c"), "a%26b%3Dc");
        assert_eq!(encode_query_component("冲"), "%E5%86%B2");
    }

    #[test]
    fn parse_query_keeps_empty_values() {
        let q = parse_query("https://x/y?a=1&b=&c");
        assert_eq!(
            q,
            vec![
                ("a".to_string(), "1".to_string()),
                ("b".to_string(), String::new()),
                ("c".to_string(), String::new()),
            ]
        );
    }
}
