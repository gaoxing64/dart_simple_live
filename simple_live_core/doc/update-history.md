# simple_live_core 修改历史（Git 复现版）

> 版本锚点：`simple_live_core` v1.1.0 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)

## 1. 数据源与复现方法

本文全部结论可由仓库自身复现：

```bash
# ① future 分支（权威历史）：core 相关提交
git log --date=short --pretty=format:"%h|%ad|%an|%s" future -- simple_live_core

# ② 全部 refs（含历史重写前的旧线）：core 相关提交
git log --all --date=short --pretty=format:"%h|%ad|%an|%s" -- simple_live_core

# ③ 单条提交的改动面
git show --stat <hash> -- simple_live_core

# ④ 按平台追溯
git log --oneline --all -- simple_live_core/lib/src/platforms/huya

# ⑤ 重写前/后等价提交互查
git log --all --grep="<提交信息关键词>" --oneline
```

**两个必须知道的前提**：

1. **本仓库历史经过重写**。`future` 分支的根提交是 `543910ba`（2026-07-30，全树导入型），因此 `future` 上能看到 233 条提交（`git rev-list --count HEAD`）、core 相关 43 条（`git log --oneline HEAD -- simple_live_core`）；而全 refs 中 core 相关提交共 **340 条**（`git log --all --oneline -- simple_live_core`，按 subject 去重 **245 条**），重写前的旧线保存在 `backup-future-20260925`、`backup-future-20261009`、`origin/future`、`future-rewrite` 等分支中，可回溯到 2023-02（上游项目早期）。
2. **`master` 是单提交的孤儿分支**（`0eb56cef`，用于 fork-sync CI），不承载 core 历史。

作者口径：`SlotSun` = 上游 dart_simple_live 的提交身份；`gaoxing64` = 本 fork；另有少量社区提交（`xiaoyaocz`、`pugaizai`、`zeke-chin`、`Slot`）。

## 2. 权威时间线（future 分支，35 条）

> 计数口径：下表是整理进时间线的 35 条；`git log --oneline HEAD -- simple_live_core` 当前给 43 条，多出的 8 条（`e3a090ad`/`3a4ddb70`/`b5967198`/`e88268c6`/`b3451ace`/`e3f67344`/`aa5f8073`/`63a3055c`）是 `abca65f8` 一并并入的账号线与格式线上游提交，只列在 §4。

