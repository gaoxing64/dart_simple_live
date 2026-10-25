//! 斗鱼弹幕（IP-3）：STT 文本协议 + 12 字节小端包头。
//!
//! 分层（对齐 B站 `platforms/bilibili/danmaku/`）：
//! - [`args`]：连接参数（斗鱼只需房间号）+ 明文 TCP 地址（ADR-015）；
//! - [`protocol`]：封包/解包/STT 解析（纯函数，golden 断言落点）；
//! - [`parse`]：STT -> [`crate::models::LiveMessage`]；
//! - [`session`]：会话主循环（连接 -> 登录 -> 进组 -> 帧循环 -> 心跳 -> 重连）。
//!
//! ⚠️ 斗鱼**不使用 TARS**（TARS 是虎牙协议）；此处为手写 STT，对齐 Dart
//! `douyu_danmaku.dart` 的 `serializeDouyu` / `deserializeDouyu` / `sttToJObject`。

pub mod args;
pub mod parse;
pub mod protocol;
pub mod session;

pub use args::DouyuDanmakuArgs;
pub use parse::decode_frame;
pub use protocol::{deserialize, serialize, stt_to_value};
pub use session::{douyu_tuning, run_session};