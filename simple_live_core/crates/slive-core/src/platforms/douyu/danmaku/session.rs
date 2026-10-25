//! 斗鱼弹幕会话主循环（对照 `WebScoketUtils` + `douyu_danmaku.dart:25-65`）。
//!
//! 与 B站 `ws::runner::run_session` 的差异（**不复用共享 runner，避免污染 B站行为**）：
//! - join 是**两个包**：`loginreq`（登录）-> `joingroup`（进组）；
//! - 心跳包是 `type@=mrkl/`，间隔 **45s**（B站 60s、B站心跳 op=2）；
//! - join 后**不**立即发首心跳（斗鱼服务端不需要，与 B站真机结论相反）。
//!
//! 时序（对齐 Dart `WebScoketUtils`）：
//! - 心跳 45s（帧间检查，时间取自注入的 [`TimeSource`]）；
//! - 断线重连 `5s × 5` 次，**收到消息后计数归零**；
//! - 超过最大次数 -> `Closed`（不再重试）。

use std::sync::Arc;

use crate::models::{LiveDanmuControlEvent, LiveDanmuItem};
use crate::time::TimeSource;
use crate::ws::{ConnectFactory, FrameSource, SessionTuning};

/// 会话内使用的帧事件源类型别名（便于文档引用；生产实现由桥层注入）。
pub type DouyuFrameSource = Box<dyn FrameSource>;

use super::args::{
    DouyuDanmakuArgs, HEARTBEAT_SECS, MAX_RECONNECT, RECONNECT_DELAY_SECS,
};
use super::parse::decode_frame;
use super::protocol::{heartbeat_payload, join_payload, login_payload, serialize};

/// 斗鱼默认调参（45s 心跳 / 5s 重连 / 5 次）。
pub fn douyu_tuning() -> SessionTuning {
    SessionTuning {
        heartbeat_secs: HEARTBEAT_SECS,
        reconnect_delay_secs: RECONNECT_DELAY_SECS,
        max_reconnect: MAX_RECONNECT,
    }
}

/// 进组序列：登录包 + 进组包（对齐 `joinRoom`）。
pub fn join_frames(args: &DouyuDanmakuArgs) -> Vec<Vec<u8>> {
    vec![
        serialize(&login_payload(&args.room_id)),
        serialize(&join_payload(&args.room_id)),
    ]
}

/// 心跳帧。
pub fn heartbeat_frame() -> Vec<u8> {
    serialize(&heartbeat_payload())
}

/// 会话主循环。`on_item` 依次收到 `Ready` / `Message` / `Reconnecting` / `Closed`。
///
/// `stop` 置 `true` 即手动停止：发出 `Closed("已手动停止")` 后返回，不再重连。
/// 发送端全部 drop（连接句柄释放）同样视为停止（否则 `changed()` 会热循环返回 Err）。
pub async fn run_session(
    args: DouyuDanmakuArgs,
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
            Ok(s) => s,
            Err(e) => {
                eprintln!("[douyu-danmaku] connect failed: {e}");
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
        };

        // 登录 + 进组（任一失败即视为连接不可用）
        let mut joined = true;
        for frame in join_frames(&args) {
            if let Err(e) = source.send(frame).await {
                eprintln!("[douyu-danmaku] join send failed: {e}");
                joined = false;
                break;
            }
        }
        if !joined {
            if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                return;
            }
            continue 'session;
        }
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready));

        let mut last_heartbeat = time.unix_secs();
        loop {
            let frame = tokio::select! {
                biased;
                f = source.next_frame() => f,
                r = stop.changed() => {
                    // `Err` = 发送端全部 drop（弹幕连接句柄已释放）：会话随句柄一起结束，
                    // 否则这里会变成「changed() 立即返回 Err」的热循环。
                    // `Ok(false)` 理论上不会出现（只有「置 true」一个写端），按误唤醒继续等帧。
                    if r.is_err() || *stop.borrow_and_update() {
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
                    Some(Err(e)) => eprintln!("[douyu-danmaku] frame error: {e}"),
                    _ => eprintln!("[douyu-danmaku] connection closed by server"),
                }
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            };
            // 收到消息 -> 重连计数归零
            attempt = 0;
            if time.unix_secs() >= last_heartbeat + tuning.heartbeat_secs
                && source.send(heartbeat_frame()).await.is_ok()
            {
                last_heartbeat = time.unix_secs();
            }
            for message in decode_frame(&frame) {
                on_item(LiveDanmuItem::Message(Box::new(message)));
            }
        }
    }
}

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
    use super::super::protocol::deserialize;
    use super::*;
    use crate::error::SliveError;
    use crate::models::LiveMessageType;
    use crate::testing::{FakeTime, ScriptedFrameSource};
    use std::collections::VecDeque;
    use std::sync::Mutex as StdMutex;

    fn args() -> DouyuDanmakuArgs {
        DouyuDanmakuArgs::new("999").expect("合法房间号")
    }

    fn collector() -> (
        Arc<StdMutex<Vec<LiveDanmuItem>>>,
        impl FnMut(LiveDanmuItem) + Send,
    ) {
        let items: Arc<StdMutex<Vec<LiveDanmuItem>>> = Arc::new(StdMutex::new(Vec::new()));
        let sink = Arc::clone(&items);
        (items, move |item| sink.lock().expect("sink").push(item))
    }

    fn chat_frame() -> Vec<u8> {
        serialize("type@=chatmsg/nn@=观众/txt@=你好/col@=1/if@=1/")
    }

    #[test]
    fn join_sends_login_then_joingroup() {
        let frames = join_frames(&args());
        assert_eq!(frames.len(), 2, "斗鱼需要登录包 + 进组包两个");
        let login = deserialize(&frames[0]).expect("登录包可解包");
        let join = deserialize(&frames[1]).expect("进组包可解包");
        assert_eq!(login, "type@=loginreq/roomid@=999/");
        assert_eq!(join, "type@=joingroup/rid@=999/gid@=-9999/");
    }

    #[test]
    fn heartbeat_frame_is_mrkl() {
        assert_eq!(
            deserialize(&heartbeat_frame()).as_deref(),
            Some("type@=mrkl/")
        );
    }

    #[tokio::test]
    async fn session_emits_ready_then_messages() {
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(ScriptedFrameSource::new(vec![chat_frame()])));
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
            douyu_tuning(),
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
            matches!(&got[1], LiveDanmuItem::Message(m) if m.message_type == LiveMessageType::Chat),
            "chatmsg 应产出聊天消息"
        );
    }

    #[tokio::test]
    async fn reconnect_five_times_then_closed() {
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(ScriptedFrameSource::new(vec![chat_frame()])));
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
            douyu_tuning(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        let reconnects = got
            .iter()
            .filter(|i| {
                matches!(
                    i,
                    LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })
                )
            })
            .count();
        assert_eq!(reconnects, 5, "最多 5 次重连（5s x 5）");
        assert!(matches!(
            got.last(),
            Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_)))
        ));
    }

    #[tokio::test]
    async fn stop_before_start_closes_without_reconnect() {
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(ScriptedFrameSource::new(vec![chat_frame()])));
        let connect: ConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        // 手动停止信号在会话开始前就已置位
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(true);
        run_session(
            args(),
            connect,
            Arc::new(FakeTime::new(0)),
            douyu_tuning(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        assert_eq!(got.len(), 1, "已停止时不得再连接或发包");
        assert!(
            matches!(&got[0], LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(msg)) if msg == "已手动停止"),
            "实际 {:?}",
            got.first()
        );
    }
}