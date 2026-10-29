# docs-site 修改历史（Git 完整复现）

> 锚点：父仓 future `16454863`（2026-10-29）｜`git log future -- docs` 全量 **19** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游部署：[repo-infra](../repo-infra/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游）。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- docs
git log --date=short --pretty=format:'%h %ad %an %s' future -- docs/decisions
git log --date=short --pretty=format:'%h %ad %an %s' future -- docs/architecture
git show --stat <hash> -- docs
```

## 2. 阶段归纳

| 阶段 | 日期范围 | 条数 | 主题 |
| --- | --- | --- | --- |
| 架构视图与知识库归位 | 2026-10-29 | 2 | 新增 `architecture/`（2 张 dot + 证据索引）；删除已落地 specs 与旧计划 |
| C ABI / submodule / 斗鱼 TCP | 2026-10-25 ~ 10-28 | 4 | ADR-016 落文档、contributing 补 submodule 说明、ADR-015 明文 TCP 同步 |
| Rust 化文档潮 | 2026-10-17 ~ 10-19 | 9 | rust-core 13 份调研/规格/验收、ADR-001~014、契约 re-baseline、多开句柄重构 |
| 早期 | 2026-07-30 ~ 10-14 | 4 | 仓库根提交、快捷键 tooltip 说明、中文输入法旁路 |

## 3. 全量时间线（19 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-29 | `16454863` | G | docs(architecture): 新增全局架构视图与证据索引（2 张 `.dot` + `system-model.evidence.md`） |
| 2026-10-29 | `66ef141d` | G | chore(repo): 删除已落地的 specs 与旧计划文档 |
| 2026-10-28 | `98c2902d` | G | feat(core): 核心解耦并新增 C ABI（ADR-016）（连带 docs） |
| 2026-10-27 | `8c0d174f` | G | docs(repo): contributing 补充 submodule 路径依赖说明 |
| 2026-10-27 | `c767f931` | G | refactor(repo): simple_live_core 与 simple_live_tv_app 改为 submodule（改 `docs/contributing.md`） |
| 2026-10-25 | `31661506` | G | fix(douyu): 弹幕统一改走明文 TCP，修复移动端 rustls 握手被拒（ADR-015 同步） |
| 2026-10-19 | `3f0ac946` | G | refactor(core)!: 弹幕入口改每实例连接句柄，修复多开互停 |
| 2026-10-18 | `4eb5bfc3` | G | docs(core): 知识库五件套同步至 Rust 架构 |
| 2026-10-18 | `4795b165` | G | docs: 同步斗鱼续流「上下文驱动」契约与测试口径 |
| 2026-10-17 | `c273dcd2` | G | core rust 化（增量：全面采用 Rust core —— 去开关 / 绑定层下沉 / TV 迁移 / 删 Twitch Dart 平台） |
| 2026-10-17 | `6dd27ec6` | G | docs: ADR-014 全面采用 Rust core，同步结构与路径文档 |
| 2026-10-17 | `a02829f1` | G | fix(tests): 虎牙夹具 key 改名 —— 消除误触 GitHub Secret Scanning 的 `live_` 前缀模式 |
| 2026-10-17 | `70c1c717` | G | refactor: Rust workspace 迁至 simple_live_core（ADR-001 预留路径落地） |
| 2026-10-17 | `ceec4fbf` | G | docs(decisions): 合并前评审修订 —— ADR-013（WSS TLS 平台分层）+ 契约口径 re-baseline |
| 2026-10-17 | `c6caffaf` | G | docs(rust-core): Rust Core 化设计与验收文档（Spec/架构/ADR/映射/测试计划/交付总结） |
| 2026-10-14 | `b58f9099` | G | docs: 说明按钮 tooltip 内联当前快捷键 + 归档实现计划 |
| 2026-10-14 | `eff3ad1b` | G | fix(live_room): 中文输入法下用 Ctrl+字母 旁路触发快捷键 |
| 2026-10-11 | `12ab0c42` | G | feat(live_room): 直播间播放器快捷键，可改键 / 禁用 / 恢复默认 |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time（仓库根提交，含 `docs/` 初版） |

## 4. 关键提交的影响面

| 提交 | 改动范围 | 事后影响 |
| --- | --- | --- |
| `c6caffaf` | 新增 `docs/rust-core/` 13 份 + `docs/decisions/` ADR-001~012 | 决策从「散落在提交信息」变成「可索引的 ADR 库」 |
| `ceec4fbf` | ADR-013 + 契约 re-baseline | 首次出现「合并前评审修订 ADR」的流程 |
| `6dd27ec6` | ADR-014 + 结构与路径文档 | Rust 全面接管成为正式决策，Dart 协议实现退场 |
| `16454863` | `docs/architecture/` 4 文件 | 首次有「当前状态」视图（此前只有阶段档案），并引入证据/置信度写法 |
| `66ef141d` | 删除 specs 与旧计划 | 阶段文档瘦身，`rust-core/` 保留为历史快照 |

## 5. 当前状态

- future HEAD `16454863`；`docs/` 路径提交 19 条（G 18 / S 1）。
- 44 个 `.md`：指南 3、架构 2（+2 dot）、决策 19、rust-core 13、fixtures 5 份 README。
- VitePress `2.0.0-alpha.15`，`base: /dart_simple_live/`，Node 22，pnpm。
- 部署只在 `master` + `paths: docs/**` 触发；本次文档库（`doc/`）不在部署范围内。
