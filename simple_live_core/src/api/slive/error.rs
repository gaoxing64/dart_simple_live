//! FRB 可见错误：镜像 `slive-core::error::CoreError`（桥层零协议逻辑，仅类型翻译）。

pub use slive_core::error::CoreError;

#[flutter_rust_bridge::frb(mirror(CoreError))]
pub struct _CoreError {
    pub message: String,
    pub status_code: i32,
}
