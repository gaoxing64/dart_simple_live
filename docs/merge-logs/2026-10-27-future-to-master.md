# 合并日志：future → master（unrelated histories 首次合并）

- 日期：2026-10-27
- 分支：`merge/future-to-master-20261027`
- 合并提交：`2cc5ba92`（双父：`0eb56cef`(master) + `8c0d174f`(future)）
- 执行：AI 协作合并流程（日志专家记录）

---

## 1. 概述

本次为 **future 分支合入 master 分支的首次 unrelated-histories 合并**。两条分支历史上无共同祖先，属于仓库重构后两条独立演化线的重新汇合：

| 项目 | master | future |
| --- | --- | --- |
| 版本号 | 1.8.9 | 1.8.15+10815 |
| 提交数 | 145 | 350 |

- future 是当前活跃开发线，本次合并以 future 内容为主体，master 独有内容选择性保留。
- 合并结果以合并提交 `2cc5ba92` 落在合并分支 `merge/future-to-master-20261027` 上，验证通过后再快进推送 `origin/master`。

## 2. 合并策略

采用 **future-first** 策略：

- 冲突默认取 future 侧（活跃开发线的最新实现）。
- master 独有内容必须保留，主要包括：
  - `.github/workflows/fork-sync.yaml`
  - `.github/workflows/publish_app_arb8.yaml`
  - `simple_live_console/` 目录
  - 及其他 master 侧独立维护的文件（合计相对 future 差异 88 个文件、+8358 行、0 删除，即 master 独有内容全部保留）。
- 子模块落位：`simple_live_core`(`0b8360c2`) 与 `simple_live_tv_app`(`263a19e6`) 以 160000 gitlink 形式落位，并附带 `.gitmodules` 注册。

## 3. 冲突统计

- **预演**：177 个冲突文件，其中 162 个位于 `simple_live_app`。完整清单见 [2026-10-27-future-to-master-conflicts.txt](./2026-10-27-future-to-master-conflicts.txt)（每行一个路径，末两行 `simple_live_core~future`、`simple_live_tv_app~future` 为 file/directory 冲突标记）。
- **实际合并**：175 个 add/add 冲突 + 2 个 file/directory 冲突（`simple_live_core`、`simple_live_tv_app`，目录与子模块 gitlink 冲突）。
- **解决方式**：
  - 172 个文件取 future 侧；
  - 3 个 `.gitignore` 人工并集处理——根目录与 `simple_live_app/.gitignore` 为 future 严格超集（直接取 future）；`simple_live_app/android/.gitignore` 手工保留 master 独有的 `/app/build/` 条目。

## 4. 合并规模

相对 master 基线：

- 变更文件：628 个
- 行数：+64,955 / −46,829

按目录分布（`git diff 0eb56cef 2cc5ba92 --numstat` 实测）：

| 目录 | 文件数 |
| --- | --- |
| simple_live_app | 312 |
| simple_live_tv_app | 141 |
| simple_live_core | 94（93 个文件 + 1 个 gitlink） |
| docs | 56 |
| .github | 7 |

`simple_live_console/` 在 master 与合并结果间零差异（master 独有且原样保留，不体现在本 diff 中）。

相对 future 的差异为 88 个文件、+8,358 行、0 删除，即 master 独有内容完整保留，未丢失任何 master 侧文件。构成：simple_live_app 74（账号服务、弹幕屏蔽 Rust 集成等）、simple_live_console 10、workflows 2（fork-sync、publish_app_arb8）、assets 1、flatpak 1。

## 5. 验证记录

- **双父结构**：合并提交 `2cc5ba92` 确认为双父（`0eb56cef` + `8c0d174f`），符合 unrelated-histories 合并预期。
- **Workflows 完整性**：`.github/workflows/` 共 9 个文件齐全（future 侧 7 个 + master 侧 2 个），无内容差异。
- **子模块**：gitlink 哈希与 future 侧一致（`simple_live_core`=`0b8360c2`，`simple_live_tv_app`=`263a19e6`）；已通过 `git ls-remote` 验证两个子模块仓库的 HEAD/future 引用指向对应提交，远端引用有效。
- **版本号**：合并后为 `1.8.15+10815`，与 future 一致。
- **.gitignore**：3 个 .gitignore 并集结果核验通过（见第 3 节）。
- **推送安全性**：future 侧发布工作流不监听 master 分支；`fork-sync.yaml` 为定时任务且仅操作 dev 分支，合并推送 master 不会误触发发布或同步工作流。

