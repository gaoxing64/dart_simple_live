# ADR-004: 弹幕推送采用 FRB StreamSink + 控制事件枚举

## Status
Accepted (2026-10-16)

## Background
Dart core 的 `LiveDanmaku` 是**回调式**：`onMessage/onClose/onReady` + 内部心跳 + 5s×5 重连（`web_socket_util.dart`）。迁移到 Rust 后，Rust→Dart 的推送方式有三选：FRB `StreamSink<T>`、Dart 回调（`DartFn`）、轮询 `receive() -> Option<T>`。上游 slive_core 用轮询（Dart 侧 `_receiveLoop` 循环调 `receive`）。

需求：既要在 Flutter 侧好用，又要让 Tauri 侧能复用同一事件源；且 AC-26/AC-28 要求断线重连与脏帧容错的行为可断言。

## Decision
Rust→Dart 采用 **FRB `StreamSink<LiveDanmuItem>`**；事件为枚举以承载控制流：

```rust
pub enum LiveDanmuItem { Message(LiveMessage), Control(LiveDanmuControlEvent) }
pub enum LiveDanmuControlEvent { Ready, Reconnecting{ attempt:u32 }, Closed{ reason:String } }
pub fn connect(room_id, cookies, danmaku_data) -> impl Stream<Item=LiveDanmuItem> + Send
pub fn disconnect(conn:&LiveDanmuConnection)
```

- 心跳（60s）、重连（5s×5）、帧解码全部在 Rust（`ws/session.rs`）；**不暴露 `heartbeat()` 给 Dart**。
- 错误经 `sink.add_error(anyhow!(...))` 送 Dart 端（FRB `add_error` 接受 `anyhow::Error`）。
- `Ready/Closed` 映射 Dart 的 `onReady/onClose`（由 App 绑定层完成）。

## Consequences
**正面**
- 无 Dart 侧忙轮询；Dart 得到原生 `Stream`，可 `listen`/`StreamBuilder`，接入 `canvas_danmaku` 与既有事件总线自然。
- 时序（心跳/重连）集中在 Rust，一处可测（`cargo test`）；Tauri 侧可把同一 core 事件源换成 `tokio mpsc` 订阅。
- 控制事件显式化，`onReady/onClose` 语义比「流结束推断」更清晰。

**负面**
- `StreamSink` 的寿命需管理（FRB 允许函数返回后继续 `add`，但仍须在 `disconnect` 时 `close()`）。
- 与上游的轮询式接口形态不同；若后续要「对齐上游 Dart 壳」需适配（本轮 D2 直连 FRB，不需要）。

## Related ADRs
ADR-005（会话状态）、ADR-006（错误模型）
