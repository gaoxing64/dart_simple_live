# ADR-012: D4 对齐口径 = 命名风格对齐上游、能力语义以 Dart core 为准；data 通道落 JSON String

## Status
Accepted (2026-10-16)

## Background
D4 要求「API/模型/接口形态对齐上游 `slive_core`」，但上游 B站**缺** core 独有的多项能力（emoticons、账号三接口、分类 A、推荐、搜索主播、SC、mcdn、zlib(ver2)）。若把「对齐上游」理解为裁剪到上游能力集，将直接违反 AC-16/AC-30（能力不丢、其余平台行为不变）。

同时 RISK-02 要求为 Dart 的 `dynamic` 通道（`LiveRoomDetail.data/danmakuData`）定形；RISK-05 要求定命名；总监已下裁决 1~5。

## Decision
1. **D4 口径（裁决 2/4）**：「对齐上游」仅指**命名与结构化风格**对齐；**能力集合与字段语义一律以 Dart core 为准**，上游的缺口不作为裁剪目标。
2. **命名（裁决 4）**：Rust API 采用上游命名风格（`live_*`、snake_case、SC 复数 `get_super_chat_messages`）；`simple_live_core` 的 Dart `LiveSite` 接口保持不变，由绑定层适配。**不**为迁就旧名改 Rust 命名（app 调用点本轮本就要改）。
3. **账号体系（裁决 1）**：F-17~F-20 全量实现为**纯 HTTP（无 webview）**；`get_account_info` 成功时回填站点 `user_id`（副作用）。
4. **`pageSize`（裁决 3）**：保留（B站推荐真用）。
5. **data 通道（RISK-02，含总监附加要求）**：
   - `LiveRoomDetail.data` / `danmaku_data` → `Option<String>`（JSON）；B站 `data` 为 `None`，`danmaku_data` 承载 `BiliBiliDanmakuArgs`，Dart 绑定层只透传不解析。
   - **契约固化**：`BiliBiliDanmakuArgs` 含 `schema_version:i32`（固定 `1`，作为前向兼容闸门）+ 字段表（名称/类型/可选性，见 `10-architecture.md §3.3(b)`）；键名 snake_case、序列化顺序稳定。
   - **单测三条（行为明确）**：happy path（往返相等）/ 缺必填字段（→ `CoreError(Decode)`，**不**补默认值）/ 非法串或版本不符（→ `CoreError(Decode)`）+ golden（固定 args → 固定 JSON 串）。
   - **Dart 侧解析失败行为（钉死）**：绑定层不解析（无解析路径）；契约规定「任何 Dart 消费者解析失败必须抛 `FormatException`，**不得静默兜底**」。
   - `LiveMessage.data` → 类型化枚举 `LiveMessageData{Online(i32), SuperChat(LiveSuperChatMessage)}`（同时满足 AC-12/AC-15）。
   - `LivePlayQuality.data` → `String`（存 qn；消费解析失败 → `CoreError(InvalidInput)`）。
6. **错误口径（裁决 5）**：非法 JSON → `CoreError(InvalidInput)`；缺 `cookie` 键 → 保留旧值；风控/业务码 `code!=0` → 抛带 message 的类型化错误、不自动重试。

## Consequences
**正面**
- 能力不丢（AC-16/AC-30/AC-32），同时满足 D4 的命名对齐意图。
- `dynamic` 通道定形为 JSON String，FRB 可桥接，契约与断言可机械验证。

**负面**
- Rust API 命名与 Dart 接口命名存在差异，绑定层需做一次命名适配（SC 单复数）。
- `data` 通道为 JSON String，Dart 侧若需结构化消费须自行 `jsonDecode`（本轮绑定层仅透传，不消费）。

## Related ADRs
ADR-006（错误）、ADR-007（模型暴露）、ADR-009（不依赖上游）、ADR-011（夹具）
