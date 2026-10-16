# Rust Core 落地第一步 · 技术架构方案

> 版本锚点：`dart_simple_live` fork future @ `4dcdb4fe` · worktree `feat/core-rust` · `2026-10-16`
> 交付边界：**crate 骨架 + B站（bilibili）端到端**（`docs/rust-core/00-briefing.md` D1–D6）
> 验收依据：`docs/rust-core/11-scope-and-acceptance.md`（AC-01 ~ AC-38）
> 桥接：`flutter_rust_bridge = 2.13.0`（D6，精确钉版本）
> 关联：`docs/rust-core/00-briefing.md` · `docs/rust-core/12-bilibili-mapping.md` · `docs/decisions/ADR-00x.md`
> 引用规范：`references/01-standards/spec-as-contract.md`（点名文件/接口、钉版本、内嵌坑、端到端验证）· `references/01-standards/context-engineering.md`（只引用指针不堆全文）· `references/01-standards/generated-code-failure-modes.md`（幻觉依赖/接口存在性核验、构建即验证）· `references/architecture/mvp-stack.md`（MVP 选型）· `references/cost-models/development-costs.md`（可行性评估）
> 说明：本方案只给**架构与选型**；逐字段/逐方法落点表见 `12-bilibili-mapping.md`。实现与本文冲突时先改本文再改代码（活规格）。

---

## 0. 结论速览（先读这一节）

| 议题 | 结论 | 依据 |
|------|------|------|
| 工作区结构 | 把现 `simple_live_app/rust/` 升级为 **cargo workspace**；新增**纯核心 crate `slive-core`**（无 FRB），现 crate `rust_lib_simple_live_app` **原地保留作 FRB 桥** | §1 / ADR-001 |
| FRB | **精确 `=2.13.0`**；复用现 `flutter_rust_bridge.yaml` 与 `rust_builder`（cargokit 零改动）；生成代码**入库** | §2 / ADR-002 |
| TLS | `reqwest`+`tokio-tungstenite` 统一走 **rustls（纯 Rust）+ webpki-roots**；**不**用 openssl-sys vendored | §8 / ADR-003 |
| 压缩 | **纯 Rust 后端**：brotli 用 `brotli` crate、zlib 用 `flate2`(miniz_oxide)，避免 NDK 编译 C 依赖 | §8 / ADR-003 |
| 弹幕推送 | Rust→Dart 用 **FRB `StreamSink<LiveDanmuItem>`**；`LiveDanmuItem = Message | Control(Ready/Closed/…)`，替代轮询 `receive()` 与 Dart 回调 | §5 / ADR-004 |
| 状态 | 用**不透明句柄 `LiveBilibiliSite`**（FRB `opaque`）承载 cookie/uid/buvid/wbi 缓存 + 复用 `reqwest::Client`；**弃** `tauri::State` 与进程级全局单例 | §6 / ADR-005 |
| 错误 | core `SliveError`(thiserror) → FRB 可见 `CoreError{message,status_code}` → App 适配层映射回 Dart `CoreError` | §7 / ADR-006 |
| 模型暴露 | 模型定义在 `slive-core`，桥层用 `#[frb(mirror)]` 暴露（回退：显式 `From`） | §3 / ADR-007 |
| 账号体系 | **全进本轮**，F-17~F-20 全部实现为**纯 HTTP（无 webview）** | §4 / ADR-012 |
| 命名口径 | **方法集合与语义以 Dart core 为准（不丢能力）；命名风格对齐上游**（SC 用上游复数 `getSuperChatMessages`） | §1.4 / §4 / ADR-012 |
| data 通道 | `LiveRoomDetail.data/danmakuData`（Dart `dynamic`）→ **JSON String**，契约与断言见 §3.3；`LiveMessage.data` → 类型化枚举 | §3.3 / ADR-012 |
| 离线夹具 | 录制真实响应/帧 + 合成边界夹具；含 **held-out 留出集**（AC-36） | §8.4 / ADR-011 |
| App 分派 | `simple_live_app/lib/app/sites.dart:15` 单点分派；`RustBilibiliSite implements LiveSite`（绑定层），开关默认关、可一键回退 | §9 / ADR-008 |
| 上游依赖 | **不**把 `SlotSun/slive-core-api-rust` 作为依赖；只对齐其 API/命名形态（D4） | §1 / ADR-009 |

> **D4 口径澄清（依据总监裁决 2/4）**：「对齐上游形态」仅指**命名与结构化风格**对齐；**能力集合与字段语义一律以 Dart core 为准**。上游缺失的能力（emoticons / 账号 / mcdn / 分类 A / 推荐 / 搜索主播 / SC）是上游的缺口，不是本轮的裁剪目标。
>
> **参考基准澄清（依据总监修正 + PM §4）**：**`C:\DTV` 不是「平台实现主参考」**——它缺 core 独有的 **9 项**能力（分类 A 列表、推荐、搜索主播、SC(HTTP+WS)、表情包解析、账号三接口 + `userId` 回填、zlib(ver2) 解压分支、mcdn 后置排序）。这 9 项**必须从 Dart core 重实现**；DTV 仅作**局部增强参考**（`d1--cn` 优先 / HLS 重试），且**不得替换既有语义**（否则违反 AC-30/AC-32）。逐项标注见 `12-bilibili-mapping.md §7`。

---

## 1. crate / workspace 结构与命名

### 1.1 现状与约束

- 仓库内唯一 Rust 工程：`simple_live_app/rust/`（crate `rust_lib_simple_live_app`，FRB 2.13.0，含 `src/api/danmaku_mask.rs`），由 `simple_live_app/rust_builder/` 经 **cargokit** 构建，`cargokit { manifestDir = "../../rust"; libname = "rust_lib_simple_live_app" }`（`rust_builder/android/build.gradle` 尾部；ios/macos podspec、linux/windows CMake 同口径）。
- 3 个 Flutter 前端共用 `simple_live_core`（Dart）：`simple_live_app`、`simple_live_console`、`simple_live_tv_app`（各自 `pubspec.yaml` 的 `simple_live_core: path: ../simple_live_core`）。
- 需求要求「**支持未来 Flutter 之外的 Tauri 等前端复用**」（briefing 附录 A 第 1 条），且 D2 要求「Dart 直连 FRB API」。

### 1.2 方案对比矩阵（打分：5 最好 / 1 最差）

| 维度（权重） | A 单 crate（`api/`+`core/` 模块） | **B workspace：纯核心 + 桥（推荐）** | C 直接依赖上游 `platforms-parser`(git) |
|---|---|---|---|
| 非 Flutter 前端复用（高） | 3（Tauri 须依赖含 FRB 的整 crate） | **5**（`slive-core` 无 FRB，可 path/git 依赖） | 4（上游 crate 可依赖，但绑上游仓库） |
| 回归风险（高） | **5**（不动 cargokit） | **5**（不动 cargokit；桥 crate 原地不挪） | 2（引入 git 依赖 + 覆盖度未知） |
| 构建/维护复杂度（高） | **5**（一个 Cargo.toml） | 4（多一个成员 crate） | 3（跨仓版本漂移） |
| 与 D4「对齐上游形态」（高） | 4 | **5**（核心/桥两层与上游 `platforms-parser`+`slive_native` 同构） | 5 |
| 过度设计风险（高，越低越好） | **5** | 4（多一层 crate，但有复用硬需求支撑） | 2（上游 `45d401d8` 正清理 AI 过度设计的转换层） |
| 合计 | 22 | **23** | 16 |

**选型：B。** 单 crate（A）差一个可复用的核心边界；C 直接继承上游的过度设计与覆盖度不确定性（`spec-as-contract` 的「幻觉依赖」防护要求依赖存在性核验，而 C 的依赖覆盖面需逐文件核实，成本高）。

### 1.3 目标目录（本轮落地）

```
simple_live_app/rust/                     # cargo workspace 根（现 FRB 工程原地升级）
  Cargo.toml                              # [workspace] members = ["crates/slive-core"] + [package] rust_lib_simple_live_app
  rust-toolchain.toml                     # 新增：钉 rust channel（可复现）
  src/
    lib.rs                                # pub mod api; mod frb_generated;
    frb_generated.rs                      # FRB 生成（入库）
    api/                                  # rust_input: crate::api（现配置不变）
      mod.rs                              # + pub mod slive;
      danmaku_mask.rs                     # 既有，不动
      simple.rs                           # 既有，不动
      slive/
        mod.rs                            # FRB 出口：pub use 门面
        site.rs                           # #[frb(opaque)] LiveBilibiliSite（15 方法门面）
        danmaku.rs                        # #[frb] 弹幕 Stream 门面 + LiveDanmuConnection
        error.rs                          # FRB 可见 #[frb] CoreError{message,status_code}
        models/
          mod.rs  category.rs  room.rs  play.rs  message.rs  account.rs
  crates/
    slive-core/                           # 纯核心 crate（无 FRB 依赖）
      Cargo.toml                          # async-trait/thiserror/md-5/reqwest(rustls)；dev: tokio
      src/
        lib.rs                            # 分层再导出
        error.rs                          # SliveError（thiserror）+ status_code 映射
        time.rs                           # TimeSource trait + SystemClock（seam #2/#3）
        http.rs                           # HttpTransport trait + ReqwestTransport（seam #1）
        testing.rs                        # #[cfg(any(test,feature="testing"))] 测试替身：FakeTime/RecordingTransport/ScriptedFrameSource
        wbi.rs                            # wbi 签名 + mixin 表（F-22；纯函数，wts 入参）
        buvid.rs                          # buvid3/4 指纹（F-21）
        ws/
          mod.rs                          # WsSessionConfig + FrameSource trait + 重连策略（seam #2）
          frame.rs                        # WS 帧编解码（F-13）
          session.rs                      # 心跳/重连会话（注入 FrameSource + TimeSource）
        models/                           # 与 Dart core 同构的跨平台强类型（无 #[frb]）
          mod.rs  category.rs  room.rs  play.rs  message.rs  account.rs
        platforms/
          mod.rs
          bilibili/
            mod.rs
            site.rs                       # BilibiliSite：15 方法编排
            categories.rs                 # F-01
            rooms.rs                      # F-02 / F-03
            search.rs                     # F-04 / F-05
            detail.rs                     # F-06
            play.rs                       # F-07 / F-08
            status.rs                     # F-09
            super_chat.rs                 # F-10
            account.rs                    # F-17 ~ F-20
            danmaku/
              mod.rs  protocol.rs  session.rs  parse.rs  emoticon.rs   # F-11 ~ F-16
```

