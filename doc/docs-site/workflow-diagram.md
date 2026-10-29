# docs-site 工作流程图

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：`docs/`（VitePress 站点 + 架构视图 + ADR 决策库 + rust-core 阶段文档）
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[repo-infra 部署链](../repo-infra/workflow-diagram.md)｜相关：[core](../../simple_live_core/doc/workflow-diagram.md)｜[app](../../simple_live_app/doc/workflow-diagram.md)

## 1. 写 → 构建 → 部署

```
作者改 docs/**.md
  → push master（paths: docs/**）
  → .github/workflows/docs-deploy.yaml
       checkout@v4 (fetch-depth: 0)
       pnpm/action-setup@v3 (version: latest)
       setup-node@v4 (node 22, cache: pnpm, docs/pnpm-lock.yaml)
       configure-pages@v5
       cd docs && pnpm install && pnpm docs:build     # → docs/.vitepress/dist
       upload-pages-artifact@v3
  → job deploy（needs: build, environment: github-pages）
       deploy-pages@v4
  → https://<owner>.github.io/dart_simple_live/
```

- `concurrency: group: pages, cancel-in-progress: false` —— 生产部署不取消在跑的那次。
- 权限：`contents: read` + `pages: write` + `id-token: write`。
- 本地开发：`cd docs && pnpm install && pnpm run docs:dev`。

## 2. 内容分区

```
docs/
├── index.md                    # 首页 hero + features（VitePress home layout）
├── contributing.md             # 开发指南（分支模型、贡献类型、发版说明）
├── user.md                     # 用户指南（反馈规范、常见问题）
├── .vitepress/config.mts       # base / nav / sidebar / socialLinks
├── public/favicon.ico          # 静态资源
├── architecture/               # 当前状态架构（2026-10-28）
│   ├── README.md               # 分层 + 关键机制 + 维护提示
│   ├── system-context.dot      # L1 系统上下文（Graphviz）
│   ├── system-containers.dot   # L2-L3 容器/组件视图
│   └── system-model.evidence.md# 证据索引 + 置信度 + 未知项
├── decisions/                  # ADR 决策库
│   ├── README.md
│   ├── ADR-001 … ADR-016       # 16 条
│   └── OPEN-DECISIONS.md       # 悬而未决登记册（只追加 + 就地关闭）
└── rust-core/                  # Rust 化阶段文档（2026-10-16 起）
    ├── 00-briefing … 21-delivery-summary   # 13 份，3288 行
    └── fixtures-draft/          # 夹具草稿（含 .bin / .json）
```

## 3. 导航映射（实际 vs 内容）

```
themeConfig:
  nav:     Home → /            | 开发指南 → /contributing
  sidebar: 文档
             ├ 开发指南 → /contributing
             └ 用户指南 → /user
```

**侧栏只声明了 2 个入口**，而 `docs/` 下有 44 个 `.md`（16 ADR + 架构 2 份 + rust-core 13 份 + fixtures 5 份 README）。这些页面能被 URL 直接访问，但站内没有任何导航路径，属于「可达但不可发现」。

## 4. 架构视图的生成与维护

```
system-context.dot   ─┐
system-containers.dot ─┼→ dot -Tsvg → *.svg（本地渲染，不入库）
                      └→ Qoder Canvas 直接打开
system-model.evidence.md ── 逐条列出证据文件:行号 + 置信度 + 未知项
```

维护契约（写在 `architecture/README.md`）：改包边界、crate 成员、外部依赖或跨层关系时，必须同步更新两张 `.dot` 与证据文件。证据文件 §5 已标注 `docs/rust-core/10-architecture.md` 与 `simple_live_core/doc/architecture.md` 的个别结论被 ADR-014 / ADR-016 取代。

## 5. 决策库的两条流水线

```
新决策 ──→ ADR-NNN-<slug>.md（编号递增，deprecated/superseded 关系写在正文）
悬而未决 ──→ OPEN-DECISIONS.md 的 OPEN 表（Date/Source/Open Item/Constraints/Leaning/Blocked By/Resolves When/Status）
了结 ────→ 立即移到「已关闭」表并补 Resolution；不删原文
```

现状：ADR 16 条；OPEN-DECISIONS 有 1 条 OPEN（编译期回退）+ 1 条 RESOLVED（斗鱼 WSS → 明文 TCP，ADR-015 supersedes ADR-013）。

## 6. 构建与发布的边界

| 项 | 事实 |
| --- | --- |
| 触发分支 | 仅 `master`；future/dev 的文档改动不部署 |
| 触发路径 | 仅 `docs/**`；根 `doc/`（各组件知识库）改动**不触发** |
| 产物 | `docs/.vitepress/dist` → Pages artifact |
| base | `/dart_simple_live/`（仓库名子路径；换仓名必须同步改） |
| Node | 22；pnpm 版本 `latest`（未钉） |
| VitePress | `2.0.0-alpha.15`（预发布版，钉死） |

## 7. 失败与兜底

| 失败点 | 表现 | 兜底 |
| --- | --- | --- |
| `pnpm install` 失败 | 部署整体红 | 无兜底；`pnpm-lock.yaml` 入库，缓存 key 指向它 |
| markdown 死链 | VitePress 默认不校验站内相对链接，坏链静默产出 404 | 需人工/脚本巡检（见 test-suite TC-D-20） |
| `.dot` 未渲染 | 仓库里没有 `.svg`，站点上看不到图 | 设计如此：图只在 Qoder Canvas / 本地 Graphviz 打开 |
| 换仓库名 | `base` 未同步 → 全站资源 404 | 改 `config.mts` 的 `base` 与 favicon 路径 |
| favicon 路径 | `head` 写死 `/favicon.ico`（绝对路径，不带 base） | 子路径部署下 favicon 404（见 backlog P1-2） |

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| 架构视图 + 证据索引落地 | `16454863` |
| 决策库成型（ADR-001~016） | `c6caffaf`、`6dd27ec6`、`98c2902d` |
| OPEN-DECISIONS 合并前评审修订 | `ceec4fbf` |
| contributing 补 submodule 说明 | `8c0d174f`、`c767f931` |
| 清理已落地 specs | `66ef141d` |
