# Spec — dart_simple_live Core Rust 化（第一步：Rust Core 落地 + B站端到端）

> 版本：**v1.0** ｜ 生成日期：2026-10-16 ｜ 状态：**待用户确认**
> 基线：fork `future` @ `4dcdb4fe` ｜ worktree 分支 `feat/core-rust`
> 基于：`00-briefing.md`（决策 D1–D6）+ `11-scope-and-acceptance.md`（PM 范围与验收）+ `10-architecture.md`（架构师方案）
> **本文件是团队唯一契约。** 与之冲突时：先改本文件，再改代码（活规格）。
> 详表索引：功能与 AC → `11-scope-and-acceptance.md` ｜ 架构细节与 ADR → `10-architecture.md` + `decisions/ADR-001~010` ｜ 逐方法落点 → `12-bilibili-mapping.md`

---

## 1. 产品定义

- **一句话**：把 `simple_live_core`（Dart）的 **B站** 能力迁移到 **Rust Core**，经 flutter_rust_bridge 直连 Flutter，为上游 issue #155「枪弹分离」路线图落第一块地基。
- **目标用户**：本项目 App 用户（**行为零变化**）与后续维护者（协议逻辑收敛到可被 Flutter / Tauri 复用的 Rust 核心）。
- **核心问题**：Dart 缺稳定 JS Runtime（插件化受阻）、协议逻辑与 App 深绑（平台变更需发版）、AI 辅助开发缺编译期约束。

---

## 2. MVP 范围（锁定 —— 不在此列表的功能一律不做）

| 优先级 | 内容 | 验收标准摘要 |
|--------|------|-------------|
| **I-1** | Rust Core 骨架：`common`（http/ws/log/error/binary）+ `model`（强类型）+ 接口层 | `cargo build`/`clippy -D warnings` 通过 |
| **I-2** | B站全部能力 F-01~F-22（15 个 `LiveSite` 方法 + 2 属性 + 弹幕全链路 + 账号三接口） | AC-01 ~ AC-29 |
| **I-3** | FRB 2.13.0 绑定，**Dart 直连 FRB API**（绑定层仅类型翻译/转发） | AC-39 / DoD-1 |
| **I-4** | 离线夹具单测为主（含 held-out 集），联网仅冒烟 | AC-35 ~ AC-38 / DoD-2 |
| **I-5** | B站可开关、可一键回退；其余 4 平台零影响 | AC-30 ~ AC-34 |

**迁移完成定义（DoD）**：DoD-1 构建 · DoD-2 离线测试全绿（skip/ignore/xfail=0）· DoD-3 端到端（详情→清晰度→取流→弹幕 30s + 一条错误流）· DoD-4 回归为零 · DoD-5 可回退 · DoD-6 门禁（≤300 行/依赖向下/无 emoji 图标/无占位）· DoD-7 证据留痕 · DoD-8 规格同步。详见 `11-scope-and-acceptance.md §5`。

---

## 3. 明确不做（Out-of-Scope —— 锁定）

| 不做的功能 | 原因 | 何时考虑 |
|------------|------|----------|
| O-1 其余 4 平台（douyu/huya/douyin/twitch） | 本轮只验证「骨架 + 单平台端到端」的可复制路径，不摊薄范围 | 本轮验收后按同路径逐平台推进 |
| O-2 JS Plugin | 路线图第二步，依赖 Rust Core 稳定 | 第二步 |
| O-3 枪弹分离 | 路线图第三步 | 第三步 |
| O-4 Plugin 分发 | 路线图第四步 | 第四步 |
| O-5 任何 UI / 用户可见交互改动 | 内部迁移，UI 零变化（AC-32 可判定性依赖此项） | 后续独立需求 |
| O-6 B站弹幕**发送** | Dart core 本无此能力，不新增 | 有需求时 |
| O-7 B站直链续流 `renewers` | 该机制仅斗鱼需要；B站无此语义 | 迁移斗鱼时；2026-10-18 已由 App 侧 `StreamRenewContext` 绕开（中转按房间/清晰度/线路自取流，无需 FRB 回调） |
| O-8 抖音 protobuf / 虎牙 TARS 的 Rust 重生成 | 属 O-1 | 迁移对应平台时 |

---

## 4. 技术架构（锁定 · 含版本锚定）

### 4.1 结构与桥接