**依赖方向（单向，只向下）**：`api（桥） → slive-core::platforms → slive-core::{models, http/ws, error}`；`models` 不依赖 `platforms`；`slive-core` **不得**依赖 FRB（守复用边界）。对应 Dart core 的既有分层口径（`simple_live_core/doc/architecture.md §2`）。

**单文件 ≤300 行落地方式（AC-33）**：按**能力**而非按类拆文件（`categories.rs` 只放分类；`play.rs` 只放清晰度+取流）。B站 `site.rs` 只做**编排**（转调各能力模块并组装），预计 <150 行；`bilibili_emoticon.dart`（300 行）在 Rust 侧拆为 `emoticon.rs` + 其内部纯函数测试同文件下移。

### 1.4 命名规范

- crate：`slive-core`（lib `slive_core`）；桥 crate 名**保持不变**（`rust_lib_simple_live_app`）——避免改 cargokit。
- Rust 类型/函数：**命名风格对齐上游 slive_core**（D4）：模型 `Live*`、字段 snake_case（`room_id`/`user_name`/`has_more`）；函数 `get_categories`/`get_room_detail`/`get_super_chat_messages`（**复数，对齐上游**）。
- **能力集合与语义以 Dart core 为准**（总监裁决 4）：上游缺的能力不得因命名对齐而裁剪。Rust API 采用上游命名风格；`simple_live_core` 的 Dart `LiveSite` 接口**保持不变**（AC-32 UI 零变化），由绑定层 `RustBilibiliSite` 在实现 `LiveSite` 时把上游命名（复数）适配到接口命名（`getSuperChatMessage` 单数）。**不**为迁就旧名而改 Rust 命名（裁决 4）。

---

### 1.5 可测试性 seam（注入点，硬前提；QA 测试计划要求）

> 不预留则 AC-01~AC-29 的 HTTP/WS 大部分无法离线验证。已在骨架中以**真实代码**落地（非占位）。

| seam | 抽象（trait） | 生产实现 | 测试替身 | 支撑的 AC |
|---|---|---|---|---|
| #1 HTTP 传输 | `http::HttpTransport` | `http::ReqwestTransport`（reqwest+rustls） | `testing::RecordingTransport`（记录请求次数/参数） | AC-25（风控码不重试 → **请求次数==1**）等 |
| #2 WS 事件源 + 时序 | `ws::FrameSource` + `time::TimeSource` | `time::SystemClock`（+真实 WS 帧源，随 F-11 落地） | `testing::ScriptedFrameSource` + `testing::FakeTime` | AC-26（`5s×5` 重连，**不依赖墙钟**） |
| #3 wbi `wts` 时间源 | `time::TimeSource` | `time::SystemClock` | `testing::FakeTime` | AC-21（固定入参 → 固定 `w_rid`） |

- 注入形态：`BilibiliSite::with_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>)`（测试用）；`BilibiliSite::new()` 注入真实实现。协议方法一律经注入的 `http`/`time`，**不直连网络、不读墙钟**。
- 测试替身经 `--features testing` 暴露给集成测试（生产默认不编译）；详见 §4.1。

---

## 2. FRB 2.13.0 集成方案

### 2.1 与现有资产的关系

| 资产 | 处置 |
|------|------|
| `simple_live_app/flutter_rust_bridge.yaml`（`rust_input: crate::api` / `rust_root: rust/` / `dart_output: lib/src/rust`） | **不改**。新增 `api/slive/**` 会被自动扫描 |
| `simple_live_app/rust_builder/`（cargokit + 5 平台工程） | **不改**（`manifestDir=../../rust`、`libname=rust_lib_simple_live_app` 保持） |
| `simple_live_app/rust/src/api/{danmaku_mask.rs,simple.rs}` | **不动**（`main.dart:71 RustLib.init()` 已有；`live_room_controller.dart` 的 `DanmakuMask` 调用不受影响） |
| 生成代码 `rust/src/frb_generated.rs`、`simple_live_app/lib/src/rust/**` | **入库**（现 `.gitignore` 仅排除 `/target`，与现口径一致） |
| 上游 slive_core 的 `cargokit/` + `rust_builder/`（2.12.0 口径） | **不整包引入**；仅在需要时对照 cargokit 补丁（见 §11 Windows 坑） |

### 2.2 版本钉死与代码生成（`spec-as-contract` 的「版本锚定」）

