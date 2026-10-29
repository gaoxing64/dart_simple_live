# repo-infra 工作流程图

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：`.github/`（工作流 + release.yml）、`scripts/`、`tools/`、`assets/` 版本资产、根文档（README / CONTRIBUTING / CHANGELOG / .gitmodules / .gitignore）
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/workflow-diagram.md)｜[TV](../../simple_live_tv_app/doc/workflow-diagram.md)｜[Core](../../simple_live_core/doc/workflow-diagram.md)｜[Docs 站](../../doc/docs-site/workflow-diagram.md)｜[Flatpak](../../flatpak/doc/workflow-diagram.md)

## 1. 三条触发线，一套产物规范

```
push/PR ─┬─ dev         → publish_app_dev.yaml       （5 job，只进 Artifacts）
         ├─ future      → publish_app_future.yaml    （5 job，只进 Artifacts，无 paths 过滤）
         ├─ dev + tv/** → Prebuild_tv_app_dev.yaml   （1 job，只进 Artifacts）
         ├─ master+docs → docs-deploy.yaml           （build → Pages）
         └─ PR→main/dev → pr.yaml                    （4 job，只构建不发布）
tag v* ─────→ publish_app_release.yml    （4 job，写 GitHub Release）
dispatch ───→ publish_tv_app_release.yaml（1 job，写 GitHub Release，tag 前缀 tv_v）
```

证据：`.github/workflows/*` 各文件 `on:` 段。所有 checkout 均带 `submodules: recursive`（`c767f931` 引入，6 文件 20 处）。

## 2. App 发版主链（`publish_app_release.yml`）

```
push tag v*
  → 四个 job 并行：build-android / build-linux / build-windows / build-flatpak
        （linux、flatpak 各自 2 架构矩阵：ubuntu-24.04 x86_64 + ubuntu-24.04-arm aarch64）
  → checkout@v7  fetch-depth: 0（生成日志要完整历史与 tag）+ submodules: recursive
  → 密钥落地：KEYSTORE_BASE64 / FIREBASE_JSON / FIREBASE_OPTIONS_DART → key.properties + google-services.json
  → setup-java@v5 zulu 17 → subosito/flutter-action（版本取 simple_live_app/pubspec.yaml）
  → flutter pub get
  → 读 assets/app_version.json 两次：
       naming_version → VERSION + BUILD_TS（产物命名）
       version        → name / body / prerelease（Release 元数据）
  → 构建：apk --split-per-abi | fastforge linux(deb,zip) | fastforge windows(msix,zip,exe) | flatpak-builder
  → 按规范改名 → upload-artifact@v7
  → tools/gen_changelog.py --previous-tag auto --tag-prefix v → release-notes.md
  → softprops/action-gh-release@v3（name=version, body_path=notes, body=version_desc, prerelease）
```

四条硬约束（都在 workflow 注释里写死）：

1. **版本与 tag 从 `assets/app_version.json` 推导，不读 `github.ref_name`** —— `workflow_dispatch` 时 `ref_name` 是分支名。
2. **日志生成失败不阻断发版**：不用 `continue-on-error`（会连日志都吞掉），改为 `echo "::error::"` + 回退 `version_desc`。
3. **`body_path` 只传非空文件**：指向不存在文件会让 `action-gh-release` 报 ENOENT 而整体失败，故用 `[ -s release-notes.md ]` 决定是否输出。
4. **`fetch-depth: 0`** 是生成日志的前置；浅克隆会让 `git describe --tags` 取不到上一个 tag。

## 3. 产物命名规范（`5db4ecc9`）

```
{产品名}_V{版本号}_{平台}_{代号}_({语言})_{构建类型}_{发布编号}_(Build{时间})
```

| 平台 | 代号 | 实样 |
| --- | --- | --- |
| Android | `app` / `tv` | `Slive_V1.8.14_android-arm64-v8a_app_(zh-cn)_release_123_(Build261029153000).apk` |
| Linux | `app` | `Slive_V…_linux-x86_64_app_(zh-cn)_release_…deb` / `.zip` |
| Linux Flatpak | `app` | `Slive_V…_linux-x86_64_flatpak_(zh-cn)_release_….flatpak` |
| Windows | `app` | `Slive_V…_windows_app_(zh-cn)_release_….msix/.zip/.exe` |

`BUILD_TS=$(TZ=Asia/Shanghai date +%y%m%d%H%M%S)`、`发布编号=github.run_number`。

**回归教训（`24edf9f7`）**：命名改造一次带出三个静默故障 —— bash 里 `$abi_app_` 少了花括号被当空变量，三个 ABI 改名到同一文件互相覆盖只剩最后一个；flatpak 上传 glob 仍是 `Slive-*.flatpak` 与新前缀 `Slive_V…` 不匹配，两个架构产物被静默丢弃。当前代码已用 `${VERSION}`、`${BUILD_TS}` 花括号与 `Slive_*.flatpak` glob。

