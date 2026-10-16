//! X-Bogus 签名（逐字节移植 Dart `simple_live_core/lib/src/platforms/douyin/xbogus.dart`）。
//!
//! # 流程（Dart `generateXBogus`）
//! 1. 校验 `msStub` 是 32 字符的 md5 hex；
//! 2. 取 2 个随机字节：`random1 ∈ [0,256)`（只参与 header）、`random2 ∈ [0,255)`（RC4 密钥）；
//! 3. `md5Bytes = md5(decode(hex(msStub)))[14..16]`（**先 hex 解码再 md5**，不是直接 md5 hex 串）；
//! 4. 组10 字节 `payload`，`payload[9] = payload[0..9]` 的 XOR 校验和；
//! 5. 用 `random2` 作单字节密钥 RC4 加密 `payload`；
//! 6. 前置 `[header, random2]` 得 12 字节，按 X-Bogus 字母表 base64 -> 固定 16 字符。
//!
//! # ⚠️ 易错点
//! - `encodeBase64` 直接读 `data[i+1]` / `data[i+2]`，**不做长度检查**
//!   （Dart 侧靠 `finalData` 恒为 12 字节保证不越界）；Rust 侧显式处理短输入。
//! - `random2` 是 RC4 密钥且范围是 `[0,255)`（**不含 255**），
//!   与 `random1` 的 `[0,256)` 不同 —— Dart 两个 `nextInt` 上限不同。
//! - 输出**不带** `X-Bogus=` 前缀（Dart 返回裸串，调用方自己拼 `signature=`）。

use md5::{Digest, Md5};

use super::crypto::rc4_u8;
use super::random::RandomSource;
use super::tables::{EMPTY_MD5_BYTES, XBOGUS_ALPHABET};

/// `msStub` 的字符长度（32 位 md5 hex）。
const MS_STUB_LEN: usize = 32;

/// X-Bogus 载荷的字节数（Dart `payload`，含末尾校验和）。
const PAYLOAD_LEN: usize = 10;

/// 编码前的总字节数（Dart `finalData = 12`）。
const FINAL_LEN: usize = 12;

/// 生成 X-Bogus 签名（对齐 Dart `generateXBogus(msStub, counter)`）。
///
/// 返回**裸签名串**（16 字符，不含 `X-Bogus=` / `signature=` 前缀）。
/// `msStub` 必须是 32 字符的 md5 小写 hex；非法长度返回 [`SliveError::InvalidInput`]。
///
/// # Errors
/// - `ms_stub` 长度不等于 32 -> `InvalidInput`（对齐 Dart `ArgumentError`）
/// - `ms_stub` 含非 hex 字符 -> `InvalidInput`（Dart 的 `int.parse` 会抛 `FormatException`）
pub fn generate_x_bogus(
    ms_stub: &str,
    counter: u32,
    random: &dyn RandomSource,
) -> Result<String, crate::error::SliveError> {
    if ms_stub.len() != MS_STUB_LEN {
        return Err(crate::error::SliveError::invalid_input(format!(
            "msStub 必须是 {MS_STUB_LEN} 字符的 md5 hex 串，实际 {} 字符",
            ms_stub.len()
        )));
    }

    // Dart: Random.secure().nextInt(256) -> [0,256)
    // Dart: Random.secure().nextInt(255) -> [0,255)
    // RandomSource 统一给 [0,10000)，此处按Dart 上限取模还原区间。
    let random1 = (random.next_below_10000() % 256) as u8;
    let random2 = (random.next_below_10000() % 255) as u8;

    let md5_tail = md5_last2(ms_stub)?;

    let header = 0x40 | (random1 & 0x1f);
    let mut payload = [0u8; PAYLOAD_LEN];
    payload[0] = (counter & 0x3f) as u8;
    payload[1] = 0;
    payload[2] = 1;
    payload[3] = 0x0e;
    payload[4] = EMPTY_MD5_BYTES[0];
    payload[5] = EMPTY_MD5_BYTES[1];
    payload[6] = md5_tail[0];
    payload[7] = md5_tail[1];
    payload[8] = random2;
    payload[9] = 0;

    // Dart: payload[9] = payload[0..9] 的 XOR
    let checksum = payload[..PAYLOAD_LEN - 1].iter().fold(0u8, |acc, b| acc ^ b);
    payload[PAYLOAD_LEN - 1] = checksum;

    rc4_u8(random2, &mut payload);

    let mut final_data = [0u8; FINAL_LEN];
    final_data[0] = header;
    final_data[1] = random2;
    final_data[2..].copy_from_slice(&payload);

    Ok(encode_x_bogus_base64(&final_data))
}

