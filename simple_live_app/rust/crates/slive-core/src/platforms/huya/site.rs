//! 虎牙站点句柄：句柄级状态 + 15 方法编排（`site.rs` 仅编排，能力下沉到各模块）。
//!
//! 状态（对齐 ADR-005 与 Dart 现状）：
//! - `hysdk_ua`：Dart 是**可变的 static**（`HuyaRequestParams.HYSDK_UA`，被 `setSiteAttrs` 改写），
//!   Rust 落为**句柄级**（请求头集合与 Dart 一致，属行为不变；见 `13-spec.md §10`）；
//! - 注入的 [`HttpTransport`] / [`TimeSource`] 使离线夹具与确定性时间断言可行
//!   （`buildAntiCode` 的 `nowMs` 取自注入时间源，便于 golden）。
//!
//! 依赖方向：本模块只向下依赖 `super::{categories,rooms,search,detail,play,status,super_chat,account}`。

use std::sync::{Arc, Mutex};

use crate::error::SliveError;
use crate::http::{HttpRequest, HttpTransport, ReqwestTransport};
use crate::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::time::{SystemClock, TimeSource};

use super::common::DEFAULT_HYSDK_UA;
use super::account::UnavailablePost;
use super::tup::{PostBytesTransport, ReqwestPostTransport};

/// 虎牙站点实例。
pub struct HuyaSite {
    http: Arc<dyn HttpTransport>,
    /// TUP（二进制 POST）传输。虎牙的取流 token 与 SC 列表走 POST + `application/x-wup`，
    /// 与 GET-only 的 [`HttpTransport`] seam 不同，故单独注入（测试可替换）。
    post: Arc<dyn PostBytesTransport>,
    time: Arc<dyn TimeSource>,
    hysdk_ua: Mutex<String>,
}

impl Default for HuyaSite {
    fn default() -> Self {
        Self::new()
    }
}

impl HuyaSite {
    /// 生产构造：真实传输 + 系统时钟。
    pub fn new() -> Self {
        Self::with_deps(
            Arc::new(ReqwestTransport::new()),
            Arc::new(ReqwestPostTransport::new()),
            Arc::new(SystemClock),
        )
    }

    /// 依赖注入构造（供测试注入 `MockTransport` / `FakeTime`）。
    pub fn with_deps(
        http: Arc<dyn HttpTransport>,
        post: Arc<dyn PostBytesTransport>,
        time: Arc<dyn TimeSource>,
    ) -> Self {
        Self {
            http,
            post,
            time,
            hysdk_ua: Mutex::new(DEFAULT_HYSDK_UA.to_string()),
        }
    }

