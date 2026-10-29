# repo-infra 架构与选型对照

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：CI/CD、发布链、版本资产、仓库形态
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/architecture.md)｜[TV](../../simple_live_tv_app/doc/architecture.md)｜[Core](../../simple_live_core/doc/architecture.md)｜[Docs 站](../../doc/docs-site/architecture.md)｜[Flatpak](../../flatpak/doc/architecture.md)

## 1. 定位

本仓根目录没有代码，只有**发布工程的胶水层**：7 个 GitHub Actions 工作流、1 个 release 分组配置、2 个 Dart 脚本、1 个 Python 发布说明生成器、2 个版本 JSON、3 个平台元数据文件、6 份根文档。它们的唯一职责是：把 `simple_live_app` / `simple_live_tv_app` / `simple_live_core` 编译成四平台产物，按统一规范命名，写进 GitHub Release，并让客户端能自查新版本。

## 2. 资产清单

| 路径 | 行数 | 职责 |
| --- | --- | --- |
| `.github/workflows/publish_app_release.yml` | 550 | Tag 发版：android / linux / windows / flatpak 四 job → Release |
| `.github/workflows/publish_app_dev.yaml` | 441 | dev 分支增量：5 job（含 mac-ios）→ 仅 Artifacts |
| `.github/workflows/publish_app_future.yaml` | 440 | future 分支增量：5 job → 仅 Artifacts（无 paths 过滤，任何 push 都触发） |
| `.github/workflows/pr.yaml` | 205 | PR 门禁：mac-ios-android / linux(2 arch) / windows / flatpak 只构建 |
| `.github/workflows/publish_tv_app_release.yaml` | 148 | TV 手动发版：单 job → Release，tag 前缀 `tv_v` |
| `.github/workflows/Prebuild_tv_app_dev.yaml` | 89 | TV dev 预构建：仅 APK → Artifacts |
| `.github/workflows/docs-deploy.yaml` | 67 | master + `docs/**` → VitePress → GitHub Pages |
| `.github/release.yml` | 67 | GitHub 原生「自动生成发布说明」分组（PR 路线） |
| `tools/gen_changelog.py` | 280 | 基于 commit 生成 Release 正文（发版路线） |
| `scripts/update_version.dart` | 178 | CHANGELOG → `app_version.json` + metainfo.xml |
| `scripts/update_contributor.dart` | 168 | 把 GitHub 用户写进 README 的 CONTRIBUTORS 区块 |
| `assets/app_version.json` | 7 | App 版本 + 更新说明 + 下载地址（客户端远程读取） |
| `assets/tv_app_version.json` | 7 | TV 同上（`prerelease: true`） |
| `assets/huya_config.json` | 3 | 虎牙 SDK UA 下发 |
| `flatpak/flatpak-manifest.yaml` | 82 | Flatpak 清单（见 [flatpak KB](../../flatpak/doc/architecture.md)） |

## 3. 关键选型

| 选择 | 现状 | 理由 / 代价 |
| --- | --- | --- |
| CI 平台 | GitHub Actions，全部 `ubuntu-latest` / `macos-latest` / `windows-latest` 托管 | 零运维；macOS 分钟数贵，故 iOS/Mac 只在 dev / future / pr 三个工作流里跑 |
| Flutter 版本源 | `flutter-version-file: <项目>/pubspec.yaml` | 版本随项目走，不在 CI 里硬编码；代价是 `pubspec.yaml` 的 `environment.flutter` 成为发版契约 |
| 打包工具 | `fastforge`（`SlotSun/fastforge`，CI 现场 clone + `melos run activate`） | 一次产出 deb/zip、msix/zip/exe、dmg/zip；不 fork 到 Actions Marketplace，依赖外部仓可用性 |
| Android 签名 | `KEYSTORE_BASE64` → `timheuer/base64-to-file` → `key.properties` | 密钥不进仓库；`key.properties` 每次构建现场生成 |
| Firebase 配置 | `FIREBASE_JSON` / `FIREBASE_OPTIONS_DART` base64 解码落地 | 同理；缺 secret 时 Android 构建直接失败 |
| 版本号读取 | `juliangruber/read-file-action` + `fromJson()` 两次读同一文件 | 命名与元数据两条用途分开（`naming_version` / `version`），互不干扰 |
| 发布说明 | 自研 `gen_changelog.py`（commit 驱动）+ `.github/release.yml`（PR 驱动） | 本仓主要直接 push 到分支，PR 说明生成器抓不到这些 commit，故发版必须走脚本；两者分类口径对齐 |
| Release 上传 | `softprops/action-gh-release`（App v3 / TV v1） | 单 action 同时建 Release 与传附件；`token: secrets.TOKEN` 而非默认 GITHUB_TOKEN（跨 fork 发布） |
| 并发控制 | dev / future / tv-dev 用 `cancel-in-progress: true`；**发版两个工作流无 `concurrency`** | 开发分支省额度；发版刻意不取消，避免半成品 Release |
| 子仓 | `simple_live_core` / `simple_live_tv_app` 为 gitlink | 允许独立历史与独立发版；代价是所有 checkout 必须 `submodules: recursive` |
| 文档站 | VitePress 2.0.0-alpha.15 + pnpm，独立 `docs/` 子站 | 见 [docs-site KB](../../doc/docs-site/architecture.md) |

