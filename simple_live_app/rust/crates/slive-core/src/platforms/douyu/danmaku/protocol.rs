//! 斗鱼弹幕 STT 文本协议编解码（对照 `douyu_danmaku.dart:152-228`）。
//!
//! 斗鱼弹幕**不是** TARS/JSON，而是「STT（`type@=xxx/rid@=1/`）+ 12 字节小端包头」：
//!
//! ```text
//! | 全长(4,LE) | 全长(4,LE) | 包类型(2,LE)=689 | 加密(1) | 保留(1) | 载荷 | 结束符(1)=0 |
//! ```
//!
//! 载荷里的字段以 `/` 分隔、`@=` 连接，`@S` 转义为 `/`、`@A` 转义为 `@`；
//! `//` 表示嵌套结构（对象或数组），`@A=` 表示「本字段整体转义」。

/// 包类型（`689`，固定值，对齐 Dart `clientSendToServer`）。
pub const PACK_TYPE: i32 = 689;

/// 封包：STT 文本 -> 二进制帧。
///
/// 全长 = `载荷字节数 + 9`（两个 4 字节长度 + 2 字节包类型 + 1 字节加密 + 1 字节保留 + 1 字节结束符）。
pub fn serialize(body: &str) -> Vec<u8> {
    let payload = body.as_bytes();
    let total = (payload.len() + 9) as u32;
    let mut frame = Vec::with_capacity(payload.len() + 12);
    frame.extend_from_slice(&total.to_le_bytes());
    frame.extend_from_slice(&total.to_le_bytes());
    frame.extend_from_slice(&(PACK_TYPE as u16).to_le_bytes());
    frame.push(0); // 加密标志：未加密
    frame.push(0); // 保留位
    frame.extend_from_slice(payload);
    frame.push(0); // 结束符
    frame
}

/// 解包：二进制帧 -> STT 文本（失败返回 `None`，对齐 Dart 的 `try/catch -> null`）。
///
/// ⚠️ Dart 用 `bodyLength = fullMsgLength - 9` 读载荷，再**显式读 1 字节结束符**；
/// 若帧尾没有结束符，Dart 的 `readByte()` 会越界抛错 -> 整帧丢弃。此处要求
/// `12 + bodyLength + 1 <= len`（同样丢弃），口径与 Dart 一致。
///
/// 另：Dart 把结束符 `\0` 也算进载荷区间，`utf8.decode` 会产出尾随 `null` 字符 ——
/// 那是 Dart 的既有缺陷，本实现在截取时**排除**结束符（差异已登记）。
pub fn deserialize(data: &[u8]) -> Option<String> {
    if data.len() < 13 {
        return None;
    }
    let full = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
    if full < 9 {
        return None;
    }
    let body_length = full - 9;
    let start: usize = 12;
    let end = start.checked_add(body_length)?;
    // 结束符必须存在（Dart 会显式读它，越界即整帧失败）
    if end.checked_add(1)? > data.len() {
        return None;
    }
    String::from_utf8(data[start..end].to_vec()).ok()
}

/// STT 文本 -> JSON `Value`（**Dart 兼容的扁平解析**，对齐 `sttToJObject`）。
///
/// 规则（顺序敏感，必须照抄）：
/// 1. 含 `//` -> 数组：按 `//` 切分后**递归**每一段（空段跳过）；
/// 2. 含 `@=` -> 对象：按 `/` 切分，`k@v` 取 `tokens[1]`（**只取第二段**）并递归；
/// 3. 含 `@A=` -> 先整体反转义再递归；
/// 4. 否则 -> 反转义后的叶子字符串。
pub fn stt_to_value(text: &str) -> serde_json::Value {
    stt_to_value_with(text, &[])
}

