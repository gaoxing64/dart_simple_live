//! 平台实现层。B站已落地并通过真机验证（见 `docs/rust-core/12-bilibili-mapping.md`）；
//! 斗鱼(IP-3)/虎牙(IP-4)/Twitch(IP-5)/抖音(IP-6) 由各路迁移任务填充。
//!
//! ⚠️ **共享文件归总监维护**：并行迁移期间各路请勿整行重写本文件（曾发生
//! `pub mod twitch;` 被覆盖丢失导致全量编译失败）。需要新增平台模块时，
//! 在回传清单里告知总监，由总监统一接线。

pub mod bilibili;
pub mod douyin;
pub mod douyu;
pub mod huya;
pub mod twitch;
