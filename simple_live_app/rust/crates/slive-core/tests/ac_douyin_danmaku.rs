//! 抖音弹幕链路 AC（protobuf 解码 + 会话时序 + 脏帧容错）。
//!
//! 全部离线：帧由 prost 结构体**合成**（`PushFrame` + gzip + `Response`），
//! 不依赖网络录制 —— 合成即确定性，且能覆盖真机难复现的分支（脏帧 / 未知 method /
//! `needAck` 开与关）。

use flate2::write::GzEncoder;
use flate2::Compression;
use prost::Message as _;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex as StdMutex};

use slive_core::error::SliveError;
use slive_core::models::{LiveDanmuControlEvent, LiveDanmuItem, LiveMessageType};
use slive_core::platforms::douyin::danmaku::args::DouyinDanmakuArgs;
use slive_core::platforms::douyin::danmaku::decode::{
    ack_frame, decode_frame, heartbeat_frame, pending_ack, METHOD_CHAT, METHOD_ROOM_USER_SEQ,
    PAYLOAD_TYPE_MSG,
};
use slive_core::platforms::douyin::danmaku::proto::{
    ChatMessage, Message, PushFrame, Response, RoomUserSeqMessage, User,
};
use slive_core::platforms::douyin::danmaku::session::{run_session, ConnectFactory};
use slive_core::testing::{FakeTime, ScriptedFrameSource};

fn args() -> DouyinDanmakuArgs {
    DouyinDanmakuArgs::new(
        "416144012050".into(),
        "7382735338101328680".into(),
        "7273033021933946".into(),
        "ttwid=1%2Cabc;".into(),
    )
}

fn gzip(data: &[u8]) -> Vec<u8> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    std::io::Write::write_all(&mut encoder, data).expect("压缩");
    encoder.finish().expect("收尾")
}

/// 合成一帧业务消息。
fn frame(log_id: u64, messages: Vec<Message>, need_ack: bool, internal_ext: &str) -> Vec<u8> {
    PushFrame {
        log_id,
        payload_type: PAYLOAD_TYPE_MSG.to_string(),
        payload: gzip(
            &Response {
                messages_list: messages,
                need_ack,
                internal_ext: internal_ext.to_string(),
                ..Default::default()
            }
            .encode_to_vec(),
        ),
        ..Default::default()
    }
    .encode_to_vec()
}

fn chat_frame(content: &str, nick: &str) -> Vec<u8> {
    frame(
        1,
        vec![Message {
            method: METHOD_CHAT.to_string(),
            payload: ChatMessage {
                content: content.to_string(),
                user: Some(User {
                    nick_name: nick.to_string(),
                    ..Default::default()
                }),
                ..Default::default()
            }
            .encode_to_vec(),
            msg_id: 1,
            msg_type: 0,
        }],
        false,
        "",
    )
}

fn online_frame(total_user: i64) -> Vec<u8> {
    frame(
        2,
        vec![Message {
            method: METHOD_ROOM_USER_SEQ.to_string(),
            payload: RoomUserSeqMessage {
                total_user,
                ..Default::default()
            }
            .encode_to_vec(),
            msg_id: 2,
            msg_type: 0,
        }],
        false,
        "",
    )
}

fn collector() -> (
    Arc<StdMutex<Vec<LiveDanmuItem>>>,
    impl FnMut(LiveDanmuItem) + Send,
) {
    let items: Arc<StdMutex<Vec<LiveDanmuItem>>> = Arc::new(StdMutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    (items, move |item| sink.lock().expect("sink").push(item))
}

#[test]
fn ac_douyin_chat_frame_decodes_to_live_message() {
    let got = decode_frame(&chat_frame("你好", "小明")).expect("应能解码");
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].message_type, LiveMessageType::Chat);
    assert_eq!(got[0].message, "你好");
    assert_eq!(got[0].user_name, "小明");
    assert_eq!(got[0].color, slive_core::models::LiveMessageColor::white());
    assert!(got[0].data.is_none(), "聊天消息不带 data");
}

#[test]
fn ac_douyin_online_frame_decodes_total_user_to_online_data() {
    let got = decode_frame(&online_frame(4321)).expect("应能解码");
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].message_type, LiveMessageType::Online);
    assert_eq!(
        got[0].data,
        Some(slive_core::models::LiveMessageData::Online(4321)),
        "Dart 取 totalUser(tag=7) 作为人气"
    );
    assert_eq!(got[0].message, "", "人气消息消息体为空（Dart 同口径）");
}

