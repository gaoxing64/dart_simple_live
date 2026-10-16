//! 抖音弹幕参数数据契约（对照 Dart `DouyinDanmakuArgs`）。
//!
//! `LiveRoomDetail.danmaku_data` 承载本结构的 JSON 串（键名 snake_case、顺序稳定）。
//! 与 B站同款契约：`schema_version` 固定 `1`；缺字段/非法 JSON/版本不符 ->
//! [`SliveError::Decode`]（J-10：Dart 侧解析失败必须抛 `FormatException`，不得静默兜底）。
//!
//! ⚠️ 与 Dart 的差异（刻意）：Dart `DouyinDanmakuArgs.toString()` 的键名是 camelCase
//! （`webRid/roomId/userId`），Rust 契约统一 snake_case（与 B站 `BiliBiliDanmakuArgs`
//! 同构），绑定层负责翻译 —— 否则 serde 反序列化与 `LiveMessage` 契约割裂。

use serde::{Deserialize, Serialize};

use crate::error::SliveError;

/// 契约版本（消费方校验 `== 1`，否则拒绝）。
pub const DOUYIN_DANMAKU_ARGS_SCHEMA_VERSION: i32 = 1;

/// 弹幕 WS 主机（对照 Dart `DouyinDanmaku.serverUrl`）。
pub const DEFAULT_WS_HOST: &str = "webcast100-ws-web-lq.douyin.com";
/// 备用 WS 主机（Dart `backupUrl`：主域名里的 `webcast3-ws-web-lq` 换成 `webcast5-ws-web-lf`）。
pub const BACKUP_WS_HOST: &str = "webcast5-ws-web-lf.douyin.com";
/// WS 路径（`webcast/im/push/v2/`）。
pub const WS_PATH: &str = "webcast/im/push/v2/";

/// 抖音默认 UA（对照 `DouyinRequestParams.kDefaultUserAgent`）。
pub const DEFAULT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0";
/// `version_code`（对照 `DouyinRequestParams.versionCodeValue`）。
pub const VERSION_CODE: &str = "180800";
/// `webcast_sdk_version`（对照 `DouyinRequestParams.sdkVersion`）。
pub const SDK_VERSION: &str = "1.0.14-beta.0";
/// `aid`（对照 `DouyinRequestParams.aidValue`）。
pub const AID: &str = "6383";

/// 弹幕连接参数（`get_room_detail` 产出，`start_douyin_danmaku` 消费）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DouyinDanmakuArgs {
    /// 契约版本（固定 1）。
    pub schema_version: i32,
    /// 直播间 web 房间号（11~12 位，如 `416144012050`）。
    pub web_rid: String,
    /// 真实房间号（19 位，每次开播新生成）。
    pub room_id: String,
    /// 观众唯一 ID（Dart 用 `generateRandomNumber(12)` 随机生成）。
    pub user_id: String,
    /// 请求 cookie（允许空串）。
    pub cookie: String,
}

impl DouyinDanmakuArgs {
    /// 构造（`schema_version` 固定为 1）。
    pub fn new(web_rid: String, room_id: String, user_id: String, cookie: String) -> Self {
        Self {
            schema_version: DOUYIN_DANMAKU_ARGS_SCHEMA_VERSION,
            web_rid,
            room_id,
            user_id,
            cookie,
        }
    }