| 层 | 技术 | 实际版本 | 锁定原因 |
|----|------|----------|----------|
| 工作区 | cargo **workspace**（`simple_live_core/` 原地升级） | — | cargokit 零改动、回归面最小 |
| 核心 crate | **`slive-core`（纯 Rust，零 FRB）** — 位于 `simple_live_core/crates/slive-core` | 0.1.0 | 可被 Flutter 之外的 Tauri 等前端复用（issue 目标）；**路径由 spike 锁定，勿移**（移动会破坏 cargokit 零改动） |
| 桥 crate | `rust_lib_simple_live_app`（**现状保留**） | 0.1.0 | 避免改 cargokit manifest/libname |
| 桥接 | **flutter_rust_bridge** | **`=2.13.0`（精确，禁 caret）** | 与现仓库资产一致；两侧版本漂移会让 `RustLib.init()` 静默抛异常 |
| HTTP | `reqwest`（`rustls-tls,json,stream,cookies,brotli,gzip`，`default-features=false`） | **0.12（实测锁定）** | 移动端 OpenSSL 构建不可行，统一 rustls（ADR-003）；0.11 为 DTV 口径且偏旧，0.12 的 rustls 支持稳定 |
| 可测试性 | `async-trait` 0.1（trait 抽象 `HttpTransport`/`TimeSource`/`FrameSource`） | 实测锁定 | 无注入点则 HTTP/WS 类 AC 无法离线验证（见 §4.2 契约） |
| WS | `tokio-tungstenite`（`rustls-tls-webpki-roots`） | 同上 | 与 HTTP 同 TLS 栈 |
| 压缩 | `brotli`（protover=3）+ `flate2` rust_backend（protover=2） | 同上 | 纯 Rust，规避 NDK 编译 C 依赖 |
| 异步 | `tokio`（rt-multi-thread/macros/time/sync/net/io-util）+ `futures-util` | 同上 | FRB 自带运行库 |
| 其他 | `serde`/`serde_json`/`thiserror`/`md-5`/`chrono`(serde)/`regex`/`rand`/`urlencoding`/`once_cell`/`log` | 同上 | 对齐 Dart core 能力面 |
| Flutter | `simple_live_app/.fvmrc` | **3.47.6** | FRB 2.13.0 要求 Dart SDK ≥ 3.9.2 |

**依赖方向（单向）**：桥 `api` → `slive-core::platforms` → `slive-core::{models, http/ws, error}`。**`slive-core` 不得依赖 FRB。**

### 4.2 关键设计决策（摘要，均有 ADR）

| 议题 | 决策 | ADR |
|------|------|-----|
| 工作区结构 | workspace + 纯核心 crate + 桥原地保留 | ADR-001 |
| FRB 集成 | 精确 `=2.13.0`；复用现 `flutter_rust_bridge.yaml`/`rust_builder`；生成代码**入库** | ADR-002 |
| TLS/压缩 | 统一 **rustls + webpki-roots**；brotli/flate2 纯 Rust；**不用** openssl-sys vendored | ADR-003 |
| 弹幕推送 | Rust→Dart 用 **FRB `StreamSink<LiveDanmuItem>`**（`Message`/`Control(Ready\|Closed\|Reconnecting)`）；心跳 60s、重连 5s×5 全在 Rust | ADR-004 |
| 状态 | **不透明句柄** `LiveBilibiliSite`（cookie/uid/buvid/wbi 缓存 + **复用单个 reqwest Client**）；弃 `tauri::State` | ADR-005 |
| 错误 | `SliveError`(thiserror) → `CoreError{message,status_code}` → App 映射回 Dart `CoreError`（两路径**同一**异常类型） | ADR-006 |
| 模型暴露 | 模型定义在 `slive-core`，桥层 `#[frb(mirror)]`（回退：显式 `From`） | ADR-007 |
| App 分派 | `simple_live_app/lib/app/sites.dart:15` **单点分派**；`RustBilibiliSite implements LiveSite`；开发阶段开关默认 **false**（走 Dart）；**体验版（2026-10-16 起）五平台开关已按 J-9 判据①翻 true**（Rust 为默认路径；回退开关保留，见 ADR-008） | ADR-008 |
| 上游依赖 | **不**依赖 `SlotSun/slive-core-api-rust`，只对齐其命名/形态 | ADR-009 |
| 图标 | 统一 **Remix Icon**（App 既有依赖），禁 emoji 作功能图标 | ADR-010 |

