//! IP-4 虎牙弹幕帧解码集成测试（消费 `tests/fixtures/huya/ws/` 帧夹具）。
//!
//! 夹具为 QA 预置的**合成帧**（`_meta.synthetic = true`，标注 `needs_realtime_validation`）：
//! 逐字节照 Dart core 的 TARS 编码规则与结构 tag 推导。
//! 本测试断言「字节 -> 期望消息」，覆盖聊天 / 表情 / 颜色 / 人气 / V2 触发 / 脏帧 / 未知命令。

use std::sync::Arc;

use serde_json::Value;
use slive_core::models::{
    LiveDanmuItem, LiveMessageColor, LiveMessageData, LiveMessageType, LiveSuperChatMessage,
};
use slive_core::platforms::huya::danmaku::args::HuyaDanmakuArgs;
use slive_core::platforms::huya::danmaku::{
    decode_to_items, frames, ConnectFactory, SuperChatFetcher,
};
use slive_core::testing::{FakeTime, ScriptedFrameSource};
use slive_core::ws::SessionTuning;

fn fixtures_dir() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/huya/ws")
}

fn read_bytes(name: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(name)).unwrap_or_else(|e| panic!("读取帧 {name} 失败: {e}"))
}

fn read_expected(name: &str) -> Value {
    let path = fixtures_dir().join(format!("{name}.expected.json"));
    let text =
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取期望 {name} 失败: {e}"));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("解析期望 {name} 失败: {e}"))
}

/// 解码一帧并返回消息列表（统一入口）。
fn decode(name: &str) -> Vec<LiveDanmuItem> {
    let frame = read_bytes(name);
    decode_to_items(&frame, &HuyaDanmakuArgs::new(1, 66_0000, 66_0001), 66_0000).items
}

fn message_of(item: &LiveDanmuItem) -> &slive_core::models::LiveMessage {
    let LiveDanmuItem::Message(message) = item else {
        panic!("期望消息，实际 {item:?}");
    };
    message
}

// ---------------------------------------------------------------------------
// 聊天弹幕
// ---------------------------------------------------------------------------

#[test]
fn ac_huya_ws_chat_frame_maps_nickname_text_and_color() {
    let want = read_expected("frame-push-uri1400-chat")["expected"]["messages"][0].clone();
    let items = decode("frame-push-uri1400-chat.bin");
    assert_eq!(items.len(), 1, "应产出恰好一条消息");
    let message = message_of(&items[0]);

    assert_eq!(message.message_type, LiveMessageType::Chat);
    assert_eq!(message.user_name, want["user_name"].as_str().unwrap());
    assert_eq!(message.message, want["message"].as_str().unwrap());
    assert_eq!(message.color.r, want["color"]["r"].as_i64().unwrap() as i32);
    assert_eq!(message.color.g, want["color"]["g"].as_i64().unwrap() as i32);
    assert_eq!(message.color.b, want["color"]["b"].as_i64().unwrap() as i32);
}

#[test]
fn ac_huya_ws_chat_frame_extracts_emoticon() {
    let items = decode("frame-push-uri1400-chat.bin");
    let message = message_of(&items[0]);
    // 该夹具正文为「你好，虎牙」，不含表情占位符
    assert!(
        message.emoticons.is_none(),
        "无表情包时应为 None，实际 {:?}",
        message.emoticons
    );
}

#[test]
fn ac_huya_ws_zero_color_falls_back_to_white() {
    let want = read_expected("frame-push-uri1400-color0")["expected"]["messages"][0].clone();
    let items = decode("frame-push-uri1400-color0.bin");
    assert_eq!(items.len(), 1);
    let message = message_of(&items[0]);
    assert_eq!(message.message, want["message"].as_str().unwrap());
    assert_eq!(
        message.color,
        LiveMessageColor::white(),
        "fontColor<=0 归白色（对齐 Dart huya_danmaku.dart:234）"
    );
}

// ---------------------------------------------------------------------------
// 在线人气
// ---------------------------------------------------------------------------

#[test]
fn ac_huya_ws_online_frame_maps_int_data() {
    let want = read_expected("frame-push-uri8006-online")["expected"]["messages"][0].clone();
    let items = decode("frame-push-uri8006-online.bin");
    assert_eq!(items.len(), 1);
    let message = message_of(&items[0]);

    assert_eq!(message.message_type, LiveMessageType::Online);
    assert_eq!(
        message.data,
        Some(LiveMessageData::Online(
            want["data_int"].as_i64().unwrap() as i32
        )),
        "人气以类型化枚举承载（保住 AC-12 语义）"
    );
    assert_eq!(message.color, LiveMessageColor::white());
    assert!(message.user_name.is_empty());
    assert!(message.message.is_empty());
}