- Rust：`flutter_rust_bridge = "=2.13.0"`（精确，禁 caret）。
- Dart：`pubspec.yaml` 现为 `flutter_rust_bridge: ^2.13.0` → **改为 `2.13.0`（精确）**。依据：FRB 的 Dart 运行库与 Rust 侧版本不一致时 `RustLib.init()` 会抛异常且报错不提示版本（实证：`fluttercandies/fjs` CHANGELOG「Dart 侧 pubspec 与 Rust 侧 Cargo.toml 被刻意双双固定;两侧一旦不一致,App 启动时 RustLib.init 会直接抛异常,而报错信息并不会提示版本问题」）。
- 生成命令（引入 `flutter_rust_bridge_codegen`，版本须与运行库**完全一致**）：
  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.13.0   # 精确
  cd simple_live_app && flutter_rust_bridge_codegen generate
  ```
- **Dart SDK 下限**：FRB 2.13.0 要求 Dart SDK ≥ 3.9.2（fjs CHANGELOG 3.3.2 条目）。当前 `simple_live_app` 钉 Flutter `3.47.6`（`.fvmrc`），须在实现阶段用 `fvm install 3.47.6` 后核验 `dart --version`（briefing §6 已记录本机可能仅到 3.47.5）。

### 2.3 生成代码入库的取舍

| 选项 | 结论 |
|------|------|
| 入库（选） | 与仓库现状一致；CI/评审可复现；回归可对生成物 diff |
| 不入库 | 需在每次构建前跑 codegen，增加构建不确定性与工具链耦合；MVP 不取 |

---

## 3. 模型映射表（`spec-as-contract` 要求「点名接口与数据形状」）

命名对齐上游 `live_*` 风格；**字段语义保留 Dart core 契约**（`children` 而非上游 `sub_categories`、`dynamic`→JSON String、保留 `emoticons`/`color`），以保证 AC-16/AC-30/AC-32。FRB 不能直接桥接 `serde_json::Value` 与部分泛型，故「无形状约束的平台私有数据」统一序列化为 JSON `String`（RISK-02）。

### 3.1 列表 / 详情 / 取流 / 消息 / 账号

来源：`simple_live_core/lib/src/model/*`、`lib/src/platforms/bilibili/bilibili_site.dart`、`lib/src/common/qr_status.dart`。

| Dart（源） | 字段（Dart 类型 / 可空） | Rust（`slive-core::models`） | 序列化/桥接 |
|---|---|---|---|
| `LiveCategory` (`live_category.dart`) | `name:String` `id:String` `children:List<LiveSubCategory>` | `LiveCategory { name:String, id:String, children:Vec<LiveSubCategory> }` | 直接 |
| `LiveSubCategory` (同上) | `name:String` `pic:String?` `id:String` `parentId:String` | `LiveSubCategory { name:String, pic:Option<String>, id:String, parent_id:String }` | 直接；`parent_id` 保持非空（缺失→`""`，对齐 `bilibili_site.dart:67`） |
| `LiveRoomItem` (`live_room_item.dart`) | `roomId:String` `title:String` `cover:String` `userName:String` `online:int` | `LiveRoomItem { room_id, title, cover, user_name, online:i32 }` | `online` 用 `i32`（B站人气为 int32 量级）；**不**引入上游的 `user_avatar/url/platform`（保持 Dart 契约） |
| `LiveAnchorItem` (`live_anchor_item.dart`) | `roomId:String` `avatar:String` `userName:String` `liveStatus:bool` | `LiveAnchorItem { room_id, avatar, user_name, live_status:bool }` | 直接（**不**用上游的 `user_id/user_avatar/is_live` 命名） |
| `LiveRoomDetail` (`live_room_detail.dart`) | `roomId,title,cover,userName,userAvatar:String` `online:int` `introduction:String?` `notice:String?` `status:bool` `data:dynamic` `danmakuData:dynamic` `isRecord:bool` `url:String` | `LiveRoomDetail { room_id,title,cover,user_name,user_avatar, online:i32, introduction:Option<String>, notice:Option<String>, status:bool, data:Option<String>, danmaku_data:Option<String>, is_record:bool, url:String }` | `data/danmakuData`：`dynamic` → JSON 字符串（RISK-02）；`danmakuData` 承载 `BiliBiliDanmakuArgs` 序列化 |
| `LivePlayQuality` (`live_play_quality.dart`) | `quality:String` `data:dynamic` `sort:int` | `LivePlayQuality { quality:String, data:String, sort:i32 }` | `data` 存 qn（B站为整型，按上游口径落 `String`；回传 `getPlayUrls` 时解析回整型） |
| `LivePlayUrl` (`live_play_url.dart`) | `urls:List<String>` `headers:Map<String,String>?` `renewers:…?` | `LivePlayUrl { urls:Vec<String>, headers:Option<HashMap<String,String>> }` | `renewers` 排除（O-7，仅斗鱼） |
| `LiveSearchRoomResult` (`live_search_result.dart`) | `hasMore:bool` `items:List<LiveRoomItem>` | `LiveSearchRoomResult { has_more:bool, items:Vec<LiveRoomItem> }` | 直接 |
| `LiveSearchAnchorResult` (同上) | `hasMore:bool` `items:List<LiveAnchorItem>` | `LiveSearchAnchorResult { has_more:bool, items:Vec<LiveAnchorItem> }` | 直接 |
| `LiveCategoryResult` (`live_category_result.dart`) | `hasMore:bool` `items:List<LiveRoomItem>` | `LiveCategoryResult { has_more:bool, items:Vec<LiveRoomItem> }` | 直接 |
| `LiveMessage` (`live_message.dart`) | `type:LiveMessageType` `userName:String` `userId:String?` `message:String` `data:dynamic` `color:LiveMessageColor` `emoticons:List<LiveMessageEmoticon>?` | `LiveMessage { message_type:LiveMessageType, user_name:String, user_id:Option<String>, message:String, data:Option<LiveMessageData>, color:LiveMessageColor, emoticons:Option<Vec<LiveMessageEmoticon>> }` | **保留 Dart 语义**（RISK-01）：`data` 用**类型化枚举** `LiveMessageData{Online(i32), SuperChat(LiveSuperChatMessage)}`，以保住 AC-12（人气 int32）与 AC-15（SC 结构体） |
| `LiveMessageType` (enum) | `chat/gift/online/superChat` | `enum LiveMessageType { Chat, Gift, Online, SuperChat }` | FRB 生成 Dart enum |
| `LiveMessageColor` (`live_message.dart`) | `r,g,b:int`；`white`；`numberToColor(int)` | `LiveMessageColor { r:i32, g:i32, b:i32 }`；`fn white() -> Self`；`fn number_to_color(i32) -> Self` | 直接 |
| `LiveMessageEmoticon` (`live_message.dart`) | `name:String?` `url:String` `width:int?` `height:int?` `large:bool` `emoticonUnique:String?` | `LiveMessageEmoticon { name:Option<String>, url:String, width:Option<i32>, height:Option<i32>, large:bool, emoticon_unique:Option<String> }` | 直接（**上游无此类型**，fork 独有，必须自建） |
| `LiveSuperChatMessage` (`live_message.dart`) | `userName,face,message:String` `price:int` `startTime:DateTime` `endTime:DateTime` `backgroundColor,backgroundBottomColor:String` | `LiveSuperChatMessage { user_name, face, message:String, price:i32, start_time:DateTime<Local>, end_time:DateTime<Local>, background_color, background_bottom_color:String }` | FRB 原生支持 `chrono::DateTime`（需开 `features=["chrono"]`）→ Dart `DateTime`（证据：FRB 文档 DateTime(Chrono)） |
| `AccountInfo` (`account_info.dart`) | `name:String?` `avatar:String?` `uid:String?` `credential:String` `isValid:bool` | `AccountInfo { name:Option<String>, avatar:Option<String>, uid:Option<String>, credential:String, is_valid:bool }` | 直接 |
| `QRCode` (`account_qr_code.dart`) | `key:String` `url:String` `createdAt:int?` `expireAt:int?` | `QrCode { key:String, url:String, created_at:Option<i64>, expire_at:Option<i64> }` | 直接 |
| `QRPollResult` (同上) | `status:QRStatus` `credential:String` `message:String` | `QrPollResult { status:QrStatus, credential:String, message:String }` | 直接 |
| `QRStatus` (enum, `qr_status.dart`) | `loading/unscanned/scanned/expired/failed` | `enum QrStatus { Loading, Unscanned, Scanned, Expired, Failed }` | FRB enum |
| `BiliBiliDanmakuArgs` (`bilibili_danmaku.dart:14`) | `roomId:int` `token:String` `buvid:String` `serverHost:String` `uid:int` `cookie:String` | `BiliBilibiliDanmakuArgs { room_id:i64, token, buvid, server_host, uid:i64, cookie:String }` | 作为 `LiveRoomDetail.danmaku_data` 的 JSON 形状（RISK-02 钉死） |

### 3.2 模型暴露策略（如何让桥层看见 `slive-core` 的类型）

`rust_input: crate::api` 只扫描 `api` 模块。`slive-core` 的类型要出现在桥层签名里，需二选一：

| 选项 | 做法 | 代价 |
|---|---|---|
| **M（推荐）** `#[frb(mirror)]` | 桥层 `api/slive/models/*` 逐个 `#[frb(mirror(slive_core::models::X))] pub struct X {…同字段…}` | 需在桥层重复声明字段（机械），无转换代码；镜像与源分歧靠编译/测试兜底 |
| C `From` 显式转换 | 桥层另立 FRB 模型 + 双向 `impl From` | 代码量翻倍，即上游 `45d401d8` 正在清理的「过度设计转换层」 |
| S 单 crate | 模型直接放桥层 `api/`，无核心 crate | 放弃 `slive-core` 复用边界（即 §1 的 A 方案） |

**选型：M。** 若实现期 `mirror` 在跨 crate 场景出现阻塞，**回退到 C**（一次性、单层、无套娃）。此为 `generated-code-failure-modes` 的「接口存在性核验」落点：mirror 是否可用须在实现阶段用真实 `codegen` 跑通（DoD-1）后再定稿。

### 3.3 data / danmakuData 通道序列化契约（回应 RISK-02，总监要求钉死）

Dart core 用 `dynamic` 携带「平台私有数据」，FRB 无法桥接 `serde_json::Value`。契约如下（**必须**有单测断言）：

**(a) `LiveRoomDetail.data`（B站本轮为 `null`；保留通道）**
- Rust：`pub data: Option<String>`。B站 `get_room_detail` 不写 `data`（Dart core 亦不写，见 `bilibili_site.dart:239-258` 未传 `data`）；保留字段仅为将来平台复用通道。
- 断言：`assert detail.data.is_none()`（B站）。

**(b) `LiveRoomDetail.danmakuData`：承载 `BiliBiliDanmakuArgs` 的 JSON**

> 依据总监附加要求：JSON String 通道**必须** ① 固化契约（字段名/可选性/版本）② 配单测（happy + 缺字段 + 非法串，行为明确）③ 钉死 Dart 侧解析失败行为。

**① 契约固化（版本 + 字段表）**

```rust
// slive-core::platforms::bilibili::danmaku::args
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct BiliBiliDanmakuArgs {
    pub schema_version: i32,   // 固定 1；版本不符 → 反序列化后校验失败 (见下)
    pub room_id: i64,          // == realRoomId
    pub uid: i64,              // 站点 user_id（未登录为 0）
    pub token: String,         // getDanmuInfo.data.token
    pub server_host: String,   // host_list[0].host，空则 "broadcastlv.chat.bilibili.com"
    pub buvid: String,         // buvid3
    pub cookie: String,
}
pub const BILI_DANMAKU_ARGS_SCHEMA_VERSION: i32 = 1;
```

| 字段 | 类型 | 可选性 | 说明 |
|---|---|---|---|
| `schema_version` | `i32` | **必填** | 固定 `1`；消费方校验 `== 1`，否则拒绝 |
| `room_id` | `i64` | 必填 | 真实房间号 |
| `uid` | `i64` | 必填 | 未登录为 `0` |
| `token` | `String` | 必填 | 允许空串（服务端异常时），空串不阻断连接 |
| `server_host` | `String` | 必填 | 空则回落 `broadcastlv.chat.bilibili.com` |
| `buvid` | `String` | 必填 | 允许空串 |
| `cookie` | `String` | 必填 | 允许空串（未登录） |

- 键名 snake_case；`serde_json` 默认按结构体字段序输出，顺序稳定。
- 因**同一份 Rust 代码同时产出与消费**（Rust→Dart→Rust，Dart 不编辑），键名与版本属**内部契约**；`schema_version` 为将来加字段/改语义提供前向兼容闸门。

**② 单测（三条，行为明确，不得含糊）**

| 用例 | 输入 | 期望行为 |
|---|---|---|
| happy path | 合法 JSON（`schema_version=1` + 全字段） | 反序列化成功；`args == 原始结构`（往返） |
| 缺字段 | 缺 `token`（或其他必填字段） | `serde_json::from_str` 返回 `Err` → `connect` 转 **`CoreError(Decode)`** 抛出（**不**默认补空值） |
| 非法串 | 非法 JSON / `null` / `schema_version=2` | 非法 JSON → `Err` → **`CoreError(Decode)`**；版本不符 → **`CoreError(Decode)`**（消息含 `schema_version`） |
| golden | 固定 `args` | JSON 串逐字符匹配固定值（键名/顺序/版本稳定） |

**③ Dart 侧解析失败行为（钉死，二选一已定）**

- **绑定层不解析**（零协议逻辑，见 §11 R-18）：`danmaku_data` 自 Rust 产出后**原样透传**回 Rust，Dart 无解析路径。
- 契约规定：**若任何 Dart 调用方需消费该 JSON，解析失败必须抛 `FormatException`（不得静默兜底/不得返回默认值）**。此规则同时适用于 `LiveRoomDetail.data`（将来平台使用）。
- 理由：静默兜底会掩盖协议回归（`generated-code-failure-modes` 的「沉默逻辑错误」高发区），与 AC-35「由确定性校验把关」一致。

- `get_room_detail` 产出：`danmaku_data = Some(serde_json::to_string(&args)?)`（`schema_version = 1`）。
- `connect(...)` 消费：`danmaku_data: Option<String>` → `serde_json::from_str::<BiliBiliDanmakuArgs>(&s)`；`None` → `CoreError(InvalidInput)`；`Err` → `CoreError(Decode)`。
- 集成断言：AC-06 断言 `danmaku_data` 非空且可反序列化；AC-11 断言 join 包体字段来自该结构体。

**(c) `LiveMessage.data`（对照 `live_message.dart:30-32`）**
- 用**类型化枚举**而非 JSON 字符串，以同时满足 AC-12 与 AC-15：
  ```rust
  pub enum LiveMessageData { Online(i32), SuperChat(LiveSuperChatMessage) }
  // LiveMessage.data: Option<LiveMessageData>
  ```
- 断言：AC-12 对 op=3 帧断言 `data == Some(Online(<i32 人气>))`；AC-15 断言 `data == Some(SuperChat(<期望结构>))`；`chat` 类消息 `data == None`。
- 备选（**不采用**）：整体序列化为 JSON string —— 会同时破坏 AC-12（人气需为数值）与 AC-15（SC 需结构化），故弃。

**(d) `LivePlayQuality.data`**：`String`（B站存 `qn` 十进制字符串，如 `"10000"`）。断言 AC-07：固定夹具 → 固定 `quality/data` 列表；`get_play_urls` 消费时 `data.parse::<i32>()`，解析失败 → `CoreError(InvalidInput)`。

---

## 4. API 映射表（`LiveSite` 15 方法 + 2 属性 = 16 接口点；`LiveDanmaku` 3+3）

`LiveSite`（`simple_live_core/lib/src/interface/live_site.dart`）全部方法与 `LiveDanmaku`（`live_danmaku.dart`）→ Rust FRB 门面（`api/slive/site.rs` / `danmaku.rs`）。调用形态：**不透明句柄** `LiveBilibiliSite`（FRB `opaque`），方法语义对齐 Dart core。B站本轮覆盖全部 15 方法 + 账号三接口。

### 4.1 方法覆盖表

| # | Dart `LiveSite` | Rust 门面（FRB 可见） | 本轮 |
|---|---|---|---|
| P1 | `id` | `fn id(&self) -> String`（常量 `"bilibili"`） | 覆盖 |
| P2 | `name` | `fn name(&self) -> String`（常量 `"哔哩哔哩直播"`） | 覆盖 |
| M1 | `getDanmaku()` | `fn get_danmaku(&self) -> LiveBilibiliDanmaku` | 覆盖 |
| M2 | `getCategories()` | `async fn get_categories(&self) -> Result<Vec<LiveCategory>, CoreError>` | 覆盖 F-01 |
| M3 | `searchRooms(keyword,{page})` | `async fn search_rooms(&self, keyword:String, page:i32) -> Result<LiveSearchRoomResult, CoreError>` | 覆盖 F-04 |
| M4 | `searchAnchors(keyword,{page})` | `async fn search_anchors(&self, keyword:String, page:i32) -> Result<LiveSearchAnchorResult, CoreError>` | 覆盖 F-05（DTV/上游均缺） |
| M5 | `getCategoryRooms(category,{page,pageSize})` | `async fn get_category_rooms(&self, category:LiveSubCategory, page:i32, page_size:Option<i32>) -> Result<LiveCategoryResult, CoreError>` | 覆盖 F-02；**保留 `pageSize`**（RISK-04 建议） |
| M6 | `getRecommendRooms({page,pageSize})` | `async fn get_recommend_rooms(&self, page:i32, page_size:Option<i32>) -> Result<LiveCategoryResult, CoreError>` | 覆盖 F-03 |
| M7 | `getRoomDetail({roomId})` | `async fn get_room_detail(&self, room_id:String) -> Result<LiveRoomDetail, CoreError>` | 覆盖 F-06 |
| M8 | `getPlayQualities({detail})` | `async fn get_play_qualities(&self, detail:LiveRoomDetail) -> Result<Vec<LivePlayQuality>, CoreError>` | 覆盖 F-07 |
| M9 | `getPlayUrls({detail,quality})` | `async fn get_play_urls(&self, detail:LiveRoomDetail, quality:LivePlayQuality) -> Result<LivePlayUrl, CoreError>` | 覆盖 F-08 |
| M10 | `getLiveStatus({roomId})` | `async fn get_live_status(&self, room_id:String) -> Result<bool, CoreError>` | 覆盖 F-09 |
| M11 | `getSuperChatMessage({roomId})`（单数） | `async fn get_super_chat_messages(&self, room_id:String) -> Result<Vec<LiveSuperChatMessage>, CoreError>`（复数，对齐上游；App 语义由适配层还原单数） | 覆盖 F-10 |
| M12 | `setSiteAttrs(String)` | `fn set_site_attrs(&self, data:String) -> Result<(), CoreError>` | 覆盖 F-17 |
| M13 | `getQRCode()` | `async fn get_qr_code(&self) -> Result<QrCode, CoreError>` | 覆盖 F-18 |
| M14 | `getQRPollResult({qrcodeKey})` | `async fn get_qr_poll_result(&self, qrcode_key:String) -> Result<QrPollResult, CoreError>` | 覆盖 F-19 |
| M15 | `getAccountInfo({credential})` | `async fn get_account_info(&self, credential:String) -> Result<AccountInfo, CoreError>` | 覆盖 F-20（含 `user_id` 回填副作用） |
| D1 | `LiveDanmaku.onMessage` | `#[frb] fn connect(&self, room_id, cookies, danmaku_data, ...) -> impl Stream<Item=LiveDanmuItem>`（`StreamSink`） | 覆盖 F-11~F-16 |
| D2 | `LiveDanmaku.heartbeat()` | Rust 内部心跳任务（60s），**不暴露**（Dart 无需驱动） | 覆盖 F-11 |
| D3 | `LiveDanmaku.start(args)` | 同 D1（`start` 语义并入 `connect` + Stream） | 覆盖 |
| D4 | `LiveDanmaku.stop()` | `fn disconnect(&self, conn:&LiveDanmuConnection)` | 覆盖 |
| D5 | `onReady` | `LiveDanmuItem::Control(DanmuControlEvent::Ready)` | 覆盖 |
| D6 | `onClose(msg)` | Stream `onError`/`onDone` 或 `Control(DanmuControlEvent::Closed{reason})` | 覆盖 |

**B站本轮覆盖：全部（15 方法 + 2 属性 + 弹幕全链路）。暂缺：无**（`renewers` 续流 O-7 除外；B站无此语义）。
**其余 4 平台（douyu/huya/douyin/twitch）：本轮不迁移**（D2 / O-1），继续走 Dart core。

### 4.2 可测试性契约（seam 注入与断言基；QA 硬前提）

> 硬约束（给贝洛奇）：协议方法一律经下述注入的 `http`/`time`/`frame` 通道，**禁止**直连 `reqwest::Client`、**禁止**直接调用 `Instant::now()`/`SystemTime::now()`。3 个 seam 已在骨架落地（`cargo test -p slive-core` 11 passed）。

**seam #1 — HTTP 传输**（`crates/slive-core/src/http.rs`）
```rust
// http.rs:76
pub trait HttpTransport: Send + Sync {
    // http.rs:78
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, SliveError>;
}
// 生产实现 http.rs:82 ReqwestTransport（reqwest 0.12 + rustls）
// 请求/响应：http.rs:22 HttpRequest{method,url,query:Vec<(String,String)>,headers,body}
//           http.rs:50 HttpResponse{status,headers,body} + .text()/.header()
// 测试替身 testing.rs:61 RecordingTransport；记录 testing.rs:94 calls() / testing.rs:99 call_count()
```

**seam #2 — WS 事件源 + 时序**（`crates/slive-core/src/ws/mod.rs`、`src/time.rs`）
```rust
// time.rs:12
pub trait TimeSource: Send + Sync {
    fn unix_secs(&self) -> u64;                                  // time.rs:14
    fn monotonic_millis(&self) -> u64;                           // time.rs:17
    fn reconnect_delay(&self, attempt: u32) -> Option<Duration>; // time.rs:22（默认 5s×最多5次）
}
// ws/mod.rs:48
pub trait FrameSource: Send {
    async fn next_frame(&mut self) -> Result<Option<Vec<u8>>, SliveError>; // ws/mod.rs:50（None=关闭）
    async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError>;    // ws/mod.rs:53
}
// ws/mod.rs:15 WsSessionConfig{heartbeat,max_reconnect,reconnect_base}；ws/mod.rs:26 bilibili()=60s/5/5s；ws/mod.rs:42 reconnect_delays()
// 测试替身 testing.rs:22 FakeTime(advance) + testing.rs:118 ScriptedFrameSource(预置剧本)
```

**seam #3 — wbi `wts` 时间源**（`crates/slive-core/src/wbi.rs`）
```rust
// wbi.rs:40 —— 纯函数，wts 为入参（不读时钟）
pub fn wbi_sign(params: &[(String, String)], img_key: &str, sub_key: &str, wts: u64) -> String;
// wbi.rs:16
pub fn get_mixin_key(origin: &str) -> String;
```

- **注入点**：`BilibiliSite::with_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>)`（`platforms/bilibili/site.rs:26`）/ 生产 `BilibiliSite::new()`（site.rs:21）；wbi 调用方从 `TimeSource::unix_secs()` 取 `wts` 后传入。
- **替身暴露**：`slive-core` 以 `--features testing` 暴露 `testing::{RecordingTransport, FakeTime, ScriptedFrameSource}`（生产默认不编译）。
- **断言基**：
  - `RecordingTransport::call_count()` → AC-25「风控码不重试」断言**请求次数 == 1**；
  - `FakeTime` + `ws::reconnect_delays(&WsSessionConfig::bilibili())` → AC-26「`5s×5` 重连」断言**不依赖墙钟**；
  - `wbi::wbi_sign(params, img_key, sub_key, wts)`（`wts` 入参）→ AC-21 固定入参 → 固定 `w_rid`。
- **单测证据**：`cargo test -p slive-core` → **11 passed**（`site_accepts_injected_seams` / `recording_transport_records_calls` / `scripted_frame_source_plays_script` / `bilibili_config_matches_dart_core` / wbi 4 例）。seam 总表见 §1.5；夹具见 §8.4。
- **未决**（QA advisory G-4）：`search_type=live_user` 的 `is_live` 类型待核实（Dart `bilibili_site.dart:332` 裸赋给 `bool`，服务端若返 int 即 TypeError）。Rust 侧**必须显式容错**（接受 int/bool 并归一化为 `bool`），**不照抄 Dart 的裸赋值**；已登记至 `12-bilibili-mapping.md`。

---

## 5. 弹幕推送方案

### 5.1 方案对比

| 选项 | 形态 | 优点 | 缺点 |
|---|---|---|---|
| **S FRB `StreamSink<T>`（推荐）** | Rust 持长连接，`sink.add(LiveDanmuItem)`，Dart `stream.listen(...)` | 无轮询空转；生命周期在 Rust；Dart 侧是原生 `Stream`（可 `StreamBuilder`/接 `canvas_danmaku` 事件总线）；Tauri 侧可换成 `tokio mpsc` 订阅同一事件源 | 需处理 sink 寿命（FRB 允许函数返回后继续 `add`，见 FRB 文档「you can hold that StreamSink forever」） |
| P 轮询 `receive() -> Option<T>` | Dart `while` 循环调 `receive` | 实现最少（上游 slive_core 采用 `_receiveLoop`） | Dart 侧忙轮询；延迟受轮询节奏影响；连接状态难精确对齐 `onReady/onClose` |
| C Dart 回调（`DartFn`） | Rust 调 Dart 闭包 | 贴近 Dart core 回调语义 | FRB 2.x 跨线程回调处理复杂；Tauri 无法复用 |

**选型：S。** 事件类型用**枚举**保证可加控制流：

```rust
// api/slive/danmaku.rs（示意）
pub enum LiveDanmuItem {                 // → Dart sealed class（FRB enum）
    Message(LiveMessage),
    Control(LiveDanmuControlEvent),      // Ready / Closed{reason} / Reconnecting{attempt}
}
#[flutter_rust_bridge::frb(opaque)]
pub struct LiveDanmuConnection { /* core 会话句柄 */ }

