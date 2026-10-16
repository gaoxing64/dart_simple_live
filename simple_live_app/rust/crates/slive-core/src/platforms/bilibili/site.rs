//! B站站点句柄：状态 + 15 方法编排（`site.rs` 仅编排，解析/构串下沉到各能力模块）。
//!
//! 状态（ADR-005）：cookie / user_id / buvid / wbi 缓存均为**句柄级**（非进程级静态）；
//! 注入的 [`HttpTransport`] 与 [`TimeSource`] 使离线夹具与确定性时间断言可行。

use std::sync::{Arc, Mutex};

use serde_json::Value;

use crate::error::SliveError;
use crate::http::{HttpRequest, HttpTransport, ReqwestTransport};
use crate::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::time::{SystemClock, TimeSource};

/// 句柄级可变状态。
#[derive(Default)]
struct SiteState {
    cookie: String,
    user_id: i64,
    buvid3: String,
    buvid4: String,
    access_id: Option<String>,
    wbi_img_key: Option<String>,
    wbi_sub_key: Option<String>,
}

/// B站站点实例。
pub struct BilibiliSite {
    http: Arc<dyn HttpTransport>,
    time: Arc<dyn TimeSource>,
    state: Mutex<SiteState>,
}

impl Default for BilibiliSite {
    fn default() -> Self {
        Self::new()
    }
}

impl BilibiliSite {
    /// 生产构造：真实传输 + 系统时钟。
    pub fn new() -> Self {
        Self::with_deps(Arc::new(ReqwestTransport::new()), Arc::new(SystemClock))
    }

    /// 依赖注入构造（供测试注入 [`crate::testing::MockTransport`] / [`crate::testing::FakeTime`]）。
    pub fn with_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>) -> Self {
        Self {
            http,
            time,
            state: Mutex::new(SiteState::default()),
        }
    }

    /// 站点 ID。
    pub fn id(&self) -> String {
        "bilibili".to_string()
    }

    /// 站点名。
    pub fn name(&self) -> String {
        "哔哩哔哩直播".to_string()
    }

    /// 当前 Unix 秒（来自注入的时间源；wbi `wts` 由此取得）。
    pub fn now_secs(&self) -> u64 {
        self.time.unix_secs()
    }

    /// 注入的 HTTP 传输。
    pub fn http(&self) -> Arc<dyn HttpTransport> {
        Arc::clone(&self.http)
    }

    /// 注入的时间源。
    pub fn time(&self) -> Arc<dyn TimeSource> {
        Arc::clone(&self.time)
    }

    /// 当前 cookie（克隆）。
    pub fn cookie(&self) -> String {
        self.lock().cookie.clone()
    }

    /// 写入 cookie（`set_site_attrs` 使用）。
    pub fn set_cookie(&self, cookie: &str) {
        self.lock().cookie = cookie.to_string();
    }

    /// 站点 user_id（供 IP-2 弹幕 uid 配对）。
    pub fn user_id(&self) -> i64 {
        self.lock().user_id
    }

    /// 回填 user_id（`get_account_info` 副作用，IP-2 使用）。
    pub fn set_user_id(&self, id: i64) {
        self.lock().user_id = id;
    }

    /// buvid 快照。
    pub fn buvid_snapshot(&self) -> (String, String) {
        let s = self.lock();
        (s.buvid3.clone(), s.buvid4.clone())
    }

    /// 写入 buvid。
    pub fn set_buvid(&self, buvid3: &str, buvid4: &str) {
        let mut s = self.lock();
        s.buvid3 = buvid3.to_string();
        s.buvid4 = buvid4.to_string();
    }

    /// 缓存的 access_id（w_webid）。
    pub fn access_id_cached(&self) -> Option<String> {
        self.lock().access_id.clone()
    }

    /// 写入 access_id。
    pub fn set_access_id(&self, access_id: &str) {
        self.lock().access_id = Some(access_id.to_string());
    }

    /// 缓存的 wbi keys。
    pub fn wbi_keys_cached(&self) -> Option<(String, String)> {
        let s = self.lock();
        match (&s.wbi_img_key, &s.wbi_sub_key) {
            (Some(img), Some(sub)) => Some((img.clone(), sub.clone())),
            _ => None,
        }
    }

    /// 写入 wbi keys。
    pub fn set_wbi_keys(&self, img_key: &str, sub_key: &str) {
        let mut s = self.lock();
        s.wbi_img_key = Some(img_key.to_string());
        s.wbi_sub_key = Some(sub_key.to_string());
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, SiteState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 携带标准头（含 buvid）发起 GET 并解析 JSON。
    pub(crate) async fn get_json(
        &self,
        url: &str,
        query: Vec<(String, String)>,
    ) -> Result<Value, SliveError> {
        let headers = super::header::build_header(self).await?;
        let request = HttpRequest {
            url: url.to_string(),
            query,
            headers,
        };
        let reply = self.http().get(&request).await?;
        reply.json()
    }

    /// F-01 分类 A 列表。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, SliveError> {
        super::categories::fetch(self).await
    }

    /// F-02 分类下房间（保留 `page_size` 参数占位）。
    pub async fn get_category_rooms(
        &self,
        category: LiveSubCategory,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_category_rooms(self, &category, page, page_size).await
    }

    /// F-03 推荐房间（保留 `page_size`）。
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

    /// F-06 房间详情（两步：getInfoByRoom + getDanmuInfo）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
        super::detail::fetch(self, &room_id).await
    }

    /// F-07 清晰度列表。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, SliveError> {
        super::play::fetch_qualities(self, &detail).await
    }

    /// F-08 播放地址（mcdn 后置排序）。
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

    /// F-10 房间 SC 列表（方法名复数，对齐上游；见 J-4）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
        super::super_chat::fetch(self, &room_id).await
    }

    /// F-17 注入凭证（同步）。
    pub fn set_site_attrs(&self, data: &str) -> Result<(), SliveError> {
        super::account::set_site_attrs(self, data)
    }

    /// F-18 生成登录二维码。
    pub async fn get_qr_code(&self) -> Result<crate::models::QrCode, SliveError> {
        super::account::get_qr_code(self).await
    }

    /// F-19 扫码轮询。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::models::QrPollResult, SliveError> {
        super::account::get_qr_poll_result(self, &qrcode_key).await
    }

    /// F-20 账号信息（成功时回填 `user_id` 副作用）。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::models::AccountInfo, SliveError> {
        super::account::get_account_info(self, &credential).await
    }
}
