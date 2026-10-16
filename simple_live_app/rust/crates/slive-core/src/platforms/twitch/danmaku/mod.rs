//! Twitch 弹幕（IRC over WebSocket）模块。
//!
//! - [`args`]：数据契约（`LiveRoomDetail.danmaku_data` 承载的 JSON 串）+ 握手/心跳帧构造；
//! - [`parse`]：IRC 行 -> [`crate::models::LiveMessage`] + PONG 应答；
//! - [`session`]：会话主循环（与 B站 `ws/runner.rs::run_session` 同构，帧内容为 IRC 文本）。
//!
//! 三个 seam 与 B站完全一致：帧源 [`crate::ws::FrameSource`]、时间源 [`crate::time::TimeSource`]、
//! 事件 [`crate::models::LiveDanmuItem`]；协议细节（URL/握手/编解码/重连）全部在本模块内，
//! 桥层只做连接装配与事件转发（AC-39）。

pub mod args;
pub mod parse;
pub mod session;

pub use args::{TwitchDanmakuArgs, TWITCH_DANMAKU_ARGS_SCHEMA_VERSION};
pub use parse::{parse_frame, IrcParseOutput};
pub use session::run_session;
