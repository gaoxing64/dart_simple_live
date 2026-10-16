//! Twitch 弹幕（IRC over WebSocket）离线用例（IP-5-DANMAKU）。
//!
//! 夹具：`tests/fixtures/twitch/ws/*.bin` + `*.expected.json`（**golden 对**，合成帧，
//! `_meta` 记录推导依据与 Dart 行号）；`golden/golden-quality-name.json` 为清晰度阈值表。
//!
//! 每个 golden 夹具的 `expected` 段即**本实现的实际行为**；与 Dart 的差异记录在同文件的
//! `dart_would_behavior` / `divergence` 段（差异 D-1~D-5，见 `http-samples.json`
//! 的 `_meta.divergence_index`）。测试断言 `expected`，差异只在夹具里留痕 —— 避免
//! 「测试锁死了错误行为」与「测试放过了行为漂移」两个极端。

mod twitch_common;

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use serde_json::Value;
use slive_core::error::SliveError;
use slive_core::models::{
    LiveDanmuControlEvent, LiveDanmuItem, LiveMessageColor, LiveMessageType,
};
use slive_core::platforms::twitch::danmaku::args::TwitchDanmakuArgs;
use slive_core::platforms::twitch::danmaku::parse::{
    nick_of, parse_frame, parse_line, parse_tags,
};
use slive_core::platforms::twitch::danmaku::session::{
    run_session, tuning, TwitchConnectFactory, TWITCH_HEARTBEAT_SECS, TWITCH_MAX_RECONNECT,
};
use slive_core::testing::{FakeTime, ScriptedFrameSource};
use slive_core::ws::FrameSource;
use twitch_common::{read_bytes, read_text};

// ------------------------------------------------------------------ golden 驱动

/// 读取一个 golden 对的 `expected` 段。
fn golden(name: &str) -> Value {
    serde_json::from_str::<Value>(&read_text(&format!("ws/{name}.expected.json")))
        .unwrap_or_else(|e| panic!("解析 golden {name} 失败: {e}"))
}

/// 读取一个 golden 对的原始帧字节。
fn golden_bytes(name: &str) -> Vec<u8> {
    read_bytes(&format!("ws/{name}.bin"))
}

/// 断言 `parse_frame` 的输出与 golden 的 `expected` 一致。
fn assert_golden(name: &str) {
    let doc = golden(name);
    let bytes = golden_bytes(name);
    let out = parse_frame(&String::from_utf8_lossy(&bytes));
    let want = &doc["expected"];

    let want_messages = want["messages"].as_array().expect("expected.messages");
    assert_eq!(
        out.messages.len(),
        want_messages.len(),
        "{name}: 消息数不符（golden 期望 {}，实际 {}）",
        want_messages.len(),
        out.messages.len()
    );
    for (got, expect) in out.messages.iter().zip(want_messages.iter()) {
        assert_eq!(got.message_type, LiveMessageType::Chat, "{name}: 消息类型");
        assert_eq!(got.user_name, expect["user_name"], "{name}: user_name");
        assert_eq!(got.message, expect["message"], "{name}: message");
        assert_eq!(
            got.color,
            LiveMessageColor::new(
                expect["color"]["r"].as_i64().expect("r") as i32,
                expect["color"]["g"].as_i64().expect("g") as i32,
                expect["color"]["b"].as_i64().expect("b") as i32,
            ),
            "{name}: color"
        );
    }

    let want_replies = want["replies"].as_array().expect("expected.replies");
    assert_eq!(
        out.replies,
        want_replies
            .iter()
            .map(|v| v.as_str().expect("reply 字符串").to_string())
            .collect::<Vec<_>>(),
        "{name}: 待发帧不符"
    );
}

#[test]
fn golden_irc_privmsg_with_color() {
    assert_golden("irc-privmsg-color");
}