## 6. 审查结论

审查工具：ocr（open-code-review v1.13.3），`--from future --to merge/future-to-master-20261027`。因 LLM 429 限流进行了两轮部分覆盖审查（第一轮 58 条、45/73 文件组失败；第二轮 24 条、59/73 失败），由主编审合并去重后形成统一结论。

**总体定性**：所有发现均集中于 master 独有保留内容，未发现 future 侧代码问题，**无合并引入的回归**；均为 master 既有内容的预存问题（部分为 future 演进导致的语义过时）。future 侧 0 删除、0 修改，master 独有内容完整保留。

### Critical

无。

### High（9 条）

安全（master 既有 CI 配置，合并后随保留内容进入 master 树）：

- `.github/workflows/publish_app_arb8.yaml:16`：job 只需读权限却授予 `write-all`，配合未钉 SHA 的第三方 action（timheuer/base64-to-file@v1.2、subosito/flutter-action@v2），一旦 action 被投毒可直接接管仓库。建议收敛为 `contents: read` 并钉 commit SHA。
- 同文件 `:27`：签名密钥经第三方 action 落盘且只钉可变 tag `v1.2`，存在签名密钥泄漏面。

功能（master 遗留代码与 future 演进的语义层不兼容/真实 bug，合并前在 master 上已存在）：

- `simple_live_console/bin/simple_live_console.dart`：console 依赖旧 core API（`BiliBiliSite` 等）且 SDK 约束 `>=2.19.1 <3.0.0`，future 侧 core 子模块已改名 `RustBilibiliSite` 且要求 `>=3.0.5 <4.0.0`，console 在合并后的树上无法编译。
- `simple_live_app/lib/services/bilibili_account_service.dart:58`：对 `Sites.allSites` 注入的 `RustBilibiliSite` 强转为 Dart `BiliBiliSite`，必抛运行时错误；服务未注册、账号真源已迁 `DBService`+`PlatformService`，建议删除或迁移。
- `simple_live_app/lib/services/douyin_account_service.dart:14`：同样强转 `RustDouyinSite` 抛异常，无调用方，建议删除。
- `simple_live_app/rust/Cargo.toml:10`：`simple_live_app/rust` 为 FRB 2.11.1 时代残留 crate，与运行库 2.13.0 不一致，`RustLib.init(forceSameCodegenVersion)` 会抛错，且与 simple_live_core 的桥 crate 同名会互相覆盖；建议删除该目录及 `lib/src/rust`、`flutter_rust_bridge.yaml` 配套残留。
- `simple_live_app/lib/src/rust/frb_generated.dart:70`：app 内副本生成物 codegen 2.11.1 vs 运行库 2.13.0，init 即抛异常，且 core 侧已有同版本绑定，属迁移后遗留。
- `simple_live_app/lib/src/rust/api/danmaku_mask.dart:22`：生成的绑定与调用方不一致（缺 `mergeListBatch`、`adaptiveWindow` 必填参数不匹配、controller 未 import），直接编译失败；正确实现在 simple_live_core 侧。
- `simple_live_app/lib/modules/live_room/danmu/danmaku_mask.dart:48`：`_lastShiftMs` 初值 0 未做首次对齐，epoch 毫秒输入下 while 循环约十亿次，isolate 卡死；Rust 侧有保护，Dart 侧缺失（该纯 Dart 实现当前未被调用，属第三份实现）。

### Medium（26 条，择要）

