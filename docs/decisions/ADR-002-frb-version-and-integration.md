# ADR-002: FRB 精确钉 2.13.0，复用现有工程，生成代码入库

## Status
Accepted (2026-10-16) — **2026-10-17 修订**：FRB 资产随 Rust workspace 一并迁入
`simple_live_core/`（见 ADR-001 二次迁移记录）；版本钉禁与生成物入库的决策不变。

## Background
D6 定 `flutter_rust_bridge = 2.13.0`（与仓库既有 `simple_live_core/` 一致；上游 slive_core 用 2.12.0，不采用）。FRB 资产现位于 `simple_live_core/`：`flutter_rust_bridge.yaml`（`rust_input: crate::api` / `rust_root: .` / `dart_output: lib/src/rust`）、`rust_builder/`（cargokit，5 平台）、生成代码 `src/frb_generated.rs` 与 `lib/src/rust/**`（已入库）。`pubspec.yaml` 写 `flutter_rust_bridge: 2.13.0`（精确）。（2026-10-17 前位于 `simple_live_app/`，`rust_root: ../simple_live_core`；迁移记于 ADR-001。）

## Decision
1. Rust 侧 `flutter_rust_bridge = "=2.13.0"`（精确）；Dart 侧 `2.13.0`（精确）。
2. **一套** FRB 配置与 cargokit 插件（现均在 `simple_live_core/`），主 App 与 TV app 共用；新 API 放 `src/api/slive/**`，由 `rust_input: crate::api` 自动扫描。
3. 代码生成用与运行库**完全一致**的 `flutter_rust_bridge_codegen 2.13.0`；生成物**入库**（重跑入口：`cd simple_live_core` 后按 `flutter_rust_bridge.yaml` 生成）。
4. 遵守 Dart SDK 下限：FRB 2.13.0 需 Dart ≥ 3.9.2（App 钉 Flutter 3.47.6；TV 钉 3.35.7 = Dart 3.9）。

## Consequences
**正面**
- 两侧版本一致，规避 `RustLib.init()` 因版本漂移静默抛异常（依据：fluttercandies/fjs CHANGELOG）。
- 一个原生库、一套 rust_builder，构建链路最短。
- 生成物入库：可评审、可复现、可对生成物 diff。

**负面**
- codegen 版本成为团队硬约束（须与运行库精确对齐）；升级需两侧同步。
- 每次改 API 需重跑 codegen 并提交生成物，增加 diff 体量（可接受）。
- 本机需装 3.47.6（briefing §6 记录本机或仅 3.47.5）。
- TV app 钉 Flutter 3.35.7（Dart 3.9）：FRB 2.13.0 生成物与 `flutter_rust_bridge` 运行库在 TV 侧
  未经完整真机回归前，属「已分析、已构建（Android）」状态；Windows 侧受 VS 生成器环境限制未本地验证。

## Related ADRs
ADR-001（结构）、ADR-007（模型暴露）、ADR-014（绑定层下沉与 TV 迁移）