/// STT 文本 -> JSON `Value`（**容器字段模式感知**，见 [`stt_to_value`] 的容器说明）。
///
/// `containers` 列出「**其后所有字段都归属该容器**」的键名（斗鱼的嵌套对象/数组写法）：
/// - `chatmsg@=nn@=X/txt@=Y/ic@=Z` -> `{"chatmsg": {"nn":"X","txt":"Y","ic":"Z"}}`
/// - `list@=0@un@=X/content@=Y` -> `{"list": [{"un":"X","content":"Y"}]}`（首段为下标）
///
/// 未命中的键仍是 Dart 的扁平口径（只取第二段），因此**对 Dart 能解析的报文完全等价**。
pub fn stt_to_value_with(text: &str, containers: &[&str]) -> serde_json::Value {
    if text.contains("//") {
        let items: Vec<serde_json::Value> = text
            .split("//")
            .filter(|field| !field.is_empty())
            .map(|field| stt_to_value_with(field, containers))
            .collect();
        return serde_json::Value::Array(items);
    }
    if text.contains("@=") {
        let fields: Vec<&str> = text.split('/').filter(|f| !f.is_empty()).collect();
        let mut map = serde_json::Map::new();
        let mut index = 0usize;
        while index < fields.len() {
            let field = fields[index];
            index += 1;
            let Some((key, raw)) = field.split_once("@=") else {
                continue;
            };
            // 容器键要**保留**第二段（`chatmsg@=nn@=X` 的 `nn@=X` 才是内容），
            // 故先判容器再按 Dart 口径截断。
            if containers.contains(&key) {
                let rest: Vec<String> = std::iter::once(raw.to_string())
                    .chain(fields[index..].iter().map(|f| f.to_string()))
                    .collect();
                index = fields.len();
                map.insert(key.to_string(), container_value(&rest));
                continue;
            }
            // Dart: field.split("@=") 只取 tokens[1]（值里再出现 "@=" 会被截断）
            let raw = match raw.split_once("@=") {
                Some((_, rest)) => rest,
                None => raw,
            };
            map.insert(key.to_string(), stt_to_value_with(&unescape(raw), containers));
        }
        return serde_json::Value::Object(map);
    }
    if text.contains("@A=") {
        return stt_to_value_with(&unescape(text), containers);
    }
    serde_json::Value::String(unescape(text))
}

/// 容器值：STT 的嵌套对象/数组写法（见 [`stt_to_value_with`]）。
///
/// 首段的四种形态：
/// - `chatmsg@=nn@=X/…` -> 嵌套对象（无下标，子字段 `nn@=X`）；
/// - `list@=0@un@=X/…` -> 数组，第 0 元素是后续字段构成的对象；
/// - `uat@=1@=cdn.example.com/…` -> 数组，第 1 元素是标量字符串；
/// - `list@=0/…` -> 数组，第 0 元素由后续字段构成。
fn container_value(rest: &[String]) -> serde_json::Value {
    let head = rest.first().map(String::as_str).unwrap_or("");
    let (index, head_item) = split_container_head(head);
    let mut items: Vec<Item> = Vec::new();
    if let Some(item) = head_item {
        items.push(item);
    }
    for fragment in rest.iter().skip(1) {
        if fragment.contains("@=") {
            items.push(field_item(fragment));
        } else if !items.is_empty() {
            items.push(Item::Fragment(fragment.clone()));
        }
    }

    let element = to_value(items);
    match index {
        Some(position) => {
            let mut slots: Vec<serde_json::Value> = vec![serde_json::Value::Null; position + 1];
            slots[position] = element;
            serde_json::Value::Array(slots)
        }
        None => element,
    }
}

/// 容器内的一段内容。
#[derive(Debug, Clone)]
enum Item {
    /// `k=v` 字段（已取出键值）。
    Field { key: String, value: String },
    /// 不含 `@=` 的续写片段（裸 `/` 的 URL 续写）。
    Fragment(String),
    /// 数组元素的直接值（`uat@=1@=cdn.example.com` 的 `cdn.example.com`）。
    Scalar(String),
}

impl Item {
    /// 取该段对应的文本（字段取值，片段/标量取自身）。
    fn text(&self) -> &str {
        match self {
            Item::Field { value, .. } => value,
            Item::Fragment(text) | Item::Scalar(text) => text,
        }
    }
}

/// 容器项序列 -> 值：全是字段则构成对象；首项是标量则拼成字符串。
///
/// 尾随的 [`Item::Fragment`] 并回前一段并补 `/`（值里的 `/` 未转义成 `@S` 的容错）。
fn to_value(items: Vec<Item>) -> serde_json::Value {
    // 首项是标量 -> 整个元素是字符串（片段续写用 `/` 连接）
    if matches!(items.first(), Some(Item::Scalar(_))) {
        let text = items.iter().map(Item::text).collect::<Vec<_>>().join("/");
        return serde_json::Value::String(text);
    }
    let mut map = serde_json::Map::new();
    for item in items {
        match item {
            Item::Field { key, value } => {
                map.insert(key, serde_json::Value::String(value));
            }
            other => {
                // 续写片段并回上一个值
                if let Some(serde_json::Value::String(previous)) = map.values_mut().next_back() {
                    previous.push('/');
                    previous.push_str(other.text());
                }
            }
        }
    }
    serde_json::Value::Object(map)
}

/// 把 `k=v` 片段转成 [`Item::Field`]（值取**最后一段**：`k@=0@=cdn.com` -> `cdn.com`）。
fn field_item(field: &str) -> Item {
    match field.split_once("@=") {
        Some((key, raw)) => Item::Field {
            key: key.to_string(),
            value: unescape(raw.rsplit("@=").next().unwrap_or(raw)),
        },
        None => Item::Scalar(unescape(field)),
    }
}

