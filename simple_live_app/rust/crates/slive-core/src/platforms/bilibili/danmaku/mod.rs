//! 弹幕相关数据契约。
//!
//! 本批次只落地 [`args`]（`BiliBiliDanmakuArgs` 数据契约 + join 载荷构造），
//! 作为 `get_room_detail` 的 `danmaku_data` 通道（AC-06）与 IP-2（F-11~F-16）的解码/会话起点。

pub mod args;
pub mod decode;
pub mod parse;

pub use args::{BiliBiliDanmakuArgs, BILI_DANMAKU_ARGS_SCHEMA_VERSION, DEFAULT_SERVER_HOST};
pub use decode::decode_frame;
pub use parse::parse_message;
