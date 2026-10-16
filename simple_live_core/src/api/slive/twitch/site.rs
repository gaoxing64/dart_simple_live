//! Twitch FRB 可见门面：不透明句柄 `LiveTwitchSite`（ADR-005）。
//!
//! 桥层**只做类型翻译 + 转发**，零协议逻辑（URL / persisted-query 哈希 / 签名 / 解析 /
//! 重试均在 `slive-core`）。异常由 `slive-core` 的 `SliveError` -> `CoreError` 映射后抛出。
//!
//! 方法集与 Dart `TwitchSite` 的公开方法**一一对应**（含恒空与恒报错方法，见
//! `slive-core/src/platforms/twitch/unsupported.rs`）；命名风格对齐 B站桥
//! （`get_super_chat_messages` 复数，绑定层映射回 Dart 单数名 `getSuperChatMessage`，J-4/J-8）。

use flutter_rust_bridge::frb;
use slive_core::platforms::twitch::TwitchSite;

use crate::api::slive::error::CoreError;
use crate::api::slive::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};

/// Twitch 站点句柄（FRB opaque）。状态在 Rust 侧，Dart 只持句柄。
#[frb(opaque)]
pub struct LiveTwitchSite {
    inner: TwitchSite,
}

impl Default for LiveTwitchSite {
    fn default() -> Self {
        Self::new()
    }
}

impl LiveTwitchSite {
    /// 构造站点句柄（App 每平台单例持有）。
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: TwitchSite::new(),
        }
    }

    /// 站点 ID（`"twitch"`）。
    #[frb(sync)]
    pub fn id(&self) -> String {
        self.inner.id()
    }

    /// 站点名（`"Twitch"`）。
    #[frb(sync)]
    pub fn name(&self) -> String {
        self.inner.name()
    }

    /// F-17 注入凭证（Twitch 匿名链路不支持）。
    #[frb(sync)]
    pub fn set_site_attrs(&self, data: String) -> Result<(), CoreError> {
        self.inner.set_site_attrs(&data).map_err(CoreError::from)
    }

    /// F-01 分类（Twitch 恒空）。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, CoreError> {
        self.inner.get_categories().await.map_err(CoreError::from)
    }

    /// F-02 分类下房间（Twitch 恒空）。
    pub async fn get_category_rooms(
        &self,
        category: LiveSubCategory,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, CoreError> {
        self.inner
            .get_category_rooms(category, page, page_size)
            .await
            .map_err(CoreError::from)
    }

    /// F-03 推荐房间（Twitch 不支持）。
    pub async fn get_recommend_rooms(
        &self,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, CoreError> {
        self.inner
            .get_recommend_rooms(page, page_size)
            .await
            .map_err(CoreError::from)
    }

    /// F-04 搜索房间（Twitch 不支持）。
    pub async fn search_rooms(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchRoomResult, CoreError> {
        self.inner
            .search_rooms(keyword, page)
            .await
            .map_err(CoreError::from)
    }

    /// F-05 搜索主播（Twitch 不支持）。
    pub async fn search_anchors(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchAnchorResult, CoreError> {
        self.inner
            .search_anchors(keyword, page)
            .await
            .map_err(CoreError::from)
    }

    /// F-06 房间详情（`ChannelShell` + `StreamMetadata` 一次批量）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, CoreError> {
        self.inner
            .get_room_detail(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// F-07 清晰度列表（GQL token + usher m3u8 解析）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, CoreError> {
        self.inner
            .get_play_qualities(detail)
            .await
            .map_err(CoreError::from)
    }

    /// F-08 播放地址。
    pub async fn get_play_urls(
        &self,
        detail: LiveRoomDetail,
        quality: LivePlayQuality,
    ) -> Result<LivePlayUrl, CoreError> {
        self.inner
            .get_play_urls(detail, quality)
            .await
            .map_err(CoreError::from)
    }

    /// F-09 直播状态。
    pub async fn get_live_status(&self, room_id: String) -> Result<bool, CoreError> {
        self.inner
            .get_live_status(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// F-10 SC 列表（Twitch 恒空；方法名复数，绑定层映射回 Dart 单数名，J-4/J-8）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, CoreError> {
        self.inner
            .get_super_chat_messages(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// F-18 二维码（Twitch 不支持）。
    pub async fn get_qr_code(&self) -> Result<crate::api::slive::models::QrCode, CoreError> {
        self.inner.get_qr_code().await.map_err(CoreError::from)
    }

    /// F-19 扫码轮询（Twitch 不支持）。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::api::slive::models::QrPollResult, CoreError> {
        self.inner
            .get_qr_poll_result(qrcode_key)
            .await
            .map_err(CoreError::from)
    }

    /// F-20 账号信息（Twitch 不支持）。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::api::slive::models::AccountInfo, CoreError> {
        self.inner
            .get_account_info(credential)
            .await
            .map_err(CoreError::from)
    }
}
