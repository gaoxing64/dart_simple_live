//! AC-42 / IP-7：a_bogus / X-Bogus 的**确定性 golden 断言**。
//!
//! golden 常量由 **Dart 实跑**产出（来源与注入点清单见 `cases.rs` 顶部说明），
//! 本Rust 实现只负责对齐，不参与生成期望值（AC-35「不自证」）。

use super::cases::{ABOGUS_CASES, UA, X_BOGUS_CASES};
use slive_core::error::SliveError;
use slive_core::platforms::douyin::signature::{
    self, a_bogus_deterministic, a_bogus_with, generate_x_bogus, ABogus, FixedClock,
    FixedRandom, XBOGUS_ALPHABET,
};

/// 固定时钟：让 `startEncryption` 与 `endEncryption` 都等于给定毫秒。
///
/// Dart侧是两次 `DateTime.now()`，同进程内通常相同或差几毫秒；
/// 这里让两次读**都**返回固定值，golden 才有确定性。
struct TwoShotClock {
    value: u64,
}

impl signature::SignatureClock for TwoShotClock {
    fn unix_millis(&self) -> u64 {
        self.value
    }
}

#[test]
fn ac42_a_bogus_matches_dart_golden() {
    for case in ABOGUS_CASES {
        let mut bog = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
        let clock = TwoShotClock {
            value: case.start_ms,
        };
        let rnd = FixedRandom::new(case.rd.to_vec());
        // Dart: startEncryption/endEncryption 是两次 now()；golden 记录的是
        // case 指定的 start/end 两次取值。Rust 侧用**可分别指定**的时钟。
        let out = bog
            .generate_with_timestamps(
                case.params,
                case.body,
                case.start_ms,
                case.end_ms,
                &rnd,
            )
            .unwrap_or_else(|e| panic!("[{}] 签名应成功: {e}", case.name));
        assert_eq!(
            out.a_bogus, case.expect,
            "[{}] a_bogus 与 Dart golden 不符",
            case.name
        );
        assert_eq!(
            out.final_params,
            format!("{}&a_bogus={}", case.params, case.expect),
            "[{}] final_params 与 Dart 的 `$params&a_bogus=$abogus` 不符",
            case.name
        );
        assert_eq!(out.user_agent, case.user_agent);
        assert_eq!(out.body, case.body);
        let _ = clock;
    }
}

#[test]
fn ac42_x_bogus_matches_dart_golden() {
    for case in X_BOGUS_CASES {
        let rnd = FixedRandom::new(case.random_bytes.to_vec());
        let got = generate_x_bogus(case.ms_stub, case.counter, &rnd)
            .unwrap_or_else(|e| panic!("[{}] X-Bogus 应生成成功: {e}", case.name));
        assert_eq!(
            got, case.expect,
            "[{}] X-Bogus 与 Dart golden 不符",
            case.name
        );
    }
}

#[test]
fn ac42_x_bogus_output_shape_is_stable() {
    for case in X_BOGUS_CASES {
        let rnd = FixedRandom::new(case.random_bytes.to_vec());
        let got = generate_x_bogus(case.ms_stub, case.counter, &rnd).expect("生成");
        assert_eq!(got.chars().count(), 16, "[{}] X-Bogus 固定 16 字符", case.name);
        assert!(
            got.chars().all(|c| XBOGUS_ALPHABET.contains(c)),
            "[{}] X-Bogus 字符必须来自专用字母表: {got}",
            case.name
        );
        assert!(!got.contains('='), "[{}] X-Bogus 无 padding", case.name);
    }
}

#[test]
fn ac42_a_bogus_is_sensitive_to_every_input() {
    let case = &ABOGUS_CASES[0];
    let base = |mut f: ABogus| -> String {
        let out = f
            .generate_with_timestamps(
                case.params,
                case.body,
                case.start_ms,
                case.end_ms,
                &FixedRandom::new(case.rd.to_vec()),
            )
            .expect("签名");
        out.a_bogus
    };

    let reference = base(ABogus::new(case.user_agent).with_fingerprint(case.fingerprint));

    // 换 params
    let mut f = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let other = f
        .generate_with_timestamps(
            "aid=6383&room_id=999",
            case.body,
            case.start_ms,
            case.end_ms,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "params 应影响签名");

    // 换 UA
    let mut f = ABogus::new("Mozilla/5.0 (X11) Chrome/1").with_fingerprint(case.fingerprint);
    let other = f
        .generate_with_timestamps(
            case.params,
            case.body,
            case.start_ms,
            case.end_ms,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "UA 应影响签名");

    // 换指纹
    let mut f = ABogus::new(case.user_agent).with_fingerprint("1|1|1|1|0|0|0|0|1|1|1|1|1|1|24|24|Win32");
    let other = f
        .generate_with_timestamps(
            case.params,
            case.body,
            case.start_ms,
            case.end_ms,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "指纹应影响签名");

    // 换 body
    let mut f = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let other = f
        .generate_with_timestamps(
            case.params,
            "{\"z\":9}",
            case.start_ms,
            case.end_ms,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "body 应影响签名");

    // 换时间
    let mut f = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let other = f
        .generate_with_timestamps(
            case.params,
            case.body,
            case.start_ms + 1_000,
            case.end_ms + 1_000,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "时间戳应影响签名");

    // 换随机前缀
    let mut f = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let other = f
        .generate_with_timestamps(
            case.params,
            case.body,
            case.start_ms,
            case.end_ms,
            &FixedRandom::new(vec![4321, 8765, 2109]),
        )
        .expect("签名");
    assert_ne!(other.a_bogus, reference, "随机前缀应影响签名");
}

