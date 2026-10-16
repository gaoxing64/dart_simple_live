//! 虎牙纯计算工具：随机源 / `rotl64` / uid 生成 / traceId / base64 / 百分号解码。
//!
//! 与 Dart `huya_site.dart`（`getUid`/`getUUid`/`getTraceId`）及
//! `huya_utils.dart`（`rotl64`/`getTraceId`）逐一对应。
//!
//! 随机源说明：本 crate 无 `rand` 依赖且 `Cargo.toml` 不可改（多路并行），
//! 故用 `RandomState`（内核熵）+ 纳秒时钟 + 单调计数器合成伪随机；
//! 随机值只用于**UA 伪装 / uid 占位 / traceId**，不参与任何签名或校验计算，
//! 因此不需要可注入的确定性随机（与 Dart 现状一致：Dart 也用不可注入的 `Random()`）。

use std::hash::{BuildHasher, Hasher};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use md5::{Digest, Md5};

/// 随机计数器（避免同纳秒重复）。
static COUNTER: AtomicU64 = AtomicU64::new(0);

/// 64 位伪随机数（`RandomState` 熵 + 时钟 + 计数器）。
pub fn random_u64() -> u64 {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);
    let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
    hasher.write_u64(nanos);
    hasher.write_u64(COUNTER.fetch_add(1, Ordering::Relaxed));
    hasher.finish()
}

/// `rotl64`：低 32 位循环左移 8 位后拼回高 32 位（对齐 Dart `huya_utils.rotl64`）。
///
/// Dart `int` 为 64 位有符号，此处按位模式运算后转回 `i64`，位模式与 Dart 一致。
pub fn rotl64(value: i64) -> i64 {
    let bits = value as u64;
    let low = bits & 0xFFFF_FFFF;
    let rotated_low = ((low << 8) | (low >> 24)) & 0xFFFF_FFFF;
    let high = bits & 0xFFFF_FFFF_0000_0000;
    (high | rotated_low) as i64
}

/// 32 位字母表（对齐 Dart `getUid` 的 `n`）。
const UID_ALPHABET: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/// 生成 uid 字符串（对齐 Dart `getUid`）。
///
/// - `t = Some(n)`：取字母表前 `e`（缺省全表）个字符拼 `n` 位（虎牙详情用它生成 13 位占位 uid）；
/// - `t = None`：标准 UUID v4 形态（36 位，含 `-` 与版本位）。
pub fn get_uid(t: Option<usize>, e: Option<usize>) -> String {
    match t {
        Some(len) => {
            let span = e.unwrap_or(UID_ALPHABET.len()).min(UID_ALPHABET.len()).max(1);
            (0..len)
                .map(|_| UID_ALPHABET[random_below(span as u64) as usize] as char)
                .collect()
        }
        None => uuid_v4(),
    }
}

/// 标准 UUID v4（对齐 Dart `getUid()` 的 `t == null` 分支）。
pub fn uuid_v4() -> String {
    let mut bytes = [0u8; 16];
    for chunk in bytes.chunks_mut(8) {
        let r = random_u64().to_be_bytes();
        chunk.copy_from_slice(&r[..chunk.len()]);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02X}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// 32 位无符号随机整数（对齐 Dart `getUUid` 的 `Random().nextInt(4294967295)`）。
pub fn random_u32() -> u32 {
    (random_u64() >> 32) as u32
}

/// 取 `[0, n)` 随机整数（`n == 0` 返回 0）。
pub fn random_below(n: u64) -> u64 {
    if n == 0 {
        return 0;
    }
    random_u64() % n
}

/// 生成 16 位十六进制 traceId（对齐 Dart `huya_utils.getTraceId`）。
///
/// Dart 用 `'xxxxxxxxxxxxxxxx'` 按 `[xy]` 替换：`x` 取 `[0,16)`，
/// `y` 取 `(t & 0x3) | 0x8`（即 `[8,12)`）。
pub fn get_trace_id() -> String {
    let mut out = String::with_capacity(16);
    for i in 0..16 {
        let t = (random_below(16) as u8) & 0xF;
        let nibble = if i % 2 == 0 { t } else { (t & 0x3) | 0x8 };
        out.push(char::from_digit(nibble as u32, 16).unwrap_or('0'));
    }
    out
}

/// md5 十六进制小写（对齐 Dart `md5.convert(...).toString()`）。
pub fn md5_hex(input: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(input.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// 标准 base64 解码（对齐 Dart `base64.decode`；忽略空白，非法字符报错）。
pub fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(input.len() / 4 * 3);
    let mut acc: u32 = 0;
    let mut bits = 0u32;
    let mut padding = 0usize;
    for ch in input.chars() {
        if ch.is_ascii_whitespace() {
            continue;
        }
        if ch == '=' {
            padding += 1;
            continue;
        }
        if padding > 0 {
            return Err("base64 填充符后仍有数据".to_string());
        }
        let value = match ch {
            'A'..='Z' => ch as u32 - 'A' as u32,
            'a'..='z' => ch as u32 - 'a' as u32 + 26,
            '0'..='9' => ch as u32 - '0' as u32 + 52,
            '+' => 62,
            '/' => 63,
            other => return Err(format!("非法 base64 字符: {other}")),
        };
        acc = (acc << 6) | value;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((acc >> bits) & 0xFF) as u8);
        }
    }
    Ok(out)
}