### 4.3 Rust API 契约（16 接口点 + 弹幕）

句柄：`#[frb(opaque)] LiveBilibiliSite`（App 每平台单例持有）。

| # | 说明 | 签名（FRB 可见） | 覆盖 |
|---|------|------------------|------|
| P1/P2 | 站点属性 | `id() -> String`（`"bilibili"`）/ `name() -> String`（`"哔哩哔哩直播"`） | ✓ |
| M1 | 弹幕入口 | `get_danmaku() -> LiveBilibiliDanmaku` | ✓ |
| M2 | 分类 | `get_categories() -> Result<Vec<LiveCategory>, CoreError>` | F-01 |
| M3 | 搜索房间 | `search_rooms(keyword, page) -> Result<LiveSearchRoomResult, CoreError>` | F-04 |
| M4 | 搜索主播 | `search_anchors(keyword, page) -> Result<LiveSearchAnchorResult, CoreError>` | F-05 |
| M5 | 分类下房间 | `get_category_rooms(category, page, page_size: Option<i32>) -> Result<LiveCategoryResult, CoreError>` | F-02 |
| M6 | 推荐 | `get_recommend_rooms(page, page_size: Option<i32>) -> Result<LiveCategoryResult, CoreError>` | F-03 |
| M7 | 房间详情 | `get_room_detail(room_id) -> Result<LiveRoomDetail, CoreError>` | F-06 |
| M8 | 清晰度 | `get_play_qualities(detail) -> Result<Vec<LivePlayQuality>, CoreError>` | F-07 |
| M9 | 播放地址 | `get_play_urls(detail, quality) -> Result<LivePlayUrl, CoreError>` | F-08 |
| M10 | 直播状态 | `get_live_status(room_id) -> Result<bool, CoreError>` | F-09 |
| M11 | SC 列表 | `get_super_chat_messages(room_id) -> Result<Vec<LiveSuperChatMessage>, CoreError>`（**复数对齐上游**，绑定层还原 Dart 单数名） | F-10 |
| M12 | 注入凭证 | `set_site_attrs(data: String) -> Result<(), CoreError>` | F-17 |
| M13 | 二维码 | `get_qr_code() -> Result<QrCode, CoreError>` | F-18 |
| M14 | 扫码轮询 | `get_qr_poll_result(qrcode_key) -> Result<QrPollResult, CoreError>` | F-19 |
| M15 | 账号信息 | `get_account_info(credential) -> Result<AccountInfo, CoreError>`（成功时**回填** `user_id`） | F-20 |
| D1–D6 | 弹幕 | `connect(...) -> impl Stream<Item=LiveDanmuItem>` / `disconnect(conn)`；`heartbeat()` **不暴露** | F-11~F-16 |

**B站本轮覆盖：全部（15 方法 + 2 属性 + 弹幕全链路）**；其余 4 平台继续走 Dart。

### 4.4 数据形状（要点）

- 模型命名对齐上游 `Live*` 风格；**字段语义保留 Dart core**（`children`、保留 `emoticons`/`color`）。
- 20 类模型逐字段映射见 `10-architecture.md §3`。
- `LiveMessage.data` 用**类型化枚举** `LiveMessageData{Online(i32), SuperChat(LiveSuperChatMessage)}`（保 AC-12/AC-15）。
- `LiveRoomDetail.data`/`danmakuData`（Dart `dynamic`）→ **JSON String**；`danmakuData` 承载 `BiliBiliDanmakuArgs`，键名钉死为 `room_id/uid/token/server_host/buvid/cookie`，**必须**有往返 + golden 断言。
- `LivePlayQuality.data` 存 `qn` 十进制字符串，消费时解析失败 → `CoreError(InvalidInput)`。

---

## 5–7. 不适用章节（显式声明，避免空洞占位）

| 章节 | 结论 | 理由 |
|------|------|------|
| DB 表清单 | **不适用** | 本轮不新增任何数据库/持久化；只读平台接口 |
| 页面清单 | **不适用** | UI 零改动（AC-32）；无新增路由/组件 |
| 设计 Token / 主题 / 字体 | **不适用** | 无 UI 变更。**UI 锁定口径**（后续变更须遵守）：统一 Remix Icon、禁 emoji 图标、禁紫→粉渐变、禁硬编码颜色 |

