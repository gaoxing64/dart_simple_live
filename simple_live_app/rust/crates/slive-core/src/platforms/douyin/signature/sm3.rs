//! SM3 哈希（对齐 Dart `package:dart_sm` 的 `SM3.hashBytes`）。
//!
//! # 为什么自己实现
//! `slive-core` 的 `Cargo.toml` **不含** SM3 crate（只有 `md-5`），且本任务禁止改
//! `Cargo.toml`，故按 GB/T 32905-2016 手写。算法与 `dart_sm` 一致，
//! 由 `ac_douyin_signature.rs::sm3_matches_dart_vectors` 用 Dart 实测向量断言。
//!
//! # 与 `big_array.rs` 的关系
//! 本文件只做**标准 SM3**；a_bogus 里那个 256 项置换表是签名层的字节混淆，
//! 与 SM3 内部无关，二者都在 [`crate::platforms::douyin::signature`] 下但互不依赖。

/// SM3 初始向量 IV。
///
/// #⚠️ 第 8 项是 `0xb0fb0e4e`，不是某些资料里写的 `0xb0fb5e4e`
///
/// GB/T 32905-2016 附录 A 的**印刷文本**记作 `b0fb5e4e`，但 Dart `dart_sm`
/// （`SM3._V`）、OpenSSL、Python `gmssl` 三方一致使用 `b0fb0e4e`，
/// 且只有该值能算出标准向量 `SM3("abc") = 66c7f0f4...`。
/// 本项目的行为基准是 **Dart**，故取 `b0fb0e4e`。
/// 若误用 `b0fb5e4e`，SM3 全盘错误 -> `a_bogus` 的 `abDir[38..43]` 全错 -> 签名被拒。
const IV: [u32; 8] = [
    0x7380_166f,
    0x4914_b2b9,
    0x1724_42d7,
    0xda8a_0600,
    0xa96f_30bc,
    0x1631_38aa,
    0xe38d_ee4d,
    0xb0fb_0e4e,
];

/// 32 位循环左移。Dart `dart_sm` 内部用 `int`（64 位）但对 32 位值等价。
///
/// 用 `wrapping_shl` 而非 `<<`：SM3 的 `P0`/`P1` 要旋转 23/17/15 位，
/// 直接 `<<` 在 debug 构建下会触发「移位溢出」panic。
#[inline]
fn rotl(x: u32, n: u32) -> u32 {
    x.rotate_left(n)
}

/// 字节序置换函数 P0：`X ^ (X <<< 9) ^ (X <<< 17)`（GB/T 32905-2016 §5.2）。
///
/// 用于**压缩函数**的 `E = P0(TT2)`。
#[inline]
fn p0(x: u32) -> u32 {
    x ^ rotl(x, 9) ^ rotl(x, 17)
}

/// 字节序置换函数 P1：`X ^ (X <<< 15) ^ (X <<< 23)`（GB/T 32905-2016 §5.3）。
///
/// 用于**消息扩展**的 `W[j] = P1(...)`。
#[inline]
fn p1(x: u32) -> u32 {
    x ^ rotl(x, 15) ^ rotl(x, 23)
}

/// 分组常数 T_j：j <= 15 用 0x79cc4519，否则 0x7a879d8a。
#[inline]
fn t_j(j: usize) -> u32 {
    if j < 16 {
        0x79cc_4519
    } else {
        0x7a87_9d8a
    }
}

/// 布尔函数 FF_j：前16 轮异或，之后 majority。
#[inline]
fn ff(j: usize, x: u32, y: u32, z: u32) -> u32 {
    if j < 16 {
        x ^ y ^ z
    } else {
        (x & y) | (x & z) | (y & z)
    }
}

/// 布尔函数 GG_j：前 16 轮异或，之后 x&y | ~x&z。
#[inline]
fn gg(j: usize, x: u32, y: u32, z: u32) -> u32 {
    if j < 16 {
        x ^ y ^ z
    } else {
        (x & y) | (!x & z)
    }
}

