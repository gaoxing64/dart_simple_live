# docs-site 待办与优化清单

> 锚点：父仓 future `16454863`（2026-10-29）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 上游部署：[repo-infra](../repo-infra/backlog.md)

## P0 — 内容可达性

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | 侧栏只声明 2 个入口（开发指南 / 用户指南），而站内有 44 个 `.md`：16 条 ADR、2 份架构文档、13 份 rust-core 全部**站内不可发现**，只能靠猜 URL | `docs/.vitepress/config.mts` 的 `themeConfig.sidebar` | 扩 sidebar：`架构`（architecture/README + evidence）、`决策（ADR）`（动态或手列 16 条）、`Rust 化档案`（rust-core 索引页） |
| P0-2 | 未启用站内搜索，44 页规模下只能靠浏览器查找 | `config.mts` 无 `themeConfig.search` | 加 `search: { provider: 'local' }`（VitePress 内置，零外链） |
| P0-3 | `docs/rust-core/` 13 份是 2026-10-16 的阶段快照，其中 `10-architecture.md` 的「B站先行」结论已被 5 平台全接入取代，页面本身无过期提示，读者易误采信 | `architecture/system-model.evidence.md` §5 第 4 条已自陈 | 在 `rust-core/README.md` 或各文件顶部加「历史快照，现行结论见 ADR-014/016 与 architecture/」横幅；或整体移入 `archive/` |

## P1 — 正确性与一致性

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | 仓库内存在 1 处站内死链：`rust-core/17-tars-module.md` 指向 `tag2` | 本地链接扫描（见 test-suite TC-D-20） | 修正链接或改为纯文本；VitePress 默认不校验站内相对链接，需靠脚本兜住 |
| P1-2 | favicon 用绝对路径 `/favicon.ico`，但 `base` 是 `/dart_simple_live/` → 子路径部署下图标 404 | `config.mts` 的 `head: [["link", { rel: "icon", href: "/favicon.ico" }]]` | 改为 `` `${base}favicon.ico` `` 或删掉 `base` 依赖的绝对写法 |
| P1-3 | `package.json` 有自引用依赖 `"Slive Docs": "link:"`（空 target），`pnpm-lock.yaml` 里锁成 `'link:'` | `docs/package.json:11-13`、`pnpm-lock.yaml:12-13` | 删除该依赖后重生成 lock；当前能装上属侥幸 |
| P1-4 | 部署仅在 `master` + `paths: docs/**` 触发：future/dev 上的文档改动不会上线，`doc/`（各组件知识库）改动完全不触发 | `.github/workflows/docs-deploy.yaml:3-9` | 明确「文档站只发 master」的口径并写进 contributing；如需预览，加 `workflow_dispatch` + 可选 ref 输入 |
| P1-5 | 首页 features 只列 Android/Windows/Linux，而 README 与代码支持 iOS/macOS 自测、TV 独立分发 | `docs/index.md` features vs `README.md` 平台清单 | 统一平台口径，或标注「自测/需自行打包」 |
| P1-6 | `contributing.md` 与根 `CONTRIBUTING.md` 内容重复且可能分叉（两处都讲分支模型与贡献方式） | `docs/contributing.md`、根 `CONTRIBUTING.md` | 二选一为真源，另一处改为链接或强制同步检查 |

## P2 — 工程与维护

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | VitePress 钉在 `2.0.0-alpha.15`（预发布），长期不升级会积累 API 漂移 | `docs/package.json` | 建立季度升级检查；升级前跑一次 `pnpm docs:build` 全量 |
| P2-2 | `pnpm/action-setup@version: latest`，pnpm 版本未钉，可能改变 lock 解析 | `docs-deploy.yaml:32-34` | 改用 `packageManager` 字段或钉具体版本 |
| P2-3 | 架构 `.dot` 的 `.svg` 不入库，站点上看不到图，读者必须本地装 Graphviz | `docs/architecture/README.md` 的渲染说明 | CI 里 `dot -Tsvg` 后作为产物/页面内嵌；或至少把 svg 入库 |
| P2-4 | `docs/` 与 `doc/`（组件知识库）命名近似、职责不同，容易混淆 | 两目录并存 | 文档站保持 `docs/`，组件知识库统一 `doc/`；在 README 写明分工 |
| P2-5 | `rust-core/fixtures-draft/` 混在文档站里，含 `.bin` 二进制与 held-out 说明 | `docs/rust-core/fixtures-draft/` | 夹具应归 `simple_live_core/tests/fixtures`，文档站只留说明 |
| P2-6 | 无 `lastUpdated` / 无编辑链接，读者无法判断页面新旧 | `config.mts` 未配 | 开 `lastUpdated: true`，成本极低 |
| P2-7 | `docs/index.md` 的 hero actions 指向 `/contributing` 与 `/user`，两者都在，但 features 描述偏营销、缺「当前架构入口」 | `docs/index.md` | 首页加第三个 action 指向架构页 |

## 已决策取舍

- 保留 Graphviz `.dot` 源文件而非图片：可评审、可 diff，接受「站点看不到图」的代价。
- 保留 `rust-core/` 阶段档案而不删：决策上下文有价值，接受过期风险（已在 evidence §5 标注）。
- 不引入多语言（i18n）：文档以中文为主，Crowdin 的 `files: []` 实际未启用。
- 文档站不做版本化（无 `v1.x` 分支文档）：单版本策略，旧版本行为只能从 Git 历史追。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P0-3 rust-core 过期 | `c6caffaf` 建库，`6dd27ec6`/`98c2902d` 后被取代 |
| P1-5 平台口径 | `docs/index.md` 自 `543910ba` 未更新 |
| P0-1 导航缺失 | `config.mts` 自建站未扩 sidebar |
| P1-3 link 依赖 | `docs/package.json` 初始即如此 |
