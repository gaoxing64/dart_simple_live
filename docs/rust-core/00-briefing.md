# Rust Core 落地 · 调研情报包(Briefing)

> 生成日期:2026-10-16
> 项目:gaoxing64/dart_simple_live(fork),主线分支 `future`
> 工作目录(worktree):`C:/Users/admin/WorkBuddy/Worktrees/dart_simple_live/core-rust`,分支 `feat/core-rust`,基线提交 `4dcdb4fe`
> 主仓库:`C:/dart_simple_live`(future @ 4dcdb4fe,**禁止在此目录改动**)

---

## 1. 任务目标

来自上游 issue SlotSun/dart_simple_live#155「枪弹分离」路线图的**第一步:Rust Core 落地**。

- 将 Dart 版 `simple_live_core` 的核心能力逐步迁移到 Rust Core
- 保持 API 尽可能兼容,降低迁移成本
- 完成基础能力迁移:网络、解析、缓存等核心模块
- 后续第二步(JS Plugin)、第三步(枪弹分离)、第四步(Plugin 分发)**不在本轮范围**

本轮交付边界(用户已确认):**crate 骨架 + B站(bilibili)端到端**。

---

## 2. 已确定的决策(用户拍板,不得推翻)

| # | 决策项 | 结论 |
|---|--------|------|
| D1 | 首批平台 | **B站 bilibili**(接口规整、账号/Cookie/二维码体系完整,DTV 有 2298 行现成 Rust 实现可逐函数对照) |
| D2 | Dart/Rust 边界 | **Dart 直连 FRB API**——不保留 Dart 薄壳;B站路径整体切 Rust,其余平台(bilibili 以外的 douyu/huya/douyin/twitch)暂留 Dart |
| D3 | 本轮范围 | 骨架(common/model/接口)+ B站全部方法 + FRB 绑定 + 单测 |
| D4 | 实现蓝本 | **API/模型/接口形态对齐上游 `slive_core`;平台协议实现细节以 `C:\DTV` 为主参考** |
| D5 | 开发环境 | 新 worktree(`core-rust`),保证主仓库与 App 始终可用、可回退 |
| D6 | 桥接版本 | flutter_rust_bridge **2.13.0**(与仓库既有 `simple_live_app/rust/` 的 danmaku_mask 一致;上游 slive_core 用的是 2.12.0) |

---

## 3. 参考资产清单

### 3.1 上游 slive_core(公开仓库,API 形态基准)

- 仓库:`https://github.com/SlotSun/slive_core`(public,master,Rust crate 名 `slive_native`,最新 2026-06-28)
- 结构:
  - `rust/src/api/{danmaku.rs, extractor.rs, log.rs, models/*.rs, mod.rs, simple.rs}` —— FRB 薄层 + 模型
  - `lib/src/platforms/{bilibili,douyu,douyin,huya,twitch}_site.dart` + `slive_site.dart` + `slive_factory.dart` + `slive_danmaku.dart` —— Dart 侧封装
  - `lib/src/rust/api/models/*.dart` —— FRB 生成的模型(freezed)
  - `cargokit/` + `flutter_rust_bridge.yaml` —— FRB 构建工具链
- `rust/Cargo.toml` 依赖:`flutter_rust_bridge = "=2.12.0"`,`platforms-parser = { git = "https://github.com/SlotSun/slive-core-api-rust.git" }`,`tokio`,`anyhow`,`serde_json`,`chrono`,`log`,`flutter_logger`
- 平台覆盖:B站 ✓ / 抖音 ✓ / 斗鱼 ✓ / 虎牙 ✓(流提取 + 弹幕)、**Twitch ✗**
- 模型清单(Rust `api/models/`,`live_` 前缀):`anchor_item` `category` `category_result` `danmu_control_event` `danmu_item` `mask_config` `mask_stats` `message` `message_color` `message_type` `play_quality` `play_url` `room_detail` `room_item` `search_anchor_result` `search_room_result` `sub_category` `super_chat_message`
- ⚠️ 上游提交 `45d401d8 refactor: 手动清理调整ai过度设计的转换接口,一层dart接口数据封装` —— 该实现 AI 生成比例高、存在过度设计,作者自己在清理。**可参考形态,不要照抄其转换层**

### 3.2 上游 slive-core-api-rust(公开仓库,平台解析层)

- 仓库:`https://github.com/SlotSun/slive-core-api-rust`(public,main,最新 2026-07-14)
- 结构:`crates/bytes-util/{bit_read,bit_write,bytes_cursor,nal_emulation_prevention,range_check}.rs` + `crates/platforms-parser/{proto/douyin.proto, src/danmaku/*, src/danmaku_mask/*}`

### 3.3 C:\DTV(平台实现主参考,成熟生产实现)

