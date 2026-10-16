//! Twitch 公共请求头（对照 `twitch_site.dart:20-40`）。
//!
//! Dart 侧的 `headers` 是一个**可变 Map**，`getRequestHeaders()` 每次调用追加
//! `device-id`（`1000000000000000 + Random().nextInt(1 << 32)`，即一个 16~17 位的伪设备号）。
//! Rust 侧把 `device-id` 落为**句柄级状态**：首次使用时由注入的 [`TimeSource`] 派生
//! （保证同一会话稳定、且离线可断言），而不是每次请求重新随机。
//!
//! **不手写 accept-encoding**：reqwest 已启用 gzip/brotli 解码器，手写声明可能与服务端
//! 实际编码不匹配（与斗鱼模块同口径，见 `douyu/header.rs`）。
//! **无 cookie / 无 token**：Twitch 匿名只读链路不需要凭证（对齐 Dart 注释「no token / no cookie」）。

use super::site::TwitchSite;

/// 站点默认 UA（对齐 `twitch_site.dart:20-21`）。
pub const TWITCH_USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36";
/// 语言协商（对齐 `twitch_site.dart:28`）。
pub const TWITCH_ACCEPT_LANGUAGE: &str = "en-US,en;q=0.9";
/// 客户端声明（对齐 `twitch_site.dart:29`）。
pub const TWITCH_ACCEPT: &str = "application/vnd.twitchtv.v5+json";
/// GQL 公共 client-id（对齐 `twitch_site.dart:31`；Twitch Web 端公开值）。
pub const TWITCH_CLIENT_ID: &str = "kimne78kx3ncx6brgo4mv6wki5h1ko";
/// 站点主域（房间链接拼接，对齐 `twitch_site.dart:24`）。
pub const TWITCH_BASE_URL: &str = "https://www.twitch.tv";
/// GQL 端点（对齐 `twitch_site.dart:22`）。
pub const TWITCH_GQL_URL: &str = "https://gql.twitch.tv/gql";
/// `device-id` 的基址（Dart `1000000000000000 + random(1<<32)`）。
pub const DEVICE_ID_BASE: u64 = 1_000_000_000_000_000;
/// `device-id` 的随机区间上界（`1 << 32`，对齐 Dart）。
pub const DEVICE_ID_SPAN: u64 = 1 << 32;

/// GQL / m3u8 请求的标准头（含 `device-id`）。
pub(crate) fn request_header(site: &TwitchSite) -> Vec<(String, String)> {
    vec![
        ("user-agent".to_string(), TWITCH_USER_AGENT.to_string()),
        (
            "accept-language".to_string(),
            TWITCH_ACCEPT_LANGUAGE.to_string(),
        ),
        ("accept".to_string(), TWITCH_ACCEPT.to_string()),
        ("client-id".to_string(), TWITCH_CLIENT_ID.to_string()),
        ("device-id".to_string(), site.device_id()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_contains_client_id_and_device_id() {
        let site = TwitchSite::new();
        let header = request_header(&site);
        let get = |key: &str| {
            header
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .expect("应含该头")
        };
        assert_eq!(get("client-id"), TWITCH_CLIENT_ID);
        assert_eq!(get("accept"), TWITCH_ACCEPT);
        assert_eq!(get("accept-language"), TWITCH_ACCEPT_LANGUAGE);
        assert_eq!(get("user-agent"), TWITCH_USER_AGENT);
        let device_id: u64 = get("device-id").parse().expect("device-id 应为数字");
        assert!(
            (DEVICE_ID_BASE..DEVICE_ID_BASE + DEVICE_ID_SPAN).contains(&device_id),
            "device-id 应落在 [1e15, 1e15+2^32)，实际 {device_id}"
        );
        assert!(
            !header.iter().any(|(k, _)| k == "accept-encoding"),
            "不手写 accept-encoding（交给 reqwest）"
        );
    }
}
