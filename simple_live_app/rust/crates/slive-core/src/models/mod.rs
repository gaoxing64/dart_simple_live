//! 跨平台强类型模型（与 Dart core `simple_live_core/lib/src/model/*` 同构）。
//!
//! 本模块**不含**任何 `#[frb]` 标注；FRB 侧通过桥 crate 的 `#[frb(mirror)]` 暴露（ADR-007）。
//! 字段语义保留 Dart core 契约（`children` / `emoticons` / `color` / `data`），命名风格对齐上游 `Live*`。

mod account;
mod category;
mod danmu;
mod message;
mod play;
mod result;
mod room;

pub use account::{AccountInfo, QrCode, QrPollResult, QrStatus};
pub use category::{LiveCategory, LiveSubCategory};
pub use danmu::{LiveDanmuControlEvent, LiveDanmuItem};
pub use message::{
    LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageEmoticon, LiveMessageType,
    LiveSuperChatMessage,
};
pub use play::{LivePlayQuality, LivePlayUrl};
pub use result::{LiveCategoryResult, LiveSearchAnchorResult, LiveSearchRoomResult};
pub use room::{LiveAnchorItem, LiveRoomDetail, LiveRoomItem};