- 基于 Tauri 2.0 的直播客户端(c-zeong),已上架 Microsoft Store
- `C:\DTV\src-tauri\src\platforms\`:
  - `bilibili/`:auth `cookie` `danmaku` `live_list` `models` `search` `state` `streamer_info` `stream_url` `websocket`(**2298 行**)
  - `douyin/`(4352 行)、`douyu/`(1724 行)、`huya/`(1802 行)、`common/`(488 行:http_client/types/types_rust)
- 关键依赖:`reqwest 0.11`(json/stream/cookies/brotli/gzip/blocking)、`tokio 1.37(full)`、`tokio-tungstenite 0.20(native-tls)`、`openssl-sys 0.9(vendored,交叉编译必要)`、`prost 0.12`、`tars-stream 0.1.1`、`brotlic 0.8`、`cookie 0.18`、`md-5 0.10`、`base64 0.21`
- ⚠️ **复用边界**:DTV 的业务函数是纯 Rust(如 `platforms::douyu::get_stream_url(&room_id, None) -> Result<String, String>`),但
  - 返回值是按"给前端 JSON"设计的(`serde` + `String`),**不对齐 core 的强类型模型**
  - 状态用 `tauri::State` + `.manage()`,弹幕靠 `window.emit` 推给 webview
  - 因此 ×是"协议/算法/接口还原的活字典",不是可整文件搬运的 crate

---

## 4. 当前 Dart core 现状(迁移源)

位置:`C:/dart_simple_live/simple_live_core/`(worktree 中为 `simple_live_core/`)

| 层 | 手写行数 | 内容 |
|----|---------|------|
| `lib/src/interface/` | 147 | `LiveSite`(16 个方法)、`LiveDanmaku`(onMessage/onClose/onReady 回调 + heartbeat/start/stop) |
| `lib/src/model/` | 683 | live_category / live_room_item / live_room_detail / live_play_quality / live_play_url / live_message / live_search_result / account_info / account_qr_code / live_anchor_item / live_category_result / live_super_chat_message |
| `lib/src/common/` | 759 | http_client / web_socket_util / binary_writer / custom_interceptor / parse_cookie / core_error / core_log / convert_helper / qr_status / common_asT |
| `lib/src/platforms/bilibili/` | 636+300+262+ | `bilibili_site` `bilibili_danmaku` `bilibili_emoticon` `model/bilibili_user_info` |
| 其余平台 | — | douyu 481 / huya 665(含 TARS 编解码)/ douyin 1300(+abogus 732、xbogus 133)/ twitch 320 |
| 生成代码(不迁移) | ≈9,000 | 抖音 protobuf 8,004 + 虎牙 TARS 1,005 → Rust 侧改用 prost / tars-stream 重新生成 |

**B站相关文件(本轮迁移对象)**:
```
simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart
simple_live_core/lib/src/platforms/bilibili/bilibili_danmaku.dart
simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart
simple_live_core/lib/src/platforms/bilibili/model/bilibili_user_info.dart
simple_live_core/lib/src/interface/live_site.dart
simple_live_core/lib/src/interface/live_danmaku.dart
simple_live_core/lib/src/model/*
simple_live_core/lib/src/common/*
```
**B站文档**:`simple_live_core/doc/{architecture,update-history,test-suite,workflow-diagram,backlog}.md`

---

## 5. 现有 Rust 基础设施(仓库内)

- `simple_live_app/rust/` —— 已有 FRB 2.13.0 工程:crate `rust_lib_simple_live_app`,`src/api/danmaku_mask.rs`(164 行,弹幕屏蔽)+ `simple.rs`(模板残esidual)+ `frb_generated.rs`
- `simple_live_app/lib/src/rust/` —— 对应 Dart 生成代码
- `simple_live_app/pubspec.yaml`:依赖 `rust_lib_simple_live_app: path: rust_builder` + `flutter_rust_bridge: ^2.13.0`
- 上游 `slive-rust-dev` 分支另有 `simple_live_app/{flutter_rust_bridge.yaml,rust_builder/}` 可参考

---

## 6. 环境与构建约束(踩坑清单)

- **Flutter 版本**:`simple_live_app/.fvmrc` = **3.47.6**(2026-10 更新,本地可能只装到 3.47.5 ⇒ 跑 app 侧前先 `fvm install 3.47.6`)
- **本机跑 Flutter 命令**必须先:补 Git Bash PATH、`unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy`(否则 flutter_tester 连不上)、带 `--no-pub`
- Rust 工具链:`RUSTUP_HOME`/`CARGO_HOME` 指向 scoop rustup;JDK = Corretto 21
- **cross-compile**:DTV 用 `openssl-sys` vendored 解决各平台 TLS;Android/iOS/macOS 需 cargokit
- 长命令一律后台 + 落盘日志(`> x.log 2>&1; echo rc=$?`),不要前台死等
- **git 铁律**:本机写 refs 曾静默失败;长 git 操作开始后不要取消;禁用 `stash`/`fetch --prune`/`push --all`/`gc`

---

## 7. 本轮硬约束(门禁)

1. **App 可用性**:其余 4 个平台(Douyu/Huya/Douyin/Twitch)必须继续走 Dart core 且行为不变;B站切换需可开关、可回退
2. **禁止 emoji 作功能图标**、禁止紫粉渐变、禁止 AI 模板味代码(占位实现/TODO 空壳/lorem 文案)
3. 代码组织:分层清晰(routes/… 概念不适用,但**单一职责、逻辑下沉、单文件 ≤300 行**适用),依赖只向下
4. 一切结论须有机械证据(build/test/lint 真实输出),不接受"我觉得可以"
5. 只在 worktree `core-rust` 内改动
