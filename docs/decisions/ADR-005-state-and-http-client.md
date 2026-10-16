# ADR-005: 以不透明句柄承载状态，复用 reqwest Client（弃 tauri::State 与全局单例）

## Status
Accepted (2026-10-16)

## Background
Dart core 中每个平台 Site 是**单例**，`cookie/userId` 为实例字段，`kImgKey/kSubKey/accessId` 为**静态**（进程级）缓存（`bilibili_site.dart:416/417/536`）。DTV 用 `tauri::State` + `.manage()` 保存 `BilibiliState{w_webid}`（桌面/框架绑定），并**每请求新建** `reqwest::Client`（携带不同 headers）。

本工程无 tauri 运行时，且要求核心可被多前端复用，状态方案不能绑定任何框架。

## Decision
1. Rust 侧以 **FRB 不透明句柄** `LiveBilibiliSite`（`#[frb(opaque)]`）承载实例状态：`cookie`、`user_id`（`get_account_info` 回填副作用）、`buvid3/4`、`access_id`、wbi 键缓存；由 App 每平台持有一个（对齐 Dart「Site 是单例」）。
2. **复用单个 `reqwest::Client`**（句柄持有，懒初始化），差异 header 经每请求 `.header(...)` 附加。
3. 弹幕连接以独立句柄 `LiveDanmuConnection` 承载，与 Site 解耦（`connect(room_id, cookies, danmaku_data)` 需要的参数从 `get_room_detail` 的 `danmaku_data` 取，对齐 Dart core 的 `BiliBiliDanmakuArgs`）。
4. Dart core 的进程级静态缓存迁为**句柄级**缓存（更正确）；若判为契约变更则回退到 `OnceCell` 进程级。

## Consequences
**正面**
- 不绑定 tauri/任何 UI 框架，满足复用；状态随句柄生命周期自然释放（无全局可变单例）。
- Client 复用带来连接池/keep-alive 收益，符合 reqwest 官方建议；请求数不增（NFR 性能项可断言）。
- `user_id` 回填（AC-20）与 cookie 注入（AC-17）在句柄内闭环，避免全局态污染多账号。

**负面**
- 句柄级缓存与 Dart 现状的进程级缓存存在**细微行为差异**（R-08），需在实现阶段以「请求参数集合一致」断言确认无契约影响。
- 需 App 侧维护「每平台一个句柄」的生命周期（与 Dart 单例等价）。

## Related ADRs
ADR-004（弹幕会话）、ADR-006（错误模型）
