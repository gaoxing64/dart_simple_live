//! 抖音 FRB 桥：opaque 句柄 `LiveDouyinSite` + 弹幕 Stream。
//!
//! 纪律（AC-39 / 裁决 J-6 / R-13）：本文件**只做类型翻译 + 转发**，零协议逻辑 ——
//! URL 拼接 / 签名 / 解析 / 重连全部在 `slive-core`。异常由 `SliveError` -> `CoreError`
//! 映射后抛出（两路径收敛到同一异常类型，ADR-006）。
//!
//! ⚠️ **真机坑（Spec §13 修复记录，FRB FFI 线程无 tokio runtime）**：
//! `start_douyin_danmaku` 在 FRB 的 FFI 调用线程上执行，那里**没有** tokio runtime，
//! 直接 `tokio::spawn` 会 panic（"there is no reactor running"，且 panic 被吞掉、
//! 表现为「直播开始后没有任何弹幕」）。故弹幕会话走**独立线程 + 自建 current_thread
//! runtime**（单会话 IO，current_thread 足够）。

use std::sync::Arc;

use async_trait::async_trait;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::watch;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

use slive_core::error::SliveError;
use slive_core::platforms::douyin::danmaku::args::{SDK_VERSION, VERSION_CODE};
use slive_core::platforms::douyin::danmaku::DouyinDanmakuArgs;
use slive_core::platforms::douyin::signing::build_ws_signature;
use slive_core::platforms::douyin::DouyinSite;
use slive_core::time::SystemClock;
use slive_core::ws::{ConnectFactory, FrameSource};

use crate::api::slive::error::CoreError;
use crate::api::slive::models::{
    LiveCategory, LiveCategoryResult, LiveDanmuItem, LivePlayQuality, LivePlayUrl, LiveRoomDetail,
    LiveSearchAnchorResult, LiveSearchRoomResult, LiveSubCategory, LiveSuperChatMessage,
};
use crate::frb_generated::StreamSink;

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// 生产 WS 帧事件源（与 B站同款 `FrameSource` 实现，仅握手头由抖音 args 决定）。
pub struct DouyinWsFrameSource {
    stream: WsStream,
}

#[async_trait]
impl FrameSource for DouyinWsFrameSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        loop {
            match self.stream.next().await {
                None => return None,
                Some(Err(e)) => return Some(Err(SliveError::Websocket(e.to_string()))),
                Some(Ok(Message::Binary(data))) => return Some(Ok(data)),
                Some(Ok(Message::Close(_))) => return None,
                Some(Ok(_)) => continue, // Text / Ping / Pong 等忽略
            }
        }
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        self.stream
            .send(Message::Binary(frame))
            .await
            .map_err(|e| SliveError::Websocket(e.to_string()))
    }
}

/// 抖音站点句柄（FRB opaque）。状态在 Rust 侧，Dart 只持句柄。
#[frb(opaque)]
pub struct LiveDouyinSite {
    inner: DouyinSite,
}

impl Default for LiveDouyinSite {
    fn default() -> Self {
        Self::new()
    }
}

impl LiveDouyinSite {
    /// 构造站点句柄（App 每平台单例持有）。
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: DouyinSite::new(),
        }
    }

    /// 站点 ID（`"douyin"`）。
    #[frb(sync)]
    pub fn id(&self) -> String {
        self.inner.id()
    }

    /// 站点名（`"抖音直播"`）。
    #[frb(sync)]
    pub fn name(&self) -> String {
        self.inner.name()
    }

    /// 注入凭证 / 配置（`{"cookie": "...", "hlsFirst": false}`）。
    #[frb(sync)]
    pub fn set_site_attrs(&self, data: String) -> Result<(), CoreError> {
        self.inner.set_site_attrs(&data).map_err(CoreError::from)
    }

    /// 分类 A 列表。
    pub async fn get_categories(&self) -> Result<Vec<LiveCategory>, CoreError> {
        self.inner.get_categories().await.map_err(CoreError::from)
    }

    /// 分类下房间（`page_size` 服务端不认，保留形参对齐 Dart 签名）。
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

    /// 推荐房间。
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

    /// 搜索直播间。
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

    /// 搜索主播（抖音不支持，恒报错）。
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

    /// 房间详情（三段降级）。
    pub async fn get_room_detail(&self, room_id: String) -> Result<LiveRoomDetail, CoreError> {
        self.inner.get_room_detail(room_id).await.map_err(CoreError::from)
    }

    /// 清晰度列表（本地计算，无网络请求）。
    pub async fn get_play_qualities(
        &self,
        detail: LiveRoomDetail,
    ) -> Result<Vec<LivePlayQuality>, CoreError> {
        self.inner.get_play_qualities(detail).await.map_err(CoreError::from)
    }

    /// 播放地址（本地计算，无网络请求）。
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

    /// 直播状态。
    pub async fn get_live_status(&self, room_id: String) -> Result<bool, CoreError> {
        self.inner.get_live_status(room_id).await.map_err(CoreError::from)
    }

    /// 房间 SC 列表（抖音无此能力，恒空）。
    pub async fn get_super_chat_messages(
        &self,
        room_id: String,
    ) -> Result<Vec<LiveSuperChatMessage>, CoreError> {
        self.inner
            .get_super_chat_messages(room_id)
            .await
            .map_err(CoreError::from)
    }

    /// 登录二维码（抖音不支持扫码登录）。
    pub async fn get_qr_code(&self) -> Result<crate::api::slive::models::QrCode, CoreError> {
        self.inner.get_qr_code().await.map_err(CoreError::from)
    }

    /// 扫码轮询（抖音不支持扫码登录）。
    pub async fn get_qr_poll_result(
        &self,
        qrcode_key: String,
    ) -> Result<crate::api::slive::models::QrPollResult, CoreError> {
        self.inner
            .get_qr_poll_result(qrcode_key)
            .await
            .map_err(CoreError::from)
    }

    /// 账号信息。
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