// ---------------------------------------------------------------------------
// V2 推送
// ---------------------------------------------------------------------------

#[tokio::test]
async fn ac_huya_ws_v2_superchat_uri_triggers_fetch() {
    let expected = read_expected("frame-push-v2-uri2001317-superchat-trigger")["expected"].clone();
    let trigger = &expected["triggers"][0];
    assert_eq!(trigger["iUri"].as_i64().unwrap(), frames::URI_SUPER_CHAT);

    let called = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let counter = Arc::clone(&called);
    let fetcher: SuperChatFetcher = Arc::new(move |pid| {
        counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Box::pin(async move { vec![sample_sc(pid)] })
    });

    // 夹具口径：本帧只置触发位、不产消息（expected.messages 为空）
    let decoded = decode_to_items(
        &read_bytes("frame-push-v2-uri2001317-superchat-trigger.bin"),
        &HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        66_0000,
    );
    assert!(decoded.items.is_empty(), "V2 SC 帧不产消息（QA 夹具钉死）");
    assert!(decoded.super_chat_triggered, "但必须置触发位");

    // 触发位由会话循环消费：经 SuperChatFetcher 拉取后产出 SC 消息
    let items = slive_core::platforms::huya::danmaku::super_chat_map::super_chat_items(
        66_0000,
        Some(&fetcher),
    )
    .await;
    assert_eq!(
        called.load(std::sync::atomic::Ordering::SeqCst),
        1,
        "V2 SC 事件触发一次拉取"
    );
    assert_eq!(items.len(), 1, "拉取后产出 SC 消息");
    let message = message_of(&items[0]);
    assert_eq!(message.message_type, LiveMessageType::SuperChat);
    assert_eq!(message.user_name, "SUPER_CHAT_MESSAGE");
    assert!(matches!(message.data, Some(LiveMessageData::SuperChat(_))));
}

#[test]
fn ac_huya_ws_v2_unrelated_uri_yields_nothing() {
    let expected = read_expected("frame-push-v2-uri1400-ignored")["expected"].clone();
    assert!(
        expected["messages"].as_array().expect("messages").is_empty(),
        "夹具声明无消息"
    );
    let items = decode("frame-push-v2-uri1400-ignored.bin");
    assert!(items.is_empty(), "iUri=1400 的 V2 帧不产出消息（仅 1400 出现在 cmd7）");
}

// ---------------------------------------------------------------------------
// 脏帧 / 未知命令（不得中断会话）
// ---------------------------------------------------------------------------

#[test]
fn ac_huya_ws_dirty_frame_yields_no_items_without_panic() {
    let expected = read_expected("frame-dirty-tag")["expected"].clone();
    assert!(expected["messages"].as_array().expect("messages").is_empty());
    let items = decode("frame-dirty-tag.bin");
    assert!(items.is_empty(), "脏帧 -> 空序列（对齐 Dart 的 try/catch）");
}

#[test]
fn ac_huya_ws_unknown_cmdtype_is_ignored() {
    let expected = read_expected("frame-unknown-cmdtype")["expected"].clone();
    assert!(expected["messages"].as_array().expect("messages").is_empty());
    let items = decode("frame-unknown-cmdtype.bin");
    assert!(items.is_empty());
    assert_eq!(
        frames::decode_frame(&read_bytes("frame-unknown-cmdtype.bin")),
        frames::HuyaFrame::Ignored
    );
}

// ---------------------------------------------------------------------------
// 上行请求帧（join / 心跳）
// ---------------------------------------------------------------------------

#[test]
fn ac_huya_ws_register_group_frame_uses_cmd16_with_group_ids() {
    // 夹具是「客户端请求字节黄金」，不带 input 描述；groupIds 由协议本身决定
    // （Dart `buildJoinGroupData`：`["live:{pid}", "chat:{pid}"]`）
    let group_ids = ["live:660000".to_string(), "chat:660000".to_string()];

    let frame = frames::build_join_frame(&group_ids).expect("构造 join 帧");
    let mut decoder = slive_core::tars::TarsDecoder::new(&frame);
    assert_eq!(
        decoder.read_i64(0).expect("cmdType") as i32,
        frames::cmd::REGISTER_GROUP_REQ,
        "join 帧命令类型固定 16"
    );
    // 载荷中应能看到 groupId 字面量（TARS string 以长度前缀 + UTF-8 存储）
    let body = String::from_utf8_lossy(decoder.remaining_slice());
    for id in &group_ids {
        assert!(body.contains(id), "join 载荷应含 {id}，实际 {body}");
    }
}

#[test]
fn ac_huya_ws_heartbeat_frame_uses_cmd20() {
    let frame = frames::build_heartbeat_frame().expect("构造心跳帧");
    let mut decoder = slive_core::tars::TarsDecoder::new(&frame);
    assert_eq!(
        decoder.read_i64(0).expect("cmdType") as i32,
        frames::cmd::HEART_BEAT_REQ,
        "心跳帧命令类型固定 20"
    );
}

