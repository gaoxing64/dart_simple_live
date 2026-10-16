//! 账号模型（对照 Dart `account_info.dart` / `account_qr_code.dart` / `common/qr_status.dart`）。

/// 二维码登录状态（对照 Dart `QRStatus`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QrStatus {
    /// 加载中。
    Loading,
    /// 未扫描。
    Unscanned,
    /// 已扫描。
    Scanned,
    /// 已过期。
    Expired,
    /// 失败。
    Failed,
}

/// 登录二维码（对照 Dart `QRCode`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QrCode {
    /// 二维码 key。
    pub key: String,
    /// 二维码 URL。
    pub url: String,
    /// 创建时间（可空）。
    pub created_at: Option<i64>,
    /// 过期时间（可空）。
    pub expire_at: Option<i64>,
}

/// 扫码轮询结果（对照 Dart `QRPollResult`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QrPollResult {
    /// 状态。
    pub status: QrStatus,
    /// 有效凭证（JSON `{"cookie":...}`；空表示尚未拿到）。
    pub credential: String,
    /// 附加信息。
    pub message: String,
}

/// 账号信息（对照 Dart `AccountInfo`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountInfo {
    /// 昵称。
    pub name: Option<String>,
    /// 头像。
    pub avatar: Option<String>,
    /// 用户 ID（B站 `userid`）。
    pub uid: Option<String>,
    /// 凭证（原样回传）。
    pub credential: String,
    /// 是否有效。
    pub is_valid: bool,
}
