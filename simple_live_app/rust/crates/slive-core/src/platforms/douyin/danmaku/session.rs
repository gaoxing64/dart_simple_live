//! 抖音弹幕会话主循环：连接 → Ready → 心跳/ack → 帧循环（解码分发）→ 断线重连。
//!
//! 时序对照 Dart `WebScoketUtils` + `DouyinDanmaku`：
//! - 心跳 **10s**（Dart `DouyinDanmaku.heartbeatTime = 10 * 1000`，非 B站的 60s）；
//! - 重连 `5s × 5` 次上限，**收到消息后计数归零**（Dart `receiveMessage` 里 `reconnectTime = 0`）；
//! - `onReady` 后 Dart 的 `joinRoom` 实际就是发一个心跳帧（`payloadType = 'hb'`），故本实现
//!   在 Ready 后立即发首个心跳（对齐服务端「先心跳才推送」的握手要求）。
//!
//! 与 B站 `ws::runner::run_session` 的差异（故不复用该函数）：帧语义完全不同 —— B站是
//! 16 字节定长头 + op 码，抖音是 protobuf `PushFrame`，且抖音需要**回 ack**（B站无此概念）。

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use crate::error::SliveError;
use crate::models::{LiveDanmuControlEvent, LiveDanmuItem};
use crate::time::TimeSource;
use crate::ws::session::{FrameSource, SessionTuning};

use super::args::DouyinDanmakuArgs;
use super::decode::{ack_frame, decode_frame, heartbeat_frame, pending_ack};

/// 连接工厂：每次（重）连创建新的帧事件源。
pub type ConnectFactory = Box<
    dyn FnMut()
        -> Pin<Box<dyn Future<Output = Result<Box<dyn FrameSource>, SliveError>> + Send>>
        + Send,
>;

/// 抖音默认调参（心跳 10s / 重连间隔 5s / 最多 5 次）。
pub const DOUYIN_TUNING: SessionTuning = SessionTuning {
    heartbeat_secs: 10,
    reconnect_delay_secs: 5,
    max_reconnect: 5,
};

/// 握手后的首帧（Dart `joinRoom` 实为心跳帧）。
pub fn join_frame() -> Vec<u8> {
    heartbeat_frame()
}

/// 会话主循环。`on_item` 依次收到 `Ready` / `Message` / `Reconnecting` / `Closed`。
///
/// `_args` 不参与循环逻辑（握手 URL 由桥层连接工厂按 args 计算），保留在签名里是为了
/// 与 B站 `run_session` 同形：调用方只需把「详情产出的参数」原样交给会话。
/// `stop` 置 `true` 即手动停止：发出 `Closed` 后返回，不再重连。
/// ⚠️ 调用方**不得**在 FRB FFI 线程直接调用本函数（无 tokio runtime，`tokio::select!`
/// 会 panic）—— 桥层须用独立线程 + 自建 runtime（见 `api/slive/douyin.rs`）。
pub async fn run_session(
    _args: DouyinDanmakuArgs,
    mut connect: ConnectFactory,
    time: Arc<dyn TimeSource>,
    mut stop: tokio::sync::watch::Receiver<bool>,
    mut on_item: impl FnMut(LiveDanmuItem) + Send,
) {
    let mut attempt: u32 = 0;
    'session: loop {
        if *stop.borrow_and_update() {
            on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
                "已手动停止".to_string(),
            )));
            return;
        }
        let mut source = match (connect)().await {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[douyin-danmaku] connect failed: {e}");
                if reconnect_or_close(&mut attempt, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
        };
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready));
        if source.send(join_frame()).await.is_err() {
            if reconnect_or_close(&mut attempt, time.as_ref(), &mut on_item).await {
                return;
            }
            continue 'session;
        }
        let mut last_heartbeat = time.unix_secs();
        loop {
            let frame = tokio::select! {
                biased;
                f = source.next_frame() => f,
                _ = stop.changed() => {
                    if *stop.borrow_and_update() {
                        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
                            "已手动停止".to_string(),
                        )));
                        return;
                    }
                    continue;
                }
            };
            let Some(Ok(frame)) = frame else {
                match &frame {
                    Some(Err(e)) => eprintln!("[douyin-danmaku] frame error: {e}"),
                    _ => eprintln!("[douyin-danmaku] connection closed by server"),
                }
                if reconnect_or_close(&mut attempt, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            };
            // 收到消息 → 重连计数归零（Dart receiveMessage）
            attempt = 0;
            let heartbeat_due =
                time.unix_secs() >= last_heartbeat + DOUYIN_TUNING.heartbeat_secs;
            if heartbeat_due && source.send(heartbeat_frame()).await.is_ok() {
                last_heartbeat = time.unix_secs();
            }
            // needAck → 回 ack（回带 log_id 与 internal_ext）
            match pending_ack(&frame) {
                Ok(Some((log_id, internal_ext))) => {
                    if let Err(e) = source.send(ack_frame(log_id, &internal_ext)).await {
                        eprintln!("[douyin-danmaku] ack 发送失败: {e}");
                    }
                }
                Ok(None) => {}
                Err(e) => eprintln!("[douyin-danmaku] ack 解析失败: {e}"),
            }
            // 解码分发：脏帧在此被吞掉（Dart 亦以 try/catch 记日志后继续）
            match decode_frame(&frame) {
                Ok(messages) => {
                    for message in messages {
                        on_item(LiveDanmuItem::Message(Box::new(message)));
                    }
                }
                Err(e) => eprintln!("[douyin-danmaku] 帧解码失败: {e}"),
            }
        }
    }
}

