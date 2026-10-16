//! AC-42 / IP-7：抖音签名（a_bogus / X-Bogus）确定性 golden 断言。
//!
//! 本文件是测试入口，实际内容拆到同目录：
//! - [`cases`]：golden 用例定义（**由 Dart 实跑产出**）+ 注入点清单
//! - [`golden`]：golden 逐字节比对 + 输入敏感度守护
//! - [`invariants`]：SM3 标准向量（Dart 实测）+ 常量表维度守护
//!
//! 基准：`simple_live_core/lib/src/platforms/douyin/abogus.dart`（732 行）
//! 与 `xbogus.dart`（133 行）。

#[path = "ac_douyin_signature/cases.rs"]
mod cases;

#[path = "ac_douyin_signature/golden.rs"]
mod golden;

#[path = "ac_douyin_signature/invariants.rs"]
mod invariants;
