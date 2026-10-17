//! 弹幕会话装配：把五个平台的 args / 调参 / 连接工厂接到 core 的会话主循环。
//!
//! 这里是**唯一**与平台协议相关的「接线」代码，零解析逻辑 —— 帧编解码、心跳、
//! 重连策略全部在 `slive-core`。

use std::sync::Arc;

use slive_core::models::{
    LiveDanmuControlEvent, LiveDanmuItem, LiveMessageData, LiveMessageType, LiveRoomDetail,
};
use slive_core::time::SystemClock;
use slive_core::ws::SessionTuning;
use tokio::sync::watch;

use crate::url::{Platform, Target};
use crate::ws;

/// 启动弹幕会话并阻塞到会话结束（Ctrl-C 触发优雅停止）。
pub async fn run(
    target: &Target,
    detail: &LiveRoomDetail,
    color: bool,
) -> Result<(), String> {
    let (stop_tx, stop_rx) = watch::channel(false);

    tokio::spawn(async move {
        if tokio::signal::ctrl_c().await.is_ok() {
            eprintln!("\n[停止] 正在关闭弹幕会话…");
            let _ = stop_tx.send(true);
        }
    });

    match target.platform {
        Platform::Bilibili => {
            let on_item = move |item: LiveDanmuItem| print_item(&item, color);
            run_bilibili(detail, stop_rx, on_item).await
        }
        Platform::Douyu => {
            let on_item = move |item: LiveDanmuItem| print_item(&item, color);
            run_douyu(detail, stop_rx, on_item).await
        }
        Platform::Huya => {
            let on_item = move |item: LiveDanmuItem| print_item(&item, color);
            run_huya(detail, stop_rx, on_item).await
        }
        Platform::Douyin => {
            let on_item = move |item: LiveDanmuItem| print_item(&item, color);
            run_douyin(detail, stop_rx, on_item).await
        }
        Platform::Twitch => {
            let on_item = move |item: LiveDanmuItem| print_item(&item, color);
            run_twitch(detail, stop_rx, on_item).await
        }
    }
}

async fn run_bilibili(
    detail: &LiveRoomDetail,
    stop_rx: watch::Receiver<bool>,
    on_item: impl FnMut(LiveDanmuItem) + Send,
) -> Result<(), String> {
    use slive_core::platforms::bilibili::danmaku::BiliBiliDanmakuArgs;

    let json = danmaku_json(detail, "B站")?;
    let args = BiliBiliDanmakuArgs::from_json(json).map_err(|e| e.to_string())?;
    let connect = ws::binary_factory(args.ws_url(), args.connect_headers());

    slive_core::ws::run_session(
        args,
        connect,
        Arc::new(SystemClock),
        SessionTuning::bilibili(),
        stop_rx,
        on_item,
    )
    .await;
    Ok(())
}

async fn run_douyu(
    detail: &LiveRoomDetail,
    stop_rx: watch::Receiver<bool>,
    on_item: impl FnMut(LiveDanmuItem) + Send,
) -> Result<(), String> {
    use slive_core::platforms::douyu::danmaku::args::DouyuDanmakuArgs;
    use slive_core::platforms::douyu::danmaku::session::{douyu_tuning, run_session};

    // 斗鱼只需房间号即可建会话（与 Dart console 一致），不依赖 danmaku_data。
    let args = DouyuDanmakuArgs::new(&detail.room_id).map_err(|e| e.to_string())?;
    let connect = ws::binary_factory(args.ws_url(), args.connect_headers());

    run_session(
        args,
        connect,
        Arc::new(SystemClock),
        douyu_tuning(),
        stop_rx,
        on_item,
    )
    .await;
    Ok(())
}

async fn run_huya(
    detail: &LiveRoomDetail,
    stop_rx: watch::Receiver<bool>,
    on_item: impl FnMut(LiveDanmuItem) + Send,
) -> Result<(), String> {
    use slive_core::http::DEFAULT_USER_AGENT;
    use slive_core::platforms::huya::common::{BASE_URL, WS_SERVER_URL};
    use slive_core::platforms::huya::danmaku::{run_session, HuyaDanmakuArgs};

    let json = danmaku_json(detail, "虎牙")?;
    let args = HuyaDanmakuArgs::from_json(json).map_err(|e| e.to_string())?;
    let headers = vec![
        ("user-agent".to_string(), DEFAULT_USER_AGENT.to_string()),
        ("origin".to_string(), BASE_URL.to_string()),
    ];
    let connect = ws::binary_factory(WS_SERVER_URL.to_string(), headers);

    // SC 增量拉取传 `None`：CLI 不消费醒目留言列表，弹幕主循环不受影响。
    run_session(
        args,
        connect,
        Arc::new(SystemClock),
        SessionTuning::bilibili(),
        stop_rx,
        None,
        on_item,
    )
    .await;
    Ok(())
}

