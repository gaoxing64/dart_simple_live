//! 虎牙弹幕链路：参数契约 + WS 帧 + TARS 消息 + 会话主循环 + `LiveMessage` 映射。
//!
//! 分层（依赖只向下）：
//! - [`args`]：弹幕参数 JSON 契约（`LiveRoomDetail.danmaku_data`）；
//! - [`tars_msgs`] / [`tars_cdn`] / [`tars_sc`]：TARS 消息定义（**纯结构，无 IO**）；
//! - [`frames`]：WS 帧编解码（**纯函数，无 IO**）；
//! - [`emoticon`]：表情包表与提取（纯函数）；
//! - [`mod`]（本文件）：会话编排（连接工厂注入 + 帧循环 + 消息映射）。
//!
//! 会话语义**复用** [`crate::ws::runner::run_session`] 的约定（心跳 60s / 重连 5s×5 /
//! 收到消息后计数归零），但由于虎牙的 join 帧、心跳帧与解码器都不同，
//! 主循环在本文件内实现（`run_session` 硬编码 B站的 args 与编解码，不复用其函数体）。
//! 连接工厂（`FrameSource`）由桥层注入 —— 核心 crate 不持有真实 WS 连接（ADR-001）。

pub mod args;
pub mod bare;
pub mod emoticon;
pub mod frames;
pub mod super_chat_map;
pub mod tars_cdn;
pub mod tars_msgs;
pub mod tars_ws_v2;
pub mod tars_sc;

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use crate::error::SliveError;
use crate::models::{LiveDanmuControlEvent, LiveDanmuItem, LiveMessage, LiveMessageColor, LiveMessageData, LiveMessageType};
use crate::time::TimeSource;
use crate::ws::{FrameSource, SessionTuning};

pub use args::{HuyaDanmakuArgs, DEFAULT_DEVICE, DEFAULT_GUID, HUYA_DANMAKU_ARGS_SCHEMA_VERSION};


/// 连接工厂：每次（重）连创建新的帧事件源（与 B站 runner 同签名形态）。
pub type ConnectFactory = Box<
    dyn FnMut()
        -> Pin<Box<dyn Future<Output = Result<Box<dyn FrameSource>, SliveError>> + Send>>
        + Send,
>;

/// 醒目留言事件的拉取钩子。
///
/// 虎牙的 SC 不随弹幕下发：收到 V2 `iUri=2001317` 事件时（2026-10-17 上游同步：
/// 旧「文案含 `(来自 xx 上头条)`」文本路径已弃用，见 dev 97413c60）
/// 才去拉一次列表（对齐 Dart `callSc`）。core 不直接发 HTTP，故由调用方注入。
/// `pub`：桥层（FRB）注入生产实现时会用到本类型名。
pub type SuperChatFetcher = Arc<dyn Fn(i64) -> Vec<crate::models::LiveSuperChatMessage> + Send + Sync>;

/// 会话主循环。`on_item` 依次收到 `Ready` / `Message` / `Reconnecting` / `Closed`。
///
/// 时序（与 Dart `HuyaDanmaku` + `WebScoketUtils` 一致）：
/// - Ready 后立即发 join（注册 `live:{topSid}` 与 `chat:{topSid}`）；
/// - **join 后立即发首个心跳**（对齐 B站真机修复：服务端收到首个心跳才开始推送）；
/// - 心跳 60s（注入时间源判定）；断线重连 `5s × 5`，**收到消息后计数归零**。
pub async fn run_session(
    args: HuyaDanmakuArgs,
    mut connect: ConnectFactory,
    time: Arc<dyn TimeSource>,
    tuning: SessionTuning,
    mut stop: tokio::sync::watch::Receiver<bool>,
    fetch_super_chat: Option<SuperChatFetcher>,
    mut on_item: impl FnMut(LiveDanmuItem) + Send,
) {
    let join_frame = match frames::build_join_frame(&args.group_ids()) {
        Ok(frame) => frame,
        Err(e) => {
            eprintln!("[huya-danmaku] join 帧构造失败: {e}");
            on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
                format!("join 帧构造失败: {e}"),
            )));
            return;
        }
    };
    let heartbeat_frame = match frames::build_heartbeat_frame() {
        Ok(frame) => frame,
        Err(e) => {
            eprintln!("[huya-danmaku] 心跳帧构造失败: {e}");
            on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(
                format!("心跳帧构造失败: {e}"),
            )));
            return;
        }
    };

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
                eprintln!("[huya-danmaku] 连接失败: {e}");
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            }
        };
        on_item(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready));
        if let Err(e) = source.send(join_frame.clone()).await {
            eprintln!("[huya-danmaku] join 发送失败: {e}");
            if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                return;
            }
            continue 'session;
        }
        let mut last_heartbeat = time.unix_secs();
        if source.send(heartbeat_frame.clone()).await.is_ok() {
            last_heartbeat = time.unix_secs();
        }

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
                    Some(Err(e)) => eprintln!("[huya-danmaku] 帧错误: {e}"),
                    _ => eprintln!("[huya-danmaku] 服务端关闭连接"),
                }
                if reconnect_or_close(&mut attempt, &tuning, time.as_ref(), &mut on_item).await {
                    return;
                }
                continue 'session;
            };
            // 收到消息 -> 重连计数归零
            attempt = 0;
            if time.unix_secs() >= last_heartbeat + tuning.heartbeat_secs
                && source.send(heartbeat_frame.clone()).await.is_ok()
            {
                last_heartbeat = time.unix_secs();
            }
            let decoded = decode_to_items(&frame, &args, args.top_sid);
            for item in decoded.items {
                on_item(item);
            }
            if decoded.super_chat_triggered {
                for item in super_chat_map::super_chat_items(args.top_sid, fetch_super_chat.as_ref()) {
                    on_item(item);
                }
            }
        }
    }
}

