//! Twitch 弹幕数据契约（`LiveRoomDetail.danmaku_data` 承载本结构的 JSON 串）。
//!
//! 与 B站 `BiliBiliDanmakuArgs` 同构：`schema_version` 固定 `1`；缺字段 / 非法 JSON /
//! 版本不符 -> [`SliveError::Decode`]（J-10：Dart 侧解析失败必须抛错，不得静默兜底）。
//!
//! Twitch 侧参数极简：**只需频道名**（IRC `JOIN #<channel>`），匿名登录不需要 token。

use serde::{Deserialize, Serialize};

use crate::error::SliveError;

/// 契约版本（消费方校验 `== 1`）。
pub const TWITCH_DANMAKU_ARGS_SCHEMA_VERSION: i32 = 1;
/// IRC over WebSocket 服务地址（对齐 `twitch_danmaku.dart:13`）。
pub const IRC_WS_URL: &str = "wss://irc-ws.chat.twitch.tv";

/// Twitch 弹幕连接参数（`get_room_detail` 产出，`start_twitch_danmaku` 消费）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TwitchDanmakuArgs {
    /// 契约版本（固定 1）。
    pub schema_version: i32,
    /// 频道名（Twitch 的 login，小写；IRC `JOIN #<channel>`）。
    pub channel: String,
}

impl TwitchDanmakuArgs {
    /// 构造（`schema_version` 固定为 1）。
    pub fn new(channel: &str) -> Self {
        Self {
            schema_version: TWITCH_DANMAKU_ARGS_SCHEMA_VERSION,
            channel: channel.to_ascii_lowercase(),
        }
    }

    /// 序列化为 JSON 串（键序稳定）。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self).map_err(|e| SliveError::decode(format!("序列化弹幕参数失败: {e}")))
    }

    /// 从 JSON 串反序列化并校验版本。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        let args: Self = serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("弹幕参数反序列化失败: {e}")))?;
        if args.schema_version != TWITCH_DANMAKU_ARGS_SCHEMA_VERSION {
            return Err(SliveError::decode(format!(
                "弹幕参数 schema_version 不符：期望 {}，实际 {}",
                TWITCH_DANMAKU_ARGS_SCHEMA_VERSION, args.schema_version
            )));
        }
        if args.channel.trim().is_empty() {
            return Err(SliveError::decode("弹幕参数 channel 为空".to_string()));
        }
        Ok(args)
    }

    /// WS 连接地址（协议信息归核心，桥层只转发 —— AC-39）。
    pub fn ws_url(&self) -> String {
        IRC_WS_URL.to_string()
    }

    /// 连接请求头。
    ///
    /// Twitch IRC 不强制 UA，但缺 UA 的裸握手会被部分边缘节点拒绝；这里带站点 UA +
    /// `Origin: https://www.twitch.tv`（对齐浏览器，参考 B站真机同类修复）。
    pub fn connect_headers(&self) -> Vec<(String, String)> {
        vec![
            (
                "user-agent".to_string(),
                super::super::header::TWITCH_USER_AGENT.to_string(),
            ),
            ("origin".to_string(), super::super::header::TWITCH_BASE_URL.to_string()),
        ]
    }

    /// 握手帧序列（`CAP REQ` -> `PASS` -> `NICK` -> `USER` -> `JOIN`）。
    ///
    /// 顺序与 Dart `twitch_danmaku.dart:59-63` **逐条一致**（Twitch 要求先 `CAP REQ`
    /// 声明能力，`JOIN` 必须在登录之后）。
    pub fn handshake(&self, nick: &str) -> Vec<String> {
        vec![
            "CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership".to_string(),
            "PASS SCHMOOPIIE".to_string(),
            format!("NICK {nick}"),
            format!("USER {nick} 8 * :{nick}"),
            format!("JOIN #{}", self.channel),
        ]
    }

    /// 心跳帧（Twitch IRC keepalive；对齐 Dart `heartbeat()` 的 `PONG :tmi.twitch.tv`）。
    pub fn heartbeat_frame() -> String {
        "PONG :tmi.twitch.tv".to_string()
    }

    /// 匿名昵称（`justinfan<5 位数字>`，对齐 Dart `joinRoom` 的 `1000 + Random().nextInt(99000)`）。
    ///
    /// Dart 用真随机；Rust 无 `rand` 依赖（Cargo.toml 已冻结），改用**时间源派生**：
    /// 仍是 `justinfan` 前缀 + 1000~99999 的数字，服务端只要求「匿名用户」语义。
    pub fn anonymous_nick(unix_secs: u64) -> String {
        let suffix = 1000 + unix_secs % 99_000;
        format!("justinfan{suffix}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_preserves_fields_and_lowercases_channel() {
        let args = TwitchDanmakuArgs::new("XQC");
        assert_eq!(args.channel, "xqc", "频道名统一小写");
        let json = args.to_json().expect("序列化");
        assert_eq!(
            json,
            r#"{"schema_version":1,"channel":"xqc"}"#,
            "键序稳定，供 golden 断言"
        );
        assert_eq!(TwitchDanmakuArgs::from_json(&json).expect("反序列化"), args);
    }

    #[test]
    fn missing_field_is_decode_error() {
        let err = TwitchDanmakuArgs::from_json(r#"{"schema_version":1}"#)
            .expect_err("缺字段应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn wrong_schema_version_is_rejected() {
        let err =
            TwitchDanmakuArgs::from_json(r#"{"schema_version":2,"channel":"xqc"}"#).expect_err("版本不符");
        match err {
            SliveError::Decode(msg) => assert!(msg.contains("schema_version"), "实际 {msg}"),
            other => panic!("期望 Decode，实际 {other:?}"),
        }
    }

    #[test]
    fn empty_channel_is_rejected() {
        let err = TwitchDanmakuArgs::from_json(r#"{"schema_version":1,"channel":"  "}"#)
            .expect_err("空频道名应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn handshake_order_matches_dart() {
        let frames = TwitchDanmakuArgs::new("xqc").handshake("justinfan12345");
        assert_eq!(frames.len(), 5);
        assert!(frames[0].starts_with("CAP REQ"));
        assert_eq!(frames[1], "PASS SCHMOOPIIE");
        assert_eq!(frames[2], "NICK justinfan12345");
        assert_eq!(frames[3], "USER justinfan12345 8 * :justinfan12345");
        assert_eq!(frames[4], "JOIN #xqc");
    }

    #[test]
    fn nick_shape_and_heartbeat_match_dart() {
        let nick = TwitchDanmakuArgs::anonymous_nick(1_700_000_000);
        assert!(nick.starts_with("justinfan"));
        let digits: u64 = nick.trim_start_matches("justinfan").parse().expect("数字后缀");
        assert!((1000..100_000).contains(&digits), "实际 {digits}");
        assert_eq!(TwitchDanmakuArgs::heartbeat_frame(), "PONG :tmi.twitch.tv");
    }

    #[test]
    fn ws_url_and_headers_carry_ua_and_origin() {
        let args = TwitchDanmakuArgs::new("xqc");
        assert_eq!(args.ws_url(), IRC_WS_URL);
        let headers = args.connect_headers();
        assert!(headers.iter().any(|(k, v)| k == "user-agent" && v.contains("Chrome")));
        assert!(headers.iter().any(|(k, v)| k == "origin" && v == "https://www.twitch.tv"));
    }
}