#[test]
fn golden_irc_privmsg_without_color_is_dropped_per_dart() {
    // Q-A（`18-fixtures-multiplatform.md §4` 钉死）：三正则缺 color 即整条丢弃。
    // **照搬 Dart，不得顺手修** —— 修正会让 Rust 与 Dart 不一致（AC-30）。
    let doc = golden("irc-privmsg-no-color");
    assert!(
        doc["expected"]["messages"].as_array().expect("messages").is_empty(),
        "夹具应钉死「无 color -> 丢弃」"
    );
    assert_golden("irc-privmsg-no-color");
}

#[test]
fn golden_irc_privmsg_without_display_name_is_dropped_per_dart() {
    // Q-A：三正则缺 display-name 即整条丢弃（**不做 nick 回退**）。
    let doc = golden("irc-privmsg-no-display-name");
    assert!(
        doc["expected"]["messages"].as_array().expect("messages").is_empty(),
        "夹具应钉死「无 display-name -> 丢弃」"
    );
    assert_golden("irc-privmsg-no-display-name");
}

#[test]
fn golden_irc_ping_replies_with_whole_frame_replaced_pong() {
    // Q-B（`twitch_danmaku.dart:79`）：对**整帧** `replaceFirst`，尾随 `\n` 一并带回。
    assert_golden("irc-ping");
}

#[test]
fn golden_irc_ping_privmsg_mixed_pins_dart_whole_frame_replace() {
    // Q8（QA 钉死，`_meta.pinned_dart_behavior = true`）：整帧 replaceFirst ->
    // 回包带上后续 PRIVMSG 行。**照搬**。
    let doc = golden("irc-ping-privmsg-mixed");
    assert_eq!(
        doc["_meta"]["pinned_dart_behavior"], true,
        "Q8 必须保持 pinned 标记"
    );
    assert_golden("irc-ping-privmsg-mixed");
}

#[test]
fn golden_irc_crlf_boundary_stays_pending_qa_decision() {
    // Q-C（`\r` 是否 trim）QA 已裁决（照搬 Dart，不 trim —— AC-30 硬约束），
    // 取值待真机观测：夹具标 PENDING_REAL_CAPTURE，不得写成断言。
    let doc = golden("irc-crlf-boundary");
    assert_eq!(
        doc["expected"]["assertion"], "PENDING_REAL_CAPTURE",
        "口径已定、取值待观测：必须保持 PENDING_REAL_CAPTURE 标记"
    );
    assert!(
        doc["expected"]["messages"].is_null(),
        "待观测项不得写期望值"
    );
    assert_eq!(doc["_meta"]["decision_pending"], true);
    assert!(doc["expected"]["question"].as_str().is_some());
    // 已裁决项必须带 ruling 说明（QA 2026-10-16 裁决纪律）
    assert!(
        doc["expected"]["ruling"]
            .as_str()
            .is_some_and(|s| !s.trim().is_empty()),
        "已裁决项必须带非空 ruling"
    );

    // QA 纪律：待裁决项**不得**在实现侧写单边断言（会「伪装成已断言」）。
    // 当前实现的 interim 口径（照搬 Dart，保留 `\r`）由
    // `platforms::twitch::danmaku::parse::tests::crlf_frame_*` 单测钉住；
    // QA 裁决为 (b) trim 时，改该单测即可，本用例无需变动。
}

#[test]
fn golden_irc_multi_line_batch_preserves_order() {
    assert_golden("irc-multi-line-batch");
}

#[test]
fn golden_irc_notice_reconnect_produces_nothing() {
    assert_golden("irc-notice-reconnect");
}

