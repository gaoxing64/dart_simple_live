//! Twitch GQL 响应模型（对照 `twitch_models.dart`，字段语义 1:1 保留）。
//!
//! 关键坑（已核对 Dart 与 Twitch GQL 实际响应）：
//! - `profileImageURL` 的 **URL 大写**（不是 `profileImageUrl`）—— 用 `rename_all = camelCase`
//!   会错，故显式 `rename`；
//! - `__typename` 是错误判别的唯一依据（`UserNotFoundError`），必须显式映射；
//! - `Stream.streamType` 来自 `type` 键；
//! - Dart 的 `User.fromJson` 对 `channel` 做了非空断言（缺失即抛）；Rust 侧改为可选，
//!   **不丢能力**（本模块只读 `displayName`/`profileImageURL`/`lastBroadcast`/`stream`）。
//!
//! 所有可选字段缺失即 `None`（等价 Dart 的 `?? ''` / `?? null` 兜底），
//! 必填标量缺失时给零值，避免畸形载荷导致整条链路崩掉（错误由调用方按类型化错误抛出）。

use serde::Deserialize;

/// 单条 GQL 响应外层（批量请求的数组元素）。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TwitchResponse {
    /// `data` 节点（Dart `Data.fromJson(json['data'])`）。
    #[serde(default)]
    pub data: Data,
}

/// `data` 节点：两种 operation 的返回字段并集。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Data {
    /// `ChannelShell` 返回的用户（或错误对象）。
    #[serde(default)]
    pub user_or_error: Option<UserOrError>,
    /// `StreamMetadata` 返回的用户。
    #[serde(default)]
    pub user: Option<User>,
}

/// `userOrError`（`ChannelShell`）。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserOrError {
    /// 用户 ID。
    #[serde(default)]
    pub id: String,
    /// 登录名（房间号本体）。
    #[serde(default)]
    pub login: String,
    /// 展示名（房间详情 `userName` 的来源）。
    #[serde(default)]
    pub display_name: String,
    /// 主题色。
    #[serde(default)]
    pub primary_color_hex: String,
    /// 头像 URL（**注意大写 URL**，对齐 Twitch 实际响应）。
    #[serde(default, rename = "profileImageURL")]
    pub profile_image_url: String,
    /// 直播流（`ChannelShell` 亦会带回）。
    #[serde(default)]
    pub stream: Option<Stream>,
    /// GraphQL 类型名（`User` / `UserNotFoundError`）。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

impl UserOrError {
    /// 是否为「用户不存在」错误对象（`twitch_site.dart:215` 的判别口径）。
    pub fn is_user_not_found(&self) -> bool {
        self.typename == "UserNotFoundError"
    }
}

/// `user`（`StreamMetadata`）。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct User {
    /// 用户 ID。
    #[serde(default)]
    pub id: String,
    /// 主题色。
    #[serde(default)]
    pub primary_color_hex: String,
    /// 是否 partner。
    #[serde(default)]
    pub is_partner: bool,
    /// 头像 / 封面 URL（**大写 URL**）。
    #[serde(default, rename = "profileImageURL")]
    pub profile_image_url: String,
    /// 所属战队。
    #[serde(default)]
    pub primary_team: Option<PrimaryTeam>,
    /// 频道节点（Dart 侧非空断言；Rust 允许缺失）。
    #[serde(default)]
    pub channel: Option<Channel>,
    /// 上一次直播（标题来源）。
    #[serde(default)]
    pub last_broadcast: Option<LastBroadcast>,
    /// 直播流（`streamType == "live"` 即在播）。
    #[serde(default)]
    pub stream: Option<Stream>,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

/// 直播流。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Stream {
    /// 流 ID。
    #[serde(default)]
    pub id: String,
    /// 观众数（房间详情 `online` 的来源）。
    #[serde(default)]
    pub viewers_count: i64,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
    /// 流类型（**来自 `type` 键**：`live` 表示直播中）。
    #[serde(default, rename = "type")]
    pub stream_type: Option<String>,
    /// 创建时间。
    #[serde(default)]
    pub created_at: Option<String>,
    /// 正在玩的游戏。
    #[serde(default)]
    pub game: Option<Game>,
}

