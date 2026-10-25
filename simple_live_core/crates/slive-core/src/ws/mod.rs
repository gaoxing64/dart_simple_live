//! WebSocket / TCP 传输层（帧编解码 + 时间源/事件源注入点，供 IP-2 弹幕链路）。
//!
//! - [`frame`]：B站弹幕帧的 16 字节头编解码（大端），AC-11 join 包 golden 的落点；
//! - [`session`]：[`FrameSource`]（事件源）+ [`TimeSource`]（时间源）可注入的会话骨架；
//! - [`tcp`]：斗鱼弹幕的明文 TCP 帧源（ADR-015）。

pub mod frame;
pub mod runner;
pub mod session;
pub mod tcp;

pub use runner::{join_frame, run_session, ConnectFactory};
pub use session::{FrameSource, SessionTuning, WsSession};
