//! 弹幕表情包解析（F-16，对照 `bilibili_emoticon.dart:26-300`）。
//!
//! B 站两种下发方式，可能同时出现：
//! 1. `info[0][13]`：整条弹幕就是一个表情（大表情），形如 `{"url": ..., "width": ...}`，
//!    也可能只是含一个对象的数组；
//! 2. `info[0][15]["extra"]`：JSON 字符串，`extra["emots"]` 是 `"[doge]" -> {...}` 的映射，
//!    一条弹幕可混排多个；key 也可能是不带方括号的裸名（如 `"冲鸭"`，B 站单独发送）。
//!
//! 纪律：上限 8（**入口截断**，出口不再截断）、名字/url 双去重、URL 统一升 https、
//! 异常载荷 → `None`（不抛）。

use std::collections::HashSet;

use serde_json::Value;

use crate::models::LiveMessageEmoticon;

/// 单条弹幕最多解析的表情数量，防止异常载荷放大内存与流量。
const MAX_EMOTICONS: usize = 8;
/// 表情名长度上限：B 站表情名都是几个字，超过基本可认定 message 夹带了正文。
const MAX_EMOTICON_NAME_LENGTH: usize = 12;

/// `info[0][13]` 校验过 url 之后的单表情形态。
struct SingleEmoticon {
    url: String,
    width: Option<i32>,
    height: Option<i32>,
    emoticon_unique: Option<String>,
}

