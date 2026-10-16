//! 斗鱼请求签名（`sign()`，对照 `douyu_utils.dart:109-158`）。
//!
//! 链路：`getEncryption` 拿一次性密钥材料（`rand_str/key/enc_time/is_special/enc_data`）
//! -> `enc_time` 次 md5 迭代得 `secret` -> 再拼 `salt` 求 `auth`
//! -> 按固定键序拼 form-urlencoded 请求体。
//!
//! 密钥材料**句柄级缓存 5 分钟**（Dart 是进程级静态 + 300s TTL，请求参数集合一致）。

use md5::{Digest, Md5};
use serde_json::Value;

use crate::error::SliveError;
use crate::util::encode_query_component;

use super::api_code::check_error_code;
use super::header::request_header;
use super::site::DouyuSite;

/// 加密材料端点。
const ENC_URL: &str = "https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption";
/// 缓存 TTL（秒），对齐 `_encCacheTTL`。
const ENC_CACHE_TTL_SECS: u64 = 5 * 60;
/// `sign()` 的默认线路（对齐 `douyu_utils.dart:129`）。
pub const DEFAULT_CDN: &str = "hw-h5";

/// 一次性加密材料。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncKey {
    /// 随机串。
    pub rand_str: String,
    /// 迭代密钥。
    pub key: String,
    /// md5 迭代次数。
    pub enc_time: i32,
    /// 是否特殊模式（`1` 时 `salt` 为空）。
    pub is_special: bool,
    /// 服务端下发的 `enc_data`。
    pub enc_data: String,
    /// 本地过期时间（Unix 秒）。
    pub expire_at: u64,
}

impl EncKey {
    /// 缓存是否仍然有效。
    pub fn is_valid_at(&self, now_secs: u64) -> bool {
        self.expire_at > now_secs
    }
}

/// 确保句柄内有可用加密材料（过期则回源）。
pub async fn ensure_enc_key(site: &DouyuSite) -> Result<(), SliveError> {
    if let Some(cached) = site.enc_key_cached() {
        if cached.is_valid_at(site.now_secs()) {
            return Ok(());
        }
    }
    let query = vec![("did".to_string(), site.dy_did())];
    let value = site
        .get_json_with(
            ENC_URL,
            query,
            request_header(site, "", &site.cookie(), false),
        )
        .await?;
    // 业务错误码优先判定：斗鱼用 `error` 而非 `code`（QA 夹具 error=1001「系统繁忙」）
    check_error_code(&value)?;
    let data = value
        .get("data")
        .filter(|d| d.is_object())
        .ok_or_else(|| SliveError::decode("加密材料响应缺 data 字段"))?;
    let key = EncKey {
        rand_str: string_field(data, "rand_str"),
        key: string_field(data, "key"),
        enc_time: data
            .get("enc_time")
            .and_then(Value::as_i64)
            .unwrap_or(1)
            .clamp(1, 64) as i32,
        is_special: data.get("is_special").and_then(Value::as_i64).unwrap_or(0) == 1,
        enc_data: string_field(data, "enc_data"),
        expire_at: site.now_secs() + ENC_CACHE_TTL_SECS,
    };
    site.set_enc_key(key);
    Ok(())
}

/// 构造取流签名请求体（`rate`/`cdn` 参与）。
///
/// 键序固定为 `enc_data/tt/did/auth/cdn/ver/rate/hevc/fa/ive`（对齐 Dart 的 `Uri(queryParameters:)`）。
pub async fn build_sign(
    site: &DouyuSite,
    room_id: &str,
    rate: i32,
    cdn: &str,
) -> Result<String, SliveError> {
    ensure_enc_key(site).await?;
    let key = site
        .enc_key_cached()
        .ok_or_else(|| SliveError::decode("加密材料缓存缺失"))?;

    let ts = site.now_secs();
    let salt = if key.is_special {
        String::new()
    } else {
        format!("{room_id}{ts}")
    };
    let mut secret = key.rand_str.clone();
    for _ in 0..key.enc_time {
        secret = md5_hex(&format!("{secret}{}", key.key));
    }
    let auth = md5_hex(&format!("{secret}{}{salt}", key.key));

    let params: Vec<(&str, String)> = vec![
        ("enc_data", key.enc_data),
        ("tt", ts.to_string()),
        ("did", site.dy_did()),
        ("auth", auth),
        ("cdn", cdn.to_string()),
        ("ver", "Douyu_new".to_string()),
        ("rate", rate.to_string()),
        ("hevc", "1".to_string()),
        ("fa", "0".to_string()),
        ("ive", "0".to_string()),
    ];
    Ok(params
        .iter()
        .map(|(k, v)| format!("{k}={}", encode_query_component(v)))
        .collect::<Vec<_>>()
        .join("&"))
}