| # | hash | 日期 | 作者 | 类型 | 摘要 | 影响面 |
| --- | --- | --- | --- | --- | --- | --- |
| 35 | `5ae375f1` | 2026-10-14 | gaoxing64 | merge | 同步上游 dev（v1.8.15 之后 5 提交）到 future | 全库 27 文件；core 仅 1 文件（详见 §5） |
| 34 | `03c4493a` | 2026-10-12 | SlotSun | fix | B 站 `getAccountInfo` 回填 `userId`（弹幕握手需配对 uid） | bilibili_site |
| 33 | `57d8f86d` | 2026-10-12 | SlotSun | fix | B 站 `setSiteAttrs` 改为按 JSON 取 cookie（#197 cookie 不生效） | bilibili_site + app `platform_service.dart` |
| 32 | `abca65f8` | 2026-10-12 | gaoxing64 | merge | 同步上游 dev(v1.8.15) 到 future（账号体系下沉 core） | 全库；core 37 文件 |
| 31 | `1c97d00b` | 2026-10-09 | gaoxing64 | merge | 同步上游 dev(v1.8.14) 到 future | 全库 |
| 30 | `d02d2e49` | 2026-10-03 | SlotSun | fix | 虎牙个别线路请求失败导致的断流 | huya_site/danmaku/request_params：线路级容错 |
| 29 | `88ee03b5` | 2026-10-03 | SlotSun | fix | 完善斗鱼 cookie 管理，提示用户续期 | douyu_utils |
| 28 | `b1df5968` | 2026-10-03 | SlotSun | fix | SC 时间戳对不齐 → 按价格&用户名&消息去重 | douyu_site/utils（SC 判重口径） |
| 27 | `aed6a865` | 2026-10-03 | SlotSun | feat | 跳过虎牙 VIP 清晰度（#187） | huya_site/huya_utils |
| 26 | `062d5a83` | 2026-10-03 | SlotSun | refactor | 调整项目结构 | 虎牙资源归入 `huya/common/`；新增 `huya_vip_room_id.dart`；5 平台同步签名 |
| 25 | `8c9fc881` | 2026-10-01 | SlotSun | feat | 虎牙表情包支持 | huya_emoticon + huya_danmaku |
| 24 | `146c4a2c` | 2026-09-30 | SlotSun | chore | 通过正则拉起虎牙 SC | huya_danmaku/huya_utils |
| 23 | `3d237b0e` | 2026-09-30 | **gaoxing64** | fix | 表情包解析对齐 B 站真实载荷并区分大小表情 | live_message / bilibili_emoticon / danmaku / 测试 |
| 22 | `aed42c1e` | 2026-09-29 | **gaoxing64** | feat | 弹幕与聊天区支持 B 站表情包 | 同上（初版） |
| 21 | `249ff1b9` | 2026-09-24 | SlotSun | fix | 斗鱼额外配置实现 cookie 不过期 | http_client/parse_cookie/douyu_* |
| 20 | `2a0f4568` | 2026-09-24 | **gaoxing64** | fix | 补上抖音 `setSiteAttrs` 实现 | douyin_site |
| 19 | `34c39a31` | 2026-09-24 | gaoxing64 | merge | 合并上游 dev (v1.8.12) 到 future | 全库 |
| 18 | `4714974c` | 2026-09-23 | SlotSun | fix | 斗鱼海外免登录看蓝光 4M（临时） | douyu_site（`expire=0` hack） |
| 17 | `9199926c` | 2026-09-22 | SlotSun | refactor | 优化部分代码逻辑 | douyin_*、huya_site |
| 16 | `b492f965` | 2026-09-22 | SlotSun | fix | 斗鱼游客流仅存活 5min → 需要 cookie | interface + 5 平台 + douyu_utils |
| 15 | `899212ba` | 2026-09-18 | gaoxing64 | merge | Merge branch 'dev' into future | 全库 |
| 14 | `63c1eb8d` | 2026-09-16 | **gaoxing64** | fix | 修复分页、播放器与桌面交互遗留问题（含抖音连麦房间） | douyin_site + `douyin_linkmic_room_test.dart` |
| 13 | `cb7f9919` | 2026-09-14 | SlotSun | chore | sync huya ua | huya_request_params |
| 12 | `48aedc9a` | 2026-09-12 | **gaoxing64** | fix | 修正分页、表情与桌面交互遗留问题 | bilibili_emoticon / douyin_site + 3 个测试文件 |
| 11 | `a5e594dc` | 2026-09-11 | **gaoxing64** | feat | B 站表情包，OSD 面板单页化 | live_message / bilibili_danmaku / emoticon / 测试 |
| 10 | `49eef9c3` | 2026-09-11 | **gaoxing64** | feat | 抖音推荐流恢复真分页 | douyin_site / live_category_result + 2 个测试 |
| 9 | `e1f7a75c` | 2026-09-11 | **gaoxing64** | feat | 分页采信服务端 hasMore，收敛单一触发路径 | interface + 5 平台 + CHANGELOG + pubspec(v1.1.0) + 测试 |
| 8 | `fae186bf` | 2026-09-10 | SlotSun | refactor | follow_user_block 模型 | live_message（附带的字段口径） |
| 7 | `4db38b22` | 2026-09-04 | SlotSun | chore | 虎牙 JS 流程完整化 | huya_danmaku/utils/tars |
| 6 | `0c4fbf83` | 2026-09-01 | SlotSun | fix | 虎牙 SC 拉取上限 10 → 50 | huya_utils |
| 5 | `e665a7b7` | 2026-08-23 | SlotSun | refactor | 虎牙弹幕数据模型贴合业务流程 | tars 模型从 `model/tars/` 迁到 `platforms/huya/tars/` |
| 4 | `7453d626` | 2026-08-17 | SlotSun | fix | 虎牙 SC 逻辑修复 | huya_utils |
| 3 | `72e00adb` | 2026-08-17 | SlotSun | feat | 虎牙 SC 支持（试验） | 新增 game_event_message_board_* tars 模型 |
| 2 | `9875d820` | 2026-08-04 | SlotSun | fix | 虎牙弹幕缺失（#164 #84） | huya_danmaku/huya_site |
| 1 | `543910ba` | 2026-07-30 | SlotSun | root | 全树导入（历史重写起点） | 全部文件 |