#[test]
fn golden_request_frames_match_handshake_and_heartbeat() {
    // 握手与心跳帧的 golden：`req-*` 夹具的帧文本必须与实现构造一致。
    for (name, expect) in [
        ("req-cap-req", "CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership"),
        ("req-pass", "PASS SCHMOOPIIE"),
        ("req-pong-heartbeat", "PONG :tmi.twitch.tv"),
    ] {
        assert_eq!(
            String::from_utf8_lossy(&golden_bytes(name)).trim_end(),
            expect,
            "{name} 帧文本不符"
        );
    }
    let join_bytes = golden_bytes("req-join");
    let join = String::from_utf8_lossy(&join_bytes);
    assert_eq!(join.trim_end(), "JOIN #12345");
    assert_eq!(
        TwitchDanmakuArgs::new("alice").handshake("justinfan1"),
        vec![
            "CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership".to_string(),
            "PASS SCHMOOPIIE".to_string(),
            "NICK justinfan1".to_string(),
            "USER justinfan1 8 * :justinfan1".to_string(),
            "JOIN #alice".to_string(),
        ],
        "握手序列必须与 golden 同序（req-* 夹具）"
    );
}

#[test]
fn golden_bins_match_recorded_hex_and_length() {
    // 防夹具自相矛盾：`bytes_hex` / `bytes_len` 与 `.bin` 实际内容必须一致。
    for name in [
        "irc-privmsg-color",
        "irc-privmsg-no-color",
        "irc-privmsg-no-display-name",
        "irc-ping",
        "irc-ping-privmsg-mixed",
        "irc-crlf-boundary",
        "irc-multi-line-batch",
        "irc-notice-reconnect",
    ] {
        let doc = golden(name);
        let bytes = golden_bytes(name);
        if let Some(len) = doc["bytes_len"].as_u64() {
            assert_eq!(bytes.len() as u64, len, "{name}: bytes_len 与 .bin 不符");
        }
        if let Some(hex) = doc["bytes_hex"].as_str() {
            let rebuilt: Vec<u8> = hex
                .split_whitespace()
                .map(|b| u8::from_str_radix(b, 16).expect("hex"))
                .collect();
            assert_eq!(rebuilt, bytes, "{name}: bytes_hex 与 .bin 不符");
        }
    }
}

// ------------------------------------------------------------------ 解析细节

#[test]
fn parse_line_splits_tags_source_command_and_trailing() {
    let (tags, source, command, params, trailing) = parse_line(
        "@color=#FF0000;display-name=Alice :alice!alice@alice.tmi.twitch.tv PRIVMSG #alice :hi there",
    );
    assert_eq!(tags.get("display-name").map(String::as_str), Some("Alice"));
    assert_eq!(tags.get("color").map(String::as_str), Some("#FF0000"));
    assert_eq!(source, "alice!alice@alice.tmi.twitch.tv");
    assert_eq!(command, "PRIVMSG");
    assert_eq!(params, "#alice");
    assert_eq!(trailing, "hi there");
}

#[test]
fn parse_line_handles_no_tags_and_no_source() {
    let (tags, source, command, params, trailing) = parse_line("PING :tmi.twitch.tv");
    assert!(tags.is_empty());
    assert!(source.is_empty());
    assert_eq!(command, "PING");
    assert_eq!(trailing, "tmi.twitch.tv");
    assert!(params.is_empty());
}

#[test]
fn tag_escapes_are_decoded() {
    let tags = parse_tags(r"system-msg=a\sb\:c\\d;display-name=A\x");
    assert_eq!(tags.get("system-msg").map(String::as_str), Some("a b;c\\d"));
    assert_eq!(
        tags.get("display-name").map(String::as_str),
        Some("A\\x"),
        "未知转义保留反斜杠"
    );
}

#[test]
fn nick_extraction_strips_ident_and_host() {
    assert_eq!(nick_of("bob!bob@bob.tmi.twitch.tv"), "bob");
    assert_eq!(nick_of("bob"), "bob");
}

#[test]
fn message_with_colon_and_url_keeps_payload_intact() {
    let out = parse_frame(
        "@color=#FF0000;display-name=A;user-id=1 :a!a@a PRIVMSG #alice :look: https://twitch.tv/a?b=1 好看",
    );
    assert_eq!(
        out.messages[0].message,
        "look: https://twitch.tv/a?b=1 好看"
    );
}

