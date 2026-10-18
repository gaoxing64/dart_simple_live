# simple_live_core 架构与选型对照

> 版本锚点：future `4795b165` + 2026-10-18 Dart core 清理（删除全部 Dart 平台实现与 `simple_live_console`）
> 覆盖范围：Rust 核心 `crates/slive-core`｜FRB 门面 `src/api/slive`｜Dart 绑定层 `lib/src/bridge`｜CLI `crates/slive-cli`
> 配套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)

## 0. 结论速览

| 问题 | 答案 |
| --- | --- |
| 协议实现（签名/解析/重连）在哪 | `crates/slive-core`，纯 Rust，**零 FRB 依赖** |
| Dart 侧还剩什么 | 模型 683 行 + 接口 147 行 + 绑定层 1,663 行 + FRB 生成物 10,846 行 |
| App / TV 怎么接 | `sites.dart` 直接 `new Rust*Site()`，**无运行时开关**（ADR-008 回退窗口关闭） |
| 命令行怎么接 | `crates/slive-cli`（产物 `slive`）直接依赖 `slive-core`，**完全绕开 FRB** |
| 弹幕怎么出 | Rust `StreamSink<LiveDanmuItem>` → Dart `Stream` → `LiveDanmaku` 回调 |
| 为什么保留 Dart 模型 | App/TV 全量消费 `LiveRoomDetail` 等，桥层做 1:1 翻译；删掉会波及 34 个调用点 |

## 1. 模块全景

```
simple_live_core/
├── crates/slive-core/                 # ★ 纯核心 crate（rlib，可被 Tauri 等复用）
│   ├── src/platforms/{bilibili,douyu,huya,douyin,twitch}/
│   ├── src/tars/                      # 手写 TARS/TUP 编解码（虎牙/斗鱼）
│   ├── src/ws/                        # 帧编解码 + 会话骨架 + run_session 主循环
│   ├── src/http.rs                    # HttpTransport trait + ReqwestTransport(rustls)
│   ├── src/time.rs                    # TimeSource trait（生产真实睡眠 / 测试立即返回）
│   ├── src/models/                    # 跨平台模型（room/play/message/danmu/account/category）
│   ├── src/wbi.rs / util.rs / error.rs / logging.rs
│   └── tests/                         # 集成用例 + 离线夹具 fixtures/{platform}/
├── crates/slive-cli/                  # ★ 命令行（bin `slive`），只依赖 slive-core
├── src/api/slive/                     # FRB 门面：opaque 句柄 + JSON args + StreamSink
├── src/frb_generated.rs               # FRB 生成物（9,122 行，入库）
├── lib/src/bridge/                    # Dart 绑定层：rust_*_site.dart（1,663 行，零协议逻辑）
├── lib/src/rust/                      # FRB Dart 生成物（10,846 行，入库）
├── lib/src/interface/                 # LiveSite / LiveDanmaku 契约（147 行）
├── lib/src/model/                     # 跨平台 Dart 模型（683 行）
├── lib/src/common/                    # 只剩 core_log.dart + qr_status.dart
├── rust_builder/                      # cargokit 构建插件（5 平台）
└── Cargo.toml                         # workspace：[slive-core, slive-cli]
```

**已删除**（2026-10-18，ADR-014 决策 4 落地）：`lib/src/platforms/**`（34 文件 / 15,286 行，含抖音 proto 8,004 行与虎牙 TARS 1,005 行）、`lib/src/common/` 的 HTTP/WS 工具 8 个文件、`packages/tars_dart`（26 文件）、`test/*.dart`（9 个）、`assets/js`、`example/`，以及整仓的 `simple_live_console/`。

## 2. 分层与边界