pub fn connect(room_id, cookies, danmaku_data) -> impl Stream<Item=LiveDanmuItem> + Send { ... }
pub fn disconnect(conn: &LiveDanmuConnection) { ... }
```

### 5.2 生命周期对齐（对照 `web_socket_util.dart` / AC-26）

| 事件 | Dart core 行为（迁移源） | Rust 实现 |
|---|---|---|
| 连接就绪 | `onReady()` 后发 join 包 | 握手成功 → `Control(Ready)`；随后发 `op=7` 加入包（`encodeData(json,7)`，protover=3/type=2/key=token/uid/roomid/buvid） |
| 心跳 | `heartbeatTime=60*1000`（B站），`onHeartBeat` 发 `encodeData("",2)` | Rust `tokio::time::interval(60s)` 发 op=2；收到任何消息重置重连计数 |
| 断线 | `5s × 最多 5 次` 重连，超过 → `onClose("重连超过最大次数,与服务器断开连接")` | 复用同一策略（抽到 `ws/session.rs`）；达上限 → `Control(Closed{reason})` 并 `sink.close()` |
| 错误 | `onClose(e.toString())` | `sink.add_error(anyhow!(...))`（FRB 文档：`add_error` 接受 `anyhow::Error` → Dart 端 `AnyhowException`） |
| 停止 | `stop()`：置空回调 + `close()` | `disconnect()`：取消心跳定时器 + 关闭 TCP + 结束 sink |
| 脏帧 | 解压/解析失败**只记日志、不断连、不抛**（AC-28） | 同上：`tracing::warn!`，跳过该帧，`continue` |

**不暴露 `heartbeat()` 给 Dart**（Dart core 的 `heartbeat()` 也只是内部定时器触发），避免 Dart 侧驱动 Rust 内部时序（`api` 设计原则：把时序留在 Rust）。

---

## 6. 状态管理

### 6.1 Cookie / session

- **弃** DTV 的 `tauri::State` + `.manage()`（`C:/DTV/.../bilibili/state.rs:1-11`，`BilibiliState{w_webid:Arc<Mutex<Option<String>>>}`）与其「每请求新建 `reqwest::Client`」范式（`stream_url.rs:65`）。
- **取**不透明句柄 `LiveBilibiliSite`（`#[frb(opaque)]`），持有：
  - `cookie: Arc<RwLock<String>>`（`set_site_attrs` 写；`get_header` 读）
  - `user_id: Arc<AtomicI64>`（`get_account_info` 回填，供 `get_room_detail` 的弹幕 uid 配对——对齐 `bilibili_site.dart:622`）
  - `buvid3/buvid4`、`access_id`、wbi `img_key/sub_key` 缓存（`Mutex<Option<String>>`）
  - `client: reqwest::Client`（**复用**，见 6.2）
