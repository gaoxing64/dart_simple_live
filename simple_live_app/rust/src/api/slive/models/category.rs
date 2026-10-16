//! 分类模型镜像。

pub use slive_core::models::{LiveCategory, LiveSubCategory};

#[flutter_rust_bridge::frb(mirror(LiveCategory))]
pub struct _LiveCategory {
    pub name: String,
    pub id: String,
    pub children: Vec<LiveSubCategory>,
}

#[flutter_rust_bridge::frb(mirror(LiveSubCategory))]
pub struct _LiveSubCategory {
    pub name: String,
    pub pic: Option<String>,
    pub id: String,
    pub parent_id: String,
}