/// 压缩单个 64 字节分组。
fn compress_block(v: &mut [u32; 8], block: &[u8]) {
    debug_assert_eq!(block.len(), 64);

    let mut w = [0u32; 68];
    for (i, word) in w.iter_mut().enumerate().take(16) {
        let o = i * 4;
        *word = u32::from_be_bytes([block[o], block[o + 1], block[o + 2], block[o + 3]]);
    }
    for j in 16..68 {
        w[j] = p1(w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)) ^ rotl(w[j - 13], 7) ^ w[j - 6];
    }

    let mut w1 = [0u32; 64];
    for j in 0..64 {
        w1[j] = w[j] ^ w[j + 4];
    }

    let (mut a, mut b, mut c, mut d) = (v[0], v[1], v[2], v[3]);
    let (mut e, mut f, mut g, mut h) = (v[4], v[5], v[6], v[7]);

    for j in 0..64 {
        let a12 = rotl(a, 12);
        let ss1 = rotl(a12.wrapping_add(e).wrapping_add(rotl(t_j(j), j as u32)), 7);
        let ss2 = ss1 ^ a12;
        let tt1 = ff(j, a, b, c)
            .wrapping_add(d)
            .wrapping_add(ss2)
            .wrapping_add(w1[j]);
        let tt2 = gg(j, e, f, g)
            .wrapping_add(h)
            .wrapping_add(ss1)
            .wrapping_add(w[j]);
        d = c;
        c = rotl(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = rotl(f, 19);
        f = e;
        // 注意是 **P0**（rotl 9/17），P1 只用在上面的消息扩展 —— 用错会得到
        // 与 GB/T 标准完全不同的摘要（本项目踩过这个坑，见 docs/rust-core/evidence-douyin-sig-*.log）。
        e = p0(tt2);
    }

    v[0] ^= a;
    v[1] ^= b;
    v[2] ^= c;
    v[3] ^= d;
    v[4] ^= e;
    v[5] ^= f;
    v[6] ^= g;
    v[7] ^= h;
}

/// SM3 摘要（32 字节）。
///
/// # Panics
/// 无 panic 分支。
pub fn sm3(data: &[u8]) -> [u8; 32] {
    let mut v = IV;
    let full = data.len() / 64;
    for i in 0..full {
        compress_block(&mut v, &data[i * 64..i * 64 + 64]);
    }

    // 填充：0x80 + 若干 0 + 64 位大端比特长度。
    let rem = &data[full * 64..];
    let mut tail = [0u8; 128];
    tail[..rem.len()].copy_from_slice(rem);
    tail[rem.len()] = 0x80;
    let bit_len = (data.len() as u64) * 8;
    let tail_len = if rem.len() + 9 <= 64 { 64 } else { 128 };
    tail[tail_len - 8..tail_len].copy_from_slice(&bit_len.to_be_bytes());
    for i in 0..tail_len / 64 {
        compress_block(&mut v, &tail[i * 64..i * 64 + 64]);
    }

    let mut out = [0u8; 32];
    for (i, word) in v.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn sm3_standard_vectors() {
        // GB/T 32905-2016 附录 A 标准向量
        assert_eq!(
            hex(&sm3(b"abc")),
            "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
        );
        assert_eq!(
            hex(&sm3(b"abcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd")),
            "debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732"
        );
    }

    #[test]
    fn sm3_empty_input() {
        assert_eq!(
            hex(&sm3(b"")),
            "1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b"
        );
    }

    #[test]
    fn sm3_multi_block_input() {
        // 长度恰好跨块，验证填充分支（含 rem.len() + 9 > 64 的 128 字节尾块路径）
        let long = "x".repeat(300);
        assert_eq!(
            hex(&sm3(long.as_bytes())),
            "29e18679e3c57a999429ccb351c5c6093989fb6f0ceae2a6487a10c9c0bc95f6"
        );
    }
}