# simple_live_console 修改历史（Git 复现版）

> 版本锚点：`simple_live_console` v1.0.0 · future 分支 `3714eec1`（2026-10-11）
> 复核：截至 `5ae375f1`（2026-10-14）`simple_live_console` 源码无变化，本文件全部证据仍然有效。
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/update-history.md)
> 说明：本组件未被 2026-10-12 的上游同步（merge `abca65f8`，dev v1.8.15）触及，本文内容在该次合并后仍然有效；锚点保留为最后一次核查基准。

## 1. 数据源与复现方法

本文全部结论可由仓库自身复现（均为只读命令）：

```bash
# ① future 分支（权威历史）：console 相关提交 → 2 条
git log --date=short --pretty=format:"%h|%ad|%an|%s" future -- simple_live_console

# ② 全部 refs（含重写前旧线）：console 相关提交 → 31 条（含多 ref 冗余）
git log --all --date=short --pretty=format:"%h|%ad|%an|%s" -- simple_live_console

# ③ 只追源码文件 → 10 条（含重复 subject）
git log --all --oneline -- simple_live_console/bin/simple_live_console.dart

# ④ 单条提交的改动面
git show --stat <hash> -- simple_live_console
git show <hash> -- simple_live_console/bin/simple_live_console.dart
```

**两个必须知道的前提**：

1. **本仓库历史经过重写**。`future` 分支的根提交是 `543910ba`（2026-07-30，全树导入型）；console 目录在该提交里被一次性重建（120 行），此前的旧线保存在 `backup-future-*`、`origin/future`、`future-rewrite` 等分支。
2. **`master` 是单提交的孤儿分支**（`0eb56cef`，2026-08-31，fork-sync CI），它也用 743 行重建了整个 console 目录，但**不在 future 线上**，不计入 §2。

作者口径：`SlotSun` = 上游 dart_simple_live 的提交身份；`gaoxing64` = 本 fork；另有早期上游作者 `xiaoyaocz` / `Slot`。

## 2. 权威时间线（future 分支，2 条）

| # | hash | 日期 | 作者 | 类型 | 改动 | 影响 |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | `062d5a83` | 2026-10-03 | SlotSun | refactor | `bin/simple_live_console.dart` **仅 1 行**：`:54` 调用名 `getPlayQualites` → `getPlayQualities` | 修正与 core 接口的拼写不一致，使 console 可与 core 编译 |
| 1 | `543910ba` | 2026-07-30 | SlotSun | root | 全树导入，建立 `simple_live_console/`（10 个文件、743 行；源码 120 行） | future 线的 console 基线 |

### 逐条核实

**`543910ba`（root，2026-07-30）**

```
 simple_live_console/.fvmrc                        |   3 +
 simple_live_console/.gitignore                    |  14 +
 simple_live_console/.vscode/launch.json           |  18 +
 simple_live_console/CHANGELOG.md                  |   3 +
 simple_live_console/README.md                     |  15 +
 simple_live_console/analysis_options.yaml         |  30 ++
 simple_live_console/bin/simple_live_console.dart  | 120 ++++
 simple_live_console/pubspec.lock                  | 519 ++++
 simple_live_console/pubspec.yaml                  |  16 +
 simple_live_console/test/all_live_console_test.dart | 5 +
 10 files changed, 743 insertions(+)
```

导入的 `simple_live_console.dart` 第 54 行仍是 `site.getPlayQualites(...)`（旧线沿用下来的拼写），故该时点 console 与新版 core 接口对不上。

**`062d5a83`（refactor: 调整项目结构，2026-10-03）**

```
-    var quality = await site.getPlayQualites(detail: detail);
+    var quality = await site.getPlayQualities(detail: detail);
```

同一提交在 core 侧是更大范围的结构调整（虎牙资源归入 `huya/common/` 等，见 core `update-history.md` #26）；对 console 只是顺带对齐了这一处调用名。

## 3. 旧线里能找回的 console 变更

`git log --all -- simple_live_console/bin/simple_live_console.dart`（subject 去重后）：

| hash（含重复） | 日期 | 作者 | 摘要 | 源码改动 |
| --- | --- | --- | --- | --- |
| `9978e672` | 2023-02-27 | xiaoyaocz | init project | **首次创建** console（115 行）；仅支持 bilibili / huya / douyu；`getPlayQualites` 拼写自始存在 |
| `ca3191e2` / `0ebf58a0` | 2023-06-25 | xiaoyaocz | 优化抖音roomId获取 | `parseUrl` 增加 `live.douyin.com` 分支（+5 行） |
| `b833fcdf` / `0cdb2179` / `ee26c3fb` | 2025-04-28 | xiaoyaocz | 优化播放器请求头的获取方式 | `getPlayUrls` 返回语义变更：打印改为 `url.urls[i]`（改 4 行） |
| `77839402` | 2025-05-06 | Slot | release 1.7.12 | 内容与上一条相同（随 release 再次落线） |
| `0eb56cef` | 2026-08-31 | gaoxing64 | ci: add fork-sync workflow | 在**孤儿 master** 上重建 console 全部文件（743 行），非 future 线 |

说明：

- 同 subject 的多个 hash（如 `ca3191e2`/`0ebf58a0`、三条 `优化播放器请求头`）是历史重写 / 多 ref 产生的**重复**，不是独立迭代。
- 自 2023-06-25 加入抖音后，旧线的 console **逻辑再未新增平台或指令**；2025-04 那次只是跟随 core `getPlayUrls` 返回值结构调整了打印语句。
- 因此 console 的行为在 3 年多里几乎冻结：两个指令、四个平台、同一套文本输出。

## 4. 当前状态

- 版本：`pubspec.yaml:3` = `1.0.0`；`CHANGELOG.md` 仅有 `1.0.0 - Initial version` 一条（历史随重写丢失，用本文 §3 代偿）。
- 分支 / HEAD：`future` @ `5ae375f1`（2026-10-14）；文档锚点保留 `3714eec1`——`git log 3714eec1..HEAD -- simple_live_console` 与 `git diff --name-only 3714eec1..HEAD -- simple_live_console` 均为空，console 源码自锚点起无变化。
- 最近一次 console 源码变更：`062d5a83`（2026-10-03，修正调用名）。
- 与 core 的关系：`pubspec.yaml:11-12` 为 path 依赖 `../simple_live_core`，console 随 core 一起编译。
- 待跟进的悬置项见 [backlog.md](./backlog.md)；测试基线见 [test-suite.md](./test-suite.md)。