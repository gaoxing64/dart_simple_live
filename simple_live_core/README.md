# simple_live_core

项目核心库。本目录同时承载 **Rust Core**（`slive-core` + FRB 桥）与**原 Dart 核心包**
（`lib/`，过渡期保留，见下）。

## Rust Core（`slive-core`）

| 路径 | 内容 |
|------|------|
| `Cargo.toml` / `Cargo.lock` | Rust workspace 根（FRB 桥 crate `rust_lib_simple_live_app`） |
| `src/` | FRB 桥层（`api/slive/**`；含既有 `danmaku_mask` 模块） |
| `crates/slive-core/` | **纯核心 crate**（零 FRB 依赖）：`platforms/{bilibili,douyu,huya,twitch,douyin}`、`tars/`、`ws/`、`http/`、`time/`、`models/` |
| `tests/` | 集成测试 + 离线夹具（`tests/fixtures/{platform}/`） |
| `lib/src/rust/` | FRB **Dart 生成物**（`frb_generated.*` + `api/**`，已入库） |
| `lib/src/bridge/` | **Dart 绑定层**（`rust_*_site.dart`：FRB 模型 ↔ Dart core 模型 1:1 翻译，零协议逻辑） |
| `rust_builder/` | cargokit 构建插件（包名 `rust_lib_simple_live_app`，5 平台） |
| `flutter_rust_bridge.yaml` | codegen 配置（`rust_root: .` / `dart_output: lib/src/rust`） |

**跑测试**（独立于 App，无需 Flutter 工具链）：

```bash
cd simple_live_core
cargo test                       # 全量（slive-core + 桥）
cargo test -p slive-core         # 仅纯核心
cargo clippy --all-targets       # 静态检查
```

**重跑 codegen**（改了 `src/api/**` 后）：在 `simple_live_core/` 下按 `flutter_rust_bridge.yaml`
生成（`rust_input: crate::api` 自动扫描）；生成物入库。

**构建入口**：主 App `simple_live_app/` 与 TV app `simple_live_tv_app/` 均以
`path: ../simple_live_core/rust_builder` 依赖 cargokit 插件，共用同一 crate 与同一份生成物；
Dart 侧统一 `import 'package:simple_live_core/simple_live_core.dart'`（绑定层经库出口暴露，
`RustLib.init()` 见 `frb_generated.dart` 出口）。

设计文档见 `docs/rust-core/` 与 `docs/decisions/`（仓库根）；绑定层边界与迁移决策见
ADR-008 / ADR-014。

## Dart 包（过渡期保留）

`lib/` + `pubspec.yaml` 为原 Dart 核心实现。**已不再是回退目标**（运行时开关已移除，ADR-008
回退窗口关闭）：App 与 TV 均已直连 Rust 绑定层；Twitch Dart 平台已删（消费者归零）。

现存部分（bilibili/douyin/douyu/huya 四平台 Dart 实现 + common 工具 + tars/proto）**仅为
`simple_live_console`（纯 Dart 调试 CLI）保留**——console 迁移至 Rust 后整包删除
（ADR-014 决策 4）。