/// 重连或关闭：`attempt + 1`，超限 -> `Closed` 并返回 `true`；否则 `Reconnecting` + 等待。
async fn reconnect_or_close(
    attempt: &mut u32,
    time: &dyn TimeSource,
    on_item: &mut (dyn FnMut(LiveDanmuItem) + Send),
) -> bool {
    *attempt += 1;
    if *attempt > DOUYIN_TUNING.max_reconnect {
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
            "重连超过最大次数".to_string(),
        )));
        true
    } else {
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting {
            attempt: *attempt,
        }));
        time.sleep(DOUYIN_TUNING.reconnect_delay_secs).await;
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeTime, ScriptedFrameSource};
    use std::collections::VecDeque;
    use std::sync::Mutex as StdMutex;

    use crate::models::LiveMessageType;
    use crate::platforms::douyin::danmaku::decode::{METHOD_CHAT, PAYLOAD_TYPE_MSG};
    use crate::platforms::douyin::danmaku::proto::{ChatMessage, Message, PushFrame, Response, User};
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use prost::Message as _;
    use std::io::Write;

    fn chat_frame(content: &str, nick: &str) -> Vec<u8> {
        let response = Response {
            messages_list: vec![Message {
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
            ..Default::default()
        };
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&response.encode_to_vec()).expect("压缩");
        PushFrame {
            payload_type: PAYLOAD_TYPE_MSG.to_string(),
            payload: encoder.finish().expect("收尾"),
            ..Default::default()
        }
        .encode_to_vec()
    }

    fn args() -> DouyinDanmakuArgs {
        DouyinDanmakuArgs::new(
            "416144012050".into(),
            "7382735338101328680".into(),
            "7273033021933946".into(),
            "ttwid=1".into(),
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
    fn join_frame_is_heartbeat_push_frame() {
        let frame = join_frame();
        let push = PushFrame::decode(frame.as_slice()).expect("应能解码");
        assert_eq!(push.payload_type, "hb", "Dart joinRoom 实为心跳帧");
        assert!(push.payload.is_empty());
    }

    #[tokio::test]
    async fn ready_then_chat_message_then_reconnect_five_times() {
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
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
            matches!(&got[1], LiveDanmuItem::Message(m) if m.message_type == LiveMessageType::Chat && m.message == "你好"),
            "聊天帧应分发为 chat 消息"
        );
        let reconnects = got
            .iter()
            .filter(|i| {
                matches!(
                    i,
                    LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })
                )
            })
            .count();
        assert_eq!(reconnects, 5, "最多 5 次重连（5s×5）");
        assert!(matches!(
            got.last(),
            Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_)))
        ));
    }

    #[tokio::test]
    async fn manual_stop_closes_without_reconnect() {
        let (items, on_item) = collector();
        // 停止信号在会话开始前就置 true：会话应立即发 Closed 且不发起任何连接
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(true);
        let connect: ConnectFactory = Box::new(|| Box::pin(async { Err(SliveError::network("不应连接")) }));
        run_session(args(), connect, Arc::new(FakeTime::new(0)), stop_rx, on_item).await;
        // 会话结束后 receiver 已随 `run_session` 返回而释放，再 send 必然失败 —— 预期收尾

        let got = items.lock().expect("items").clone();
        assert_eq!(got.len(), 1, "手动停止只发一个 Closed");
        assert!(matches!(
            got[0],
            LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_))
        ));
    }
}
