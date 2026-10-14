# simple_live_tv_app 修改历史（Git 复现版）

> 版本锚点：`simple_live_tv_app` v1.5.1+10501 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/update-history.md)
> 说明：2026-10-12 的上游同步（merge `abca65f8`，dev v1.8.15）**没有**触及 TV（`git show abca65f8 --stat -- simple_live_tv_app` 输出为空）；2026-10-14 的同步（merge `5ae375f1`）**是 TV 端自建分支以来第一次成规模改动**，本文已按该提交重写锚点后的内容。

## 1. 数据源与复现方法

本文全部结论可由仓库自身复现：

```bash
# ① future 分支：TV 端相关提交（现 5 条；合并提交被路径简化过滤掉，不会出现在结果里）
git log --date=short --pretty=format:"%h|%ad|%an|%s" future -- simple_live_tv_app

# ② 全部 refs（含历史重写前的旧线）：TV 端相关提交（240 条，含重写重复）
git log --all --date=short --pretty=format:"%h|%ad|%an|%s" -- simple_live_tv_app | wc -l

# ③ 单条提交的改动面
git show --stat <hash> -- simple_live_tv_app

# ④ 追某文件的历史
git log --oneline future -- simple_live_tv_app/pubspec.yaml

# ⑤ 重写前/后等价提交互查（多数 subject 在旧线存在两份 hash）
git log --all --grep="<提交信息关键词>" --oneline

# ⑥ 本次同步给 TV 带来的净改动（22 文件、+566/-457）
git diff --stat 8fd14a9f..HEAD -- simple_live_tv_app

# ⑦ fork 的 future 线在本次合并前是否自研改过 TV（应为空 → 合并无冲突，上游 TV 改动整体落入）
git diff --name-only 70b1d18f..8fd14a9f -- simple_live_tv_app
```

**两个必须知道的前提**：

1. **本仓库历史经过重写**。`future` 分支的根提交是 `543910ba`（2026-07-30，全树导入型，`git rev-list --max-parents=0 future` 可验证），因此 `future` 上 TV 端只看到 **5 条**提交；而全 refs 中 TV 端相关提交 **240 条**（大量是重写前后「同 subject 两份 hash」的重复）。重写前的旧线保存在 `backup-future-20260925`、`backup-future-20261009`、`future-rewrite`、`origin/future` 等分支，可回溯到 2023-09（TV 项目起点）。
2. **`master` 是单提交的孤儿分支**（`0eb56cef`，2026-08-31，fork-sync CI），因含全树快照而出现在 `--all` 路径日志里，不承载 TV 真实历史。

作者口径：`SlotSun` = 上游 dart_simple_live 提交身份；`xiaoyaocz` = 上游项目作者；`gaoxing64` = 本 fork；另有 `pugaizai`、`bgylde`、`Slot`、`Zhang, Tianrong` 等社区贡献者。**fork 侧（gaoxing64）无一条改动 TV 业务代码的提交**——`0eb56cef` 仅新增 CI 工作流。

## 2. 权威时间线（future 分支，5 条）

| # | hash | 日期 | 作者 | 类型 | 摘要 | 影响面 |
| --- | --- | --- | --- | --- | --- | --- |
| 5 | `bafc703b` | 2026-10-14 | SlotSun | ci | prebuild tv_app v1.5.1 with flutter v3.35.7 after | TV 端仅 `pubspec.lock`（+13/-13）；工作流与版本文件见 §2.4 |
| 4 | `6da36e04` | 2026-10-13 | SlotSun | feat(tv) | 支持斗鱼扫码登录 | 22 文件、+575/-466：账号体系整体替换（见 §2.3） |
| 3 | `543910ba` | 2026-07-30 | SlotSun | root | 全树导入（subject 为 `feat(follow): add follow_user.last_watch_time`） | 140 文件、+13413 行（TV 端整棵树一次落地） |
| 2 | `062d5a83` | 2026-10-03 | SlotSun | refactor | 调整项目结构 | 2 文件、4+/4-：跟随 core 接口改名 |
| 1 | `b0d408e6` | 2026-10-03 | SlotSun | refactor | gen application settings by utils | `analysis_options.yaml` 加 analyzer.exclude；windows 插件注册表同步 |