| 层 | 位置 | 职责 | 硬纪律 |
| --- | --- | --- | --- |
| Dart 绑定层 | `lib/src/bridge/rust_*_site.dart` | `implements LiveSite`；FRB 模型 ↔ Dart 模型 1:1 翻译 | **零协议逻辑**：不得出现 URL 拼接 / 签名 / 解析 / 重试（AC-39 / J-6 / R-13） |
| FFI 边界 | `lib/src/rust/` + `src/frb_generated.rs` | FRB 2.13.0 codegen，两侧均入库 | 版本两侧必须精确一致（`=2.13.0`），漂移会让 `RustLib.init()` 静默抛异常 |
| FRB 门面 | `src/api/slive/**`（1,771 行） | `#[frb(opaque)]` 站点句柄、`StreamSink` 弹幕、`SliveError → CoreError` 映射 | 同样只翻译转发；`#[frb(ignore)]` 标记内部管线函数 |
| Rust 核心 | `crates/slive-core/` | 协议全套：签名、分页、解码、心跳、重连 | 不得依赖 FRB / Flutter |
| 构建 | `rust_builder/`（cargokit） | App 与 TV 共用同一 crate、同一份生成物 | 包名固定 `rust_lib_simple_live_app` |

依赖方向单行：`bridge → api → slive-core`；`bridge` 另外依赖 `model/interface`。**不存在核心反向依赖应用的情况。**

## 3. Rust 核心内部结构

### 3.1 平台层

五个平台目录结构同构但深度不同：`site.rs`（站点句柄 + 全部对外方法）+ 按能力拆分的模块（`detail/` `play/` `rooms/` `search/` `categories/` `danmaku/` `signature/` `account/`）。

| 平台 | 行数（含内联测试） | 目录特征 |
| --- | --- | --- |
| bilibili | 2,054 | `wbi.rs` `buvid.rs` `cookie.rs` `super_chat.rs` `emoticon.rs`；弹幕 `args/decode/parse` 三分 |
| douyu | 4,078 | `sign.rs`（enc 链）`transport.rs` `api_code.rs`；弹幕 `protocol/session/parse`；`super_chat.rs` |
| huya | 4,952 | `anti_code.rs` `tup.rs` `vip_room_id.rs` `detail_parse.rs`；弹幕 8 文件（`bare/frames/tars_*`） |
| douyin | 7,561 | `signature/`（abogus + x_bogus + sm3 + tables，10 文件）、`detail/{enter,reflow,html,builder}`、`play/branches`、手写 `danmaku/proto` |
| twitch | 2,476 | `gql.rs` `m3u8.rs` `unsupported.rs`；IRC 文本帧 `danmaku/{parse,session}` |

`unsupported.rs` 是 Twitch 的显式能力声明：分类/分类下房间/SC **恒返回空**，推荐/搜索/凭证/账号 **恒报错**（`SliveError::InvalidInput` / `Api{code:-1}`），**不静默兜底** —— 与 Dart core 原语义逐条对齐。

### 3.2 基础设施

- **`tars/`**：手写 TARS/TUP 编解码（`buffer/{reader,writer}` `decoder` `encoder` `packet` `uni_packet` `value`…）。**不用 `tars-stream` crate**：它依赖 nightly 的 `specialization`，stable 编不过（见 `docs/rust-core/17-tars-module.md`）。
- **`ws/`**：`frame.rs` 负责 B站 16 字节大端包头；`session.rs` 定义 `FrameSource`（事件源）与 `SessionTuning`（心跳/重连参数）；`runner.rs` 是会话主循环（`Ready → Message → Reconnecting → Closed`）。各平台另有自己的 `run_session`（帧格式差异大，不强行抽象）。
- **`http.rs`**：`HttpTransport` trait 只有一个 `get(&HttpRequest)`；生产实现 `ReqwestTransport`，**统一 rustls**（避免 Android OpenSSL/NDK C 依赖）。
- **`time.rs`**：`TimeSource` 注入 —— 生产 `SystemClock` 真实睡眠，测试实现立即返回，是「重连 5 次/心跳到期」这类用例不 flaky 的前提。
- **可测性 seam**：每个 `*Site` 都有 `with_deps(http, time, post…)`，集成测试注入假传输与假时钟，无需联网。