// ---------------------------------------------------------------------------
// 会话循环（复用 B站 runner 的时序语义）
// ---------------------------------------------------------------------------

fn sample_sc(pid: i64) -> LiveSuperChatMessage {
    let now = chrono::Local::now();
    LiveSuperChatMessage {
        user_name: format!("金主{pid}"),
        face: "https://img/f.jpg".to_string(),
        message: "上头条".to_string(),
        price: 100,
        start_time: now - chrono::Duration::seconds(10),
        end_time: now + chrono::Duration::seconds(50),
        background_color: "#ffffff".to_string(),
        background_bottom_color: "#246488".to_string(),
    }
}

#[tokio::test]
async fn ac_huya_session_sends_join_then_heartbeat_and_maps_messages() {
    // 记录上行帧，验证顺序：join -> 首心跳
    struct RecordingSource {
        inner: ScriptedFrameSource,
        sent: Arc<std::sync::Mutex<Vec<Vec<u8>>>>,
    }

    #[async_trait::async_trait]
    impl slive_core::ws::FrameSource for RecordingSource {
        async fn next_frame(&mut self) -> Option<Result<Vec<u8>, slive_core::error::SliveError>> {
            self.inner.next_frame().await
        }
        async fn send(&mut self, frame: Vec<u8>) -> Result<(), slive_core::error::SliveError> {
            self.sent.lock().expect("锁").push(frame.clone());
            self.inner.send(frame).await
        }
    }

    let sent: Arc<std::sync::Mutex<Vec<Vec<u8>>>> = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut queue = std::collections::VecDeque::new();
    queue.push_back(Box::new(RecordingSource {
        inner: ScriptedFrameSource::new(vec![read_bytes("frame-push-uri8006-online.bin")]),
        sent: Arc::clone(&sent),
    }) as Box<dyn slive_core::ws::FrameSource>);

    let connect: ConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move {
            next.ok_or_else(|| slive_core::error::SliveError::network("无更多连接"))
        })
    });

    let items: Arc<std::sync::Mutex<Vec<LiveDanmuItem>>> =
        Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);

    slive_core::platforms::huya::danmaku::run_session(
        HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        connect,
        Arc::new(FakeTime::new(0)),
        SessionTuning::bilibili(),
        stop_rx,
        None,
        move |item| sink.lock().expect("锁").push(item),
    )
    .await;

    // 上行序列：join(16) -> 首心跳(20)
    let sent = sent.lock().expect("锁").clone();
    assert!(sent.len() >= 2, "至少发出 join 与首心跳");
    let cmd_of = |frame: &[u8]| {
        let mut d = slive_core::tars::TarsDecoder::new(frame);
        d.read_i64(0).expect("cmdType") as i32
    };
    assert_eq!(cmd_of(&sent[0]), frames::cmd::REGISTER_GROUP_REQ, "首帧是 join");
    assert_eq!(cmd_of(&sent[1]), frames::cmd::HEART_BEAT_REQ, "join 后立即发首心跳");

    // 下行事件：Ready -> online 消息 -> ... -> Closed
    let got = items.lock().expect("锁").clone();
    assert!(matches!(
        got.first(),
        Some(LiveDanmuItem::Control(
            slive_core::models::LiveDanmuControlEvent::Ready
        ))
    ));
    assert!(
        matches!(&got[1], LiveDanmuItem::Message(m) if m.message_type == LiveMessageType::Online),
        "online 帧应被分发"
    );
    assert!(matches!(
        got.last(),
        Some(LiveDanmuItem::Control(
            slive_core::models::LiveDanmuControlEvent::Closed(_)
        ))
    ));
}

#[tokio::test]
async fn ac_huya_session_reconnects_five_times_then_closes() {
    let mut queue = std::collections::VecDeque::new();
    queue.push_back(Box::new(ScriptedFrameSource::new(vec![
        read_bytes("frame-push-uri8006-online.bin"),
    ])) as Box<dyn slive_core::ws::FrameSource>);

    let connect: ConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move {
            next.ok_or_else(|| slive_core::error::SliveError::network("无更多连接"))
        })
    });

    let items: Arc<std::sync::Mutex<Vec<LiveDanmuItem>>> =
        Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);

    slive_core::platforms::huya::danmaku::run_session(
        HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        connect,
        Arc::new(FakeTime::new(0)),
        SessionTuning::bilibili(),
        stop_rx,
        None,
        move |item| sink.lock().expect("锁").push(item),
    )
    .await;

    let got = items.lock().expect("锁").clone();
    let reconnects = got
        .iter()
        .filter(|i| {
            matches!(
                i,
                LiveDanmuItem::Control(
                    slive_core::models::LiveDanmuControlEvent::Reconnecting { .. }
                )
            )
        })
        .count();
    assert_eq!(reconnects, 5, "5s × 5 重连（对齐 B站 runner 语义）");
}

