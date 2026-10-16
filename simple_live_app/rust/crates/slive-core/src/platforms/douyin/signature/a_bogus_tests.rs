#[cfg(test)]
mod tests {
    //! `a_bogus` 的单元测试（从 `a_bogus.rs` 拆出，单文件行数门禁 <= 300）。

    use crate::platforms::douyin::signature::a_bogus::{ABogus, xor_checksum};
    use crate::platforms::douyin::signature::clock::FixedClock;
    use crate::platforms::douyin::signature::random::FixedRandom;
    use crate::platforms::douyin::signature::tables::{DEFAULT_BROWSER_FP, DEFAULT_USER_AGENT};
    use crate::platforms::douyin::signature::ABogusOutput;


    fn sign(params: &str, body: &str, millis: u64, rnd: Vec<u32>) -> ABogusOutput {
        let mut bog = ABogus::new(DEFAULT_USER_AGENT);
        bog.generate(params, body, &FixedClock::new(millis), &FixedRandom::new(rnd))
            .expect("签名应成功")
    }

    #[test]
    fn default_ua_falls_back_when_empty() {
        assert_eq!(ABogus::new("").user_agent(), DEFAULT_USER_AGENT);
    }

    #[test]
    fn with_fingerprint_ignores_empty() {
        let bog = ABogus::new(DEFAULT_USER_AGENT).with_fingerprint("");
        assert_eq!(bog.browser_fp(), DEFAULT_BROWSER_FP);
    }

    #[test]
    fn with_fingerprint_overrides() {
        let bog = ABogus::new(DEFAULT_USER_AGENT).with_fingerprint("1|2|3|Win32");
        assert_eq!(bog.browser_fp(), "1|2|3|Win32");
    }

    #[test]
    fn generate_is_deterministic_for_fixed_clock_and_random() {
        let a = sign("aid=6383&room_id=1", "", 1_700_000_000_123, vec![1234, 5678, 9012]);
        let b = sign("aid=6383&room_id=1", "", 1_700_000_000_123, vec![1234, 5678, 9012]);
        assert_eq!(a.a_bogus, b.a_bogus);
        assert_eq!(a.final_params, b.final_params);
    }

    #[test]
    fn final_params_is_params_plus_prefixed_bogus() {
        let out = sign("a=1", "", 1_700_000_000_000, vec![1, 2, 3]);
        assert_eq!(out.final_params, format!("a=1&a_bogus={}", out.a_bogus));
        assert_eq!(out.user_agent, DEFAULT_USER_AGENT);
        assert_eq!(out.body, "");
    }

    #[test]
    fn body_is_echoed_back() {
        let out = sign("a=1", "{\"k\":1}", 1_700_000_000_000, vec![1, 2, 3]);
        assert_eq!(out.body, "{\"k\":1}");
    }

    #[test]
    fn output_ends_with_base64_padding() {
        let out = sign("a=1", "", 1_700_000_000_000, vec![1, 2, 3]);
        assert!(
            out.a_bogus.ends_with('='),
            "a_bogus 应带 base64 padding，实际 {}",
            out.a_bogus
        );
    }

    #[test]
    fn differs_when_random_changes() {
        let a = sign("a=1", "", 1_700_000_000_000, vec![1, 1, 1]);
        let b = sign("a=1", "", 1_700_000_000_000, vec![2, 2, 2]);
        assert_ne!(a.a_bogus, b.a_bogus, "随机前缀应影响签名");
    }

    #[test]
    fn differs_when_time_changes() {
        let a = sign("a=1", "", 1_700_000_000_000, vec![7, 7, 7]);
        let b = sign("a=1", "", 1_800_000_000_000, vec![7, 7, 7]);
        assert_ne!(a.a_bogus, b.a_bogus, "时间戳应参与签名");
    }

