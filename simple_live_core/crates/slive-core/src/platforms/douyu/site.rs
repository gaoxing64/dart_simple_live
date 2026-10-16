//! 斗鱼站点句柄：状态 + 15 方法编排（`site.rs` 仅编排，解析/构串下沉到各能力模块）。
//!
//! 状态（对齐 ADR-005）：cookie / `dy_did` / `LTP0` / 加密密钥缓存均为**句柄级**
//! （Dart core 的 `DouyuUtils._did/_encKey` 是进程级静态，迁到句柄级不改变请求参数集合）。
//!
//! 注入点：[`HttpTransport`]（GET）+ [`DouyuPost`]（表单 POST）+ [`TimeSource`]，
//! 使离线夹具与确定性时间断言可行（对齐 B站 `BilibiliSite::with_deps`）。

use std::sync::{Arc, Mutex};

use serde_json::Value;

use crate::error::SliveError;
use crate::http::{HttpReply, HttpRequest, HttpTransport, ReqwestTransport};
use crate::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::time::{SystemClock, TimeSource};

use super::transport::{DouyuPost, PostRequest, ReqwestDouyuPost};

/// 斗鱼默认 `dy_did`（未登录游客态，对齐 `douyu_utils.dart:10`）。
pub const DEFAULT_DY_DID: &str = "10000000000000000000000000001501";

/// 句柄级可变状态。
#[derive(Debug)]
struct SiteState {
    cookie: String,
    dy_did: String,
    ltp0: String,
    enc_key: Option<super::sign::EncKey>,
}

impl Default for SiteState {
    fn default() -> Self {
        Self {
            cookie: String::new(),
            dy_did: DEFAULT_DY_DID.to_string(),
            ltp0: String::new(),
            enc_key: None,
        }
    }
}

/// 斗鱼站点实例。
pub struct DouyuSite {
    http: Arc<dyn HttpTransport>,
    post: Arc<dyn DouyuPost>,
    time: Arc<dyn TimeSource>,
    state: Mutex<SiteState>,
}

impl Default for DouyuSite {
    fn default() -> Self {
        Self::new()
    }
}

impl DouyuSite {
    /// 生产构造：真实传输 + 系统时钟。
    pub fn new() -> Self {
        Self::with_deps(
            Arc::new(ReqwestTransport::new()),
            Arc::new(ReqwestDouyuPost::new()),
            Arc::new(SystemClock),
        )
    }

    /// 依赖注入构造（供测试注入 mock 传输 / `FakeTime`）。
    pub fn with_deps(
        http: Arc<dyn HttpTransport>,
        post: Arc<dyn DouyuPost>,
        time: Arc<dyn TimeSource>,
    ) -> Self {
        Self {
            http,
            post,
            time,
            state: Mutex::new(SiteState::default()),
        }
    }

    /// 站点 ID。
    pub fn id(&self) -> String {
        "douyu".to_string()
    }

    /// 站点名。
    pub fn name(&self) -> String {
        "斗鱼直播".to_string()
    }

    /// 当前 Unix 秒（来自注入的时间源）。
    pub fn now_secs(&self) -> u64 {
        self.time.unix_secs()
    }

    /// 当前 Unix 毫秒（`TimeSource` 只提供秒精度，这里按秒放大；仅用于 `tt`/`_`/`expireAt`
    /// 这类「服务端只看量级」的参数，与 Dart `millisecondsSinceEpoch` 的用途一致）。
    pub fn now_millis(&self) -> u64 {
        self.time.unix_secs().saturating_mul(1000)
    }

    /// 注入的 HTTP GET 传输。
    pub fn http(&self) -> Arc<dyn HttpTransport> {
        Arc::clone(&self.http)
    }

    /// 注入的表单 POST 传输。
    pub fn post(&self) -> Arc<dyn DouyuPost> {
        Arc::clone(&self.post)
    }

