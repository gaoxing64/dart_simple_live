//! 抖音弹幕链路：参数契约 + protobuf 解码 + 会话主循环。
//!
//! 对照 Dart `douyin_danmaku.dart`（239 行）。协议三件套：
//! - [`args`]：握手参数与 URL/请求头构造（签名由 `signature` 子模块注入）；
//! - [`proto`]：手写 `prost::Message` 结构（对照 `douyin.proto`，免 protoc/build.rs）；
//! - [`decode`]：`PushFrame` → gzip → `Response` → `LiveMessage`；
//! - [`session`]：心跳 10s / ack 回帧 / 重连 5s×5 的会话循环。

pub mod args;
pub mod decode;
pub mod emoticon;
pub mod proto;
pub mod session;

pub use args::{DouyinDanmakuArgs, DOUYIN_DANMAKU_ARGS_SCHEMA_VERSION};
pub use session::{run_session, ConnectFactory};
