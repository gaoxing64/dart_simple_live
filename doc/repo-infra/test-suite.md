# repo-infra 测试案例库（面向 AI）

> 锚点：父仓 future `16454863`（2026-10-29）｜无自动化测试；本库是可执行的**人工/脚本核验清单**
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 下游：[App](../../simple_live_app/doc/test-suite.md)｜[TV](../../simple_live_tv_app/doc/test-suite.md)｜[Core](../../simple_live_core/doc/test-suite.md)｜[Flatpak](../../flatpak/doc/test-suite.md)

## 1. 怎么跑

本组件**没有单元测试**（`grep -rnE "flutter test|cargo test|analyze" .github/workflows/` 为空）。可用的是三类核验：

```bash
# A. 脚本冒烟（本地可跑，无需网络）
python tools/gen_changelog.py --repo SlotSun/dart_simple_live \
  --version-desc-file assets/app_version.json --tag-prefix v --output /tmp/rn.md
python tools/gen_changelog.py --help

# B. 工作流语法校验（需 actionlint，未入 CI）
actionlint .github/workflows/*.yml .github/workflows/*.yaml

# C. 仓库一致性巡检
git log --oneline -- .github scripts tools assets | wc -l
git submodule status
```

`scripts/update_version.dart` 需 Flutter/Dart SDK：

```bash
dart run scripts/update_version.dart                  # 只刷 version_desc + metainfo
dart run scripts/update_version.dart --version 1.8.15 # 连 version/version_num 一起改
dart run scripts/update_contributor.dart https://github.com/<user>
```

> 注意：两个脚本都会**就地改写仓库文件**（`assets/app_version.json`、`metainfo.xml`、`README.md`）。核验前先 `git stash` 或在新分支跑。

## 2. 现测基线（2026-10-29 实跑）

| 项 | 实测结果 |
| --- | --- |
| `gen_changelog.py` 默认参数（version 1.8.14，tag 存在） | 输出 1 条提交入册；`Full Changelog: compare/v1.8.13...v1.8.14` |
| `--to 9.9.9`（不存在的 tag） | **不报错**：`resolve_to_tag` 退化到版本文件里的 `v1.8.14`，输出与默认一致 —— 非法 `--to` 被静默吞掉 |
| 无 `version` 且无 `--to` | 返回码 1，`::error::` 写 stderr |
| 当前 tag | App `v1.8.14` / `v1.8.15` / `v1.9.0` 等；TV `tv_v1.5.0` 等 |
| `assets/app_version.json` | `1.8.14`（10814），与 `pubspec.yaml` 的 `1.8.15+10815` **不一致** |

## 3. AI 用例库

### 3.1 版本资产一致性（离线，优先）

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-I-01 | 干净工作区 | 比对 `assets/app_version.json.version` 与 `simple_live_app/pubspec.yaml` 的 `version:` 前缀 | 发版前必须相等；不等时打 FAIL（对应 backlog P0-1） |
| TC-I-02 | 同上 | 比对 `version_num` 与 pubspec 的 `+build` 号 | `version_num == build`（1.8.14 → 10814） |
| TC-I-03 | 同上 | `_versionToNum('1.8.15')` | `10815` |
| TC-I-04 | 同上 | 比对 `assets/tv_app_version.json.version` 与 `simple_live_tv_app/pubspec.yaml` | 相等（1.5.1） |
| TC-I-05 | metainfo 存在 | 解析 `simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml` | `<releases>` 段含 `CHANGELOG.md` 全部版本，且首条为最新 |
| TC-I-06 | CHANGELOG 有新版本 | 跑 `update_version.dart --version x.y.z` | `app_version.json` 的 `version`/`version_num`/`version_desc` 三处同步；`version_desc` 行数 = CHANGELOG 该版本 `- ` 行数 |

### 3.2 发布说明生成器（`tools/gen_changelog.py`）

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-I-10 | 正常仓 | 默认参数跑一次 | 退出码 0；文件含 `version_desc` 原文 + `## What's Changed` + `**Full Changelog**` |
| TC-I-11 | 有 `feat(x): y` 提交 | 查看分组 | 落在 `**🚀 Features**`，文本为 `**x**: y` |
| TC-I-12 | 有 `fix!: y` 提交 | 查看分组 | 落在 `**⚠️ Breaking Changes**`（`!` 优先于类型） |
| TC-I-13 | 有 `chore: y` | 查看分组 | 落在 `**🔧 Chores & Dependencies**` |
| TC-I-14 | 有不符合 conventional 的标题 | 查看分组 | 落在 `**🧩 Other Changes**`，不丢条目 |
| TC-I-15 | 两条完全相同 `fix(a): b` | 跑一次 | 去重成 1 条（`seen` 集合） |
| TC-I-16 | `--previous-tag v1.8.13 --to v1.8.14` | 跑一次 | Full Changelog 链接为 `compare/v1.8.13...v1.8.14` |
| TC-I-17 | 首次发布（无上一个 tag） | `--previous-tag ""` | 不产出 Full Changelog 段；stdout 有「按首次发布处理」warning |
| TC-I-18 | `--header "# Android TV"` | 跑一次 | 文件首行为该标题 |
| TC-I-19 | `--tag-prefix tv_v` + tv 版本文件 | 跑一次 | 匹配 `tv_v1.5.0`，不误匹配 `v1.5.0` |
| TC-I-20 | 版本文件不存在 | 跑一次 | 退出码非 0，stderr 含「版本文件不存在」 |
| TC-I-21 | 版本文件非法 JSON | 跑一次 | 退出码非 0，stderr 含「不是合法 JSON」 |
| TC-I-22 | **非法 `--to 9.9.9`** | 跑一次 | **当前实测：静默退化到版本文件的 tag，退出码 0** —— 期望应改为 `::warning::` 并保留非法值提示（见 backlog P2-2） |
| TC-I-23 | `--output` 指向不存在目录 | 跑一次 | 自动 `mkdir -p` 后写入成功 |
| TC-I-24 | 提交区间非法（`prev` 与 `to` 无共同祖先） | 跑一次 | 退化为全历史且不崩 |