/// `md5(decode(hexStr))` 的末两字节（Dart `md5Last2`）。
///
/// 注意是**先 hex 解码成 16 字节再算 md5**，不是对 32 字符的 hex 串直接算 md5。
pub(super) fn md5_last2(hex_str: &str) -> Result<[u8; 2], crate::error::SliveError> {
    let bytes = hex_str.as_bytes();
    let mut raw = [0u8; 16];
    for i in 0..16 {
        let hi = hex_nibble(bytes[i * 2]).ok_or_else(|| {
            crate::error::SliveError::invalid_input(format!(
                "msStub 含非 hex 字符: {:?}",
                bytes[i * 2] as char
            ))
        })?;
        let lo = hex_nibble(bytes[i * 2 + 1]).ok_or_else(|| {
            crate::error::SliveError::invalid_input(format!(
                "msStub 含非 hex 字符: {:?}",
                bytes[i * 2 + 1] as char
            ))
        })?;
        raw[i] = (hi << 4) | lo;
    }
    let digest = Md5::digest(raw);
    Ok([digest[14], digest[15]])
}

/// 单个 hex 字符 -> 0..15；非法返回 `None`。
fn hex_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// 6 位索引 -> X-Bogus 字母表字符（对齐 Dart `alphabetLookup`）。
///
/// Dart 建的是一张 128 项的表：`table[standardAlphabet.codeUnitAt(i)] = xbogusAlphabet.codeUnitAt(i)`，
/// 编码时以**标准字母表的字符**为键取值。展开即 `结果(i) = xbogusAlphabet[i]` ——
/// 是**按位置取**，不是「在 X-Bogus 表里找标准字符的位置」。
///
/// ⚠️ 本函数曾经写反成 `XBOGUS_ALPHABET.find(std_char)`（按值反查），
/// 导致 4 条 X-Bogus golden 全错。判据：6 位索引 `i` 必须映射到 `XBOGUS_ALPHABET[i]`。
pub(super) fn alphabet_lookup(index: u8) -> char {
    XBOGUS_ALPHABET
        .chars()
        .nth(index as usize)
        .expect("X-Bogus 字母表必须是 64 字符")
}

/// X-Bogus 的 base64 变体（Dart `encodeBase64`）。
///
/// 12 字节 -> 16 字符，无 padding。注意 Dart 侧直接访问 `data[i+1]`/`data[i+2]`，
/// 短输入会抛 `RangeError`；Rust 侧对短输入做补零处理（实际调用恒为 12 字节）。
pub(super) fn encode_x_bogus_base64(data: &[u8]) -> String {
    debug_assert_eq!(XBOGUS_ALPHABET.chars().count(), 64);
    let byte_at = |i: usize| data.get(i).copied().unwrap_or(0);
    let mut out = String::with_capacity(16);
    let mut i = 0;
    while i < data.len() {
        let (b0, b1, b2) = (byte_at(i), byte_at(i + 1), byte_at(i + 2));
        out.push(alphabet_lookup((b0 >> 2) & 0x3f));
        out.push(alphabet_lookup(((b0 << 4) | (b1 >> 4)) & 0x3f));
        out.push(alphabet_lookup(((b1 << 2) | (b2 >> 6)) & 0x3f));
        out.push(alphabet_lookup(b2 & 0x3f));
        i += 3;
    }
    out
}