#[test]
fn empty_trailing_is_not_emitted() {
    assert!(parse_frame("@color=#FF0000;display-name=A :a!a@a PRIVMSG #alice :")
        .messages
        .is_empty());
}

#[test]
fn invalid_utf8_does_not_panic() {
    let mut frame = b"@color=#FF0000;display-name=A;user-id=1 :a!a@a PRIVMSG #alice :".to_vec();
    frame.extend_from_slice(&[0xff, 0xfe]);
    let out = parse_frame(&String::from_utf8_lossy(&frame));
    assert_eq!(out.messages.len(), 1);
    assert!(out.messages[0].message.contains('\u{fffd}'));
}

// ------------------------------------------------------------------ 会话时序

/// 记录所有发送帧、可按脚本推进时间源的帧源。
struct RecordingSource {
    inner: ScriptedFrameSource,
    time: Arc<FakeTime>,
    advance_on_first_frame: Option<u64>,
    advanced: bool,
    sent: Arc<Mutex<Vec<String>>>,
}

#[async_trait::async_trait]
impl FrameSource for RecordingSource {
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        if !self.advanced {
            self.advanced = true;
            if let Some(secs) = self.advance_on_first_frame {
                self.time.advance(secs);
            }
        }
        self.inner.next_frame().await
    }

    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
        self.sent
            .lock()
            .expect("sent")
            .push(String::from_utf8_lossy(&frame).to_string());
        self.inner.send(frame).await
    }
}

#[test]
fn tuning_matches_dart() {
    let t = tuning();
    assert_eq!(t.heartbeat_secs, TWITCH_HEARTBEAT_SECS);
    assert_eq!(t.heartbeat_secs, 40, "Dart heartbeatTime = 40 * 1000");
    assert_eq!(t.reconnect_delay_secs, 5, "Dart: reconnect 每 5 秒");
    assert_eq!(t.max_reconnect, TWITCH_MAX_RECONNECT);
    assert_eq!(t.max_reconnect, 5, "Dart maxReconnectTime = 5");
}

#[tokio::test]
async fn session_sends_handshake_in_dart_order() {
    let time = Arc::new(FakeTime::new(twitch_common::FIXED_WTS));
    let sent = Arc::new(Mutex::new(Vec::new()));
    let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
    queue.push_back(Box::new(RecordingSource {
        inner: ScriptedFrameSource::new(vec![]),
        time: time.clone(),
        advance_on_first_frame: None,
        advanced: false,
        sent: Arc::clone(&sent),
    }));
    let connect: TwitchConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
    });
    let items = Arc::new(Mutex::new(Vec::new()));
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        time,
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    )
    .await;

    let got = sent.lock().expect("sent").clone();
    assert_eq!(got.len(), 5, "无帧到达时不触发心跳，只发握手 5 帧");
    assert_eq!(
        got[0],
        "CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership"
    );
    assert_eq!(got[1], "PASS SCHMOOPIIE");
    assert!(got[2].starts_with("NICK justinfan"), "实际 {}", got[2]);
    assert!(got[3].starts_with("USER justinfan"), "实际 {}", got[3]);
    assert_eq!(got[4], "JOIN #alice");
    assert!(matches!(
        items.lock().expect("items").first(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))
    ));
}

#[tokio::test]
async fn session_heartbeat_fires_after_40s_and_ping_is_answered() {
    let time = Arc::new(FakeTime::new(twitch_common::FIXED_WTS));
    let sent = Arc::new(Mutex::new(Vec::new()));
    let ping_frame = golden_bytes("irc-ping");
    let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
    queue.push_back(Box::new(RecordingSource {
        inner: ScriptedFrameSource::new(vec![ping_frame]),
        time: Arc::clone(&time),
        advance_on_first_frame: Some(TWITCH_HEARTBEAT_SECS),
        advanced: false,
        sent: Arc::clone(&sent),
    }));
    let connect: TwitchConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
    });
    let items = Arc::new(Mutex::new(Vec::new()));
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        time,
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    )
    .await;

    let got = sent.lock().expect("sent").clone();
    assert_eq!(got.len(), 7, "握手 5 + 心跳 1 + PONG 应答 1，实际 {got:?}");
    assert_eq!(got[5], "PONG :tmi.twitch.tv", "心跳载荷与 Dart heartbeat() 一致");
    // Q-B/Q8（钉死）：应答 = 整帧 replaceFirst，保留帧尾换行。
    assert_eq!(got[6], "PONG :tmi.twitch.tv\n", "服务端 PING 按 Dart 整帧应答");
}

