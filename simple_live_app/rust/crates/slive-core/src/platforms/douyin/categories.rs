//! 分类列表（对照 Dart `DouyinSite.getCategories`，`douyin_site.dart:59-107`）。
//!
//! 数据来源是**首页 HTML 内嵌的转义 JSON**，不是独立接口。页面里的形态是
//! `{\"pathname\":\"\/\",\"categoryData\":[...],\"其他键\":...}`（整段被 JS 字符串转义）。
//!
//! # 解析方式：定位标记 + 括号配平（⚠️ 刻意偏离 Dart，见下）
//! Dart 的做法是「正则非贪婪截到首个 `],` → 去掉 `],` → `json.decode`」，这里改成：
//! 1. 正则只用来**定位** `categoryData` 标记（容忍 `"/"` 与 `"\/"` 两种斜杠写法）；
//! 2. 从其后的 `[` 开始做**括号配平扫描**（正确跳过字符串内的括号）截出数组原文；
//! 3. 反转义后 `json::from_str`。
//!
//! 偏离理由（属「沉默逻辑错误」修复，非能力变更）：Dart 的 `replaceAll('],', "")`
//! 会删掉**全部** `],`，一旦被截出的片段内含内层 `],`（`sub_partition` 后面跟逗号的
//! 形态）就会拼出非法 JSON 而整页失败；且其正则里的 `\/` 未写成 `\\/`，页面用
//! `"\/"` 形态时根本匹配不到。本实现在两种斜杠形态下都能解析，且不依赖 `],` 的出现位置。
//!
//! 结构约定（来自 Dart 组装逻辑）：
//! - 一级分类 `id = "{partition.id_str},{partition.type}"`；
//! - 子分类来自 `sub_partition[]`，其 `id` 同构；
//! - 每个一级分类的 `children` **首位插入自身**（Dart `subs.insert(0, ...)`），
//!   所以「全部」入口就是一级分类自己。
//!
//! 截不到内嵌数据时返回**类型化错误**（`Decode`）而非空列表 —— 空列表会让 App
//! 分类页一片空白且无任何提示，属「沉默逻辑错误」。

use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LiveCategory, LiveSubCategory};

use super::site::DouyinSite;
use super::util::as_object;

/// 首页 URL（Dart `getCategories` 的目标）。
pub const HOME_URL: &str = "https://live.douyin.com/";

/// 定位内嵌 `categoryData` 标记。
///
/// 只匹配到键名（不含 `":[` 之后的内容），因此**不关心**数组怎么结束 ——
/// 结束位置交给括号配平扫描，顺带兼容 `"/"` 与 `"\/"` 两种斜杠转义形态。
fn category_data_marker() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r#"\{\\"pathname\\":\\"[\\]?/[\\]?\\",\\"categoryData\\":"#)
            .expect("分类内嵌数据正则是常量，编译期即合法")
    })
}

/// 拉取分类 A 列表。
pub(crate) async fn fetch(site: &DouyinSite) -> Result<Vec<LiveCategory>, SliveError> {
    super::header::ensure_ttwid(site).await?;
    let html = site
        .get_text(HOME_URL, Vec::new(), super::header::build_header(site))
        .await?;
    parse_categories(&html)
}

/// 从首页 HTML 解析分类（与网络解耦，便于夹具测试）。
fn parse_categories(html: &str) -> Result<Vec<LiveCategory>, SliveError> {
    let raw = extract_category_data_array(html).ok_or_else(|| {
        SliveError::decode("抖音首页未返回分类数据（页面结构可能已变更）".to_string())
    })?;
    let parsed: Value = serde_json::from_str(&unescape(&raw))
        .map_err(|e| SliveError::decode(format!("解析抖音首页分类数据失败: {e}")))?;

    let items = crate::util::array_at(&parsed, "").to_vec();
    if items.is_empty() {
        return Err(SliveError::decode(
            "抖音首页分类数据为空（categoryData 缺失或不是数组）".to_string(),
        ));
    }
    Ok(items.iter().filter_map(build_category).collect())
}

