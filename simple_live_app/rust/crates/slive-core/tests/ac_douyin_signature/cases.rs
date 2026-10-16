//! AC-42 / IP-7：抖音签名（a_bogus / X-Bogus）确定性 golden 断言。
//!
//! # golden 来源（**非自证**）
//! golden 常量由 **Dart 实跑**产出，流程可复现：
//!
//! 1. 取 Dart SDK（本机 `fvm` 缓存的 3.9.2）；
//! 2. 用脚本把 `abogus.dart` / `xbogus.dart` 复制成 patched 副本，
//!    **只替换 3 处非确定性注入点**（`Random()` / `DateTime.now()`），
//!    其余字节不改 —— 脚本会打印 unified diff 供审计；
//! 3. patched 副本 + 本文件 `CASES` 里的入参跑一次，把输出记为 golden。
//!
//! 也就是说：期望值来自 **Dart 实现的真实输出**，本Rust 实现只负责对齐，
//! 不参与生成期望值。注入点清单：
//!
//! | Dart 位置 | 原表达式 | 替换为 |
//! |---|---|---|
//! | `abogus.dart:21` | `Random().nextInt(10000)` | `goldenRd()`（固定序列） |
//! | `abogus.dart:645` | `DateTime.now().millisecondsSinceEpoch` | `goldenStartMs()` |
//! | `abogus.dart:659` | `DateTime.now().millisecondsSinceEpoch` | `goldenEndMs()` |
//! | `xbogus.dart:92-95` | `Random.secure().nextInt(...)` | `goldenRandomByte()` |
//!
//! 浏览器指纹走 Dart `ABogus(fp: ...)` 构造参数注入（原生支持，未改代码）。
//!
//! # 覆盖的用例
//! - 4 组 a_bogus：常规 query / 带 body / 空 params / 大指纹 + 百分号编码中文 + 非 ASCII UA
//! - 4 组 X-Bogus：不同 msStub / counter / 随机字节

use slive_core::platforms::douyin::signature::DEFAULT_USER_AGENT;

/// Dart 实跑使用的默认 UA（= `DouyinRequestParams.kDefaultUserAgent`）。
pub const UA: &str = DEFAULT_USER_AGENT;

/// 非 ASCII 平台 UA（覆盖 Mac UA 分支）。
pub const UA_MAC: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";

pub struct AbogusGolden {
    pub name: &'static str,
    pub params: &'static str,
    pub user_agent: &'static str,
    pub fingerprint: &'static str,
    pub body: &'static str,
    pub start_ms: u64,
    pub end_ms: u64,
    /// 3 个 rd（每次签名消耗 3 个，Dart `generateRandomBytes(length: 3)`）。
    pub rd: [u32; 3],
    /// 由 `rd` 展开出的 12 字节随机前缀（等价于 Dart `generateRandomBytes()` 的输出）���
    pub random_prefix: [u8; 12],
    /// Dart 实跑输出的裸 a_bogus 值。
    pub expect: &'static str,
}