- `qr_login_page.dart:36`：`QRStatus.expired` 分支误写为 `failed`，二维码过期后无刷新入口，登录流程中断（两处）。
- `qr_login_controller.dart:88`：B 站登录 Cookie 明文写日志，凭据泄露，应删除或脱敏。
- `bilibili_account_service.dart:63`：登录态只写旧 KV 不写 DB Account，登出不清 credential，出现两套登录态与"登出后自动登录"。
- `deleteAllCookies` 清整个 WebView cookie 库，登出 B 站连带清掉抖音会话，跨账号副作用。
- `danmaku_mask.dart`/rust `danmaku_mask.rs`：频控分支不可达（maxFrequency 恒等于 1，设置项无效）；除零/死循环未完全防护；isolate 失败路径缺失致永久挂起。
- `.github/workflows/fork-sync.yaml`：GITHUB_TOKEN 推送不触发下游构建工作流（若期望"同步即构建"需 PAT）；rebase+force-with-lease 无并发控制。
- `.github/workflows/publish_app_arb8.yaml`：缺 `submodules: recursive`、缺 Firebase 配置注入、无 timeout、upload-artifact 未设 `if-no-files-found: error`。
- `rust_builder/android/AndroidManifest.xml`：package 属性与 AGP 9 冲突，include 即编译失败；build.gradle 硬编码 AGP 7.3.0/compileSdk 33 与宿主(9.0.1/37)脱节。
- `assets/update-linux-metainfo.dart`：正则依赖固定缩进、失败静默；无幂等去重；version 未 XML 转义；与 `scripts/update_version.dart` 功能重叠且行为相反，会互相覆盖。
- 旧包名 metainfo 副本（`io.github.SlotSun.dart_simple_live.metainfo.xml` + `.desktop`）：无任何构建引用，release 停在 1.8.4，screenshot/license 不合规，建议删除。
- `lib/app/utils/{archive,document,duration_2_str_utils,string_normalizer}.dart`：`extensions/` 下已有同名实现的过期副本，无引用死代码，建议删除。

### Low（11 条）

死代码（`_editDistance`、lazy_static 冗余依赖、BOM/行尾）、SPDX 标识弃用（GPL-3.0）、toJson/fromJson 字段不对称（id_str）、扫码轮询 Toast 刷屏、截图 URL 停在 v1.7.18 等，明细见 [2026-10-27-review-synthesis.md](./2026-10-27-review-synthesis.md)（主编审合并稿）与 [2026-10-27-ocr-review-report.txt](./2026-10-27-ocr-review-report.txt)（工具原始输出）。

### 覆盖缺口

两轮共 45+59 个文件组因 HTTP 429 限流失败（主要是 rust_builder/cargokit、rust 残留目录的多数文件组），本次审查为部分覆盖，cargokit 构建工具链未审。合并放行不依赖缺口部分：缺口均为 master 既有第三方工具代码。

## 7. 后续

1. 本合并分支 `merge/future-to-master-20261027` 验证通过后，快进推送至 `origin/master`。
2. 本次为持续合并流程的第一次合并；后续 future 分支的新提交将按同样流程（预演 → 合并 → 验证 → 审查 → 记录日志）定期合入 master。
3. **审查问题处置清单**（均为 master 既有预存问题，非合并引入，建议单独开 issue/分支处置）：
   - 删除 rust 残留：`simple_live_app/rust/`、`simple_live_app/lib/src/rust/` 及 `flutter_rust_bridge.yaml` 配套残留；
   - 删除账号服务或迁移 `PlatformService`：`bilibili_account_service.dart`、`douyin_account_service.dart`（强转 Rust 站点类必抛异常，账号真源已迁 DBService+PlatformService）；
   - 修复 arb8 workflow 权限：`write-all` → `contents: read`，第三方 action 钉 commit SHA，并处理签名密钥落盘问题；
   - 修复 `danmaku_mask`：Dart 侧 `_lastShiftMs` 首次对齐、修复生成绑定与调用方不一致（正确实现以 simple_live_core 侧为准）；
   - 删除 `utils` 死代码副本与旧包名 metainfo 副本；
   - `simple_live_console` 适配或移除：升级 SDK 约束至 `>=3.0.5` 并迁移站点类调用到 rust bridge 新 API，或从合并后的树上移除/归档到独立分支。
