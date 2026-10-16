//! a_bogus 的字节混淆与随机前缀（逐字节对照 Dart `StringProcessor` /
//! `CryptoUtility.transformBytes`）。
//!
//! #⚠️ 有状态
//! Dart 的 `CryptoUtility.bigArray` 是**实例字段**，`transformBytes` 会**原地修改**它。
//! 本模块的 [`transform_bytes`] 同样持有 `&mut [u8; 256]`，保持与 Dart 相同的
//! 「同一个签名器多次签名的结果互不相同」的行为（Dart 侧 `DouyinUtils.buildRequestUrl`
//! 每次新建 `ABogus`，故线上路径等价于「每次都是新表」）。

use super::crypto::abogus_encode;
use super::tables::RANDOM_PREFIX_LEN;

/// Dart `StringProcessor.jsShiftRight`：`>>> n`（64 位无符号右移）。
///
/// Dart 实现先`val & 0xFFFFFFFF` 再 `>>> n`，故当 `n >= 32` 时恒为 0
/// （a_bogus 里 `abDir[24]/[25]/[49]/[50]` 就是这样恒为 0的）。
/// **这是 Dart 的既有行为，Rust 必须照抄**，不可"修正"为 `val >> n`。
#[inline]
pub fn js_shift_right(val: u64, n: u32) -> u64 {
    (val & 0xFFFF_FFFF) >> n
}

/// Dart `StringProcessor.generateRandomBytes(length: 3)`。
///
/// 每次迭代调用一次随机源取`[0, 10000)` 的整数 `rd`，展开成 4 个码元；
/// 共 3 次迭代 = 12 个码元。
///
/// `rand_next` 在每次迭代时被调用恰好一次（与 Dart 一致）。
pub fn random_prefix<F: FnMut() -> u32>(mut rand_next: F) -> Vec<u16> {
    let mut out = Vec::with_capacity(RANDOM_PREFIX_LEN);
    for _ in 0..3 {
        let rd = rand_next() % 10_000;
        let lo = rd & 255;
        let hi = js_shift_right(rd as u64, 8) as u32 & 255;
        out.push(((lo & 170) | 1) as u16);
        out.push(((lo & 85) | 2) as u16);
        out.push(((hi & 170) | 5) as u16);
        out.push(((hi & 85) | 40) as u16);
    }
    out
}

/// Dart `CryptoUtility.transformBytes`。
///
/// `bytes_list` 是待序列化的码元序列（Dart 侧是 `String.fromCharCodes` 的结果）。
/// `big` 是会被原地修改的置换表（Dart 的 `CryptoUtility.bigArray`）。
///
/// 返回混淆后的码元序列（长度与输入一致）。
pub fn transform_bytes(bytes_list: &[u16], big: &mut [u8; 256]) -> Vec<u16> {
    let len = big.len(); // 256
    let mut out = Vec::with_capacity(bytes_list.len());

    let mut index_b = big[1] as usize;
    let mut initial_value: usize = 0;
    let mut value_e: usize = 0;

    for (index, &ch) in bytes_list.iter().enumerate() {
        let mut sum_initial: usize;
        if index == 0 {
            initial_value = big[index_b] as usize;
            sum_initial = index_b + initial_value;
            big[1] = initial_value as u8;
            big[index_b] = index_b as u8;
        } else {
            sum_initial = initial_value + value_e;
        }

        let char_value = ch as usize;
        sum_initial %= len;
        let value_f = big[sum_initial] as usize;
        out.push((char_value ^ value_f) as u16);

        value_e = big[(index + 2) % len] as usize;
        sum_initial = (index_b + value_e) % len;
        initial_value = big[sum_initial] as usize;
        big[sum_initial] = big[(index + 2) % len];
        big[(index + 2) % len] = initial_value as u8;
        index_b = sum_initial;
    }
    out
}

