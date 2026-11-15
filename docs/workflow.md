# 分支与发布流程

本文档是仓库唯一的流程依据。`contributing.md` 负责环境搭建和提交规范，本文档负责分支模型、发布节奏和子模块管理。

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
- 不变量：`future` 的版本必须大于或等于 `master`。一旦发现 `future` 低于 `master`，说明标识变更或发布提交没有回灌，应立即停止发版并按 `docs/workflow-migration.md` 对齐。

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

`simple_live_tv_app` 仍是 Git submodule，主仓库只记录它的 gitlink。克隆主仓库时用
`git clone --recurse-submodules`，已有克隆用 `git submodule update --init simple_live_tv_app`。
`git submodule status` 仅用于查看 TV app 的锁定 commit。

### 子模块维护规则

- 禁止 `git submodule update --remote`，它会把 TV app 指到分支最新提交，破坏可复现性。
- TV app 的代码改动在其独立仓库中提交；主仓库只更新对应 gitlink。
- LiveCore 版本通过两个 App 的 `pubspec.lock` 锁定，不通过 `.gitmodules` 管理。

## 分支收敛

当前仓库存在 `dev`、多个 `backup/*` 历史分支，以及 `future` 与 `master` 的双向分歧。收敛原则：

1. `future` 是唯一开发主线，`dev` 停止使用；历史内容如未进 `future` 需先 cherry-pick。
2. `backup/*` 是历史快照，确认无独有提交后删除，只保留 Tag 归档。
3. `future` 与 `master` 的独有提交先做一次对齐，见 `docs/workflow-migration.md`，之后严格按本文档执行。

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