- 句柄由 App 持有单例（每平台一个，对齐 Dart core「各 Site 是单例」的说法，`live_site.dart:115-118`）。**Cookie 变更后无需重建句柄**（内部 `RwLock`）。
- 依赖 `tokio`（`rt-multi-thread` + `macros` + `time/sync/net/io-util`）+ `futures-util`。FRB 自带运行库；异步函数在 FRB 的 tokio 上执行。

### 6.2 `reqwest::Client` 复用

- 构建一次（`OnceCell`/句柄字段），配置对齐 DTV 的网络兼容口径：`.http1_only()`（DTV 注释：部分环境 HTTP/2 ALPN 抖动）、`.connect_timeout(15s)`、`.timeout(45s)`（DTV `common/http_client.rs:11` 口径）、`.no_proxy()`（DTV 直连口径）。
- **每个请求**用 `.header(USER_AGENT/REFERER/COOKIE/ORIGIN)` 携带差异头，而非每请求新建 client。收益：连接池复用（DTV 的 `HttpClient` 已体现该收益）。reqwest 官方亦建议「创建一个 client 并复用」（连接池/keep-alive）。
- **不写日志** cookie/credential（NFR 安全项：`bilibili_site.dart:598` 的 `CoreLog.i(cookieStr)` 行为在 Rust 侧**禁止**复刻）。

---

## 7. 错误模型（Rust error → Dart 异常映射契约）

### 7.1 三层

| 层 | 类型 | 说明 |
|---|---|---|
| core | `SliveError`（`thiserror`） | `Network(String)` / `Http{status:u16, body:String}` / `Api{code:i32, message:String}` / `Decode(String)` / `Websocket(String)` / `NotFound(String)` / `InvalidInput(String)` |
| 桥（FRB 可见） | `CoreError { message:String, status_code:i32 }`（`#[frb]`） | 从 `SliveError` 映射；FRB 生成 Dart 异常类 |
| App 适配层 | Dart `simple_live_core::CoreError` | 回退路径与该路径收敛到**同一** Dart 异常类型，保证 App `catch (CoreError)` 行为不变（AC-30/AC-32） |

### 7.2 映射规则