#[tokio::test]
async fn session_delivers_chat_and_reconnects_five_times_then_closed() {
    let time = Arc::new(FakeTime::new(twitch_common::FIXED_WTS));
    // golden 帧是一整条 WS 文本帧，内部含 PING + PRIVMSG 两行
    let frame = golden_bytes("irc-ping-privmsg-mixed");
    let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
    queue.push_back(Box::new(ScriptedFrameSource::new(vec![frame])));
    let connect: TwitchConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
    });
    let items = Arc::new(Mutex::new(Vec::new()));
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        time,
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    )
    .await;

    let got = items.lock().expect("items").clone();
    assert!(matches!(
        got.first(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))
    ));
    match &got[1] {
        LiveDanmuItem::Message(m) => {
            assert_eq!(m.message_type, LiveMessageType::Chat);
            assert_eq!(m.message, "after ping");
            assert_eq!(m.user_name, "Grace");
            assert_eq!(m.color, LiveMessageColor::new(0x12, 0x34, 0x56));
        }
        other => panic!("第二条应为消息，实际 {other:?}"),
    }
    let reconnects = got
        .iter()
        .filter(|i| {
            matches!(
                i,
                LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })
            )
        })
        .count();
    assert_eq!(reconnects, TWITCH_MAX_RECONNECT as usize, "5s × 5 次重连");
    assert!(matches!(
        got.last(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_)))
    ));
}

#[tokio::test]
async fn session_emits_reconnecting_on_connect_failure() {
    let connect: TwitchConnectFactory =
        Box::new(|| Box::pin(async { Err(SliveError::network("connect refused")) }));
    let items = Arc::new(Mutex::new(Vec::new()));
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        Arc::new(FakeTime::new(0)),
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    )
    .await;

    let got = items.lock().expect("items").clone();
    assert!(
        got.iter()
            .all(|i| !matches!(i, LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))),
        "连接失败不得发 Ready"
    );
    assert_eq!(
        got.iter()
            .filter(|i| matches!(
                i,
                LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })
            ))
            .count(),
        TWITCH_MAX_RECONNECT as usize
    );
    assert!(matches!(
        got.last(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(msg)))
            if msg == "重连超过最大次数"
    ));
}

#[tokio::test]
async fn session_stop_before_connect_emits_closed_immediately() {
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    stop_tx.send(true).expect("预置 stop");
    let connect: TwitchConnectFactory = Box::new(|| panic!("已置 stop 时不得尝试连接"));
    let items = Arc::new(Mutex::new(Vec::new()));
    run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        Arc::new(FakeTime::new(0)),
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    )
    .await;

    let got = items.lock().expect("items").clone();
    assert_eq!(got.len(), 1, "只应发一条事件，实际 {got:?}");
    assert!(
        matches!(&got[0], LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(msg)) if msg == "已手动停止"),
        "实际 {got:?}"
    );
}

