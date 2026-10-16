//! 四平台夹具加载辅助（QA 产出，与 B站的 `common` 并列，不改动它）。
//!
//! 抽出来是为了让每个平台的测试文件守住 **单文件 ≤ 300 行** 的门禁：
//! 四个平台需要同样的「定位目录 / 读文本 / 读字节 / 取样本」能力，
//! 各写一份会把每个文件推到 400~600 行。
//!
//! 与 B站 `tests/common/mod.rs` 的区别：这里**不构造任何平台对象**，
//! 只做夹具 IO。因此 IP-x agent 正在改平台函数签名时，
//! 引用本模块的测试文件不会连带编译失败。
#![allow(dead_code)]

pub mod tars;

use std::path::PathBuf;

use serde_json::Value;

/// 定位 `tests/fixtures/<platform>` 目录。
pub fn fixtures_dir(platform: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!("tests/fixtures/{platform}"))
}

/// 读文本夹具。
pub fn read_text(platform: &str, rel: &str) -> String {
    let path = fixtures_dir(platform).join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 读二进制夹具。
pub fn read_bytes(platform: &str, rel: &str) -> Vec<u8> {
    let path = fixtures_dir(platform).join(rel);
    std::fs::read(&path).unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 解析并返回 `http/http-samples.json`。
pub fn http_samples(platform: &str) -> Value {
    serde_json::from_str(&read_text(platform, "http/http-samples.json"))
        .unwrap_or_else(|e| panic!("解析 {platform}/http-samples.json 失败: {e}"))
}

/// 取某端点样本。
pub fn sample(platform: &str, key: &str) -> Value {
    let doc = http_samples(platform);
    doc["samples"][key].clone()
}

/// 列出 `ws/` 下所有 `.expected.json` 的文件名（已排序，保证用例顺序稳定）。
pub fn ws_expected_files(platform: &str) -> Vec<String> {
    let dir = fixtures_dir(platform).join("ws");
    let mut names: Vec<String> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("读取 {platform}/ws 目录失败: {e}"))
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.ends_with(".expected.json"))
        .collect();
    names.sort();
    names
}

/// 校验 `.expected.json` 里`bytes_hex` 与真实 `.bin` 逐字节一致。
///
/// 防止「改了期望值却没改帧」或反之——两者不一致时无法判断哪个是真值，
/// 此时整个夹具不可信。
pub fn assert_hex_matches_bin(platform: &str, stem: &str, doc: &Value) {
    let bytes = read_bytes(platform, &format!("ws/{stem}.bin"));
    let hex = doc["bytes_hex"].as_str().expect("bytes_hex");
    let parsed: Vec<u8> = hex
        .split_whitespace()
        .map(|t| u8::from_str_radix(t, 16).expect("hex 字节"))
        .collect();
    assert_eq!(parsed, bytes, "{stem} 的 bytes_hex 与 .bin 不一致");
    assert_eq!(
        doc["bytes_len"].as_u64().expect("bytes_len") as usize,
        bytes.len(),
        "{stem} 的 bytes_len 与实际长度不符"
    );
}