> 顺序按新→旧排列。**合并提交 `5ae375f1` 不在这 5 条里**：`git log --oneline HEAD -- simple_live_tv_app` 会做历史简化，两侧内容合并后与第二父提交一致的合并不会被打出来（`git log --oneline --merges HEAD -- simple_live_tv_app` 输出为空）；本次同步对 TV 的净改动用 `git diff --stat 8fd14a9f..HEAD -- simple_live_tv_app` 看。
> fork 侧自研提交（`70b1d18f..8fd14a9f`，即多开/关注/OSD 那一整批）**没有一条动过 `simple_live_tv_app`**，故 `6da36e04` 的上游 TV 改动是无冲突整体落入。

### 2.1 `062d5a83` refactor: 调整项目结构（2026-10-03）

- 对照 core v1.1.0 的接口改名（core 知识库 §3.1），同步两处拼写：
  - `modules/category/category_controller.dart:26`：`getCategores()` → `getCategories()`；
  - `modules/live_room/live_room_controller.dart`：本地方法 `getPlayQualites()` → `getPlayQualities()`，并改 `site.liveSite.getPlayQualites(...)` → `getPlayQualities(...)`（现版本位于 `:171`、`:176`）。
- 影响：只是编译期同步上游改名，无行为变化。

### 2.2 `b0d408e6` refactor: gen application settings by utils（2026-10-03）

- `simple_live_tv_app/analysis_options.yaml:10-13`：新增 `analyzer.exclude`（`build/**`、`android/**`、`windows/**`），把生成的平台目录移出静态分析。
- `windows/flutter/generated_plugin_registrant.cc`（-3 行）、`generated_plugins.cmake`（-1 行）：同步 Windows 端插件注册表（随依赖变更自动生成）。
- 影响：仅工程配置/生成物，不涉及 TV 运行时逻辑。

### 2.3 `6da36e04` feat(tv): 支持斗鱼扫码登录（2026-10-13，SlotSun）

复现：`git show --stat 6da36e04 -- simple_live_tv_app`（22 文件、+575/-466）。实质是**把 app 端已完成的「账号 = Hive 记录 + core 站点契约」体系整体搬到 TV**，顺带把斗鱼从「无需登录」升级成可扫码。