### 3.3 工作流静态核验

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-I-30 | 读全部 7 个工作流 | 检查每个 `actions/checkout` | 均带 `submodules: recursive`（子仓化后 20 处） |
| TC-I-31 | 读 release 两个工作流 | 检查 `concurrency` | 应存在；当前**缺失**（backlog P0-2，记为 FAIL） |
| TC-I-32 | 读 release 工作流 | 检查 4 个 `Upload Release` 的 `files:` | android→`Slive_*.apk`；linux→`*.deb,*.zip`；windows→`*.msix,*.zip,*.exe`；flatpak→`Slive_*.flatpak` |
| TC-I-33 | 同上 | 检查 `body_path` | 只接受 `steps.notes.outputs.file`，且上游有 `[ -s release-notes.md ]` 守卫 |
| TC-I-34 | 同上 | 检查每个 `Upload Release` | 均带 `token: ${{ secrets.TOKEN }}`（默认 GITHUB_TOKEN 不足以跨仓） |
| TC-I-35 | 读 4 个构建工作流 | 检查 Flutter 版本来源 | 全部 `flutter-version-file: <项目>/pubspec.yaml`，无硬编码版本 |
| TC-I-36 | 读全部工作流 | `grep -E "flutter test\|cargo test\|analyze"` | 当前为空 → 记 FAIL（backlog P0-3） |
| TC-I-37 | 读 dev/future | `diff` 两文件 | 差异应仅限 `ref`、`paths`、action 版本；结构一致 |
| TC-I-38 | 读 `pr.yaml` | 检查是否引用 secrets | 应为 0 处（fork PR 无 secret） |
| TC-I-39 | 读 `docs-deploy.yaml` | 检查触发 | `branches: [master]` + `paths: [docs/**]`；权限 `pages: write` + `id-token: write` |
| TC-I-40 | 读 TV release | 检查 action 版本 | 当前 `upload-artifact@v3` / `gh-release@v1` → 记 FAIL（backlog P0-5） |

### 3.4 产物命名规范

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-I-50 | 取任一 Android 产物名 | 按 `_` 切分 | 7 段：`Slive` / `V1.8.14` / `android-arm64-v8a` / `app` / `(zh-cn)` / `release` / `123_(Build261029153000)` |
| TC-I-51 | 取 flatpak 产物名 | 同上 | 平台段 `linux-x86_64`，代号 `flatpak` |
| TC-I-52 | 扫描命名脚本 | 检查变量引用 | 一律 `${VAR}` 花括号；`$abi_app_` 这类写法即 FAIL（`24edf9f7` 的根因） |
| TC-I-53 | 检查上传 glob | 与命名前缀比对 | glob 必须能匹配新前缀（`Slive_*` 而非 `Slive-*`） |
| TC-I-54 | 三 ABI 改名 | 检查目标文件名 | 三个文件名互不相同（`armeabi-v7a`/`arm64-v8a`/`x86_64` 各自出现在平台段） |

### 3.5 仓库形态

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-I-60 | 克隆后 | `git submodule status` | 2 个 gitlink：`simple_live_core`、`simple_live_tv_app`，均非 `-` 前缀（未初始化） |
| TC-I-61 | 普通 clone（无 `--recurse-submodules`） | 直接构建 App | 应失败并提示缺 core —— 验证 CONTRIBUTING 的说明必要 |
| TC-I-62 | 读 `.gitignore` | 检查例外 | `*.py` 忽略 + `!tools/gen_changelog.py` 例外对并存 |
| TC-I-63 | 读 `.gitignore` | 检查四个本地构建仓 | `media-kit/`、`libmpv-*-build/`、`libmpv-worktrees/` 均被忽略 |

## 4. 建议补的自动化（当前为零）

| 优先级 | 用例 | 落地方式 |
| --- | --- | --- |
| P0 | TC-I-01/02/04 版本一致性 | `pr.yaml` 加一个 `uv run` / `python` 步骤，10 行脚本即可 |
| P0 | TC-I-30/32/33/34/36 工作流契约 | `actionlint` + 少量 `grep` 断言 |
| P1 | TC-I-10~19 生成器行为 | `pytest` 针对 `group_commits` / `resolve_to_tag` / `build_markdown` 三个纯函数 |
| P1 | TC-I-50~54 命名规范 | 命名规则抽成单一定义（脚本或 env），测试直接断言 |

## 5. 已知缺口

- 工作流本体无法在本地执行，所有 CI 行为只能靠「push 后看 Actions」验证。
- `gen_changelog.py` 的分组/去重逻辑没有单测，本次实测依赖真实仓库历史。
- `update_version.dart` / `update_contributor.dart` 无测试，且会就地改文件，回归只能靠 `git diff` 目检。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-I-52/53/54 命名与 glob | `24edf9f7` |
| TC-I-30 子模块 checkout | `c767f931` |
| TC-I-10~19 生成器行为 | `63c1eb8d` |
| TC-I-05 metainfo 同步 | `099d9c26`、`0dbb3bd6` |
