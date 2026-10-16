//! 虎牙平台实现（IP-4；对照 Dart `simple_live_core/lib/src/platforms/huya/`）。
//!
//! 模块划分（按能力分包，依赖只向下）：
//! - [`site`]：站点句柄 + 15 方法编排（唯一持有状态处）；
//! - [`common`] / [`utils`] / [`anti_code`] / [`vip_room_id`]：常量与纯计算；
//! - [`categories`] / [`rooms`] / [`search`] / [`status`] / [`detail`]：HTTP 读链路；
//! - [`play`]：清晰度（本地）与取流（逐线路换 token）；
//! - [`tup`]：TUP over HTTP（二进制 POST seam + 两个 servant 调用）；
//! - [`danmaku`]：弹幕参数契约 + WS 帧 + TARS 消息 + 会话主循环。
//!
//! 与其它平台的关系：TARS 基础层由共享模块 [`crate::tars`] 提供，本平台
//! **只定义虎牙自己的消息结构**，不重复实现编解码。
//!
//! 行为基准一律以 Dart core 为准（不丢能力）；未在 Dart 实现的能力
//! （账号三接口）在 Rust 侧以 `SliveError::InvalidInput` 表达同一语义。

pub mod account;
pub mod anti_code;
pub mod categories;
pub mod common;
pub mod danmaku;
pub mod detail;
pub mod detail_parse;
pub mod models;
pub mod play;
pub mod rooms;
pub mod search;
pub mod site;
pub mod status;
pub mod super_chat;
pub mod tup;
pub mod utils;
pub mod vip_room_id;

pub use models::{HuyaBitRateModel, HuyaLineModel, HuyaLineType, HuyaQualityData, HuyaUrlDataModel};
pub use site::HuyaSite;