async fn run_douyin(
    detail: &LiveRoomDetail,
    stop_rx: watch::Receiver<bool>,
    on_item: impl FnMut(LiveDanmuItem) + Send,
) -> Result<(), String> {
    use slive_core::platforms::douyin::danmaku::args::{SDK_VERSION, VERSION_CODE};
    use slive_core::platforms::douyin::danmaku::session::run_session;
    use slive_core::platforms::douyin::danmaku::DouyinDanmakuArgs;
    use slive_core::platforms::douyin::signing::build_ws_signature;

    let json = danmaku_json(detail, "抖音")?;
    let args = DouyinDanmakuArgs::from_json(json).map_err(|e| e.to_string())?;

    // 握手 URL 含 x_bogus 签名：签名失败属入参非法，必须在建连前报出来。
    let signature = build_ws_signature(&args.room_id, &args.user_id, VERSION_CODE, SDK_VERSION)
        .map_err(|e| e.to_string())?;
    let ts_millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default();
    let url = args.ws_url(args.primary_host(), ts_millis, &signature);
    let connect = ws::binary_factory(url, args.connect_headers());

    run_session(
        args,
        connect,
        Arc::new(SystemClock),
        stop_rx,
        on_item,
    )
    .await;
    Ok(())
}

async fn run_twitch(
    detail: &LiveRoomDetail,
    stop_rx: watch::Receiver<bool>,
    on_item: impl FnMut(LiveDanmuItem) + Send,
) -> Result<(), String> {
    use slive_core::platforms::twitch::danmaku::args::TwitchDanmakuArgs;
    use slive_core::platforms::twitch::danmaku::session::{run_session, tuning};

    // Q-13：Twitch 的 danmaku_data 是频道名纯字符串，不是 JSON 契约。
    let args = TwitchDanmakuArgs::new(&detail.room_id);
    let connect = ws::text_factory(args.ws_url(), args.connect_headers());

    run_session(
        args,
        connect,
        Arc::new(SystemClock),
        tuning(),
        stop_rx,
        on_item,
    )
    .await;
    Ok(())
}

fn danmaku_json<'a>(detail: &'a LiveRoomDetail, platform: &str) -> Result<&'a str, String> {
    detail
        .danmaku_data
        .as_deref()
        .ok_or_else(|| format!("{platform}未下发弹幕参数（房间可能未开播）"))
}

fn print_item(item: &LiveDanmuItem, color: bool) {
    match item {
        LiveDanmuItem::Control(event) => match event {
            LiveDanmuControlEvent::Ready => eprintln!("[已连接]"),
            LiveDanmuControlEvent::Reconnecting { attempt } => {
                eprintln!("[重连] 第 {attempt} 次")
            }
            LiveDanmuControlEvent::Closed(reason) => eprintln!("[已关闭] {reason}"),
        },
        LiveDanmuItem::Message(msg) => match msg.message_type {
            LiveMessageType::Chat => {
                println!("{}：{}", paint(&msg.user_name, msg.color, color), msg.message)
            }
            LiveMessageType::Online => {
                if let Some(LiveMessageData::Online(online)) = &msg.data {
                    eprintln!("----- 人气值：{online} -----");
                }
            }
            LiveMessageType::SuperChat => {
                if let Some(LiveMessageData::SuperChat(sc)) = &msg.data {
                    println!("[SC ¥{}] {}：{}", sc.price, sc.user_name, sc.message);
                }
            }
            LiveMessageType::Gift => {}
        },
    }
}

fn paint(text: &str, color: slive_core::models::LiveMessageColor, enabled: bool) -> String {
    if !enabled {
        return text.to_string();
    }
    format!(
        "\x1b[38;2;{};{};{}m{text}\x1b[0m",
        color.r, color.g, color.b
    )
}
