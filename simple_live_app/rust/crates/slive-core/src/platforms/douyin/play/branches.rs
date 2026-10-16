//! 清晰度列表（F-07）的**三条分支**实现，从 `play.rs` 拆出（单文件 ≤300 行门禁）。
//!
//! 三条分支的判定顺序即 Dart 的 if/else 链（`douyin_site.dart:961-1077`），**不可重排**：
//! 1. [`from_url_tables`]：无画质列表 -> 用地址表的键当画质名；
//! 2. [`from_levels`]：`stream_data` 非 JSON -> 按 `level` 在地址表里倒序索引取值；
//! 3. [`from_stream_data`]：`stream_data` 是 JSON -> 按 `sdk_key` 精确取 `main.flv` / `main.hls`。
//!
//! 本模块只依赖 [`super::util`] 与 `models`，**不**发起任何网络请求。

use serde_json::Value;

use crate::models::LivePlayQuality;

use super::super::util::{as_object, safe_json_decode, urls_to_json};

/// 组装一条画质项（`urls` 为空的不产出 —— 与 Dart 的 `if (urls.isNotEmpty)` 一致）。
pub(super) fn push_quality(
    out: &mut Vec<LivePlayQuality>,
    quality: &str,
    sort: i32,
    urls: Vec<String>,
) {
    if urls.is_empty() {
        return;
    }
    out.push(LivePlayQuality {
        quality: quality.to_string(),
        sort,
        data: urls_to_json(&urls),
    });
}

/// 按 flv/hls 顺序拼地址（`hls_first` 决定谁在前）。
pub(super) fn order_urls(flv: &str, hls: &str, hls_first: bool) -> Vec<String> {
    let mut urls = Vec::with_capacity(2);
    if hls_first {
        push_non_empty(&mut urls, hls);
        push_non_empty(&mut urls, flv);
    } else {
        push_non_empty(&mut urls, flv);
        push_non_empty(&mut urls, hls);
    }
    urls
}

fn push_non_empty(out: &mut Vec<String>, url: &str) {
    if !url.is_empty() {
        out.push(url.to_string());
    }
}

/// 分支 1：无画质列表 -> 键名即画质名，`sort` 从键数递减。
pub(super) fn from_url_tables(data: &Value, hls_first: bool) -> Vec<LivePlayQuality> {
    let flv_map = as_object(data.get("flv_pull_url"));
    let hls_map = as_object(data.get("hls_pull_url_map"));

    // 键集合：flv 的全部键 + hls 里 flv 没有的键（保持插入序）
    let mut keys: Vec<String> = Vec::new();
    if let Some(flv) = flv_map {
        keys.extend(flv.keys().cloned());
    }
    if let Some(hls) = hls_map {
        for key in hls.keys() {
            if !flv_map.map(|f| f.contains_key(key)).unwrap_or(false) {
                keys.push(key.clone());
            }
        }
    }

    let mut out = Vec::new();
    let mut level = keys.len() as i32;
    for key in keys {
        let flv = flv_map
            .and_then(|m| m.get(&key))
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        let hls = hls_map
            .and_then(|m| m.get(&key))
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        push_quality(&mut out, &key, level, order_urls(&flv, &hls, hls_first));
        level -= 1;
    }
    out
}

/// 分支 2：`stream_data` 非 JSON -> 按 `level` 在地址表里倒序索引取值。
pub(super) fn from_levels(data: &Value, qualities: &[Value], hls_first: bool) -> Vec<LivePlayQuality> {
    let flv_list = map_values(data.get("flv_pull_url"));
    let hls_list = map_values(data.get("hls_pull_url_map"));

    let mut out = Vec::new();
    for quality in qualities {
        let level = crate::util::as_i32(quality.get("level")).unwrap_or(0);
        // 倒序索引：level 越大越靠近列表尾部（Dart `flvList.length - level`）
        let flv = pick_by_level(&flv_list, level);
        let hls = pick_by_level(&hls_list, level);
        let name = quality
            .get("name")
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        push_quality(&mut out, &name, level, order_urls(&flv, &hls, hls_first));
    }
    out
}

/// `list[len - level]`；越界（含 level 为负）-> 空串。
fn pick_by_level(list: &[String], level: i32) -> String {
    if level < 0 {
        return String::new();
    }
    list.len()
        .checked_sub(level as usize)
        .and_then(|i| list.get(i))
        .cloned()
        .unwrap_or_default()
}

/// 分支 3：`stream_data` 是 JSON -> 按 `sdk_key` 精确取 `main.flv` / `main.hls`。
pub(super) fn from_stream_data(
    qualities: &[Value],
    stream_data: &str,
    hls_first: bool,
) -> Vec<LivePlayQuality> {
    let quality_data = safe_json_decode(stream_data)
        .and_then(|v| v.pointer("/data").and_then(|d| as_object(Some(d))).cloned())
        .unwrap_or_default();

    let mut out = Vec::new();
    for quality in qualities {
        let sdk_key = quality
            .get("sdk_key")
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        let main = quality_data
            .get(&sdk_key)
            .and_then(|v| v.get("main"))
            .and_then(|v| as_object(Some(v)));
        let flv = main
            .and_then(|m| m.get("flv"))
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        let hls = main
            .and_then(|m| m.get("hls"))
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        let name = quality
            .get("name")
            .map(crate::util::value_to_string)
            .unwrap_or_default();
        let level = crate::util::as_i32(quality.get("level")).unwrap_or(0);
        push_quality(&mut out, &name, level, order_urls(&flv, &hls, hls_first));
    }
    out
}

/// 对象的所有值（按插入序），转字符串。
pub(super) fn map_values(value: Option<&Value>) -> Vec<String> {
    as_object(value)
        .map(|m| m.values().map(crate::util::value_to_string).collect())
        .unwrap_or_default()
}