## 4. Secret 矩阵

| Secret | 使用者 | 用途 |
| --- | --- | --- |
| `TOKEN` | release.yml、tv_release | `action-gh-release` 跨仓发布 |
| `KEYSTORE_BASE64` / `STORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` | app 三个工作流 | App APK 签名 |
| `TV_KEYSTORE_BASE64` / `TV_STORE_PASSWORD` / `TV_KEY_PASSWORD` / `TV_KEY_ALIAS` | tv 两个工作流 | TV APK 签名（与 App 分开，防止串签） |
| `FIREBASE_JSON` / `FIREBASE_OPTIONS_DART` | app 三个工作流 | Android Firebase 埋点 |

`pr.yaml` 与 `docs-deploy.yaml` **不读任何 secret** —— PR 来自 fork 时 secret 不可用，这也意味着 PR 构建产出的是未签名包。

## 5. Action 版本矩阵（漂移现状）

| Action | dev | future | release | tv-release | tv-dev | pr | docs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `actions/checkout` | v7 | v6 / v4 | v7 | v4 | v7 | v4 | v4 |
| `actions/setup-java` | v5 / v4 | v5 / v4 | v5 | v4 | v5 | v4 | — |
| `subosito/flutter-action` | v2.16.0 / v2 | v2 | v2.16.0 / v2 | v2 | v2.16.0 | v2 | — |
| `actions/upload-artifact` | v7 | v4 | v7 | **v3** | v7 | — | — |
| `softprops/action-gh-release` | — | — | v3 | **v1** | — | — | — |

TV 两个工作流是唯一还停在 `upload-artifact@v3` / `action-gh-release@v1` 的，v3 已被 GitHub 弃用。

## 6. 版本一致性三角

```
CHANGELOG.md  ──手工──→  assets/app_version.json.version
                             │                    │
                             │                    └→ 客户端远程检查（gitmirror / jsDelivr，@master）
                             ↓
simple_live_app/pubspec.yaml.version  ──→  APK 内部 versionName/versionCode
                             ↓
              simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml（releases 段）
```

现状：`pubspec.yaml` = `1.8.15+10815`，`assets/app_version.json` = `1.8.14`（`version_num` 10814）。**两者不一致**是当前真实状态（future 分支已升版本但未发版），见 backlog P0-1。

## 7. 与各组件的关系

| 组件 | 关系 |
| --- | --- |
| `simple_live_app` | 被构建主体；`pubspec.yaml` 提供 Flutter 版本与依赖钉版 |
| `simple_live_tv_app` | 同左；独立 tag 前缀 `tv_v`，独立 keystore |
| `simple_live_core` | 子仓，被 `flutter pub get` 拉取；`Cargo.lock` 曾在本仓被修（`24edf9f7` 的 libc 0.2.191） |
| `media-kit` + 三个 libmpv 构建仓 | **不入本仓**（`.gitignore` 排除），通过 App 的 `dependency_overrides` 与 libs 下载 URL 间接参与构建 |
| `docs/` | 被 `docs-deploy.yaml` 部署，`paths: docs/**` 过滤 |

## 8. 风险

1. **发版无并发锁**：两个 release 工作流都没有 `concurrency`，同一 tag 重复触发或手动重跑会并发写同一 Release。
2. **版本号三处手工同步**：`CHANGELOG.md` → `app_version.json` → `pubspec.yaml`，`update_version.dart` 只覆盖前两者，`pubspec.yaml` 仍需手改。
3. **`fastforge` 依赖外部仓**：CI 每次 `git clone https://github.com/SlotSun/fastforge.git` + `melos run activate`，该仓不可用即全部桌面端构建失败。
4. **`future` 无 paths 过滤**：任何 push 都触发 5 个 job（含 macOS），额度消耗大。
5. **CI 零测试**：7 个工作流全部只做构建，无 `flutter test` / `cargo test` / `analyze`。测试基线完全靠本地人工跑（见 app test-suite §4 的 13 条存量失败）。
6. **TV 工作流 action 过期**：`upload-artifact@v3` 已被弃用，随时可能整体失败。
7. **`update_contributor.dart` 注释与文件名不符**：文件内用法写的是 `scripts/add_contributor.dart`，实际文件名是 `update_contributor.dart`。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| 产物命名统一规范（5 文件 282 行） | `5db4ecc9` |
| 命名改造的三个静默回归修复 | `24edf9f7` |
| 子仓化 + 20 处 `submodules: recursive` | `c767f931` |
| 恢复 future 多端构建 | `cb506ea3` |
| release action 升 v3 | `abad1a1d` |
| iOS 构建修复（libc 0.2.191） | `24edf9f7` |
| 发布说明脚本入仓（`*.py` 例外） | `63c1eb8d` |
