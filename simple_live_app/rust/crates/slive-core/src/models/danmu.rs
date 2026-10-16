//! 弹幕流条目模型（对照上游 `slive_core` 的 `LiveDanmuItem` / `LiveDanmuControlEvent`）。

use crate::models::LiveMessage;

/// 连接生命周期控制事件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveDanmuControlEvent {
    /// 连接就绪（join 包已发出）。
    Ready,
    /// 正在第 `attempt` 次重连。
    Reconnecting { attempt: u32 },
    /// 已关闭（重连超过最大次数，不再重试）。
    Closed(String),
}

/// 弹幕流条目：业务消息或控制事件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveDanmuItem {
    /// 业务消息（聊天 / 人气 / 醒目留言）。
    Message(Box<LiveMessage>),
    /// 连接控制事件。
    Control(LiveDanmuControlEvent),
}
