# 架构决策记录（ADR）索引

> 项目：dart_simple_live · Core Rust 化第一步（B站端到端）
> 分支：`feat/core-rust` · 基线 `4dcdb4fe` · 2026-10-16
> 格式：MADR（Status / Background / Decision / Consequences / Related ADRs）

| 编号 | 标题 | 状态 |
|------|------|------|
| ADR-001 | 采用 cargo workspace（纯核心 crate `slive-core` + FRB 桥 crate） | Accepted |
| ADR-002 | FRB 精确钉 2.13.0，复用现有工程，生成代码入库 | Accepted |
| ADR-003 | 统一 rustls（纯 Rust）作为 TLS/加密后端，压缩用纯 Rust 实现 | Accepted |
| ADR-004 | 弹幕推送采用 FRB StreamSink + 控制事件枚举 | Accepted |
| ADR-005 | 以不透明句柄承载状态，复用 reqwest Client（弃 tauri::State 与全局单例） | Accepted |
| ADR-006 | 错误模型 SliveError → FRB CoreError → Dart CoreError | Accepted |
| ADR-007 | 模型定义在核心 crate，桥层以 `#[frb(mirror)]` 暴露 | Accepted（mirror 可行性待实现期验证，见 ADR-007 Consequences） |
| ADR-008 | App 侧单点分派 + 绑定层适配 + 默认关闭的运行时开关 | Accepted（薄壳边界 R-13 待总监确认） |
| ADR-009 | 不将上游 `slive-core-api-rust` 作为依赖，仅对齐其 API 形态 | Accepted |
| ADR-010 | 图标统一 Remix Icon，禁止 emoji 作功能图标 | Accepted |
| ADR-011 | 离线夹具采用「录制 + 合成 + MockTransport 注入 + held-out 留出集」 | Accepted |
| ADR-012 | D4 对齐口径 = 命名风格对齐上游、能力语义以 Dart core 为准；data 通道落 JSON String | Accepted |

> 总监裁决映射：裁决 1（账号全进纯 HTTP）→ ADR-012；裁决 2（LiveMessage 保留 color/emoticons/data）→ ADR-007/012；裁决 3（保留 pageSize）→ ADR-012；裁决 4（命名风格对齐上游）→ ADR-012；裁决 5（错误口径）→ ADR-006/012；**R-13（绑定层边界刚性）→ ADR-008**。RISK-02（含 JSON 通道固化 + 单测 + Dart 解析失败行为）→ ADR-012；RISK-07 → ADR-011；RISK-10 → ADR-009。

架构方案正文见 `docs/rust-core/10-architecture.md`；逐方法落点见 `docs/rust-core/12-bilibili-mapping.md`。