/// 登录态相关请求也走同一签名（`cdn="hw-h5"`、`rate=-1`，见 Dart `sign` 默认值）。
pub async fn build_default_sign(site: &DouyuSite, room_id: &str) -> Result<String, SliveError> {
    build_sign(site, room_id, -1, DEFAULT_CDN).await
}

fn md5_hex(input: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(input.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn string_field(data: &Value, key: &str) -> String {
    data.get(key).map(crate::util::value_to_string).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use super::super::transport::MockDouyuPost;
    use std::sync::Arc;

    const ENC_FIXTURE: &str = r#"{"error":0,"data":{"key":"KEY-1","rand_str":"RAND-1","enc_time":2,"is_special":0,"enc_data":"ENC-1"}}"#;

    fn site(mock: &Arc<MockTransport>) -> DouyuSite {
        DouyuSite::with_deps(
            mock.clone(),
            Arc::new(MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        )
    }

    #[tokio::test]
    async fn sign_iterates_md5_and_keeps_key_order() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("getEncryption", ENC_FIXTURE);
        let s = site(&mock);

        let body = build_sign(&s, "999", 0, DEFAULT_CDN).await.expect("签名");

        // secret = md5("RAND-1KEY-1") -> md5(secret+"KEY-1"); auth = md5(secret+"KEY-1"+"9991700000000")
        let s1 = md5_hex("RAND-1KEY-1");
        let s2 = md5_hex(&format!("{s1}KEY-1"));
        let auth = md5_hex(&format!("{s2}KEY-19991700000000"));
        let expected = format!(
            "enc_data=ENC-1&tt=1700000000&did=10000000000000000000000000001501&auth={auth}&cdn=hw-h5&ver=Douyu_new&rate=0&hevc=1&fa=0&ive=0"
        );
        assert_eq!(body, expected);
        assert_eq!(mock.request_count("getEncryption"), 1);
    }

    #[tokio::test]
    async fn special_mode_uses_empty_salt() {
        let mock = Arc::new(MockTransport::new());
        mock.stub(
            "getEncryption",
            r#"{"error":0,"data":{"key":"K","rand_str":"R","enc_time":1,"is_special":1,"enc_data":"E"}}"#,
        );
        let s = site(&mock);
        let body = build_sign(&s, "999", -1, "hw-h5").await.expect("签名");
        let secret = md5_hex("RK");
        let auth = md5_hex(&format!("{secret}K"));
        assert!(body.contains(&format!("auth={auth}")), "is_special=1 时 salt 为空：{body}");
    }

    #[tokio::test]
    async fn enc_key_is_cached_within_ttl_and_refetched_after() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("getEncryption", ENC_FIXTURE);
        let time = Arc::new(FakeTime::new(1_700_000_000));
        let s = DouyuSite::with_deps(
            mock.clone(),
            Arc::new(MockDouyuPost::new()),
            time.clone(),
        );

        build_sign(&s, "1", 0, "hw-h5").await.expect("首次签名");
        build_sign(&s, "2", 0, "hw-h5").await.expect("二次签名");
        assert_eq!(mock.request_count("getEncryption"), 1, "TTL 内只回源一次");

        time.advance(5 * 60 + 1);
        build_sign(&s, "3", 0, "hw-h5").await.expect("过期后重新签名");
        assert_eq!(mock.request_count("getEncryption"), 2, "过期后回源");
    }

    #[tokio::test]
    async fn missing_data_is_decode_error() {
        let mock = Arc::new(MockTransport::new());
        mock.stub("getEncryption", r#"{"error":0}"#);
        let s = site(&mock);
        let err = build_sign(&s, "1", 0, "hw-h5")
            .await
            .expect_err("缺 data 必须报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }
}