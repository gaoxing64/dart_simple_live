//! Twitch 站点句柄：句柄级状态 + 15 方法编排（`site.rs` 仅编排，能力下沉到各模块）。
//!
//! 状态（对齐 ADR-005）：
//! - `device_id`：Dart 每次请求用 `Random()` 重新生成（`getDeviceId()`）；Rust 落为
//!   **句柄级**（同一会话稳定），值由注入的 [`TimeSource`] 派生 —— 请求头集合与 Dart 一致，
//!   属行为不变（`13-spec.md §10` 已有同类裁决：wbi keys 静态 -> 句柄级）；
//! - 注入的 [`HttpTransport`]（usher m3u8 是 GET）、[`TwitchPost`]（GQL 是 POST JSON）与
//!   [`TimeSource`] 使离线夹具与确定性断言可行。
//!
//! 依赖方向：本模块只向下依赖 `super::{detail,play,unsupported,transport,header}` 与
//! `crate::{error,http,models,time}`。

use std::sync::{Arc, Mutex};

use serde_json::Value;

use crate::error::SliveError;
use crate::http::{HttpRequest, HttpTransport, ReqwestTransport};
use crate::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::time::{SystemClock, TimeSource};

use super::header::{request_header, DEVICE_ID_BASE, DEVICE_ID_SPAN, TWITCH_GQL_URL};
use super::transport::{PostRequest, ReqwestTwitchPost, TwitchPost};

/// 句柄级可变状态。
#[derive(Default)]
struct SiteState {
    device_id: String,
}

/// Twitch 站点实例。
pub struct TwitchSite {
    http: Arc<dyn HttpTransport>,
    gql: Arc<dyn TwitchPost>,
    time: Arc<dyn TimeSource>,
    state: Mutex<SiteState>,
}

impl Default for TwitchSite {
    fn default() -> Self {
        Self::new()
    }
}

impl TwitchSite {
    /// 生产构造：真实传输 + 系统时钟。
    pub fn new() -> Self {
        Self::with_deps(
            Arc::new(ReqwestTransport::new()),
            Arc::new(ReqwestTwitchPost::new()),
            Arc::new(SystemClock),
        )
    }

    /// 依赖注入构造（供测试注入 `MockTransport` / `MockTwitchPost` / `FakeTime`）。
    pub fn with_deps(
        http: Arc<dyn HttpTransport>,
        gql: Arc<dyn TwitchPost>,
        time: Arc<dyn TimeSource>,
    ) -> Self {
        Self {
            http,
            gql,
            time,
            state: Mutex::new(SiteState::default()),
        }
    }

    /// 站点 ID。
    pub fn id(&self) -> String {
        "twitch".to_string()
    }

    /// 站点名。
    pub fn name(&self) -> String {
        "Twitch".to_string()
    }

    /// 注入的 HTTP 传输（GET 通道）。
    pub fn http(&self) -> Arc<dyn HttpTransport> {
        Arc::clone(&self.http)
    }

    /// 注入的 GQL POST 传输。
    pub fn gql(&self) -> Arc<dyn TwitchPost> {
        Arc::clone(&self.gql)
    }

    /// 注入的时间源。
    pub fn time(&self) -> Arc<dyn TimeSource> {
        Arc::clone(&self.time)
    }

    /// 当前 Unix 秒。
    pub fn now_secs(&self) -> u64 {
        self.time.unix_secs()
    }

    /// 句柄级 `device-id`（首次访问时由时间源派生并缓存）。
    pub fn device_id(&self) -> String {
        {
            let state = self.lock();
            if !state.device_id.is_empty() {
                return state.device_id.clone();
            }
        }
        let derived = (DEVICE_ID_BASE + self.time.unix_secs() % DEVICE_ID_SPAN).to_string();
        let mut state = self.lock();
        if state.device_id.is_empty() {
            state.device_id = derived.clone();
        }
        state.device_id.clone()
    }