    /// 序列化为 JSON 串（键序稳定）。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self)
            .map_err(|e| SliveError::decode(format!("序列化弹幕参数失败: {e}")))
    }

    /// 从 JSON 串反序列化并校验版本。
    ///
    /// 缺字段 -> `Decode`；非法 JSON -> `Decode`；`schema_version != 1` -> `Decode`。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        let args: Self = serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("弹幕参数反序列化失败: {e}")))?;
        if args.schema_version != DOUYIN_DANMAKU_ARGS_SCHEMA_VERSION {
            return Err(SliveError::decode(format!(
                "弹幕参数 schema_version 不符：期望 {}，实际 {}",
                DOUYIN_DANMAKU_ARGS_SCHEMA_VERSION, args.schema_version
            )));
        }
        Ok(args)
    }

    /// WS 握手签名用的 query 串（**不含** `signature=`）。
    ///
    /// 参数与顺序逐条对照 Dart `DouyinDanmaku.start` 的 `Uri.replace(queryParameters: {...})`，
    /// 顺序影响签名结果，不可重排。`cursor` 含毫秒时间戳，由调用方注入。
    pub fn sign_query(&self, ts_millis: u64) -> String {
        let browser_version = DEFAULT_USER_AGENT.replace("Mozilla/", "");
        // 值内含 `/` `(` `)` `;` `,` 等分隔符，必须百分号编码（Dart Uri 自动编码）。
        let params: Vec<(&str, String)> = vec![
            ("app_name", "douyin_web".to_string()),
            ("version_code", VERSION_CODE.to_string()),
            ("webcast_sdk_version", SDK_VERSION.to_string()),
            ("update_version_code", SDK_VERSION.to_string()),
            ("compress", "gzip".to_string()),
            ("cursor", format!("h-1_t-{ts_millis}_r-1_d-1_u-1")),
            ("host", "https://live.douyin.com".to_string()),
            ("aid", AID.to_string()),
            ("live_id", "1".to_string()),
            ("did_rule", "3".to_string()),
            ("debug", "false".to_string()),
            ("maxCacheMessageNumber", "20".to_string()),
            ("endpoint", "live_pc".to_string()),
            ("support_wrds", "1".to_string()),
            ("im_path", "/webcast/im/fetch/".to_string()),
            ("user_unique_id", self.user_id.clone()),
            ("device_platform", "web".to_string()),
            ("cookie_enabled", "true".to_string()),
            ("screen_width", "1920".to_string()),
            ("screen_height", "1080".to_string()),
            ("browser_language", "zh-CN".to_string()),
            ("browser_platform", "Win32".to_string()),
            ("browser_name", "Mozilla".to_string()),
            ("browser_version", browser_version),
            ("browser_online", "true".to_string()),
            ("tz_name", "Asia/Shanghai".to_string()),
            ("identity", "audience".to_string()),
            ("room_id", self.room_id.clone()),
            ("heartbeatDuration", "0".to_string()),
        ];
        params
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

    /// WS 地址（`host` 可覆盖，用于主备切换）。
    ///
    /// `signature` 由 `signature::x_bogus` 产出（协议信息归核心，桥层只转发 —— AC-39）。
    pub fn ws_url(&self, host: &str, ts_millis: u64, signature: &str) -> String {
        format!(
            "wss://{host}/{WS_PATH}?{}&signature={signature}",
            self.sign_query(ts_millis)
        )
    }

    /// 主域名（Dart `serverUrl`）。
    pub fn primary_host(&self) -> &'static str {
        DEFAULT_WS_HOST
    }

    /// 备用域名（Dart `backupUrl`：`webcast3-ws-web-lq` -> `webcast5-ws-web-lf`）。
    pub fn backup_host(&self) -> &'static str {
        BACKUP_WS_HOST
    }

    /// 连接请求头（对齐 Dart `DouyinDanmaku.start` 的 headers）。
    pub fn connect_headers(&self) -> Vec<(String, String)> {
        vec![
            ("User-Agent".to_string(), DEFAULT_USER_AGENT.to_string()),
            ("Cookie".to_string(), self.cookie.clone()),
            ("Origin".to_string(), "https://live.douyin.com".to_string()),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::parse_query;

    fn sample() -> DouyinDanmakuArgs {
        DouyinDanmakuArgs::new(
            "416144012050".into(),
            "7382735338101328680".into(),
            "7273033021933946".into(),
            "ttwid=1%2Cabc;".into(),
        )
    }

    #[test]
    fn roundtrip_preserves_fields() {
        let args = sample();
        let json = args.to_json().expect("序列化");
        assert_eq!(DouyinDanmakuArgs::from_json(&json).expect("反序列化"), args);
    }

    #[test]
    fn missing_field_is_decode_error() {
        let err = DouyinDanmakuArgs::from_json(r#"{"schema_version":1,"room_id":"1"}"#)
            .expect_err("缺字段应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn wrong_schema_version_is_rejected() {
        let json = r#"{"schema_version":2,"web_rid":"w","room_id":"r","user_id":"u","cookie":""}"#;
        let err = DouyinDanmakuArgs::from_json(json).expect_err("版本不符应报错");
        match err {
            SliveError::Decode(msg) => assert!(msg.contains("schema_version"), "实际 {msg}"),
            other => panic!("期望 Decode，实际 {other:?}"),
        }
    }

    #[test]
    fn sign_query_matches_dart_param_order() {
        let args = sample();
        let query = args.sign_query(1_700_000_000_000);
        let pairs = parse_query(&format!("wss://x/?{query}"));
        let keys: Vec<&str> = pairs.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(
            keys,
            vec![
                "app_name",
                "version_code",
                "webcast_sdk_version",
                "update_version_code",
                "compress",
                "cursor",
                "host",
                "aid",
                "live_id",
                "did_rule",
                "debug",
                "maxCacheMessageNumber",
                "endpoint",
                "support_wrds",
                "im_path",
                "user_unique_id",
                "device_platform",
                "cookie_enabled",
                "screen_width",
                "screen_height",
                "browser_language",
                "browser_platform",
                "browser_name",
                "browser_version",
                "browser_online",
                "tz_name",
                "identity",
                "room_id",
                "heartbeatDuration",
            ],
            "参数顺序参与签名，重排即与服务端不兼容"
        );
    }

    #[test]
    fn cursor_embeds_injected_timestamp() {
        let query = sample().sign_query(1_700_000_000_123);
        assert!(
            query.contains("cursor=h-1_t-1700000000123_r-1_d-1_u-1"),
            "cursor 未带注入时间戳：{query}"
        );
    }

    #[test]
    fn ws_url_appends_signature_and_keeps_path() {
        let url = sample().ws_url("webcast100-ws-web-lq.douyin.com", 42, "SIG");
        assert!(url.starts_with("wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/?"));
        assert!(url.ends_with("&signature=SIG"), "实际 {url}");
    }

    #[test]
    fn browser_version_strips_mozilla_prefix_and_encodes() {
        let query = sample().sign_query(1);
        // Dart `Uri(queryParameters:)` 的编码口径：空格 -> `+`，`(` -> `%28`
        assert!(
            query.contains("browser_version=5.0+%28Windows"),
            "browser_version 应剥掉 Mozilla/ 并编码：{query}"
        );
    }

    #[test]
    fn connect_headers_carry_ua_cookie_origin() {
        let headers = sample().connect_headers();
        let get = |k: &str| {
            headers
                .iter()
                .find(|(hk, _)| hk.eq_ignore_ascii_case(k))
                .map(|(_, v)| v.clone())
                .unwrap_or_default()
        };
        assert_eq!(get("user-agent"), DEFAULT_USER_AGENT);
        assert_eq!(get("cookie"), "ttwid=1%2Cabc;");
        assert_eq!(get("origin"), "https://live.douyin.com");
    }
}