/// 校验一份 `.expected.json` 的 `_meta` 必填字段（团队硬约束）。
pub fn assert_ws_meta(platform: &str, name: &str, doc: &Value) {
    let meta = &doc["_meta"];
    assert_eq!(meta["platform"], platform, "{name} 的 platform 不符");
    assert_eq!(meta["synthetic"], true, "{name} 缺 _meta.synthetic");
    assert_eq!(
        meta["needs_realtime_validation"], true,
        "{name} 缺 needs_realtime_validation 标记"
    );
    assert!(
        meta["derivation"].as_str().is_some_and(|v| !v.is_empty()),
        "{name} 缺 derivation（须写明推导依据）"
    );
    assert!(
        meta["target_rust_fn"].as_str().is_some_and(|v| !v.is_empty()),
        "{name} 缺 target_rust_fn"
    );
    assert!(
        !meta["target_ac"].as_array().expect("target_ac 是数组").is_empty(),
        "{name} 缺 target_ac"
    );
    // 客户端请求帧（kind=ws-client-request）只锁字节，无 expected 产出段；
    // 待裁决帧（assertion=PENDING_QA_DECISION）按纪律不写期望值。
    // 其余服务端帧必须有 messages。
    if meta["kind"].as_str() == Some("ws-client-request") {
        assert!(
            meta["direction"].as_str() == Some("client->server"),
            "{name} 缺 direction=client->server"
        );
    } else if doc["expected"]["assertion"].as_str() == Some("PENDING_REAL_CAPTURE") {
        // 行为口径已裁决、但期望值仍等真实抓包的夹具：messages 保持 null，
        // 且必须已登记裁决结论（ruling）——不允许「未裁决的占位」。
        assert!(
            doc["expected"]["messages"].is_null(),
            "{name} 的期望值待抓包，messages 必须为 null（不得伪装成已断言）"
        );
        assert_eq!(meta["decision_pending"], true, "{name} 缺 decision_pending 标记");
        assert!(
            doc["expected"]["ruling"].as_str().is_some_and(|r| !r.is_empty()),
            "{name} 的行为口径必须已给出裁决（ruling）"
        );
    } else {
        assert!(
            doc["expected"]["messages"].is_array(),
            "{name} 的 expected.messages 不是数组"
        );
    }
}

/// 校验一批 HTTP 样本的元数据（`synthetic` / `dart_source` / `field_sources` / `target_ac`）。
pub fn assert_http_samples_meta(platform: &str) -> usize {
    let doc = http_samples(platform);
    let samples = doc["samples"].as_object().expect("samples 是对象");
    for (key, s) in samples {
        assert_eq!(s["synthetic"].as_bool(), Some(true), "样本 {key} 缺 synthetic");
        assert!(
            s["dart_source"].as_str().is_some_and(|v| !v.is_empty()),
            "样本 {key} 缺 dart_source（字段必须能对上 Dart 解析行号）"
        );
        assert!(
            !s["field_sources"]
                .as_object()
                .expect("field_sources 是对象")
                .is_empty(),
            "样本 {key} 的 field_sources 为空—— 等于没有推导依据"
        );
        assert!(
            !s["target_ac"].as_array().expect("target_ac 是数组").is_empty(),
            "样本 {key} 缺 target_ac"
        );
    }
    assert_eq!(doc["_meta"]["platform"], platform);
    assert_eq!(doc["_meta"]["synthetic"], true);
    assert!(doc["_meta"]["derivation"].as_str().is_some_and(|v| !v.is_empty()));
    assert_eq!(doc["_meta"]["needs_realtime_validation"], true);
    samples.len()
}

/// 独立 MD5（RFC 1321）。
///
/// 为什么不复用 crate 里的签名实现：golden 的价值在于「期望值由**独立于被测实现**的
/// 算法重算得出」（AC-35）。把一份 MD5 放在测试侧，既满足「不新增依赖」的硬约束，
/// 也让「实现算错、golden 也一起错」的同源失效不可能发生。
/// 只求正确，不追求性能。
pub fn md5_hex(input: &str) -> String {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613,
        0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
        0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
        0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
        0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244,
        0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb,
        0xeb86d391,
    ];

    let mut msg = input.as_bytes().to_vec();
    let bit_len = (msg.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    let (mut a0, mut b0, mut c0, mut d0) =
        (0x67452301u32, 0xefcdab89u32, 0x98badcfeu32, 0x10325476u32);

    for chunk in msg.as_chunks::<64>().0 {
        let mut m = [0u32; 16];
        for (i, word) in m.iter_mut().enumerate() {
            *word = u32::from_le_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        let (mut a, mut b, mut c, mut d) = (a0, b0, c0, d0);
        for i in 0..64 {
            let (f, g) = match i / 16 {
                0 => ((b & c) | (!b & d), i),
                1 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                2 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };
            let tmp = d;
            d = c;
            c = b;
            let sum = a
                .wrapping_add(f)
                .wrapping_add(K[i])
                .wrapping_add(m[g]);
            b = b.wrapping_add(sum.rotate_left(S[i]));
            a = tmp;
        }
        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }

    let mut out = String::with_capacity(32);
    for w in [a0, b0, c0, d0] {
        for byte in w.to_le_bytes() {
            out.push_str(&format!("{byte:02x}"));
        }
    }
    out
}