## 4. 发布说明生成（`tools/gen_changelog.py`，280 行）

```
main()
  → read_version_desc(--version-desc-file)        # 取 version / version_desc
  → resolve_to_tag(--to | version, --tag-prefix)  # v1.8.9 直查 → 裸版本拼前缀
       tag 不存在 → to_ref = HEAD + ::warning
  → resolve_previous_tag(auto)                    # git describe --tags --abbrev=0 <to>^
       取不到 → 按首次发布处理，无 Full Changelog 段
  → collect_commits(prev..to_ref, --no-merges)    # 区间非法则退化为全历史
  → group_commits()                               # 正则 ^(type)(scope)?(!)?: desc
       8 类：Breaking / Features / Bug Fixes / Performance / Refactors
             / Documentation / Build & CI / Chores & Dependencies
       兜底 🧩 Other Changes；同 (type, text) 去重
  → build_markdown()                              # header + version_desc + What's Changed + Full Changelog
  → 写 --output
```

- 分类口径与 `.github/release.yml` 一一对应（顺序也一致），后者只服务 PR 路线（`gh release create --generate-notes`）。
- 只依赖 `git` 与标准库，不联网。
- TV 发版传 `--header "# Android TV"`、`--tag-prefix tv_v`。

## 5. 版本资产与脚本链

```
CHANGELOG.md ──(scripts/update_version.dart)──┬→ assets/app_version.json  (version / version_num / version_desc / prerelease / download_url)
                                             └→ simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml（releases 全量重写）

README.md ──(scripts/update_contributor.dart)──→ <!-- CONTRIBUTORS:START/END --> 区块重写

assets/app_version.json ──(App 运行时)──→ https://raw.gitmirror.com/.../master/assets/app_version.json
                                    └────→ https://cdn.jsdelivr.net/gh/slotsun/dart_simple_live@master/assets/app_version.json
```

- `update_version.dart` 用 `_findProjectRoot()` 向上找 `pubspec.yaml + assets/` 定位根目录；`--version x.y.z` 才同时改 `version`/`version_num`（`_versionToNum` = 主*10000+次*100+修订）。
- 两个脚本**都不在 CI 中调用**（`grep scripts/ .github/` 为空），是人工发版前的本地步骤。
- `assets/huya_config.json` 只存 `hysdk_ua` 一个键，供客户端下发 UA。

## 6. 分支与仓库形态

```
future（开发主干，历史已重写，根提交 543910ba）
  ├─ 375 条提交
  ├─ simple_live_core/   → gitlink（子仓 gaoxing64/dart_simple_live_core）
  ├─ simple_live_tv_app/ → gitlink（子仓 gaoxing64/dart_simple_live_tv_app）
  └─ media-kit/ 与三个 libmpv-*-build/ → 仅本地，.gitignore 排除

dev（Github Flow 主干）→ master（发版时 squash merge，停更后删除 dev 并脱敏）
```

`.gitignore` 有两条刻意例外：`*.py` 全忽略但 `!tools/gen_changelog.py` 例外（否则 CI 里 `python tools/gen_changelog.py` 文件不存在）；`deliverables/`、`.workbuddy/`、`.fvm/` 与四个本地构建仓不入库。

## 7. 失败与兜底

| 失败点 | 表现 | 兜底 |
| --- | --- | --- |
| 浅克隆 | `git describe` 无 tag，日志退化为全历史 | `fetch-depth: 0` 写死 |
| 版本文件与 tag 不一致 | `::warning::` + 对比终点退化 HEAD，Full Changelog 链接错 | 发版前跑 `update_version.dart --version` |
| 日志生成异常 | `::error::` 可见但 job 继续 | Release 正文回退 `version_desc` |
| `body_path` 指向不存在文件 | `action-gh-release` ENOENT | 只在 `-s` 通过时输出 `file=` |
| 子仓未取到 | 编译缺 `simple_live_core` | 所有 checkout 带 `submodules: recursive` |
| 重名产物覆盖 | 只剩最后一个 ABI 包 | `${VAR}` 花括号（`24edf9f7`） |
| glob 前缀不匹配 | 产物静默丢弃、Release 附件为空 | 上传 glob 与命名规范同批改 |

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| 产物命名统一规范 | `5db4ecc9` |
| 命名改造的三个回归修复 | `24edf9f7` |
| 子仓化 + 全量 `submodules: recursive` | `c767f931` |
| future 多端构建恢复 | `cb506ea3` |
| release action 升 v3 | `abad1a1d` |
| Linux flutter channel 回退 | `2160f940`、`0774ff89` |