- **删除**：`services/bilibili_account_service.dart`（-76，原把 cookie 写进 LocalStorage 的 `BilibiliCookie` 键）、`modules/account/bilibili/qr_login_controller.dart`（-111）、`.../qr_login_page.dart`（-139）。
- **新增通用扫码页**：`modules/account/qr_login/qr_login_controller.dart`（+78）与 `qr_login_page.dart`（+84）。控制器不再写死站点，站点由传入 `Account.siteId` 决定（`qr_login_controller.dart:17`），轮询成功后把 JSON 凭证交给 `PlatformService.accountLogin`（`:61-66`）；页面标题/提示按 `controller.site.name` 拼接（`qr_login_page.dart:16,76`）。
- **新增 TV 侧账号模型**：`models/db/account.dart`（+109，Hive `typeId: 3`，持久化字段 id/siteId/credential/createdAt/updatedAt，`userName/avatar/uid/isActive` 不进 `fromJson`，`:49-57`）+ 生成物 `account.g.dart`（+50）。
- **新增服务**：`services/platform_service.dart`（+67，`RxList<Account>` + `initAccount/accountLogin/updateAccount/accountLogout`，启动时逐账号请求 `getAccountInfo`）、`services/migration_service.dart`（+44，按 `kHiveDbVer` 给 bilibili/douyu 补两条空账号 `id='0'/'1'`，`:19-40`）。
- **DB**：`services/db_service.dart`（+11）新增 `accountBox = Hive.openBox("account")`（`:17`）与 `addAccount/getAllAccounts`（`:20-26`）。
- **启动**：`main.dart`（+10/-2）注册 `AccountAdapter`（`:72`）、跑 `MigrationService`（`:83`）、`Get.put(PlatformService())`（`:89`），并移除 `Get.put(BiliBiliAccountService())`（原 `8fd14a9f:77`）。
- **路由**：`app_pages.dart`（+6/-6）把 `BiliBiliQRLoginPage` 换成 `QRLoginPage`；`route_path.dart`（+2）新增 `kAccountQRLogin = "/qr_login/qr_login"`（`:31`）；`app_navigation.dart`（+6/-19）**同时删掉了进 B 站房间前的登录拦截**（原 `toLiveRoomDetail` 里的 `bilibiliLoginTip` 分支），新增 `toQRCoreLogin({required Account account})`（`:19-21`）。
- **设置页**：`settings_controller.dart`（+6/-11）删 `bilibiliTap()`、加 `accountTap(Account)`（`:64-66`）与 `douyuFocusNode`（`:56`）；`settings_page.dart`（+61/-58）的账号 Tab 改为遍历 `PlatformService.instance.accountList`（`:422-451`），斗鱼项从「无需登录」变成可扫码，虎牙/抖音仍是「无需登录」硬编码项（`:452-478`）。
- **同步**：`sync_service.dart` 与 `sync_controller.dart`（各 +8/-8）把账号同步从「取 `jsonBody['cookie']`」改成整包 `Account.fromJson`（`sync_service.dart:299`、`sync_controller.dart:167`），HTTP 端点由 `/sync/account/bilibili` 改名为 `/sync/account/account`（`sync_service.dart:152`）；改名后与手机端发送地址一致（`simple_live_app/lib/requests/sync_client_request.dart:99`，本次合并前 TV 无该端点）。
- **依赖/版本**：`pubspec.yaml`（+2/-2）——`pubspec.yaml:4` 版本 `1.5.0+10500 → 1.5.1+10501`、`pubspec.yaml:39` `canvas_danmaku ^0.2.7 → ^0.3.3`；`pubspec.lock`（+15/-24）随之变动（`flutter_qjs` 传递依赖消失、`meta` 1.17.0→1.16.0）。弹幕库升级带来的适配：`player_controls.dart:224`、`:535` 去掉两处 `.toInt()`（0.3.3 的 `DanmakuOption.duration` 已是 `double`）。
- 另新增 `lib/app/common/asT.dart`（+6），当前 TV 代码内无任何 import（见 backlog P2-7）。

### 2.4 `bafc703b` ci: prebuild tv_app v1.5.1 with flutter v3.35.7（2026-10-14，SlotSun）

复现：`git show --stat bafc703b`（3 文件、+83/-16）。提交正文原文：`because vs of my pc is v2026, cant dev tv_app with flutter v3.35.7, need check prebuild in github action`。

- **新增** `.github/workflows/Prebuild_tv_app_dev.yaml`（+67）：workflow 名 `app-tv_prebuild-dev`（`:1`），触发条件是 `workflow_dispatch` + push 到 **`dev` 分支且 `simple_live_tv_app/**` 有变更**（`:3-9`），并发组 `cancel-in-progress`（`:11-13`）；`checkout` 显式 `ref: dev`（`:21-23`），Flutter 版本用 `flutter-version-file: simple_live_tv_app/pubspec.yaml` 读取（`:51-54`，即 pubspec `environment.flutter: 3.35.7`，`:8`，而非 `.fvmrc`），只跑 `flutter pub get` + `flutter build apk --release --split-per-abi`（`:60-67`），**不产出 release/发布物**。
- `assets/tv_app_version.json`（+3/-3）：`1.5.0/10500/- 永远的1.5.0` → `1.5.1/10501/- 永远的1.5.1`。这是 TV「检查更新」读取的远端清单（`requests/common_request.dart:19,33` 指向上游仓库 master 分支的该文件）。
- `simple_live_tv_app/pubspec.lock`（+13/-13）：同一依赖解析的继续收敛。TV 包内其他文件未动。

