//! Twitch FRB 门面（IP-5）。桥层只做类型翻译 + 转发，零协议逻辑（ADR-008 / R-18 / AC-39）。
//!
//! 与 B站的 `../site.rs` + `../danmaku.rs` 结构一致，但**符号完全独立**
//! （`LiveTwitchSite` / `start_twitch_danmaku` / `stop_twitch_danmaku`），
//! 不修改 B站任何文件。

pub mod danmaku;
pub mod site;
