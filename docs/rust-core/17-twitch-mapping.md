# IP-5 Twitch 迁移映射表（dart_simple_live Rust Core）

> 分支 `feat/core-rust` ｜ 行为基准唯一：`simple_live_core/lib/src/platforms/twitch/`
> （`twitch_site.dart` 320 行 / `twitch_models.dart` 264 行 / `twitch_danmaku.dart` 104 行）
> 上游参考（**仅参考，未依赖**，ADR-009）：`SlotSun/slive-core-api-rust` 的
> `crates/platforms-parser/src/extractor/platforms/twitch/`
>
> 与 `12-bilibili-mapping.md` 同构：逐方法落点 + 逐条差异登记。

---

## 1. 文件落点

### 1.1 Rust 核心（`crates/slive-core/src/platforms/twitch/`）

| 文件 | 行数 | 职责 | 对照 Dart |
|------|------|------|-----------|
| `mod.rs` | 22 | 模块声明 + `pub use site::TwitchSite` | — |
| `site.rs` | 262 | 句柄状态（device-id）+ **15 方法编排**（仅编排） | `twitch_site.dart` 全体 |
| `site_tests.rs` | 50 | 句柄层单测（从 site.rs 拆出，守 300 行门禁） | — |
| `header.rs` | 75 | 请求头（client-id / UA / accept / device-id） | `:20-40` |
| `gql.rs` | 71 | persisted query 构造 + 三个 sha256 常量 | `:49-64, 249, 256, 94` |
| `models.rs` | 275 | GQL 响应反序列化模型（10 类） | `twitch_models.dart` |
| `detail.rs` | 114 | F-06 房间详情（一次批量两个 operation） | `:207-279` |
| `play.rs` | 164 | F-07 清晰度 / F-08 播放地址 | `:89-199` |
| `m3u8.rs` | 152 | m3u8 主列表解析 + 带宽→清晰度阈值表 | `:136-188` |
| `unsupported.rs` | 129 | 恒空 / 恒报错方法集中地 | `:67-77, 202-204, 282-319` |
| `transport.rs` | 266 | GQL **POST JSON** seam + mock（Twitch 专属） | — |
| `danmaku/mod.rs` | 17 | 弹幕子模块声明 | — |
| `danmaku/args.rs` | 173 | 弹幕契约 + 握手帧 + 心跳帧 + 匿名昵称 | `twitch_danmaku.dart:56-63, 27` |
| `danmaku/parse.rs` | 199 | IRC 行解析 → `LiveMessage` + PONG（照搬 Dart 三正则语义） | `:73-103` |
| `danmaku/parse_tests.rs` | 159 | 解析层单测 | — |
| `danmaku/session.rs` | 171 | 会话主循环（握手/心跳/重连/stop） | `:32-71` + `WebScoketUtils` |
| `danmaku/session_tests.rs` | 177 | 会话层单测 | — |

### 1.2 FRB 桥（`rust/src/api/slive/twitch/`）

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 8 | `pub mod danmaku; pub mod site;`（**不改** `api/slive/mod.rs`） |
| `site.rs` | 188 | `#[frb(opaque)] LiveTwitchSite` + 15 方法转发 |
| `danmaku.rs` | 165 | IRC-over-WS 生产连接 + `start_twitch_danmaku` / `stop_twitch_danmaku` |

