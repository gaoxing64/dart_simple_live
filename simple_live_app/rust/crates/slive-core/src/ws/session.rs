//! 弹幕会话骨架：**时间源与事件源均可注入**（seam）。
//!
//! 本批次只落地注入点（traits + 注入式构造），供 IP-2 的 F-11（握手/心跳/重连）复用：
//! - [`FrameSource`]：帧事件源（生产为 ws 连接；测试为 [`crate::testing::ScriptedFrameSource`]）；
//! - [`TimeSource`]：时间源（生产 [`crate::time::SystemClock`]；测试 [`crate::testing::FakeTime`]），
//!   心跳到期时间据此计算，重连时序可被确定性断言而不依赖墙钟。

use std::sync::Arc;

use async_trait::async_trait;

use crate::error::SliveError;
use crate::time::TimeSource;

/// WS 帧事件源抽象（事件源 seam）。`None` 表示连接结束。
#[async_trait]
pub trait FrameSource: Send + Sync {
    /// 取下一条原始帧。
    async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>>;

    /// 发送一帧（join / 心跳）。失败即连接不可用，由会话转入重连。
    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError>;
}

/// 心跳 / 重连调参（对齐 Dart core：心跳 60s、重连间隔 5s、最多 5 次）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SessionTuning {
    /// 心跳间隔（秒）。
    pub heartbeat_secs: u64,
    /// 重连间隔（秒）。
    pub reconnect_delay_secs: u64,
    /// 最大重连次数。
    pub max_reconnect: u32,
}

impl SessionTuning {
    /// B站默认调参。
    pub const fn bilibili() -> Self {
        Self {
            heartbeat_secs: 60,
            reconnect_delay_secs: 5,
            max_reconnect: 5,
        }
    }
}

impl Default for SessionTuning {
    fn default() -> Self {
        Self::bilibili()
    }
}

/// 弹幕会话骨架：持有注入的时间源与事件源。
///
/// 说明：本批次仅提供**注入点与帧拉取/心跳调度**；完整连接、心跳发送与 `5s×5` 重连循环
/// 在 IP-2（F-11）基于这些依赖实现。
pub struct WsSession {
    time: Arc<dyn TimeSource>,
    source: Box<dyn FrameSource>,
    tuning: SessionTuning,
}

impl WsSession {
    /// 使用 B站默认调参构造。
    pub fn new(time: Arc<dyn TimeSource>, source: Box<dyn FrameSource>) -> Self {
        Self::with_tuning(time, source, SessionTuning::bilibili())
    }

    /// 显式指定调参构造。
    pub fn with_tuning(
        time: Arc<dyn TimeSource>,
        source: Box<dyn FrameSource>,
        tuning: SessionTuning,
    ) -> Self {
        Self {
            time,
            source,
            tuning,
        }
    }

    /// 当前调参。
    pub fn tuning(&self) -> SessionTuning {
        self.tuning
    }

    /// 当前时间（来自注入的时间源）。
    pub fn now_secs(&self) -> u64 {
        self.time.unix_secs()
    }

    /// 下一次心跳的到期时间（基于注入时间源）。
    pub fn next_heartbeat_at(&self, last_sent_secs: u64) -> u64 {
        last_sent_secs + self.tuning.heartbeat_secs
    }

    /// 距上次心跳是否已到期。
    pub fn heartbeat_due(&self, last_sent_secs: u64) -> bool {
        self.now_secs() >= self.next_heartbeat_at(last_sent_secs)
    }

    /// 取下一条帧（委托注入的事件源）。
    pub async fn recv(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
        self.source.next_frame().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeTime, ScriptedFrameSource};

    #[tokio::test]
    async fn session_uses_injected_time_and_source() {
        let time = Arc::new(FakeTime::new(1_700_000_000));
        let mut source = ScriptedFrameSource::new(vec![vec![1, 2, 3]]);
        source.push_error("boom");
        let mut session = WsSession::new(time.clone(), Box::new(source));

        assert_eq!(session.now_secs(), 1_700_000_000);
        assert!(!session.heartbeat_due(1_700_000_000), "刚发过心跳不应到期");
        time.advance(60);
        assert!(session.heartbeat_due(1_700_000_000), "前进 60s 后应到期");
        assert_eq!(session.next_heartbeat_at(0), 60);

        assert_eq!(session.recv().await.expect("首帧").expect("首帧 ok"), vec![1, 2, 3]);
        assert!(matches!(
            session.recv().await.expect("次帧"),
            Err(SliveError::Websocket(_))
        ));
        assert!(session.recv().await.is_none(), "帧用尽应为 None");
    }
}
