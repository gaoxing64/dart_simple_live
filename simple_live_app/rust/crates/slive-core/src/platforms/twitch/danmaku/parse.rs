//! Twitch IRC 行解析（对照 `twitch_danmaku.dart:73-103`，**逐条照搬 Dart 语义**）。
//!
//! IRC over WebSocket 的一个 WS 文本帧可含**多行**（`\r\n` 分隔），故先按行拆分再逐行解析。
//! 行格式：`@tags :source COMMAND #channel :trailing`
//!
//! ## 严格照搬的既有 quirks（`18-fixtures-multiplatform.md §4`，**不要顺手修**）
//!
//! | # | quirk | Dart 依据 |
//! |---|-------|-----------|
//! | Q-A | `PRIVMSG` 的三条正则（content / display-name / color）**必须同时命中**才产出；缺任一即**整条丢弃** | `:86-90` |
//! | Q-B | `PING` 对**整帧文本**做 `replaceFirst("PING","PONG")` —— 混帧时回包会带上后续 PRIVMSG 行 | `:79`（Q8） |
//! | Q-C | 帧尾 `\r` 会被 `(.)` 捕获进 `message` | `:86` 正则；**是否 trim 待 QA 裁决**（夹具标 `PENDING_QA_DECISION`） |
//!
//! ## 关于 Q-A / Q-C 的如实登记（**未擅自修改**）
//!
//! Q-A 会导致「未设置昵称颜色」与「无 display-name」的消息被静默丢弃 —— 这是 Dart 现状，
//! 也是 QA 钉死的既有行为（`§4`：修正会让 Rust 与 Dart 不一致 → 违反 AC-30）。
//! 实现**照搬**；是否修正属产品口径，已列入回传清单交由总监 + QA 裁决
//! （见 `docs/rust-core/17-twitch-mapping.md §3`）。
//!
//! 颜色值按 Dart 口径：去 `#` 后 `from_str_radix(16)`，再走
//! [`LiveMessageColor::number_to_color`]（与 B站 `numberToColor` 同一实现）。

use std::collections::HashMap;

use crate::models::{LiveMessage, LiveMessageColor, LiveMessageType};

/// 解析结果：一条 IRC 帧可能产生「若干消息 + 若干待发帧」（PING -> PONG）。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct IrcParseOutput {
    /// 解析出的业务消息。
    pub messages: Vec<LiveMessage>,
    /// 需要立即回发的帧（PONG；keepalive）。
    pub replies: Vec<String>,
}

/// 解析一个 WS 文本帧（可能含多行）。
///
/// Q-B：按 Dart 的顺序先做**整帧** PING 判定（`starts_with("PING")`），命中则回发
/// 「整帧把首个 PING 换成 PONG」；随后按 `\n` 逐行解析 `PRIVMSG`。
pub fn parse_frame(text: &str) -> IrcParseOutput {
    let mut out = IrcParseOutput::default();

    // Q-B（`twitch_danmaku.dart:77-80`）：Dart 先判「整帧是否以 PING 开头」，
    // 再 `replaceFirst`。混帧（首行 PING、后续 PRIVMSG）时回包会带上后续行 ——
    // 这是钉死的既有行为（Q8），**不得修**。
    if text.starts_with("PING") {
        out.replies.push(text.replacen("PING", "PONG", 1));
    }

    // Q-C：按 `\n` 拆行（Dart `message.split('\n')`）；`\r` 是否保留属待裁决项，
    // 此处**保留**（与 Dart 正则 `(.)` 捕获 `\r` 的行为一致）。
    for line in text.split('\n') {
        let (tags, source, command, _channel, trailing) = parse_line(line);
        if command != "PRIVMSG" {
            continue;
        }
        // Q-A：三条件必须同时命中（content / display-name / color），缺一即丢弃。
        if let Some(message) = build_chat_message(&tags, &source, &trailing) {
            out.messages.push(message);
        }
    }
    out
}

