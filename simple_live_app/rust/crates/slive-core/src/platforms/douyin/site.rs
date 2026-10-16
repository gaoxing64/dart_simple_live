//! 抖音站点句柄：状态 + 全方法编排（`site.rs` 仅编排，解析/构串下沉到各能力模块）。
//!
//! 状态（对齐 ADR-005 句柄级，非进程级静态）：
//! - `cookie`：注入的登录 cookie（`set_site_attrs`）；
//! - `ttwid_cookie`：`getRequestHeaders` 换到的 ttwid，会**前置**拼到 `cookie` 前；
//! - `hls_first`：清晰度列表里 hls 是否排在前（`set_site_attrs` 的 `hlsFirst`）；
//! - `last_served_slot`：推荐流续接槽位（Dart `_lastServedSlot`，防相邻页重复命中同 slot）。
//!
//! 注入的 [`HttpTransport`] / [`TimeSource`] 使离线夹具与确定性时间断言可行。

use std::sync::{Arc, Mutex};

use serde_json::Value;

use crate::error::SliveError;
use crate::http::{HttpRequest, HttpTransport, ReqwestTransport};
use crate::models::{
    AccountInfo, LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage, QrCode,
    QrPollResult,
};
use crate::time::{SystemClock, TimeSource};

/// 句柄级可变状态。
#[derive(Default)]
struct SiteState {
    /// 注入的 cookie（`set_site_attrs`）。
    cookie: String,
    /// `live.douyin.com` 下发的 ttwid（`ttwid=...`）。
    ttwid_cookie: String,
    /// hls 是否排在 flv 之前。
    hls_first: bool,
    /// 推荐流上一次真正命中的 slot（`-1` = 本实例刚开始翻）。
    last_served_slot: i32,
}

/// 抖音站点实例。
pub struct DouyinSite {
    http: Arc<dyn HttpTransport>,
    time: Arc<dyn TimeSource>,
    state: Mutex<SiteState>,
}

impl Default for DouyinSite {
    fn default() -> Self {
        Self::new()
    }
}

impl DouyinSite {
    /// 生产构造：真实传输 + 系统时钟。
    pub fn new() -> Self {
        Self::with_deps(Arc::new(ReqwestTransport::new()), Arc::new(SystemClock))
    }

