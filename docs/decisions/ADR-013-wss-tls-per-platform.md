# ADR-013: 弹幕 WSS 的 TLS 后端按平台分层（桌面 native-tls / 移动 rustls）

## Status
Superseded by [ADR-015](ADR-015-douyu-danmaku-plain-tcp.md)（2026-10-25）。原记录：Accepted (2026-10-17)，**Supersedes ADR-003 Decision #2（仅 WSS 部分）**；ADR-003 其余决策（reqwest rustls、压缩、证书库口径）不变。

## Background

2026-10-17 真机（Windows）实测：斗鱼弹幕 `wss://danmuproxy.douyu.com:8506` 在 rustls 下
**TLS 握手即被服务端拒绝**（`AlertReceived(HandshakeFailure)`，服务端主动发 alert）。

排查结论（全为真机对照实验）：
- 根因排除项：① 非根证书问题（`rustls-tls-native-roots` 同样被拒）；② 非子协议问题
  （`Sec-WebSocket-Protocol: binary` 无效）；③ 非协议层问题（curl/系统 TLS 同 URL 返回 **101**，
  换 `native-tls` 后立刻连通并收到 `loginres` + 真实 `chatmsg`）。
- **根因：斗鱼弹幕代理对 rustls 的 ClientHello 指纹做风控，仅放行系统 TLS 栈**
  （Windows=Schannel，与 Dart core 的 `dart:io`/浏览器同栈）。

ADR-003 原决策「WSS 统一 rustls、不使用 native-tls」的前提（服务端不区分 TLS 栈）
被该实证推翻；但 ADR-003 规避 Android NDK 上 OpenSSL 的动机（R-04/R-05）**依然成立**。

## Decision

WSS（`tokio-tungstenite`）TLS 后端**按目标平台分层**（Cargo target-specific deps）：

| 目标平台 | 后端 | 理由 |
|----------|------|------|
| Windows / macOS / Linux | `native-tls` | 过斗鱼风控；与桌面 Dart core（`dart:io`）同栈，行为对齐 |
| Android / iOS | `rustls-tls-webpki-roots` | **保 ADR-003 原动机**：移动端零 OpenSSL/NDK C 依赖，不破坏 cargokit 链路 |

```toml
[target.'cfg(not(any(target_os = "android", target_os = "ios")))'.dependencies]
tokio-tungstenite = { version = "0.21", features = ["native-tls"] }

[target.'cfg(any(target_os = "android", target_os = "ios"))'.dependencies]
tokio-tungstenite = { version = "0.21", features = ["rustls-tls-webpki-roots"] }
```

## Consequences

**正面**
- 桌面端斗鱼弹幕修复（真机验证）；其余平台 WS（B站/虎牙/抖音）同为系统 TLS，兼容面更大。
- 移动端构建链路未被改动（无 openssl-sys / CMake C 依赖进入 Android/iOS 构建）。

**负面 / 已知限制**
- 桌面端证书验证改用系统 store（不再 webpki-roots 静态根）：与浏览器/Dart core 行为一致，
  企业自签场景反而更宽；接受。
- **Android 端斗鱼弹幕为 OPEN 项**：移动端仍走 rustls，若斗鱼风控同样拒绝 rustls 指纹，
  则 Android 上斗鱼弹幕将失败（B站/虎牙/抖音弹幕不受影响）。**需真机验证**；
  若确认失败，评估路径：Android 也切 native-tls（vendor openssl，接受构建成本）
  或斗鱼移动端降级策略。见 `OPEN-DECISIONS`。

## Related ADRs
- **Supersedes**: ADR-003（Decision #2 WSS 部分）
- ADR-001（core crate 依赖结构不变）
- ADR-004（弹幕流推送——链路契约不变，仅 TLS 传输层变化）
