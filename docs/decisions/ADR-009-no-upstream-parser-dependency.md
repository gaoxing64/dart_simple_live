# ADR-009: 不将上游 `slive-core-api-rust` 作为依赖，仅对齐其 API 形态

## Status
Accepted (2026-10-16)

## Background
D4 要求「API/模型/接口形态对齐上游 `slive_core`」。上游把平台逻辑放在独立 git crate `SlotSun/slive-core-api-rust`（`crates/platforms-parser`），FRB 薄层在 `slive_core/rust`。看似「直接依赖上游 parser」能省事。

但需要核验（`generated-code-failure-modes §3` 幻觉依赖/接口存在性）：
- 上游 parser 为 git 依赖，存在版本漂移（最新 2026-07-14）；
- 上游 B站**缺**分类 A 列表语义差异、`mcdn` 后置排序（源码 grep 无 `mcdn`）、**表情包解析**（无 `emoticon`）、**账号三接口**（无 `qrcode/account`）——这些是 Dart core 有、必须保留的能力（AC-16 等）；
- 上游提交 `45d401d8 refactor: 手动清理调整ai过度设计的转换接口` 表明其转换层正在被作者清理，直接继承会引入过度设计（R-03）。

（另：上游 `danmaku.rs` **有** zlib+brotli 双分支、`wbi.rs`/`extractor.rs` **有** `w_webid`(access_id) 与 buvid SPI，覆盖度比 briefing 旧结论更好——但不足以覆盖全 B站能力。）

## Decision
- **不**把 `SlotSun/slive-core-api-rust` 或 `slive_core` 作为依赖（不写进 `Cargo.toml`）。
- 仅**对齐其形态**：命名（`live_*`、snake_case、`get_super_chat_messages` 复数）、两层结构、模型概念。
- 协议实现以 **`C:\DTV` 为主参考**（D4）+ **Dart core 为语义基准**（能力不丢）；wbi / buvid / zlib+brotli / WS 帧编解码均**自实现**（可参照 DTV 的函数逐条对照，见 `12-bilibili-mapping.md`）。
- 对上游源码仅作「查漏参考」（如 zlib 分支、w_webid 的签名参数），不作为构建依赖。

## Consequences
**正面**
- 无跨仓 git 依赖与版本漂移；构建可复现、离线可测。
- 规避上游过度设计与覆盖度缺口；能力集合由 Dart core 契约确定（AC-30/AC-16）。
- 分层与命名仍与上游一致（D4），后续可对照。

**负面**
- 需自行实现 B站协议（wbi/buvid/WS/表情包/账号），实现量大于「直接依赖」；但这是 D1「DTV 有 2298 行现成实现可逐函数对照」的既定路径。
- 若上游后续补齐能力，需人工比对是否回填（记入 backlog）。

## Related ADRs
ADR-001（结构）、ADR-007（模型）；risks R-01/R-03