    #[test]
    fn differs_when_ua_changes() {
        let mut a = ABogus::new(DEFAULT_USER_AGENT);
        let mut b = ABogus::new("Mozilla/5.0 (Macintosh) Safari/605.1.15");
        let clock = FixedClock::new(1_700_000_000_000);
        let rnd = FixedRandom::new(vec![7, 7, 7]);
        let o1 = a.generate("a=1", "", &clock, &rnd).expect("gen a");
        let o2 = b.generate("a=1", "", &clock, &rnd).expect("gen b");
        assert_ne!(o1.a_bogus, o2.a_bogus, "a_bogus 必须绑定 UA");
    }

    #[test]
    fn differs_when_body_changes() {
        let a = sign("a=1", "", 1_700_000_000_000, vec![7, 7, 7]);
        let b = sign("a=1", "{\"x\":1}", 1_700_000_000_000, vec![7, 7, 7]);
        assert_ne!(a.a_bogus, b.a_bogus, "body 应参与签名");
    }

    #[test]
    fn differs_when_fingerprint_changes() {
        let clock = FixedClock::new(1_700_000_000_000);
        let rnd = FixedRandom::new(vec![7, 7, 7]);
        let mut a = ABogus::new(DEFAULT_USER_AGENT);
        let mut b = ABogus::new(DEFAULT_USER_AGENT).with_fingerprint("1|1|1|1|0|0|0|0|1|1|1|1|1|1|24|24|Win32");
        let o1 = a.generate("a=1", "", &clock, &rnd).expect("gen a");
        let o2 = b.generate("a=1", "", &clock, &rnd).expect("gen b");
        assert_ne!(o1.a_bogus, o2.a_bogus, "指纹应参与签名");
    }

    #[test]
    fn reuse_across_calls_changes_result_like_dart() {
        // Dart 的 bigArray 是实例字段、被 transformBytes 原地改写，
        // 因此同一实例连续两次签名结果不同（除非随机前缀恰好一致）。
        let clock = FixedClock::new(1_700_000_000_000);
        let mut bog = ABogus::new(DEFAULT_USER_AGENT);
        let o1 = bog
            .generate("a=1", "", &clock, &FixedRandom::new(vec![5, 5, 5]))
            .expect("gen 1");
        let o2 = bog
            .generate("a=1", "", &clock, &FixedRandom::new(vec![5, 5, 5]))
            .expect("gen 2");
        assert_ne!(o1.a_bogus, o2.a_bogus, "复用实例应体现 bigArray 的状态变化");
    }

    #[test]
    fn fresh_instances_agree() {
        let clock = FixedClock::new(1_700_000_000_000);
        let mut a = ABogus::new(DEFAULT_USER_AGENT);
        let mut b = ABogus::new(DEFAULT_USER_AGENT);
        let o1 = a
            .generate("a=1", "", &clock, &FixedRandom::new(vec![5, 5, 5]))
            .expect("gen a");
        let o2 = b
            .generate("a=1", "", &clock, &FixedRandom::new(vec![5, 5, 5]))
            .expect("gen b");
        assert_eq!(o1.a_bogus, o2.a_bogus);
    }

    #[test]
    fn empty_params_is_handled() {
        let out = sign("", "", 1_700_000_000_000, vec![0, 1, 2]);
        assert!(!out.a_bogus.is_empty());
        assert_eq!(out.final_params, format!("&a_bogus={}", out.a_bogus));
    }

    #[test]
    fn unicode_params_are_handled() {
        let out = sign("keyword=%E6%8A%96%E9%9F%B3", "", 1_700_000_000_000, vec![1, 2, 3]);
        assert!(!out.a_bogus.is_empty());
    }

    #[test]
    fn xor_checksum_uses_first_index_as_seed() {
        let mut d = [0u32; 72];
        d[18] = 44; // sortIndex2[0]
        d[20] = 0xAB;
        assert_eq!(xor_checksum(&d), 44 ^ 0xAB);
    }
}
