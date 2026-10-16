//! 抖音模块内部工具（纯函数，无业务、无副作用）。
//!
//! 对齐 Dart `douyin_site.dart` 的私有助手：`_asMap` / `_firstUrl` / `_errorPrompt` /
//! `_safeJsonDecode` / `generateRandomNumber`，以及 `DouyinUtils.getMSToken`。
//!
//! ⚠️ **随机源说明**：core crate 依赖表里**没有** `rand`（§4.1 锁定清单），
//! 而 Dart 的 `generateRandomNumber` 用 `Random.secure()`。这里改用
//! 「纳秒时钟 + splitmix64 混淆」派生伪随机数 —— 该值只是**观众唯一 ID**
//! （Dart 注释原文：「似乎这个参数不是必须的，先随机生成一个」），服务端不校验，
//! 因此不构成安全边界。**不得**用于任何凭证/签名相关随机。

use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::error::SliveError;

/// 安全地把动态值当对象用；非对象一律 `None`（对齐 Dart `_asMap`）。
pub fn as_object(value: Option<&Value>) -> Option<&serde_json::Map<String, Value>> {
    value.and_then(Value::as_object)
}

/// 取 `{"url_list": ["..."]}` 里的第一个地址；取不到返回空串（对齐 `_firstUrl`）。
pub fn first_url(value: Option<&Value>) -> String {
    as_object(value)
        .and_then(|o| o.get("url_list"))
        .and_then(Value::as_array)
        .and_then(|a| a.first())
        .map(crate::util::value_to_string)
        .unwrap_or_default()
}

/// 网页版错误提示（`detailExtra.errorPrompts`）；取不到返回空串。
///
/// 该字段常见形态是**字符串数组**而非对象（Dart 曾用 `_asMap(...).toString()` 取值
/// 恒为 null，使那段提示成为死代码）—— 这里字符串/数组两种形态都认。
pub fn error_prompt(room_data: &Value) -> String {
    let Some(extra) = as_object(room_data.get("detailExtra")) else {
        return String::new();
    };
    match extra.get("errorPrompts") {
        Some(Value::String(s)) if !s.is_empty() => s.clone(),
        Some(Value::Array(a)) => a
            .first()
            .map(crate::util::value_to_string)
            .unwrap_or_default(),
        _ => String::new(),
    }
}

/// 解析 JSON 串；空串/非法 JSON -> `None`（对齐 `_safeJsonDecode`，**不抛**）。
///
/// 用途：`stream_data` 可能被风控截断成半截 JSON，抛异常会让整个直播间判成「加载失败」。
pub fn safe_json_decode(source: &str) -> Option<Value> {
    if source.is_empty() {
        return None;
    }
    serde_json::from_str(source).ok()
}

/// 解析 JSON 串并要求是对象；失败 -> `None`。
pub fn safe_json_object(source: &str) -> Option<serde_json::Map<String, Value>> {
    safe_json_decode(source).and_then(|v| v.as_object().cloned())
}

/// 生成 `length` 位十进制随机数字符串（对齐 Dart `generateRandomNumber(length).toString()`）。
///
/// Dart 版是「逐位 `nextInt(10)` 拼接后 parse」，12 位必然落在 i64 内，故等价于
/// 「固定 12 位数字串」。首位为 0 时 Dart 会 `int.tryParse` 成功（`0` 开头不丢位），
/// 输出与本实现一致。
pub fn random_digits(length: usize) -> String {
    (0..length)
        .map(|_| char::from(b'0' + (next_u64() % 10) as u8))
        .collect()
}

/// 生成 `random_length` 位 msToken（对齐 Dart `DouyinUtils.getMSToken`）。
///
/// ⚠️ 字母表**照抄** Dart 的字面串 `'ABCDEFGHIGKLMNOPQRSTUVWXYZabcdefghigklmnopqrstuvwxyz0123456789='`：
/// 其中 `HIG` / `hig` 三个字符重复（J 与 K 之间多了 H、o 与 p 之间多了 h），
/// 是上游的笔误，但**签名校验依赖字符分布**，擅自「修正」会让 a_bogus 被服务端拒绝。
pub fn ms_token(random_length: usize) -> String {
    const BASE: &[u8] = b"ABCDEFGHIGKLMNOPQRSTUVWXYZabcdefghigklmnopqrstuvwxyz0123456789=";
    (0..random_length)
        .map(|_| BASE[(next_u64() % BASE.len() as u64) as usize] as char)
        .collect()
}

/// msToken 默认长度（Dart `getMSToken(randomLength = 184)`）。
pub const MS_TOKEN_LENGTH: usize = 184;

/// 伪随机 u64（splitmix64 + 纳秒时钟播种；用途见模块注释的随机源说明）。
fn next_u64() -> u64 {
    use std::cell::Cell;
    thread_local! {
        static STATE: Cell<u64> = const { Cell::new(0) };
    }
    STATE.with(|s| {
        let mut z = s.get();
        if z == 0 {
            z = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0x9E37_79B9_7F4A_7C15)
                | 1;
        }
        z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
        s.set(z);
        let mut x = z;
        x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        x ^ (x >> 31)
    })
}

/// 顺序敏感的 query 参数容器（对齐 Dart `LinkedHashMap` 的插入序）。
///
/// a_bogus 对 query 串做签名，**顺序变了签名就变**，所以不能用
/// `HashMap`（Dart 侧 `buildRequestUrl` 是就地 `exParams['aid'] = ...` 覆盖：
/// 已存在的键**保留原位置**）。
#[derive(Debug, Clone, Default)]
pub struct QueryParams(Vec<(String, String)>);