#[test]
fn ac42_start_and_end_timestamps_are_independent() {
    // Dart 的 start/end 是两次独立 now()，本测试锁定二者都进签名
    let case = &ABOGUS_CASES[0];
    let mut same = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let a = same
        .generate_with_timestamps(
            case.params,
            case.body,
            1_700_000_000_000,
            1_700_000_000_000,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("sig");
    let mut diff = ABogus::new(case.user_agent).with_fingerprint(case.fingerprint);
    let b = diff
        .generate_with_timestamps(
            case.params,
            case.body,
            1_700_000_000_000,
            1_700_000_000_500,
            &FixedRandom::new(case.rd.to_vec()),
        )
        .expect("sig");
    assert_ne!(a.a_bogus, b.a_bogus, "endEncryption 变化应改变签名");
}

#[test]
fn ac42_production_entrypoints_are_usable() {
    // 平台侧真实调用形态（不注入时钟/随机源）
    let signed = signature::a_bogus("aid=6383&room_id=1", UA);
    assert!(signed.starts_with("aid=6383&room_id=1&a_bogus="), "{signed}");
    assert!(signed.len() > "aid=6383&room_id=1&a_bogus=".len());

    let sig = signature::x_bogus("d41d8cd98f00b204e9800998ecf8427e", 1).expect("X-Bogus");
    assert_eq!(sig.chars().count(), 16);

    // 便捷注入入口
    let out = a_bogus_with(
        "a=1",
        UA,
        &FixedClock::new(1_700_000_000_000),
        &FixedRandom::new(vec![1, 2, 3]),
    )
    .expect("注入路径应成功");
    assert!(out.a_bogus.ends_with('='));
}

#[test]
fn ac42_repeated_calls_with_system_random_differ() {
    // 生产路径每次都应产出不同签名（随机前缀）
    let a = signature::a_bogus("a=1", UA);
    let b = signature::a_bogus("a=1", UA);
    assert_ne!(a, b, "系统随机源应让每次签名不同");
}

#[test]
fn ac42_x_bogus_rejects_invalid_ms_stub() {
    let err = signature::x_bogus("too-short", 1).expect_err("非法 msStub 应报错");
    assert!(matches!(err, SliveError::InvalidInput(_)), "{err:?}");

    let err = signature::x_bogus("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", 1)
        .expect_err("非 hex 应报错");
    assert!(matches!(err, SliveError::InvalidInput(_)), "{err:?}");
}

/// 平台侧契约入口 `a_bogus_deterministic` 也必须与 Dart golden 一致。
///
/// 该入口把 `random_prefix`（12 字节）与 `now_millis` 都做成入参，
/// 且 start/end 用同一个时间戳 —— 故只有 **start == end** 的用例能对上
/// （Dart 是两次 `DateTime.now()`，多数用例两者差几毫秒）。
#[test]
fn ac42_deterministic_entrypoint_matches_dart_golden() {
    let mut checked = 0;
    for case in ABOGUS_CASES {
        if case.start_ms != case.end_ms {
            continue;
        }
        let got = a_bogus_deterministic(
            case.params,
            case.user_agent,
            case.fingerprint,
            &case.random_prefix,
            case.start_ms,
        )
        .unwrap_or_else(|e| panic!("[{}] 确定性入口应成功: {e}", case.name));
        assert_eq!(
            got,
            format!("{}&a_bogus={}", case.params, case.expect),
            "[{}] a_bogus_deterministic 与 Dart golden 不符",
            case.name
        );
        checked += 1;
    }
    assert!(checked > 0, "至少应有一个 start == end 的用例参与该断言");
}

/// `random_prefix` 为空时退化为系统随机源（生产语义）。
#[test]
fn ac42_deterministic_entrypoint_falls_back_to_system_random() {
    let case = &ABOGUS_CASES[0];
    let a = a_bogus_deterministic(case.params, case.user_agent, case.fingerprint, &[], case.start_ms)
        .expect("应成功");
    let b = a_bogus_deterministic(case.params, case.user_agent, case.fingerprint, &[], case.start_ms)
        .expect("应成功");
    assert_ne!(a, b, "空前缀应走系统随机源，两次结果不同");
    assert!(a.contains("&a_bogus="), "返回值必须含 &a_bogus= 前缀拼接");
}
