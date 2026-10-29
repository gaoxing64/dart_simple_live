# docs-site 测试案例库（面向 AI）

> 锚点：父仓 future `16454863`（2026-10-29）｜无自动化测试；本库是可执行的文档站巡检清单
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 上游部署：[repo-infra](../repo-infra/test-suite.md)

## 1. 怎么跑

```bash
cd docs
pnpm install
pnpm docs:dev          # 本地预览 http://localhost:5173/dart_simple_live/
pnpm docs:build        # 产出 .vitepress/dist，构建失败即红
pnpm docs:preview
```

站内巡检（无需联网）：

```bash
# 链接扫描
python - <<'EOF'
import os,re,glob
bad=[]
for f in glob.glob('**/*.md',recursive=True):
    txt=open(f,encoding='utf-8',errors='replace').read()
    for m in re.finditer(r'\[[^\]]*\]\(([^)\s]+)\)', txt):
        t=m.group(1)
        if t.startswith(('http','#','mailto')): continue
        p=t.split('#')[0]
        if not p: continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f),p))):
            bad.append((f,t))
print(len(bad), bad[:10])
EOF

# ADR 编号连续性
ls decisions/ADR-*.md | sed 's/.*ADR-\([0-9]*\).*/\1/' | sort | uniq -c

# 架构图渲染（需 Graphviz）
cd architecture && dot -Tsvg system-context.dot -o /tmp/ctx.svg && dot -Tsvg system-containers.dot -o /tmp/ctr.svg
```

## 2. 现测基线（2026-10-29）

| 项 | 实测 |
| --- | --- |
| 站内死链 | **1 处**：`rust-core/17-tars-module.md` → `tag2` |
| ADR 编号 | 001~016 连续无缺号 |
| ADR 交叉引用 | 31 个 md 引用 `ADR-0xx`；ADR-013 已标 `Superseded by ADR-015`，`decisions/README.md` 索引同步 |
| 证据文件引用 | `system-model.evidence.md` 中 28 个 `文件:行号` 引用，除缩写 `sites.dart` 外均可定位到实体文件 |
| Graphviz | **本机未安装 `dot`**，两张图无法本地渲染 |
| `.md` 总数 | 44 |

## 3. AI 用例库

### 3.1 构建与部署

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D-01 | 干净 clone | `cd docs && pnpm install` | 成功，`pnpm-lock.yaml` 无变更（lock 与 manifests 一致） |
| TC-D-02 | 同上 | `pnpm docs:build` | 退出码 0，产出 `.vitepress/dist/index.html` |
| TC-D-03 | 构建产物 | 检查 `dist` 内资源前缀 | 全部以 `/dart_simple_live/` 开头（`base` 生效） |
| TC-D-04 | 构建产物 | 访问 `dist/favicon.ico` | 存在；但页面内 `href="/favicon.ico"` 指向站点根 → 子路径下 404（backlog P1-2，记 FAIL） |
| TC-D-05 | 读 `docs-deploy.yaml` | 检查触发 | `branches: [master]` + `paths: [docs/**]`，权限含 `pages: write` / `id-token: write` |
| TC-D-06 | 同上 | 检查 `concurrency` | `group: pages` + `cancel-in-progress: false` |

### 3.2 内容完整性

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D-10 | 无 | `find . -name "*.md" \| wc -l` | 44（当前值；增删页面须同步本 KB） |
| TC-D-11 | 无 | 统计 ADR | 16 条，编号 001~016 连续 |
| TC-D-12 | 有 ADR 被取代 | 检查被取代 ADR 首部 | 含 `Superseded by ADR-0xx`；`decisions/README.md` 索引表同步该状态 |
| TC-D-13 | 有 OPEN 项关闭 | 检查 `OPEN-DECISIONS.md` | 该项出现在「已关闭」表且含 Resolution；不在 OPEN 表残留 |
| TC-D-14 | 无 | 检查 `architecture/README.md` | 含分层图、关键机制、维护提示三段；结论与 `simple_live_core`/`simple_live_app` 的 KB 不矛盾 |
| TC-D-15 | 无 | 检查 `evidence.md` §5 | 未知项逐条带置信度 |
| TC-D-16 | 无 | 校验 `system-context.dot` / `system-containers.dot` 语法 | `dot -Tsvg` 成功（需 Graphviz；当前本机缺失，见 TC-D-30） |
| TC-D-17 | 无 | 检查 `rust-core/` 各文件 | 应有「历史快照」标注（当前缺失，backlog P0-3，记 FAIL） |
| TC-D-18 | 无 | 检查首页 features 平台清单 | 与 `README.md` 平台清单一致（当前不一致，backlog P1-5，记 FAIL） |

