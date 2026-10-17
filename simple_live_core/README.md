# simple_live_core

项目核心库。**协议实现 100% 在 Rust**（`crates/slive-core`），Dart 侧只保留跨平台模型与
FRB 绑定层 —— 不存在并行的 Dart 协议实现（ADR-014）。

## 目录

| 路径 | 内容 |
|------|------|
| `Cargo.toml` / `Cargo.lock` | Rust workspace 根（成员：`slive-core`、`slive-cli`） |
| `crates/slive-core/` | **纯核心 crate**（零 FRB 依赖）：`platforms/{bilibili,douyu,huya,twitch,douyin}`、`tars/`、`ws/`、`http/`、`time/`、`models/` |
| `crates/slive-cli/` | 命令行工具 `slive`：只依赖 `slive-core`，**不经过 FRB** |
| `src/` | FRB 桥层（`api/slive/**`；含既有 `danmaku_mask` 模块）+ `frb_generated.rs` |
| `crates/slive-core/tests/` | 集成测试 + 离线夹具（`tests/fixtures/{platform}/`） |
| `lib/src/rust/` | FRB **Dart 生成物**（已入库） |
| `lib/src/bridge/` | **Dart 绑定层**（`rust_*_site.dart`：FRB 模型 ↔ Dart 模型 1:1 翻译，零协议逻辑） |
| `lib/src/{model,interface}/` | App/TV 消费的跨平台模型与 `LiveSite`/`LiveDanmaku` 契约 |
| `rust_builder/` | cargokit 构建插件（包名 `rust_lib_simple_live_app`，5 平台） |
| `flutter_rust_bridge.yaml` | codegen 配置（`rust_root: .` / `dart_output: lib/src/rust`） |

## 跑测试（无需 Flutter 工具链）

```bash
cd simple_live_core
cargo test                       # 全量（918 用例：lib 486 + 集成 432）
cargo test -p slive-core         # 仅纯核心
cargo test -p slive-cli          # 仅 CLI（URL 解析）
cargo clippy --all-targets       # 静态检查
```

> 已知：`ac_twitch_danmaku`(7) + `ac_twitch_fixtures`(1) 共 8 条因二进制夹具被 CRLF 污染而恒红，
> 根因与修法见 `doc/backlog.md` P0-1。

## 命令行

```bash
cd simple_live_core
cargo build -p slive-cli --release
./target/release/slive info    https://live.bilibili.com/7734200
./target/release/slive danmaku https://live.bilibili.com/6
./target/release/slive help
```

`info` 输出房间详情、全部清晰度与直链（含请求头）；`danmaku` 持续打印弹幕，Ctrl-C 退出。

## 重跑 codegen

改了 `src/api/**` 后，在 `simple_live_core/` 下按 `flutter_rust_bridge.yaml` 生成
（`rust_input: crate::api` 自动扫描）；生成物入库。**两侧版本必须都是 2.13.0**。

## 构建入口

主 App `simple_live_app/` 与 TV app `simple_live_tv_app/` 均以
`path: ../simple_live_core/rust_builder` 依赖 cargokit 插件，共用同一 crate 与同一份生成物；
Dart 侧统一 `import 'package:simple_live_core/simple_live_core.dart'`（绑定层经库出口暴露，
`RustLib.init()` 见 `frb_generated.dart` 出口）。

设计文档见 `docs/rust-core/` 与 `docs/decisions/`（仓库根）；组件知识库见 `doc/`（五件套）；
绑定层边界与迁移决策见 ADR-008 / ADR-014。
