# B站离线夹具草案（fixtures-draft）

> 归属：`docs/rust-core/15-test-plan.md §2` · 架构依据 `10-architecture.md §8.4` · ADR `decisions/ADR-011-offline-fixtures-and-heldout.md`
> 作者：QA（严过关）｜日期：2026-10-16
> ⚠️ **本目录是「草案」，不是最终夹具仓库。** 落地目标为 `crates/slive-core/tests/fixtures/bilibili/`；实现者按本文迁移并补真实抓包。

## 目录

| 路径 | 内容 | 就绪度 |
|------|------|--------|
| `emoticon/emoticon-cases.json` | 迁移自 Dart 的 **31 条表情包契约**（37 条断言组） | ✅ 立即可用 |
| `golden/golden-join-packet.json` | AC-11 join/心跳包**逐字节** golden | ✅ 立即可用 |
| `golden/golden-wbi.json` | AC-21 wbi `mixin_key`/`w_rid` golden | ✅ 立即可用 |
| `ws/frame-*.bin` + `*.expected.json` | 合成 WS 帧（op3/op5 ver0/ver2/脏帧） | ✅ 可用（ver3 待补） |
| `http/http-samples.json` | 15 个端点的**合成最小样本** + 期望 | ⚠️ 合成，待真实抓包替换 |
| `heldout/README.md` | held-out 留出集策略（数据待抓包） | ⏳ 策略就绪，数据待建 |
| `tools/gen_fixtures.py` | **可复现**生成器（重跑可还原全部产物） | ✅ |
| `FIXTURE_INDEX.md` | 夹具 → AC → 来源 → 就绪度 索引 | ✅ |

## 怎么重新生成

```bash
python docs/rust-core/fixtures-draft/tools/gen_fixtures.py
```

生成器是**单一事实来源**：所有产物（表情用例 / golden / WS 帧 / HTTP 样本）均可从脚本 + Dart 源码还原。

## 三条纪律（务必遵守）

1. **不伪造**：`http/` 与 `ws/` 的样本内容均为**合成**，各产物内已标 `synthetic: true`；`http/http-samples.json` 的每个 sample 带 `field_sources`（字段 → `bilibili_site.dart` 行号）。**真实响应形态必须抓包核实后才能定稿**，禁止把合成样本当真实抓包。
2. **实现者不可见**：`heldout/` 由 QA 持有，实现者不可见（AC-36）。
3. **golden 不自证**：`golden/` 的期望由**已验证的 Dart 算法**独立推导，**禁止**用被测 Rust 产出回写期望（AC-35）。

## 字段可信度分级

| 级别 | 含义 | 例子 |
|------|------|------|
| **A 已核实** | 字段/算法直接对应 Dart 源码行号 | 表情 info 数组（`bilibili_emoticon_test.dart`）、join 包头（`bilibili_danmaku.dart:119-145`）、wbi（`bilibili_site.dart:505-534`） |
| **B 推导** | 由已核实算法确定性推导 | golden `w_rid`、golden join 字节 |
| **C 合成待核实** | 字段名来自 Dart 解析代码，但**真实响应嵌套/类型未抓包确认** | `http/http-samples.json` 各 sample（含 `verify_note`）、WS 帧负载内容 |
| **D 待核实（明确标注）** | 连字段类型都不确定 | `search_type=live_user` 的 `is_live`（bool vs int，见 AC-05 `verify_note`） |
