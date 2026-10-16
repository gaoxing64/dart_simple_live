//! IP-7 不变量守护：SM3 标准向量（**Dart 实测值**）+ 常量表维度。
//!
//! SM3 向量取自 Dart `package:dart_sm` 的 `SM3.hashBytes` 实跑结果，
//! 并与 OpenSSL / Python `gmssl` 交叉验证一致（见 docs/rust-core/evidence-douyin-sig-*.log）。

use slive_core::platforms::douyin::signature::tables::{
    BIG_ARRAY, CHARACTER, CHARACTER2, SORT_INDEX, SORT_INDEX2, XBOGUS_ALPHABET,
};

#[test]
fn ac42_sm3_matches_dart_sm3_vectors() {
    use slive_core::platforms::douyin::signature::sm3::sm3;
    let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();

    // Dart dart_sm SM3.hashBytes 实测值
    assert_eq!(
        hex(&sm3(b"")),
        "1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b"
    );
    assert_eq!(
        hex(&sm3(b"abc")),
        "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
    );
    assert_eq!(
        hex(&sm3(b"hello world")),
        "44f0061e69fa6fdfc290c494654a05dc0c053da7e5c52b84ef93a9d67d3fff88"
    );
    assert_eq!(hex(&sm3(b"cus")), "417d9419cff0742bacd41b07de88334d86546560873f7912a6adcbe82b8161bf");
    // 跨块（>64 字节），验证填充分支
    assert_eq!(
        hex(&sm3(&vec![b'x'; 300])),
        "29e18679e3c57a999429ccb351c5c6093989fb6f0ceae2a6487a10c9c0bc95f6"
    );
}

#[test]
fn ac42_tables_have_expected_dimensions() {
    assert_eq!(BIG_ARRAY.len(), 256);
    // Dart 的 bigArray 是 0..255 的一个置换
    let mut sorted = BIG_ARRAY.to_vec();
    sorted.sort_unstable();
    assert_eq!(sorted, (0..=255).collect::<Vec<u8>>(), "bigArray 必须是全排列");
    assert_eq!(SORT_INDEX.len(), 44);
    assert_eq!(SORT_INDEX2.len(), 44);
    assert!(
        SORT_INDEX.iter().all(|i| *i < 72),
        "sortIndex 不得越界到 abDir[72] 之外"
    );
    assert!(
        SORT_INDEX2.iter().all(|i| *i < 72),
        "sortIndex2 不得越界到 abDir[72] 之外"
    );
    // abDir[56] = aid = 6383（> u16::MAX 无关但 > 255）：Dart 用 `String.fromCharCodes`
    // 会把它当作单个码元，而 Rust 侧 `d[i] as u16` 会截断。两张表都不含 56，
    // 所以该键从不参与序列化 —— 一旦有人改表加了 56，签名会静默出错。
    assert!(
        !SORT_INDEX.contains(&56) && !SORT_INDEX2.contains(&56),
        "abDir[56]=aid(6383) 不可进入序列化表（会与 as u16 截断行为不一致）"
    );
    // abDir[15]（Map）与 abDir[19]（List）在 Dart 里是配置快照，两表都不该读它们。
    assert!(
        !SORT_INDEX.contains(&15)
            && !SORT_INDEX.contains(&19)
            && !SORT_INDEX2.contains(&15)
            && !SORT_INDEX2.contains(&19),
        "abDir[15]/[19] 在 Dart 里非字节，序列化表不应引用"
    );
}

#[test]
fn ac42_alphabets_are_64_chars_and_distinct() {
    assert_eq!(CHARACTER.chars().count(), 64);
    assert_eq!(CHARACTER2.chars().count(), 64);
    assert_eq!(XBOGUS_ALPHABET.chars().count(), 64);
    assert_ne!(CHARACTER, CHARACTER2);
}