### 2.5 2026-10-14 的这次同步（merge `5ae375f1`）

`5ae375f1`（gaoxing64，2026-10-14）双亲 `8fd14a9f` + `f8318694`，把上游 `origin/dev` 在 v1.8.15 之后的 5 条提交并入。对 TV 而言：

```bash
git log --oneline 8fd14a9f..f8318694                     # 5 条：57d8f86d / 03c4493a / 6da36e04 / bafc703b / f8318694
git diff --stat 8fd14a9f..HEAD -- simple_live_tv_app     # 22 文件、+566/-457
git diff --name-only 70b1d18f..8fd14a9f -- simple_live_tv_app   # 空：fork 自研线从未改过 TV
```

- 全部 TV 净改动来自 §2.3/§2.4 两条上游提交；`git diff --name-only 8fd14a9f..HEAD -- simple_live_tv_app` 仍只列 22 个文件（与 `6da36e04` 的文件集合相同）。净行数差 9 行（+575/-466 → +566/-457）**只来自 `pubspec.lock`**：两条提交各自的锁改动相互重叠（`+15/-24` 与 `+13/-13` → 合并后净变动 `+6/-15`），其余 21 个文件的 numstat 两边完全一致（`git diff --numstat 8fd14a9f..HEAD -- simple_live_tv_app` 对 `git show 6da36e04 --numstat` 可逐行核对）。
- 同批并入但**不改 TV 文件**的 3 条：`57d8f86d`（fix(bili): 迁移到 Account cookie 不生效 #197，改 `simple_live_app/lib/services/platform_service.dart` + `simple_live_core/.../bilibili_site.dart`）、`03c4493a`（fix(bili): 补充弹幕 cookie 需要配对的 uid，只改 core）、`f8318694`（crowdin.yml +1 行）。三条的 `git show <hash> --name-only -- simple_live_tv_app` 均为空。
- 但前两条通过 path 依赖**直接影响 TV 的账号/弹幕路径**（`pubspec.yaml:13-14`）：`57d8f86d` 把 core 的 `BiliBiliSite.setSiteAttrs` 从「整串当 cookie」改成 `jsonDecode` 后取 `cookie`（`bilibili_site.dart:553-558`），这正好是 TV 存的 JSON 凭证所需要的（`platform_service.dart:55` 传的就是 `Account.credential`）；`03c4493a` 在 `getAccountInfo` 里补 `userId = info.mid!`（`bilibili_site.dart:622`），而 TV 启动/登录时正走这个方法（`platform_service.dart:45`），弹幕参数 `BiliBiliDanmakuArgs.uid` 取的即该字段（`bilibili_site.dart:252`）。两条的实际效果未在真机验证。
- 另外 `57d8f86d` 对 app 端 `accountLogout` 的修正（`siteId: ac.siteId` → `userName: ''`），在 TV 侧的对应实现里已经是修正后的写法（`platform_service.dart:33-39`）。

## 3. 上游演变（由 `git log --all` 归纳，2023-09 ~ 2026-08）

TV 端全部功能演进都在上游（`xiaoyaocz` / `SlotSun` / `pugaizai` / `bgylde`）。挑重要节点（给真实 hash，注意旧线常见同 subject 两份）：

