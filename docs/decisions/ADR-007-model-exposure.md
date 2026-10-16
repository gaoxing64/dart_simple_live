# ADR-007: 模型定义在核心 crate，桥层以 `#[frb(mirror)]` 暴露

## Status
Accepted (2026-10-16) — **主路径已由 spike 验证通过**（见 `docs/rust-core/14-spike-frb-mirror.md`：FRB 2.13.0 下跨 crate mirror 生成真实 Dart 数据类，非 opaque；`From` 回退不启用）。

## Background
`rust_input: crate::api` 只扫描 `api` 模块。若模型定义在 `slive-core`（无 FRB），桥层函数签名引用它们时，FRB 需要显式声明才能生成 Dart 类型。三选：
- M：桥层 `#[frb(mirror(slive_core::models::X))]` 重新声明同名字段；
- C：桥层另立 FRB 模型 + 双向 `impl From`（上游做法）；
- S：模型直接放桥层（即放弃纯核心 crate，回到 ADR-001 的 A 方案）。

约束：D4 对齐上游形态；AC-16/AC-30 要求保留 Dart core 语义（`children`/`emoticons`/`color`/`dynamic`→JSON String）；`generated-code-failure-modes` 警示避免「过度设计的转换层」（上游 `45d401d8` 正在清理）。

## Decision
1. 模型**唯一定义**在 `slive-core::models`，并**保留 Dart core 字段语义**（`children` 而非上游 `sub_categories`；`LiveMessage` 保留 `emoticons/color/message_type/data`；`dynamic` 字段序列化为 JSON `String`；`online` 用 `i32`）。
2. 桥层用 **`#[frb(mirror)]`** 暴露（选项 M），不写转换代码。
3. **回退预案**：若跨 crate `mirror` 在实现阶段受阻，回退到选项 C（一次性、单层、无套娃的 `From`）。
4. `data/danmakuData`（`dynamic`）→ JSON `String`；`LiveMessage.data` → 类型化枚举 `LiveMessageData{Online(i32), SuperChat(LiveSuperChatMessage)}`（保 AC-12/AC-15）；`LiveSuperChatMessage` 时间字段用 `chrono::DateTime<Local>`（FRB 原生桥接，开 `features=["chrono"]`）。

## Consequences
**正面**
- 模型单一来源，无双份类/双份转换；核心 crate 保持 FRB-free，可复用。
- 字段语义保留 Dart core，保证能力不丢（AC-16/AC-30）。

**负面**
- mirror 需在桥层重复声明字段（机械），且 mirror 与源**不强制**同步——分歧只能靠编译/测试兜底，需在实现阶段加「往返一致性」用例。
- ~~跨 crate mirror 的可行性需在实现阶段用真实 codegen 验证~~ → **已由 Phase 2 spike 验证通过**（`14-spike-frb-mirror.md`），`From` 回退方案保留为文档兜底、不启用。
- 前置依赖：codegen 需 `cargo-expand`（自动安装）；Dart 侧 `dart` 需在 PATH（供生成后格式化）。

## Related ADRs
ADR-001（结构）、ADR-002（FRB 集成）、ADR-003（chrono/依赖）