/// 拆分一行 IRC：`@tags :source COMMAND params... :trailing`。
///
/// 返回 `(tags, source, command, params, trailing)`；`params` 是 `#channel` 等中间参数。
pub fn parse_line(line: &str) -> (HashMap<String, String>, String, String, String, String) {
    // ⚠️ **不 trim 行尾 `\r`**：Dart 的 `PRIVMSG [^:]+:(.+)` 中 `.` 会把 `\r` 一起捕获进
    // message（Q-C）。是否 trim 属**待 QA 裁决**口径（夹具标 `PENDING_QA_DECISION`），
    // 裁决前一律照搬 Dart —— 见模块文档。
    let mut rest = line;

    let tags = match rest.strip_prefix('@') {
        Some(rest_tags) => match rest_tags.find(' ') {
            Some(pos) => {
                let parsed = parse_tags(&rest_tags[..pos]);
                rest = rest_tags[pos..].trim_start();
                parsed
            }
            None => {
                rest = "";
                HashMap::new()
            }
        },
        None => HashMap::new(),
    };

    let source = match rest.strip_prefix(':') {
        Some(rest_source) => match rest_source.find(' ') {
            Some(pos) => {
                let src = rest_source[..pos].to_string();
                rest = rest_source[pos..].trim_start();
                src
            }
            None => String::new(),
        },
        None => String::new(),
    };

    let command_end = rest.find(' ').unwrap_or(rest.len());
    let command = rest[..command_end].to_string();
    rest = rest[command_end..].trim_start();

    // 有 trailing（` :xxx`）时，中间参数与 trailing 分开；否则全部视为参数。
    let (params, trailing) = match rest.find(" :") {
        Some(pos) => (rest[..pos].trim().to_string(), rest[pos + 2..].to_string()),
        None => match rest.strip_prefix(':') {
            Some(t) => (String::new(), t.to_string()),
            None => (rest.trim().to_string(), String::new()),
        },
    };

    (tags, source, command, params, trailing)
}

/// 解析 `@k=v;k2=v2` 标签串（含 IRC 转义还原）。
pub fn parse_tags(raw: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for part in raw.split(';') {
        if part.is_empty() {
            continue;
        }
        let (key, value) = match part.split_once('=') {
            Some((k, v)) => (k, unescape_tag(v)),
            None => (part, String::new()),
        };
        map.insert(key.to_string(), value);
    }
    map
}

/// IRC 标签转义还原（`\:` -> `;`、`\s` -> 空格、`\\` -> `\`、`\r`/`\n`）。
fn unescape_tag(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some(':') => out.push(';'),
            Some('s') => out.push(' '),
            Some('\\') => out.push('\\'),
            Some('r') => out.push('\r'),
            Some('n') => out.push('\n'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// `nick!user@host` -> `nick`。
///
/// ⚠️ 当前**仅供测试与诊断**使用：Q-A 下无 `display-name` 的消息会被丢弃，
/// 因此生产路径不会拿它兜底（照搬 Dart，见模块文档）。
pub fn nick_of(source: &str) -> String {
    source.split('!').next().unwrap_or(source).to_string()
}

/// 构造聊天消息。
///
/// **Q-A 语义**：`display-name` 与 6 位 `color` 两个标签**缺一即返回 `None`（丢弃）**；
/// `trailing` 为空同样不产出。**不做** nick 回退、**不做**白色兜底 —— 与 Dart 一致。
fn build_chat_message(
    tags: &HashMap<String, String>,
    _source: &str,
    trailing: &str,
) -> Option<LiveMessage> {
    if trailing.is_empty() {
        return None;
    }
    // Dart `display-name=([^;]+);`：值非空。
    let user_name = tags.get("display-name").filter(|s| !s.is_empty())?;
    // Dart `color=#([a-zA-Z0-9]{6});`：必须是 `#` + 6 位十六进制。
    let digits = tags.get("color")?.strip_prefix('#')?;
    if digits.len() != 6 || !digits.chars().all(|c| c.is_ascii_alphanumeric()) {
        return None;
    }
    let color = i32::from_str_radix(digits, 16)
        .map(LiveMessageColor::number_to_color)
        .unwrap_or_else(|_| LiveMessageColor::white());

    Some(LiveMessage {
        message_type: LiveMessageType::Chat,
        user_name: user_name.clone(),
        user_id: tags.get("user-id").filter(|s| !s.is_empty()).cloned(),
        message: trailing.to_string(),
        data: None,
        color,
        emoticons: None,
    })
}
