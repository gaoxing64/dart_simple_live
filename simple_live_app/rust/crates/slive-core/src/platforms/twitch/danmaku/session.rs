//! Twitch 弹幕会话主循环（IRC over WebSocket）。
//!
//! 与 B站 `ws/runner.rs` 的 `run_session` **同构**（同样的事件序列、心跳判定、重连策略、
//! `stop` 语义），差别只在帧内容：B站是二进制包，Twitch 是 IRC 文本行。
//! 共享的 `run_session` 签名硬绑 `BiliBiliDanmakuArgs` + 二进制解码，故此处按同一范式
//! 在 Twitch 模块内实现（**不改共享 `runner.rs`** —— 多平台并行期共享文件由总监接线）。
//!
//! 时序（对照 `twitch_danmaku.dart` + `WebScoketUtils`）：
//! - 连接成功 -> `Ready` -> 立即发握手 5 帧（CAP REQ/PASS/NICK/USER/JOIN）；
//! - 收到 PING -> 立即回 PONG（不等心跳周期）；
//! - 心跳 40s（Dart `heartbeatTime = 40 * 1000`，发 `PONG :tmi.twitch.tv`）；
//! - 断线重连 `5s × 5` 次，**收到消息后计数归零**（与 Dart `reconnectTime = 0` 一致）；
//! - 超过最大次数 -> `Closed`（不再重试）；`stop` -> `Closed("已手动停止")`。
//!
//! 帧为 UTF-8 文本（IRC over WS 用 WebSocket Text 帧）；非法 UTF-8 按替换字符处理，
//! **不因单条脏帧中断会话**。

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use crate::error::SliveError;
use crate::models::{LiveDanmuControlEvent, LiveDanmuItem};
use crate::time::TimeSource;
use crate::ws::session::{FrameSource, SessionTuning};
use crate::ws::ConnectFactory;

use super::args::TwitchDanmakuArgs;
use super::parse::parse_frame;

/// 心跳间隔（秒）：对齐 Dart `heartbeatTime = 40 * 1000`。
pub const TWITCH_HEARTBEAT_SECS: u64 = 40;
/// 重连间隔（秒）：对齐 `WebScoketUtils.reconnect` 的 `Duration(seconds: 5)`。
pub const TWITCH_RECONNECT_DELAY_SECS: u64 = 5;
/// 最大重连次数：对齐 `maxReconnectTime = 5`。
pub const TWITCH_MAX_RECONNECT: u32 = 5;

/// Twitch 会话调参（心跳 40s，其余与 B站一致）。
pub const fn tuning() -> SessionTuning {
    SessionTuning {
        heartbeat_secs: TWITCH_HEARTBEAT_SECS,
        reconnect_delay_secs: TWITCH_RECONNECT_DELAY_SECS,
        max_reconnect: TWITCH_MAX_RECONNECT,
    }
}

/// Twitch 会话主循环。`on_item` 依次收到 `Ready` / `Message` / `Reconnecting` / `Closed`。
///
/// 心跳在**每帧处理后**检查到期（与 B站同口径；长静默场景的定时兜底由桥层连接负责）。
/// `stop` 置 `true` 即手动停止：发出 `Closed("已手动停止")` 后返回，不再重连。
pub async fn run_session(
    args: TwitchDanmakuArgs,
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
                eprintln!("[twitch-danmaku] connect failed: {e}");
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
        };
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready));

        let nick = TwitchDanmakuArgs::anonymous_nick(time.unix_secs());
        for frame in args.handshake(&nick) {
            if source.send(frame.into_bytes()).await.is_err() {
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
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
                    Some(Err(e)) => eprintln!("[twitch-danmaku] frame error: {e}"),
                    _ => eprintln!("[twitch-danmaku] connection closed by server"),
                }
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            };
            // 收到消息 -> 重连计数归零（对齐 `WebScoketUtils.receiveMessage`）
            attempt = 0;

            if time.unix_secs() >= last_heartbeat + tuning.heartbeat_secs
                && source
                    .send(TwitchDanmakuArgs::heartbeat_frame().into_bytes())
                    .await
                    .is_ok()
            {
                last_heartbeat = time.unix_secs();
            }

            let text = String::from_utf8_lossy(&frame);
            let parsed = parse_frame(&text);
            for reply in parsed.replies {
                if source.send(reply.into_bytes()).await.is_err() {
                    break;
                }
            }
            for message in parsed.messages {
                on_item(LiveDanmuItem::Message(Box::new(message)));
            }
        }
    }
}

/// 重连或关闭：`attempt + 1`，超限 -> `Closed` 并返回 `true`；否则 `Reconnecting` + 等待。
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

/// 便于外部（桥层）构造连接工厂的类型别名（语义与 `ws::ConnectFactory` 相同）。
pub type TwitchConnectFactory = Box<
    dyn FnMut()
        -> Pin<Box<dyn Future<Output = Result<Box<dyn FrameSource>, SliveError>> + Send>>
        + Send,
>;

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
