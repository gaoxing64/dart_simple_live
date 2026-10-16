#[cfg(test)]
mod tests {
    //! `x_bogus` 的单元测试（从 `x_bogus.rs` 拆出，单文件行数门禁 <= 300）。

    use crate::platforms::douyin::signature::random::FixedRandom;
    use crate::platforms::douyin::signature::tables::{EMPTY_MD5_BYTES, XBOGUS_ALPHABET};
    use crate::platforms::douyin::signature::x_bogus::{
        alphabet_lookup, encode_x_bogus_base64, generate_x_bogus, md5_last2,
    };
    use md5::{Digest, Md5};


    #[test]
    fn output_is_16_chars() {
        let out = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            1,
            &FixedRandom::new(vec![0x41, 0x7f]),
        )
        .expect("应成功");
        assert_eq!(out.chars().count(), 16);
    }

    #[test]
    fn output_uses_only_xbogus_alphabet() {
        let out = generate_x_bogus(
            "5d41402abc4b2a76b9719d911017c592",
            2,
            &FixedRandom::new(vec![0xff, 0x0d]),
        )
        .expect("应成功");
        for c in out.chars() {
            assert!(
                XBOGUS_ALPHABET.contains(c),
                "字符 {c:?} 不在X-Bogus 字母表内"
            );
        }
    }

    #[test]
    fn rejects_wrong_length_ms_stub() {
        let err = generate_x_bogus("abc", 1, &FixedRandom::new(vec![1, 1]))
            .expect_err("长度非法应报错");
        assert!(matches!(err, crate::error::SliveError::InvalidInput(_)), "{err:?}");
    }

    #[test]
    fn rejects_non_hex_ms_stub() {
        let err = generate_x_bogus("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", 1, &FixedRandom::new(vec![1, 1]))
            .expect_err("非 hex 应报错");
        assert!(matches!(err, crate::error::SliveError::InvalidInput(_)), "{err:?}");
    }

    #[test]
    fn uppercase_hex_is_accepted() {
        assert!(generate_x_bogus(
            "D41D8CD98F00B204E9800998ECF8427E",
            1,
            &FixedRandom::new(vec![1, 2])
        )
        .is_ok());
    }

    #[test]
    fn differs_when_random_changes() {
        let a = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            1,
            &FixedRandom::new(vec![0x10, 0x20]),
        )
        .expect("a");
        let b = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            1,
            &FixedRandom::new(vec![0x30, 0x40]),
        )
        .expect("b");
        assert_ne!(a, b);
    }

    #[test]
    fn differs_when_counter_changes() {
        let a = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            1,
            &FixedRandom::new(vec![9, 9]),
        )
        .expect("a");
        let b = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            2,
            &FixedRandom::new(vec![9, 9]),
        )
        .expect("b");
        assert_ne!(a, b);
    }

    #[test]
    fn counter_is_masked_to_6_bits() {
        let a = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            1,
            &FixedRandom::new(vec![9, 9]),
        )
        .expect("a");
        let b = generate_x_bogus(
            "d41d8cd98f00b204e9800998ecf8427e",
            65,
            &FixedRandom::new(vec![9, 9]),
        )
        .expect("b");
        assert_eq!(a, b, "counter & 0x3f，65 应等于 1");
    }

    #[test]
    fn md5_last2_matches_md5_of_decoded_bytes() {
        // msStub 先 hex 解码成 16 字节，再对**这些字节**做 MD5，取 [14]/[15]。
        // d41d8cd9...8427e 解码后 = md5("") 的原始 16 字节摘要；
        // 对那 16 字节再 MD5 -> 59adb24e f3cdbe02 97f05b39 5827453f，其 [14]/[15] = 45 3f。
        // （若误取 md5("") 本身的 [14..16] 会得到 2c f8 —— 那是另一个值。）
        assert_eq!(
            md5_last2("d41d8cd98f00b204e9800998ecf8427e").expect("hex"),
            [0x45, 0x3f]
        );
    }

    #[test]
    fn md5_last2_uses_decoded_bytes_not_hex_string() {
        // 本测试锁定「先 hex 解码」语义：若把 32 字符的 hex 串当字节直接 MD5，
        // 会得到一个不同值。两侧都算一遍，断言**不相等**才说明实现走了解码路径。
        let got = md5_last2("0123456789abcdef0123456789abcdef").expect("hex");
        let wrong = Md5::digest(b"0123456789abcdef0123456789abcdef");
        assert_ne!(
            got,
            [wrong[14], wrong[15]],
            "对 hex 串直接 MD5 是错的：实现必须先 hex 解码"
        );
        // 再正向确认：与「解码后 MD5」一致
        let right = Md5::digest([
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab,
            0xcd, 0xef,
        ]);
        assert_eq!(got, [right[14], right[15]]);
    }

    #[test]
    fn empty_md5_bytes_constant_matches_dart() {
        assert_eq!(EMPTY_MD5_BYTES, [0x45, 0x3f]);
    }

    #[test]
    fn alphabet_lookup_covers_all_64_indices() {
        let mut seen = std::collections::HashSet::new();
        for i in 0..64u8 {
            seen.insert(alphabet_lookup(i));
        }
        assert_eq!(seen.len(), 64, "64 个索引应映射到 64 个不同字符");
    }

    /// 守护「按位置取」而非「按值反查」——写反过一次（见函数注释）。
    #[test]
    fn alphabet_lookup_indexes_by_position() {
        let table: Vec<char> = XBOGUS_ALPHABET.chars().collect();
        for i in 0..64u8 {
            assert_eq!(
                alphabet_lookup(i),
                table[i as usize],
                "索引 {i} 必须取 XBOGUS_ALPHABET[{i}]，而不是反查 STD[{i}] 的位置"
            );
        }
        assert_eq!(alphabet_lookup(0), 'D', "XBOGUS_ALPHABET[0] 应为 'D'");
        assert_eq!(alphabet_lookup(63), 'e', "XBOGUS_ALPHABET[63] 应为 'e'");
    }

    #[test]
    fn encode_base64_handles_short_input_without_panic() {
        // Dart 侧会抛 RangeError；Rust 侧补零不 panic（防御性，实际不触发）
        let out = encode_x_bogus_base64(&[1, 2]);
        assert_eq!(out.chars().count(), 4);
    }
}