/// 拆解容器首段 -> `(数组下标, 首项)`。
fn split_container_head(head: &str) -> (Option<usize>, Option<Item>) {
    let Some((prefix, remainder)) = head.split_once('@') else {
        // `<下标>` 独占首段（`k@=0/…`）
        return match head.parse::<usize>() {
            Ok(position) => (Some(position), None),
            Err(_) => (None, Some(field_item(head))),
        };
    };
    let Ok(position) = prefix.parse::<usize>() else {
        return (None, Some(field_item(head)));
    };
    // `<下标>@=<值>`：去掉下标与紧随的 '='，余下不含 k=v 即为标量值
    let remainder = remainder.strip_prefix('=').unwrap_or(remainder);
    if remainder.contains("@=") {
        (Some(position), Some(field_item(remainder)))
    } else {
        (Some(position), Some(Item::Scalar(unescape(remainder))))
    }
}

/// `@S` -> `/`，`@A` -> `@`（对齐 `unscapeSlashAt`）。
///
/// 长度收缩（2 -> 1 字符），故用游标式 `replace_range` 而非 `replace`。
pub fn unescape(text: &str) -> String {
    let mut out = text.to_string();
    for (token, replacement) in [("@S", "/"), ("@A", "@")] {
        if !out.contains(token) {
            continue;
        }
        let mut result = String::with_capacity(out.len());
        let mut rest = out.as_str();
        while let Some(index) = rest.find(token) {
            result.push_str(&rest[..index]);
            result.push_str(replacement);
            rest = &rest[index + token.len()..];
        }
        result.push_str(rest);
        out = result;
    }
    out
}

/// 登录包（`loginreq`）。
pub fn login_payload(room_id: &str) -> String {
    format!("type@=loginreq/roomid@={room_id}/")
}

/// 进组包（`joingroup`）。
///
/// `gid` 用 Dart 的 `-9999`（固定值；DTV 用的 `1` 是另一套实现，行为基准以 Dart core 为准）。
pub fn join_payload(room_id: &str) -> String {
    format!("type@=joingroup/rid@={room_id}/gid@=-9999/")
}

