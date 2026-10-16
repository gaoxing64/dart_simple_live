//! 可注入时间源（seam）。
//!
//! wbi 签名的 `wts`、ws 心跳与重连等待均通过 [`TimeSource`] 取得，
//! 使 golden（固定 `wts` -> 固定 `w_rid`）与重连时序可被确定性断言（AC-21 / AC-26 前置）。
//! `sleep` 是**可注入的等待**：生产实现真等，测试实现立即返回（时序靠断言计数而非墙钟）。

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;

/// 时间源抽象。
#[async_trait]
pub trait TimeSource: Send + Sync {
    /// 当前 Unix 时间戳（秒）。
    fn unix_secs(&self) -> u64;

    /// 等待若干秒。生产实现真实睡眠；测试实现立即返回（AC-26 抗 flaky）。
    async fn sleep(&self, secs: u64);
}

/// 生产实现：系统时钟（真实睡眠）。
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemClock;

#[async_trait]
impl TimeSource for SystemClock {
    fn unix_secs(&self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    async fn sleep(&self, secs: u64) {
        tokio::time::sleep(Duration::from_secs(secs)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_clock_is_after_2020() {
        let secs = SystemClock.unix_secs();
        assert!(secs > 1_577_836_800, "系统时钟应晚于 2020，实际 {secs}");
    }

    #[tokio::test]
    async fn system_clock_sleep_completes() {
        SystemClock.sleep(0).await;
    }
}