## 3. fork 自研提交详解（gaoxing64，8 个功能提交 + 5 个 merge）

### 3.1 `e1f7a75c` feat(list): 分页采信服务端 hasMore（v1.1.0，2026-09-11）

- **背景**：App 端出现「列表卡在第一页、刷新无效」。根因在 core：douyu 推荐流依赖 `pgcnt`，而该字段实测恒为 0。
- **改动**：
  - `LiveSite.getCategoryRooms/getRecommendRooms` 新增 `int? pageSize` 具名参数（**对实现方破坏性**，5 个平台同步补齐）；
  - 各平台 hasMore 判据收敛：服务端字段有效则采信，失效则退化为「本页满/非空」；
  - 新增 `test/douyu_recommend_paging_test.dart`（离线）；
  - 版本 1.0.0 → 1.1.0，写 `CHANGELOG.md`。
- **影响**：所有列表页的「能否继续加载」语义；App 侧 `BasePageController.canLoadMore` 直接采信该值。

### 3.2 `49eef9c3` feat(douyin): 推荐流恢复真分页（2026-09-11）

- **背景**：`webcast/feed/` 实测不是分页接口（count/offset/cursor 全被忽略，6 页链式并集仅 47/120），「无限滚动」只能加载一次。
- **改动**：首屏改并发扇出（4~6 路不同 count，合并去重）；第 2 页起改走 `partition/detail/room/v2/` 的 7 个顶级分区轮转真分页；`_lastServedSlot` 防止相邻页重复。
- **测试**：`douyin_recommend_fanout_test.dart`（扇出并发性、上限兜底、切片去重/失败隔离、页号→(分区,offset) 可重放、行尾顺延）；`douyin_category_paging_test.dart`（分类页共用同一 offset 约定）。
- **残留**：feed 池只有 45~65 间 → 首屏 `hasMore` 恒 true 交给续接页；并发收益在 6 路饱和（见 backlog）。

### 3.3 `63c1eb8d` fix: 抖音连麦房间（2026-09-16）

- **背景**：19 位 roomId 的连麦房间经 `web/enter` 返回降级骨架（无 `stream_url`），`detail.data` 为空 Map → 下游 `NoSuchMethodError: The method '[]' was called on null`。
- **改动**：19 位 roomId 先走 `reflow/info`；`web/enter` 报在播但缺流数据时用 reflow 补查；所有取数路径判空，拿不到就抛 `CoreError`/空画质。
- **测试**：`douyin_linkmic_room_test.dart` 五条用例，含「两条路都拿不到时抛 CoreError 而不是空指针」。

### 3.4 `a5e594dc` → `aed42c1e` → `3d237b0e` B 站表情包（2026-09-11 ~ 09-30）

- **背景（Issue #153）**：B 站「表情包弹幕」只在 message 里下发占位符文本（`[doge]`），图片另放在 `info[0][13]`（单表情）或 `info[0][15].extra.emots`（行内混排）。
- **改动**：`LiveMessage` 新增 `emoticons` 字段与 `LiveMessageEmoticon`（含 `large`/`emoticonUnique`/宽高）；新增 `bilibili_emoticon.dart` 解析器（只保留正文真正出现的占位符、单条上限 8、图片统一升 https、两种下发方式去重、异常载荷返回 null）；`LiveMessage.toString()` 保证表情序列化为对象数组。
- **测试**：`bilibili_emoticon_test.dart` 共 20+ 组用例（含「大表情真实载荷没有第 15 位」「裸名长度上限 12 字」「无空白的表情名+正文按整串替换（已知取舍）」）。
- **演进**：`48aedc9a`、`3d237b0e` 为两轮复查修正（对齐线上真实载荷、统一两入口的 large 判据）。

### 3.5 `2a0f4568` fix(douyin): 补上 `setSiteAttrs`（2026-09-24）

- 上游 v1.8.12 在 `LiveSite` 上新增了 `setSiteAttrs`（cookie/UA 注入），抖音实现漏补导致合并后编译失败。本提交补齐并接入 App 的 `platform_service.dart`。

### 3.6 五次上游同步 merge

