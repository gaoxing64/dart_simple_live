//! 签名用时钟（可注入 seam）。
//!
//! # 为什么不用 `crate::time::TimeSource`
//! core 的 [`crate::time::TimeSource`] 是**秒**粒度（服务B站 `wbi` 的 `wts`），
//! 而 a_bogus 需要**毫秒**（Dart `DateTime.now().millisecondsSinceEpoch`）。
//! 两者精度需求不同，故签名层自带毫秒时钟，避免改动 core 公共 trait 影响存量模块。

/// 毫秒时间源（签名专用seam）。
///
/// 抽象成 trait 的目的：golden 断言必须能在**固定时间**下复现
/// （Dart 侧 `DateTime.now()` 不可注入，是迁移中唯一无法直接对齐的点）。
pub trait SignatureClock: Send + Sync {
    /// Unix 毫秒时间戳。
    fn unix_millis(&self) -> u64;
}

/// 生产时钟：系统墙钟（毫秒）。
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemClock;

impl SignatureClock for SystemClock {
    fn unix_millis(&self) -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}

/// 固定时钟（测试 / golden 用）。
#[derive(Debug, Clone, Copy)]
pub struct FixedClock {
    millis: u64,
}

impl FixedClock {
    /// 固定为某一毫秒时间戳。
    #[must_use]
    pub const fn new(millis: u64) -> Self {
        Self { millis }
    }
}

impl SignatureClock for FixedClock {
    fn unix_millis(&self) -> u64 {
        self.millis
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_clock_is_after_2020_in_millis() {
        assert!(
            SystemClock.unix_millis() > 1_577_836_800_000,
            "系统时钟应晚于 2020（毫秒）"
        );
    }

    #[test]
    fn fixed_clock_always_returns_same_millis() {
        let c = FixedClock::new(1_700_000_000_123);
        assert_eq!(c.unix_millis(), 1_700_000_000_123);
        assert_eq!(c.unix_millis(), 1_700_000_000_123);
    }

    #[test]
    fn fixed_clock_accepts_zero() {
        assert_eq!(FixedClock::new(0).unix_millis(), 0);
    }
}