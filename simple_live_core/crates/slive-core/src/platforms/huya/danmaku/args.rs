//! 虎牙弹幕参数数据契约（对应 Dart `HuyaDanmakuArgs`）。
//!
//! `LiveRoomDetail.danmaku_data` 承载本结构的 JSON 串。
//! 契约要点（对齐 B站 `danmaku/args.rs` 的口径）：
//! - `schema_version` 固定 `1`；键名 snake_case、顺序稳定；
//! - 缺字段 / 非法 JSON / 版本不符 -> [`SliveError::Decode`]（J-5：不静默兜底）；
//! - **未开播也必须产出**（`ayyuid/top_sid/sub_sid` 全 0）—— App 的直播控制器
//!   无论是否在播都会调 `liveDanmaku.start(detail.danmakuData)`
//!   （对照 Dart `huya_site.dart:324-334` 的注释与兜底分支）。

use serde::{Deserialize, Serialize};

use crate::error::SliveError;

/// 契约版本（消费方校验 `== 1`，否则拒绝）。
pub const HUYA_DANMAKU_ARGS_SCHEMA_VERSION: i32 = 1;
/// 弹幕默认设备标识（对齐 Dart `HuyaDanmaku.device`）。
pub const DEFAULT_DEVICE: &str = "chrome";
/// 匿名 guid（Dart 侧硬编码在 `HuyaUserId.sGuid`，与登录态无关）。
pub const DEFAULT_GUID: &str = "0a7d4b0826af6c69380199dc9adc6b50";

/// 弹幕连接参数（`get_room_detail` 产出，弹幕会话消费）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuyaDanmakuArgs {
    /// 契约版本（固定 1）。
    pub schema_version: i32,
    /// 主播 uid（未开播为 0）。
    pub ayyuid: i64,
    /// 频道 id（`lChannelId`，取流与弹幕注册的 `topSid`）。
    pub top_sid: i64,
    /// 子频道 id（`lSubChannelId`）。
    pub sub_sid: i64,
}

impl Default for HuyaDanmakuArgs {
    fn default() -> Self {
        Self::new(0, 0, 0)
    }
}

impl HuyaDanmakuArgs {
    /// 构造（`schema_version` 固定为 1）。
    pub fn new(ayyuid: i64, top_sid: i64, sub_sid: i64) -> Self {
        Self {
            schema_version: HUYA_DANMAKU_ARGS_SCHEMA_VERSION,
            ayyuid,
            top_sid,
            sub_sid,
        }
    }

    /// 未开播占位参数（三 id 全 0）。
    pub fn offline() -> Self {
        Self::new(0, 0, 0)
    }

    /// 是否为有效的直播参数（`top_sid != 0`，对齐 Dart `args.topSid != 0` 的判据）。
    pub fn is_live(&self) -> bool {
        self.top_sid != 0
    }

    /// 序列化为 JSON 串（键序稳定）。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self)
            .map_err(|e| SliveError::decode(format!("序列化弹幕参数失败: {e}")))
    }

    /// 从 JSON 串反序列化并校验版本。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        let args: Self = serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("弹幕参数反序列化失败: {e}")))?;
        if args.schema_version != HUYA_DANMAKU_ARGS_SCHEMA_VERSION {
            return Err(SliveError::decode(format!(
                "弹幕参数 schema_version 不符：期望 {}，实际 {}",
                HUYA_DANMAKU_ARGS_SCHEMA_VERSION, args.schema_version
            )));
        }
        Ok(args)
    }

    /// 注册的群组 id（对齐 Dart `buildJoinGroupData`：`live:$pid` 与 `chat:$pid`）。
    pub fn group_ids(&self) -> [String; 2] {
        [
            format!("live:{}", self.top_sid),
            format!("chat:{}", self.top_sid),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_preserves_fields() {
        let args = HuyaDanmakuArgs::new(99, 12345, 67890);
        let json = args.to_json().expect("序列化");
        assert_eq!(
            json,
            r#"{"schema_version":1,"ayyuid":99,"top_sid":12345,"sub_sid":67890}"#
        );
        assert_eq!(HuyaDanmakuArgs::from_json(&json).expect("反序列化"), args);
    }

    #[test]
    fn missing_field_is_decode_error() {
        let err = HuyaDanmakuArgs::from_json(r#"{"schema_version":1,"top_sid":1}"#)
            .expect_err("缺字段应报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn wrong_schema_version_is_rejected() {
        let json = r#"{"schema_version":2,"ayyuid":0,"top_sid":1,"sub_sid":2}"#;
        let err = HuyaDanmakuArgs::from_json(json).expect_err("版本不符应报错");
        match err {
            SliveError::Decode(msg) => assert!(msg.contains("schema_version"), "实际 {msg}"),
            other => panic!("期望 Decode，实际 {other:?}"),
        }
    }

    #[test]
    fn offline_args_roundtrip_and_are_not_live() {
        let args = HuyaDanmakuArgs::offline();
        assert!(!args.is_live());
        let json = args.to_json().expect("序列化");
        assert_eq!(
            HuyaDanmakuArgs::from_json(&json).expect("反序列化"),
            args,
            "未开播也必须能往返（App 无论如何都会 start）"
        );
    }

    #[test]
    fn live_args_are_detected() {
        assert!(HuyaDanmakuArgs::new(1, 2, 3).is_live());
        assert!(!HuyaDanmakuArgs::new(1, 0, 3).is_live(), "判据是 top_sid != 0");
    }

    #[test]
    fn group_ids_use_top_sid() {
        let args = HuyaDanmakuArgs::new(0, 999, 888);
        assert_eq!(args.group_ids(), ["live:999".to_string(), "chat:999".to_string()]);
    }
}