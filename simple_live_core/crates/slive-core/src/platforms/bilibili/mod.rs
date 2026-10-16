//! B站平台实现（对照 `docs/rust-core/12-bilibili-mapping.md`）。

pub mod account;
pub mod buvid;
pub mod categories;
pub mod cookie;
pub mod danmaku;
pub mod detail;
pub mod emoticon;
pub mod header;
pub mod play;
pub mod rooms;
pub mod search;
pub mod site;
pub mod status;
pub mod super_chat;
pub mod util;
pub mod wbi;

pub use site::BilibiliSite;