    /// 覆盖 `device-id`（测试/未来注入用）。
    pub fn set_device_id(&self, device_id: &str) {
        self.lock().device_id = device_id.to_string();
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, SiteState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 携带标准头 POST 一条 GQL 请求并解析 JSON。
    pub(crate) async fn post_gql(&self, body: &Value) -> Result<Value, SliveError> {
        let payload = serde_json::to_string(body)
            .map_err(|e| SliveError::decode(format!("序列化 GQL 请求失败: {e}")))?;
        let reply = self
            .gql()
            .post_json(&PostRequest {
                url: TWITCH_GQL_URL.to_string(),
                body: payload,
                headers: request_header(self),
            })
            .await?;
        reply.json()
    }

    /// 带标准头发起 GET 并返回响应文本（usher m3u8 用）。
    pub(crate) async fn get_text(
        &self,
        url: &str,
        query: Vec<(String, String)>,
    ) -> Result<String, SliveError> {
        let request = HttpRequest {
            url: url.to_string(),
            query,
            headers: request_header(self),
        };
        Ok(self.http().get(&request).await?.text)
    }

    /// F-01 分类（Twitch 不做分类，恒空）。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, SliveError> {
        super::unsupported::categories()
    }

    /// F-02 分类下房间（恒空；`page_size` 仅为统一签名）。
    pub async fn get_category_rooms(
        &self,
        _category: LiveSubCategory,
        _page: i32,
        _page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::unsupported::category_rooms()
    }

    /// F-03 推荐房间（Dart 未实现 -> 报错）。
    pub async fn get_recommend_rooms(
        &self,
        _page: i32,
        _page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::unsupported::recommend_rooms()
    }

    /// F-04 搜索房间（Dart 抛异常 -> `Api(-1)`）。
    pub async fn search_rooms(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchRoomResult, SliveError> {
        super::unsupported::search_rooms(&keyword, page)
    }

    /// F-05 搜索主播（Dart 抛异常 -> `Api(-1)`）。
    pub async fn search_anchors(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchAnchorResult, SliveError> {
        super::unsupported::search_anchors(&keyword, page)
    }

    /// F-06 房间详情（`ChannelShell` + `StreamMetadata` 一次批量）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
        super::detail::fetch(self, &room_id).await
    }

    /// F-07 清晰度列表（GQL token + usher m3u8 解析）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, SliveError> {
        super::play::fetch_qualities(self, &detail).await
    }

    /// F-08 播放地址（`quality.data` 已是线路 URL）。
    pub async fn get_play_urls(
        &self,
        detail: LiveRoomDetail,
        quality: LivePlayQuality,
    ) -> Result<LivePlayUrl, SliveError> {
        super::play::fetch_urls(self, &detail, &quality)
    }

    /// F-09 直播状态（复用详情链路的 `status`，对齐 Dart）。
    pub async fn get_live_status(&self, room_id: String) -> Result<bool, SliveError> {
        Ok(self.get_room_detail(room_id).await?.status)
    }

    /// F-10 SC 列表（恒空）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
        super::unsupported::super_chat(&room_id)
    }

    /// F-17 注入凭证（Twitch 匿名链路不需要 -> 报错）。
    pub fn set_site_attrs(&self, data: &str) -> Result<(), SliveError> {
        super::unsupported::set_site_attrs(data)
    }

    /// F-18 二维码（Dart 未实现 -> 报错）。
    pub async fn get_qr_code(&self) -> Result<crate::models::QrCode, SliveError> {
        super::unsupported::qr_code()
    }

    /// F-19 扫码轮询（Dart 未实现 -> 报错）。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::models::QrPollResult, SliveError> {
        super::unsupported::qr_poll_result(&qrcode_key)
    }

    /// F-20 账号信息（Dart 未实现 -> 报错）。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::models::AccountInfo, SliveError> {
        super::unsupported::account_info(&credential)
    }
}

#[cfg(test)]
#[path = "site_tests.rs"]
mod tests;