/// 随机前缀 + 混淆结果 -> a_bogus 字符串（对齐 Dart `generateAbogus` 末段）。
///
/// Dart: `abogusEncode(generateRandomBytes() + transformBytes(sortedValues), 0)`
pub fn encode_signature(
    sorted_values: &[u16],
    rand_next: impl FnMut() -> u32,
    big: &mut [u8; 256],
    alphabet: &str,
) -> Option<String> {
    let mut plain = random_prefix(rand_next);
    plain.extend_from_slice(&transform_bytes(sorted_values, big));
    abogus_encode(&plain, alphabet)
}

/// **给定**随机前缀 + 混淆结果 -> a_bogus 字符串（确定性路径）。
///
/// 与 [`encode_signature`] 的唯一差别：前缀由调用方给定而非随机生成。
/// `prefix` 通常是 12 个码元（对应 Dart 3 次 `generateRandomBytes()` 迭代）。
pub fn encode_signature_with_prefix(
    sorted_values: &[u16],
    prefix: &[u16],
    big: &mut [u8; 256],
    alphabet: &str,
) -> Option<String> {
    let mut plain = prefix.to_vec();
    plain.extend_from_slice(&transform_bytes(sorted_values, big));
    abogus_encode(&plain, alphabet)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::douyin::signature::tables::BIG_ARRAY;

    #[test]
    fn js_shift_right_is_zero_beyond_32_bits() {
        // Dart 的 `(v & 0xFFFFFFFF) >>> n` 在 n >= 32 时恒 0
        assert_eq!(js_shift_right(1_700_000_000_123, 0), 1_700_000_000_123 & 0xFFFF_FFFF);
        assert_eq!(js_shift_right(1_700_000_000_123, 32), 0);
        assert_eq!(js_shift_right(1_700_000_000_123, 40), 0);
        assert_eq!(js_shift_right(u64::MAX, 32), 0);
    }

    #[test]
    fn js_shift_right_8_bits() {
        assert_eq!(js_shift_right(0x1234, 8), 0x12);
        assert_eq!(js_shift_right(0x1234, 0), 0x1234);
    }

    #[test]
    fn random_prefix_is_deterministic_for_fixed_source() {
        let seq = [1234u32, 5678, 9012];
        let mut i = 0;
        let a = random_prefix(|| {
            let v = seq[i];
            i += 1;
            v
        });
        let mut j = 0;
        let b = random_prefix(|| {
            let v = seq[j];
            j += 1;
            v
        });
        assert_eq!(a, b);
        assert_eq!(a.len(), RANDOM_PREFIX_LEN);
        // Dart 的固定低/高位标记
        assert_eq!(a[0] & 1, 1);
        assert_eq!(a[1] & 3, 2);
        assert_eq!(a[2] & 5, 5);
        assert_eq!(a[3] & 0x28, 0x28);
    }

    #[test]
    fn random_prefix_consumes_source_exactly_three_times() {
        let mut calls = 0;
        let _ = random_prefix(|| {
            calls += 1;
            42
        });
        assert_eq!(calls, 3, "每次迭代只消费 1 个随机数（Dart generateByteSequence 只调一次）");
    }

    #[test]
    fn transform_bytes_is_stateful_on_big_array() {
        let input: Vec<u16> = (0u16..32).collect();
        let mut big1 = BIG_ARRAY;
        let mut big2 = BIG_ARRAY;
        let first = transform_bytes(&input, &mut big1);
        let second = transform_bytes(&input, &mut big1);
        let fresh = transform_bytes(&input, &mut big2);
        assert_eq!(first, fresh, "新表的首次结果应一致");
        assert_ne!(first, second, "同表二次调用应不同（Dart 会原地改 bigArray）");
    }

    #[test]
    fn transform_bytes_preserves_length() {
        let input: Vec<u16> = (0u16..77).collect();
        let mut big = BIG_ARRAY;
        assert_eq!(transform_bytes(&input, &mut big).len(), input.len());
    }
}