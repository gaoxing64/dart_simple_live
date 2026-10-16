//! 清晰度 / 播放地址模型镜像。

pub use slive_core::models::{LivePlayQuality, LivePlayUrl};

#[flutter_rust_bridge::frb(mirror(LivePlayQuality))]
pub struct _LivePlayQuality {
    pub quality: String,
    pub data: String,
    pub sort: i32,
}

#[flutter_rust_bridge::frb(mirror(LivePlayUrl))]
pub struct _LivePlayUrl {
    pub urls: Vec<String>,
    pub headers: Option<std::collections::HashMap<String, String>>,
}