/// 回归（2026-10-18 虎牙弹幕停更）：SC 拉取必须作为 future 在会话 runtime 内 await。
///
/// 旧实现把同步闭包注入会话，桥层在闭包里又 `block_on` 一个 runtime —— Tokio 直接
/// panic（"Cannot start a runtime from within a runtime"），弹幕线程静默退出。
#[tokio::test]
async fn ac_huya_session_super_chat_fetch_awaits_inside_session_runtime() {
    let mut queue = std::collections::VecDeque::new();
    queue.push_back(Box::new(ScriptedFrameSource::new(vec![
        read_bytes("frame-push-v2-uri2001317-superchat-trigger.bin"),
        read_bytes("frame-push-uri8006-online.bin"),
    ])) as Box<dyn slive_core::ws::FrameSource>);

    let connect: ConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move {
            next.ok_or_else(|| slive_core::error::SliveError::network("无更多连接"))
        })
    });

    let items: Arc<std::sync::Mutex<Vec<LiveDanmuItem>>> =
        Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    let in_runtime = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let fetch_flag = Arc::clone(&in_runtime);
    let fetcher: SuperChatFetcher = Arc::new(move |pid| {
        let flag = Arc::clone(&fetch_flag);
        Box::pin(async move {
            flag.store(
                tokio::runtime::Handle::try_current().is_ok(),
                std::sync::atomic::Ordering::SeqCst,
            );
            vec![sample_sc(pid)]
        })
    });
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);

    slive_core::platforms::huya::danmaku::run_session(
        HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        connect,
        Arc::new(FakeTime::new(0)),
        SessionTuning::bilibili(),
        stop_rx,
        Some(fetcher),
        move |item| sink.lock().expect("锁").push(item),
    )
    .await;

    assert!(
        in_runtime.load(std::sync::atomic::Ordering::SeqCst),
        "SC 拉取必须在会话 runtime 内 await（不得嵌套 block_on）"
    );
    let got = items.lock().expect("锁").clone();
    assert!(
        got.iter().any(|item| matches!(
            item,
            LiveDanmuItem::Message(m) if m.message_type == LiveMessageType::SuperChat
        )),
        "SC 触发帧经异步拉取后应产出 SuperChat 消息"
    );
}

#[tokio::test]
async fn ac_huya_session_stop_closes_without_reconnect() {
    let connect: ConnectFactory = Box::new(|| {
        Box::pin(async {
            Ok(Box::new(ScriptedFrameSource::new(Vec::new())) as Box<dyn slive_core::ws::FrameSource>)
        })
    });

    let items: Arc<std::sync::Mutex<Vec<LiveDanmuItem>>> =
        Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    stop_tx.send(true).expect("置停止");

    slive_core::platforms::huya::danmaku::run_session(
        HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        connect,
        Arc::new(FakeTime::new(0)),
        SessionTuning::bilibili(),
        stop_rx,
        None,
        move |item| sink.lock().expect("锁").push(item),
    )
    .await;

    let got = items.lock().expect("锁").clone();
    assert_eq!(got.len(), 1, "手动停止只发一条 Closed");
    assert!(matches!(
        got.first(),
        Some(LiveDanmuItem::Control(
            slive_core::models::LiveDanmuControlEvent::Closed(_)
        ))
    ));
}

// ---------------------------------------------------------------------------
// 上游同步 97413c60：旧 uri 2001314 不再触发（防回退反例）
// ---------------------------------------------------------------------------

#[test]
fn ac_huya_upstream_97413c60_old_uri_2001314_does_not_trigger() {
    // SlotSun dev 97413c60「listen real uri」：真实 SC uri 是 2001317；
    // 旧值 2001314 为修复前语义，**不得再触发**（实现若回退即本用例失败）。
    let doc = read_expected("frame-push-v2-uri2001314-ignored");
    assert_eq!(
        doc["expected"]["triggers"].as_array().expect("triggers").len(),
        0,
        "旧 uri 2001314 不得触发（上游 97413c60 口径）"
    );
    let decoded = decode_to_items(
        &read_bytes("frame-push-v2-uri2001314-ignored.bin"),
        &HuyaDanmakuArgs::new(1, 66_0000, 66_0001),
        66_0000,
    );
    assert!(decoded.items.is_empty(), "反例帧同样不产消息");
    assert!(
        !decoded.super_chat_triggered,
        "旧 uri 2001314 必须不置触发位（上游 97413c60）"
    );
}