impl QueryParams {
    /// 新建空容器。
    pub fn new() -> Self {
        Self(Vec::new())
    }

    /// 追加（键已存在则**原位覆盖**，保持位置不变 —— 对齐 Dart Map 赋值语义）。
    pub fn put(&mut self, key: &str, value: impl Into<String>) -> &mut Self {
        let value = value.into();
        match self.0.iter_mut().find(|(k, _)| k == key) {
            Some(slot) => slot.1 = value,
            None => self.0.push((key.to_string(), value)),
        }
        self
    }

    /// 键是否存在。
    pub fn contains(&self, key: &str) -> bool {
        self.0.iter().any(|(k, _)| k == key)
    }

    /// 迭代（顺序即签名顺序）。
    pub fn iter(&self) -> impl Iterator<Item = (&str, &str)> {
        self.0.iter().map(|(k, v)| (k.as_str(), v.as_str()))
    }

    /// 编码为 query 串（`Uri(queryParameters:).query` 口径：空格 -> `+`）。
    pub fn to_query(&self) -> String {
        self.0
            .iter()
            .map(|(k, v)| {
                format!(
                    "{}={}",
                    crate::util::encode_query_component(k),
                    crate::util::encode_query_component(v)
                )
            })
            .collect::<Vec<_>>()
            .join("&")
    }
}

/// 对象转 JSON 串（`LiveRoomDetail.data` 的 JSON 通道，§4.4）。
pub fn to_json_string(value: &Value) -> Result<String, SliveError> {
    serde_json::to_string(value)
        .map_err(|e| SliveError::decode(format!("序列化附加数据失败: {e}")))
}

/// 地址数组转 JSON 串（`LivePlayQuality.data` 的 JSON 通道）。
pub fn urls_to_json(urls: &[String]) -> String {
    // `Vec<String>` 的 serde 形态恒为 JSON 数组字面量，不含非法字符。
    serde_json::to_string(urls).unwrap_or_else(|_| "[]".to_string())
}

/// JSON 串（地址数组）还原为地址列表；非法 JSON -> `Decode`（消费失败必须显式报错）。
pub fn urls_from_json(raw: &str) -> Result<Vec<String>, SliveError> {
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str::<Vec<String>>(raw)
        .map_err(|e| SliveError::decode(format!("播放地址反序列化失败: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn first_url_reads_first_of_url_list() {
        let v = json!({"url_list": ["https://a", "https://b"]});
        assert_eq!(first_url(Some(&v)), "https://a");
        assert_eq!(first_url(Some(&json!({}))), "");
        assert_eq!(first_url(None), "");
        assert_eq!(first_url(Some(&json!("not-object"))), "");
    }

    #[test]
    fn error_prompt_accepts_string_and_array_forms() {
        assert_eq!(
            error_prompt(&json!({"detailExtra": {"errorPrompts": "房间不存在"}})),
            "房间不存在"
        );
        assert_eq!(
            error_prompt(&json!({"detailExtra": {"errorPrompts": ["已下播", "x"]}})),
            "已下播"
        );
        assert_eq!(error_prompt(&json!({})), "");
        assert_eq!(error_prompt(&json!({"detailExtra": {"errorPrompts": {}}})), "");
    }

    #[test]
    fn safe_json_decode_never_panics_on_truncated_json() {
        assert_eq!(safe_json_decode(""), None);
        assert_eq!(safe_json_decode(r#"{"a":1"#), None, "半截 JSON 必须降级为 None");
        assert_eq!(safe_json_decode(r#"{"a":1}"#).unwrap()["a"], json!(1));
    }

    #[test]
    fn query_params_preserve_insertion_order_and_overwrite_in_place() {
        let mut q = QueryParams::new();
        q.put("aid", "6383").put("app_name", "douyin_web").put("aid", "6384");
        assert_eq!(q.to_query(), "aid=6384&app_name=douyin_web", "覆盖须保留原位置");
        assert!(q.contains("aid"));
        assert!(!q.contains("msToken"));
    }

    #[test]
    fn query_params_encode_spaces_as_plus() {
        let mut q = QueryParams::new();
        q.put("k", "a b&c");
        assert_eq!(q.to_query(), "k=a+b%26c");
    }

    #[test]
    fn random_digits_has_requested_length_and_decimal_only() {
        let s = random_digits(12);
        assert_eq!(s.len(), 12);
        assert!(s.chars().all(|c| c.is_ascii_digit()), "实际 {s}");
    }

    #[test]
    fn ms_token_uses_dart_literal_alphabet() {
        let s = ms_token(64);
        assert_eq!(s.len(), 64);
        assert!(
            s.chars().all(|c| c.is_ascii_alphanumeric() || c == '='),
            "实际 {s}"
        );
        // 上游笔误：`J` 不在字母表内（HGIK 之间多一个 H）
        assert!(!s.contains('J'), "字母表须照抄 Dart 字面串");
    }

    #[test]
    fn urls_json_roundtrip() {
        let urls = vec!["https://a.flv".to_string(), "https://a.m3u8".to_string()];
        let raw = urls_to_json(&urls);
        assert_eq!(raw, r#"["https://a.flv","https://a.m3u8"]"#);
        assert_eq!(urls_from_json(&raw).expect("往返"), urls);
        assert_eq!(urls_from_json("").expect("空串视为空列表"), Vec::<String>::new());
        assert!(matches!(
            urls_from_json("not json"),
            Err(SliveError::Decode(_))
        ));
    }
}
