# 分支与发布流程

本文档是仓库唯一的流程依据。仓库根目录的 `CONTRIBUTING.md` 负责环境搭建和提交规范，本文档负责分支模型、发布节奏和子模块管理。

## 分支模型

| 分支 | 用途 | 谁能直接 push | 合并方式 |
|------|------|---------------|----------|
| `master` | 生产发布 | 不允许 | 仅 Release PR + Squash |
| `future` | 日常开发 | 维护者 | feature PR，Squash 或 Rebase |
| `feature/*` | 单个功能 | 作者本人 | 合回 future 后删除 |
| `hotfix/*` | 线上救急 | 作者本人 | PR 合入 master（唯一例外），再 cherry-pick 回 future |

`master` 只接受两种 PR：来自 `future` 的 Release PR，以及来自 `hotfix/*` 的紧急修复 PR。两者都用 Squash。其余改动一律先进入 `future`。`future` 是唯一开发主线。

## 日常开发

```bash
git switch future
git pull --ff-only
git switch -c feature/<scope>-<short-desc>

git add -p
git commit -m "feat(player): 说明"

git push -u origin HEAD
```

然后在 GitHub 发起 PR，base 选 `future`。合入前要求：CI 通过、自我 review 过 diff、无临时调试代码、涉及 UI 的附截图。

### 两级 CI

| 流水线 | 触发条件 | 内容 |
|--------|----------|------|
| `ci.yml` | PR → `future` | 子模块校验、analyze、测试，分钟级 |
| `pr.yaml` | PR → `master`（即 Release PR） | macOS / Linux / Windows / Flatpak 全平台构建 |

日常功能 PR 只跑 `ci.yml`；`pr.yaml` 只在 Release PR 上验证发布候选，避免每次改动都触发六平台重构建。

注意：`pull_request` 事件使用的是 base 分支上的 workflow 文件。`pr.yaml` 的新触发条件要随一次 Release 进入 `master` 后才会对后续 Release PR 生效；首次发布前请本地跑一遍全平台构建。

## 发布

发布是把 `future` 的成果整体搬到 `master`，不是把 `master` 反向合回 `future`。

1. 在 `future` 上确认发布内容，更新 `CHANGELOG.md`。
2. 同步版本号（见"版本号"），提交到 `future`。
3. 在 GitHub 建 Release PR：`future` → `master`，标题 `release: vX.Y.Z`。
4. 用 Squash and merge 合入，得到一个干净的发布提交。
5. 在 `master` 上打 Tag 并推送：

```bash
git switch master
git pull --ff-only
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

6. Tag 推送会自动触发 `.github/workflows/publish_app_release.yml`。

### 为什么只允许 Squash

`master` 的历史只保留"每个版本一个提交"，回滚、对比、追责都以版本为单位，不会把几十个开发提交混进发布线。`future` 保留完整开发历史，两者职责不同。

### 禁止的做法

- 禁止 `master` 直接 commit，包括"只改个文档"。
- 禁止 `master` 合回 `future`，这会把 Squash 后的重复提交带回来，制造假冲突。
- 禁止对已发布 Tag 强制推送或移动。

## 版本号

版本号只有一个真源：`simple_live_app/pubspec.yaml` 的 `version:`，格式 `major.minor.patch+build`。

`assets/app_version.json` 是应用内更新检查用的派生数据，必须与 `pubspec.yaml` 一致。`pubspec.yaml` 需要手动改，改完后用脚本同步 `app_version.json` 与 metainfo：

```bash
# 先手动编辑 simple_live_app/pubspec.yaml 的 version:
dart run scripts/update_version.dart --version X.Y.Z
```

注意：该脚本只更新 `app_version.json` 与 metainfo，不会回写 `pubspec.yaml`，版本号以 `pubspec.yaml` 为准。

`simple_live_tv_app/pubspec.yaml` 与 LiveCore 仓库中的 `pubspec.yaml` 是独立版本，跟随各自仓库的发布节奏，不参与主应用版本号。

规则：

- `patch` 用于修 bug，`minor` 用于加功能，`major` 用于破坏性变更。
- `build` 号（`+` 后）必须单调递增，不允许回退。
- `future` 上的版本号是"下一个待发布版本"，`master` 上的版本号是"当前已发布版本"，两者相差一个版本属于正常状态。
- 不变量：`future` 的版本必须大于或等于 `master`。一旦发现 `future` 低于 `master`，说明标识变更或发布提交没有回灌，应立即停止发版，先对齐两条线的版本号再继续。

## Core 依赖与 TV 子模块

LiveCore 是独立仓库 [gaoxing64/livecore](https://github.com/gaoxing64/livecore)。
主 App 和 TV App 在 `pubspec.yaml` 中通过 Git URL 引用 `future` 分支；`pubspec.lock`
记录实际解析到的 commit，确保同一份锁文件可重复构建。Rust 构建插件也从同一仓库的
`rust_builder` 路径获取。

### 更新 LiveCore 依赖

```bash
# 在 LiveCore 仓库完成改动并推送到 future 后，回到主仓库：
cd simple_live_app
flutter pub upgrade livecore rust_lib_livecore

