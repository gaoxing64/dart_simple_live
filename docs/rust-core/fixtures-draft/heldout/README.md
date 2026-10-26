# held-out 留出集（AC-36）

> **本目录由 QA 持有，实现者不可见。** 详见 `15-test-plan.md §3`。

## 目的

防「对可见用例特判 / 硬编码」——实现者只依据 `../http`、`../ws`、`../emoticon`、`../golden`（可见夹具）开发；held-out 用于**最终判定**，其结构**故意不同于**可见集。

## 机制

| 项 | 值 |
|----|-----|
| 数据目录 | `crates/slive-core/tests/fixtures/bilibili/heldout/`（落地目标） |
| 用例文件 | `crates/slive-core/tests/heldout.rs`（`#[cfg(feature = "heldout")]`） |
| 开关 | `crates/slive-core/Cargo.toml` 的 `[features] heldout = []` |
| 判定命令 | `cargo test -p slive-core --features heldout`（**默认 `cargo test` 不编译**，实现者无法窥探内容） |
| 判定口径 | **held-out 失败即本轮不通过**（不因实现者看不到而豁免） |

## 内容规划（每条能力 ≥1 条，结构不同于可见集）

| 能力 | held-out 差异点（用于击穿特判） |
|------|-------------------------------|
| F-01~F-05 | 不同房间 / 不同 null 组合 / 更深 `<em>` 嵌套 / 满 40 条边界 |
| F-06 | 另一在播房间 + 另一未开播房间（`host_list` 数量 / `token` 长度不同） |
| F-07/F-08 | 另一房间：`accept_qn` 集合不同、`mcdn` 线路位置不同 |
| F-10~F-15 | 另一房间真实弹幕帧（含 ver3 brotli、混排表情数量不同） |
| F-16 | 不同 `emoticon_unique` 前缀（`official_` / `upower_`）→ 击穿「只认 `room_0_1`」 |
| F-17~F-21 | 另一份 `nav`（不同 `img_key/sub_key`）→ 击穿「硬编码 `w_rid`」 |

## ⏳ 当前状态（Phase 2）

- **策略就绪；真实数据待建。**
- 前提：需**真实抓包**（联网访问 B站），当前无网络抓包环境（见 `15-test-plan.md §6 G-1`）。
- **禁止**用合成数据冒充 held-out——合成数据与可见集合同源，失去反特判效力。
- 解除条件：有网环境执行一次录制脚本（`tests/record_http.rs` / `record_ws.rs`，`#[ignore]`、手动跑），QA 选取「结构不同于可见集」的样本入库；**脱敏**（不得含 cookie/credential）。

## 交接流程

```text
QA 产出 heldout/（真实录制 + 用例，仅 QA 持有）
  ↓
实现者按可见夹具开发，跑 `cargo test`（heldout 不编译）
  ↓
Phase 4：QA 运行 `cargo test --features heldout` → 单独判定 → 留证 + 回传总监
```
