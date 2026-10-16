//! F-11 弹幕会话主循环：连接 → Ready → join → 帧循环（解码分发 + 帧间心跳）→ 断线重连。
//!
//! 事件模型见 [`LiveDanmuItem`]；连接工厂由桥层提供（生产 = tokio-tungstenite 包装），
//! 核心 crate 不持有真实连接（ADR-001 纯核心边界）。
//!
//! 时序（对照 Dart `WebScoketUtils` + `BiliBiliDanmaku`）：
//! - 心跳 60s（帧间检查，时间来自注入源）；
//! - 断线重连 `5s × 5` 次，**收到消息后计数归零**（AC-26）；
//! - 超过最大次数 → `Closed`（不再重试）。

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use crate::error::SliveError;
use crate::models::{LiveDanmuControlEvent, LiveDanmuItem};
use crate::platforms::bilibili::danmaku::{decode_frame, BiliBiliDanmakuArgs};
use crate::time::TimeSource;

use super::frame::{encode_packet, heartbeat_packet, OP_JOIN};
use super::session::{FrameSource, SessionTuning};

/// 连接工厂：每次（重）连创建新的帧事件源。
pub type ConnectFactory = Box<
    dyn FnMut()
        -> Pin<Box<dyn Future<Output = Result<Box<dyn FrameSource>, SliveError>> + Send>>
        + Send,
>;

/// join 帧：op=7 + join 载荷（AC-11 的 golden 断言落点）。
pub fn join_frame(args: &BiliBiliDanmakuArgs) -> Vec<u8> {
    encode_packet(args.join_payload().as_bytes(), OP_JOIN as i32)
}

/// 会话主循环。`on_item` 依次收到 `Ready` / `Message` / `Reconnecting` / `Closed`。
///
/// 心跳在**每帧处理后**检查到期（60s，注入时间源判定）；长静默场景的定时兜底
/// 由桥层连接实现负责（核心不持有定时器，保证可测性）。
/// `stop` 置 `true` 即手动停止：发出 `Closed("已手动停止")` 后返回，不再重连。
pub async fn run_session(
    args: BiliBiliDanmakuArgs,
    mut connect: ConnectFactory,
    time: Arc<dyn TimeSource>,
    tuning: SessionTuning,
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
            Ok(s) => {
                eprintln!("[danmaku-rs] connect ok");
                s
            }
            Err(e) => {
                eprintln!("[danmaku-rs] connect failed: {e}");
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
        };
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready));
        if let Err(e) = source.send(join_frame(&args)).await {
            eprintln!("[danmaku-rs] join send failed: {e}");
            if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                return;
            }
            continue 'session;
        }
        let mut last_heartbeat = time.unix_secs();
        // join 后立即发首个心跳（对齐主流 B站客户端：服务端收到首个心跳才开始推送；
        // 纯「帧间检查」会与服务端互相等待 —— 真实冒烟发现，DoD-3）
        if source.send(heartbeat_packet()).await.is_ok() {
            last_heartbeat = time.unix_secs();
        }
        let mut first_frame_logged = false;
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
                // 诊断：断开原因必须可见（服务端 Close=None / 传输错误=Err）
                match &frame {
                    Some(Err(e)) => eprintln!("[danmaku-rs] frame error: {e}"),
                    _ => eprintln!("[danmaku-rs] connection closed by server"),
                }
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            };
            // 收到消息 → 重连计数归零（AC-26）
            attempt = 0;
            if !first_frame_logged {
                first_frame_logged = true;
                match crate::ws::frame::parse_header(&frame) {
                    Ok(h) => eprintln!(
                        "[danmaku-rs] first frame: op={} protover={} body_len={}",
                        h.op,
                        h.protover,
                        frame.len().saturating_sub(16)
                    ),
                    Err(e) => eprintln!("[danmaku-rs] first frame 解析失败: {e}"),
                }
            }
            if time.unix_secs() >= last_heartbeat + tuning.heartbeat_secs
                && source.send(heartbeat_packet()).await.is_ok()
            {
                last_heartbeat = time.unix_secs();
            }
            for message in decode_frame(&frame) {
                on_item(LiveDanmuItem::Message(Box::new(message)));
            }
        }
    }
}

