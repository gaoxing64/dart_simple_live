# repo-infra 待办与优化清单

> 锚点：父仓 future `16454863`（2026-10-29）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/backlog.md)｜[TV](../../simple_live_tv_app/doc/backlog.md)｜[Core](../../simple_live_core/doc/backlog.md)｜[Flatpak](../../flatpak/doc/backlog.md)

## P0 — 会让发版出错或静默丢产物

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | 版本号三处手工同步，`assets/app_version.json`（1.8.14）落后 `simple_live_app/pubspec.yaml`（1.8.15+10815）；发版工作流只读前者做命名与 Release 元数据，`update_version.dart` 不碰 `pubspec.yaml` | `assets/app_version.json:2`、`simple_live_app/pubspec.yaml:2`、`scripts/update_version.dart`（只写 app_version.json + metainfo.xml） | 发版前检查清单强制 `dart run scripts/update_version.dart --version x.y.z` **并**手改 pubspec；或让脚本顺带改 `pubspec.yaml` 的 `version:` 行 |
| P0-2 | 两个发版工作流无 `concurrency`：同 tag 重跑或手动 dispatch 会并发写同一 Release，`body` 与附件互相覆盖 | `publish_app_release.yml`、`publish_tv_app_release.yaml` 全文无 `concurrency`（dev/future/tv-dev 都有） | 加 `concurrency: group: release-${{ github.ref_name }}`，`cancel-in-progress: false` |
| P0-3 | **7 个工作流全部只构建、零测试**：无 `flutter test` / `cargo test` / `flutter analyze`，PR 门禁也只看「能不能编译」 | `grep -rnE "flutter test\|cargo test\|analyze" .github/workflows/` → 空；`pr.yaml` 只有 4 个 build job | PR 门禁加 `flutter test`（App/TV）与 `cargo test`（core），允许先用 `continue-on-error` 观察一轮再转硬门禁 |
| P0-4 | 4 个 release job 并行写同一 Release：任一 job 先建 Release，其余 job 以同 `name` 追加附件；某 job 失败则该平台附件缺失且无提示 | `publish_app_release.yml` 4 处 `softprops/action-gh-release@v3`，均无 `needs` | 改为「先聚合 artifacts，再由单 job 统一发 Release」，或至少给失败 job 加 `::error::` 汇总步骤 |
| P0-5 | TV 发版工作流用 `softprops/action-gh-release@v1` 与 `actions/upload-artifact@v3`，v3 已被 GitHub 弃用 | `publish_tv_app_release.yaml:83`、`:135` | 对齐到 `@v7` 与 `@v3`（App 侧现行版本） |

## P1 — 维护性与额度

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | `publish_app_dev.yaml`（441 行）与 `publish_app_future.yaml`（440 行）几乎逐行重复，仅 action 版本与 `ref`/paths 不同 | `diff` 两文件后差异集中在 `@v4/v6/v7`、`@v4/v7`、paths 段 | 抽成可复用工作流（`workflow_call`）+ 两个薄壳，参数化 ref 与 action 版本 |
| P1-2 | `future` 工作流**无 `paths` 过滤**，任何 push（含纯文档）都触发 5 个 job 含 macOS | `publish_app_future.yaml:5-9` 只有 `branches: [future]` | 补 `paths: ['simple_live_app/**','simple_live_core/**','assets/**']`，与 dev 对齐 |
| P1-3 | Action 版本四套并存：`checkout` v4/v6/v7、`setup-java` v4/v5、`upload-artifact` v3/v4/v7、`gh-release` v1/v3 | 见 [architecture §5](./architecture.md) 版本矩阵 | 统一到一套（建议 checkout v7 / setup-java v5 / upload-artifact v7 / gh-release v3） |
| P1-4 | JDK 版本不一致：Android job 用 17，mac-ios job 与 `pr.yaml` 用 21 | `publish_app_release.yml:42`(17)、`publish_app_dev.yaml:126`(21)、`pr.yaml:23`(21) | 统一（AGP 9 建议 17 或 21 择一，四个工作流同值） |
| P1-5 | `fastforge` 每次 CI 现场 `git clone` + `melos run activate`，上游仓不可用即桌面端全挂；未固定 commit | 4 个工作流各 1 处 `git clone https://github.com/SlotSun/fastforge.git` | 固定 tag/commit；或预构建成 composite action / 自托管二进制 |
| P1-6 | `.github/release.yml` 依赖的标签（feat/fix/perf/refactor/breaking-change/Semver-* 等）在仓内不存在，PR 路线生成说明会全落 🧩 Other Changes | `.github/release.yml` 头部注释自陈「本仓库当前**没有**这些标签，也没有 labeler」 | `gh label create` 补齐 + 加 labeler 工作流；或把 categories 精简到已有标签 |
| P1-7 | `docs-deploy.yaml` 只在 `master` + `paths: docs/**` 触发：future/dev 上的文档改动不会部署，且 `doc/` 知识库改动完全不触发 | `docs-deploy.yaml:3-9` | 明确「文档站只发 master」的口径；若要预览，加 `workflow_dispatch` + 手动选分支（已有 dispatch 但 ref 固定 master） |
| P1-8 | `scripts/update_contributor.dart` 文件内用法注释写的是 `scripts/add_contributor.dart`（文件名不符） | `scripts/update_contributor.dart:6` | 改注释为实际文件名 |
| P1-9 | `assets/app_version.json` 的 `version_num` 靠 `_versionToNum`（主*10000+次*100+修订）推导，与 `pubspec.yaml` 的 `+build` 号（10815）无校验 | `scripts/update_version.dart:_versionToNum` | 发版前断言 `version_num == pubspec 的 +build` |

