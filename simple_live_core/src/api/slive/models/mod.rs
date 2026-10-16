//! FRB 可见模型镜像：以 `#[frb(mirror)]` 暴露 `slive-core::models` 的类型（ADR-007 主路径，已 spike 验证）。
//!
//! 规则（FRB 2 external-types 文档）：
//! 1. 被镜像的外部类型必须**公开再导出**；
//! 2. 以 `_` 前缀占位类型声明**完全一致**的字段/变体；
//! 3. 镜像定义与原类型不一致 -> **编译报错**（这正是防字段漂移的护栏）。

pub mod account;
pub mod category;
pub mod danmu;
pub mod message;
pub mod play;
pub mod result;
pub mod room;

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