/// 截出 `categoryData` 数组的**原始（仍转义）**文本。
fn extract_category_data_array(html: &str) -> Option<String> {
    let start = category_data_marker().find(html)?.end();
    let bytes = html.as_bytes();
    if bytes.get(start) != Some(&b'[') {
        return None;
    }
    let end = scan_array_end(bytes, start)?;
    Some(html[start..end].to_string())
}

/// 从 `[` 开始做括号配平扫描，返回**配对 `]` 之后**的下标（UTF-8 边界）。
///
/// 正确跳过字符串字面量内部的括号与转义序列；数组未闭合 -> `None`（截取失败）。
pub(crate) fn scan_array_end(bytes: &[u8], open: usize) -> Option<usize> {
    scan_balanced(bytes, open, b'[', b']')
}

/// 从 `{` 开始做括号配平扫描，返回**配对 `}` 之后**的下标（UTF-8 边界）。
///
/// 语义与 [`scan_array_end`] 相同，供 `detail/html.rs` 解析内嵌 `state` 复用。
pub(crate) fn scan_json_object_end(bytes: &[u8], open: usize) -> Option<usize> {
    scan_balanced(bytes, open, b'{', b'}')
}

/// 括号配平扫描的公共实现（`open_char` / `close_char` 决定配对类型）。
///
/// # 为何要区分「转义形态」与「普通形态」的字符串
/// 同一函数要服务两种输入，而它们的引号规则**相反**：
/// - **页面内嵌 JSON（转义形态）**：每个引号都是 `\"`，字符串由 `\"` 开启、也由 `\"` 收尾；
/// - **普通 JSON 字面量（未转义）**：引号是裸 `"`，字符串内的 `\"` 是**转义引号**（不收尾）。
///
/// 因此用「该字符串是由 `\"` 还是由裸 `"` 开启」来决定收尾规则 —— 二者都是确定性的，
/// 不存在猜测。若按单一规则扫描，转义形态会因开引号的 `\` 落在字符串态之外而
/// **永远走不出字符串**（`]` 被当作字符串内容跳过，截取必然失败）。
fn scan_balanced(bytes: &[u8], open: usize, open_char: u8, close_char: u8) -> Option<usize> {
    let mut depth = 0usize;
    let mut in_string = false;
    // 当前字符串是否由 `\"`（转义形态）开启。
    let mut escaped_form = false;
    let mut escaped = false;
    let mut idx = open;
    while idx < bytes.len() {
        let byte = bytes[idx];
        if in_string {
            if escaped {
                escaped = false;
                idx += 1;
                continue;
            }
            if byte == b'\\' {
                let next = bytes.get(idx + 1).copied();
                if next == Some(b'"') && escaped_form {
                    // 转义形态：`\"` 是收尾引号
                    in_string = false;
                    idx += 2;
                    continue;
                }
                escaped = true;
                idx += 1;
                continue;
            }
            if byte == b'"' {
                in_string = false;
            }
            idx += 1;
            continue;
        }
        if byte == b'\\' {
            if bytes.get(idx + 1) == Some(&b'"') {
                // 转义形态：`\"` 是开引号
                in_string = true;
                escaped_form = true;
                idx += 2;
                continue;
            }
            idx += 1;
            continue;
        }
        if byte == b'"' {
            in_string = true;
            escaped_form = false;
            idx += 1;
            continue;
        }
        if byte == open_char {
            depth += 1;
        } else if byte == close_char {
            depth -= 1;
            if depth == 0 {
                return Some(idx + 1);
            }
        }
        idx += 1;
    }
    None
}

/// 反转义（Dart 的 `\"` -> `"`、`\\` -> `\`；额外把 `\/` 还原成 `/`）。
pub(crate) fn unescape(raw: &str) -> String {
    raw.replace("\\\"", "\"")
        .replace("\\\\", "\\")
        .replace("\\/", "/")
}

