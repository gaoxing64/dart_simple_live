//! Twitch 平台模块（IP-5）。
//!
//! 行为基准唯一：`simple_live_core/lib/src/platforms/twitch/{twitch_site,twitch_models,twitch_danmaku}.dart`。
//! - HTTP 读链路：GQL（`gql.twitch.tv/gql`，**POST JSON**）+ usher m3u8（GET）；
//! - 弹幕：**IRC over WebSocket**（`wss://irc-ws.chat.twitch.tv`，匿名登录）。
//!
//! 结构沿用 B站/斗鱼/虎牙范式：`site.rs` 仅编排，解析/构串下沉到各能力模块，依赖只向下。
//! Twitch 的 GQL 是 POST JSON，共享 `HttpTransport` 只暴露 `get`，故在 [`transport`] 内
//! 自建一条平台内 POST 通道（与斗鱼 `transport.rs` 同构，不改共享 `http.rs`）。

pub mod danmaku;
pub mod detail;
pub mod gql;
pub mod header;
pub mod models;
pub mod m3u8;
pub mod play;
pub mod site;
pub mod transport;
pub mod unsupported;

pub use site::TwitchSite;