#[tokio::test]
async fn session_stop_while_connected_emits_closed() {
    struct NeverSource;
    #[async_trait::async_trait]
    impl FrameSource for NeverSource {
        async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
            std::future::pending::<Option<Result<Vec<u8>, SliveError>>>().await
        }
        async fn send(&mut self, _frame: Vec<u8>) -> Result<(), SliveError> {
            Ok(())
        }
    }

    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    let connect: TwitchConnectFactory = Box::new(|| {
        let source: Box<dyn FrameSource> = Box::new(NeverSource);
        Box::pin(async move { Ok(source) })
    });
    let items = Arc::new(Mutex::new(Vec::new()));
    let runner = tokio::spawn(run_session(
        TwitchDanmakuArgs::new("alice"),
        connect,
        Arc::new(FakeTime::new(0)),
        tuning(),
        stop_rx,
        {
            let items = Arc::clone(&items);
            move |item| items.lock().expect("items").push(item)
        },
    ));
    // 等会话进入帧循环后置 stop。
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    stop_tx.send(true).expect("发 stop");
    runner.await.expect("会话应自行结束");

    let got = items.lock().expect("items").clone();
    assert!(
        got.iter().any(|i| matches!(
            i,
            LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(msg)) if msg == "已手动停止"
        )),
        "应发出「已手动停止」，实际 {got:?}"
    );
    assert!(
        !got.iter()
            .any(|i| matches!(i, LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. }))),
        "手动停止不应触发重连"
    );
}

// ------------------------------------------------------------------ 契约往返

#[test]
fn danmaku_args_contract_roundtrip() {
    let args = TwitchDanmakuArgs::new("Alice");
    assert_eq!(args.channel, "alice", "频道名统一小写（IRC JOIN 口径）");
    let json = args.to_json().expect("序列化");
    assert_eq!(json, r#"{"schema_version":1,"channel":"alice"}"#, "键序稳定");
    assert_eq!(TwitchDanmakuArgs::from_json(&json).expect("反序列化"), args);
    assert_eq!(args.ws_url(), "wss://irc-ws.chat.twitch.tv");
}

#[tokio::test]
async fn room_detail_danmaku_data_is_plain_room_id_per_dart() {
    // 照搬 Dart `twitch_site.dart:241` + QA 夹具 `expected.danmaku_data`：
    // `danmakuData` 就是 roomId 字符串（**不带** JSON 包装）。
    let h = twitch_common::harness();
    h.stub_gql_sample("gql_twitch_tv_room_shell");
    let detail = h
        .site
        .get_room_detail("Alice".to_string())
        .await
        .expect("详情");
    assert_eq!(
        detail.danmaku_data.as_deref(),
        Some("Alice"),
        "danmakuData 应原样是请求的 roomId"
    );
}

#[test]
fn danmaku_args_reject_bad_contract() {
    for bad in [
        r#"{"schema_version":2,"channel":"alice"}"#,
        r#"{"schema_version":1}"#,
        r#"{"schema_version":1,"channel":""}"#,
        r#"{"schema_version":1,"channel":"   "}"#,
        "not json",
    ] {
        let err = TwitchDanmakuArgs::from_json(bad).expect_err("非法契约必须报错");
        assert!(
            matches!(err, SliveError::Decode(_)),
            "{bad} 应为 Decode（J-10：解析失败必须抛错，不得静默兜底），实际 {err:?}"
        );
    }
}

#[test]
fn connect_headers_carry_ua_and_origin() {
    let headers = TwitchDanmakuArgs::new("alice").connect_headers();
    assert!(headers
        .iter()
        .any(|(k, v)| k == "user-agent" && v.contains("Chrome/137")));
    assert!(headers
        .iter()
        .any(|(k, v)| k == "origin" && v == "https://www.twitch.tv"));
}

#[test]
fn anonymous_nick_shape_is_stable_and_in_range() {
    for secs in [0u64, 1, 1_700_000_000, 4_294_967_295] {
        let nick = TwitchDanmakuArgs::anonymous_nick(secs);
        assert!(nick.starts_with("justinfan"), "实际 {nick}");
        let digits: u64 = nick
            .trim_start_matches("justinfan")
            .parse()
            .expect("数字后缀");
        assert!(
            (1000..100_000).contains(&digits),
            "{nick} 超出 Dart 的 1000~99999"
        );
    }
}
