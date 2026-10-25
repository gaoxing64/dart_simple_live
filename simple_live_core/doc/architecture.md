# simple_live_core 架构与选型对照

> 锚点：future `52466f96`（2026-10-21）｜范围：Rust 核心、FRB 门面、Dart 绑定层、CLI
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/architecture.md)｜[TV](../../simple_live_tv_app/doc/architecture.md)

## 1. 结论速览

| 问题 | 答案 |
| --- | --- |
| 协议在哪 | `crates/slive-core`，纯 Rust，零 FRB/Flutter 依赖 |
| Dart 还剩什么 | 模型 + `LiveSite` 契约 + 绑定层 + FRB 生成物 |
| App/TV 怎么接 | `sites.dart` 直接 `Rust*Site()`，无运行时开关 |
| CLI 怎么接 | `crates/slive-cli`（bin `slive`）直连核心，绕开 FRB |
| 弹幕怎么出 | Rust `StreamSink<LiveDanmuItem>` → Dart Stream → 回调 |

## 2. 模块全景

```
simple_live_core/
├── crates/slive-core/          # 纯核心
│   ├── src/platforms/{bilibili,douyu,huya,douyin,twitch}/
│   ├── src/tars/               # 手写 TARS/TUP
│   ├── src/ws/                 # 帧/会话/runner
│   ├── src/http.rs             # HttpTransport + ReqwestTransport(rustls)
│   ├── src/time.rs             # TimeSource（可注入）
│   ├── src/models/             # room/play/message/danmu/account/category
│   └── tests/                  # 31 个 ac_*.rs + fixtures/
├── crates/slive-cli/           # bin slive（info / danmaku）
├── src/api/slive/              # FRB 门面（opaque 句柄 + StreamSink）
├── src/frb_generated.rs        # FRB 生成物（入库）
├── lib/src/bridge/             # rust_*_site.dart（零协议逻辑）
├── lib/src/rust/               # FRB Dart 生成物（入库）
├── lib/src/interface/          # LiveSite / LiveDanmaku
├── lib/src/model/              # Dart 模型
├── lib/src/common/             # core_log / qr_status
└── rust_builder/               # cargokit（5 平台）
```

## 3. 分层与硬纪律

| 层 | 位置 | 职责 | 纪律 |
| --- | --- | --- | --- |
| Dart 绑定 | `lib/src/bridge/` | FRB 模型 ↔ Dart 模型 1:1 | 零协议逻辑（无 URL/签名/解析/重试） |
| FFI | `lib/src/rust/` + `src/frb_generated.rs` | FRB 2.13.0 codegen，两侧入库 | 版本必须精确一致 |
| FRB 门面 | `src/api/slive/` | opaque 句柄、弹幕 StreamSink、错误映射 | 只翻译转发 |
| Rust 核心 | `crates/slive-core/` | 签名/分页/解码/心跳/重连 | 不得依赖 FRB/Flutter |
| 构建 | `rust_builder/` | App/TV 共用同一 crate/生成物 | 包名 `rust_lib_simple_live_app` |

依赖方向：`bridge → api → slive-core`，无反向依赖。

## 4. 平台实现对照

| 维度 | bilibili | douyu | huya | douyin | twitch |
| --- | --- | --- | --- | --- | --- |
| 详情 | JSON API | `betard` JSON | HTML 正则 | reflow/web-enter/html | GQL |
| 分页 | has_more / 非空 | pgcnt / 非空 | totalPage | 满页 / 分区轮转 | 无 |
| 取流签名 | wbi | enc + md5 | tars + antiCode | 本地组装 | 无 |
| 反爬 | buvid + wbi | did + enc_data | 匿名 uid/cookie | abogus / x_bogus | 无 |
| 弹幕 | WSS 二进制 | WSS STT | WSS TARS | WSS protobuf | WSS IRC |
| 心跳 | 60s | 45s | 60s | 10s + ack | 40s |
| 账号 | 扫码+校验 | did+扫码+刷新 | 桩 | 信息 | 桩 |

## 5. 关键选型

| 选择 | 理由 | 代价 |
| --- | --- | --- |
| Rust 核心 + FRB | 一套协议多前端；性能与并发 | 双份模型、FRB 版本锁 |
| 手写 TARS/TUP | `tars-stream` 依赖 nightly specialization | 协议变更需人工跟踪 |
| HTTP 全 rustls | 移动端零 OpenSSL/NDK C 依赖 | 斗鱼弹幕改走明文 TCP（ADR-015） |
| `TimeSource` 注入 | 重连/心跳测试不 flaky | 每个 Site 需 `with_deps` |
| 离线夹具 + held-out | 少联网、可回归 | 夹具需随平台更新 |

## 6. 依赖与版本

- Rust 根：`flutter_rust_bridge =2.13.0`、`tokio`、`reqwest(rustls)`、`prost`、`flate2/brotli`、`md-5`。
- Dart：`flutter_rust_bridge 2.13.0`（精确）、`freezed_annotation ^3`、`logger`。
- CLI 额外：`tokio-tungstenite`、`async-trait`、`futures-util`；参数解析手写。

## 7. 风险

1. **双份模型**：新增字段要同时改 Rust 模型、FRB、Dart 模型和翻译函数。
2. **FRB 版本漂移**：不报编译错，运行时 `RustLib.init()` 抛异常。
3. **抖音/虎牙脆弱**：签名与网页正则随平台改版失效。
4. **斗鱼弹幕只收粉丝**。
5. **core 仍依赖 Flutter SDK**（`foundation.debugPrint`），不能当纯 Dart 包发布。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| 全面采用 Rust、删除 Dart 协议 | `f72bb417` |
| FRB 资产/绑定层下沉 | `73e80b1e` |
| 弹幕入口改每实例句柄 | `3f0ac946` |
| 新增 slive CLI | `935db9e3` |
| 夹具 binary 化修复 Twitch 红灯 | `7b6341d5` |
