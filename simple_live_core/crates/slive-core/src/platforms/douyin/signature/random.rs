//! 签名用随机源（可注入 seam）。
//!
//! # 为什么不用 `rand` crate
//! `slive-core/Cargo.toml` **不含** `rand`，且本任务禁止改`Cargo.toml`。
//! 这里用 xorshift64*（`SplitMix64` 风格的乘子）自实现，
//! 播种源为墙钟纳秒 + 栈变量地址混合 —— 满足「同进程内不同实例不同序列」即可，
//! 签名场景**不要求密码学强度**（Dart侧同样是 `Random()`，非`Random.secure()`）。

use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

/// 随机源（签名专用 seam）。
///
/// Dart 侧 a_bogus 用 `Random().nextInt(10000)`（3 次），
/// x_bogus 用 `Random.secure().nextInt(256)` / `nextInt(255)`（各 1 次）。
/// 抽象成 trait 后，golden 测试可注入固定序列使输出可复现。
pub trait RandomSource: Send + Sync {
    /// 返回下一个 `[0, 10000)` 的随机整数（对齐 Dart `Random().nextInt(10000)`）。
    fn next_below_10000(&self) -> u32;
}

/// 生产随机源：xorshift64*，墙钟纳秒 + 栈地址播种。
#[derive(Debug)]
pub struct SystemRandom {
    state: AtomicU64,
}

impl Default for SystemRandom {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemRandom {
    /// 以墙钟纳秒与栈变量地址混合播种。
    #[must_use]
    pub fn new() -> Self {
        // 取栈上变量的地址引入 ASLR 熵，避免同纳秒内多次构造得到相同序列。
        let stack_marker = 0u8;
        let addr = &stack_marker as *const u8 as u64;
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9E37_79B9_7F4A_7C15);
        let mixed = nanos ^ addr.rotate_left(17) ^ 0x2545_F491_4F6C_DD1D;
        let seed = if mixed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            mixed
        };
        Self {
            state: AtomicU64::new(seed),
        }
    }

    fn next_u64(&self) -> u64 {
        let mut x = self.state.load(Ordering::Relaxed);
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state.store(x, Ordering::Relaxed);
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
}

impl RandomSource for SystemRandom {
    fn next_below_10000(&self) -> u32 {
        // 取高 33 位再取模，避免低位线性相关性。
        ((self.next_u64() >> 33) % 10_000) as u32
    }
}

/// 固定序列随机源（测试 / golden 用）：按序循环返回 `values`。
#[derive(Debug)]
pub struct FixedRandom {
    values: Vec<u32>,
    cursor: Mutex<usize>,
}

impl FixedRandom {
    /// 由固定序列构造。`values` 为空会 panic（无法提供随机源）。
    #[must_use]
    pub fn new(values: Vec<u32>) -> Self {
        assert!(!values.is_empty(), "固定随机源至少要有 1 个值");
        Self {
            values,
            cursor: Mutex::new(0),
        }
    }
}

impl RandomSource for FixedRandom {
    fn next_below_10000(&self) -> u32 {
        let mut cur = self.cursor.lock().expect("FixedRandom cursor 锁中毒");
        let v = self.values[*cur % self.values.len()] % 10_000;
        *cur += 1;
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn system_random_stays_in_range() {
        let r = SystemRandom::new();
        for _ in 0..256 {
            assert!(r.next_below_10000() < 10_000);
        }
    }

    #[test]
    fn system_random_varies() {
        let r = SystemRandom::new();
        let set: HashSet<u32> = (0..64).map(|_| r.next_below_10000()).collect();
        assert!(set.len() > 32, "连续取值应几乎不重复，实际 {}", set.len());
    }

    #[test]
    fn fixed_random_cycles_and_wraps_mod_10000() {
        let r = FixedRandom::new(vec![1234, 99_999]);
        assert_eq!(r.next_below_10000(), 1234);
        assert_eq!(r.next_below_10000(), 9_999);
        assert_eq!(r.next_below_10000(), 1234, "应循环回起点");
    }

    #[test]
    #[should_panic(expected = "固定随机源至少要有 1 个值")]
    fn fixed_random_rejects_empty() {
        let _ = FixedRandom::new(Vec::new());
    }
}