#[test]
fn ac_douyin_unknown_method_is_silently_skipped() {
    let f = frame(
        3,
        vec![Message {
            method: "WebcastLikeMessage".to_string(),
            payload: vec![1, 2, 3],
            msg_id: 3,
            msg_type: 0,
        }],
        false,
        "",
    );
    assert!(
        decode_frame(&f).expect("应能解码").is_empty(),
        "点赞/礼物等 method 不产消息（Dart if/else 链亦然）"
    );
}

#[test]
fn ac_douyin_heartbeat_frame_yields_no_message() {
    assert!(decode_frame(&heartbeat_frame())
        .expect("心跳帧应能解")
        .is_empty());
}

#[test]
fn ac_douyin_ack_frame_carries_log_id_and_internal_ext_in_payload() {
    let raw = ack_frame(7788, "internal-ext-value");
    let back = PushFrame::decode(raw.as_slice()).expect("应能解码");
    assert_eq!(back.payload_type, "ack");
    assert_eq!(back.log_id, 7788);
    assert_eq!(
        String::from_utf8(back.payload).expect("utf8"),
        "internal-ext-value",
        "internalExt 必须落在 payload（Dart 误写 payloadType，此处按 proto 修正）"
    );
}

#[test]
fn ac_douyin_pending_ack_reads_flag_and_fields() {
    let needs = frame(555, vec![], true, "ext-abc");
    assert_eq!(
        pending_ack(&needs).expect("应能解析"),
        Some((555, "ext-abc".to_string()))
    );
    let no_need = frame(556, vec![], false, "ext-xyz");
    assert_eq!(pending_ack(&no_need).expect("应能解析"), None);
    assert_eq!(
        pending_ack(&heartbeat_frame()).expect("心跳无需 ack"),
        None
    );
}

#[test]
fn ac_douyin_dirty_frames_report_decode_error_without_panic() {
    // 非法 protobuf
    assert!(decode_frame(&[0xff, 0xff, 0xff]).is_err());
    // payload_type=msg 但 payload 非 gzip
    let bad = PushFrame {
        payload_type: PAYLOAD_TYPE_MSG.to_string(),
        payload: vec![1, 2, 3, 4],
        ..Default::default()
    }
    .encode_to_vec();
    assert!(matches!(decode_frame(&bad), Err(SliveError::Decode(_))));
}

#[test]
fn ac_douyin_args_roundtrip_and_reject_bad_schema() {
    let a = args();
    let json = a.to_json().expect("序列化");
    assert_eq!(
        DouyinDanmakuArgs::from_json(&json).expect("往返"),
        a,
        "契约往返必须无损"
    );
    for key in ["schema_version", "web_rid", "room_id", "user_id", "cookie"] {
        assert!(json.contains(&format!("\"{key}\"")), "缺少键 {key}：{json}");
    }
    assert!(matches!(
        DouyinDanmakuArgs::from_json(r#"{"schema_version":2,"web_rid":"w","room_id":"r","user_id":"u","cookie":""}"#),
        Err(SliveError::Decode(_))
    ));
    assert!(matches!(
        DouyinDanmakuArgs::from_json(r#"{"schema_version":1,"room_id":"r"}"#),
        Err(SliveError::Decode(_))
    ));
}

#[test]
fn ac_douyin_ws_url_carries_path_signature_and_injected_cursor() {
    let url = args().ws_url("webcast100-ws-web-lq.douyin.com", 1_700_000_000_123, "SIG");
    assert!(url.starts_with("wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/?"));
    assert!(url.ends_with("&signature=SIG"));
    assert!(url.contains("cursor=h-1_t-1700000000123_r-1_d-1_u-1"));
    assert!(url.contains("room_id=7382735338101328680"));
    assert!(url.contains("user_unique_id=7273033021933946"));
    assert!(url.contains("compress=gzip"));
}

#[test]
fn ac_douyin_connect_headers_carry_ua_cookie_origin() {
    let headers = args().connect_headers();
    let get = |k: &str| {
        headers
            .iter()
            .find(|(hk, _)| hk.eq_ignore_ascii_case(k))
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    };
    assert!(get("user-agent").contains("Chrome/125.0.0.0"));
    assert_eq!(get("cookie"), "ttwid=1%2Cabc;");
    assert_eq!(get("origin"), "https://live.douyin.com");
}

#[tokio::test]
async fn ac_douyin_session_emits_ready_then_messages_then_reconnects_five_times() {
    let mut queue: VecDeque<Box<dyn slive_core::ws::FrameSource>> = VecDeque::new();
    queue.push_back(Box::new(ScriptedFrameSource::new(vec![chat_frame(
        "你好", "小明",
    )])));
    let connect: ConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
    });
    let (items, on_item) = collector();
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);

    run_session(args(), connect, Arc::new(FakeTime::new(0)), stop_rx, on_item).await;

    let got = items.lock().expect("items").clone();
    assert!(matches!(
        got.first(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))
    ));
    assert!(
        matches!(&got[1], LiveDanmuItem::Message(m)
            if m.message_type == LiveMessageType::Chat && m.message == "你好"),
        "聊天帧应分发为 chat 消息"
    );
    assert_eq!(
        got.iter()
            .filter(|i| matches!(i, LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })))
            .count(),
        5,
        "最多 5 次重连（5s×5，与 Dart WebScoketUtils 一致）"
    );
    assert!(matches!(
        got.last(),
        Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_)))
    ));
}

