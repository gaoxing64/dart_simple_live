# ADR-006: 错误模型 SliveError → FRB CoreError → Dart CoreError

## Status
Accepted (2026-10-16)

## Background
Dart core 用 `CoreError(message, statusCode)`（`core_error.dart`），App 直接展示其 `message`（含 400/401/403/404/500/502/503 的中文文案）。AC-23/AC-25 要求「类型化错误、不得静默返回空」；AC-20/AC-24 要求账号校验失败时**不抛**而是 `isValid=false`。FRB 2.x 支持 `anyhow::Result`（→ Dart `AnyhowException`）、自定义错误类型（`Result<T,E>` → Dart 生成类）、panic（→ `PanicException`）。

## Decision
1. core 定义 `SliveError`（`thiserror`）：`Network` / `Http{status,body}` / `Api{code,message}` / `Decode` / `Websocket` / `NotFound` / `InvalidInput`。
2. 桥层暴露 FRB 可见 `CoreError { message:String, status_code:i32 }`（`#[frb]`），由 `SliveError` 映射；FRB 生成 Dart 异常类。
3. App 绑定层把该 FRB 异常映射回 `simple_live_core::CoreError`，使**两条路径收敛到同一 Dart 异常类型**，App 的 `catch (CoreError)` 行为不变（AC-30/AC-32）。
4. 映射规则：`Http.status → status_code`；`Api.code → status_code`（风控 `-352` 原样带 message）；其余 → 0，message 复刻 `core_error.dart` 的 `statusCodeToString` 文案。
5. 业务错误**不静默**：列表接口 `code!=0` → 抛（AC-25）；`get_account_info` 失败 → `isValid=false` 不抛（AC-20/AC-24）。
6. 弹幕流错误走 `sink.add_error(anyhow!(...))`（Dart 端为 Stream error）。

## Consequences
**正面**
- 保留 `statusCode+message` 契约，App 无需改错误处理（AC-32）。
- 类型化错误可满足 AC-23/AC-25 的断言。
- `SliveError` 在 core，可被 Tauri/CLI 复用。

**负面**
- 需维护 `SliveError → CoreError → Dart CoreError` 两段映射（机械但必要）。
- 弹幕流错误不得不用 `anyhow`（FRB `add_error` 只收 `anyhow::Error`），与同步 API 的 `CoreError` 存在两套表述，需在文档与适配层写清。

## Related ADRs
ADR-004（流错误）、ADR-008（绑定层）
