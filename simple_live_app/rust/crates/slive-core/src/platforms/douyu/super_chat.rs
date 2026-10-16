//! F-10 房间 SC 列表（对照 `douyu_site.dart:354-358`）。
//!
//! 斗鱼 HTTP 侧**没有** SC 列表接口 —— Dart core 的实现直接 `return []` 并注释「尚不支持」。
//! 本模块照实返回空列表：**不编造接口**。斗鱼的醒目留言只从弹幕流里实时解析
//! （`comm_chatmsg` / `voice_trlt`，见 `danmaku/parse.rs`）。

use crate::error::SliveError;
use crate::models::LiveSuperChatMessage;

/// 恒返回空列表（Dart core 现状）。
pub(crate) async fn fetch() -> Result<Vec<LiveSuperChatMessage>, SliveError> {
    Ok(Vec::new())
}

#[tokio::test]
async fn douyu_has_no_http_super_chat_list() {
    assert!(
        fetch().await.expect("恒成功").is_empty(),
        "斗鱼 HTTP 侧不提供 SC 列表，必须返回空列表而不是报错"
    );
}