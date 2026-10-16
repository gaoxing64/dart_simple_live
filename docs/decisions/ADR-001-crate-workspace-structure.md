# ADR-001: 采用 cargo workspace（纯核心 crate `slive-core` + FRB 桥 crate）

## Status
Accepted (2026-10-16)

## Background
本轮要把 Dart `simple_live_core` 的 B站能力迁到 Rust，桥接用 flutter_rust_bridge 2.13.0（D6）。仓库现有唯一 Rust 工程是 `simple_live_app/rust/`（crate `rust_lib_simple_live_app`，含 `api/danmaku_mask.rs`），由 `rust_builder/` 经 cargokit 构建（`cargokit { manifestDir = "../../rust"; libname = "rust_lib_simple_live_app" }`）。需求明确要求「**支持未来 Flutter 之外的 Tauri 等前端复用**」；D4 要求 API/模型形态对齐上游 `slive_core`（其为「独立平台解析 crate + FRB 薄 crate」两层结构）。

需在「单 crate」「workspace 两层」「直接依赖上游 crate」之间选择。

## Decision
把 `simple_live_app/rust/` 升级为 **cargo workspace**：
- 新增纯核心 crate `crates/slive-core`（**不依赖 FRB**）：承载 `http/ws/error/models/platforms/bilibili`；
- 现 crate `rust_lib_simple_live_app` **原地保留作 FRB 桥**，新增 `src/api/slive/**`；
- 依赖单向：桥 → core。

命名：core crate `slive-core`（lib `slive_core`），模型/函数对齐上游 `live_*`/snake_case 风格；桥 crate 名不变以复用 cargokit。

## Consequences
**正面**
- `slive-core` 可被 Tauri/CLI 以 path/git 依赖直接复用，且不带入 FRB；符合 briefing 附录 A-1。
- cargokit / rust_builder / `flutter_rust_bridge.yaml` **零改动**，回归面最小（AC-30）。
- 两层结构与上游同构，符合 D4，便于后续平台照搬。

**负面**
- 多一个 crate（workspace 成员），Cargo.toml 与依赖声明各多一份。
- 跨 crate 模型暴露需要 `#[frb(mirror)]`（见 ADR-007），比单 crate 略繁琐。
- 若未来多 Flutter 前端共享，还需把 workspace 迁到仓库根并让 `simple_live_core` 承载 bindings（已留迁移路径）。

## Related ADRs
ADR-002（FRB 集成）、ADR-007（模型暴露）、ADR-009（不依赖上游 parser）