| core `SliveError` | `status_code` | Dart `CoreError.message`（对齐全 `core_error.dart`） |
|---|---|---|
| `Http{status,..}` | `status` | 复用 `statusCodeToString(status)` 文案（400/401/403/404/500/502/503/默认） |
| `Api{code,message}` | `code` | `message`（如风控 `code=-352` 原样带 message，AC-25） |
| `Network(_)` | 0 | 「发送 GET 请求失败」等（对齐 `http_client.dart` 文案口径），附原始信息 |
| `Decode(_)` / `Websocket(_)` | 0 | 原始信息 |
| `NotFound(_)` | 0 | 如「房间不存在」 |
| `InvalidInput(_)` | 0 | 如 `setSiteAttrs` 非法 JSON（裁决 5：抛类型化错误） |
| `Api{code:-352 等}` | `code` | 风控/业务错误码：抛带消息的类型化错误，**不自动重试**（裁决 5） |

- **业务错误不得静默**：列表接口 `code!=0` → 抛错不放空（AC-25）；`get_account_info` 失败 → `is_valid=false` 不抛（AC-20/AC-24）。
- **`setSiteAttrs` 容错（裁决 5 定稿）**：非法 JSON → `CoreError(InvalidInput)`；JSON 合法但缺 `cookie` 键 → **保留旧值**（不抛、不清空）。
- **风控/业务错误码（裁决 5 定稿）**：`code!=0`（如 `-352`）→ 抛带 `message` 的类型化错误（`Api{code,message}` → `CoreError{message,status_code:code}`），**不自动重试**（与 Dart core 现状一致，AC-25）。
- **弹幕流错误**走 `sink.add_error(anyhow!(...))`（FRB `add_error` 接受 `anyhow::Error`），Dart 端表现为 `Stream` 的 error（对齐 `onClose`）。
- 备选（不推荐）：全用 `anyhow::Result`（FRB → `AnyhowException`）。简单但丢失 `status_code`，难以还原 Dart `CoreError` 契约。

---

## 8. 交叉编译与构建方案

### 8.1 TLS / 压缩后端选型（关键：跨平台可编译性）

| 需求 | 选项 | 结论 |
|---|---|---|
| HTTPS | (a) `native-tls`+`openssl-sys` vendored（DTV 口径）；(b) **`rustls`（纯 Rust）**；(c) 平台原生 TLS | **(b) rustls**。证据：FRB 官方/社区案例中 Android 上 OpenSSL 构建失败（`openssl-sys` build script exit 101）导致 `.so` 缺失、App dlopen 失败，公认解法是 `reqwest = { version = "0.12", features=["rustls-tls"], default-features=false }`（FRB issue #2005、GitCode 案例；本项目实测取 0.12）；DTV 走 (a) 是因为它只面向桌面（Windows/macOS）+ 已有 vendored 工具链，代价是 Android/iOS 要预编译 OpenSSL |
| 证书库 | webpki-roots（内置 Mozilla 根） vs 系统 store | 用 **`rustls-tls`（webpki-roots）**，无系统 store 依赖；后续如需企业 CA 再加 `rustls-platform-verifier` |
| WSS | `tokio-tungstenite` native-tls vs rustls | 统一 rustls：`tokio-tungstenite = { features=["rustls-tls-webpki-roots"] }`（DTV 用 native-tls 属桌面口径） |
| brotli（弹幕 protover=3） | `brotlic`(C) vs `brotli`(纯 Rust) | 用 **`brotli`**（Dart core 用 `package:brotli`；上游 Rust 亦用 `brotli`）。避开 NDK 编译 C 依赖 |
| zlib（弹幕 protover=2） | `flate2`(miniz_oxide 纯 Rust) vs C zlib | 用 **`flate2` + `rust_backend`**（纯 Rust） |

依赖清单（`crates/slive-core/Cargo.toml`）：`reqwest 0.12`(`rustls-tls,json,stream,cookies,brotli,gzip`, `default-features=false`)、`async-trait`、`thiserror`、`md-5`（已落地）；`tokio`、`serde`/`serde_json`、`futures-util`、`tokio-tungstenite`(`rustls-tls-webpki-roots`)、`chrono`(`serde`)、`brotli`、`flate2`(rust_backend)、`regex`、`rand`、`urlencoding`、`log`/`tracing`、`once_cell`（随各 F-xx 落地）。桥 crate：`flutter_rust_bridge = "=2.13.0"`（`features=["chrono"]`）+ `slive-core = { path = "crates/slive-core" }`。

> 版本锚定（实测）：`reqwest` 取 **0.12**（0.11 偏旧、本机缓存为 0.12、rustls 支持稳定）；`md-5` 0.10、`thiserror` 1.x、`async-trait` 0.1。ADR-003 的「rustls / 纯 Rust 后端」结论不随版本变化。

> 依赖存在性核验（`generated-code-failure-modes §3`）：以上 crate 名与 feature 须在实现阶段以 `cargo tree`/`cargo add --dry-run` 核验版本可解析，禁止凭记忆写 feature 名。

### 8.2 构建链路

- **工具链**：新增 `simple_live_app/rust/rust-toolchain.toml` 钉 `channel`（钉 channel，不改工具链来源；briefing §6：`RUSTUP_HOME`/`CARGO_HOME` 指向 scoop rustup）。
- **cargokit**：复用现 `rust_builder`（Android gradle plugin / iOS+macOS podspec / linux+windows CMake），`manifestDir=../../rust`，`libname=rust_lib_simple_live_app` —— **本轮不改**。
- **iOS**：桥 crate `crate-type` 已含 `staticlib`（`rust/Cargo.toml:7`），cargokit `build_pod.sh` 走静态库链入。
- **目标架构**（实现阶段 `rustup target add`）：`aarch64-linux-android`、`armv7-linux-androideabi`、`x86_64-linux-android`、`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`、`aarch64-apple-darwin`、`x86_64-apple-darwin`、`x86_64-pc-windows-msvc`、`x86_64-unknown-linux-gnu`。
- **纯 Rust 核心的额外收益**：`slive-core` 不依赖 FRB，可用 `cargo test` 在**桌面**直接跑离线 fixture 用例（AC-35/AC-36），无需真机/模拟器；FRB 只在桥层参与构建。

### 8.3 端到端验证步骤（`spec-as-contract §4` 收尾）

```bash
# 1) 版本与构建
cd simple_live_app/rust
cargo tree -p slive-core | grep -E "reqwest|rustls|brotli|flate2"   # 依赖核验
cargo build -p slive-core && cargo clippy -p slive-core -- -D warnings
# 2) 离线单测（覆盖 AC-01~AC-29；skip/ignore/xfail 必须为 0）
cargo test -p slive-core -- --nocapture > ../../docs/rust-core/evidence-cargo-test.log 2>&1; echo rc=$?
# 3) FRB 代码生成（版本须 =2.13.0）
cd ../.. && flutter_rust_bridge_codegen --version && flutter_rust_bridge_codegen generate
# 4) App 侧编译与回归（其余 4 平台零回归）
cd ../simple_live_app && flutter analyze && flutter test
# 5) 端到端（固定房间，详情→清晰度→取流→弹幕 30s 窗口 + 一条错误流）
flutter test integration_test/rust_bilibili_e2e_test.dart
```

### 8.4 离线夹具的录制 / 合成方案（回应 RISK-07，总监要求必给）

**问题**：core 现有 B站离线用例只有表情包 31 条（`bilibili_emoticon` 契约），其余 B站请求/解码**零覆盖**，无历史抓包；无夹具则 AC-01~AC-21 无法机械验证。

**原则**：夹具必须**实现者不可篡改**、**确定性**（AC-35），且含**留出集**（AC-36）。所有夹具放 `crates/slive-core/tests/fixtures/bilibili/`。

**(a) 三类夹具及其来源**

| 类别 | 对应能力 | 来源 | 形态 |
|------|----------|------|------|
| HTTP 响应 | F-01~F-10、F-17~F-21 | ① 录制真实响应（一次性脚本，见下）；② 手工合成边界响应 | `.json` 文件（保留真实字段，含风控 `code=-352`、空页、`has_more=0`、`accept_qn` 缺项等边界） |
| WS 帧 | F-11~F-16 | ① 录制真实帧（二进制）；② 按帧格式**合成**（含 op=3 人气、op=5 三协议 ver0/2/3、脏帧） | `.bin`（原始字节）+ 期望产出 `.json` |
| 确定性 golden | F-22 wbi / join 包 | 纯计算合成（固定 `img_key/sub_key/wts/room_id` → 固定 `w_rid`；固定 args → 固定 join 字节） | 内联常量断言（不落盘） |

**(b) 录制方法（一次性、可复现，不入产品路径）**

- HTTP：写一个 `#[ignore]` 的录制用例（`tests/record_http.rs`），入参为一组 URL（分类/推荐/搜索/详情/丹幕/SC/二维码），仅**在有网环境手动** `cargo test -- --ignored record_http` 落盘 `fixtures/`。产品路径**不得**依赖网络（AC-38 抗 flaky）。
- WS：`tests/record_ws.rs`（`#[ignore]`）对一固定房间连接 30s，落盘原始帧到 `fixtures/ws/`（脱敏：**不得**含 cookie/credential——NFR 安全项）。
- 合成：边界/错误夹具（空页、`code=-352`、缺字段、脏帧、超限表情）**手工构造**，不依赖网络。

**(c) 注入方式（离线可测）**