    /// 只注入 GET 传输与时间源（TUP 用不可用的桩，测试 TUP 时改用 [`Self::with_deps`]）。
    pub fn with_get_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>) -> Self {
        Self::with_deps(http, Arc::new(UnavailablePost), time)
    }

    /// 站点 ID。
    pub fn id(&self) -> String {
        "huya".to_string()
    }

    /// 站点名。
    pub fn name(&self) -> String {
        "虎牙直播".to_string()
    }

    /// 注入的 HTTP 传输。
    pub fn http(&self) -> Arc<dyn HttpTransport> {
        Arc::clone(&self.http)
    }

    /// 注入的 TUP（二进制 POST）传输。
    pub fn post(&self) -> Arc<dyn PostBytesTransport> {
        Arc::clone(&self.post)
    }

    /// 注入的时间源。
    pub fn time(&self) -> Arc<dyn TimeSource> {
        Arc::clone(&self.time)
    }

    /// 当前毫秒时间戳（取流签名用）。
    pub fn now_millis(&self) -> u64 {
        self.time.unix_secs() * 1000
    }

    /// 当前 SDK UA（`set_site_attrs` 可改）。
    pub fn hysdk_ua(&self) -> String {
        self.lock().clone()
    }

    /// 写入 SDK UA（`set_site_attrs` 使用）。
    pub fn set_hysdk_ua(&self, ua: &str) {
        *self.lock() = ua.to_string();
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, String> {
        self.hysdk_ua.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 当前请求头（含可变的 SDK UA；Origin/Referer 固定）。
    pub fn request_headers(&self) -> Vec<(String, String)> {
        super::common::request_headers(&self.hysdk_ua())
    }

    /// 带标准头发起 GET 并返回响应文本。
    pub(crate) async fn get_text(
        &self,
        url: &str,
        query: Vec<(String, String)>,
    ) -> Result<String, SliveError> {
        Ok(self.get_reply(url, query).await?.text)
    }

    /// 带标准头发起 GET 并返回原始响应（含 `set-cookie`）。
    pub(crate) async fn get_reply(
        &self,
        url: &str,
        query: Vec<(String, String)>,
    ) -> Result<crate::http::HttpReply, SliveError> {
        let request = HttpRequest {
            url: url.to_string(),
            query,
            headers: self.request_headers(),
        };
        self.http().get(&request).await
    }

    /// 带标准头发起 GET 并解析 JSON。
    pub(crate) async fn get_json(
        &self,
        url: &str,
        query: Vec<(String, String)>,
    ) -> Result<serde_json::Value, SliveError> {
        self.get_reply(url, query).await?.json()
    }

    /// F-01 分类 A 列表（4 个大类 + 各自分类）。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, SliveError> {
        super::categories::fetch(self).await
    }

    /// F-01b 子分类（公开以便单独复用；`get_categories` 内部调用）。
    pub async fn get_sub_categories(
        &self,
        parent_id: &str,
    ) -> Result<Vec<LiveSubCategory>, SliveError> {
        super::categories::fetch_sub(self, parent_id).await
    }

    /// F-02 分类下房间（`page_size` 接口忽略，仅统一签名）。
    pub async fn get_category_rooms(
        &self,
        category: LiveSubCategory,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_category_rooms(self, &category, page, page_size).await
    }

    /// F-03 推荐房间（`page_size` 接口忽略，仅统一签名）。
    pub async fn get_recommend_rooms(
        &self,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_recommend_rooms(self, page, page_size).await
    }

    /// F-04 搜索房间。
    pub async fn search_rooms(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchRoomResult, SliveError> {
        super::search::search_rooms(self, &keyword, page).await
    }

    /// F-05 搜索主播。
    pub async fn search_anchors(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchAnchorResult, SliveError> {
        super::search::search_anchors(self, &keyword, page).await
    }

    /// F-06 房间详情（含弹幕参数与取流数据）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
        super::detail::fetch(self, &room_id).await
    }

    /// F-07 清晰度列表（跳过 4K：需 VIP）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, SliveError> {
        super::play::fetch_qualities(self, &detail)
    }

    /// F-08 播放地址（逐线路取 TARS token + 反 anticode；单线失败跳过）。
    pub async fn get_play_urls(
        &self,
        detail: LiveRoomDetail,
        quality: LivePlayQuality,
    ) -> Result<LivePlayUrl, SliveError> {
        super::play::fetch_urls(self, &detail, &quality).await
    }

    /// F-09 直播状态。
    pub async fn get_live_status(&self, room_id: String) -> Result<bool, SliveError> {
        super::status::fetch(self, &room_id).await
    }

    /// F-10 房间醒目留言列表（方法名复数，对齐上游；见 J-4）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
        super::super_chat::fetch(self, &room_id).await
    }

    /// F-17 注入凭证（虎牙仅识别 `ua` 键）。
    pub fn set_site_attrs(&self, data: &str) -> Result<(), SliveError> {
        super::account::set_site_attrs(self, data)
    }

    /// F-18 生成登录二维码（虎牙 Dart core 未实现 -> 类型化错误）。
    pub async fn get_qr_code(&self) -> Result<crate::models::QrCode, SliveError> {
        super::account::get_qr_code().await
    }

    /// F-19 扫码轮询（同上，Dart 未实现）。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::models::QrPollResult, SliveError> {
        super::account::get_qr_poll_result(qrcode_key).await
    }

    /// F-20 账号信息（同上，Dart 未实现）。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::models::AccountInfo, SliveError> {
        super::account::get_account_info(credential).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_and_name_match_dart() {
        let site = HuyaSite::new();
        assert_eq!(site.id(), "huya");
        assert_eq!(site.name(), "虎牙直播");
    }

    #[test]
    fn hysdk_ua_is_handle_level_and_mutable() {
        let site = HuyaSite::new();
        assert_eq!(site.hysdk_ua(), DEFAULT_HYSDK_UA);
        site.set_hysdk_ua("custom-ua");
        assert_eq!(site.hysdk_ua(), "custom-ua");
        assert_eq!(site.request_headers()[2].1, "custom-ua", "请求头随之更新");
        // 另一个句柄不受影响（句柄级，非进程级）
        assert_eq!(HuyaSite::new().hysdk_ua(), DEFAULT_HYSDK_UA);
    }

    #[tokio::test]
    async fn account_methods_report_unsupported() {
        let site = HuyaSite::new();
        for err in [
            site.get_qr_code().await.err(),
            site.get_qr_poll_result("k".to_string()).await.err(),
            site.get_account_info("c".to_string()).await.err(),
        ] {
            let err = err.expect("虎牙不支持，必须报错");
            assert!(
                matches!(err, SliveError::InvalidInput(_)),
                "未实现应为 InvalidInput，实际 {err:?}"
            );
        }
    }
}