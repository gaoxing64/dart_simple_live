//! 弹幕参数数据契约（`docs/rust-core/10-architecture.md §3.3(b)`）。
//!
//! `LiveRoomDetail.danmaku_data` 承载本结构的 JSON 串（键名 snake_case、顺序稳定）。
//! 契约要点：`schema_version` 固定 `1`；缺字段/非法 JSON/版本不符 -> [`SliveError::Decode`]。

use serde::{Deserialize, Serialize};

use crate::error::SliveError;

/// 契约版本（消费方校验 `== 1`，否则拒绝）。
pub const BILI_DANMAKU_ARGS_SCHEMA_VERSION: i32 = 1;
/// `server_host` 为空时的兜底主机。
pub const DEFAULT_SERVER_HOST: &str = "broadcastlv.chat.bilibili.com";

/// 弹幕连接参数（`get_room_detail` 产出，`connect` 消费）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BiliBiliDanmakuArgs {
    /// 契约版本（固定 1）。
    pub schema_version: i32,
    /// 真实房间号。
    pub room_id: i64,
    /// 站点 user_id（未登录为 0）。
    pub uid: i64,
    /// `getDanmuInfo.data.token`。
    pub token: String,
    /// `host_list[0].host`，空则兜底 [`DEFAULT_SERVER_HOST`]。
    pub server_host: String,
    /// buvid3。
    pub buvid: String,
    /// cookie（允许空串）。
    pub cookie: String,
}

impl BiliBiliDanmakuArgs {
    /// 构造（`schema_version` 固定为 1）。
    pub fn new(
        room_id: i64,
        uid: i64,
        token: String,
        server_host: String,
        buvid: String,
        cookie: String,
    ) -> Self {
        let server_host = if server_host.is_empty() {
            DEFAULT_SERVER_HOST.to_string()
        } else {
            server_host
        };
        Self {
            schema_version: BILI_DANMAKU_ARGS_SCHEMA_VERSION,
            room_id,
            uid,
            token,
            server_host,
            buvid,
            cookie,
        }
    }

    /// 序列化为 JSON 串（键序稳定）。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self).map_err(|e| SliveError::decode(format!("序列化弹幕参数失败: {e}")))
    }

    /// 从 JSON 串反序列化并校验版本。
    ///
    /// 缺字段 -> `Decode`；非法 JSON -> `Decode`；`schema_version != 1` -> `Decode`（消息含 `schema_version`）。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        let args: Self = serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("弹幕参数反序列化失败: {e}")))?;
        if args.schema_version != BILI_DANMAKU_ARGS_SCHEMA_VERSION {
            return Err(SliveError::decode(format!(
                "弹幕参数 schema_version 不符：期望 {}，实际 {}",
                BILI_DANMAKU_ARGS_SCHEMA_VERSION, args.schema_version
            )));
        }
        Ok(args)
    }

    /// WS 连接地址（协议信息归核心，桥层只转发 —— AC-39）。
    pub fn ws_url(&self) -> String {
        format!("wss://{}/sub", self.server_host)
    }

    /// 连接请求头（对齐浏览器：UA + Origin 必带；cookie 非空时携带。
    /// 真机发现：登录 cookie + 无 UA/Origin 的裸 WS 握手会被服务端直接 reset —— 风控）。
    pub fn connect_headers(&self) -> Vec<(String, String)> {
        let mut headers = vec![
            (
                "user-agent".to_string(),
                crate::http::DEFAULT_USER_AGENT.to_string(),
            ),
            ("origin".to_string(), "https://live.bilibili.com".to_string()),
        ];
        if !self.cookie.is_empty() {
            headers.push(("cookie".to_string(), self.cookie.clone()));
        }
        headers
    }

    /// 构造 join 包（op=7）的 JSON body（键序须与 golden 一致）。
    pub fn join_payload(&self) -> String {
        #[derive(Serialize)]
        struct JoinBody<'a> {
            uid: i64,
            roomid: i64,
            protover: i32,
            buvid: &'a str,
            platform: &'a str,
            #[serde(rename = "type")]
            msg_type: i32,
            key: &'a str,
        }
        let body = JoinBody {
            uid: self.uid,
            roomid: self.room_id,
            protover: 3,
            buvid: &self.buvid,
            platform: "web",
            msg_type: 2,
            key: &self.token,
        };
        serde_json::to_string(&body).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> BiliBiliDanmakuArgs {
        BiliBiliDanmakuArgs::new(6, 0, "test-token-abc".into(), DEFAULT_SERVER_HOST.into(), "buvid3-FIXED".into(), String::new())
    }

    #[test]
    fn roundtrip_preserves_fields() {
        let args = sample();
        let json = args.to_json().expect("序列化");
        assert_eq!(BiliBiliDanmakuArgs::from_json(&json).expect("反序列化"), args);
    }

    #[test]
    fn missing_field_is_decode_error() {
        let err = BiliBiliDanmakuArgs::from_json(r#"{"schema_version":1,"room_id":6}"#)
            .expect_err("缺字段应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn wrong_schema_version_is_rejected() {
        let json = r#"{"schema_version":2,"room_id":6,"uid":0,"token":"t","server_host":"h","buvid":"b","cookie":""}"#;
        let err = BiliBiliDanmakuArgs::from_json(json).expect_err("版本不符应报错");
        match err {
            SliveError::Decode(msg) => assert!(msg.contains("schema_version"), "实际 {msg}"),
            other => panic!("期望 Decode，实际 {other:?}"),
        }
    }

    #[test]
    fn join_payload_matches_golden_body() {
        assert_eq!(
            sample().join_payload(),
            "{\"uid\":0,\"roomid\":6,\"protover\":3,\"buvid\":\"buvid3-FIXED\",\"platform\":\"web\",\"type\":2,\"key\":\"test-token-abc\"}"
        );
    }
}
