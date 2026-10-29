# docs-site 架构与选型对照

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：VitePress 站点、架构视图、决策库、阶段文档
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游部署：[repo-infra](../repo-infra/architecture.md)｜内容下游：[core](../../simple_live_core/doc/architecture.md)｜[app](../../simple_live_app/doc/architecture.md)

## 1. 定位

`docs/` 是**面向开发者的公开文档站**，而不是组件文档的容器：它承载三类内容 ——（a）面向使用者的指南（contributing / user），（b）面向架构评审的当前状态模型（architecture + evidence），（c）面向决策追溯的 ADR 库与 Rust 化阶段档案。各组件自己的知识库（`simple_live_app/doc/`、`simple_live_core/doc/` 等）**不在本站内**，它们是给 AI 与维护者看的内部文档。

## 2. 站点结构

| 路径 | 数量 | 性质 |
| --- | --- | --- |
| `index.md` | 1 | VitePress home layout（hero + 3 features） |
| `contributing.md` / `user.md` | 2 | 人工维护的指南 |
| `architecture/` | 4（2 `.dot` + 1 README + 1 evidence） | 当前状态模型，2026-10-28 版 |
| `decisions/` | 18（16 ADR + `OPEN-DECISIONS.md` + `README.md`） | 决策库 |
| `rust-core/` | 13 份 md（3288 行）+ `fixtures-draft/`（7 份 README） | 2026-10-16 起的 Rust 化阶段档案 |
| `.vitepress/config.mts` | 1 | 站点配置 |

合计 44 个 `.md`：根 4 + architecture 2 + decisions 18 + rust-core 13 + fixtures 7。

## 3. 关键选型

| 选择 | 现状 | 理由 / 代价 |
| --- | --- | --- |
| 静态站点框架 | VitePress `2.0.0-alpha.15` | Markdown 即页面、零后端、GitHub Pages 直发；代价是**用了 alpha 版并钉死**，升级需跨版本验证 |
| 部署目标 | GitHub Pages，`base: '/dart_simple_live/'` | 免运维；代价是换仓名/换 owner 必须同步改 `base` |
| 包管理 | pnpm + `pnpm-lock.yaml` 入库，CI 用 `pnpm/action-setup@version: latest` | lock 保证可复现；但 pnpm 版本没钉，`latest` 漂移会改 lock 解析行为 |
| Node | 22 | 与 VitePress 2.x 要求匹配 |
| 架构图 | Graphviz `.dot` 源文件入库，`.svg` **不入库** | 图可 diff、可评审；代价是站点上看不到图，需本地 `dot -Tsvg` 或 Qoder Canvas |
| 架构说明 | 双文件：`README.md`（结论）+ `system-model.evidence.md`（证据/置信度/未知项） | 结论与证据分离，避免"看起来很有道理但没依据"；代价是两份要同步 |
| 决策记录 | ADR-001~016 一人一文件 + 独立 OPEN-DECISIONS 登记册 | 可追溯、可 supersede；登记册「只追加 + 就地关闭」防止决策丢失 |
| 阶段档案 | `rust-core/` 保留 2026-10-16 的 13 份调研/验收文档 | 保留决策上下文；代价是内容已部分过期（B 站先行阶段） |
| 导航 | nav 2 项 + sidebar 2 项 | 极简；代价是 40+ 页面不可发现（见 backlog P0-1） |
| 搜索 | 未启用（无 `themeConfig.search`） | 省依赖；44 页规模下已影响可用性 |

## 4. 内容权威性排序

站内同一事实可能出现在多处，**以右侧为高优先级**：

```
rust-core/*（2026-10 阶段文档，历史快照）
  < decisions/ADR-*（决策结论，可 supersede）
      < architecture/README.md（当前状态结论）
          < architecture/system-model.evidence.md（逐条证据 + 置信度）
              < 代码与 pubspec/Cargo.toml（最终真源）
```

`architecture/README.md` 自己就写明：`docs/rust-core/10-architecture.md` 与 `simple_live_core/doc/architecture.md` 是阶段性文档，个别结论已被 ADR-014 / ADR-016 取代。

## 5. 证据索引的写法（`system-model.evidence.md`）

| 段 | 内容 |
| --- | --- |
| §1 系统边界与角色 | 用户、外部平台、外部服务 |
| §2 容器 / 组件 | 与 `system-containers.dot` 一一对应 |
| §3 关键关系 | 调用方向、协议、传输 |
| §4 技术栈清单 | 每条带 `文件:行号` 证据 |
| §5 未知与需验证项 | 6 条，逐条给置信度（如「iOS/macOS 可用性：低，无 CI 证据」） |
| §6 重新生成 | `dot -Tsvg` 命令 + 变更时的同步义务 |

这是全仓唯一显式标注「置信度」的文档，可作为其他知识库写证据的范式。

## 6. 决策库结构

| 文件 | 作用 |
| --- | --- |
| `ADR-001` ~ `ADR-016` | 一条决策一文件，标题即决策内容（如「ADR-016：宿主层拆分与通用 C ABI」） |
| `OPEN-DECISIONS.md` | 悬而未决登记册：OPEN 表 8 列 + 「已关闭」表补 Resolution |
| `decisions/README.md` | 索引与编号规则 |

演进痕迹：ADR-013（WSS TLS 按平台分层）被 ADR-015（斗鱼改明文 TCP）**supersede**，OPEN-DECISIONS 的「已关闭」表里同步记了这次关闭与真机失败证据（rustls `AlertReceived(HandshakeFailure)`）。

## 7. 与组件知识库的分工

| 维度 | `docs/`（本站） | 组件 `doc/`（各 KB） |
| --- | --- | --- |
| 读者 | 外部开发者 / 评审者 | AI / 维护者 |
| 内容 | 当前状态架构、决策、阶段档案 | 流程图、Git 全量历史、待办、测试用例 |
| 时效 | 随架构变更更新 | 随每次功能提交「跟到」某锚点 |
| 导航 | 站内 sidebar（覆盖很少） | 各 KB 头部互相链接 |
| 图 | Graphviz `.dot` | ASCII 流程图 |

## 8. 风险

1. **VitePress alpha 钉版**：`2.0.0-alpha.15` 长期不升级会积累 API 漂移；升级又需全站回归。
2. **导航覆盖极低**：44 页里只有 2 页可从站内点击到达。
3. **阶段文档过期**：`rust-core/` 13 份里至少 2 份结论已被 ADR 取代，但页面本身没有过期提示。
4. **favicon 路径未带 base**：`head: [["link", { rel: "icon", href: "/favicon.ico" }]]` 在 `/dart_simple_live/` 子路径下指向站点根，实际 404。
5. **无死链校验**：本次扫描发现 1 处坏链（`rust-core/17-tars-module.md` 的 `tag2`）。
6. **`package.json` 有自引用依赖**：`"Slive Docs": "link:"` 是空 target 的自依赖，属误配。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| 架构视图与证据索引 | `16454863` |
| ADR 体系建立（001~012） | `c6caffaf` |
| ADR-013 / 契约 re-baseline | `ceec4fbf` |
| ADR-014 全面采用 Rust core | `6dd27ec6` |
| ADR-015 斗鱼明文 TCP | `31661506`（配套 `98c2902d` 的 ADR-016） |
| contributing 补 submodule | `8c0d174f` |