    /// 注入的时间源。
    pub fn time(&self) -> Arc<dyn TimeSource> {
        Arc::clone(&self.time)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, SiteState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 当前 cookie（克隆）。
    pub fn cookie(&self) -> String {
        self.lock().cookie.clone()
    }

    /// 写入 cookie（`set_site_attrs` / 刷新成功后回填）。
    pub fn set_cookie(&self, cookie: &str) {
        self.lock().cookie = cookie.to_string();
    }

    /// 当前 `dy_did`（未登录为 [`DEFAULT_DY_DID`]）。
    pub fn dy_did(&self) -> String {
        self.lock().dy_did.clone()
    }

    /// 写入 `dy_did`。
    pub fn set_dy_did(&self, did: &str) {
        if !did.is_empty() {
            self.lock().dy_did = did.to_string();
        }
    }

    /// 当前 `LTP0`（扫码登录后的续期凭据）。
    pub fn ltp0(&self) -> String {
        self.lock().ltp0.clone()
    }

    /// 写入 `LTP0`。
    pub fn set_ltp0(&self, ltp0: &str) {
        self.lock().ltp0 = ltp0.to_string();
    }

    /// 读取缓存的加密密钥。
    pub fn enc_key_cached(&self) -> Option<super::sign::EncKey> {
        self.lock().enc_key.clone()
    }

    /// 写入加密密钥缓存。
    pub fn set_enc_key(&self, key: super::sign::EncKey) {
        self.lock().enc_key = Some(key);
    }

    /// 带自定义头发起 GET 并解析 JSON。
    pub(crate) async fn get_json_with(
        &self,
        url: impl Into<String>,
        query: Vec<(String, String)>,
        headers: Vec<(String, String)>,
    ) -> Result<Value, SliveError> {
        self.get_reply(url, query, headers).await?.json()
    }

    /// 带自定义头发起 GET，返回原始响应（`set-cookie` 头需要单独读取）。
    pub(crate) async fn get_reply(
        &self,
        url: impl Into<String>,
        query: Vec<(String, String)>,
        headers: Vec<(String, String)>,
    ) -> Result<HttpReply, SliveError> {
        let request = HttpRequest {
            url: url.into(),
            query,
            headers,
        };
        self.http().get(&request).await
    }

    /// 发起表单 POST 并解析 JSON。
    pub(crate) async fn post_form_json(
        &self,
        url: impl Into<String>,
        body: &str,
        headers: Vec<(String, String)>,
    ) -> Result<Value, SliveError> {
        let reply = self.post_form_reply(url, body, headers).await?;
        reply.json()
    }

    /// 发起表单 POST，返回原始响应。
    pub(crate) async fn post_form_reply(
        &self,
        url: impl Into<String>,
        body: &str,
        headers: Vec<(String, String)>,
    ) -> Result<HttpReply, SliveError> {
        self.post()
            .post_form(&PostRequest {
                url: url.into(),
                body: body.to_string(),
                headers,
            })
            .await
    }

    /// F-01 分类列表。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, SliveError> {
        super::categories::fetch(self).await
    }

    /// F-02 分类下房间（斗鱼单页条数写死在 URL 里，`page_size` 仅为统一签名占位）。
    pub async fn get_category_rooms(
        &self,
        category: LiveSubCategory,
        page: i32,
        page_size: Option<i32>,
    ) -> Result<LiveCategoryResult, SliveError> {
        super::rooms::fetch_category_rooms(self, &category, page, page_size).await
    }

    /// F-03 推荐房间（`page_size` 同样为占位）。
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

    /// F-06 房间详情（单请求：`betard/{roomId}` 一次取全，对齐 Dart）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
        super::detail::fetch(self, &room_id).await
    }

    /// F-07 清晰度列表（`getH5PlayV1` + `sign`）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, SliveError> {
        super::play::fetch_qualities(self, &detail).await
    }

    /// F-08 播放地址（逐线路取流 + 海外 expire 兜底）。
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

    /// F-10 房间 SC 列表（斗鱼 HTTP 侧不提供，恒空 —— 对齐 Dart「尚不支持」）。
    pub async fn get_super_chat_messages(
        &self,
        _room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
        super::super_chat::fetch().await
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

    /// F-20 账号信息。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::models::AccountInfo, SliveError> {
        super::account::get_account_info(self, &credential).await
    }

    /// 刷新 cookie（公开方法，对齐 Dart `DouyuSite.refreshCookie`）。
    ///
    /// 入参缺省时用句柄内已有的 `dy_did`/`LTP0`（FRB 未暴露这两个字段，故走默认值）。
    pub async fn refresh_cookie(&self, dy_did: &str, ltp0: &str) -> Result<String, SliveError> {
        let did = if dy_did.is_empty() {
            self.dy_did()
        } else {
            dy_did.to_string()
        };
        let token = if ltp0.is_empty() {
            self.ltp0()
        } else {
            ltp0.to_string()
        };
        let current = self.cookie();
        let new_cookie = super::cookie::refresh_cookie(self, &did, &token, &current).await?;
        self.set_cookie(&new_cookie);
        self.set_ltp0(&token);
        Ok(new_cookie)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeTime, MockTransport};

    fn site() -> DouyuSite {
        DouyuSite::with_deps(
            Arc::new(MockTransport::new()),
            Arc::new(crate::platforms::douyu::transport::MockDouyuPost::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        )
    }

    #[test]
    fn id_and_name_match_dart_site() {
        let s = site();
        assert_eq!(s.id(), "douyu");
        assert_eq!(s.name(), "斗鱼直播");
    }

    #[test]
    fn default_dy_did_and_state_writes() {
        let s = site();
        assert_eq!(s.dy_did(), DEFAULT_DY_DID, "游客态用默认 did");
        s.set_dy_did("DID-X");
        s.set_cookie("acf_uid=u1");
        s.set_ltp0("LTP1");
        assert_eq!(s.dy_did(), "DID-X");
        assert_eq!(s.cookie(), "acf_uid=u1");
        assert_eq!(s.ltp0(), "LTP1");
        s.set_dy_did("");
        assert_eq!(s.dy_did(), "DID-X", "空 did 不覆盖已有值");
    }

    #[tokio::test]
    async fn super_chat_is_empty_list() {
        assert!(site()
            .get_super_chat_messages("999".to_string())
            .await
            .expect("斗鱼 SC 恒空")
            .is_empty());
    }
}