# Slive 当前架构（2026-10-28）

面向开发者的当前状态架构说明。所有结论以代码、依赖清单与 ADR 为依据，证据逐条列在 [`system-model.evidence.md`](./system-model.evidence.md)。

## 阅读顺序

1. 先看 [`system-context.dot`](./system-context.dot)：系统边界、用户、外部平台与外部服务。
2. 再看 [`system-containers.dot`](./system-containers.dot)：Dart 表现层 → 绑定层 → FRB → Rust 核心 → 外部平台的运行时关系。
3. 需要核对依据时看 [`system-model.evidence.md`](./system-model.evidence.md)（含置信度与未知项）。

两个 `.dot` 可直接在 Qoder Canvas 打开。本地渲染需要 Graphviz：

```bash
cd docs/architecture
dot -Tsvg system-context.dot -o system-context.svg
dot -Tsvg system-containers.dot -o system-containers.svg
```

## 一句话架构

**Slive 是一个“Flutter 多端 UI + 纯 Dart 契约包 + 纯 Rust 协议核心”的直播聚合客户端。** 五个平台的协议全部在 `crates/slive-core`；Dart 只保留模型、接口契约和无协议逻辑的绑定层；两者通过 `flutter_rust_bridge 2.13.0` 连接，非 Dart 宿主通过 `slive-ffi` 的 C ABI 复用同一核心。

## 分层

```
Flutter App / TV App / CLI / 未来 C++·C# 宿主
        │
        ├── simple_live_app / simple_live_tv_app     GetX + Hive + media_kit
        │
        ├── simple_live_core (Dart)                  LiveSite 契约 + 模型 + 绑定层
        │        │
        │        └── FRB 2.13.0（生成物入库）
        │                 │
        └─────────────────┴── Rust workspace
                               ├── 根 crate rust_lib_simple_live_app   FRB 门面
                               ├── crates/slive-core                 协议 / 模型 / 纯逻辑
                               ├── crates/slive-host                 WSS / TCP 真实连接
                               ├── crates/slive-ffi                  C ABI
                               └── crates/slive-cli                  slive CLI
```

依赖方向单向向下：`bridge → api（FRB 门面） → slive-host → slive-core`；`slive-core` 不依赖 FRB、Flutter 或任何宿主，也不持真实连接。

## 关键机制

- **平台接入**：`simple_live_app/lib/app/sites.dart` 与 TV 端同名文件单点注册，直接构造 `RustBilibiliSite` / `RustDouyuSite` / `RustHuyaSite` / `RustDouyinSite` / `RustTwitchSite`；不再有 Dart 协议实现或运行时开关（ADR-014）。
- **弹幕**：Rust 侧持有长连接，经 FRB `StreamSink<LiveDanmuItem>` 推送 `Message | Control(Ready/Closed/...)`；心跳与 5s×5 重连留在 Rust，Dart 只订阅 Stream（ADR-004）。
- **错误**：`SliveError`（thiserror）→ FRB `CoreError{message,status_code}` → Dart `CoreError`，业务错误码不自动重试（ADR-006）。
- **播放**：`media_kit`（自定义 fork + 预编译 libmpv）；斗鱼的 300 秒短效直链由 `StreamRelayService` 在本地做 HTTP 中转与 FLV tag 边界续接。
- **测试 seam**：`HttpTransport` / `TimeSource` / `FrameSource` 三个注入点，离线夹具 + held-out 留出集，使心跳/重连/签名可在桌面 `cargo test` 验证（ADR-011）。

## 维护提示

- 修改包边界、crate 成员、外部依赖或跨层关系时，同步更新两张图与证据文件。
- `docs/rust-core/10-architecture.md` 与 `simple_live_core/doc/architecture.md` 是阶段性文档，个别结论已被 ADR-014 / ADR-016 取代（证据文件 §5 已标注）。