cd ../simple_live_tv_app
flutter pub upgrade livecore rust_lib_livecore

# 提交两个应用更新后的 pubspec.lock
```

独立开发 LiveCore 时，在主仓库旁单独克隆：

```bash
git clone https://github.com/gaoxing64/livecore.git
```

克隆目录名就是 `livecore/`，与远程仓库同名；该目录已被主仓库 `.gitignore` 忽略
（`/livecore/`），不要放进主仓库，也不要初始化为 submodule。本地这份克隆只用于开发
LiveCore 本身，两个 App 始终按 `pubspec.lock` 里锁定的 commit 解析依赖。

`simple_live_tv_app` 仍是 Git submodule，主仓库只记录它的 gitlink。克隆主仓库时用
`git clone --recurse-submodules`，已有克隆用 `git submodule update --init simple_live_tv_app`。
`git submodule status` 仅用于查看 TV app 的锁定 commit。

### 子模块维护规则

- 禁止 `git submodule update --remote`，它会把 TV app 指到分支最新提交，破坏可复现性。
- TV app 的代码改动在其独立仓库中提交；主仓库只更新对应 gitlink。
- LiveCore 版本通过两个 App 的 `pubspec.lock` 锁定，不通过 `.gitmodules` 管理。

## 分支收敛

`future` 已是唯一开发主线，`master` 只走 Release PR；标识与版本号已经对齐
（见 `CHANGELOG.md` 的 1.9.1 / 1.9.2 条目），不再需要额外的一次性迁移步骤。

2026-11-16 已完成一次分支清理：`dev` 与全部 `backup/*` 分支删除，只保留 `future`
与 `master`。有独有历史的分支先打成 `archive/*` 标签再删，需要找回旧实现时从标签
cherry-pick：

| 标签 | 内容 |
|------|------|
| `archive/dev-safe-mode-20261101` | `dev` 线的安全模式、SC 提醒等 21 个提交（未进入 `future`） |
| `archive/future-pre-tidy-20261031` | `future` 瘦身前快照 |
| `archive/future-pre-md-squash-20261031` | `future` 文档压缩前快照 |
| `archive/future-pre-submodule-squash-20261031` | `future` 子模块压缩前快照 |
| `archive/future-pre-drop-specs-pointer-20261031` | `future` 移除 specs 指针前快照 |
| `archive/master-pre-tidy-20261031` | `master` 瘦身前快照 |
| `archive/backup-future-20260925` | 2026-09 的 `future` 历史快照 |
| `archive/dev-nativeapi-20260716` | 2026-07 的 window_manager nativeapi 实验分支 |

LiveCore 仓库同样清掉了 pre-rewrite 的 `chore/drop-kb-docs`，归档为
`archive/chore-drop-kb-docs-20261031`。两个仓库现在都只剩 `future`（主仓库另有 `master`）。

规则：以后再有分支要下线，先确认无独有提交，或打 `archive/*` 标签归档，再删分支。

## 检查清单

发版前：

- [ ] CI 在 `future` 上全绿
- [ ] `CHANGELOG.md` 有本次版本条目
- [ ] `pubspec.yaml` 与 `app_version.json` 版本一致
- [ ] 子模块 gitlink 指向已推送的 commit
- [ ] Release PR 的 base 是 `master`，compare 是 `future`
- [ ] 合入方式是 Squash

合并后：

- [ ] `master` 上 Tag 已推送
- [ ] Release workflow 成功
- [ ] 安装包能覆盖升级，且数据未丢失
