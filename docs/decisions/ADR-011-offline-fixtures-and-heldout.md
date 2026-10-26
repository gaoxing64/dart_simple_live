# ADR-011: 离线夹具采用「录制 + 合成 + MockTransport 注入 + held-out 留出集」

## Status
Accepted (2026-10-16)

## Background
AC-01~AC-21 需要**机器可验证**（夹具输入 → 期望输出），AC-35/AC-36 要求证据由实现者改不动、并含**实现者不可见**的留出集，AC-38 要求真实命令输出、抗 flaky。但 core 现有 B站离线用例仅表情包 31 条，其余 B站请求/解码**零覆盖**，且无历史抓包（`11-scope-and-acceptance.md` RISK-07）。

Dart core 的测试策略是「注入 `HttpClientAdapter` 跑离线测试」（`simple_live_core/doc/architecture.md §3.3`）；上游 slive_core 依赖独立 `platforms-parser` 的既有测试。二者都不能直接解决「本轮从零建 B站夹具」。

## Decision
1. 夹具统一放 `crates/slive-core/tests/fixtures/bilibili/`，分三类：HTTP 响应 `.json`、WS 帧 `.bin`（含期望产出 `.json`）、确定性 golden（内联常量）。
2. 来源：**录制**（`#[ignore]` 一次性脚本 `tests/record_{http,ws}.rs`，仅手动联网跑，产品路径不联网）+ **合成**（边界/错误夹具手工构造）。
3. **注入**：`http::HttpClient` 抽象为 trait `HttpTransport`（默认 `ReqwestTransport`；测试 `MockTransport` 按 URL 返回夹具）；`ws::session` 事件源抽象，测试注入预置帧序列。这与 Dart core 的 adapter 注入同构。
4. **安全**：录制/夹具**不得**含 cookie/credential（NFR 安全项）。
5. **held-out**：`tests/fixtures/bilibili/heldout/` 由 QA 提供、实现者不可见；`cargo test --features heldout` 单独判定（AC-36）。
6. 覆盖清单（每个 AC 至少一条夹具）见 `10-architecture.md §8.4(e)`。

## Consequences
**正面**
- AC 全部可机械验证，且抗 flaky（不依赖墙钟/网络）。
- 实现者不可见留出集，防止「特判可见用例」（AC-36 反作弊）。
- 抽象出的 `HttpTransport` 让核心层可脱离 FRB 在桌面 `cargo test`，无需真机。

**负面**
- 需一次性录制脚本与合成夹具的初期投入（约覆盖 15 个端点 + WS 帧集）。
- 网络受限环境下录制需择机（合成夹具可先行，不阻塞）。

## Related ADRs
ADR-003（HTTP 层）、ADR-009（不依赖上游测试）
