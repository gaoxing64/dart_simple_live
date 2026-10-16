//! 斗鱼(douyu)平台模块（IP-3）。
//!
//! 行为基准唯一：`simple_live_core/lib/src/platforms/douyu/{douyu_site,douyu_danmaku,douyu_utils}.dart`。
//! 弹幕为 **STT 文本协议 + 12 字节小端包头**（非 TARS —— TARS 是虎牙协议）。
//! 模块划分沿用 B站范式（`site.rs` 仅编排 + 按能力拆文件），依赖只向下。

pub mod account;
pub mod api_code;
pub mod categories;
pub mod cookie;
pub mod danmaku;
pub mod detail;
pub mod header;
pub mod play;
pub mod rooms;
pub mod search;
pub mod sign;
pub mod site;
pub mod status;
pub mod super_chat;
pub mod transport;
pub mod util;

pub use site::DouyuSite;