/// 重连或关闭：`attempt + 1`，超限 → `Closed` 并返回 `true`；否则 `Reconnecting` + 等待并返回 `false`。
async fn reconnect_or_close(
    attempt: &mut u32,
    tuning: &SessionTuning,
    time: &dyn TimeSource,
    on_item: &mut (dyn FnMut(LiveDanmuItem) + Send),
) -> bool {
    *attempt += 1;
    if *attempt > tuning.max_reconnect {
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
            "重连超过最大次数".to_string(),
        )));
        true
    } else {
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting {
            attempt: *attempt,
        }));
        time.sleep(tuning.reconnect_delay_secs).await;
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::LiveMessageType;
    use crate::testing::{FakeTime, ScriptedFrameSource};
    use std::collections::VecDeque;
    use std::sync::Mutex as StdMutex;

    fn op3_frame(popularity: i32) -> Vec<u8> {
        let mut frame = vec![0u8; 20];
        frame[0..4].copy_from_slice(&20u32.to_be_bytes());
        frame[4..6].copy_from_slice(&16u16.to_be_bytes());
        frame[8..12].copy_from_slice(&3u32.to_be_bytes());
        frame[12..16].copy_from_slice(&1u32.to_be_bytes());
        frame[16..20].copy_from_slice(&popularity.to_be_bytes());
        frame
    }

    fn args() -> BiliBiliDanmakuArgs {
        BiliBiliDanmakuArgs::from_json(
            r#"{"schema_version":1,"room_id":1,"uid":0,"token":"t","server_host":"h","buvid":"b","cookie":""}"#,
        )
        .expect("合法 args")
    }

    fn collector() -> (
        Arc<StdMutex<Vec<LiveDanmuItem>>>,
        impl FnMut(LiveDanmuItem) + Send,
    ) {
        let items: Arc<StdMutex<Vec<LiveDanmuItem>>> = Arc::new(StdMutex::new(Vec::new()));
        let sink = Arc::clone(&items);
        (items, move |item| sink.lock().expect("sink").push(item))
    }

    /// 模拟「60s 静默后来了一帧」：取首帧前推进注入时钟，并记录全部已发送帧。
    struct TimeAdvancingSource {
        inner: ScriptedFrameSource,
        time: Arc<FakeTime>,
        advanced: bool,
        sent: Arc<StdMutex<Vec<Vec<u8>>>>,
    }

    #[async_trait::async_trait]
    impl FrameSource for TimeAdvancingSource {
        async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
            if !self.advanced {
                self.advanced = true;
                self.time.advance(60);
            }
            self.inner.next_frame().await
        }

        async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
            // 同步记录（锁内无 await，guard 不跨 await）
            self.sent.lock().expect("sent").push(frame.clone());
            self.inner.send(frame).await
        }
    }

    #[test]
    fn ac11_join_frame_uses_op7_and_payload_body() {
        let args = args();
        let frame = join_frame(&args);
        assert_eq!(&frame[4..6], &16u16.to_be_bytes(), "头长固定 16");
        assert_eq!(&frame[8..12], &7u32.to_be_bytes(), "join 的 op=7");
        assert_eq!(&frame[12..16], &1u32.to_be_bytes(), "seq 固定 1");
        assert_eq!(&frame[16..], args.join_payload().as_bytes(), "body = join 载荷");
    }

    #[tokio::test]
    async fn ac26_reconnect_five_times_then_closed() {
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(ScriptedFrameSource::new(vec![op3_frame(100)])));
        let connect: ConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        run_session(
            args(),
            connect,
            Arc::new(FakeTime::new(0)),
            SessionTuning::bilibili(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        assert!(matches!(
            got.first(),
            Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))
        ));
        assert!(
            matches!(&got[1], LiveDanmuItem::Message(m) if m.message_type == LiveMessageType::Online),
            "op3 帧应分发为 online 消息"
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
    async fn ac26_received_message_resets_reconnect_counter() {
        // 6 个连接、每个都推帧 → 计数每次归零；连接耗尽后才走满剩余重连并 Closed
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        for _ in 0..6 {
            queue.push_back(Box::new(ScriptedFrameSource::new(vec![op3_frame(1)])));
        }
        let connect: ConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        run_session(
            args(),
            connect,
            Arc::new(FakeTime::new(0)),
            SessionTuning::bilibili(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        let ready_count = got
            .iter()
            .filter(|i| matches!(i, LiveDanmuItem::Control(LiveDanmuControlEvent::Ready)))
            .count();
        assert_eq!(ready_count, 6, "每次重连成功都应 Ready（计数被消息归零）");
        assert_eq!(
            got.iter()
                .filter(|i| matches!(i, LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_))))
                .count(),
            1,
            "只有重连耗尽才 Closed"
        );
    }

    #[tokio::test]
    async fn heartbeat_sent_when_due_on_frame_arrival() {
        let time = Arc::new(FakeTime::new(1_000_000));
        let sent: Arc<StdMutex<Vec<Vec<u8>>>> = Arc::new(StdMutex::new(Vec::new()));
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(TimeAdvancingSource {
            inner: ScriptedFrameSource::new(vec![op3_frame(1)]),
            time: Arc::clone(&time),
            advanced: false,
            sent: Arc::clone(&sent),
        }));
        let connect: ConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        run_session(
            args(),
            connect,
            time,
            SessionTuning::bilibili(),
            stop_rx,
            on_item,
        )
        .await;

        // 事件里应有首帧的 online 消息，且会话最终因队列耗尽走 Closed —— 只关心发送序列
        let got = sent.lock().expect("sent");
        assert_eq!(got.len(), 3, "join + 首心跳 + 到期心跳");
        assert_eq!(&got[0][8..12], &7u32.to_be_bytes(), "首帧是 join(op=7)");
        assert_eq!(&got[1][8..12], &2u32.to_be_bytes(), "join 后立即发首个心跳(op=2)");
        assert_eq!(&got[2][8..12], &2u32.to_be_bytes(), "到期后补发心跳(op=2)");
        let _ = items.lock().expect("items").len();
    }
}