| 日期 | hash（示例） | 节点 |
| --- | --- | --- |
| 2023-09-18 | `99f688a6` / `4939a07c` | 初始化 TV 项目（仓库内最早的 TV 记录） |
| 2024-03-07 ~ 03-08 | `fab65d50`、`15ce795c`、`dc831173` | TV 端初步开发 → 初步完成（首页/播放/使用流程） |
| 2024-03-13 | `3e574eeb` / `51d877fa` | TV 端双击返回；随附「直播卡片显示人气」「完善多端数据同步」 |
| 2024-05-29 | `a4d28518` / `c8d6fd84` | TV 增加 Banner 图标（#384）、点击播放器显示设置 |
| 2024-08-13 | `cea61275` / `caa29f2f` | TV 增加远程同步；`cf4de73f` TV 增加自动更新关注 |
| 2025-04-23 | `9e4cc128` / `ac203552` | TV 项目适配 AGP（其后 `58b01aa0` / `11cd69a8` 又 Revert） |
| 2025-08-06 | `49e62ed9` | 修复 TV 打包报错 |
| 2025-10-28 | `d095d236`、`eb4968b1`、`e7957204` | pugaizai：flatpak CI + 升 Flutter 3.35.7 → 随后 revert 回 3.27.4 |
| 2025-10-29 | `352de94d` | 更新 media_kit、弹幕改用 `canvas_danmaku` |
| 2025-11-27 | `e7928c38` | TV 修改 JS 引擎（配合上游去 `flutter_qjs`） |
| 2025-12-13 | `28bbdd97`、`0791454d`、`dfd9e793` | 完善 Android TV 构建，允许 fork 后手动构建/发版 |
| 2025-12-24 | `bd3339b9` | 支持用户修改主播备注 |
| 2026-01-10 | `a0a8bae1` | bump Flutter 3.38.6 |
| 2026-02-01 | `7f7fe65e` | fix(huya): room-search（感谢 GH4N） |
| 2026-08-27 | `3a577157` | Release Dev 1.11.5 / TV 1.6.6（版本 1.6.5+10605 → 1.6.6+10606，`.fvmrc` 3.38.3 → 3.47.1） |

## 4. 当前状态

- **分支**：`future` 领先 `dev` **185** 个提交（`git rev-list --left-right --count dev...future` → `0 185`）。
- **版本**：当前工作树 `pubspec.yaml:4` = `1.5.1+10501`；`environment.flutter` = `3.35.7`（`pubspec.yaml:8`，与 `.fvmrc` 一致）；`canvas_danmaku` 已升到 `^0.3.3`（`pubspec.yaml:39`）；`analysis_options.yaml` 用 `flutter_lints ^5.0.0`。
- **账号体系**：已从「B 站专属 cookie 服务」换成与手机端同构的 `Account` 模型——Hive 三个箱 `TVHostiry` / `TVFollowUser` / `account`（`db_service.dart:15-17`），`AccountAdapter` typeId 3（`models/db/account.dart:5`），全局状态在 `PlatformService.accountList`（`platform_service.dart:13`）。
- **与上游旧线的版本落差（待确认）**：上游旧线在 2026-08-27（`3a577157`）TV 端已是 `1.6.6+10606` / Flutter `3.47.1`；而 future 分支的 TV 端为 `1.5.1+10501` / `3.35.7`。二者并非同一条版本线，future 的 TV 快照看似**落后于上游同期**，具体对应关系需人工核对。注意 `future` 的 TV `pubspec.yaml` 已不再只有导入那一次改动：`git log --oneline future -- simple_live_tv_app/pubspec.yaml` → `6da36e04` + `543910ba` 两条。
- **最近一次 TV 变更（future 内）**：`6da36e04`（功能）与 `bafc703b`（仅 `pubspec.lock`），均经 merge `5ae375f1`（2026-10-14）落入。
- **CI**：仓库根新增 `.github/workflows/Prebuild_tv_app_dev.yaml`，但它只在 **push 到 `dev`** 且 `simple_live_tv_app/**` 变化时触发（`:3-9`，`checkout ref: dev`），fork 的 `future` 分支不会跑到它；TV 的发布线仍由 `publish_tv_app_release.yaml`（手动 dispatch）承载。
- 待跟进的悬置项见 [backlog.md](./backlog.md)；回归基线见 [test-suite.md](./test-suite.md)。