//! 账号模型镜像。

pub use slive_core::models::{AccountInfo, QrCode, QrPollResult, QrStatus};

#[flutter_rust_bridge::frb(mirror(QrStatus))]
pub enum _QrStatus {
    Loading,
    Unscanned,
    Scanned,
    Expired,
    Failed,
}

#[flutter_rust_bridge::frb(mirror(QrCode))]
pub struct _QrCode {
    pub key: String,
    pub url: String,
    pub created_at: Option<i64>,
    pub expire_at: Option<i64>,
}

#[flutter_rust_bridge::frb(mirror(QrPollResult))]
pub struct _QrPollResult {
    pub status: QrStatus,
    pub credential: String,
    pub message: String,
}

#[flutter_rust_bridge::frb(mirror(AccountInfo))]
pub struct _AccountInfo {
    pub name: Option<String>,
    pub avatar: Option<String>,
    pub uid: Option<String>,
    pub credential: String,
    pub is_valid: bool,
}
