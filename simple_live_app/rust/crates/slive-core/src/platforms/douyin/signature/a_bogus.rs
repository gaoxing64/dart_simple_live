//! a_bogus 签名（逐字节移植 Dart `simple_live_core/lib/src/platforms/douyin/abogus.dart`）。
//!
//! # 与 Dart 的对应关系
//! | Rust | Dart |
//! |---|---|
//! | [`ABogus::generate`] | `ABogus.generateAbogus` |
//! | [`SignatureClock`]（毫秒） | `DateTime.now().millisecondsSinceEpoch` |
//! | [`RandomSource`] | `Random()`（`generateRandomBytes` 的 rd 来源） |
//! | [`tables::BIG_ARRAY`] | `CryptoUtility.bigArray` |
//! | [`transform::random_prefix`] | `StringProcessor.generateRandomBytes` |
//!
//! # ⚠️ 有状态：不要跨请求复用
//! 与 Dart 一致，[`ABogus::generate`] 会**原地修改** `self.big_array`
//! （Dart 的 `CryptoUtility.bigArray` 也是实例字段，被 `transformBytes` 改写）。
//! Dart 侧 `DouyinUtils.buildRequestUrl` 每次请求都 `ABogus(...)` 新建实例，
//! 故线上语义等价于「每次都用新表」。Rust 侧同理：**每个请求新建一个 `ABogus`**。

use crate::error::SliveError;

use super::clock::SignatureClock;
use super::crypto::{base64_encode, rc4};
use super::random::RandomSource;
use super::sm3::sm3;
use super::tables::{
    BIG_ARRAY, CHARACTER2, DEFAULT_AID, DEFAULT_BROWSER_FP, DEFAULT_OPTIONS, DEFAULT_PAGE_ID,
    DEFAULT_USER_AGENT, SALT, SORT_INDEX, SORT_INDEX2, UA_KEY,
};

/// a_bogus 签名器。字段与 Dart `ABogus` 的**可变**部分一一对应。
///
/// Dart 侧`aid` / `page_id` / `salt` / `paths` / `track` 等是 `final` 常量，
/// 其中只有 `aid`、`page_id`、`salt` 会经`abDir` 影响字节，
/// 其余（`paths`/`track`/`dump`/`rpU`）只存在于 Dart 的 `abDir[15]`，
/// 而 `sortIndex` / `sortIndex2` **从不读取** `abDir[15]`（已核对两个表的 44 项），
/// 故 Rust 侧不落这些字段。
#[derive(Debug, Clone)]
pub struct ABogus {
    pub(super) user_agent: String,
    pub(super) browser_fp: String,
    pub(super) options: [u32; 3],
    pub(super) aid: u32,
    pub(super) page_id: u32,
    pub(super) salt: String,
    pub(super) big_array: [u8; 256],
}

/// a_bogus 的输出（对齐 Dart `generateAbogus` 返回的 4 元组）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ABogusOutput {
    /// `"$params&a_bogus=$abogus"`（Dart 元组第 0 项）—— 拼 URL 用这个。
    pub final_params: String,
    /// 裸 `a_bogus` 值，不含 `a_bogus=` 前缀（Dart 元组第 1 项）。
    pub a_bogus: String,
    /// 本次签名使用的 UA（Dart 元组第 2 项）。
    pub user_agent: String,
    /// 本次签名使用的 body（Dart 元组第 3 项）。
    pub body: String,
}

impl Default for ABogus {
    fn default() -> Self {
        Self::new(DEFAULT_USER_AGENT)
    }
}

impl ABogus {
    /// 用指定 UA 构造。UA 为空则回落到 Dart `ABogus` 的默认 Edge UA。
    #[must_use]
    pub fn new(user_agent: &str) -> Self {
        let ua = if user_agent.is_empty() {
            DEFAULT_USER_AGENT
        } else {
            user_agent
        };
        Self {
            user_agent: ua.to_string(),
            browser_fp: DEFAULT_BROWSER_FP.to_string(),
            options: DEFAULT_OPTIONS,
            aid: DEFAULT_AID,
            page_id: DEFAULT_PAGE_ID,
            salt: SALT.to_string(),
            big_array: BIG_ARRAY,
        }
    }

    /// 覆盖浏览器指纹（对齐 Dart `ABogus(fp: ...)`）。
    #[must_use]
    pub fn with_fingerprint(mut self, fp: &str) -> Self {
        if !fp.is_empty() {
            self.browser_fp = fp.to_string();
        }
        self
    }

    /// 覆盖固定参数（对齐 Dart `ABogus(options: ...)`）。
    #[must_use]
    pub fn with_options(mut self, options: [u32; 3]) -> Self {
        self.options = options;
        self
    }

