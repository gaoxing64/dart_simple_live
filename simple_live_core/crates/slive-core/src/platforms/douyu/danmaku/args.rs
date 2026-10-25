//! 斗鱼弹幕连接参数（对照 `douyu_site.dart:233`：`danmakuData = room_id`）。
//!
//! 与 B站不同：斗鱼弹幕**只需房间号**（登录包 `loginreq` 带 roomid 即可），
//! 不存在 token / server_host / buvid。因此 `danmakuData` 是**裸房间号字符串**，
//! 不是 JSON —— App 侧 `liveDanmaku.start(detail.danmakuData)` 原样透传即可
//! （绑定层不解析，与 J-10 的口径一致：解析责任在 Rust 侧，非法值报错）。
//!
//! 传输：全平台统一走**明文 TCP**（ADR-015）。斗鱼弹幕代理对非系统 TLS 栈的
//! ClientHello 做风控（rustls 握手被服务端 `HandshakeFailure`），WSS 在移动端不可用；
//! 8601 与 WSS 使用完全相同的 STT 帧格式，且不需要任何握手头。

use crate::error::SliveError;

/// 斗鱼弹幕服务地址（`tcp://` scheme 由装配层解析）。
pub const DANMAKU_TCP_URL: &str = "tcp://danmuproxy.douyu.com:8601/";
/// 默认心跳间隔（秒）—— 对齐 Dart `heartbeatTime = 45 * 1000`。
pub const HEARTBEAT_SECS: u64 = 45;
/// 重连间隔（秒）—— 对齐 `WebScoketUtils` 的 5s。
pub const RECONNECT_DELAY_SECS: u64 = 5;
/// 最大重连次数 —— 对齐 `maxReconnectTime = 5`。
pub const MAX_RECONNECT: u32 = 5;

/// 斗鱼弹幕连接参数（房间号 -> 可连接）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DouyuDanmakuArgs {
    /// 房间号。
    pub room_id: String,
}

impl DouyuDanmakuArgs {
    /// 构造（房间号去空白；空串视为非法）。
    pub fn new(room_id: &str) -> Result<Self, SliveError> {
        let room_id = room_id.trim();
        if room_id.is_empty() {
            return Err(SliveError::invalid_input("斗鱼弹幕房间号为空"));
        }
        Ok(Self {
            room_id: room_id.to_string(),
        })
    }

    /// 弹幕连接地址（`tcp://host:port/`）。
    pub fn connect_url(&self) -> String {
        DANMAKU_TCP_URL.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn room_id_is_trimmed_and_validated() {
        let args = DouyuDanmakuArgs::new(" 999 ").expect("合法房间号");
        assert_eq!(args.room_id, "999");
        assert!(DouyuDanmakuArgs::new("   ").is_err(), "空房间号必须报错");
        assert!(DouyuDanmakuArgs::new("").is_err());
    }

    #[test]
    fn connect_url_is_douyu_tcp() {
        let args = DouyuDanmakuArgs::new("999").expect("合法");
        assert_eq!(args.connect_url(), "tcp://danmuproxy.douyu.com:8601/");
    }

    #[test]
    fn tuning_constants_match_dart() {
        assert_eq!(HEARTBEAT_SECS, 45, "Dart heartbeatTime = 45s");
        assert_eq!(RECONNECT_DELAY_SECS, 5);
        assert_eq!(MAX_RECONNECT, 5);
    }
}
