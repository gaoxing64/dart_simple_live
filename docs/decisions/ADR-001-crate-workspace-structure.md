# ADR-001: 采用 cargo workspace（纯核心 crate `slive-core` + FRB 桥 crate）

## Status
Accepted (2026-10-16)

## Background
本轮要把 Dart `simple_live_core` 的 B站能力迁到 Rust，桥接用 flutter_rust_bridge 2.13.0（D6）。仓库现有唯一 Rust 工程是 `simple_live_core/`（crate `rust_lib_simple_live_app`，含 `api/danmaku_mask.rs`），由 `rust_builder/` 经 cargokit 构建（`cargokit { manifestDir = "../../rust"; libname = "rust_lib_simple_live_app" }`）。需求明确要求「**支持未来 Flutter 之外的 Tauri 等前端复用**」；D4 要求 API/模型形态对齐上游 `slive_core`（其为「独立平台解析 crate + FRB 薄 crate」两层结构）。

需在「单 crate」「workspace 两层」「直接依赖上游 crate」之间选择。

## Decision
把 `simple_live_core/` 升级为 **cargo workspace**：
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

## 迁移记录（2026-10-17）
**已执行"预留迁移路径"**（用户决策：为扩大规模测试与项目管理，且长期只保留 Rust core）：

- workspace 从 `simple_live_app/rust/` **迁至 `simple_live_core/`**（Rust 根 = `simple_live_core/Cargo.toml`；
  纯核心 crate 在 `simple_live_core/crates/slive-core/`）。
- cargokit 的 6 处路径（windows/linux CMake、android gradle `manifestDir`、ios/macos podspec、
  `flutter_rust_bridge.yaml` 的 `rust_root`）已同步更新 —— 即本次迁移**打破了本 ADR 原文的
  "零改动"承诺**（原承诺的前提是 workspace 不动）。
- **Dart 包（`simple_live_core/lib` + `pubspec.yaml`）过渡期原位保留**（回退目标，AC-34）；
  逐步精简后该目录即纯 Rust 项目。`simple_live_core/src`（Rust 桥）与 `simple_live_core/lib`
  （Dart）并存无工具链冲突。
- 验证：独立目录 `cargo test` 909 passed / 0 failed（新增归属）；`flutter build windows --release` rc=0
  （cargokit 全链路）。

## 二次迁移记录（2026-10-17 ·「全面采用 Rust core」）

回退窗口结束（用户决策：清理 Dart core、全面采用 Rust core），FRB 资产整体并入本目录：

- **FRB 配置与生成物迁入**：`simple_live_app/flutter_rust_bridge.yaml` → `simple_live_core/`
  （`rust_root: .` / `dart_output: lib/src/rust`）；生成代码 `simple_live_app/lib/src/rust/**` →
  `simple_live_core/lib/src/rust/**`（git mv 保历史；`frb_generated.rs` 无硬编码路径，无需重跑 codegen）。
- **cargokit 插件迁入**：`simple_live_app/rust_builder/` → `simple_live_core/rust_builder/`
  （包名 `rust_lib_simple_live_app` 不变；windows CMake 的 7 级相对路径以 `.plugin_symlinks` 为基准，
  与源码位置无关；android `manifestDir = ../../../simple_live_core` 新旧位置同为仓库根下两级，解析不变）。
  主 App 与 TV app 均以 `path: ../simple_live_core/rust_builder` 依赖，共用同一 crate 与同一份生成物。
- **Dart 绑定层下沉**：`simple_live_app/lib/services/rust_core/**` → `simple_live_core/lib/src/bridge/**`，
  由 `simple_live_core.dart` 出口暴露；同库出口 `frb_generated.dart`（`RustLib`）与 `api/danmaku_mask.dart`
  （`DanmakuMask`）。**不出口** FRB `api/slive/error.dart` 的 `CoreError`——与 Dart core
  `common/core_error.dart` 同名，双导出会使同时引用两处的平台文件编译期歧义（douyin_site 实测），
  消费方按需深导入（App `analysis_options` 对 `implementation_imports` 置 ignore）。
- **运行时开关移除**：`Constant.kUseRust*` 五个开关与 `sites.dart` 二元分派删除，五平台直连绑定层
  （ADR-008 回退窗口关闭）；TV app 同步直连并补 `RustLib.init()`。
- **Dart core 清理（受 console 保留制约）**：`lib/src/platforms/twitch/` 整删（消费者归零）；
  其余 4 平台 Dart 实现、common 工具、tars/proto/emoticon **保留**——`simple_live_console`
  （纯 Dart CLI）仍走 Dart 路径，其 SDK 约束（`<3.0.0`）与本包（`>=3.0.5`）已冲突、当前本就无法
  `pub get`，待下轮迁移后随 console 一并整删。
- 验证：主 App `flutter build windows --release` rc=0；app/core/tv 三包 `flutter analyze` 0 error。
  TV Windows 本地构建受环境限制（TV 钉 Flutter 3.35.7，其工具链默认 VS2019 生成器，本机仅装 VS18）
  ——与本次改动无关，改由 TV Android 构建验证 cargokit 路径。

## Related ADRs
ADR-002（FRB 集成）、ADR-007（模型暴露）、ADR-009（不依赖上游 parser）
