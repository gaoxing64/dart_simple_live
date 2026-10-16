# ADR-003: 统一 rustls（纯 Rust）作为 TLS/加密后端，压缩用纯 Rust 实现

## Status
Accepted (2026-10-16)

## Background
需在 Android/iOS/macOS/Windows/Linux 交叉编译 HTTP(reqwest) 与 WSS(tokio-tungstenite) 客户端。DTV 用 `openssl-sys 0.9 (vendored)` + `native-tls`（桌面口径，Android/iOS 需另行预编译 OpenSSL）。B站弹幕帧可能为 zlib(protover=2) 或 brotli(protover=3)，需解压；DTV 用 C 绑定 `brotlic 0.8`。

联网实证：FRB 项目在 Android 上因 `openssl-sys` build script 失败（exit 101）导致 `.so` 缺失、App `dlopen` 失败，公认解法是 `reqwest = { features=["rustls-tls"], default-features=false }`（FRB issue #2005；GitCode 案例）。Dart core 用 `package:brotli`，上游 Rust 用纯 Rust `brotli` crate。

## Decision
1. `reqwest` 显式 `default-features = false`，启用 `["rustls-tls","json","stream","cookies","brotli","gzip"]`。
   > 版本说明（spike 后补充）：实际采用 **reqwest 0.12**（DTV 的 0.11 偏旧；0.12 的 rustls 支持稳定且本机缓存为 0.12）。本 ADR 的「rustls/纯 Rust 后端」结论不随版本变化。
2. ~~WSS 用 `tokio-tungstenite` 的 `rustls-tls-webpki-roots`；不使用 `native-tls`。~~
   > **⚠️ SUPERSEDED（2026-10-17，见 ADR-013）**：斗鱼弹幕服务器对 rustls ClientHello 做 TLS 指纹风控
   > （真机实证：rustls 握手被拒 / 系统 TLS 101 通过）。WSS 的 TLS 后端已改为**按平台分层** ——
   > 桌面 native-tls、移动 rustls（保本 ADR「移动端零 OpenSSL」动机）。本条仅 WSS 部分被取代，
   > reqwest（HTTP）仍为 rustls，不变。
3. 证书库用 **webpki-roots**（内置 Mozilla 根），不依赖系统 store；企业 CA 需求出现时再评估 `rustls-platform-verifier`。
   > **注（2026-10-17）**：桌面 WSS 改用系统 store（native-tls 的固有行为）；HTTP/移动端不变。
4. 压缩：brotli 用纯 Rust `brotli` crate；zlib 用 `flate2` 的 `rust_backend`（miniz_oxide）。**不用** `brotlic`/C zlib。
5. `http1_only()`（部分环境 HTTP/2 ALPN 抖动）+ `connect_timeout(15s)` + `timeout(45s)` + `no_proxy()`，对齐 DTV 兼容口径。

## Consequences
**正面**
- 全平台纯 Rust 后端，移动端交叉编译不再需要 OpenSSL/CMake C 工具链，规避 R-04/R-05/R-06。
- 与 Dart core / 上游的压缩语义一致（brotli 纯 Rust）。

**负面**
- rustls 默认不读系统证书 store（webpki-roots 为静态根）：个别企业代理/自签证书场景需另配。属可接受权衡。
- 与 DTV 的依赖口径不同，参考 DTV 依赖清单时需注意不要照抄 openssl/native-tls/brotlic。

## Related ADRs
ADR-001（核心 crate 依赖）
