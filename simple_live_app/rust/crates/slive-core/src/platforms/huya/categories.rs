//! F-01 分类与子分类（对照 `huya_site.dart:49-96`）。
//!
//! 分类 A 列表是**硬编码 4 个大类**（`1` 网游 / `2` 单机 / `8` 娱乐 / `3` 手游），
//! 子分类逐个请求 `live.cdn.huya.com/liveconfig/game/bussLive` —— 共 4 次串行请求，
//! 与 Dart 完全一致（§9：不得引入额外串行往返）。
//!
//! `gid` 的三分支处理（对齐 Dart：Map / double / int / 其他）是服务端历史遗留，
//! 原样保留以防行为漂移。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveCategory, LiveSubCategory};

use super::common::SUB_CATEGORY_URL;
use super::site::HuyaSite;

/// 硬编码大类（`(id, name)`，顺序与 Dart 一致）。
const ROOT_CATEGORIES: [(&str, &str); 4] = [
    ("1", "网游"),
    ("2", "单机"),
    ("8", "娱乐"),
    ("3", "手游"),
];

/// F-01 分类 A 列表（含各分类的子分类）。
pub(crate) async fn fetch(site: &HuyaSite) -> Result<Vec<LiveCategory>, SliveError> {
    let mut out = Vec::with_capacity(ROOT_CATEGORIES.len());
    // Dart：串行 for 循环（非 Future.wait），顺序请求以保持与 Dart 相同的请求时序。
    for (id, name) in ROOT_CATEGORIES {
        let children = fetch_sub(site, id).await?;
        out.push(LiveCategory {
            id: id.to_string(),
            name: name.to_string(),
            children,
        });
    }
    Ok(out)
}

/// F-01b 子分类列表。
pub(crate) async fn fetch_sub(
    site: &HuyaSite,
    parent_id: &str,
) -> Result<Vec<LiveSubCategory>, SliveError> {
    let value = site
        .get_json(
            SUB_CATEGORY_URL,
            vec![("bussType".to_string(), parent_id.to_string())],
        )
        .await?;
    let items = crate::util::array_at(&value, "/data");
    Ok(items
        .iter()
        .map(|item| LiveSubCategory {
            id: parse_gid(item),
            name: text(item, "gameFullName"),
            parent_id: parent_id.to_string(),
            pic: Some(format!(
                "https://huyaimg.msstatic.com/cdnimage/game/{}-MS.jpg",
                parse_gid(item)
            )),
        })
        .collect())
}

/// `gid` 四分支解析（对齐 Dart `getSubCategories`）。
///
/// ⚠️ `gid == null` 时 Dart 走 `else` 分支的 `item["gid"].toString()`，得到字符串
/// `"null"`（**不是**空串）—— 故 `pic` 会拼成 `.../null-MS.jpg`。
/// 该"看似 bug"的服务端行为必须原样保留（改了会导致分类列表少一项 / 图 404）。
fn parse_gid(item: &Value) -> String {
    match item.get("gid") {
        // `{"gid": {"value": "1,2,3"}}` -> 取第一段
        Some(Value::Object(map)) => map
            .get("value")
            .map(crate::util::value_to_string)
            .unwrap_or_default()
            .split(',')
            .next()
            .unwrap_or_default()
            .to_string(),
        // JSON 里 `gid` 是 double 时取整（避免 "1.0"）
        Some(Value::Number(number)) => match number.as_i64() {
            Some(int) => int.to_string(),
            None => number.as_f64().map(|f| (f as i64).to_string()).unwrap_or_default(),
        },
        // `null` 也走 Dart 的 `.toString()` -> 字面量 "null"
        // （`value_to_string` 会把 Null 映射成空串，故必须单独一支）
        Some(Value::Null) => "null".to_string(),
        // 字符串按 Dart `.toString()` 取**内容**（不带引号）；
        // `serde_json::Value` 的 `Display` 会给 String 加引号，故必须走 `value_to_string`。
        Some(other) => crate::util::value_to_string(other),
        // 键整体缺失：Dart `item["gid"].toString()` 得 "null"
        None => "null".to_string(),
    }
}

/// 取直接键的字符串值（缺失 -> 空串）。
fn text(item: &Value, key: &str) -> String {
    item.get(key)
        .map(crate::util::value_to_string)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn gid_object_takes_first_comma_segment() {
        assert_eq!(
            parse_gid(&json!({"gid": {"value": "12,34"}})),
            "12",
            "Map 形态取第一段"
        );
    }

    #[test]
    fn gid_double_drops_fraction() {
        assert_eq!(parse_gid(&json!({"gid": 7.0})), "7", "double 取整");
    }

    #[test]
    fn gid_int_and_string_are_verbatim() {
        assert_eq!(parse_gid(&json!({"gid": 9})), "9");
        assert_eq!(parse_gid(&json!({"gid": "abc"})), "abc");
    }

    #[test]
    fn gid_missing_yields_literal_null() {
        // Dart: item["gid"].toString() 对 null 与缺键都得 "null"（不是空串）
        assert_eq!(parse_gid(&json!({})), "null");
        assert_eq!(parse_gid(&json!({"gid": null})), "null");
    }

    #[test]
    fn gid_null_pic_keeps_dart_shape() {
        // 回归：null 时 pic 必须是 .../null-MS.jpg（夹具 ac4_gid_four_types 钉死）
        let gid = parse_gid(&json!({"gid": null}));
        assert_eq!(
            format!("https://huyaimg.msstatic.com/cdnimage/game/{gid}-MS.jpg"),
            "https://huyaimg.msstatic.com/cdnimage/game/null-MS.jpg"
        );
    }

    #[test]
    fn root_categories_match_dart_order() {
        let names: Vec<&str> = ROOT_CATEGORIES.iter().map(|(_, n)| *n).collect();
        assert_eq!(names, vec!["网游", "单机", "娱乐", "手游"]);
        let ids: Vec<&str> = ROOT_CATEGORIES.iter().map(|(i, _)| *i).collect();
        assert_eq!(ids, vec!["1", "2", "8", "3"]);
    }
}