/// 百分号解码（对齐 Dart `Uri.decodeComponent`；`+` **不**转空格，与 Dart 一致）。
///
/// `%` 后不足两位或非十六进制 -> 原样保留该 `%`（Dart 亦容错）。
pub fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = &input[i + 1..i + 3];
            if let Ok(value) = u8::from_str_radix(hex, 16) {
                out.push(value);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotl64_rotates_low_32_bits_only() {
        assert_eq!(rotl64(0), 0);
        // 低 32 位 0x00000001 左移 8 位 -> 0x00000100
        assert_eq!(rotl64(1), 0x100);
        assert_eq!(rotl64(0x0000_00FF), 0x0000_FF00);
        // 高 32 位保持不变
        assert_eq!(rotl64(0x1234_5678_0000_00FFu64 as i64), 0x1234_5678_0000_FF00u64 as i64);
    }

    #[test]
    fn get_uid_with_len_uses_limited_alphabet() {
        let uid = get_uid(Some(13), Some(10));
        assert_eq!(uid.len(), 13, "13 位占位 uid");
        assert!(
            uid.chars().all(|c| c.is_ascii_digit()),
            "e=10 时只用前 10 个数字字符，实际 {uid}"
        );
    }

    #[test]
    fn get_uid_full_alphabet_stays_in_table() {
        let uid = get_uid(Some(8), None);
        assert_eq!(uid.len(), 8);
        assert!(
            uid.chars().all(|c| c.is_ascii_alphanumeric()),
            "实际 {uid}"
        );
    }

    #[test]
    fn uuid_v4_has_hyphens_and_version_bits() {
        let id = uuid_v4();
        let parts: Vec<&str> = id.split('-').collect();
        assert_eq!(
            parts.iter().map(|p| p.len()).collect::<Vec<_>>(),
            vec![8, 4, 4, 4, 12],
            "标准 UUID 分段"
        );
        assert!(parts[2].starts_with('4'), "版本位为 4，实际 {}", parts[2]);
        assert!(
            matches!(parts[3].as_bytes()[0], b'8' | b'9' | b'A' | b'B'),
            "variant 位正确，实际 {}",
            parts[3]
        );
    }

    #[test]
    fn trace_id_is_16_hex_chars() {
        let id = get_trace_id();
        assert_eq!(id.len(), 16);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()), "实际 {id}");
    }

    #[test]
    fn md5_matches_known_vector() {
        assert_eq!(md5_hex(""), "d41d8cd98f00b204e9800998ecf8427e");
        assert_eq!(md5_hex("abc"), "900150983cd24fb0d6963f7d28e17f72");
    }

    #[test]
    fn base64_decode_matches_known_vectors() {
        assert_eq!(base64_decode("aGVsbG8=").unwrap(), b"hello");
        assert_eq!(base64_decode("").unwrap(), b"");
        assert_eq!(base64_decode("6JmO54mZ").unwrap(), "虎牙".as_bytes());
        assert!(base64_decode("a*b").is_err(), "非法字符必须报错");
    }

    #[test]
    fn percent_decode_keeps_plus_and_broken_escape() {
        assert_eq!(percent_decode("a%3D"), "a=");
        assert_eq!(percent_decode("a+b"), "a+b", "Dart 不把 + 转空格");
        assert_eq!(percent_decode("100%"), "100%", "不完整转义原样保留");
        assert_eq!(percent_decode("%zz"), "%zz");
    }
}