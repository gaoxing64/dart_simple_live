//! a_bogus 用的 RC4 与两种 base64 变体（逐字节对照 Dart `CryptoUtility`）。
//!
//! 与标准 base64 的差异（照抄 Dart，**不可**"纠正"）：
//! - [`base64_encode`]：把每个码元按 8 位展开成二进制串、补 0 到 6 的倍数、
//!   每 6 位查表；padding 数 = `pad_len / 2`（Dart 的 `~/` 整除）。
//! - [`abogus_encode`]：经典 3 字节 -> 4 字符，按 Dart 的 `shifts`/`masks` 与
//!   两个 break 条件处理尾部不足 3 字节的情形。

/// RC4 加密（对齐 Dart `CryptoUtility.rc4Encrypt`）。
///
/// Dart 侧 `plaintext.codeUnits` 逐个取，密钥 `key[i % key.len]`。
/// 本函数等价实现：按 `u16` 码元处理明文，返回与码元低 8 位异或后的字节。
///
/// # Panics
/// `key` 为空时 Dart 会抛 `RangeError`（`key.length == 0` -> 取模 0）。
/// Rust 侧改为返回空`Vec`，调用点由签名层保证 key 非空（`UA_KEY` 长度 3）。
pub fn rc4(key: &[u8], plaintext: &[u16]) -> Vec<u8> {
    if key.is_empty() {
        return Vec::new();
    }
    let mut s: [u8; 256] = std::array::from_fn(|i| i as u8);
    let mut j: usize = 0;
    for i in 0..256usize {
        j = (j + s[i] as usize + key[i % key.len()] as usize) % 256;
        s.swap(i, j);
    }

    let mut out = Vec::with_capacity(plaintext.len());
    let (mut i, mut j) = (0usize, 0usize);
    for &ch in plaintext {
        i = (i + 1) % 256;
        j = (j + s[i] as usize) % 256;
        s.swap(i, j);
        let k = s[(s[i] as usize + s[j] as usize) % 256];
        // Dart: ciphertext.add(char ^ k)，char 是码元；低 8 位参与异或后取字节。
        out.push(((ch & 0xff) as u8) ^ k);
    }
    out
}

/// RC4 单字节密钥版本（对齐 Dart `xbogus.dart` 的 `rc4Encrypt(int key, data)`）。
///
/// Dart 侧 `key` 是 `int`，`(j + s[i] + key) & 0xff` 等价于把 key 截断为一个字节。
pub fn rc4_u8(key: u8, data: &mut [u8]) {
    let mut s: [u8; 256] = std::array::from_fn(|i| i as u8);
    let mut j: usize = 0;
    for i in 0..256usize {
        j = (j + s[i] as usize + key as usize) % 256;
        s.swap(i, j);
    }

    let mut i: usize = 0;
    j = 0;
    for byte in data.iter_mut() {
        i = (i + 1) % 256;
        j = (j + s[i] as usize) % 256;
        s.swap(i, j);
        let k = s[(s[i] as usize + s[j] as usize) % 256];
        *byte ^= k;
    }
}

/// Dart `CryptoUtility.base64Encode`：8 位展开 -> 补 0 到 6 的倍数 -> 每 6 位查表。
///
/// `alphabet` 必须是 **64 字符**的表（Dart侧`character` / `character2`）。
///
/// # Panics
/// `alphabet` 的字符数 < 64 时按Dart 语义无法查到越界索引，本函数返回 `None`。
pub fn base64_encode(input: &[u16], alphabet: &str) -> Option<String> {
    let alphabet: Vec<char> = alphabet.chars().collect();
    if alphabet.len() < 64 {
        return None;
    }

    let mut binary = String::with_capacity(input.len() * 8);
    for &c in input {
        // Dart: c.toRadixString(2).padLeft(8, '0')，码元 > 255 时二进制串更长。
        let bits = format!("{c:b}");
        binary.push_str(&"0".repeat(8usize.saturating_sub(bits.len())));
        binary.push_str(&bits);
    }

    let pad_len = (6 - binary.len() % 6) % 6;
    binary.push_str(&"0".repeat(pad_len));

    let mut out = String::with_capacity(binary.len() / 6 + 2);
    let bytes = binary.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let mut idx = 0usize;
        for k in 0..6 {
            idx = (idx << 1) | usize::from(bytes[i + k] == b'1');
        }
        out.push(alphabet[idx]);
        i += 6;
    }
    // Dart: '=' * (paddingLength ~/ 2)
    out.push_str(&"=".repeat(pad_len / 2));
    Some(out)
}

/// Dart `CryptoUtility.abogusEncode`：3 字节 -> 4 字符的自定义 base64。
///
/// 与标准 base64 的padding 规则一致（`(4 - len % 4) % 4`），
/// 但尾部不足时按 Dart 的 break 条件少输出字符。
///
/// # Panics
/// `alphabet` 字符数 < 64 时返回 `None`（Dart 侧会抛 `RangeError`）。
pub fn abogus_encode(bytes_str: &[u16], alphabet: &str) -> Option<String> {
    let alphabet: Vec<char> = alphabet.chars().collect();
    if alphabet.len() < 64 {
        return None;
    }

    const SHIFTS: [u32; 4] = [18, 12, 6, 0];
    const MASKS: [u32; 4] = [0xFC0000, 0x03F000, 0x0FC0, 0x3F];

    let len = bytes_str.len();
    let mut out = String::new();
    let mut i = 0usize;
    while i < len {
        let at = |k: usize| u32::from(bytes_str[k]);
        let n: u32 = if i + 2 < len {
            (at(i) << 16) | (at(i + 1) << 8) | at(i + 2)
        } else if i + 1 < len {
            (at(i) << 16) | (at(i + 1) << 8)
        } else {
            at(i) << 16
        };

        for j in 0..4usize {
            if SHIFTS[j] == 6 && i + 1 >= len {
                break;
            }
            if SHIFTS[j] == 0 && i + 2 >= len {
                break;
            }
            out.push(alphabet[((n & MASKS[j]) >> SHIFTS[j]) as usize]);
        }
        i += 3;
    }
    out.push_str(&"=".repeat((4 - out.len() % 4) % 4));
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::douyin::signature::tables;

    #[test]
    fn rc4_empty_key_returns_empty() {
        assert!(rc4(&[], &[1, 2, 3]).is_empty());
    }

    #[test]
    fn rc4_matches_dart_probe() {
        // Dart: CryptoUtility.rc4Encrypt(Uint8List.fromList([0,1,14]), "abc")
        let out = rc4(&[0, 1, 14], &[97, 98, 99]);
        // 独立参照：RC4(key=[0,1,14]) on "abc"
        assert_eq!(out.len(), 3);
        // 具体字节由 golden 端到端测试覆盖，这里只断言非平凡（不是恒等）
        assert_ne!(out, vec![97, 98, 99]);
    }

    #[test]
    fn base64_encode_pads_with_half_pad_len() {
        // 1 字节输入 -> 8 位 -> 补 4 个 0 -> 2 组 6 位 -> 2 字符 + 2 个 '='
        let out = base64_encode(&[0b1010_1010], tables::CHARACTER).expect("alphabet ok");
        assert_eq!(out.chars().count(), 4);
        assert!(out.ends_with("=="));
    }

    #[test]
    fn abogus_encode_rejects_short_alphabet() {
        assert!(abogus_encode(&[1, 2, 3], "short").is_none());
        assert!(base64_encode(&[1], "short").is_none());
    }
}