### 3.3 链接与引用

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D-20 | 无 | 跑 §1 的链接扫描脚本 | 0 处死链（当前 1 处 → FAIL） |
| TC-D-21 | 无 | 检查所有相对链接的写法（文本 + 括号 + 相对路径） | 目标文件存在且大小写匹配（Linux CI 大小写敏感） |
| TC-D-22 | 无 | 检查外部链接 | 只允许 http/https；不得有 `localhost`、绝对盘符路径 |
| TC-D-23 | 有代码引用 | 抽查 `evidence.md` 的 `文件:行号` | 文件存在；行号落在文件行数范围内 |
| TC-D-24 | 无 | 检查 `docs/` 内是否引用 `../simple_live_app/...` | 不应存在（VitePress 的 srcDir 是 `docs/`，跨出根目录的链接不会被构建） |

### 3.4 导航可用性

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D-25 | 构建产物 | 从首页出发，仅用站内点击找 ADR-016 | 当前**不可达**（sidebar 仅 2 项）→ FAIL（backlog P0-1） |
| TC-D-26 | 同上 | 仅用站内点击找 `architecture/README.md` | 当前不可达 → FAIL |
| TC-D-27 | 同上 | 仅用站内点击找 `rust-core/00-briefing.md` | 当前不可达 → FAIL |
| TC-D-28 | 同上 | 使用站内搜索找「ADR-016」 | 当前无搜索 → FAIL（backlog P0-2） |

### 3.5 环境与工具链

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D-30 | 任意机 | `command -v dot` | 应存在；当前开发机缺失，架构图只能靠 Qoder Canvas 打开 |
| TC-D-31 | 无 | 检查 `package.json` | 无自引用依赖（当前有 `"Slive Docs": "link:"` → FAIL，backlog P1-3） |
| TC-D-32 | 无 | 检查 VitePress 版本 | `2.0.0-alpha.15`（预发布，需记录升级计划） |
| TC-D-33 | 无 | 检查 Node 版本声明 | CI 用 22；本地应 ≥22 |

## 4. 建议补的自动化

| 优先级 | 用例 | 落地方式 |
| --- | --- | --- |
| P0 | TC-D-20~24 死链与引用 | `pr.yaml` 或 docs-deploy 前置步骤跑 10 行 Python（本 KB §1 已给脚本） |
| P1 | TC-D-11~13 ADR 编号与状态 | 同上，正则断言编号连续、`Superseded` 双向一致 |
| P1 | TC-D-16 dot 语法 | CI 装 graphviz 后 `dot -Tsvg` 空跑 |
| P2 | TC-D-25~28 导航覆盖 | 生成 sitemap 后比对「sidebar 可达页面」与「全部页面」的差集，超阈值告警 |

## 5. 已知缺口

- VitePress 默认**不校验**站内相对链接，死链不会导致构建失败，只能靠外部脚本。
- 没有视觉回归（无截图基线），布局问题只能人眼发现。
- `rust-core/` 内容的正确性无法自动校验（属历史快照，与现行实现必然有偏差）。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-D-14/15 架构与证据 | `16454863` |
| TC-D-11~13 ADR 体系 | `c6caffaf`、`ceec4fbf`、`6dd27ec6` |
| TC-D-24 站内相对链接 | `66ef141d` 删 specs 后可能留下指向已删文件的链接 |