#[tokio::test]
async fn ac_douyin_session_manual_stop_closes_without_connecting() {
    let (items, on_item) = collector();
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(true);
    let connect: ConnectFactory =
        Box::new(|| Box::pin(async { Err(SliveError::network("不应发起连接")) }));

    run_session(args(), connect, Arc::new(FakeTime::new(0)), stop_rx, on_item).await;

    let got = items.lock().expect("items").clone();
    assert_eq!(got.len(), 1, "手动停止只发一个 Closed");
    assert!(matches!(
        got[0],
        LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_))
    ));
}

#[tokio::test]
async fn ac_douyin_session_sends_join_heartbeat_and_ack() {
    /// 记录所有已发送帧的源。
    struct RecordingSource {
        inner: ScriptedFrameSource,
        sent: Arc<StdMutex<Vec<Vec<u8>>>>,
    }

    #[async_trait::async_trait]
    impl slive_core::ws::FrameSource for RecordingSource {
        async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
            self.inner.next_frame().await
        }
        async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
            self.sent.lock().expect("sent").push(frame.clone());
            self.inner.send(frame).await
        }
    }

    let sent: Arc<StdMutex<Vec<Vec<u8>>>> = Arc::new(StdMutex::new(Vec::new()));
    // 连接工厂是可多次调用的闭包：用 Option 取出一次性连接源（帧用尽后交回错误，
    // 让会话走「重连 5 次 -> Closed」的既定收尾）。
    let mut pending = Some(RecordingSource {
        inner: ScriptedFrameSource::new(vec![frame(
            4242,
            vec![Message {
                method: METHOD_CHAT.to_string(),
                payload: ChatMessage {
                    content: "ack 测试".into(),
                    ..Default::default()
                }
                .encode_to_vec(),
                msg_id: 9,
                msg_type: 0,
            }],
            true,
            "ext-xyz",
        )]),
        sent: Arc::clone(&sent),
    });
    let connect: ConnectFactory = Box::new(move || {
        let next = pending.take();
        Box::pin(async move {
            next.ok_or_else(|| SliveError::network("无更多连接"))
                .map(|s| Box::new(s) as Box<dyn slive_core::ws::FrameSource>)
        })
    });
    let (_items, on_item) = collector();
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);

    run_session(args(), connect, Arc::new(FakeTime::new(0)), stop_rx, on_item).await;
    // 会话已自行走完「帧用尽 -> 重连耗尽 -> Closed」，receiver 随之释放，
    // 此时再发停止信号必然失败 —— 这属预期收尾，不做断言（信号的作用已由
    // 「帧用尽后不再分发消息」与最终 Closed 事件覆盖）。
    drop(stop_tx);

    let frames = sent.lock().expect("sent").clone();
    assert!(!frames.is_empty(), "Ready 后应立刻发心跳（对齐 Dart joinRoom）");
    let first = PushFrame::decode(frames[0].as_slice()).expect("首帧应能解码");
    assert_eq!(first.payload_type, "hb", "Dart 的 joinRoom 实为心跳帧");

    let ack = frames
        .iter()
        .map(|f| PushFrame::decode(f.as_slice()).expect("应能解码"))
        .find(|p| p.payload_type == "ack")
        .expect("needAck=true 时必须回 ack，否则服务端断连");
    assert_eq!(ack.log_id, 4242, "ack 必须回带 log_id");
    assert_eq!(String::from_utf8(ack.payload).expect("utf8"), "ext-xyz");
}