/// 当前活跃抖音弹幕会话的停止信号（单房间语义，与 Dart core 一致）。
fn active_stop() -> &'static std::sync::Mutex<Option<watch::Sender<bool>>> {
    static CELL: std::sync::OnceLock<std::sync::Mutex<Option<watch::Sender<bool>>>> =
        std::sync::OnceLock::new();
    CELL.get_or_init(|| std::sync::Mutex::new(None))
}

/// 手动停止当前抖音弹幕会话（全局单例；对齐 Dart `LiveDanmaku.stop()`）。
#[frb(sync)]
pub fn stop_douyin_danmaku() {
    if let Some(stop_tx) = active_stop().lock().expect("stop 锁").take() {
        let _ = stop_tx.send(true);
    }
}

/// 启动抖音弹幕会话：事件推入 stream（FRB 侧表现为 `Stream<LiveDanmuItem>`）。
///
/// `args_json` 是 [`DouyinDanmakuArgs`] 的 JSON 串（snake_case 契约）；解析失败或
/// 握手签名失败 -> `CoreError`，对应 Dart 侧 `FormatException`（J-10）。
/// 同时启动新会话会**停止**旧会话（单房间语义）。
pub fn start_douyin_danmaku(
    args_json: String,
    sink: StreamSink<LiveDanmuItem>,
) -> Result<(), CoreError> {
    let args = DouyinDanmakuArgs::from_json(&args_json).map_err(CoreError::from)?;
    let (stop_tx, stop_rx) = watch::channel(false);

    // 单房间语义：新会话顶掉旧会话
    {
        let mut active = active_stop().lock().expect("stop 锁");
        if let Some(old) = active.take() {
            let _ = old.send(true);
        }
        *active = Some(stop_tx);
    }

    // 握手 URL 提前算好（含 x_bogus 签名）：连接工厂只持克隆，签名不重复计算。
    // 签名失败属「入参非法」，必须在起线程**之前**返回给 Dart（否则错误会被吞进
    // 无人观察的线程里，表现为「直播了但连不上」且无任何提示）。
    let ws_url = build_ws_signature(&args.room_id, &args.user_id, VERSION_CODE, SDK_VERSION)
        .map_err(CoreError::from)
        .map(|signature| {
            let ts_millis = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or_default();
            args.ws_url(args.primary_host(), ts_millis, &signature)
        })?;
    let ws_headers = args.connect_headers();

    let connect: ConnectFactory = Box::new(move || {
        let url = ws_url.clone();
        let headers = ws_headers.clone();
        Box::pin(async move { connect_douyin_ws(url, headers).await })
    });

    // ⚠️ FRB 的 FFI 调用线程没有 tokio runtime —— 在这里 `tokio::spawn` 会
    // panic（"there is no reactor running"，真实日志抓到，且 panic 被吞）。
    // 弹幕会话放到独立线程 + 自建 runtime（current_thread 足够：单会话 IO）。
    std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("douyin danmaku runtime");
        runtime.block_on(async move {
            slive_core::platforms::douyin::danmaku::run_session(
                args,
                connect,
                Arc::new(SystemClock),
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

/// 连接装配（URL/headers 来自核心契约）。
#[flutter_rust_bridge::frb(ignore)]
async fn connect_douyin_ws(
    url: String,
    headers: Vec<(String, String)>,
) -> Result<Box<dyn FrameSource>, SliveError> {
    let mut request = url
        .into_client_request()
        .map_err(|e| SliveError::Websocket(format!("非法 WS 地址: {e}")))?;
    for (key, value) in headers {
        let name = key
            .parse::<tokio_tungstenite::tungstenite::http::HeaderName>()
            .map_err(|e| SliveError::Websocket(format!("非法头名: {e}")))?;
        let value = value
            .parse::<tokio_tungstenite::tungstenite::http::HeaderValue>()
            .map_err(|e| SliveError::Websocket(format!("非法头值: {e}")))?;
        request.headers_mut().insert(name, value);
    }
    let (stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .map_err(|e| SliveError::Websocket(e.to_string()))?;
    Ok(Box::new(DouyinWsFrameSource { stream }))
}