---

## 8. 验收标准（QA 唯一依据）

**39 条 AC，全部为「夹具输入 → 期望输出」或真实命令输出，机器可验证。** 详表见 `11-scope-and-acceptance.md §3`，编号索引：

| 组 | 编号 | 覆盖 |
|----|------|------|
| 成功流（21） | AC-01 ~ AC-21 | 分类/分类下房间/推荐/搜索房间/搜索主播/详情/清晰度/取流/状态/SC/弹幕握手/人气/多协议解码/聊天弹幕/WS SC/表情包/凭证注入/二维码/轮询/账号信息/请求头与 wbi |
| 错误·边界（8） | AC-22 ~ AC-29 | 未开播/房间不存在/凭证无效/风控码(-352)/HTTP 失败与 WS 重连/空页/脏帧/未知清晰度 |
| 回归约束（5） | AC-30 ~ AC-34 | 其余 4 平台零新增失败/可回退/UI 零变化/门禁（≤300 行·依赖向下·无 emoji·无占位）/Dart B站代码保留至回退窗口（**窗口结束判据见 J-9**） |
| 反作弊（4） | AC-35 ~ AC-38 | 确定性 golden/held-out 留出集/实现与测试 diff 分离/真实命令输出 |
| **绑定层与凭证安全（2）** | **AC-39 ~ AC-40** | AC-39 绑定层只做类型翻译与转发、**零协议逻辑**（URL 拼接 / 签名 / 帧编解码 / 重连策略 / 解析）、**结构可判定如下**：桥 crate 不得含上述协议符号与实现，**允许**持有 WS/HTTP **传输依赖**作为连接工厂的注入实现（`tokio-tungstenite` 由桥层提供 `ConnectFactory`，与 `HttpTransport` 由 core 定 trait、运行时注入同构；口径修订：2026-10-17 合并前评审裁定）；AC-40 凭证注入/账号校验后日志（含调试输出）**不得**出现 credential/cookie 明文（断言不含 `SESSDATA` 等子串，对齐 `bilibili_site.dart:598` 教训） |

---

## 9. 边界与约束

- **性能**：每类 B站请求不得引入额外串行往返（请求数 ≤ Dart core 同路径，以拦截到的请求集合断言）。
- **安全**：credential/cookie **禁止**写入日志（`bilibili_site.dart:598` 的 `CoreLog.i(cookieStr)` 行为**不得**复刻）；仅 HTTPS。
- **可回退**：开关（`kUseRustBilibili`）关闭时全走 Dart（**运行时回退**，2026-10-17 re-baseline：Rust 库随 App 构建为硬依赖，见 AC-31 判定口径修订）。
- **可维护**：三层分层、依赖只向下、**单文件 ≤300 行**、按能力拆文件（`site.rs` 仅编排）。
- **回归判定口径（采纳 QA 建议）**：离线子集**零新增失败** + 联网子集**失败同质**（联网用例自身 flaky 是既有共识，不做精确条数比对）。比对方式 = 失败「文件 + 用例名」**集合相等**，差值即新增/消除。基准快照：`16-app-regression-baseline.md §4`（App 564/549/15，core 84/80/4）。
- **测试环境前置（必做）**：本机代理变量会让 `flutter test` 的 loopback WebSocket 走代理 → 报 `Invalid WebSocket upgrade request` 且表现为 `+0 -55` 全挂。**跑测试必须隔离**：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY="localhost,127.0.0.1,::1" no_proxy="..." fvm flutter test --no-pub`。
- **不适用**：国际化（无文案变化）、埋点（内部迁移，不新增/修改任何埋点）。

---

## 10. 内嵌已知坑（防重蹈覆辙）

| 坑 | 技术栈指纹 | 根因 | 修法 |
|----|-----------|------|------|
| FRB 两侧版本漂移 | flutter_rust_bridge | Dart pubspec 与 Rust Cargo.toml 版本不一致时 `RustLib.init()` 抛异常且**不提示版本** | 两侧都钉精确 `2.13.0`；codegen 版本亦须一致 |
| Android OpenSSL 构建失败 | reqwest/openssl-sys | `openssl-sys` build script 在 NDK 下失败 → `.so` 缺失 → dlopen 失败 | 改用 `rustls-tls`（ADR-003） |
| Windows Gradle 静默产出无 `.so` 的 APK | cargokit | `run_build_tool.cmd` 未传播 build_tool 非零退出码 | 核验 vendored cargokit 是否含修复；构建后**校验产物存在**，不只看 `flutter run` 退出码 |
| `brotlic`(C) 在 NDK 下需 CMake | brotlic | C 绑定交叉编译复杂 | 用纯 Rust `brotli` + `flate2`(rust_backend) |
| chrono 时区/单位差异 | chrono + FRB | native 微秒 / web 毫秒，且总转设备本地时 | `DateTime<Local>`；实现期以真值断言校准 |
| 进程级缓存 → 句柄级缓存 | wbi 缓存 | Dart core 的 `kImgKey/kSubKey/accessId` 是**静态**（进程级） | 迁到句柄级属行为不变（请求参数集合一致）；若判为契约变更则回退 `OnceCell` |
| 本机 SDK 版本 | fvm | `.fvmrc` 钉 3.47.6，本机可能仅 3.47.5 | 实现期先 `fvm install 3.47.6` |

---

## 11. 端到端验证步骤（Spec 收尾）

```bash
# 1) 依赖与构建核验
cd simple_live_core
cargo tree -p slive-core | grep -E "reqwest|rustls|brotli|flate2"
cargo build -p slive-core && cargo clippy -p slive-core -- -D warnings

