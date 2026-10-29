# flatpak 修改历史（Git 完整复现）

> 锚点：父仓 future `16454863`（2026-10-29）｜`git log future -- flatpak` 全量 **10** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[repo-infra](../../doc/repo-infra/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游）。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- flatpak
git show --stat <hash> -- flatpak
git log -p future -- flatpak/flatpak-manifest.yaml | head -120
```

## 2. 阶段归纳

本组件只有 10 条提交，且**全部围绕同一件事**：跟 Flutter SDK 版本。没有一次功能性改动 —— 说明 Flatpak 分发自建立起就没再演进过结构，只做版本同步。

| 阶段 | 日期范围 | 条数 | 主题 |
| --- | --- | --- | --- |
| 3.47.x 跟进 | 2026-10-09 ~ 10-25 | 3 | 3.47.6 → 3.47.8；其一为斗鱼 cookie 修复连带改清单 |
| 3.47.0 ~ 3.47.4 | 2026-08-16 ~ 09-22 | 5 | 四个小版本逐次跟进 + 斗鱼游客流修复 |
| 3.44.8 与建仓 | 2026-07-30 ~ 08-01 | 2 | 清单随仓库根提交引入；首次 Flutter 升级 |

## 3. 全量时间线（10 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-25 | `ddb0cc3e` | G | chore: 升级 Flutter 至 3.47.8（清单 `tag` + `commit` 同步） |
| 2026-10-09 | `6847a151` | S | chore: sync fvm 3.47.6 |
| 2026-09-22 | `b492f965` | S | fix(douyu): douyu 游客模式直播流只能存活 5min，需要配置 cookie（连带清单） |
| 2026-09-17 | `ee085b69` | S | chore: flutter version 3.47.4 |
| 2026-09-06 | `48fa02cb` | S | feat: 允许禁用「滑动调节亮度/音量」（连带清单） |
| 2026-08-29 | `cb2f3a9f` | S | chore: upgrade flutter to 3.47.2 |
| 2026-08-21 | `8b40850f` | S | chore: upgrade flutter to 3.47.1 |
| 2026-08-16 | `542acd47` | S | chore: upgrade flutter to 3.47.0 |
| 2026-08-01 | `9bdc5f10` | S | chore: bump flutter v3.44.8 |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time（仓库根提交，含清单初版） |

## 4. 版本演进表（清单 `tag` 字段）

| 日期 | Flutter 版本 | 提交 |
| --- | --- | --- |
| 2026-07-30 | 初版（3.44.x 之前） | `543910ba` |
| 2026-08-01 | 3.44.8 | `9bdc5f10` |
| 2026-08-16 | 3.47.0 | `542acd47` |
| 2026-08-21 | 3.47.1 | `8b40850f` |
| 2026-08-29 | 3.47.2 | `cb2f3a9f` |
| 2026-09-17 | 3.47.4 | `ee085b69` |
| 2026-10-09 | 3.47.6 | `6847a151` |
| 2026-10-25 | 3.47.8（当前） | `ddb0cc3e` |

对照 `simple_live_app/pubspec.yaml` 的 `environment.flutter: 3.47.8` —— 当前一致。

## 5. 当前状态

- `flatpak/flatpak-manifest.yaml` 82 行；runtime `org.freedesktop.Platform 25.08` + `llvm21` 扩展。
- 提交 10 条（G 1 / S 9），全部为版本跟进或连带改动，无结构性重构。
- 清单被 4 个工作流复用（release / dev / future / pr），其中 pr 只构建不打包。
- 元数据 `metainfo.xml` 的 `<releases>` 只 1 条（1.8.14），与 CHANGELOG 的版本数不匹配 —— 说明 `update_version.dart` 近期未跑。