/// 一条 `categoryData` 项 -> `LiveCategory`；`partition` 缺失则跳过（脏条目不拖垮整页）。
fn build_category(item: &Value) -> Option<LiveCategory> {
    let partition = as_object(item.get("partition"))?;
    let id = partition_id(partition);
    let name = partition
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    let mut children: Vec<LiveSubCategory> = crate::util::array_at(item, "/sub_partition")
        .iter()
        .filter_map(|sub| sub_category_of(sub, &id))
        .collect();

    // Dart：children 首位插入一级分类自身（「全部」入口）
    children.insert(
        0,
        LiveSubCategory {
            id: id.clone(),
            name: name.clone(),
            parent_id: id.clone(),
            pic: Some(String::new()),
        },
    );

    Some(LiveCategory { name, id, children })
}

/// 一条 `sub_partition` 项 -> `LiveSubCategory`。
///
/// `partition` 缺失或**空对象**一律跳过：Dart 的 `subItem["partition"]["id_str"]`
/// 遇到空对象会抛 `NoSuchMethodError` 让整页失败，而分区里混进空 `partition` 是
/// 已观察到的脏数据形态（QA 夹具备注亦提及）。这里显式跳过，保证单条脏数据
/// 只丢自己、不拖垮整页 —— 属「沉默逻辑错误」修复，非能力变更。
fn sub_category_of(sub: &Value, parent_id: &str) -> Option<LiveSubCategory> {
    let p = as_object(sub.get("partition")).filter(|p| !p.is_empty())?;
    Some(LiveSubCategory {
        id: partition_id(p),
        name: p
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        parent_id: parent_id.to_string(),
        pic: Some(String::new()),
    })
}

