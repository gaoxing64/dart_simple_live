//! Simple Live 纯核心 crate。
//!
//! 分层（只向下依赖，见 `docs/rust-core/10-architecture.md §1.3`）：
//! `platforms` -> `models`/`http`/`error`；`models` 不依赖 `platforms`。
//! 本 crate **不得**依赖 flutter_rust_bridge（复用边界，ADR-001）。
//!
//! 可测试性 seam（注入点，见 §8.4(c) / 交付硬约束）：
//! - [`http::HttpTransport`]：HTTP 传输抽象（生产 [`http::ReqwestTransport`] / 测试 [`testing::MockTransport`]，
//!   后者按 URL 返回夹具并记录请求次数与参数 —— AC-25「请求次数 == 1」的断言基础）
//! - [`time::TimeSource`]：时间源抽象（生产 [`time::SystemClock`] / 测试 [`testing::FakeTime`]），
//!   wbi 的 `wts` 与 ws 心跳均从注入的时间源取
//! - [`ws::FrameSource`]：WS 帧事件源抽象（测试 [`testing::ScriptedFrameSource`]），供 IP-2 弹幕链路注入

pub mod error;
pub mod http;
pub mod logging;
pub mod models;
pub mod platforms;
pub mod tars;
pub mod testing;
pub mod time;
pub mod util;
pub mod wbi;
pub mod ws;