/// golden 常量。Dart 实跑产出，**实现者不得修改**（AC-35「不自证」）。
pub const ABOGUS_CASES: &[AbogusGolden] = &[
    AbogusGolden {
        name: "case1_webcast_room",
        params: "aid=6383&device_platform=web&room_id=123456789&update_version_code=170400&compress=gzip",
        user_agent: UA,
        fingerprint: "1920|1080|1920|1040|0|30|0|0|1872|92|1920|1040|1857|92|1|24|Win32",
        body: "",
        start_ms: 1_700_000_000_123,
        end_ms: 1_700_000_000_456,
        rd: [1234, 5678, 9012],
        random_prefix: [131, 82, 5, 44, 43, 6, 7, 60, 33, 22, 39, 41],
        expect: "E7mhBdu2krjihxWT56KLfY3q6VM3Y8/I0SVkMD2fodvcqL39HMTa9exoIBGvXyujZsmfIFYjy4hbO3xprQAjM36UHWwEUdQ2mgWkKl5Q5I0j53iruyRDntmF4vj3SFlm5XNAEOk0y75rKb70Woqe-vIlO62-zo0/95m=",
    },
    AbogusGolden {
        name: "case2_with_body",
        params: "aweme_type=0&room_id=987654321&count=20",
        user_agent: UA,
        fingerprint: "1280|720|1280|800|0|0|0|0|1280|720|1280|720|1280|720|24|24|Win32",
        body: r#"{"aweme_id":"1234567890"}"#,
        start_ms: 1_712_345_678_901,
        end_ms: 1_712_345_678_999,
        rd: [777, 4242, 3133],
        random_prefix: [9, 3, 7, 41, 131, 18, 5, 56, 41, 23, 13, 44],
        expect: "df8ZQR8Vk3EThjyu5VKLfY3q6XRhY8/n0SVkMD2fvYGcWL39HMY79exo/sTvKifjZsmfIFujy4hbYNQprQ2n01wfHuix/25ZmDSkKl5Q5xSSs1XJtyUgntsNmktUCec2-i-lrOXMw7lHKREk09oHmhK4bIOwu3GMSj==",
    },
    AbogusGolden {
        name: "case3_empty_params",
        params: "",
        user_agent: UA,
        fingerprint: "800|600|800|660|0|30|0|0|800|600|800|600|800|600|24|24|Win32",
        body: "",
        start_ms: 1_690_000_000_000,
        end_ms: 1_690_000_000_000,
        rd: [0, 1, 2],
        random_prefix: [1, 2, 5, 40, 1, 3, 5, 40, 3, 2, 5, 40],
        expect: "DfmhQDgpkVEpDE6Y5lCLfY3q6fe3Y8/O0SVkMD2fvxvcWL39HMYD9exoamsvKY8jZsmfIYWjy4hJYpPMiO5jA37vHmJLWoaBmDSdt-P2so0jR1vruygmrsJP-kb3tlaQsvrlEKiBq7lHFmG0AIeedjppPESF",
    },
    AbogusGolden {
        name: "case4_large_fp_and_unicode",
        params: "keyword=%E6%8A%96%E9%9F%B3&msToken=aBcDeF1234567890&count=50",
        user_agent: UA_MAC,
        fingerprint: "2560|1440|2560|1510|0|30|0|0|2560|1440|2560|1510|2560|1400|24|24|MacIntel",
        body: "",
        start_ms: 1_750_000_000_123,
        end_ms: 1_750_000_000_789,
        rd: [5535, 1024, 33],
        random_prefix: [139, 23, 5, 61, 1, 2, 5, 44, 33, 3, 5, 40],
        expect: "xJWhMfgdkVjiDj6Y5ldLfY3q6-l3Ypk30SVkMD2fwnvcQL39HMTa9exobHzvb4RjZsmfIFmjy4haT3nprQAy836UHuXLUdQ2s6mkKl5Q5I0j53iruy60nzDF-vT-SaBm-kBlrOXmqwlHFmSZAnAn5hoUbfebYrtswrgECiqL13fINE==",
    },
];

pub struct XBogusGolden {
    pub name: &'static str,
    pub ms_stub: &'static str,
    pub counter: u32,
    /// [random1, random2]，Dart 侧分别是 `nextInt(256)` / `nextInt(255)`。
    pub random_bytes: [u32; 2],
    pub expect: &'static str,
}

/// golden 常量（Dart 实跑产出）。
pub const X_BOGUS_CASES: &[XBogusGolden] = &[
    XBogusGolden {
        name: "x1",
        ms_stub: "d41d8cd98f00b204e9800998ecf8427e",
        counter: 1,
        random_bytes: [0x41, 0x7f],
        expect: "f1CpNb7LVQAWG7w4",
    },
    XBogusGolden {
        name: "x2",
        ms_stub: "5d41402abc4b2a76b9719d911017c592",
        counter: 2,
        random_bytes: [0xff, 0x0d],
        expect: "1jxOUkjYScpIzbGp",
    },
    XBogusGolden {
        name: "x3",
        ms_stub: "0123456789abcdef0123456789abcdef",
        counter: 0,
        random_bytes: [0x00, 0x03],
        expect: "fD0JYipRk1vCBScq",
    },
    XBogusGolden {
        name: "x4",
        ms_stub: "ffffffffffffffffffffffffffffffff",
        counter: 63,
        random_bytes: [0x9c, 0xfe],
        expect: "1MV8hJc1lIlw14JY",
    },
];

/// golden 用例的入参合法性（防止再次写进越界值）。
///
/// `rd` 必须落在 `[0, 10000)` —— Dart 是 `Random().nextInt(10000)`。
/// 一旦越界，Rust 侧会做取模而 Dart 侧不会，golden 就失去意义
/// （本项目实际踩过：`65535` / `31337` 两个越界值曾导致 2/4 用例假失败）。
#[test]
fn ac42_golden_inputs_are_within_dart_range() {
    for case in ABOGUS_CASES {
        for &rd in &case.rd {
            assert!(
                rd < 10_000,
                "[{}] rd={rd} 越界：Dart Random().nextInt(10000) 只产生 [0,10000)",
                case.name
            );
        }
        assert!(!case.name.is_empty());
        assert!(!case.params.contains("a_bogus="), "params 不能已含 a_bogus");
    }
    for case in X_BOGUS_CASES {
        assert_eq!(
            case.ms_stub.len(),
            32,
            "[{}] msStub 必须是 32 字符",
            case.name
        );
        for &b in &case.random_bytes {
            assert!(
                b <= 255,
                "[{}] random2 越界说明注入值不合法",
                case.name
            );
        }
    }
}
