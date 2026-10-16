//! 抖音签名（a_bogus / X-Bogus），逐字节对齐 Dart `simple_live_core/lib/src/platforms/douyin/`。
//!
//! 唯一行为基准：`abogus.dart`（732 行）+ `xbogus.dart`（133 行）。
//! golden 由 **Dart 实跑**产出（见 `tests/ac_douyin_signature.rs`），不是自证。
//!
//! # 平台侧调用契约
//!
//! ```ignore
//! use slive_core::platforms::douyin::signature;
//!
//! // a_bogus：拼 URL（返回已带 `a_bogus=` 的 query 串）
//! let query: &str = /* 已 URL 编码的 query 串 */;
//! let signed = signature::a_bogus(query, signature::DEFAULT_USER_AGENT);
//! let url = format!("{base_url}?{signed}");
//!
//! // X-Bogus：WS 握手
//! let sig = signature::x_bogus(md5_hex, 1)?;
//! ```
//!
//! # 必填参数
//! - **a_bogus**：`params` 必须是**已编码**的完整 query 串（空格 -> `+`），
//!   且**末尾不能**已有 `a_bogus=`；UA 必须与实际 HTTP 请求头里的 UA 一致，
//!   否则服务端校验失败（a_bogus 的 `abDir[42]/[43]` 绑定了 UA 的 SM3）。
//! - **X-Bogus**：`ms_stub` 必须是 **32 字符 md5 小写 hex**；
//!   `counter` 固定传 1（对齐 Dart `douyin_danmaku.dart:229`）。
//!
//! # 依赖方向
//! 本模块是**纯计算**（无 HTTP、无 WS），只依赖 `crate::error`，
//! 可被 FRB / Tauri 等任意前端复用，且不依赖 flutter_rust_bridge（ADR-001）。

pub mod a_bogus;
pub mod generate;
#[cfg(test)]
mod a_bogus_tests;
pub mod clock;
pub mod crypto;
pub mod random;
pub mod sm3;
pub mod tables;
pub mod transform;
pub mod x_bogus;
#[cfg(test)]
mod x_bogus_tests;

pub use a_bogus::{ABogus, ABogusOutput};
pub use transform::encode_signature_with_prefix;
pub use clock::{FixedClock, SignatureClock, SystemClock};
pub use random::{FixedRandom, RandomSource, SystemRandom};
pub use tables::{
    CHARACTER, CHARACTER2, DEFAULT_AID, DEFAULT_BROWSER_FP, DEFAULT_OPTIONS, DEFAULT_PAGE_ID,
    DEFAULT_USER_AGENT, EMPTY_MD5_BYTES, SALT, STANDARD_ALPHABET, UA_KEY, XBOGUS_ALPHABET,
};
pub use x_bogus::generate_x_bogus;

/// 生成 a_bogus，返回**已带 `a_bogus=` 前缀**的 query 串（可直接拼 URL）。
///
/// 内部使用系统时钟 + 系统随机源（生产路径）。
/// `params` 必须是已 URL 编码的完整 query 串；`user_agent` 必须与请求头 UA 一致。
#[must_use]
pub fn a_bogus(params: &str, user_agent: &str) -> String {
    let clock = SystemClock;
    let random = SystemRandom::new();
    match ABogus::new(user_agent).generate(params, "", &clock, &random) {
        Ok(out) => out.final_params,
        // 字母表常量被破坏才会走到；此时返回一个可诊断但必然被拒的串，
        // 不 panic（panic 会连带崩掉上层 HTTP 链路）。
        Err(err) => {
            log::error!("a_bogus 生成失败: {err}");
            format!("{params}&a_bogus=")
        }
    }
}

/// 生成 a_bogus（显式注入时钟与随机源 trait，确定性路径）。
///
/// golden 测试与需要复现的场景用这个；线上用 [`a_bogus`]。
///
/// # Errors
/// 见 [`ABogus::generate`]。
pub fn a_bogus_with(
    params: &str,
    user_agent: &str,
    clock: &dyn SignatureClock,
    random: &dyn RandomSource,
) -> Result<ABogusOutput, crate::error::SliveError> {
    ABogus::new(user_agent).generate(params, "", clock, random)
}

/// 生成 a_bogus —— **平台侧与 golden 统一入口**（显式注入指纹 / 随机前缀 / 时间戳）。
///
/// 与 [`a_bogus`] 的唯一差别是把三个非确定性来源变成入参，因此可复现。
/// 返回值语义与 Dart `generateAbogus(...).first` 一致：
/// **`"原query&a_bogus=XXXX"`**（已含 `&a_bogus=` 前缀拼接）。
///
/// # 参数
/// - `query`：已 URL 编码的完整 query 串，**末尾不能已有 `a_bogus=`**；
/// - `user_agent`：必须与实际 HTTP 请求头 UA 完全一致（a_bogus 绑定了 UA 的 SM3）；
/// - `browser_fp`：浏览器指纹；传空则用 [`DEFAULT_BROWSER_FP`]；
/// - `random_prefix`：a_bogus 的 12 字节随机前缀；**传空则用系统随机源**；
/// - `now_millis`：Unix 毫秒时间戳，同时用作 `startEncryption` 与 `endEncryption`
///   （Dart 是两次 `DateTime.now()`，同进程内通常相同）。
///
/// # Errors
/// 仅在内部字母表常量被破坏时返回 [`SliveError::Decode`](crate::error::SliveError::Decode)。
pub fn a_bogus_deterministic(
    query: &str,
    user_agent: &str,
    browser_fp: &str,
    random_prefix: &[u8],
    now_millis: u64,
) -> Result<String, crate::error::SliveError> {
    let mut signer = ABogus::new(user_agent).with_fingerprint(browser_fp);
    let out = if random_prefix.is_empty() {
        signer.generate(query, "", &FixedClock::new(now_millis), &SystemRandom::new())?
    } else {
        let prefix: Vec<u16> = random_prefix.iter().map(|b| u16::from(*b)).collect();
        signer.generate_with_prefix(query, "", now_millis, now_millis, &prefix)?
    };
    Ok(out.final_params)
}

/// 生成 X-Bogus（生产路径，系统随机源），返回裸签名串（16 字符）。
///
/// # Errors
/// `ms_stub` 不是 32 字符 md5 hex 时返回 `InvalidInput`。
pub fn x_bogus(ms_stub: &str, counter: u32) -> Result<String, crate::error::SliveError> {
    generate_x_bogus(ms_stub, counter, &SystemRandom::new())
}

/// 生成 X-Bogus（显式注入随机源，确定性路径）。
///
/// # Errors
/// 同 [`x_bogus`]。
pub fn x_bogus_with(
    ms_stub: &str,
    counter: u32,
    random: &dyn RandomSource,
) -> Result<String, crate::error::SliveError> {
    generate_x_bogus(ms_stub, counter, random)
}