# 2) 离线单测（覆盖 AC-01~AC-29；skip/ignore/xfail 必须为 0）
cargo test -p slive-core -- --nocapture > ../../docs/rust-core/evidence-cargo-test.log 2>&1; echo rc=$?
# held-out 留出集（AC-36，实现者不可见）
cargo test -p slive-core --features heldout

# 3) FRB 代码生成（版本须 =2.13.0）
flutter_rust_bridge_codegen --version && flutter_rust_bridge_codegen generate

# 4) App 侧编译与回归（其余 4 平台零新增失败）
cd ../simple_live_app && flutter analyze && flutter test

# 5) 端到端（固定房间：详情→清晰度→取流→弹幕 30s 窗口 + 一条错误流）
flutter test integration_test/rust_bilibili_e2e_test.dart
```

---

## 12. 总监裁决记录（本 Spec 的锁定口径）

| # | 事项 | 裁决 | 理由 |
|---|------|------|------|
| J-1 | 账号体系是否进本轮（RISK-03） | **全进**（F-17~F-20，纯 HTTP 无 webview） | D3 是「B站全部方法」；缺失会破坏 App 可用性 |
| J-2 | `LiveMessage` 形态（RISK-01/02） | **保留** `emoticons`/`color`/`data`；`data` 用类型化枚举；`data/danmakuData` 走 JSON String（须有往返+golden 断言、解析失败行为钉死） | "对齐上游"指命名风格，非裁能力；上游无 emoticons 是它的缺口 |
| J-3 | `pageSize`（RISK-04） | **保留** | fork 语义且 B站推荐真用；在 AC-30 回归约束内 |
| J-4 | SC 命名（RISK-05） | Rust 用上游复数 `get_super_chat_messages`；绑定层映射为 Dart 可见单数 `getSuperChatMessage`。**不额外暴露复数别名**（避免冗余 API 面） | 语义以 core 为准（不丢能力）、命名风格对齐上游；Dart 可见名不变以守住 AC-32 |
| J-5 | 错误口径（RISK-06/08） | 非法 JSON → 抛类型化错误；缺 `cookie` 键 → 保留旧值；风控码 → 抛带 message 错误、**不自动重试** | 与 Dart core 现状一致 |
| J-6 | 绑定层边界（R-13） | **接受绑定层，但刚性**：只做类型翻译/转发，**零协议逻辑**；B站路径不保留 Dart 协议实现（旧实现仅作回退目标，窗口结束即删） | D2 的目的是消灭 Dart 侧重复协议实现；绑定层承载协议逻辑即退化为被否决的"薄壳" |
| J-7 | AC-39 可判定性增强（采纳 PM advisory） | 绑定层所在 crate **不得依赖** http/ws/签名相关 crate（**编译期结构约束**），使 AC-39 从"人工代码审查"升级为"结构可判定" | 防止绑定层悄悄长出协议逻辑、退化成 Dart 薄壳 |
| J-8 | SC 别名（采纳 PM advisory 的收敛） | **不**同时暴露单数/复数两个 Rust 接口；由绑定层单点映射 | 最小化 API 面，避免两个名字各写一套测试 |
| J-9 | **回退窗口"结束"的判据**（采纳架构师 advisory） | 可判定定义 —— 三者**同时**满足方为窗口结束：① 开关 `kUseRustBilibili` 默认置 **true**（Rust 成为 B站默认路径）；② 该状态经过**一个完整发布周期**（Rust 默认版发布 → 下一版发布）；③ 期间 B站相关 **P0 回归为零**。齐备后方可删除 Dart 侧 B站三文件（AC-34） | 否则"窗口结束即删"没有触发点，AC-34 / R-18 动作无判据 |
| J-10 | JSON 通道的 Dart 侧失败行为（采纳架构师方案） | 绑定层**不解析**该串；契约规定任何 Dart 消费者解析失败**必须抛 `FormatException`**，**不得静默兜底** | 静默兜底是"沉默逻辑错误"高发区，与 AC-35 自证禁令冲突 |

---

## 13. 变更记录

| 日期 | 变更内容 | 原因 | 影响范围 |
|------|----------|------|----------|
| 2026-10-16 | 初始版本 v1.0（Phase 1.5） | 用户确认 D1–D6 与三方向后汇编 | 全部 |
| 2026-10-16 | 并入 PM 修订（AC-39/AC-40）与总监裁决 J-1~J-8；AC 索引扩至 **40 条** | Phase 1 两份文档（PM 范围 / 架构方案）交叉校验后定稿 | §8 / §12 |
| 2026-10-16 | 补 J-9（回退窗口结束判据）/ J-10（JSON 通道 Dart 侧失败行为）；采纳架构师 JSON 通道加固（`schema_version` + 单测三条 + 缺字段/非法串 → `CoreError(Decode)`） | 架构师 advisory + 交叉校验收口 | §8 / §12 |
| 2026-10-16 | 补记实测锁定：crate 路径 `simple_live_core/crates/slive-core`（spike 定，勿移）、`reqwest 0.12`、`async-trait 0.1`；§9 增回归判定口径与测试环境前置（代理隔离） | spike 通过后回写实测值（活规格：实现与文档同步） | §4.1 / §9 |
| 2026-10-16 | **实现期差异修订（DoD-8）**：① Dart 侧需 `freezed 3.x`（FRB 2.13 对有数据枚举强制 freezed；2.x 与 hive_ce_generator 冲突）；② `startDanmaku` 为 Stream 形态，连接句柄存全局 + `stop_danmaku()`（单房间语义）；③ 绑定层 `setSiteAttrs` 用 pending 模式（同步 void vs FRB async 句柄）；④ **nav 匿名响应 code=-101 但 wbi_img 有效**（真实冒烟发现）→ `getWbiKeys` 不做通用 code 检查；⑤ join 后立即发首心跳；⑥ `quality.data` 以字符串往返（仅绑定层内部使用） | 真实网络冒烟 + 实现期验证（活规格） | §4.1 / §4.4 / §13 |
| 2026-10-16 | **IP-2 交付后用户验收通过**（B站真机与 Dart core 体验一致）；**真机三类修复**：① FRB FFI 线程无 tokio runtime → `tokio::spawn` panic 被吞（弹幕会话改独立线程+自建 runtime）；② 登录 cookie 与 uid=0 矛盾 → 服务端 reset（F-06 组装前先回填 mid）；③ WS 握手补 UA+Origin | 用户真机上手反馈 + debug run 日志定位 | §10 / §13 |
| 2026-10-16 | **启动其余平台迁移**：IP-3 斗鱼（TARS 弹幕，DTV 1724 行参考）→ IP-4 虎牙（TARS）→ IP-5 twitch（IRC，上游有骨架）→ IP-6 抖音（abogus/protobuf，最复杂殿后）。每平台对齐 B站范式：site 全方法 + 弹幕全链路 + 账号 + FRB 桥 + Dart 绑定层 + 离线测试。斗鱼 renewers（FRB 回调）登记待办 O-7 | 用户指令"其他平台也都 Rust 化" | 全部 |
