//! IP-3 斗鱼 FRB 门面：`LiveDouyuSite`（opaque 句柄）+ 弹幕入口 `start_douyu_danmaku`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：桥层**只做类型翻译 + 转发**，零协议逻辑 ——
//! URL / 签名 / STT 编解码 / 重连策略 / 海外 expire 兜底全部在 `slive-core`。
//! 异常由 `SliveError` 映射为 `CoreError` 后抛出（与 B站同一口径）。
//!
//! ⚠️ 命名独立于 B站：入口是 `start_douyu_danmaku`（不是改 `danmaku.rs` 的 `start_danmaku`），
//! 以免多平台并行期间互相覆盖桥层文件。

use flutter_rust_bridge::frb;
use slive_core::platforms::douyu::danmaku::args::DouyuDanmakuArgs;
use slive_core::platforms::douyu::danmaku::session::{douyu_tuning, run_session};
use slive_core::platforms::douyu::DouyuSite;
use slive_core::time::SystemClock;
use slive_core::ws::ConnectFactory;
use std::sync::Arc;

use crate::api::slive::danmaku::connect_ws_frame_source;
use crate::api::slive::error::CoreError;
use crate::api::slive::models::LiveDanmuItem;
use crate::api::slive::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::frb_generated::StreamSink;

/// 斗鱼弹幕会话的停止信号登记（**斗鱼专属**，不改动 B站 `danmaku.rs` 的全局单例）。
///
/// 单房间语义：启动新会话会顶掉旧会话（对齐 Dart core 一个 `LiveDanmaku` 实例的行为）。
pub(crate) struct DouyuStopRegistry;

impl DouyuStopRegistry {
    fn cell() -> &'static std::sync::Mutex<Option<tokio::sync::watch::Sender<bool>>> {
        static CELL: std::sync::OnceLock<std::sync::Mutex<Option<tokio::sync::watch::Sender<bool>>>> =
            std::sync::OnceLock::new();
        CELL.get_or_init(|| std::sync::Mutex::new(None))
    }

    /// 注册新会话并停掉旧会话，返回本会话的接收端。
    pub(crate) fn activate() -> tokio::sync::watch::Receiver<bool> {
        let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        let mut active = Self::cell().lock().expect("douyu stop 锁");
        if let Some(old) = active.take() {
            let _ = old.send(true);
        }
        *active = Some(stop_tx);
        stop_rx
    }

    /// 停止当前会话（手动停止 / 换房间）。
    pub(crate) fn stop_active() {
        if let Some(stop_tx) = Self::cell().lock().expect("douyu stop 锁").take() {
            let _ = stop_tx.send(true);
        }
    }
}

/// 斗鱼站点句柄（FRB opaque）。状态在 Rust 侧，Dart 只持句柄。
#[frb(opaque)]
pub struct LiveDouyuSite {
    inner: DouyuSite,
}

impl Default for LiveDouyuSite {
    fn default() -> Self {
        Self::new()
    }
}

impl LiveDouyuSite {
    /// 构造站点句柄（App 每平台单例持有）。
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: DouyuSite::new(),
        }
    }

    /// 站点 ID（`"douyu"`）。
    #[frb(sync)]
    pub fn id(&self) -> String {
        self.inner.id()
    }

    /// 站点名（`"斗鱼直播"`）。
    #[frb(sync)]
    pub fn name(&self) -> String {
        self.inner.name()
    }

    /// F-17 注入凭证（同步；绑定层用 pending 模式对齐 Dart 的 `setSiteAttrs`）。
    #[frb(sync)]
    pub fn set_site_attrs(&self, data: String) -> Result<(), CoreError> {
        self.inner.set_site_attrs(&data).map_err(CoreError::from)
    }

    /// F-01 分类列表。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, CoreError> {
        self.inner.get_categories().await.map_err(CoreError::from)
    }

    /// F-02 分类下房间。
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

    /// F-03 推荐房间。
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

    /// F-04 搜索房间。
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

    /// F-05 搜索主播。
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

    /// F-06 房间详情。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, CoreError> {
        self.inner
            .get_room_detail(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// F-07 清晰度列表。
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

    /// F-10 房间 SC 列表（斗鱼 HTTP 侧不提供，恒空；绑定层映射回 Dart 单数名）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, CoreError> {
        self.inner
            .get_super_chat_messages(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// F-18 生成登录二维码。
    pub async fn get_qr_code(&self) -> Result<crate::api::slive::models::QrCode, CoreError> {
        self.inner.get_qr_code().await.map_err(CoreError::from)
    }

    /// F-19 扫码轮询。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::api::slive::models::QrPollResult, CoreError> {
        self.inner
            .get_qr_poll_result(qrcode_key)
            .await
            .map_err(CoreError::from)
    }

    /// F-20 账号信息。
    pub async fn get_account_info(
        &self,
        credential: String,
    ) -> Result<crate::api::slive::models::AccountInfo, CoreError> {
        self.inner
            .get_account_info(credential)
            .await
            .map_err(CoreError::from)
    }

    /// 刷新 cookie（`LTP0`/`dy_did` 留空则用句柄内已有值）。
    pub async fn refresh_cookie(
        &self,
        dy_did: String,
        ltp0: String,
    ) -> Result<String, CoreError> {
        self.inner
            .refresh_cookie(&dy_did, &ltp0)
            .await
            .map_err(CoreError::from)
    }
}

/// 启动斗鱼弹幕会话（F-11~F-16）。
///
/// `room_id` 即 `LiveRoomDetail.danmakuData`（斗鱼弹幕参数**就是房间号**，不是 JSON）——
/// 空房间号 -> `CoreError(InvalidInput)`，对应 Dart 侧解析失败抛异常的口径（J-10）。
/// 同时启动新会话会**停止**旧会话（单房间语义，与 Dart core 一致）。
pub fn start_douyu_danmaku(
    room_id: String,
    sink: StreamSink<LiveDanmuItem>,
) -> Result<(), CoreError> {
    let args = DouyuDanmakuArgs::new(&room_id).map_err(CoreError::from)?;
    let stop_rx = DouyuStopRegistry::activate();

    let ws_url = args.ws_url();
    let ws_headers = args.connect_headers();
    let connect: ConnectFactory = Box::new(move || {
        let url = ws_url.clone();
        let headers = ws_headers.clone();
        Box::pin(async move { connect_ws_frame_source(url, headers).await })
    });

    // ⚠️ FRB 的 FFI 调用线程没有 tokio runtime —— 在这里 `tokio::spawn` 会 panic
    // （"there is no reactor running"，B站真机日志抓到）。必须独立线程 + 自建 runtime。
    std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("douyu danmaku runtime");
        runtime.block_on(async move {
            run_session(
                args,
                connect,
                Arc::new(SystemClock),
                douyu_tuning(),
                stop_rx,
                move |item| {
                    let _ = sink.add(item);
                },
            )
            .await;
        });
    });

    Ok(())
}

/// 手动停止斗鱼弹幕会话（对齐 Dart `DouyuDanmaku.stop()`）。
#[frb(sync)]
pub fn stop_douyu_danmaku() {
    DouyuStopRegistry::stop_active();
}