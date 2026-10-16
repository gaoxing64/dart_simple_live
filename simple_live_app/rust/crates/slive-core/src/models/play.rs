//! 清晰度 / 播放地址（对照 Dart `live_play_quality.dart` / `live_play_url.dart`）。

use std::collections::HashMap;

/// 清晰度项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LivePlayQuality {
    /// 清晰度描述（如 `原画`；无法映射为 `未知清晰度`）。
    pub quality: String,
    /// 清晰度数据（B站为 `qn` 十进制字符串，消费时解析回整型；§3.3(d)）。
    pub data: String,
    /// 排序位。
    pub sort: i32,
}

/// 播放地址。
///
/// `renewers`（直链续流）按 O-7 排除（仅斗鱼需要，B站无此语义）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LivePlayUrl {
    /// 播放地址列表（含 `mcdn` 的排在最后）。
    pub urls: Vec<String>,
    /// 请求头。
    pub headers: Option<HashMap<String, String>>,
}