- HTTP 层：`slive-core::http::HttpClient` 抽象为 trait `HttpTransport`（默认 `ReqwestTransport`；测试用 `MockTransport` 按 URL 匹配返回夹具字节）。这与 Dart core「注入 `HttpClientAdapter` 跑离线测试」（`architecture.md §3.3`）同构。
- WS 层：`ws::session` 的事件源抽象为 trait/通道，测试注入「预置帧序列」，不建真实连接。

**(d) held-out 留出集（AC-36）**

- 位置：`tests/fixtures/bilibili/heldout/`，**由 QA 提供、实现者不可见**（实现者只依据 `fixtures/` 开发）。
- 覆盖：每个能力至少 1 条**结构不同于可见集**的真实录制（不同房间/不同响应形态），用于最终判定「是否特判可见用例」。
- 判定：`cargo test --features heldout` 单独运行；held-out 失败即本轮不通过（不因实现者看不到而豁免）。

**(e) 最小夹具清单（对齐 AC）**：`Area/getList`(AC-01)、`second/getList`(AC-02)、`getListByArea`(AC-03)、`search/type?live`(AC-04)、`search/type?live_user`(AC-05)、`getInfoByRoom`+`getDanmuInfo`(AC-06)、`getRoomPlayInfo`(AC-07/08)、`Room/get_info`(AC-09)、`getMessageList`(AC-10)、`qrcode/generate|poll`(AC-18/19)、`member/web/account`(AC-20)、`finger/spi`(AC-21)、`nav`(wbi)、`live.bilibili.com/lol`(access_id)、WS 帧集(AC-11~16)、31 条表情契约(AC-16，从 `bilibili_emoticon_test.dart` 迁移)。

---

## 9. App 接入方案（B站走 Rust、其余 4 平台走 Dart 的分派与开关）

### 9.1 分派点（点名文件）

唯一分派点：`simple_live_app/lib/app/sites.dart:10-16`（`Site(id: Constant.kBiliBili, …, liveSite: BiliBiliSite())`）。

```dart
// lib/app/sites.dart（改 1 行）
liveSite: createBilibiliSite(),   // 原：BiliBiliSite()
```

```dart
// lib/src/bridge/bilibili_factory.dart（新增，绑定层）
LiveSite createBilibiliSite() =>
    AppSettingsController.instance.useRustBilibili ? RustBilibiliSite() : BiliBiliSite();
```

### 9.2 绑定层（AC-32 明确允许改「绑定层」；**边界刚性**，总监 R-13 裁决）

| 新增文件 | 职责 |
|---|---|
| `lib/src/bridge/rust_bilibili_site.dart` | `class RustBilibiliSite implements LiveSite`：转调 FRB `LiveBilibiliSite`；FRB 模型 → `simple_live_core` 模型（1:1 机械映射）；FRB 异常 → `CoreError` |
| `lib/src/bridge/rust_bilibili_danmaku.dart` | `class RustBilibiliDanmaku implements LiveDanmaku`：订阅 FRB `Stream<LiveDanmuItem>`；`Message→onMessage`、`Control(Ready)→onReady`、`Closed/onError/onDone→onClose` |
| `lib/src/bridge/bilibili_factory.dart` | 上面的 `createBilibiliSite()` |

**刚性边界（R-13，可审查项 → 登记 §11 R-18）**

| 允许（ONLY） | 禁止（出现即视为掉进被否决的「Dart 薄壳」） |
|---|---|
| 类型翻译（FRB 模型 ↔ Dart core 模型，1:1 机械字段映射） | 任何 B站 **URL 拼接** |
| 转发（调用 FRB 方法、订阅/退订 Stream） | 任何 **签名/加密**（wbi / md5 / mixin 表） |
| 异常映射（FRB 异常 → `CoreError`；命名适配 SC 单复数） | 任何 **JSON 解析/组装** |
| 开关读取（`useRustBilibili`） | 任何 **重试/心跳/重连策略** |
| — | 任何平台协议分支/兜底逻辑 |

- 协议逻辑**全部**在 `slive-core`；绑定层**零协议逻辑**。审查方式：绑定层文件内不得出现 `http`/`wss`/`md5`/`md-5`/`wbi`/`jsonDecode`/`Url`/`Retry` 等符号（Phase 2 用 diff + grep 核对，登记为可审查项）。
- **Dart 侧协议实现不再保留**：Dart core 的 `BiliBiliSite`（`bilibili_site.dart`/`bilibili_danmaku.dart`/`bilibili_emoticon.dart`）**仅作为回退窗口内的回退目标**存在；**窗口结束即删除**（对齐 AC-34）。
- 理由（总监 R-13）：D2 选「直连 FRB」的目的就是消灭 Dart 侧重复的协议实现；绑定层一旦承载协议逻辑，即退化为被否决的 Dart 薄壳。

### 9.3 开关

- 存储：`LocalStorageService`（现成，如 `kDanmakuMaskEnable` 范式）+ `AppSettingsController`（GetX，如 `setDanmakuMaskEnable` 范式）。
- 新增键 `kUseRustBilibili`（默认 **false** = 走 Dart，安全优先）；新增 `AppSettingsController.useRustBilibili` getter / `setUseRustBilibili` setter，并在设置页加一项（**设置项属既有页面文案范畴**，本轮可不暴露 UI，仅留存储 + 代码开关；若需 UI 入口在实现阶段与 PM 确认，避免触碰 AC-32 的 UI 零变化）。
- 生效时机：`Sites.allSites` 在 App 启动时构建，故开关**下次启动生效**（本轮口径）。
- **可回退**：开关关 → 全走 Dart，Rust 路径不参与运行（AC-31）；Rust 侧编译失败**不得**阻断 App 构建（门禁 §7-1）。

---

## 10. 目录与命名规范（落地）

- 分层：`common(基础) → model → interface → platforms`（Rust 侧对应 `http/ws/error → models → api门面 → platforms`），**只向下依赖**。
- 单文件 ≤300 行：按**能力**拆分（见 §1.3）；`site.rs` 仅编排。
- 无占位实现（AC-33）：禁止 `todo!()`/空 `unimplemented!()`/lorem；未覆盖能力**显式** `Err(SliveError::InvalidInput("not supported in this round"))` 而非静默。
- 图标与视觉（P0 约束）：全项目统一 **Remix Icon**（`remixicon` 已是 App 依赖，`lib/app/sites.dart` 已用；自定义图标走既有 `assets/iconfont/live_icons.ttf`）——**禁止 emoji 作功能图标**；禁止紫→粉渐变方案。本轮无新增 UI，此约束为后续 UI 变更的锁定口径。

---

## 11. 风险清单与不可行项