/// 心跳包（`mrkl`）。
pub fn heartbeat_payload() -> String {
    "type@=mrkl/".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialize_matches_dart_golden_bytes() {
        // Dart: serializeDouyu("type@=mrkl/")
        let frame = serialize("type@=mrkl/");
        let body = "type@=mrkl/";
        let full = (body.len() + 9) as u32; // 11 + 9 = 20
        assert_eq!(full, 20);
        assert_eq!(
            frame.len(),
            body.len() + 13,
            "帧长 = 12 字节头 + 载荷 + 1 字节结束符"
        );
        assert_eq!(&frame[0..4], &20u32.to_le_bytes(), "全长小端 = 20");
        assert_eq!(&frame[4..8], &frame[0..4], "第二个全长与第一个相同");
        assert_eq!(
            &frame[8..10],
            &689u16.to_le_bytes(),
            "包类型 689 小端"
        );
        assert_eq!(frame[10], 0, "加密标志");
        assert_eq!(frame[11], 0, "保留位");
        assert_eq!(&frame[12..12 + body.len()], body.as_bytes());
        assert_eq!(*frame.last().expect("结束符"), 0);
    }

    #[test]
    fn serialize_matches_qa_golden_fixture_bytes() {
        // 与 tests/fixtures/douyu/ws/req-loginreq.expected.json 的 bytes_hex 对齐
        let body = login_payload("252140");
        let frame = serialize(&body);
        let mut expected = Vec::new();
        expected.extend_from_slice(&0x27u32.to_le_bytes());
        expected.extend_from_slice(&0x27u32.to_le_bytes());
        expected.extend_from_slice(&[0xb1, 0x02]);
        expected.extend_from_slice(&[0, 0]);
        expected.extend_from_slice(body.as_bytes());
        expected.push(0);
        assert_eq!(frame, expected, "loginreq 封包必须与 QA 夹具逐字节一致");
        assert_eq!(frame.len(), 43);
    }

    #[test]
    fn serialize_roundtrips_through_deserialize() {
        for body in [
            login_payload("999").as_str(),
            join_payload("999").as_str(),
            heartbeat_payload().as_str(),
        ] {
            let frame = serialize(body);
            assert_eq!(deserialize(&frame).as_deref(), Some(body));
        }
    }

    #[test]
    fn deserialize_rejects_truncated_and_oversized_frames() {
        assert!(deserialize(&[]).is_none());
        assert!(deserialize(&[1, 2, 3]).is_none(), "不足 13 字节");
        // 头声明 100 字节但实际只给 13
        let mut frame = serialize("type@=mrkl/");
        frame[0] = 100;
        assert!(deserialize(&frame).is_none(), "声明长度超出实际必须拒绝");
        // 全长小于 9 -> 下溢保护
        let mut tiny = serialize("x");
        tiny[0] = 1;
        assert!(deserialize(&tiny).is_none(), "全长非法必须拒绝");
    }

    #[test]
    fn deserialize_rejects_frame_without_terminator() {
        let mut frame = serialize("type@=mrkl/");
        frame.pop();
        assert!(
            deserialize(&frame).is_none(),
            "缺结束符时 Dart 会越界抛错 -> 整帧丢弃，本实现同口径"
        );
    }

    #[test]
    fn stt_parses_nested_object_and_array() {
        let value = stt_to_value("type@=chatmsg/nn@=主播/txt@=你好/col@=1/");
        assert_eq!(value["type"], "chatmsg");
        assert_eq!(value["nn"], "主播");
        assert_eq!(value["txt"], "你好");
        assert_eq!(value["col"], "1");
    }

    #[test]
    fn stt_parses_array_by_double_slash() {
        // Dart: 含 "//" 即整体按数组切分，每段再递归（每段本身是 `k=v` -> 对象）
        let value = stt_to_value("a@=1//b@=2//");
        assert_eq!(
            value,
            serde_json::json!([{"a": "1"}, {"b": "2"}]),
            "//数组的每个元素仍是对象（Dart sttToJObject 的递归口径）"
        );
        // 空段被跳过
        assert_eq!(
            stt_to_value("//a@=1//"),
            serde_json::json!([{"a": "1"}])
        );
    }

    #[test]
    fn stt_unescapes_slash_and_at() {
        let value = stt_to_value("txt@=a@Sb@Ac/");
        assert_eq!(value["txt"], "a/b@c", "@S->/ 且 @A->@");
        assert_eq!(unescape("@S"), "/");
        assert_eq!(unescape("@A"), "@");
        assert_eq!(unescape("plain"), "plain");
    }

    #[test]
    fn stt_at_a_prefix_escape_can_create_a_false_pair() {
        // 对齐 Dart：`unescapeSlashAt("key@A=a@Sb")` = "key@=a/b"，其中新产生的 "@=" 让下一轮
        // 走进 k=v 分支 —— 结果是对象 {"key":"a"}，而不是整串。这是 Dart 的既有行为。
        let value = stt_to_value("key@A=a@Sb");
        assert_eq!(value, serde_json::json!({"key": "a"}));
        assert_eq!(
            unescape("key@A=a@Sb"),
            "key@=a/b",
            "反转义先于 k=v 判定，@A= 会被还原成 @="
        );
    }

    #[test]
    fn container_fields_collect_following_fields() {
        // comm_chatmsg: chatmsg@= 之后的字段全部归属嵌套对象
        let value = stt_to_value_with(
            "type@=comm_chatmsg/cprice@=5000/chatmsg@=nn@=土豪/txt@=666/ic@=face1/",
            &["chatmsg"],
        );
        assert_eq!(value["type"], "comm_chatmsg");
        assert_eq!(value["cprice"], "5000");
        assert_eq!(value["chatmsg"]["nn"], "土豪");
        assert_eq!(value["chatmsg"]["txt"], "666");
        assert_eq!(value["chatmsg"]["ic"], "face1");
    }

    #[test]
    fn container_with_numeric_head_becomes_array() {
        // voice_trlt: list@=0@un@=A/… -> 数组第 0 项（值里裸 '/' 的片段并回上一字段）
        let value = stt_to_value_with(
            "type@=voice_trlt/list@=0@un@=A/content@=B/uat@=1@=cdn.example.com/avatar.png",
            &["list", "uat"],
        );
        assert_eq!(value["list"][0]["un"], "A");
        assert_eq!(value["list"][0]["content"], "B");
        assert_eq!(
            value["list"][0]["uat"], "cdn.example.com/avatar.png",
            "容器内 k@=<下标>@=<值> 取最后一段，裸 '/' 片段并回"
        );
    }

    #[test]
    fn top_level_container_key_collects_remaining_fields() {
        // uat 作为顶层容器键时，其后字段全部归属它
        let value = stt_to_value_with("type@=x/uat@=0@=cdn.example.com/a.png", &["uat"]);
        assert_eq!(value["uat"][0], "cdn.example.com/a.png");
    }

    #[test]
    fn default_parser_is_unchanged_by_containers_arg() {
        // 不传容器名时行为必须与 Dart 扁平解析完全一致
        let text = "type@=chatmsg/nn@=a/txt@=b/col@=1/";
        assert_eq!(
            stt_to_value_with(text, &[]),
            stt_to_value(text),
            "空容器列表等价于默认解析"
        );
    }

    #[test]
    fn payloads_match_dart_literals() {
        assert_eq!(login_payload("999"), "type@=loginreq/roomid@=999/");
        assert_eq!(join_payload("999"), "type@=joingroup/rid@=999/gid@=-9999/");
        assert_eq!(heartbeat_payload(), "type@=mrkl/");
    }
}