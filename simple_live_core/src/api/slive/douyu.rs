//! IP-3 斗鱼 FRB 门面：`LiveDouyuSite`（opaque 句柄）+ 弹幕入口 `DouyuDanmakuConnection`。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：桥层**只做类型翻译 + 转发**，零协议逻辑 ——
//! URL / 签名 / STT 编解码 / 重连策略 / 海外 expire 兜底全部在 `slive-core`。
//! 异常由 `SliveError` 映射为 `CoreError` 后抛出（与 B站同一口径）。
//!
//! ⚠️ 命名独立于 B站：弹幕入口是 `DouyuDanmakuConnection::start`（不是改
//! `danmaku.rs` 的 `DanmakuConnection::start`），以免多平台并行期间互相覆盖桥层文件。

use flutter_rust_bridge::frb;
use slive_core::platforms::douyu::danmaku::args::DouyuDanmakuArgs;
use slive_core::platforms::douyu::danmaku::session::{douyu_tuning, run_session};
use slive_core::platforms::douyu::DouyuSite;
use slive_core::time::SystemClock;
use slive_core::ws::ConnectFactory;
use std::sync::Arc;
use tokio::sync::watch;

use crate::api::slive::danmaku::connect_ws_frame_source;
use crate::api::slive::error::CoreError;
use crate::api::slive::models::LiveDanmuItem;
use crate::api::slive::models::{
    LiveCategory, LiveCategoryResult, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::frb_generated::StreamSink;

/// 斗鱼弹幕连接句柄（FRB opaque）：**每实例一份**，持有本会话的停止信号。
///
/// 2026-10-18 修复多开异常：旧实现用全局单例 `DouyuStopRegistry` 登记「当前会话」，
/// 启动第二路会先把第一路的 stop 置 `true` —— 多开时只有最后启动的那路有弹幕，
/// 其余路聊天区显示「已手动停止」。改为句柄自持 stop 后各停各的、互不影响；
/// 句柄被释放（Dart 侧丢弃且未显式 stop）时发送端 drop，会话随句柄一起结束。
#[frb(opaque)]
pub struct DouyuDanmakuConnection {
    stop_tx: watch::Sender<bool>,
}

impl DouyuDanmakuConnection {
    /// 构造连接句柄（尚未连接；`start` 之后才持有会话）。
    #[frb(sync)]
    pub fn new() -> Self {
        let (stop_tx, _stop_rx) = watch::channel(false);
        Self { stop_tx }
    }

    /// 启动斗鱼弹幕会话（F-11~F-16）。
    ///
    /// `room_id` 即 `LiveRoomDetail.danmakuData`（斗鱼弹幕参数**就是房间号**，不是 JSON）——
    /// 空房间号 -> `CoreError(InvalidInput)`，对应 Dart 侧解析失败抛异常的口径（J-10）。
    /// 多路播放各自持句柄调用，会话之间互不停止。
    pub fn start(&self, room_id: String, sink: StreamSink<LiveDanmuItem>) -> Result<(), CoreError> {
        let args = DouyuDanmakuArgs::new(&room_id).map_err(CoreError::from)?;
        let stop_rx = self.stop_tx.subscribe();

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

    /// 手动停止本会话（对齐 Dart `DouyuDanmaku.stop()`：发出 `Closed`，不再重连）。
    #[frb(sync)]
    pub fn stop(&self) {
        let _ = self.stop_tx.send(true);
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