### 3.3 弹幕会话的一生

```
XxxDanmakuConnection::new()                  # FRB 门面：每路播放一个句柄（多开各停各的）
XxxDanmakuConnection::start(args_json, sink) # （或 CLI 直接装配）
  → args from_json（失败 → CoreError）
  → stop_rx = 本句柄的 watch::Sender.subscribe()（无全局单例，互不顶掉）
  → std::thread::spawn + 自建 current_thread runtime   ← FRB 的 FFI 线程没有 reactor，tokio::spawn 会 panic
  → run_session(args, ConnectFactory, TimeSource, Tuning, stop_rx, on_item)
       ├─ connect 失败 → 退避 5s，最多 5 次 → Closed
       ├─ 连接成功 → on_item(Ready) → 发 join 帧
       ├─ 收帧 → 解码 → on_item(Message)
       └─ 每帧处理后检查心跳到期 → 发心跳
  → sink.add(item) / CLI 打印
```

## 4. 平台实现对照表

| 维度 | bilibili | douyu | huya | douyin | twitch |
| --- | --- | --- | --- | --- | --- |
| 详情来源 | JSON API | `betard/{roomId}` JSON | 网页 HTML 正则 | JSON（reflow / web-enter / html 三级） | GQL |
| 列表分页 | 服务端 `has_more` / 本页非空 | 类目 `pgcnt` / 推荐本页非空 | `page < totalPage` | offset+count（满页判据） | 不支持 |
| 取流签名 | wbi（md5 + 重排表） | `getEncryption` + md5 链（5min 缓存） | tars `getCdnTokenInfoEx` + antiCode | 无（本地组装） | 无 |
| 反爬 | buvid3/4 + wbi | dy_did/acf_did + enc_data | 匿名 uid + 固定 cookie/guid | **abogus**（SM3+RC4，aid=6383） | 无需 |
| 弹幕传输 | WSS 自定义二进制 | WSS + 自制 STT 文本帧 | WSS + TARS | WSS + protobuf(gzip) | WSS + IRC |
| 弹幕鉴权 | 16 字节包头 + token JSON | `loginreq`/`joingroup` | `RegisterGroupReq`(cmd16) | 长 query + **xbogus** | 匿名 `justinfan` |
| 心跳 | 60s | 45s | 60s | 10s + needAck 回执 | 40s |
| 重连 | 5s × 5 | 5s × 5 | 5s × 5 | 5s × 5 | 5s × 5（收到消息归零） |
| 消息支持面 | chat / online / SC / 表情 | chat（仅粉丝）/ SC | chat / online / SC / 表情（小 + 大） | chat / online / 会员表情 + 标准表情 | 仅 chat |
| SC 路径 | WS 下行解析 | WS 下行解析 | WS 信号 + HTTP 拉取（`SuperChatFetcher`） | 不支持 | 不支持 |
| 搜索 | 房间 + 主播 | 房间 + 主播 | 房间 | 仅房间 | 不支持 |
| 账号 | 扫码 + 校验 | did + 扫码 + `refreshCookie` | 桩 | `getAccountInfo` | 桩 |
| 特殊兜底 | mcdn 线路后置 | 海外 `expire=0`、cookie JWT 续期 | 4K(HDR/VIP) 跳过、线路级容错 | 连麦房间 reflow 补查、脏数据单条跳过 | — |

## 5. 依赖清单

### 5.1 Rust

| crate | 版本/特性 | 用途 |
| --- | --- | --- |
| `reqwest` | 0.12，`rustls-tls/json/cookies/gzip/brotli` | HTTP，全平台 rustls |
| `tokio` | 1，`rt-multi-thread/macros/time/sync` | 异步运行时 |
| `prost` | 0.12 | 抖音 protobuf（手写结构，免 protoc） |
| `flate2`（`rust_backend`）+ `brotli` | — | B站 op5 载荷解压（ver2 zlib / ver3 brotli） |
| `md-5` / `chrono` / `serde` / `thiserror` / `once_cell` / `regex` / `log` | — | 通用 |
| `flutter_rust_bridge` | `=2.13.0`（仅根 crate） | FFI 门面与 codegen |
| `tokio-tungstenite` | 0.21，**桌面 `native-tls` / 移动 `rustls`** | 弹幕 WS（ADR-013） |