## P2 — 结构与文档

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | `crowdin.yml` 的 `files:` 为空数组，Crowdin 集成形同未启用 | `crowdin.yml`（9 字节） | 明确关闭并从 workflow 移除引用，或补上真实翻译源 |
| P2-2 | `gen_changelog.py` 在「区间非法」时退化为全历史，首次发布/无 tag 时会把整条历史刷进 Release 正文 | `collect_commits()` 的 `except RuntimeError: out = run_git(["log", ..., to_ref])` | 退化时加 `::warning::` 并在正文标注「全量历史」 |
| P2-3 | `.gitignore` 用 `*.py` 全忽略 + 单文件例外，新增任何 Python 工具都会被静默忽略 | `.gitignore` 的 `*.py` 与 `!tools/gen_changelog.py` | 改为 `tools/*.py` 白名单式忽略 |
| P2-4 | 三个 `libmpv-*-build/` 与 `media-kit/` 只在本机存在（`.gitignore` 排除），CI 靠 App 的远程 libs 下载，本地与 CI 的二进制来源不同步 | `.gitignore` 注释段 | 在 README/CONTRIBUTING 显式写明「本地可改二进制，CI 不可」 |
| P2-5 | `assets/` 同时存放运行时下发的 JSON 与图标/截图，职责混杂 | `assets/` 9 个条目 | 拆 `assets/config/`（下发）与 `assets/branding/`（宣传图） |
| P2-6 | 无发版 checklist 文档；版本、tag、CHANGELOG、app_version、pubspec 五处先后顺序只存在于个人经验 | `CONTRIBUTING.md` 无发版章节 | 写 `docs/release.md` 或根 `RELEASE.md` |

## 已决策取舍

- 保留「发版工作流无 concurrency」以外的开发流并发取消：dev/future 高频 push，取消旧构建省额度。
- 保留自研 `gen_changelog.py` 而非全用 GitHub 原生说明：本仓主要直接 push，原生说明抓不到非 PR commit。
- 保留 `fastforge` 现场 clone：省去自建 distribution 的成本，接受外部依赖风险。
- 保留 `future` 无 paths 过滤：future 是开发主干，任何改动都值得一次全平台构建验证（代价是额度）。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P0-2 命名规范带出的 glob/变量回归 | `24edf9f7` |
| P1-1 dev/future 重复 | 两文件同期生成，`5db4ecc9` 同批改 5 工作流 |
| P1-5 fastforge 外部依赖 | `a38cbc75` 起沿用 |
| P0-5 TV action 过期 | `publish_tv_app_release.yaml` 自 `bafc703b` 未再升级 |
| P2-3 `*.py` 例外 | `63c1eb8d` |