/// 解析 `DANMU_MSG` 的 `info` 中的表情包；无表情 → `None`。
///
/// 只保留 [message] 里真正出现过的表情，避免把整个表情面板塞进消息对象。
pub fn parse_bilibili_emoticons(
    info: &[Value],
    message: &str,
) -> Option<Vec<LiveMessageEmoticon>> {
    if info.len() < 2 {
        return None;
    }
    let meta = info.first()?.as_array()?;
    if meta.is_empty() {
        return None;
    }

    // 先读 info[0][13]：它带不带可用 url 是「这条弹幕是不是大表情」的唯一依据；
    // 两个入口共用它定 large，否则同一 message 会因 extra 在不在得到相反的尺寸口径。
    let single = read_single_emoticon(meta);

    let mut result: Vec<LiveMessageEmoticon> = Vec::new();
    let mut seen_names: HashSet<String> = HashSet::new();

    parse_extra_emots(
        meta,
        message,
        single.as_ref().map(|s| s.url.clone()),
        &mut result,
        &mut seen_names,
    );
    append_single_emoticon(single.as_ref(), message, &mut result, &mut seen_names);

    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

fn is_full(result: &[LiveMessageEmoticon]) -> bool {
    result.len() >= MAX_EMOTICONS
}

/// 入口 2：`info[0][15]["extra"]["emots"]` 的占位符映射。
fn parse_extra_emots(
    meta: &[Value],
    message: &str,
    big_emoticon_url: Option<String>,
    result: &mut Vec<LiveMessageEmoticon>,
    seen_names: &mut HashSet<String>,
) {
    if meta.len() <= 15 || message.is_empty() {
        return;
    }
    let extra = meta
        .get(15)
        .and_then(|v| v.as_object())
        .and_then(|m| m.get("extra"))
        .and_then(Value::as_str);
    let Some(extra) = extra.filter(|s| !s.is_empty()) else {
        return;
    };
    let Some(emot_map) = serde_json::from_str::<Value>(extra)
        .ok()
        .and_then(|v| v.get("emots").cloned())
        .and_then(|v| v.as_object().cloned())
    else {
        return;
    };

    for (name, value) in &emot_map {
        // 到量就停（入口截断）：截断会掩盖「解析出来又被丢掉」的不可见行为
        if is_full(result) {
            break;
        }
        if !can_replace(name, message) {
            continue;
        }
        let Some(url) = value.get("url").and_then(Value::as_str).and_then(normalize_url)
        else {
            continue;
        };
        if !seen_names.insert(name.clone()) {
            continue;
        }
        // 与 info[0][13] 同图，或整条弹幕就是这个裸名 key —— 都是单独下发的大表情
        let large = Some(url.clone()) == big_emoticon_url
            || (!is_placeholder(name)
                && standalone_emoticon_name(message.trim()).as_deref() == Some(name.as_str()));
        result.push(LiveMessageEmoticon {
            name: Some(name.clone()),
            url,
            width: value.get("width").and_then(as_int),
            height: value.get("height").and_then(as_int),
            large,
            emoticon_unique: value
                .get("emoticon_unique")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
}

/// 入口 1：`info[0][13]` 的单表情对象（已校验 url）。
fn append_single_emoticon(
    single: Option<&SingleEmoticon>,
    message: &str,
    result: &mut Vec<LiveMessageEmoticon>,
    seen_names: &mut HashSet<String>,
) {
    let Some(single) = single else {
        return;
    };
    if is_full(result) {
        return;
    }
    // extra.emots 可能已解析过同一张图（两种下发方式同时出现）；
    // 拿不到 name 时去重集合用不上，而渲染层对 name == null 的表情无条件追加，
    // 因此必须按 url 去重，否则同一条弹幕会多贴一张重复的图
    if result.iter().any(|e| e.url == single.url) {
        return;
    }
    let name = standalone_emoticon_name(message.trim());
    if let Some(n) = &name {
        if !seen_names.insert(n.clone()) {
            return;
        }
    }
    result.push(LiveMessageEmoticon {
        name,
        url: single.url.clone(),
        width: single.width,
        height: single.height,
        // info[0][13] 带可用 url 就是「大表情」
        large: true,
        emoticon_unique: single.emoticon_unique.clone(),
    });
}

/// `info[0][13]` 的单表情对象；没有可用图片地址时返回 `None`。
fn read_single_emoticon(meta: &[Value]) -> Option<SingleEmoticon> {
    if meta.len() <= 13 {
        return None;
    }
    let single = first_map(meta.get(13)?)?;
    let url = single.get("url").and_then(Value::as_str).and_then(normalize_url)?;
    Some(SingleEmoticon {
        url,
        width: single.get("width").and_then(as_int),
        height: single.get("height").and_then(as_int),
        emoticon_unique: single
            .get("emoticon_unique")
            .and_then(Value::as_str)
            .map(String::from),
    })
}

/// 整条 message 能否当作单个表情名（渲染层整串替换 vs 追加到末尾）。
///
/// 只接受：本身是 `[xxx]` 占位符；或完全不含方括号、长度 ≤ 12、无空白的裸名。
/// 「占位符 + 正文」混排（如 `[大笑]哈哈哈`）退回 `None` 交给渲染层追加。
fn standalone_emoticon_name(trimmed: &str) -> Option<String> {
    if trimmed.is_empty() {
        return None;
    }
    if is_placeholder(trimmed) {
        return Some(trimmed.to_string());
    }
    if trimmed.contains('[') || trimmed.contains(']') {
        return None;
    }
    if trimmed.chars().count() > MAX_EMOTICON_NAME_LENGTH || trimmed.chars().any(char::is_whitespace)
    {
        return None;
    }
    Some(trimmed.to_string())
}

fn is_placeholder(text: &str) -> bool {
    text.chars().count() > 2 && text.starts_with('[') && text.ends_with(']')
}

/// `emots` 的 key 能否拿来对 [message] 做子串替换。
///
/// 只有两种形态安全：`[xxx]` 占位符（`message.contains`）；
/// 或整条弹幕就是这个 key（单独发表情，不夹带正文）。
/// 仅满足 `contains` 的裸名（如 "6"、"哈"）必须挡掉，否则正文每处都被换成图。
fn can_replace(name: &str, message: &str) -> bool {
    if name.is_empty() {
        return false;
    }
    if is_placeholder(name) {
        return message.contains(name);
    }
    standalone_emoticon_name(message.trim()).as_deref() == Some(name)
}

/// 图片地址规范化：补全协议并统一升 https；相对路径等不合法形态一律丢弃。
fn normalize_url(raw: &str) -> Option<String> {
    let url = raw.trim();
    if url.is_empty() {
        return None;
    }
    if let Some(rest) = url.strip_prefix("//") {
        let _ = rest;
        // 对齐 Dart `'https:$url'`：url 保留 `//` 前缀直接拼接
        return Some(format!("https:{url}"));
    }
    if let Some(rest) = url.strip_prefix("http://") {
        return Some(format!("https://{rest}"));
    }
    if url.starts_with("https://") {
        return Some(url.to_string());
    }
    None
}

/// `info[0][13]` 可能是对象，也可能是只含一个对象的数组。
fn first_map(value: &Value) -> Option<&serde_json::Map<String, Value>> {
    match value {
        Value::Array(items) => items.first().and_then(Value::as_object),
        other => other.as_object(),
    }
}

fn as_int(value: &Value) -> Option<i32> {
    match value {
        Value::Number(n) => n
            .as_i64()
            .map(|v| v as i32)
            .or_else(|| n.as_f64().map(|f| f as i32)),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}