    /// 当前 UA。
    #[must_use]
    pub fn user_agent(&self) -> &str {
        &self.user_agent
    }

    /// 当前浏览器指纹。
    #[must_use]
    pub fn browser_fp(&self) -> &str {
        &self.browser_fp
    }

    /// 生成 a_bogus（对齐 Dart `generateAbogus(params, body: body)`）。
    ///
    /// 时钟会被读两次（Dart 同样前后各取一次 `DateTime.now()`），
    /// 分别写入 `startEncryption` 与 `endEncryption`。
    ///
    /// # Errors
    /// 仅在内部字母表常量被破坏时返回 [`SliveError::Decode`]
    /// （`CHARACTER` / `CHARACTER2` 长度不足 64，不应发生）。
    pub fn generate(
        &mut self,
        params: &str,
        body: &str,
        clock: &dyn SignatureClock,
        random: &dyn RandomSource,
    ) -> Result<ABogusOutput, SliveError> {
        // Dart 分两次取 now()，这里同样读两次（同一时钟实现下值可能相同）。
        let start_ms = clock.unix_millis();
        self.generate_with_timestamps(params, body, start_ms, clock.unix_millis(), random)
    }

    /// 补齐 `abDir[44..60]`（endEncryption / pageId / aid），产出待序列化的码元序列。
    pub(super) fn sorted_values(&self, dir: &[u32; 72], end_ms: u64) -> Vec<u16> {
        let mut d = *dir;

        d[44] = ((end_ms >> 24) & 255) as u32;
        d[45] = ((end_ms >> 16) & 255) as u32;
        d[46] = ((end_ms >> 8) & 255) as u32;
        d[47] = (end_ms & 255) as u32;
        d[48] = d[8];
        d[49] = super::transform::js_shift_right(end_ms, 32) as u32;
        d[50] = super::transform::js_shift_right(end_ms, 40) as u32;

        d[51] = (self.page_id >> 24) & 255;
        d[52] = (self.page_id >> 16) & 255;
        d[53] = (self.page_id >> 8) & 255;
        d[54] = self.page_id & 255;
        d[55] = self.page_id;
        d[56] = self.aid;
        d[57] = self.aid & 255;
        d[58] = (self.aid >> 8) & 255;
        d[59] = (self.aid >> 16) & 255;
        d[60] = (self.aid >> 24) & 255;

        let mut out: Vec<u16> = SORT_INDEX.iter().map(|&i| d[i] as u16).collect();
        out.extend(self.browser_fp.encode_utf16());
        out.push(xor_checksum(&d));
        out
    }

    /// Dart `paramsToArray(paramsToArray(x))`：**加盐 SM3 -> 再对结果字节 SM3**。
    ///
    /// 注意第二次调用时入参已是 `List<int>`，Dart 的 `processParam` 只对
    /// `String` 加盐，故第二次**不再加盐**。
    pub(super) fn double_sm3(&self, input: &str) -> [u32; 32] {
        let first = sm3(format!("{input}{}", self.salt).as_bytes());
        let second = sm3(&first);
        std::array::from_fn(|i| u32::from(second[i]))
    }

    /// Dart `paramsToArray(base64Encode(rc4(uaKey, userAgent)), addSalt: false)`。
    ///
    /// 三个易错点：
    /// 1. UA 按 **UTF-16 码元**参与 RC4（Dart `String.fromCharCodes`），不是 UTF-8 字节；
    /// 2. 用**第二**字母表 `character2`（`selectedAlphabet: 1`）；
    /// 3. 此处 `addSalt: false` —— **不加盐**。
    pub(super) fn ua_digest(&self) -> [u32; 32] {
        let ua_units: Vec<u16> = self.user_agent.encode_utf16().collect();
        let units: Vec<u16> = rc4(&UA_KEY, &ua_units).into_iter().map(u16::from).collect();
        let encoded = base64_encode(&units, CHARACTER2).unwrap_or_default();
        let digest = sm3(encoded.as_bytes());
        std::array::from_fn(|i| u32::from(digest[i]))
    }
}

/// Dart 的 `abXor`：`sortIndex2` 对应的 `abDir` 值做 XOR（首项直接赋值，其余异或）。
pub(super) fn xor_checksum(d: &[u32; 72]) -> u16 {
    let mut xor = 0u32;
    for (i, &idx) in SORT_INDEX2.iter().enumerate() {
        let v = d[idx];
        if i == 0 {
            xor = v;
        } else {
            xor ^= v;
        }
    }
    xor as u16
}
