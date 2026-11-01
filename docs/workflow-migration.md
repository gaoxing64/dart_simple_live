# 分支现状与收敛方案

本文件记录 2026-11 分支审计结论和收敛步骤，属于一次性迁移说明。迁移完成后可删除。

> 状态（2026-11-02）：版本号已对齐，`future` 已推进到 `1.9.1+10901`，高于已发布的 `master` `1.9.0+10900`。标识迁移仍未执行，`future` 目前仍是 `com.slotsun.slive`。

## 审计结论

### 1. 版本号"1.9 在 master、1.8 在 future"不是异常，是标识变更造成的分叉

`master` 上的 `1.9.0+10900` 来自提交 `1798223b feat(identity): 全平台应用标识改为 gaoxing`。该提交只存在于 `master` 线，`future` 没有它，所以：

| 位置 | 应用 ID | 版本 |
|------|---------|------|
| `future` | `com.slotsun.slive` | `1.9.1+10901`（审计时为 1.8.15+10815） |
| `master` | `com.gaoxing.slive` | `1.9.0+10900` |

同时 `future` 有 18 个 `master` 没有的功能提交（切台预取、CDN 缓存、媒体控制、播放器修复等），内容差异 69 个文件、+2479/−462 行。

结论：两条线各有独有内容，不是简单的"master 领先 future"。直接把 `future` 合进 `master` 会丢掉 gaoxing 标识；只把 `master` 合回 `future` 又会带回被 `future` 清理过的旧文件。

### 2. 子模块用法基本正确

`.gitmodules` 只声明 path 和 url，父仓库用 gitlink 锁定具体 commit，符合固定 commit 模式。需要修正的只有两处：

- 文档里"fork 者请使用各自账号下的同名仓库"容易让人误以为要改 `.gitmodules` 指向自己的 fork。
- 仓库内存在多份手写的子模块 hash 清单文件，与 gitlink 重复，容易过期。

### 3. 历史清理没有真正生效

之前的裸仓库迁移只创建了本地裸仓库，GitHub 上的 `future`、`master`、`dev` 未被改写。`git ls-remote` 显示远程 `future` 仍指向 `d560d51f`，`master` 仍指向 `92e29c42`。

### 4. CI 与分支名不匹配

`.github/workflows/pr.yaml` 的触发分支写的是 `main` 和 `dev`，仓库里没有 `main`，实际主线是 `future`，所以 PR 检查从未在 `future` 上跑过。

## 收敛步骤

按顺序执行，每步都可回退。

### 第一步：统一标识到 future

把 `master` 独有的标识变更移植到 `future`，让 `future` 成为唯一内容基线。

```bash
git switch future
git pull --ff-only
git cherry-pick 1798223b
```

已用 `git merge-tree` 预演过这次 cherry-pick：大部分文件可自动合并，需要人工确认的是 `simple_live_app/lib/main.dart`、`simple_live_app/lib/services/playback/live_playback_audio_handler.dart`、`simple_live_app/pubspec.yaml` 三个文件。

处理原则：保留 `future` 的功能改动，同时采用 `com.gaoxing.slive`、`io.github.gaoxing.Slive` 等新标识。`pubspec.yaml` 里版本号取 `future` 的递增结果，标识相关配置取 `master` 的。完成后确认：

```bash
rg -n "slotsun" simple_live_app/android/app/build.gradle.kts
rg -n "gaoxing" simple_live_app/android/app/build.gradle.kts
```

### 第二步：版本号对齐（已完成）

`future` 已推进到 `1.9.1+10901`，高于 `master` 的 `1.9.0+10900`。同步的文件：

- `simple_live_app/pubspec.yaml`
- `CHANGELOG.md`
- `assets/app_version.json`
- `simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml`

注意：`scripts/update_version.dart` 会把所有历史 release 的日期重写为当天，不建议直接运行；本次为手工精确更新。

### 第三步：发布 1.9.1

完成标识迁移后，按正常发布流程把 `future` 发布到 `master`：

```bash
git switch future
git push origin future
# 在 GitHub 建 Release PR：future -> master，标题 release: v1.9.1
# 用 Squash and merge 合入
git switch master
git pull --ff-only
git tag -a v1.9.1 -m "Release v1.9.1"
git push origin v1.9.1
```

合入前用 `git diff master future -- simple_live_app` 逐项确认没有丢失 gaoxing 标识、没有回退功能。

### 第四步：停止使用 dev

```bash
git switch future
git log dev --not future --oneline   # 确认没有独有提交
```

有独有提交就先 cherry-pick，没有就删除本地与远程 `dev`。历史发布流水线 `publish_app_dev.yaml` 与 `Prebuild_tv_app_dev.yaml` 一并停用。

### 第五步：修正 CI 触发分支

把 `.github/workflows/pr.yaml` 的 `pull_request.branches` 从 `main`/`dev` 改为 `future`，与本文档的分支模型一致。

### 第六步：清理历史分支

`backup/*` 分支在确认无独有提交后删除：

```bash
git branch --merged future | rg "backup/"
git branch -d backup/<name>
git push origin --delete <remote-branch>
```

## 回退方式

每一步执行前记录当前 SHA：

```bash
git rev-parse master future dev > /tmp/sha-before-migration.txt
```

需要回退时按记录逐个 `git reset --hard <sha>`，并同步远程。已推送的 Tag 不移动，只新增修正版本。
