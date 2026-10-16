//! slive FRB 门面。桥层只做类型翻译 + 转发，零协议逻辑（ADR-008 / R-18 / AC-39）。
//!
//! ⚠️ **共享文件归总监维护**：并行迁移期间各路请勿整行重写本文件。

pub mod danmaku;
pub mod douyin;
pub mod douyu;
pub mod error;
pub mod huya;
pub mod huya_site;
pub mod models;
pub mod site;
pub mod twitch;