| merge | 内容 | 备注 |
| --- | --- | --- |
| `899212ba`（09-18） | Merge branch 'dev' into future | 常规同步 |
| `34c39a31`（09-24） | 同步 dev v1.8.12 | 带来 `setSiteAttrs` 接口（见 3.5） |
| `1c97d00b`（10-09） | 同步 dev v1.8.14 | 带来虎牙 SC/表情、斗鱼 cookie、Cleanup 结构（#24~#30） |
| `abca65f8`（10-12） | 同步 dev v1.8.15 | 账号体系下沉 core + `dart format` 全库重排（详见 §4） |
| `5ae375f1`（10-14） | 同步 dev 在 v1.8.15 之后的 5 条提交 | 仅 B 站 cookie/uid 两处动 core（详见 §5） |

> 合并冲突的处理惯例：以 fork 侧的分页/表情实现为准，上游只取协议层更新（UA、endpoint、字段）；每次同步后跑 `test/` 全量离线用例 + 联网冒烟。

## 4. 2026-10-12 同步上游 dev(v1.8.15)

- **合并提交**：`abca65f8`（2026-10-12，gaoxing64）——把 `origin/dev`（= `fork-parent/dev`，上游 SlotSun，自报 v1.8.15）合入 `future`，合并后是当时的分支 HEAD（现 HEAD 见 §5）。
- **上游带来 13 条提交**，复现命令：`git log --oneline 3714eec1..abca65f8 --no-merges`（`3714eec1` 为合并前的 `future` HEAD）。按聚类：

| 聚类 | # | hash | 日期 | 作者 | 摘要 |
| --- | --- | --- | --- | --- | --- |
| 账号迁移（10） | 1 | `e3a090ad` | 2026-10-10 | SlotSun | refactor(account): 逐步迁移账号登录从 app 到 core，项目架构更清晰 |
| | 2 | `3a4ddb70` | 2026-10-10 | SlotSun | refactor(account): 实现 bilibili_account 接口 |
| | 3 | `b5967198` | 2026-10-10 | SlotSun | refactor(account): 实现 douyu_account 接口 |
| | 4 | `c690e5f3` | 2026-10-10 | SlotSun | db: 构造 account 数据模型 |
| | 5 | `e88268c6` | 2026-10-10 | SlotSun | refactor(account): 完成 account 站点分流基础功能 |
| | 6 | `b3451ace` | 2026-10-11 | SlotSun | fix(account): credential 数据拼装 |
| | 7 | `e3f67344` | 2026-10-11 | SlotSun | refactor(account): 跑通 QRcode 全流程 |
| | 8 | `9abf40ff` | 2026-10-11 | SlotSun | refactor(account): 完成 bilibili_webLogin 功能迁移 |
| | 9 | `aa5f8073` | 2026-10-11 | SlotSun | refactor(account): 完成平台账号数据同步迁移工作 |
| | 10 | `70b1d18f` | 2026-10-11 | SlotSun | feat(account): 完善平台账号各项同步迁移功能 |
| 格式统一（1） | 11 | `63a3055c` | 2026-10-11 | SlotSun | style: dart format .（全库 40 文件，其中 core 26 文件） |
| 依赖同步（2） | 12 | `6847a151` | 2026-10-09 | SlotSun | chore: sync fvm 3.47.6（仅 `simple_live_app/.fvmrc` + flatpak 清单；**core `.fvmrc` 仍锁 3.38.4**） |
| | 13 | `80e1a096` | 2026-10-09 | SlotSun | chore: sync media_kit version（仅 app 侧 pubspec/lock 与平台注册文件） |

> 口径说明：`git log --oneline abca65f8 --first-parent` 只看得到 merge 本身，须用上面的 range + `--no-merges` 才能列出被并入的 13 条。core `CHANGELOG.md` / `pubspec.yaml` 版本仍为 1.1.0，本次未变；「v1.8.15」是 merge message 中标注的上游版本。

**本次合并触及 `simple_live_core` 37 个文件**（`git diff --stat 3714eec1 abca65f8 -- simple_live_core`）：主体是账号体系下沉（新增 `account_info.dart` / `account_qr_code.dart` / `qr_status.dart` / `common_asT.dart`，各平台补 `getQRCode/getQRPollResult/getAccountInfo`）+ `dart format` 全库重排（抖音 `*.pb*.dart` 因 format 变动最大）。`simple_live_app` 侧另有 `platform_service.dart` / `sync_service.dart` / `constant.dart` 等 5 处适配（上游提交 `70b1d18f`）。