### 1.3 Dart 绑定层

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/services/rust_core/rust_twitch_site.dart` | 215 | `RustTwitchSite extends LiveSite` + `RustTwitchDanmaku` |

### 1.4 测试与夹具

| 文件 | 职责 |
|------|------|
| `tests/ac_twitch_http.rs` | HTTP 读链路 23 例（成功流 + 错误流 + 未实现能力） |
| `tests/ac_twitch_danmaku.rs` | 弹幕 29 例（13 组 golden 帧对拍 + 会话时序） |
| `tests/ac_twitch_quality_golden.rs` | 清晰度阈值 golden 5 例 |
| `tests/twitch_common/mod.rs` | 夹具加载 + 注入式 harness |
| `tests/fixtures/twitch/http/http-samples.json` | GQL / m3u8 样本（3 端点 + **12 变体**） |
| `tests/fixtures/twitch/ws/*.bin` + `*.expected.json` | IRC 帧 golden 对（**13 组**） |
| `tests/fixtures/twitch/golden/golden-quality-name.json` | 阈值表 11 例（含边界 ±1） |

---

## 2. 逐方法映射（`TwitchSite` 公开方法全集）

| # | Dart 方法 | Dart 行为 | Rust 方法 | 落点 | 一致性 |
|---|-----------|-----------|-----------|------|--------|
| 1 | `id` | `'twitch'` | `id()` | site.rs | ✅ |
| 2 | `name` | `'Twitch'` | `name()` | site.rs | ✅ |
| 3 | `getCategories` | `return []` | `get_categories()` | unsupported.rs | ✅ 恒空 |
| 4 | `getCategoryRooms` | `hasMore:false, items:[]` | `get_category_rooms()` | unsupported.rs | ✅ 恒空 |
| 5 | `getLiveStatus` | `getRoomDetail().status` | `get_live_status()` | site.rs | ✅ 复用详情链路（**1 次请求**） |
| 6 | `getPlayQualities` | GQL token + usher m3u8 | `get_play_qualities()` | play.rs + m3u8.rs | ✅ |
| 7 | `getPlayUrls` | `urls:[quality.data] + headers` | `get_play_urls()` | play.rs | ✅ 无网络请求 |
| 8 | `getRecommendRooms` | `throw UnimplementedError()` | `get_recommend_rooms()` | unsupported.rs | ✅ `InvalidInput` |
| 9 | `getRoomDetail` | GQL 批量 `[ChannelShell, StreamMetadata]` | `get_room_detail()` | detail.rs | ✅ **1 次请求** |
| 10 | `getSuperChatMessage` | `return []` | `get_super_chat_messages()` | unsupported.rs | ✅ 恒空 |
| 11 | `searchAnchors` | `throw Exception("twitch暂不支持搜索主播")` | `search_anchors()` | unsupported.rs | ✅ `Api{-1}` |
| 12 | `searchRooms` | `throw Exception("twitch暂不支持搜索房间")` | `search_rooms()` | unsupported.rs | ✅ `Api{-1}` |
| 13 | `setSiteAttrs` | `throw UnimplementedError()` | `set_site_attrs()` | unsupported.rs | ✅ `InvalidInput` |
| 14 | `getAccountInfo` | `throw UnimplementedError()` | `get_account_info()` | unsupported.rs | ✅ `InvalidInput` |
| 15 | `getQRCode` | `throw UnimplementedError()` | `get_qr_code()` | unsupported.rs | ✅ `InvalidInput` |
| 16 | `getQRPollResult` | `throw UnimplementedError()` | `get_qr_poll_result()` | unsupported.rs | ✅ `InvalidInput` |
| 17 | `getDanmaku` | `TwitchDanmaku()` | `RustTwitchDanmaku`（Dart 层） | rust_twitch_site.dart | ✅ |

**能力对齐声明**：Dart core「尚不支持」的方法**一个都没有被顺手实现**（迁移擅自实现会改变
App 行为并破坏 AC-30 回归为零）。Rust 侧以**类型化错误**表达同一语义，不静默返回空。

### 弹幕方法（Dart `TwitchDanmaku`）

| Dart | Rust | 说明 |
|------|------|------|
| `heartbeatTime = 40 * 1000` | `TWITCH_HEARTBEAT_SECS = 40` | ✅ |
| `heartbeat()` → `PONG :tmi.twitch.tv` | `TwitchDanmakuArgs::heartbeat_frame()` | ✅ 载荷一致 |
| `joinRoom()` 5 帧 | `TwitchDanmakuArgs::handshake(nick)` | ✅ 顺序一致（CAP REQ→PASS→NICK→USER→JOIN） |
| `justinfan{1000+rand(99000)}` | `anonymous_nick(unix_secs)` | ⚠️ **D-7**（见下） |
| `decodeMessage()` | `parse_frame()` | ⚠️ **D-1~D-5**（见下） |
| `start/stop` | `start_twitch_danmaku/stop_twitch_danmaku` | ✅ 独立线程 + 自建 runtime |

---

## 3. 差异登记

> **结论：与 Dart core 行为完全一致（零有意差异）。**
> QA 在 `18-fixtures-multiplatform.md §4` 钉死了 Twitch 的既有 quirks（Q7/Q8），
> §7 明确「**不要修改夹具来让实现通过** … 若确信夹具与 Dart 行为不符，先提 QA 复核」。
> 本实现**全部照搬**，逐条列在下表（编号沿用 QA 的 Q-x）。

| # | quirk | Dart 依据 | Rust 落点 | 处理 |
|---|-------|-----------|-----------|------|
| Q7 | `title` 缺失时回落成**字面量字符串 `"null"`**（不是空串） | `twitch_site.dart:229` | `detail.rs` | ✅ 照搬，有单测钉住 |
| Q8 | `PING` 用**整帧** `replaceFirst` —— 混帧回包会带上后续 PRIVMSG 行（含帧尾换行） | `:79` | `danmaku/parse.rs`（`text.starts_with("PING")` + `replacen(...,1)`） | ✅ 照搬，golden 用例断言 `_meta.pinned_dart_behavior` |
| Q-A | `PRIVMSG` 的三条正则（content / display-name / color）**必须同时命中**才产出，缺任一即**整条丢弃** | `:86-90` | `danmaku/parse.rs::build_chat_message` | ✅ 照搬（**不做** nick 回退、**不做**白色兜底） |
| Q-B | m3u8 的 `BANDWIDTH` 与 URL 行**按下标配对**（脆弱点，Dart 同款） | `:163-166` | `m3u8.rs::parse_variants` | ✅ 照搬；`playlist_variants_cover_fallback_and_boundary_cases` 钉住错位边界（缺带宽 -> `0`/自动/排最后） |
| Q-C | 帧尾 `\r` 被 `(.)` 捕获进 `message` | `:86` | `danmaku/parse.rs`（**不 trim CR**） | ⚠️ **待 QA 裁决**（夹具标 `PENDING_QA_DECISION`）。裁决前照搬 Dart；我的测试**只断言「待裁决」标记存在**，不写单边期望值（QA 纪律：待裁决项不得伪装成已断言） |
| Q-D | 未开播时 `getPlayQualities` **仍先取 token** 再返回空列表 | `:106` 在 `if (liveStatus)` 之前 | `play.rs::fetch_qualities` | ✅ 照搬，单测钉住「1 次 GQL + 0 次 m3u8」 |

### 两处**实现层**的必要偏离（非行为差异）

| # | 偏离 | 理由 |
|---|------|------|
| E-1 | `device-id` 由**时间源派生**且**句柄级缓存**（Dart 每次请求真随机） | `slive-core` 无 `rand` 依赖（`Cargo.toml` 冻结且 IP-5 禁改），且随机源不可注入会让离线夹具断言失真。请求头**集合**与 Dart 一致（ADR-005 同类裁决） |
| E-2 | 匿名昵称由**时间源派生**（Dart 用 `Random()`） | 同上；Twitch 只要求 `justinfan` 前缀语义，服务端不校验具体值 |

### ⚠️ 建议 QA / 总监复核的**产品口径**问题（我未擅自修改）

**Q-A 的丢弃面可能远超预期**：Twitch 仅对设置了昵称颜色的用户下发 `color` 标签，
若无颜色标签的用户占比高，则其聊天消息在 Rust（与 Dart）两侧**都**收不到。
这属于**产品口径**（是否值得为「与 Dart 一致」牺牲这部分消息），不是实现 bug。
证据已在夹具内（`irc-privmsg-no-color.expected.json` / `-no-display-name`），
**建议**：真机抓包统计 P-3（§6 待抓包清单）后，再决定是否提「修正 Q-A」的变更。

## 4. 契约与 seam

| seam | Twitch 用法 | 与 B站一致 |
|------|-------------|-----------|
| `HttpTransport`（GET） | usher m3u8 | ✅ |
| `TwitchPost`（POST JSON，**平台内自建**） | gql.twitch.tv/gql | ➖ 共享 `HttpTransport` 只有 `get`；Twitch 全 POST，故模块内自建（同斗鱼 `transport.rs` 做法，不改共享 `http.rs`） |
| `TimeSource` | device-id 派生、`play_session_id` 下标、`p` 参数、nickname | ✅ |
| `FrameSource` | IRC 文本帧 | ✅（**桥层独立实现**：B站 `WsFrameSource` 只取 Binary，Twitch 是 Text 帧） |
| `SessionTuning` | 心跳 40s / 重连 5s×5 | ✅（B站 60s/5s×5） |

### 会话主循环为何不复用 `ws::runner::run_session`

共享的 `run_session` 签名硬绑 `BiliBiliDanmakuArgs` + 二进制 `decode_frame`，Twitch 是
IRC 文本协议。按「不改共享 `runner.rs`」的边界，Twitch 在 `danmaku/session.rs` 内**同构实现**
（同样的事件序列 / 心跳判定 / 重连策略 / stop 语义）。
**建议（交由总监裁决）**：若后续平台增多，可把 `run_session` 抽成「协议 trait + 通用循环」。

---

## 5. 未接入 / 待接线（需总监处理）

| # | 事项 | 说明 |
|---|------|------|
| 1 | `crates/slive-core/src/platforms/mod.rs` | 已由总监预置 `pub mod twitch;` ✅ |
| 2 | `rust/src/api/slive/mod.rs` | **需加 `pub mod twitch;`**（共享文件，我未改） |
| 3 | `flutter_rust_bridge_codegen` | **需运行**（我按边界禁跑）；生成后复核 `rust_twitch_site.dart` 顶部的 `ignore_for_file` |
| 4 | `lib/app/sites.dart` | **需接线** `Constant.kUseRustTwitch ? RustTwitchSite() : TwitchSite()` |
| 5 | `lib/app/constant.dart` | **需加** `kUseRustTwitch`（默认 false = 可回退，AC-31） |
| 6 | held-out 夹具集 | `tests/fixtures/twitch/heldout/` 现为空目录；真机抓包后填入（AC-36） |

---

## 6. 真机待抓包清单（合成夹具 → 真机校对）

| # | 待验项 | 为什么必须真机 |
|---|--------|--------------|
| 1 | 三个 persisted query 的 `sha256Hash` 是否仍有效 | Twitch 会轮换哈希；失效即 HTTP 400 |
| 2 | `profileImageURL` 的 **URL 大写** | 夹具按真实响应建模，但需真机确认（写成 `profileImageUrl` 会静默取空） |
| 3 | m3u8 中 `BANDWIDTH` 与 URL 行是否**严格同序** | 当前实现按下标配对（Dart 同款脆弱点）；乱序需改为按 URL 关联 |
| 4 | IRC 帧是否用 WebSocket **Text** 帧、是否 CRLF、多行 | 桥层按 Text 帧实现；若为 Binary 需改 `TwitchIrcFrameSource` |
| 5 | D-4（去尾随换行的 PONG）服务端是否接受 | Twitch IRC over WS 通常两者都收，但需确认 |
| 6 | 无 `color` / 无 `display-name` 的真实帧占比 | 决定 D-1/D-2 的实际影响面（当前按「普遍存在」处理） |
| 7 | `RECONNECT` 的实际触发与形态 | 当前与 Dart 一致：不主动响应，仅靠心跳/断开判定重连 |
