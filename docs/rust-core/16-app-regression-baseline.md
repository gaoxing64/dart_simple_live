# App 侧回归基线快照（AC-30 / DoD-4 比对基准）

> 采集：QA（严过关）｜日期：2026-10-16｜工作目录：`C:/Users/admin/WorkBuddy/Worktrees/dart_simple_live/core-rust`
> 目的：为 **AC-30「其余 4 平台 + App 零新增失败」/ DoD-4「回归为零」** 提供**实现者动 App 之前**的比对基准。
> 性质：**采集任务**——未修改任何测试、未动任何 `src/`（`test/` 与 `lib/` 零改动，见 §7）。
> 原始日志：`docs/rust-core/evidence-app-flutter-test.log`（2.0 MB）、`docs/rust-core/evidence-core-flutter-test.log`（0.87 MB）

---

## 1. 结论速览

| 项 | 结果 | 与既有记录 |
|----|------|-----------|
| **App 侧**（`simple_live_app`） | **564 执行 / 549 通过 / 15 失败** | ✅ 与 `simple_live_app/doc/test-suite.md §2/§7` **逐条一致** |
| 失败文件集合 | `search_initial_site`(9) + `theme_mode`(2) + `follow_grouped_view`(1) + `page_view_auto_load`(1) + `viewpager_drag`(1) + `widget_test`(1) | ✅ 与 §7 登记红灯**完全相同** |
| **Core 侧**（`simple_live_core`，含 5 平台联网冒烟） | **84 执行 / 80 通过 / 4 失败**（全部 huya 联网） | ⚠️ 文档记为 82/79/**3**；本次为 84/80/**4**，见 §6 |
| 基线可用性 | **可用**作 DoD-4 比对基准（App 侧精确复现；core 侧差异为网络数据依赖，已定性） | — |

**基线判定：App 侧 15 条红灯为「存量问题」，与本次 Rust Core 化迁移无关**（本次迁移尚未改任何 App 业务代码）。AC-30 的判定口径应为：**迁移后 App 侧失败名单与本文 §4 的 15 条逐条一致 = 零新增失败**。

---

## 2. 执行环境

| 项 | 值 | 说明 |
|----|----|------|
| App 侧 Flutter | **3.47.6**（`.fvmrc` 钉） | `fvm flutter --version` → Flutter 3.47.6 / Dart 3.13.5 |
| Core 侧 Flutter | **3.38.4**（`.fvmrc` 钉） | core 与 app 版本不同（既有约定） |
| fvm | 4.3.1（scoop 安装） | 缓存：`C:\Users\admin\scoop\persist\fvm\versions\{3.38.4,3.47.6}` 均已安装 |
| 依赖解析 | `fvm flutter pub get` 已执行（两目录） | 新鲜 worktree，`.dart_tool` 原本缺失 |

### ⚠️ 关键环境坑：`HTTP_PROXY` 导致 `flutter_tester` 无法连接（必读）

- **现象**：`fvm flutter test --no-pub` 首次运行，**全部 55 个测试文件无法加载**，均为
  `Failed to load ...: Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`（`+0 -55`）。这**不是测试失败**，是测试运行器起不来。
- **根因**：本机环境变量 `HTTP_PROXY` / `HTTPS_PROXY` / `http_proxy` / `https_proxy` **全部指向 `http://127.0.0.1:50736`**（本地代理）。Dart 测试运行器遵循该代理，把与 `flutter_tester` 子进程的 **loopback WebSocket** 连接也走代理，代理拒绝升级请求 → 连接失败。
  （**与沙箱无关**：关闭沙箱重试同样失败；禁用代理后立即成功。）
- **修复（命令级，不需改工程）**：运行测试时**清空代理并放行 loopback**：

  ```bash
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
      NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1" \
      fvm flutter test --no-pub
  ```

- **验证**：单文件 `test/duration_2_str_utils_test.dart` 在加上上述环境后 **6/6 通过**；随后全量跑通。
- **给后续实现者/CI**：**任何人跑 `flutter test` 前都必须做此代理隔离**，否则会误判为「测试全挂」。（另一已知坑：若报 `Can't load Kernel binary: Invalid SDK hash`，删 `.dart_tool/hooks_runner/` 重跑，但本机未触发。）

---

## 3. 执行命令（真实）

```bash
# ---- App 侧 ----
cd simple_live_app
fvm flutter pub get                                  # 首次：解析依赖（rc=0）
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1" \
    fvm flutter test --no-pub  > ../docs/rust-core/evidence-app-flutter-test.log 2>&1; echo rc=$?

# ---- Core 侧（参照，含联网冒烟）----
cd ../simple_live_core
fvm flutter pub get                                  # 首次：rc=0（Changed 4 dependencies）
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1" \
    fvm flutter test --no-pub  > ../docs/rust-core/evidence-core-flutter-test.log 2>&1; echo rc=$?
```

### 静态清单（独立复核，非采信文档）

| 项 | 实测 | `test-suite.md` 记录 | 一致 |
|----|------|----------------------|------|
| `test/*.dart` 文件数 | **56** | 56 | ✅ |
| 其中含用例文件（排除 `follow_test_harness.dart`） | **55** | 55 | ✅ |
| 静态 `test(`/`testWidgets(` 声明数 | **538** | 538 | ✅ |
| `integration_test/*.dart` | **1** | 1 | ✅ |

---

## 4. App 侧失败清单（15 条，逐条）

> 来源：`evidence-app-flutter-test.log`（`fvm flutter test --no-pub`，Flutter 3.47.6）。
> 「一行原因」取自日志中失败点的报错首行。

| # | 文件 | 用例名 | 一行原因 |
|---|------|--------|----------|
| 1 | `search_initial_site_test.dart` | 首页 tab -> 平台 id 的映射 取到的就是该下标的平台 | `MissingPluginException(getApplicationSupportDirectory)` |
| 2 | `search_initial_site_test.dart` | 首页 tab -> 平台 id 的映射 虎牙的下标不是 0（否则下面的用例会假通过） | `MissingPluginException(getApplicationSupportDirectory)` |
| 3 | `search_initial_site_test.dart` | 首页 tab -> 平台 id 的映射 下标越界时返回 null，交给搜索页回落到第一个 | `MissingPluginException(getApplicationSupportDirectory)` |
| 4 | `search_initial_site_test.dart` | 搜索页的初始平台 没带平台时停在第一个 | `MissingPluginException(getApplicationSupportDirectory)` |
| 5 | `search_initial_site_test.dart` | 搜索页的初始平台 带了平台 id 时，index 与 tabController 一起对齐 | `MissingPluginException(getApplicationSupportDirectory)` |
| 6 | `search_initial_site_test.dart` | 搜索页的初始平台 带了已不存在的平台 id 时回落到第一个 | `MissingPluginException(getApplicationSupportDirectory)` |
| 7 | `search_initial_site_test.dart` | 端到端：首页在虎牙时点搜索 搜索页默认停在虎牙 | `MissingPluginException(getApplicationSupportDirectory)` |
| 8 | `search_initial_site_test.dart` | 端到端：首页在虎牙时点搜索 首页在抖音时点搜索，搜索页默认停在抖音 | `MissingPluginException(getApplicationSupportDirectory)` |
| 9 | `search_initial_site_test.dart` | 端到端：首页在虎牙时点搜索 关掉搜索后再打开，仍然重新跟随首页 | `MissingPluginException(getApplicationSupportDirectory)` |
| 10 | `theme_mode_test.dart` | theme mode 索引 setThemeMode 归一化后落盘 | `MissingPluginException(getApplicationSupportDirectory)` |
| 11 | `theme_mode_test.dart` | theme mode 索引 onInit 读到越界值时回退到跟随系统 | `MissingPluginException(getApplicationSupportDirectory)` |
| 12 | `follow_grouped_view_test.dart` | tab 变视图切换：直播中=卡片网格，未开播=紧凑行 | `Test failed.`（控件/几何断言，见日志 L829） |
| 13 | `page_view_auto_load_test.dart` | 鼠标滚轮滚到底部自动加载 | `Test failed.`（真 `IndexedPage` 几何/环境相关，见日志 L14970） |
| 14 | `viewpager_drag_test.dart` | 关注页：鼠标左键横拖切换视图 Tab（全部→直播中） | `Test failed.`（横拖切页几何/环境相关，见日志 L8515） |
| 15 | `widget_test.dart` | Counter increments smoke test | `Test failed.`（脚手架残留，**历来失败**，与业务无关，见日志 L6858） |

**按文件汇总**：`search_initial_site_test.dart` **9** ｜ `theme_mode_test.dart` **2** ｜ `follow_grouped_view_test.dart` **1** ｜ `page_view_auto_load_test.dart` **1** ｜ `viewpager_drag_test.dart` **1** ｜ `widget_test.dart` **1** = **15**。

**根因归类**：
- **11 条**（#1–#11，search_initial_site + theme_mode）：`MissingPluginException` —— widget test 无 `path_provider` 宿主，`AppSettingsController.onInit → getApplicationSupportDirectory()` 抛异常。与 `test-suite.md §7` 记载的根因**完全一致**。
- **4 条**（#12–#15）：控件/几何/环境相关断言 + 脚手架残留 smoke，与 §7「几何依赖真控制器/环境扰动」一致。

---

## 5. 与 `test-suite.md` 记录的差异

| 维度 | `test-suite.md`（§2/§7） | 本次实测 | 差异 |
|------|--------------------------|----------|------|
| App 执行/通过/失败 | 564 / 549 / 15 | **564 / 549 / 15** | **无差异（精确复现）** |
| 失败文件集合 | search_initial_site, theme_mode, follow_grouped_view, page_view_auto_load, viewpager_drag, widget_test | 同左 | **无差异** |
| 各文件失败数 | 9 / 2 / 1 / 1 / 1 / 1 | 同左 | **无差异** |
| 静态声明/文件数 | 538 / 55(+1 harness) | 538 / 55(+1 harness) | **无差异** |

> ✅ **App 侧基线完全复现，可与迁移后结果逐条比对。**

---

## 6. Core 侧（参照）与差异说明

Core 侧（`simple_live_core`，Flutter 3.38.4）含 5 平台**联网冒烟**，本次结果：

| 项 | 本次实测 | `simple_live_core/doc/test-suite.md §2` 记录 | 差异 |
|----|----------|---------------------------------------------|------|
| 执行 / 通过 / 失败 | **84 / 80 / 4** | 82 / 79 / 3 | +2 执行、+1 通过、+1 失败 |
| 失败集合 | 全在 `simple_live_core_test.dart` 的 `huya tests`：`getPlayQuality` / `getPlayUrls` / `getDanmaku` / `getDanmaku - huya` | 3 条 huya 联网用例（房间未开播） | 同性质，多 1 条 |

**4 条失败的一行原因**（均为 huya 联网、数据依赖，非逻辑回归）：

| 用例 | 一行原因 |
|------|----------|
| `huya tests getPlayQuality` | `type 'Null' is not a subtype of type 'HuyaUrlDataModel' in type cast`（房间未开播 → playurl 为 null） |
| `huya tests getPlayUrls` | `Bad state: No element`（取流列表为空） |
| `huya tests getDanmaku` | `Expected: a value greater than <0>`（30s 窗口内 0 条弹幕） |
| `huya tests getDanmaku - huya` | 同上 |

**差异定性（如实标注，不外推）**：
- 4 条**全部是 huya 联网冒烟**，与文档记载的「房间未开播」口径**同质**；差异来自**运行时刻的真实网络/房间状态**（固定 huya 房间是否在播、弹幕窗口是否有消息），属 `test-suite.md` 自述的「联网用例 flaky、只作协议存活探针」范畴。
- **执行条数 +2**：联网冒烟中有依赖真实响应的循环/子用例，其展开条数随网络数据浮动（`simple_live_core_test.dart` 为联网用例）。
- **结论**：core 侧**离线子集**（表情包 31 + douyin/douyu 离线约 43 条）稳定，**联网子集**随环境浮动。DoD-4 比对时，**core 侧以「离线子集零新增失败 + 联网子集失败同质」为口径**，不建议对联网子集做精确条数比对。
- ⚠️ 本文**不**声称 core 侧与文档「不一致 = 缺陷」；这是**网络数据依赖**，不是回归。

---

## 7. 纪律与副作用声明（如实）

- ✅ **未修改任何测试**：`test/` 零改动（`git status -- 'simple_live_app/test' 'simple_live_core/test'` 为空）。
- ✅ **未修改任何 `src/`/`lib/`**：`lib/` 下的改动均属**架构师并行 FRB spike**（`lib/src/rust/**`、`rust/Cargo.*`、`rust/src/**`），非本次采集产出。
- ⚠️ **`flutter pub get` 的工具副作用（已还原）**：
  1. `simple_live_app` 的 5 个平台注册文件（`{linux,windows}/flutter/generated_plugin_*`、`macos/Flutter/GeneratedPluginRegistrant.swift`）被 `pub get` 重新生成为「含 `media_kit_libs_windows_video`」版本 —— 说明**仓库内提交的这几个文件相对 `pubspec.yaml/lock` 已过期**（任何 `pub get` 都会改）。**QA 已 `git checkout` 还原**，以保持实现者 diff 干净。
     > 提示：这几个文件**不属于任何实现改动**；若实现者在自己的 `pub get` 后看到它们变更，属既有仓库状态，非本次迁移引入。
  2. `simple_live_core/pubspec.lock` 被 core 的 `pub get` 改动（`Changed 4 dependencies`）。**已还原**。这同样说明 **core 提交的 lock 相对 pubspec 约束已落后**；建议由 team-lead 决定是否单独一轮更新（不由本采集任务顺手改）。
- ✅ **未使用 `#[ignore]`/`skip`/放宽阈值**：本任务只采集，未触碰任何断言。
- ✅ 采集期间 worktree 有**架构师并行改动**（`git status` 是移动靶），故本报告以「命令 + 原始日志」为准，`git status` 快照仅供参考。

---

## 8. 基线可用性结论（给 AC-30 / DoD-4）

1. **App 侧基线可用**：**549 通过 / 15 失败**，15 条红灯名单见 §4；迁移后 App 侧 `flutter test` 的**失败名单必须与 §4 逐条一致**（零新增失败）方可判 AC-30 通过。
2. **比对方法**：迁移后重跑（**务必带 §2 的代理隔离**），提取「失败文件 + 用例名」集合与 §4 做**集合相等**比较；集合差值即新增/消除的失败。
3. **core 侧口径**：以「离线子集零新增失败」为主；联网子集（huya 冒烟）只做**同质性**检查，不做精确条数比对。
4. **必须记录的前置**：本节快照即为**实现者动 App 之前**的基准，时间锚点 = `2026-10-16`（`feat/core-rust` worktree，App 侧迁移前）。

---

## 9. 变更记录

| 日期 | 变更 |
|------|------|
| 2026-10-16 | 初始版本：App 侧 549/15 精确复现 + core 侧 80/4（huya）参照 + 代理环境坑与修复 |
