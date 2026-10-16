# ADR-002: FRB 精确钉 2.13.0，复用现有工程，生成代码入库

## Status
Accepted (2026-10-16)

## Background
D6 定 `flutter_rust_bridge = 2.13.0`（与仓库既有 `simple_live_app/rust/` 一致；上游 slive_core 用 2.12.0，不采用）。现有 FRB 资产：`simple_live_app/flutter_rust_bridge.yaml`（`rust_input: crate::api` / `rust_root: rust/` / `dart_output: lib/src/rust`）、`rust_builder/`（cargokit，5 平台）、生成代码 `rust/src/frb_generated.rs` 与 `lib/src/rust/**`（当前已入库）。`pubspec.yaml` 现写 `flutter_rust_bridge: ^2.13.0`（caret）。

## Decision
1. Rust 侧 `flutter_rust_bridge = "=2.13.0"`（精确）；Dart 侧由 `^2.13.0` **改为 `2.13.0`**（精确）。
2. **复用**现有 `flutter_rust_bridge.yaml` 与 `rust_builder`，不新建第二套 FFI 插件；新 API 放 `src/api/slive/**`，由 `rust_input: crate::api` 自动扫描。
3. 代码生成用与运行库**完全一致**的 `flutter_rust_bridge_codegen 2.13.0`；生成物**入库**。
4. 遵守 Dart SDK 下限：FRB 2.13.0 需 Dart ≥ 3.9.2（App 钉 Flutter 3.47.6）。

## Consequences
**正面**
- 两侧版本一致，规避 `RustLib.init()` 因版本漂移静默抛异常（依据：fluttercandies/fjs CHANGELOG）。
- 一个原生库、一套 rust_builder，构建链路最短。
- 生成物入库：可评审、可复现、可对生成物 diff。

**负面**
- codegen 版本成为团队硬约束（须与运行库精确对齐）；升级需两侧同步。
- 每次改 API 需重跑 codegen 并提交生成物，增加 diff 体量（可接受）。
- 本机需装 3.47.6（briefing §6 记录本机或仅 3.47.5）。

## Related ADRs
ADR-001（结构）、ADR-007（模型暴露）
