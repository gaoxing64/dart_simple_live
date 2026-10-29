# repo-infra 修改历史（Git 完整复现）

> 锚点：父仓 future `16454863`（2026-10-29）｜`git log future -- .github scripts tools assets` 全量 **26** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/update-history.md)｜[TV](../../simple_live_tv_app/doc/update-history.md)｜[Core](../../simple_live_core/doc/update-history.md)｜[Flatpak](../../flatpak/doc/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游）。
> 本表是路径过滤后的**全量时间线**（含上游同步、合并与文档提交），新→旧。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- .github scripts tools assets
git log --date=short --pretty=format:'%h %ad %an %s' future -- .github
git log --date=short --pretty=format:'%h %ad %an %s' future -- scripts tools assets
git show --stat <hash> -- .github scripts tools assets
```

> `flatpak/` 的 10 条单独记在 [flatpak KB](../../flatpak/doc/update-history.md)，本表不重复。

## 2. 阶段归纳

| 阶段 | 日期范围 | 条数 | 主题 |
| --- | --- | --- | --- |
| 子仓化 + 发布链收尾 | 2026-10-17 ~ 10-27 | 3 | 产物命名统一规范（5 文件 282 行）、三个静默回归修复、core/tv 改 submodule 并给 6 工作流补 `submodules: recursive` |
| 上游同步期 | 2026-09-12 ~ 10-14 | 13 | 4 次 dev→future 合并、TV dev 预构建、contributors 更新、release v1.8.11~1.8.14 的版本资产写入、`gen_changelog.py` 入仓 |
| CI 稳定化 | 2026-08-16 ~ 09-21 | 9 | future 多端构建恢复、iOS 构建修复、action 升版、linux flutter channel 回退 ×2、CI 更新 |
| 基建成形 | 2026-07-30 | 1 | 仓库根提交 `543910ba`（含首批 CI 与资产） |

## 3. 全量时间线（26 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-27 | `c767f931` | G | refactor(repo): simple_live_core 与 simple_live_tv_app 改为 submodule（6 工作流 20 处 checkout 加 `submodules: recursive`） |
| 2026-10-19 | `24edf9f7` | G | fix(ci): 修复产物命名规范引入的三个产物回归（`$abi_app_` 缺花括号致三 ABI 覆盖、flatpak glob 前缀不匹配、libc 0.2.190→0.2.191 修 iOS） |
| 2026-10-17 | `5db4ecc9` | G | ci: 统一 CI 产物命名为 `{产品名}_V{版本号}_{平台}_{代号}_({语言})_{构建类型}_{发布编号}_(Build{时间})` |
| 2026-10-14 | `5ae375f1` | G | merge: 同步 dev（v1.8.15 之后 5 提交）到 future |
| 2026-10-14 | `bafc703b` | S | ci: prebuild tv_app v1.5.1 with flutter v3.35.7 after（写 `assets/tv_app_version.json`） |
| 2026-10-09 | `1c97d00b` | G | merge: 同步上游 dev（v1.8.14）到 future |
| 2026-10-03 | `b1df5968` | S | fix: SC 时间戳对不齐，改由价格&用户名&消息判断去重（连带 workflow） |
| 2026-09-30 | `f095d767` | S | doc: update contributors（`scripts/update_contributor.dart` 产出） |
| 2026-09-26 | `aa056416` | S | fix: ci |
| 2026-09-25 | `099d9c26` | S | release v1.8.14（`assets/app_version.json`） |
| 2026-09-24 | `0dbb3bd6` | S | release v1.8.13（`assets/app_version.json`） |
| 2026-09-24 | `34c39a31` | G | merge: 合并上游 dev（v1.8.12）到 future |
| 2026-09-21 | `2160f940` | S | fix(ci): revert linux flutter channel master |
| 2026-09-21 | `0774ff89` | S | fix(ci): revert subosito/flutter-action@v2 on windows/linux |
| 2026-09-20 | `3970ae46` | S | chore(ci): 更新 ci |
| 2026-09-18 | `85d9864e` | S | release v1.8.12（`assets/app_version.json`） |
| 2026-09-18 | `a38cbc75` | G | Merge branch 'dev' into future（upstream v1.8.11） |
| 2026-09-18 | `abad1a1d` | S | fix(ci): softprops/action-gh-release@v3 |
| 2026-09-18 | `378be06b` | S | release v1.8.11（`assets/app_version.json`） |
| 2026-09-18 | `899212ba` | G | Merge branch 'dev' into future |
| 2026-09-16 | `63c1eb8d` | G | fix: 修复分页、播放器与桌面交互的遗留问题（新增 `tools/gen_changelog.py`） |
| 2026-09-14 | `9b0d4308` | S | feat: 完善弹幕随屏幕大小放缩（连带 `assets/app_version.json`） |
| 2026-09-14 | `cb7f9919` | S | chore(core): sync huya-ua（写 `assets/huya_config.json`） |
| 2026-09-12 | `cb506ea3` | G | ci(github workflows): 恢复 future 分支的多端构建 workflow |
| 2026-08-16 | `594686f2` | S | fix(ci): ios building error |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time（仓库根提交，含首批 CI 与版本资产） |

> 表内 26 行严格按 `git log` 输出顺序（新→旧，日期为 commit 日期）。

## 4. 关键提交的影响面

| 提交 | 改动范围 | 事后影响 |
| --- | --- | --- |
| `5db4ecc9` | 5 个工作流，+282 −35 | 四平台产物首次统一命名，`BUILD_TS` 与 `run_number` 进入文件名 |
| `24edf9f7` | 5 工作流 + `simple_live_core/Cargo.lock`，+11 −11 | 三个静默回归：ABI 覆盖、flatpak 产物丢弃、iOS 编译失败；确立「改命名必须同批改 glob」 |
| `c767f931` | 6 工作流 + `.gitmodules` + `docs/contributing.md`，+20 处 checkout | 仓库从 monorepo 变为「父仓 + 2 子仓」；漏 `submodules: recursive` 即构建失败 |
| `63c1eb8d` | 新增 `tools/gen_changelog.py` + `.gitignore` 的 `!tools/gen_changelog.py` 例外 | `*.py` 全忽略但此文件例外，否则 CI 里文件不存在 |
| `cb506ea3` | 恢复 future 多端构建 | future 从「只跑部分平台」变成 5 job 全量 |

## 5. 当前状态

- future HEAD `16454863`；基建路径提交 26 条（G 10 / S 16）。
- 7 个工作流、1 个 release 分组配置、2 个 Dart 脚本、1 个 Python 脚本、2 个版本 JSON、1 个 UA JSON。
- 最近一次基建改动是 2026-10-27 的子仓化；此后 10-29 的三次 docs 提交未触及 `.github`。
- 无任何 CI 内测试步骤（见 [backlog](./backlog.md) P0-3）。
