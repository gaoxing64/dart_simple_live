//! TARS 读写缓冲的共享工具与再导出。
//!
//! - [`WriteBuffer`]：顺序写缓冲，见 [`writer`]。
//! - [`ReadBuffer`]：顺序读缓冲（零拷贝借用），见 [`reader`]。
//!
//! 两者字节序均可运行时切换（[`Endian`]），默认大端 —— TARS 协议字段编码恒为大端。

pub mod reader;
pub mod writer;

pub use reader::ReadBuffer;
pub use writer::WriteBuffer;

use crate::error::SliveError;

use super::endian::Endian;

/// 构造统一的越界错误（Dart 版由 `ByteData` 抛 `RangeError`，此处改为返回 `Err`）。
pub(crate) fn out_of_bounds(what: &str, pos: usize, need: usize, len: usize) -> SliveError {
    SliveError::decode(format!(
        "TARS 缓冲越界：{what} 需要 {need} 字节，偏移 {pos} 处仅剩 {} 字节（总长 {len}）",
        len.saturating_sub(pos)
    ))
}

/// TARS 字符串长度上限（对齐 Dart `TarsStruct.TARS_MAX_STRING_LENGTH` = 100 MiB）。
///
/// 用于防畸形包声明超大长度后触发巨额分配（拒绝服务面）。
pub const TARS_MAX_STRING_LENGTH: usize = 100 * 1024 * 1024;

/// 校验字符串长度合法（非负且不超上限）；`len` 为 i32 原值（负值即非法）。
pub(crate) fn check_string_len(len: i32) -> Result<usize, SliveError> {
    if len < 0 {
        return Err(SliveError::decode(format!("TARS 字符串长度为负: {len}")));
    }
    let n = len as usize;
    if n > TARS_MAX_STRING_LENGTH {
        return Err(SliveError::decode(format!(
            "TARS 字符串过长: {n} > {TARS_MAX_STRING_LENGTH}"
        )));
    }
    Ok(n)
}

/// 把字节解为 UTF-8 字符串，非法序列返回 `Decode` 错误（不 lossy 静默替换）。
pub(crate) fn decode_utf8(bytes: &[u8], what: &str) -> Result<String, SliveError> {
    std::str::from_utf8(bytes)
        .map(str::to_owned)
        .map_err(|e| SliveError::decode(format!("TARS {what} 非 UTF-8: {e}")))
}

    /// 取字节序对应的多字节数组（大端或小端）。
    ///
    /// 大端：取 `v.to_be_bytes()` 的**低 N 字节**（即高序字节），顺序不变。
    /// 小端：取同样的低 N 字节但**逆序**排列（等价于 `v.to_le_bytes()` 的低 N 字节）。
    pub(crate) fn order_bytes<const N: usize>(v: u64, endian: Endian) -> [u8; N] {
        let full = v.to_be_bytes();
        let mut a = [0u8; N];
        for i in 0..N {
            a[i] = if endian.is_big() {
                full[8 - N + i]
            } else {
                full[8 - N + (N - 1 - i)]
            };
        }
        a
    }

/// 按字节序组装多字节整数（大端或小端）。
pub(crate) fn from_order_bytes<const N: usize>(a: [u8; N], endian: Endian) -> u64 {
    let mut full = [0u8; 8];
    if endian.is_big() {
        full[8 - N..].copy_from_slice(&a);
    } else {
        // 小端：线上字节是低 N 字节的逆序，还原到大端表示的高 N 位
        for i in 0..N {
            full[8 - N + i] = a[N - 1 - i];
        }
    }
    u64::from_be_bytes(full)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn order_helpers_are_symmetric() {
        for e in [Endian::Big, Endian::Little] {
            for v in [0u64, 1, 0x0102_0304_0506_0708, u64::MAX] {
                assert_eq!(from_order_bytes::<8>(order_bytes::<8>(v, e), e), v);
                assert_eq!(from_order_bytes::<4>(order_bytes::<4>(v, e), e), v & 0xFFFF_FFFF);
                assert_eq!(from_order_bytes::<2>(order_bytes::<2>(v, e), e), v & 0xFFFF);
                assert_eq!(from_order_bytes::<1>(order_bytes::<1>(v, e), e), v & 0xFF);
            }
        }
    }

    /// 对拍标准库 `to_be_bytes` / `to_le_bytes`。
    ///
    /// 这一条比「往返对称」更强：往返对称在**两侧共享同一个错误**时也会通过
    /// （例如曾把小端索引写成 `full[N-1-i]`，写读同时错、往返仍成立）。
    #[test]
    fn order_helpers_match_std_byte_layout() {
        let cases: [u64; 4] = [0x0102, 0x0102_0304, 0x0102_0304_0506_0708, u64::MAX];

        for v in cases {
            let be = v.to_be_bytes();
            let le = v.to_le_bytes();
            // 大端 N 字节 = to_be_bytes() 的**末尾** N 字节（高序在前）
            assert_eq!(order_bytes::<8>(v, Endian::Big), be);
            assert_eq!(order_bytes::<4>(v, Endian::Big), be[4..]);
            assert_eq!(order_bytes::<2>(v, Endian::Big), be[6..]);
            assert_eq!(order_bytes::<1>(v, Endian::Big), be[7..]);
            // 小端 N 字节 = to_le_bytes() 的**开头** N 字节（低序在前）
            assert_eq!(order_bytes::<8>(v, Endian::Little), le);
            assert_eq!(order_bytes::<4>(v, Endian::Little), le[..4]);
            assert_eq!(order_bytes::<2>(v, Endian::Little), le[..2]);
            assert_eq!(order_bytes::<1>(v, Endian::Little), le[..1]);

            // from_order_bytes 是 order_bytes 的逆运算
            assert_eq!(from_order_bytes::<8>(be, Endian::Big), v);
            assert_eq!(from_order_bytes::<8>(le, Endian::Little), v);
            let be4 = [be[4], be[5], be[6], be[7]];
            let le4 = [le[0], le[1], le[2], le[3]];
            assert_eq!(from_order_bytes::<4>(be4, Endian::Big), v & 0xFFFF_FFFF);
            assert_eq!(from_order_bytes::<4>(le4, Endian::Little), v & 0xFFFF_FFFF);
            assert_eq!(from_order_bytes::<2>([be[6], be[7]], Endian::Big), v & 0xFFFF);
            assert_eq!(from_order_bytes::<2>([le[0], le[1]], Endian::Little), v & 0xFFFF);
        }
    }

    #[test]
    fn string_len_guards_reject_bad_values() {
        assert!(check_string_len(-1).is_err());
        assert!(check_string_len(TARS_MAX_STRING_LENGTH as i32 + 1).is_err());
        assert_eq!(check_string_len(10).unwrap(), 10);
    }

    #[test]
    fn out_of_bounds_message_is_readable() {
        let e = out_of_bounds("u32", 2, 4, 4);
        let msg = e.to_string();
        assert!(msg.contains("需要 4 字节"), "实际: {msg}");
        assert!(msg.contains("仅剩 2 字节"), "实际: {msg}");
    }
}