/// 重连或关闭（与 B站 runner 同语义）。
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

/// 一帧解码的产出：业务消息 + 是否需要拉取醒目留言。
#[derive(Debug, Default)]
pub struct DecodedFrame {
    /// 业务消息（0..N 条）。
    pub items: Vec<LiveDanmuItem>,
    /// 命中醒目留言信号（V2 `iUri=2001317`；文本路径已弃用，2026-10-17 上游同步）。
    pub super_chat_triggered: bool,
}

/// 解码一帧并映射为消息（0..N 条）。
///
/// 映射口径（对齐 Dart `decodeMessage` / `callSc`）：
/// - 聊天 -> `LiveMessageType::Chat`，颜色 `font_color <= 0` 归白色；
/// - 人气 -> `LiveMessageType::Online`（`data = Online(online)`）；
/// - 醒目留言事件（V2 `iUri=2001317`）-> **只置触发位，不产消息**
///   （Dart `huya_danmaku.dart` @97413c60 只调 `callSc()`；SC 内容由会话循环
///   经 `SuperChatFetcher` 另行拉取，QA 夹具的 `expected.messages` 亦为空）；
/// - 脏帧 -> 空序列（不中断会话）。
pub fn decode_to_items(
    frame: &[u8],
    _args: &HuyaDanmakuArgs,
    _top_sid: i64,
) -> DecodedFrame {
    match frames::decode_frame(frame) {
        frames::HuyaFrame::Chat {
            user_name,
            content,
            font_color,
        } => {
            // 文本正则触发已随上游弃用（SlotSun dev 97413c60「listen real uri」，
            // 2026-10-17 同步）：旧 `(来自 xx 上头条)` 文案匹配是临时方案，改由
            // V2 真实 uri（`URI_SUPER_CHAT = 2001317`）唯一触发，避免误触发/漏触发。
            // `super_chat_map::mentions_super_chat` 保留以备回退，但不再参与判定。
            DecodedFrame {
                items: vec![LiveDanmuItem::Message(Box::new(LiveMessage {
                    message_type: LiveMessageType::Chat,
                    user_name,
                    user_id: None,
                    message: content.clone(),
                    data: None,
                    color: if font_color <= 0 {
                        LiveMessageColor::white()
                    } else {
                        LiveMessageColor::number_to_color(font_color as i32)
                    },
                    emoticons: emoticon::extract_emoticons(&content),
                }))],
                super_chat_triggered: false,
            }
        }
        frames::HuyaFrame::Online { online } => DecodedFrame {
            items: vec![LiveDanmuItem::Message(Box::new(LiveMessage {
                message_type: LiveMessageType::Online,
                user_name: String::new(),
                user_id: None,
                message: String::new(),
                data: Some(LiveMessageData::Online(online as i32)),
                color: LiveMessageColor::white(),
                emoticons: None,
            }))],
            super_chat_triggered: false,
        },
        frames::HuyaFrame::SuperChatEvent => DecodedFrame {
            items: Vec::new(),
            super_chat_triggered: true,
        },
        frames::HuyaFrame::Ignored | frames::HuyaFrame::Malformed(_) => DecodedFrame::default(),
    }
}