### 4.1 冲突解决口径（以 fork 侧为准）

- **`pageSize` 签名保留 fork 版**：`LiveSite.getCategoryRooms/getRecommendRooms` 的 `int? pageSize` 是 fork-only（上游 `origin/dev` 的 `live_site.dart` 无此参数）。5 个平台实现同步保留，App 依赖该参数调整单页条数。
- **抖音 `setSiteAttrs` 契约取上游、实现取 fork**：签名由 fork 的 `Map<String, dynamic>` 改回上游的 `String`（string2json 适配各平台 credentials），但实现仍是 fork 的 `headers['cookie']` 语义（`douyin_site.dart:1233`）。上游 `origin/dev` 用的是 `_cookie` 字段 + `_updateDouyinCookie()`，**合并结果里没有**该方法与字段，以 fork 语义为准。
- **新产生的「fork vs 上游」差异**：① `pageSize` 在本轮再次成为冲突点（上游仍无此参数）；② 抖音 `setSiteAttrs` 实现分叉（详见 §9 与 architecture.md §6）。

### 4.2 适配修复

- **无**：`flutter analyze`（core）无 error，仅存量 info/warning（如 `huya_site.dart:37` 的 `_isVipRoom` unused_field）；core 侧不需要额外代码修复。core 本次未跑测试（仅 App 侧做了适配）。

## 5. 2026-10-14 同步上游 dev（v1.8.15 之后 5 提交）（最新）

- **合并提交**：`5ae375f1`（2026-10-14，gaoxing64），父提交 = `8fd14a9f`（fork 侧）+ `f8318694`（`origin/dev`）；**无冲突**，`bilibili_site.dart` 自动合并，fork 的 `String` 契约保留（`live_site.dart:103`）。
- **上游带来 5 条提交**，复现命令：`git log --oneline 70b1d18f..f8318694`（`70b1d18f` = §4 账号线最后一条，即本次同步的起点）。逐条 `git show <hash> --stat` 核对对 core 的实际影响：**只有前两条触及 `simple_live_core`**。

| # | hash | 日期 | 作者 | 摘要 | 触及 core？ |
| --- | --- | --- | --- | --- | --- |
| 1 | `57d8f86d` | 2026-10-12 | SlotSun | fix(bili): 迁移到 Account cookie 不生效（上游 issue #197） | ✅ `bilibili_site.dart`（同提交另改 app `platform_service.dart`） |
| 2 | `03c4493a` | 2026-10-12 | SlotSun | fix(bili): 补充弹幕 cookie 需要配对的 uid | ✅ `bilibili_site.dart`（1 行） |
| 3 | `6da36e04` | 2026-10-13 | SlotSun | feat(tv): 支持斗鱼扫码登录（tv 侧账号 model/migration） | ❌ 全在 `simple_live_tv_app`（22 文件） |
| 4 | `bafc703b` | 2026-10-14 | SlotSun | ci: prebuild tv_app v1.5.1 with flutter v3.35.7 | ❌ CI workflow + `assets/tv_app_version.json` + tv `pubspec.lock` |
| 5 | `f8318694` | 2026-10-14 | Slot | Update Crowdin configuration file | ❌ `crowdin.yml`（1 行） |

- **core 改动面**：`git diff --stat 8fd14a9f..HEAD -- simple_live_core` = **1 文件 / 5 增 1 删**，全在 `lib/src/platforms/bilibili/bilibili_site.dart`；`test/`、`pubspec.yaml`、`CHANGELOG.md` 无变化（`git diff --stat 8fd14a9f..HEAD -- simple_live_core/test simple_live_core/pubspec.yaml simple_live_core/CHANGELOG.md` 输出为空）。

### 5.1 `setSiteAttrs`：整串当 cookie → 按 JSON 取 `cookie` 键（`57d8f86d`）