| 编号 | 风险 | 证据 | 处置 |
|---|---|---|---|
| R-01 | **上游 Twitch 覆盖与 briefing 描述不符** | briefing 称「上游 Twitch 无覆盖」，但 `SlotSun/slive-core-api-rust` HEAD 树含 `crates/platforms-parser/src/extractor/platforms/twitch/{extractor,danmaku}.rs`，`slive_core` 含 `lib/src/platforms/twitch/twitch_site.dart` 与 `LiveTwitchExtractor/LiveTwitchDanmakuProvider` 包装 | 记录为准（不影响本轮 O-1）；后续迁移 Twitch 时以**上游源码**为准，勿沿用 briefing 旧结论（防上下文污染） |
| R-02 | **FRB 2.12→2.13 差异** | 2.13.0 要求 Dart SDK ≥ 3.9.2；wire-format 内容哈希与 2.12 相同（fjs CHANGELOG），但**不能**直接复用上游 2.12.0 生成的代码 | 必须用 `flutter_rust_bridge_codegen 2.13.0` 重新生成；App 侧 Flutter 钉 3.47.6 并核验 Dart 版本 |
| R-03 | **上游过度设计规避** | 上游提交 `45d401d8 refactor: 手动清理调整ai过度设计的转换接口,一层dart接口数据封装` | 不引入 `platforms-parser` 依赖（ADR-009）；模型暴露取 mirror（单层），避免多层转换 |
| R-04 | **Windows 构建链路** | fjs CHANGELOG：「`cargokit/run_build_tool.cmd` 现会传播 Dart build tool 非零退出码（含 snapshot 重建重试路径）……（此前）Windows Gradle 构建静默产出无 `libfjs.so` 的 APK」 | 核验本地 vendored `rust_builder/cargokit` 是否含该修复；若无，构建后**必须**校验产物存在（`.dll`/`.so`）而非只看 `flutter run` 退出码 |
| R-05 | **OpenSSL/证书在移动端不可行** | FRB issue #2005 / GitCode 案例：Android `openssl-sys` 构建失败致 dlopen 失败 | 统一 rustls（ADR-003） |
| R-06 | **`brotlic`(C) 在 NDK 下需 CMake** | DTV 用 `brotlic 0.8`（C 绑定）；Dart/上游用纯 Rust `brotli` | 用纯 Rust `brotli` + `flate2`(rust_backend)（ADR-003） |
| R-07 | **`chrono::DateTime` 时区/单位差异** | FRB 文档：native 用微秒、web 用毫秒；且**总转设备本地时** | `LiveSuperChatMessage` 用 `DateTime<Local>`；AC 只要求「秒→毫秒」，时间戳语义由 `DateTime` 承载，若出现偏差在实现阶段以真值断言校准 |
| R-08 | **进程级缓存 → 句柄级缓存的行为漂移** | Dart core 的 `kImgKey/kSubKey/accessId` 是**静态**（进程级，`bilibili_site.dart:416/417/536`） | 迁到句柄级（更正确）属**行为不变**（请求参数集合一致，NFR 性能项可断言）；若判为契约变更则回退到进程级 `OnceCell`（实现阶段定） |
| R-09 | **`setSiteAttrs` 容错口径**（RISK-06） | Dart 现状：非 JSON 抛 `FormatException`、缺 `cookie` 静默保留 | **已裁决**：非法 JSON → `CoreError(InvalidInput)`；缺 `cookie` 键 → 保留旧值。写入 AC-17 |
| R-10 | **风控/验证码边界**（RISK-08） | `code=-352` 等未定义 | **已裁决**：抛带 message 的类型化错误（AC-25），**不**自动重试；文案走 `CoreError` 映射 |
| R-11 | **单文件 300 行 vs 表情包解析** | `bilibili_emoticon.dart` 300 行 | Rust 侧拆 `emoticon.rs`（解析入口 + 两子函数），测试同文件下移 |
| R-12 | **`i32` vs `i64` 人气溢出** | Dart `online:int`（64 位）；B站人气为 int32 量级 | 模型用 `i32`（AC-12 明确 int32）；跨平台若遇大风车号再评估 |
| R-13 | **可回退与「不保留薄壳」张力** | D2 要求「不保留 Dart 薄壳」，AC-31 要求运行时可回退 | **已裁决（R-13）**：接受绑定层，但**边界刚性**，见 §9.2 与 §11 R-18 |
| R-14 | **离线夹具缺失**（RISK-07） | core 仅表情包 31 条覆盖，其余零覆盖 | **已定方案**：见 §8.4（录制 + 合成 + MockTransport 注入 + held-out 留出集） |
| R-15 | **账号体系是否纳入本轮**（RISK-03） | 上游 B站无账号接口 | **已裁决**：**全进**，纯 HTTP（无 webview） |
| R-16 | **`pageSize` 参数**（RISK-04） | fork 独有且 B站推荐真用 | **已裁决**：**保留**（在 AC-30 回归范围内） |
| R-17 | **SC 命名**（RISK-05） | Dart 单数 vs 上游复数 | **已裁决**：方法集合/语义以 Dart core 为准；**命名风格对齐上游**，SC 用上游复数 `getSuperChatMessages` |
| R-18 | **绑定层越界（承载协议逻辑）** | D2「直连 FRB」的目的是消灭 Dart 侧重复协议实现；绑定层若做 URL/签名/JSON/重试即退化为被否决的 Dart 薄壳 | **可审查项（总监 R-13）**：边界与禁止符号清单见 §9.2；Phase 2 用 diff + grep 核对绑定层文件不含 `http`/`wss`/`md-5`/`wbi`/`jsonDecode`/`Url`/`Retry` 等符号。Dart core B站代码**窗口结束即删**（AC-34） |

**不可行项（明确）**：B站弹幕**发送**（Dart core 无此能力，O-6）；`renewers` 直链续流（B站无此语义，O-7）；其余 4 平台本轮迁移（O-1）。

**可审查项登记**：R-18（绑定层边界，§9.2）；ADR-007 mirror 可行性（Phase 2 首日 spike，不通则回退单层 `From`）。

---

## 12. 需求回溯（每条架构决策 → 对应需求）

| 架构决策（本文节） | 对应需求 | ADR |
|---|---|---|
| workspace + 纯核心 crate `slive-core` | D4 对齐上游形态；briefing 附录 A-1（Tauri 复用）；AC-33 | ADR-001 |
| 复用现 FRB 工程、cargokit 零改动、生成代码入库、精确 `=2.13.0` | D6；AC-30（其余平台构建不变）；AC-33 | ADR-002 |
| TLS/压缩统一 rustls + 纯 Rust 后端 | DoD-1 构建通过；跨平台可编译（Android/iOS） | ADR-003 |
| 弹幕用 FRB `StreamSink` + 控制流枚举 | F-11~F-16；AC-11~AC-16、AC-26、AC-28 | ADR-004 |
| 不透明句柄 + Client 复用 + 弃 tauri::State | F-06/F-17/F-20 的 uid 回填与 cookie 注入；NFR 性能（请求数不增） | ADR-005 |
| `SliveError`→`CoreError`→Dart `CoreError` | AC-23/AC-24/AC-25/AC-26；`core_error.dart` 文案契约 | ADR-006 |
| 模型定义在 core + mirror 暴露 | D2（Dart 直连 FRB）；AC-16/AC-30（保留 emoticons/color） | ADR-007 |
| `sites.dart` 单点分派 + 绑定层适配 + 默认关开关 | AC-31（可回退）、AC-32（UI 零变化）、AC-34（Dart B站保留） | ADR-008 |
| 不依赖上游 `platforms-parser` | D4（对齐形态而非依赖）；规避过度设计（R-03） | ADR-009 |
| 模型字段语义保留 Dart core（`children`/`emoticons`/`dynamic`→JSON） | AC-16/AC-30（能力不丢）；RISK-01/RISK-02 处置 | ADR-007 |
| 按能力拆文件、site.rs 仅编排 | AC-33（单文件 ≤300 行、单一职责） | ADR-001 |
| 图标统一 Remix Icon、禁 emoji | 门禁 §7-2（P0） | ADR-010 |
| 账号体系纯 HTTP 全量实现（F-17~F-20 + uid 回填） | 裁决 1 / F-17~F-20；AC-17~AC-20、AC-24 | ADR-012 |
| LiveMessage 保留 color/emoticons/data 语义 | 裁决 2 / AC-14、AC-16、AC-12、AC-15 | ADR-007、ADR-012 |
| 保留 `pageSize` | 裁决 3 / F-02/F-03；AC-30 | ADR-012 |
| 上游命名风格（SC 复数）+ 能力以 Dart core 为准 | 裁决 4；D4；AC-30/AC-32 | ADR-012 |
| 错误口径（非法 JSON 抛错；风控码抛错不重试；缺 cookie 保留旧值） | 裁决 5；AC-17、AC-25 | ADR-006、ADR-012 |
| `data/danmakuData` → JSON String 契约 + 断言 | RISK-02；AC-06、AC-11 | ADR-012 |
| 离线夹具（录制+合成+held-out） | RISK-07；AC-01~AC-21、AC-35、AC-36 | ADR-011 |
| 上游覆盖度核实并回填 §4 | RISK-10；`12-bilibili-mapping.md §7` | ADR-009 |
| DTV 非主参考：9 项从 Dart 重实现 | 总监修正；AC-16/AC-30 | ADR-009、`12-bilibili-mapping.md §7` |

---

## 附录 A：本轮不采用的备选（已在各节留痕）

- 单 crate（§1 A）、直接依赖上游 parser（§1 C）、Dart 轮询 `receive()`（§5 P）、Dart 回调（§5 C）、`anyhow::Result` 全量错误（§7 备选）、openssl vendored（§8 8.1a）、`From` 显式转换（§3.2 C）、把 Rust 放进 `simple_live_core` 使其成为 FFI 插件（会波及 3 前端，风险高，延后到多前端共享阶段）。

## 附录 B：证据索引（源码行号）

- Dart core：`lib/src/interface/live_site.dart:17-122`、`live_danmaku.dart:5-25`、`platforms/bilibili/bilibili_site.dart:11-636`、`bilibili_danmaku.dart:14-262`、`bilibili_emoticon.dart:1-300`、`model/*`、`common/{http_client,web_socket_util,core_error,binary_writer,qr_status}.dart`、`doc/architecture.md`。
- DTV（`C:\DTV`）：`platforms/bilibili/{state.rs:1-11,stream_url.rs:65-71,websocket.rs:32-265,auth.rs,search.rs,models.rs}`、`platforms/common/http_client.rs:11-45`、`Cargo.toml`（依赖清单）。
- 上游：`github.com/SlotSun/slive_core`（`rust/Cargo.toml`=`=2.12.0`、`rust/src/api/{danmaku,extractor,simple}.rs`、`api/models/*.rs`、`flutter_rust_bridge.yaml`、`lib/src/slive_{site,factory,danmaku}.dart`）；`github.com/SlotSun/slive-core-api-rust`（`crates/platforms-parser/src/{extractor/models.rs, extractor/platforms/bilibili/{extractor,danmaku,wbi}.rs, danmaku/message.rs}`）。
- 现 Rust 资产：`simple_live_app/rust/{Cargo.toml,src/api/danmaku_mask.rs}`、`rust_builder/{pubspec.yaml,android/build.gradle,ios/*.podspec}`、`flutter_rust_bridge.yaml`、`lib/src/rust/frb_generated.dart`（`@generated … 2.13.0`）、`lib/main.dart:71`（`RustLib.init()`）。
- 联网证据：FRB 文档 Stream（`cjycode.com/flutter_rust_bridge/guides/types/translatable/stream`）与 Return Types（`…/translatable/return`）与 DateTime(Chrono)（`…/translatable/detailed/chrono`）；FRB issue #2005 + GitCode 案例（Android rustls 方案）；`fluttercandies/fjs` CHANGELOG（2.13.0 版本钉死/Dart≥3.9.2/cargokit Windows 退出码）。
