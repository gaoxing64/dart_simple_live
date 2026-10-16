//! DoD-3 端到端冒烟（联网，手动执行）：
//! `cargo test -p rust_lib_simple_live_app --test manual_e2e -- --ignored --nocapture`
//!
//! 固定房间 6：详情 → 清晰度 → 取流 → 弹幕 30s 窗口；另覆盖一条错误流（不存在的房间 → 类型化错误，AC-23）。

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use rust_lib_simple_live_app::api::slive::danmaku::connect_ws_frame_source;
use slive_core::platforms::bilibili::BilibiliSite;
use slive_core::time::SystemClock;
use slive_core::ws::{run_session, ConnectFactory, SessionTuning};

#[tokio::test(flavor = "multi_thread")]
#[ignore = "联网冒烟：手动执行 cargo test -p rust_lib_simple_live_app --test manual_e2e -- --ignored --nocapture"]
async fn dod3_bilibili_end_to_end() {
    let site = BilibiliSite::new();
    let room_id = "6";

    // 1) 房间详情（未开播仍应有详情与弹幕参数，AC-22）
    let detail = site
        .get_room_detail(room_id.to_string())
        .await
        .expect("房间详情应成功");
    println!(
        "[1] detail: status={} title={} danmakuData={}bytes",
        detail.status,
        detail.title,
        detail.danmaku_data.as_ref().map(|s| s.len()).unwrap_or(0)
    );
    assert!(
        detail.danmaku_data.is_some(),
        "弹幕参数（danmakuData）不得缺失"
    );

    // 2) 清晰度
    let qualities = site
        .get_play_qualities(detail.clone())
        .await
        .expect("清晰度应成功");
    println!("[2] qualities: {} 项", qualities.len());
    assert!(!qualities.is_empty(), "清晰度列表不应为空");

    // 3) 播放地址（mcdn 后置）
    let play = site
        .get_play_urls(detail.clone(), qualities[0].clone())
        .await
        .expect("取流应成功");
    println!("[3] play urls: {} 条", play.urls.len());
    assert!(!play.urls.is_empty(), "播放地址不应为空");

    // 4) 弹幕 30s 窗口（真实 WS + join + 心跳 + 解码分发）
    let args_json = detail.danmaku_data.clone().expect("上一步已断言");
    let args =
        slive_core::platforms::bilibili::danmaku::BiliBiliDanmakuArgs::from_json(&args_json)
            .expect("danmakuData 应可解析");
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    let messages = Arc::new(AtomicUsize::new(0));
    let ready = Arc::new(AtomicUsize::new(0));

    let msg_counter = Arc::clone(&messages);
    let ready_counter = Arc::clone(&ready);
    let url = args.ws_url();
    let headers = args.connect_headers();
    // 先显式连一次，把连接失败原因打印出来（会话循环里 connect 失败是静默重连）
    match connect_ws_frame_source(url.clone(), headers.clone()).await {
        Ok(_) => println!("[4.0] ws connect ok: {url}"),
        Err(e) => println!("[4.0] ws connect FAILED: {e}"),
    }
    let connect: ConnectFactory = Box::new(move || {
        let url = url.clone();
        let headers = headers.clone();
        Box::pin(async move { connect_ws_frame_source(url, headers).await })
    });
    let on_item = move |item: slive_core::models::LiveDanmuItem| match item {
        slive_core::models::LiveDanmuItem::Message(_) => {
            msg_counter.fetch_add(1, Ordering::SeqCst);
        }
        slive_core::models::LiveDanmuItem::Control(event) => {
            if matches!(event, slive_core::models::LiveDanmuControlEvent::Ready) {
                ready_counter.fetch_add(1, Ordering::SeqCst);
            }
        }
    };
    let session = tokio::spawn(run_session(
        args,
        connect,
        Arc::new(SystemClock),
        SessionTuning::bilibili(),
        stop_rx,
        on_item,
    ));
    tokio::time::sleep(std::time::Duration::from_secs(30)).await;
    let _ = stop_tx.send(true);
    let _ = session.await;

    let msg_count = messages.load(Ordering::SeqCst);
    let ready_count = ready.load(Ordering::SeqCst);
    println!("[4] danmaku 30s: Ready={ready_count} messages={msg_count}");
    assert!(ready_count >= 1, "30s 内应至少 Ready 一次");
    assert!(msg_count >= 1, "30s 内应收到至少一条弹幕/人气消息");

    // 5) 错误流：不存在的房间 → 类型化错误，不得 panic（AC-23）
    let err = site
        .get_room_detail("999999999999".to_string())
        .await
        .expect_err("不存在的房间必须报错");
    println!("[5] error flow: {err}");
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "联网冒烟：手动执行"]
async fn dod3_error_flow_only() {
    let site = BilibiliSite::new();
    let err = site
        .get_room_detail("999999999999".to_string())
        .await
        .expect_err("不存在的房间必须报错");
    println!("[error flow] {err}");
}
