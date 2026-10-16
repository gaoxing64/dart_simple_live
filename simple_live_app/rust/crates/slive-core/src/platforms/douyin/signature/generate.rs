//! `ABogus` 的三个生成入口（从 `a_bogus.rs` 拆出，单文件行数门禁 <= 300）。
//!
//! 三者的差别只在**非确定性来源怎么来**：
//! - [`generate`](ABogus::generate)：时钟 + 随机源都走 trait（生产路径）；
//! - [`generate_with_timestamps`](ABogus::generate_with_timestamps)：时间戳入参、随机走 trait；
//! - [`generate_with_prefix`](ABogus::generate_with_prefix)：时间戳 + 随机前缀都入参（golden）。

use crate::error::SliveError;

use super::a_bogus::{ABogus, ABogusOutput};
use super::random::RandomSource;
use super::tables::CHARACTER;
use super::transform::{encode_signature, encode_signature_with_prefix};

impl ABogus {
    /// 生成 a_bogus，显式指定 `startEncryption` / `endEncryption`（确定性路径）。
    ///
    /// Dart 用两次 `DateTime.now().millisecondsSinceEpoch`，二者通常相同或相差几毫秒。
    /// 该入口把两个时间戳变成入参，供 golden 测试精确复现 Dart 的某次真实取值。
    ///
    /// # Errors
    /// 见 [`ABogus::generate`]。
    pub fn generate_with_timestamps(
        &mut self,
        params: &str,
        body: &str,
        start_ms: u64,
        end_ms: u64,
        random: &dyn RandomSource,
    ) -> Result<ABogusOutput, SliveError> {
        let dir = self.build_dir(params, body, start_ms);
        let sorted = self.sorted_values(&dir, end_ms);
        let mut big = self.big_array;
        let abogus = encode_signature(&sorted, || random.next_below_10000(), &mut big, CHARACTER)
            .ok_or_else(|| SliveError::decode("a_bogus: CHARACTER 字母表长度不足 64"))?;
        self.big_array = big;

        Ok(ABogusOutput {
            final_params: format!("{params}&a_bogus={abogus}"),
            a_bogus: abogus,
            user_agent: self.user_agent.clone(),
            body: body.to_string(),
        })
    }

    /// 生成 a_bogus，**时间戳与随机前缀都由调用方给定**（完全确定性）。
    ///
    /// `prefix` 是 a_bogus 的随机前缀码元序列（Dart 侧为 12 个），
    /// 长度不受限 —— 直接前置到混淆结果之前，与 Dart 的
    /// `generateRandomBytes() + transformBytes(...)` 拼接顺序一致。
    ///
    /// # Errors
    /// 见 [`ABogus::generate`]。
    pub fn generate_with_prefix(
        &mut self,
        params: &str,
        body: &str,
        start_ms: u64,
        end_ms: u64,
        prefix: &[u16],
    ) -> Result<ABogusOutput, SliveError> {
        let dir = self.build_dir(params, body, start_ms);
        let sorted = self.sorted_values(&dir, end_ms);
        let mut big = self.big_array;
        let abogus =
            encode_signature_with_prefix(&sorted, prefix, &mut big, CHARACTER).ok_or_else(|| {
                SliveError::decode("a_bogus: CHARACTER 字母表长度不足 64")
            })?;
        self.big_array = big;

        Ok(ABogusOutput {
            final_params: format!("{params}&a_bogus={abogus}"),
            a_bogus: abogus,
            user_agent: self.user_agent.clone(),
            body: body.to_string(),
        })
    }

    /// 组装 `abDir`（Dart 的 `Map<int, dynamic>`）中**参与序列化**的部分。
    ///
    /// Dart 未显式赋值且未被 `sortIndex`/`sortIndex2` 读取的键按 `?? 0` 处理，
    /// 这里用 `[u32; 72]` 定长数组 + 显式写入对齐。
    /// `abDir[15]`（Map）与 `abDir[19]`（List）在 Dart 里是给 `abDir` 自身用的
    /// 「配置快照」，两个 sort 表都不含 15/19，故保持 0。
    fn build_dir(&self, params: &str, body: &str, start_ms: u64) -> [u32; 72] {
        let mut d = [0u32; 72];
        d[8] = 3;
        d[18] = 44;
        d[66] = 0;
        d[69] = 0;
        d[70] = 0;
        d[71] = 0;

        // abDir[20..25]：startEncryption 的 4 字节 + 两次 `>>> 32` / `>>> 40`
        d[20] = ((start_ms >> 24) & 255) as u32;
        d[21] = ((start_ms >> 16) & 255) as u32;
        d[22] = ((start_ms >> 8) & 255) as u32;
        d[23] = (start_ms & 255) as u32;
        d[24] = super::transform::js_shift_right(start_ms, 32) as u32;
        d[25] = super::transform::js_shift_right(start_ms, 40) as u32;

        // abDir[26..29]：options[0] 的大端 4 字节
        d[26] = (self.options[0] >> 24) & 255;
        d[27] = (self.options[0] >> 16) & 255;
        d[28] = (self.options[0] >> 8) & 255;
        d[29] = self.options[0] & 255;

        // abDir[30..33]：options[1] 的**小端前两字节 + 大端高两字节**（照抄 Dart 原式）
        d[30] = (self.options[1] / 256) & 255;
        d[31] = (self.options[1] % 256) & 255;
        d[32] = (self.options[1] >> 24) & 255;
        d[33] = (self.options[1] >> 16) & 255;

        // abDir[34..37]：options[2] 的大端 4 字节
        d[34] = (self.options[2] >> 24) & 255;
        d[35] = (self.options[2] >> 16) & 255;
        d[36] = (self.options[2] >> 8) & 255;
        d[37] = self.options[2] & 255;

        // abDir[38..43]：三组 SM3 摘要的指定字节
        let array1 = self.double_sm3(params);
        let array2 = self.double_sm3(body);
        let array3 = self.ua_digest();
        d[38] = array1[21];
        d[39] = array1[22];
        d[40] = array2[21];
        d[41] = array2[22];
        d[42] = array3[23];
        d[43] = array3[24];

        // abDir[64]/[65]：指纹长度（Dart 用 `String.length`，即 UTF-16 码元数）
        let fp_len = self.browser_fp.encode_utf16().count() as u32;
        d[64] = fp_len;
        d[65] = fp_len;
        d
    }
}