impl Stream {
    /// 是否直播中（`twitch_site.dart:226` 的口径：`streamType == 'live'`）。
    pub fn is_live(&self) -> bool {
        self.stream_type.as_deref() == Some("live")
    }
}

/// 游戏。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Game {
    /// 游戏 ID。
    #[serde(default)]
    pub id: String,
    /// 游戏名。
    #[serde(default)]
    pub name: String,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

/// 频道节点。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Channel {
    /// 频道 ID。
    #[serde(default)]
    pub id: String,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
    /// 当前登录者的边（**来自 `self` 键**）。
    #[serde(default, rename = "self")]
    pub self_edge: Option<ChannelSelfEdge>,
    /// 预告片。
    #[serde(default)]
    pub trailer: Option<Trailer>,
}

/// `channel.self` 边。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChannelSelfEdge {
    /// 是否已授权。
    #[serde(default)]
    pub is_authorized: bool,
    /// 限制类型。
    #[serde(default)]
    pub restriction_type: Option<String>,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

/// 预告片（Dart 仅取类型名，本模块同样只保留该字段）。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Trailer {
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

/// 战队。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrimaryTeam {
    /// 战队 ID。
    #[serde(default)]
    pub id: String,
    /// 战队名。
    #[serde(default)]
    pub name: String,
    /// 战队展示名。
    #[serde(default)]
    pub display_name: String,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

/// 上一次直播（标题来源）。
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LastBroadcast {
    /// 场次 ID。
    #[serde(default)]
    pub id: String,
    /// 标题。
    #[serde(default)]
    pub title: String,
    /// GraphQL 类型名。
    #[serde(default, rename = "__typename")]
    pub typename: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_channel_shell_shape() {
        let raw = r##"{"data":{"userOrError":{"id":"1","login":"xqc","displayName":"XQC",
            "primaryColorHex":"#FF0000","profileImageURL":"https://a/p.jpg","stream":null,
            "__typename":"User"}}}"##;
        let parsed: TwitchResponse = serde_json::from_str(raw).expect("解析");
        let user = parsed.data.user_or_error.expect("应有 userOrError");
        assert_eq!(user.display_name, "XQC");
        assert_eq!(user.profile_image_url, "https://a/p.jpg");
        assert!(!user.is_user_not_found());
    }

    #[test]
    fn parses_stream_metadata_shape() {
        let raw = r#"{"data":{"user":{"lastBroadcast":{"id":"b","title":"T"},
            "profileImageURL":"https://a/c.jpg","stream":{"id":"s","viewersCount":1234,
            "type":"live","__typename":"Stream"},"__typename":"User"}}}"#;
        let parsed: TwitchResponse = serde_json::from_str(raw).expect("解析");
        let user = parsed.data.user.expect("应有 user");
        assert_eq!(user.last_broadcast.expect("lastBroadcast").title, "T");
        let stream = user.stream.expect("stream");
        assert!(stream.is_live());
        assert_eq!(stream.viewers_count, 1234);
    }

    #[test]
    fn user_not_found_typename_is_detected() {
        let raw = r#"{"data":{"userOrError":{"__typename":"UserNotFoundError","displayName":"ghost"}}}"#;
        let parsed: TwitchResponse = serde_json::from_str(raw).expect("解析");
        assert!(parsed
            .data
            .user_or_error
            .expect("应有 userOrError")
            .is_user_not_found());
    }

    #[test]
    fn missing_optional_nodes_do_not_fail_parse() {
        let parsed: TwitchResponse =
            serde_json::from_str(r#"{"data":{"user":{}}}"#).expect("解析");
        let user = parsed.data.user.expect("应有 user");
        assert!(user.stream.is_none());
        assert!(user.last_broadcast.is_none());
        assert_eq!(user.profile_image_url, "");
        assert!(parsed.data.user_or_error.is_none());
    }
}
