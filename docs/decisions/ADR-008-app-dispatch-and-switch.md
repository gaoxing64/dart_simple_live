# ADR-008: App 侧单点分派 + 绑定层适配 + 默认关闭的运行时开关

## Status
Accepted (2026-10-16)

## Background
D2 要求「Dart 直连 FRB API，不保留 Dart 薄壳；B站整体切 Rust」。但 AC-31 要求「B站开关置于 Dart 时仍可用（可回退）」、AC-32 要求「无 UI 文件改动」、AC-34 要求「Dart B站代码保留至回退窗口结束」。App 的 Site 注册点是 `simple_live_app/lib/app/sites.dart:10-16`（`Site.liveSite` 类型为 `simple_live_core::LiveSite`）。

三者存在张力：既要直连 FRB、又要可运行时回退、又不改 UI。

## Decision
1. **唯一分派点** `lib/app/sites.dart`：`liveSite: createBilibiliSite()`（仅改 1 行）。
2. **绑定层适配**（AC-32 明确允许改「绑定层」）新增：
   - `lib/src/bridge/rust_bilibili_site.dart`：`RustBilibiliSite implements LiveSite`，转调 FRB 句柄；FRB 模型 ↔ `simple_live_core` 模型（1:1 机械映射）；FRB 异常 → `CoreError`。
   - `lib/src/bridge/rust_bilibili_danmaku.dart`：订阅 FRB `Stream<LiveDanmuItem>`，映射到 `onMessage/onReady/onClose`。
   - `lib/src/bridge/bilibili_factory.dart`：`createBilibiliSite()` 按开关在 `RustBilibiliSite` / `BiliBiliSite` 间选择。
3. **开关**：`LocalStorageService` 新键 + `AppSettingsController` getter/setter，默认 **false**（走 Dart，安全优先）；开关下次启动生效。设置 UI 入口本轮不新增（避免触碰 AC-32），仅存储 + 代码开关。
4. Dart core 的 `BiliBiliSite`/相关文件**保留至回退窗口结束**（AC-34）。
5. **绑定层边界刚性（总监 R-13 裁决）**：绑定层**只允许**类型翻译 + 转发 + 异常映射 + 开关读取；**禁止**任何协议逻辑（URL 拼接 / 签名加密 / JSON 解析组装 / 重试心跳重连 / 平台分支兜底）。审查方式：绑定层文件内不得出现 `http`/`wss`/`md-5`/`wbi`/`jsonDecode`/`Url`/`Retry` 等符号（登记为可审查项 R-18，Phase 2 diff+grep 核对）。
6. **Dart 侧协议实现不再保留**：Dart core 的 `BiliBiliSite`/`bilibili_danmaku.dart`/`bilibili_emoticon.dart` 仅作**回退窗口内的回退目标**；**窗口结束即删除**（对齐 AC-34、AC-31）。

## Consequences
**正面**
- App 的 UI/控制器零改动（AC-32），Site 消费者完全无感。
- 一键回退（AC-31）；Dart 路径与 Rust 路径收敛到同一 Dart 类型。
- 全平台运行时回退：开关翻 false 即回 Dart core 路径（**2026-10-17 口径修订**：原「Rust 编译失败不阻断 App」为编译期回退，与 ADR-001 硬依赖冲突，不在本轮范围，见 AC-31 修订 —— 保留的是**运行时**回退；体验版五平台开关已翻 true）。

**负面**
- 「不保留 Dart 薄壳」（D2）与「可运行时回退」（AC-31）的措辞张力：本 ADR 将绑定层限定为「类型翻译 + 转发」，边界已由**总监 R-13 裁决确认**（只允许翻译/转发/异常映射/开关读取；禁任何协议逻辑）。
- 需维护模型映射表（FRB ↔ Dart core），随模型变更同步。
- 回退窗口结束后需执行删除（Dart core B站三文件），属一次性清理成本。

## Related ADRs
ADR-006（错误映射）、ADR-004（弹幕流映射）
