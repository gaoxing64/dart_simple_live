# simple_live_core

项目核心库，实现获取各个网站的信息及弹幕。

> **目录结构说明（2026-10-17 起）**：本目录同时承载 **Rust Core**（新建）与**原 Dart 核心包**
> （过渡期保留 = 回退目标）。长期目标：逐步精简 Dart 部分，本目录成为纯 Rust 项目。

## Rust Core（`slive-core`）

| 路径 | 内容 |
|------|------|
| `Cargo.toml` / `Cargo.lock` | Rust workspace 根（FRB 桥 crate `rust_lib_simple_live_app`） |
| `src/` | FRB 桥层（`api/slive/**`；含既有 `danmaku_mask` 模块） |
| `crates/slive-core/` | **纯核心 crate**（零 FRB 依赖）：`platforms/{bilibili,douyu,huya,twitch,douyin}`、`tars/`、`ws/`、`http/`、`time/`、`models/` |
| `tests/` | 集成测试 + 离线夹具（`tests/fixtures/{platform}/`） |

**跑测试**（独立于 App，无需 Flutter 工具链）：

```bash
cd simple_live_core
cargo test                       # 全量（slive-core + 桥）
cargo test -p slive-core         # 仅纯核心
cargo clippy --all-targets       # 静态检查
```

构建入口在 App 侧：`simple_live_app/`（`rust_builder/` = cargokit 胶水，路径已指向本目录）。

设计文档见 `docs/rust-core/` 与 `docs/decisions/`（仓库根）。

## Dart 包（过渡期保留）

`lib/` + `pubspec.yaml` 为原 Dart 核心实现，当前作为 Rust Core 的**运行时回退目标**
（`simple_live_app/lib/app/sites.dart` 的开关可一键切回）；逐步精简，最终移除。