- **现状**：`bilibili_site.dart:553-558` 先 `jsonDecode(data)`，仅在含 `cookie` 键时写入站点字段 `cookie`（`:18`）；与 `douyu_site.dart:344-356`、`douyin_site.dart:1233-1246` 同构（huya 只读 `ua`，`huya_site.dart:559-564`）。
- **为什么算修复**：扫码轮询早就把凭证包成 JSON —— `bilibili_site.dart:600` `credential = jsonEncode({'cookie': cookieStr})`；旧实现把整串直接赋给 `cookie`，等于把 `{"cookie":"..."}` 字面量当 cookie 发出，登录后的 B 站请求依旧鉴权失败（上游 issue #197，见提交标题）。
- **同条提交的 app 侧 1 处**：`platform_service.dart` 的 `accountLogout` 把 `siteId: ac.siteId` 换成 `userName: ''`（`siteId` 由 `copyWith` 保留原值）。属 `simple_live_app`，本文件不展开。

### 5.2 `getAccountInfo` 回填 `userId`（`03c4493a`）

- **现状**：`bilibili_site.dart:622` `userId = info.mid!; // danmaku_arg needs`，位置在 `result["code"] == 0` 之后、`res.copyWith(...)` 之前，仍在同一 `try` 内（`catch` 在 `:631-633`）→ `mid` 为 null 时 `!` 抛错被吞，退化为 `isValid=false` 的空 `AccountInfo`。
- **为什么需要**：`userId` 声明于 `:19`，此前**全文件没有任何写入点**（`git show abca65f8:simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart | grep -n userId` 只命中 `:19` 声明与 `:252` 读取）。`getRoomDetail` 把它填进弹幕参数（`:250-257` 的 `BiliBiliDanmakuArgs.uid`），WS join 包带的就是 `"uid": args.uid`（`bilibili_danmaku.dart:91`），cookie 则进握手头（`:63-67`）——uid 与 cookie 必须同属一个账号，否则登录态下配对不上。
- **影响面只在握手**：core 的 `LiveDanmaku` 没有发送弹幕的接口（`live_danmaku.dart:5-25` 只有回调 / 心跳 / `start` / `stop`），故本次改动不触及下行解码路径。
- **副作用范围**：写的是 Site 单例字段（`live_site.dart:115-117` 注释「because every site is singleInstant」），所以「先 `getAccountInfo`/`setSiteAttrs`、后 `getRoomDetail`」才拿得到非 0 的 uid。

### 5.3 验证与遗留

- 本轮未跑构建命令；以下引自合并提交信息（`git log -1 --format=%B 5ae375f1`）：core/app `dart analyze` 0 error；App 侧 `flutter test` 同机对比，合并前后均 507 通过 / 15 失败且失败名单逐条一致。
- core `test/` 无新增、无改动（见上面的空 diff）。B 站凭证 JSON 解析与 `userId` 回填目前**没有离线用例**（`grep -rn "setSiteAttrs" simple_live_core/test` 无命中），缺口见 test-suite.md §4.5 与 §4.7。

## 6. 上游演化脉络（由旧线复现，2023-02 ~ 2026-07）

按月提交密度（全部 refs、按 subject 去重，仅作量级参考）：

| 月份 | 条数 | 关键事件 |
| --- | --- | --- |
| 2023-06 ~ 2024-03 | 分散 1~13/月 | 早期多平台雏形 |
| 2024-06 | 9 | 平台解析迭代 |
| 2025-05 | 14 | — |
| 2025-08 | 14 | — |
| 2025-09 | 12 | 斗鱼/抖音本地签名试验（`4802e965`/`38bdefb2`） |
| 2025-10 | 13 | **Twitch 全流程落地**（`8da23f68` 结构调整、"适应更多平台"、`24aace36` 弹幕）；flatpak/Flutter 3.35.7（`pugaizai`） |
| 2025-11 | 12 | 斗鱼 SC（`25d99dfd`）；抖音 hls 优先 / 真原画预留（`97c9c27a`/`63ac4e78`）；JS 引擎内存限制（`c69c9fbe`）；抖音 ttwid 账号服务（`7ff3caac`，社区）；twitch gql token（`c476e87d`） |
| 2025-12 | 16 | 虎牙大重构：platform 重构（`6e02e3e7`）、WUP2（`c21d9ed0`/`44153322`）、antiCode 修复（`b897a303`）；tag 数据治理（`30f7a6c8`） |
| 2026-01 | 7 | pinyin 替换 romanize、斗鱼 SC 配色/修复、webdav 修复 |
| 2026-02 | 8 | 虎牙 room-search 修复、douyin-category 修复、Flutter 3.41 |
| 2026-03 | 3 | **斗鱼逆写 JS，剥离 flutter_qjs**（`dd44a80e`） |
| 2026-04 | 2 | 账号逐步改为平台预设（`6b0fc354`） |
| 2026-06 | 4 | **抖音 xbogus 替换 JS 引擎**（`0509f173`）、移除 JS 插件（`1c9d1714`）、release v1.8.9 |
| 2026-07 | 1 | 虎牙弹幕空安全修复（`ed8e2880`）——此后进入 future 重写 |

