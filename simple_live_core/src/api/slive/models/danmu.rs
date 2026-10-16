//! 弹幕流条目镜像。

pub use slive_core::models::{LiveDanmuControlEvent, LiveDanmuItem};

#[flutter_rust_bridge::frb(mirror(LiveDanmuControlEvent))]
pub enum _LiveDanmuControlEvent {
    Ready,
    Reconnecting { attempt: u32 },
    Closed(String),
}

#[flutter_rust_bridge::frb(mirror(LiveDanmuItem))]
pub enum _LiveDanmuItem {
    Message(Box<crate::api::slive::models::LiveMessage>),
    Control(LiveDanmuControlEvent),
}