/// `"{id_str},{type}"`（两项缺一即为空串，形如 Dart 的字符串插值）。
fn partition_id(partition: &serde_json::Map<String, Value>) -> String {
    let id_str = partition
        .get("id_str")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    let kind = partition
        .get("type")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    format!("{id_str},{kind}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// 构造与抖音首页同构的内嵌文本（`\/` 转义形态，与真实页面一致）。
    fn home_html(category_data: &Value) -> String {
        let inner =
            serde_json::to_string(&json!({"pathname": "/", "categoryData": category_data}))
                .expect("序列化");
        let escaped = inner.replace('\\', "\\\\").replace('"', "\\\"");
        format!("<html><script>{escaped}</script></html>")
    }

    #[test]
    fn unescape_restores_quotes_slashes_and_backslashes() {
        assert_eq!(unescape(r#"\"a\""#), "\"a\"");
        assert_eq!(unescape(r#"\"\/a\""#), "\"/a\"");
        assert_eq!(unescape(r#"\\"#), "\\");
    }

    #[test]
    fn scan_array_end_handles_nested_and_brackets_in_strings() {
        assert_eq!(scan_array_end(b"[]", 0), Some(2));
        assert_eq!(scan_array_end(b"[[]]", 0), Some(4));
        assert_eq!(scan_array_end(br#"["]"]"#, 0), Some(5), "字符串内的 ] 不计数");
        // 未转义 JSON 里的 `\"` 是**转义引号**（不收尾），故字符串跨到第 8 字节才闭合
        assert_eq!(scan_array_end(br#"["[\"]"]"#, 0), Some(8), "转义引号内的括号不计数");
        assert_eq!(scan_array_end(b"[", 0), None, "未闭合 -> None");
    }

    #[test]
    fn scan_array_end_handles_page_embedded_escaped_json() {
        // 页面内嵌形态：引号全是 `\"`，字符串由 `\"` 开启也由 `\"` 收尾
        assert_eq!(
            scan_array_end(br#"[{\"a\":1}]"#, 0),
            Some(11),
            "转义形态下必须能正常走出字符串，否则截取必然失败"
        );
        // 转义形态的字符串里含括号
        assert_eq!(
            scan_array_end(br#"[{\"k\":\"a[b]c\"}]"#, 0),
            Some(19),
            "转义形态字符串内的括号同样不计数"
        );
    }

    #[test]
    fn scan_array_end_handles_nested_objects_in_escaped_json() {
        let raw = br#"[{\"p\":{\"x\":1},\"s\":[{\"a\":1},{\"b\":2}]}]"#;
        assert_eq!(scan_array_end(raw, 0), Some(raw.len()));
    }

    #[test]
    fn extract_supports_both_slash_escape_forms() {
        for prefix in [
            r#"{\"pathname\":\"\/\",\"categoryData\":[{\"a\":1}],"#,
            r#"{\"pathname\":\"/\",\"categoryData\":[{\"a\":1}],"#,
        ] {
            let html = format!("<script>{prefix}</script>");
            let raw = extract_category_data_array(&html)
                .unwrap_or_else(|| panic!("应能截出数组：{prefix}"));
            assert_eq!(unescape(&raw), r#"[{"a":1}]"#, "实际 {}", unescape(&raw));
        }
    }

    #[test]
    fn extract_ignores_inner_array_terminators() {
        // Dart 的 replaceAll('],','') 会把内层 `],` 一并删掉从而拼出非法 JSON；
        // 本实现按括号配平截取，内层 `],` 原样保留。
        let html = r#"<script>{\"pathname\":\"\/\",\"categoryData\":[{\"sub\":[1,2],\"x\":3}],\"t\":1}</script>"#;
        let raw = extract_category_data_array(html).expect("应能截出");
        assert_eq!(
            unescape(&raw),
            r#"[{"sub":[1,2],"x":3}]"#,
            "内层 `],` 必须保留"
        );
    }

    #[test]
    fn partition_id_joins_id_str_and_type() {
        let mut p = serde_json::Map::new();
        p.insert("id_str".into(), json!("106"));
        p.insert("type".into(), json!(4));
        assert_eq!(partition_id(&p), "106,4");
    }

    #[test]
    fn build_category_inserts_self_as_first_child() {
        let item = json!({
            "partition": {"id_str": "106", "type": 4, "title": "文化"},
            "sub_partition": [
                {"partition": {"id_str": "1061", "type": 4, "title": "音乐"}},
                {"partition": {"id_str": "1062", "type": 4, "title": "舞蹈"}},
            ],
        });
        let cat = build_category(&item).expect("应能组装");
        assert_eq!(cat.id, "106,4");
        assert_eq!(cat.name, "文化");
        assert_eq!(cat.children.len(), 3, "自身 + 2 个子分类");
        assert_eq!(cat.children[0].id, "106,4", "children[0] 是自身");
        assert_eq!(cat.children[0].name, "文化");
        assert_eq!(cat.children[1].id, "1061,4");
        assert_eq!(cat.children[1].parent_id, "106,4");
    }

    #[test]
    fn build_category_skips_dirty_entries_without_panicking() {
        assert!(build_category(&json!({})).is_none(), "缺 partition 应跳过");
        assert!(build_category(&json!("not-object")).is_none());
        // 子项脏数据只丢该子项，不影响整体
        let cat = build_category(&json!({
            "partition": {"id_str": "1", "type": 4, "title": "x"},
            "sub_partition": [
                {"partition": {}},
                {"partition": {"id_str": "2", "type": 4, "title": "ok"}}
            ],
        }))
        .expect("应能组装");
        assert_eq!(cat.children.len(), 2, "自身 + 1 个有效子项");
    }

    #[test]
    fn parses_categories_from_home_html() {
        let html = home_html(&json!([
            {"partition": {"id_str": "106", "type": 4, "title": "文化"},
             "sub_partition": [{"partition": {"id_str": "1061", "type": 4, "title": "音乐"}}]},
            {"partition": {"id_str": "103", "type": 4, "title": "游戏"},
             "sub_partition": []},
        ]));
        let cats = parse_categories(&html).expect("应能解析");
        assert_eq!(cats.len(), 2);
        assert_eq!(cats[0].name, "文化");
        assert_eq!(cats[0].children.len(), 2);
        assert_eq!(cats[1].id, "103,4");
        assert_eq!(cats[1].children.len(), 1, "无子分类时仍只有自身");
    }

    #[test]
    fn missing_render_data_reports_decode_error() {
        let err = parse_categories("<html>无内嵌数据</html>").expect_err("应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn empty_category_data_reports_decode_error() {
        let err = parse_categories(&home_html(&json!([]))).expect_err("空数组应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn truncated_json_reports_decode_error_not_panic() {
        let html = r#"{\"pathname\":\"/\",\"categoryData\":[{\"partition\":{\"id_str\":\"1\""#;
        let err = parse_categories(html).expect_err("半截 JSON 应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }
}