## 7. 各平台提交热度与关注点

> 口径（本次按 HEAD=`5ae375f1` 重算）：`future 条数` = `git log --oneline HEAD -- simple_live_core/lib/src/platforms/<平台>`；`全部 refs 条数` = 同一路径加 `--all`。common/model/test 三行把路径换成 `simple_live_core/lib/src/common`、`lib/src/model`、`test`。这两列会随 fetch 进来的上游线一起漂移，换锚点时要重跑。

| 模块 | future 条数 | 全部 refs 条数 | 关注点 |
| --- | --- | --- | --- |
| huya | 22 | 58 | 最活跃：SC、表情、WUP2/tars、antiCode、UA 同步、结构迁移 |
| douyin | 15 | 39 | 反爬（abogus/xbogus）、推荐分页、连麦容错 |
| bilibili | 19 | 32 | wbi 签名、表情包、清晰度、账号凭证注入（`57d8f86d`/`03c4493a`） |
| douyu | 15 | 32 | enc 签名、cookie 生命周期、SC、海外 hack |
| twitch | 9 | 27 | gql/IRC、token 更新 |
| common | — | 37 | WS 重连、HTTP、日志 |
| model | — | 50 | 模型增补与迁移（含 tars 模型两轮搬迁） |
| test | 11 | 42 | 离线回归为主，fork 贡献了绝大部分 |

## 8. 历史重写：新旧提交对照

「重写前旧线」与「future 新线」是同一批工作的两套 hash，核对历史时用 `--grep` 按 subject 找两条：

| 新（future） | 旧（backup/origin） | 说明 |
| --- | --- | --- |
| `a5e594dc` | `47cd644f` | B 站表情包（subject 相同） |
| `49eef9c3` | `05805539` | 抖音推荐真分页 |
| `e1f7a75c` | `03402670` | 分页 hasMore 收敛 |
| `48aedc9a` | `35255ee6` | 旧线 subject 为「按 Open Code Review 复查结果修正…」 |
| `63c1eb8d` | `2575256b` | 旧线 subject 为「按 OCR 复查结果修复…」 |
| `34c39a31` | `02ed58ac` | 上游 v1.8.12 同步 merge |
| `899212ba` | `f3d4c217` | dev→future merge |

> 结论：**以 future 分支为准**；旧线仅用于找回重写前的上下文（PR 讨论、issue 编号、更细的中间提交）。注意 `2a0f4568`（补 setSiteAttrs 实现）与旧线 `7eb83ef3`（补实现并修复编译失败）是同日两条不同提交，不是重写重复。

## 9. 当前状态

- 版本：`pubspec.yaml` = 1.1.0（两次同步均未变）；`CHANGELOG.md` 仅有 1.1.0 / 1.0.0 两个条目（更早历史随重写丢失，用本文 §6 代替）。
- 分支：`future` HEAD = `5ae375f1`（2026-10-14，同步上游 dev 在 v1.8.15 之后的 5 条提交）。
  - `git rev-list --left-right --count origin/dev...future` → `0 130`（future 领先 `origin/dev` 130 个提交）；
  - `git rev-list --left-right --count dev...future` → `0 185`（future 领先 `dev` 185 个提交）。
- 最近一次 core 变更：`57d8f86d` + `03c4493a`（2026-10-12 的上游提交，经 `5ae375f1` 并入，只动 `bilibili_site.dart`）；再往前是 `abca65f8`（账号体系下沉 core + `dart format`）。
- 待跟进的悬置项见 [backlog.md](./backlog.md)；回归基线见 [test-suite.md](./test-suite.md)。