CLI 只额外用 `tokio-tungstenite` + `async-trait` + `futures-util`，**参数解析手写**（零 clap 依赖）。

### 5.2 Dart（`pubspec.yaml`）

| 依赖 | 用途 |
| --- | --- |
| `flutter` (sdk) | 绑定层用 `foundation`（`debugPrint`）；core 仍非纯 Dart 包 |
| `flutter_rust_bridge: 2.13.0` | FRB Dart 运行时（精确钉版） |
| `freezed_annotation ^3.0.0` | FRB 枚举 → sealed class 生成依赖 |
| `logger ^2.6.2` | `CoreLog` 实现（App/TV 用 `onPrintLog` 接管） |

已移除：`dio`、`web_socket_channel`、`html_unescape`、`protobuf`、`crypto`、`brotli`、`tars_dart`、`fixnum`、`dart_sm`，以及 dev 依赖 `test`。

## 6. 关键设计决策（ADR 索引）

| ADR | 结论 |
| --- | --- |
| ADR-001 | workspace 置于 `simple_live_core/`，根 crate 为 FRB 桥、`crates/slive-core` 为纯核心 |
| ADR-002 | FRB **2.13.0** 精确钉版，生成物入库 |
| ADR-003 | HTTP 全 rustls；压缩走纯 Rust 后端 |
| ADR-004 | 弹幕用 `StreamSink` 推送（`LiveDanmuItem`：Message / Control） |
| ADR-005 | 站点状态留在 Rust，Dart 只持 opaque 句柄 |
| ADR-006 | `SliveError` → `CoreError` 统一映射 |
| ADR-007 | 模型在 FRB 侧显式定义，不直接暴露 core 内部类型 |
| ADR-008 | App/TV 直连绑定层，**无运行时开关**（回退窗口已关闭） |
| ADR-009 | 不依赖上游 parser crate，协议自研 |
| ADR-011 | 离线夹具 + held-out 留出集（`--features heldout`） |
| ADR-012 | D4 数据通道对齐（`data` / `danmaku_data` JSON 契约） |
| ADR-013 | WSS TLS 分平台：桌面 native-tls（斗鱼指纹风控）、移动 rustls |
| ADR-014 | **全面采用 Rust core**；Dart 实现仅为 console 保留，console 迁移后整删（本次已执行） |

## 7. 已知取舍与风险

1. **双份模型**：Rust `models/*` 与 Dart `lib/src/model/*` 是同一套数据的两种声明，靠 `rust_site_models.dart` 手写翻译维持一致。新增字段要同时改三处（Rust 模型 / FRB 生成 / Dart 模型）。
2. **FRB 版本锚定是硬约束**：两侧版本漂移不会编译报错，而是运行时 `RustLib.init()` 抛异常，排查成本高。
3. **抖音是最大单点**：7,561 行、签名全在本地（abogus/x_bogus/sm3），平台风控一变即失效，且难以离线验证。
4. **虎牙最脆弱**：详情靠网页正则 + 硬编码 VIP 名单，弹幕 WS 用 temp cookie/guid。
5. **斗鱼弹幕只受理粉丝发言**（历史行为），会漏消息。
6. **Tab 与 TARS 全靠手写**：协议变更需人工跟踪，无第三方库兜底。
7. **测试偏斜**：抖音 180 条、虎牙 93 条、斗鱼 80 条、Twitch 50 条、B站仅 20 条内联用例；B站主要靠集成夹具覆盖。
8. **当前 8 条红灯**：Twitch 夹具被 Windows CRLF 污染（`.gitattributes` 的 `* text=auto` 把 `.bin` 当文本），非逻辑缺陷，见 backlog。