    /// 依赖注入构造（供测试注入 [`crate::testing::MockTransport`] / [`crate::testing::FakeTime`]）。
    pub fn with_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>) -> Self {
        Self {
            http,
            time,
            state: Mutex::new(SiteState {
                last_served_slot: -1,
                ..SiteState::default()
            }),
        }
    }

    /// 站点 ID。
    pub fn id(&self) -> String {
        "douyin".to_string()
    }

    /// 站点名。
    pub fn name(&self) -> String {
        "抖音直播".to_string()
    }

    /// 注入的 HTTP 传输。
    pub fn http(&self) -> Arc<dyn HttpTransport> {
        Arc::clone(&self.http)
    }

    /// 注入的时间源。
    pub fn time(&self) -> Arc<dyn TimeSource> {
        Arc::clone(&self.time)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, SiteState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 请求头用的 cookie：`ttwid` 在前、注入 cookie 在后（对齐 Dart 的字符串拼接顺序）。
    pub fn header_cookie(&self) -> String {
        let s = self.lock();
        match (s.ttwid_cookie.is_empty(), s.cookie.is_empty()) {
            (true, true) => String::new(),
            (true, false) => s.cookie.clone(),
            (false, true) => s.ttwid_cookie.clone(),
            (false, false) => format!("{}; {}", s.ttwid_cookie, s.cookie),
        }
    }

    /// 前置合并一条 `ttwid=...`。
    pub fn merge_ttwid(&self, ttwid_pair: &str) {
        self.lock().ttwid_cookie = ttwid_pair.to_string();
    }

    /// 写入注入的 cookie（空串 = 移除，对齐 Dart `headers.remove('cookie')`）。
    pub fn set_cookie(&self, cookie: &str) {
        self.lock().cookie = cookie.to_string();
    }

    /// hls 是否优先。
    pub fn hls_first(&self) -> bool {
        self.lock().hls_first
    }

    /// 写入 hls 优先标记。
    pub fn set_hls_first(&self, hls_first: bool) {
        self.lock().hls_first = hls_first;
    }

    /// 上一次命中的推荐 slot。
    pub fn last_served_slot(&self) -> i32 {
        self.lock().last_served_slot
    }

    /// 写入上次命中的推荐 slot。
    pub fn set_last_served_slot(&self, slot: i32) {
        self.lock().last_served_slot = slot;
    }

    /// 发起一次 GET 并解析 JSON（响应体非法 JSON -> `Decode`）。
    pub(crate) async fn get_json(
        &self,
        url: &str,
        query: Vec<(String, String)>,
        headers: Vec<(String, String)>,
    ) -> Result<Value, SliveError> {
        let request = HttpRequest {
            url: url.to_string(),
            query,
            headers,
        };
        let reply = self.http().get(&request).await?;
        reply.json()
    }

    /// 发起一次 GET 并取回文本（页面 HTML / RENDER_DATA 解析用）。
    pub(crate) async fn get_text(
        &self,
        url: &str,
        query: Vec<(String, String)>,
        headers: Vec<(String, String)>,
    ) -> Result<String, SliveError> {
        let request = HttpRequest {
            url: url.to_string(),
            query,
            headers,
        };
        Ok(self.http().get(&request).await?.text)
    }

    /// 分类 A 列表（F-01）。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, SliveError> {
        super::categories::fetch(self).await
    }

    /// 分类下房间（`count` 固定 15，`page_size` 忽略 —— 服务端只认 15，见模块文档）。
    pub async fn get_category_rooms(
        &self,
        category: LiveSubCategory,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_category_rooms(self, &category, page, page_size).await
    }

    /// 推荐房间：第 1 页真实推荐流，第 2 页起换真分页的分区接口。
    pub async fn get_recommend_rooms(
        &self,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_recommend_rooms(self, page, page_size).await
    }

    /// 搜索房间。
    pub async fn search_rooms(
        &self,
        keyword: String,
        page: i32,
    ) -> Result<LiveSearchRoomResult, SliveError> {
        super::search::search_rooms(self, &keyword, page).await
    }

    /// 搜索主播（抖音不支持，恒报错 —— 对齐 Dart 的抛异常口径）。
    pub async fn search_anchors(
        &self,
        _keyword: String,
        _page: i32,
    ) -> Result<LiveSearchAnchorResult, SliveError> {
        Err(SliveError::Api {
            code: -1,
            message: "抖音暂不支持搜索主播，请直接搜索直播间".to_string(),
        })
    }

    /// 房间详情（三段降级：roomId -> webRid -> 页面 HTML）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
        super::detail::fetch(self, &room_id).await
    }

    /// 清晰度列表（本地计算，输入是 `detail.data` 的 JSON 串，无网络请求）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, SliveError> {
        super::play::fetch_qualities(self, &detail)
    }

    /// 播放地址（本地计算，输入是 `quality.data` 的 JSON 数组串，无网络请求）。
    pub async fn get_play_urls(
        &self,
        _detail: LiveRoomDetail,
        quality: LivePlayQuality,
    ) -> Result<LivePlayUrl, SliveError> {
        super::play::fetch_urls(self, &quality)
    }

    /// 直播状态（复用详情链路的 `status`）。
    pub async fn get_live_status(&self, room_id: String) -> Result<bool, SliveError> {
        super::status::fetch(self, &room_id).await
    }

    /// 房间 SC 列表（抖音无此能力，恒空 —— 对齐 Dart）。
    pub async fn get_super_chat_messages(
        &self,
        _room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
        Ok(Vec::new())
    }

    /// 注入凭证 / 配置（同步）。
    pub fn set_site_attrs(&self, data: &str) -> Result<(), SliveError> {
        super::account::set_site_attrs(self, data)
    }

    /// 登录二维码（抖音不支持扫码登录）。
    pub async fn get_qr_code(&self) -> Result<QrCode, SliveError> {
        Err(SliveError::NotFound(
            "抖音不支持扫码登录，请手动配置 cookie".to_string(),
        ))
    }

    /// 扫码轮询（抖音不支持扫码登录）。
    pub async fn get_qr_poll_result(&self, _qrcode_key: String) -> Result<QrPollResult, SliveError> {
        Err(SliveError::NotFound(
            "抖音不支持扫码登录，请手动配置 cookie".to_string(),
        ))
    }

    /// 账号信息（`webcast/user/me/`；cookie 为空时返回未校验的默认对象）。
    pub async fn get_account_info(&self, credential: String) -> Result<AccountInfo, SliveError> {
        super::account::get_account_info(self, &credential).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_and_name_match_dart_constants() {
        let site = DouyinSite::new();
        assert_eq!(site.id(), "douyin");
        assert_eq!(site.name(), "抖音直播");
    }

    #[test]
    fn header_cookie_prefers_ttwid_then_injected_cookie() {
        let site = DouyinSite::new();
        assert_eq!(site.header_cookie(), "", "无任何 cookie 时为空");

        site.merge_ttwid("ttwid=1%2Cabc");
        assert_eq!(site.header_cookie(), "ttwid=1%2Cabc");

        site.set_site_attrs(r#"{"cookie":"odin_tt=xyz"}"#)
            .expect("注入合法");
        assert_eq!(
            site.header_cookie(),
            "ttwid=1%2Cabc; odin_tt=xyz",
            "ttwid 必须前置（Dart 的拼接顺序）"
        );
    }

    #[test]
    fn empty_cookie_removes_injected_value_but_keeps_ttwid() {
        let site = DouyinSite::new();
        site.set_site_attrs(r#"{"cookie":"a=1"}"#).expect("注入");
        site.set_site_attrs(r#"{"cookie":""}"#).expect("清空");
        assert_eq!(site.header_cookie(), "");
    }

    #[test]
    fn hls_first_is_injectable_and_defaults_false() {
        let site = DouyinSite::new();
        assert!(!site.hls_first(), "Dart 默认 false");
        site.set_site_attrs(r#"{"hlsFirst":true}"#).expect("注入");
        assert!(site.hls_first());
    }

    #[test]
    fn last_served_slot_starts_at_minus_one() {
        let site = DouyinSite::new();
        assert_eq!(site.last_served_slot(), -1, "Dart 初始值 -1");
        site.set_last_served_slot(3);
        assert_eq!(site.last_served_slot(), 3);
    }

    #[tokio::test]
    async fn unsupported_methods_report_dart_equivalent_errors() {
        let site = DouyinSite::new();
        assert!(matches!(
            site.search_anchors("k".into(), 1).await,
            Err(SliveError::Api { code: -1, .. })
        ));
        assert!(matches!(
            site.get_qr_code().await,
            Err(SliveError::NotFound(_))
        ));
        assert!(matches!(
            site.get_qr_poll_result("k".into()).await,
            Err(SliveError::NotFound(_))
        ));
        assert_eq!(site.get_super_chat_messages("1".into()).await.expect("恒空"), Vec::new());
    }
}
