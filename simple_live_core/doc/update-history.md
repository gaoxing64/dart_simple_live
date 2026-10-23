# simple_live_core 修改历史（Git 完整复现）

> 锚点：future `52466f96`（2026-10-21）｜`git log future -- simple_live_core` 全量 **66** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/update-history.md)｜[TV](../../simple_live_tv_app/doc/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游）。本表为路径过滤后的全量时间线。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- simple_live_core
git show --stat <hash>
git log --oneline -- crates/slive-core/src/platforms/douyin
git log --all --date=short --pretty=format:'%h %ad %s' -- simple_live_core
```

历史已重写：future 根提交 `543910ba`；旧线在 `backup-future-*` / `origin/future`。

## 2. 阶段归纳

| 阶段 | 日期范围 | 主题 |
| --- | --- | --- |
| 弹幕句柄/多开修复 | 2026-10-19 ~ 10-20 | 每实例连接句柄、句柄释放即停止、账号凭证 |
| Rust 全面接管 | 2026-10-17 ~ 10-18 | FRB 下沉、Dart 协议删除、slive-cli、虎牙表情、夹具修复 |
| 账号/续流 | 2026-10-09 ~ 10-16 | 账号从 App 迁 core、斗鱼本地续流中转 |
| 平台能力 | 2026-09-01 ~ 10-08 | 分页 hasMore、B站/抖音/虎牙表情、SC、VIP 清晰度 |
| 初始导入 | 2026-07-30 ~ 08-31 | 全树导入与基础协议 |

## 3. 全量时间线（66 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-20 | `63197f69` | G | fix(account): 校验失败不再抹凭证，修复升级用户每次启动误报账号失效 |
| 2026-10-19 | `24edf9f7` | G | fix(ci): 修复产物命名规范改动引入的三个产物回归 |
| 2026-10-19 | `3f0ac946` | G | refactor(core)!: 弹幕入口改每实例连接句柄，修复多开互停 |
| 2026-10-19 | `eecc060f` | G | fix(core): 弹幕会话将连接句柄释放视为停止 |
| 2026-10-18 | `953f78b7` | G | feat(core): 虎牙弹幕支持房间大表情与梗表情包 |
| 2026-10-18 | `4eb5bfc3` | G | docs(core): 知识库五件套同步至 Rust 架构 |
| 2026-10-18 | `7b6341d5` | G | fix(core): 标记 .bin 夹具为 binary，修复 Twitch 8 条恒红用例 |
| 2026-10-18 | `f72bb417` | G | refactor(core)!: 删除 Dart 协议实现，console 由 slive-cli 取代 |
| 2026-10-18 | `935db9e3` | G | feat(cli): 新增 slive 命令行工具，直连 Rust 核心不经 FRB |
| 2026-10-18 | `4795b165` | G | docs: 同步斗鱼续流「上下文驱动」契约与测试口径 |
| 2026-10-18 | `2c0cf372` | G | fix(core): 修复虎牙 SC 拉取嵌套 runtime 导致弹幕静默停更 |
| 2026-10-17 | `30bf6aae` | G | feat(core): 抖音弹幕支持会员表情与标准表情 |
| 2026-10-17 | `c273dcd2` | G | core rust 化（增量：全面采用 Rust core —— 去开关 / 绑定层下沉 / TV 迁移 / 删 Twitch Dart 平台） |
| 2026-10-17 | `6dd27ec6` | G | docs: ADR-014 全面采用 Rust core，同步结构与路径文档 |
| 2026-10-17 | `e0cd41a6` | G | refactor(core): 删除 Dart Twitch 平台实现（消费者归零） |
| 2026-10-17 | `73e80b1e` | G | refactor(core): FRB 资产与 Dart 绑定层迁入 simple_live_core，App 直连 Rust 去开关 |
| 2026-10-17 | `a02829f1` | G | fix(tests): 虎牙夹具 key 改名 —— 消除误触 GitHub Secret Scanning 的 live_ 前缀模式 |
| 2026-10-17 | `70c1c717` | G | refactor: Rust workspace 迁至 simple_live_core（ADR-001 预留路径落地） |
| 2026-10-17 | `7cb47723` | G | Merge fork-parent/dev: 同步上游 4 提交增量（含虎牙 SC 真实 uri 修复 97413c60） |
| 2026-10-17 | `97413c60` | S | fix(core): listen real uri to get list of huya-sc #157 |
| 2026-10-16 | `4dcdb4fe` | G | docs(douyu): 续流中转落地后同步 core/app 文档 |
| 2026-10-16 | `77eebd63` | G | fix(douyu): 新增本地续流中转，修复未配置 cookie 时约 5 分钟断流 |
| 2026-10-14 | `64d2c634` | G | docs(core): 新增 simple_live_core 知识库（5 份，锚点 abca65f8） |
| 2026-10-14 | `5ae375f1` | G | merge: 同步 dev(v1.8.15 之后 5 提交) 到 future |
| 2026-10-12 | `03c4493a` | S | fix(bili): 补充弹幕 cookie 需要配对的uid |
| 2026-10-12 | `57d8f86d` | S | fix(bili): 迁移到Account cookie 不生效 #https://github.com/SlotSun/dart_simple_live/issues/197#issuecomment-6118992744 |
| 2026-10-12 | `abca65f8` | G | merge: 同步上游 dev(v1.8.15) 到 future |
| 2026-10-11 | `aa5f8073` | S | refactor(account): 完成平台账号数据同步迁移工作 |
| 2026-10-11 | `63a3055c` | S | style: dart format . |
| 2026-10-11 | `e3f67344` | S | refactor(account): 跑通QRcode全流程 |
| 2026-10-11 | `b3451ace` | S | fix(account): credential 数据拼装 |
| 2026-10-10 | `e88268c6` | S | refactor(account): 完成account 站点分流基础功能 |
| 2026-10-10 | `b5967198` | S | refactor(account): 实现 douyu_account 接口 |
| 2026-10-10 | `3a4ddb70` | S | refactor(account): 实现 bilibili_account 接口 |
| 2026-10-10 | `e3a090ad` | S | refactor(account): 逐步迁移账号登录从app到core，项目架构更清晰 |
| 2026-10-09 | `1c97d00b` | G | merge: 同步上游 dev(v1.8.14) 到 future |
| 2026-10-03 | `d02d2e49` | S | fix(huya): 偶尔因个别线路请求失败导致的断流 |
| 2026-10-03 | `88ee03b5` | S | fix: 完善斗鱼cookie管理，提示用户续期cookie |
| 2026-10-03 | `b1df5968` | S | fix: SC时间戳对不齐，改由价格&用户名&消息判断去重 |
| 2026-10-03 | `aed6a865` | S | feat: 跳过 huya vip 清晰度 #187 |
| 2026-10-03 | `062d5a83` | S | refactor: 调整项目结构 |
| 2026-10-01 | `8c9fc881` | S | feat: support huya emoticon |
| 2026-09-30 | `146c4a2c` | S | chore(huya): 通过正则拉起huya-sc |
| 2026-09-30 | `3d237b0e` | G | fix(core): 表情包解析对齐 B 站真实载荷并区分大小表情 |
| 2026-09-29 | `aed42c1e` | G | feat(danmaku): 弹幕与聊天区支持 B 站表情包 |
| 2026-09-24 | `249ff1b9` | S | fix(douyu): 额外配置实现cookie不过期 |
| 2026-09-24 | `2a0f4568` | G | fix(douyin): 补上 LiveSite.setSiteAttrs 接口实现 |
| 2026-09-24 | `34c39a31` | G | merge: 合并上游 dev (v1.8.12) 到 future |
| 2026-09-23 | `4714974c` | S | fix(douyu): 海外用户可以免登录看蓝光4m不断 temp |
| 2026-09-22 | `9199926c` | S | refactor: 优化部分代码逻辑 |
| 2026-09-22 | `b492f965` | S | fix(douyu): douyu 游客模式直播流只能存活5min,需要配置 cookie |
| 2026-09-18 | `899212ba` | G | Merge branch 'dev' into future |
| 2026-09-16 | `63c1eb8d` | G | fix: 修复分页、播放器与桌面交互的遗留问题 |
| 2026-09-14 | `cb7f9919` | S | chore(core): sync huya-ua |
| 2026-09-12 | `48aedc9a` | G | fix: 修正分页、表情与桌面交互的遗留问题 |
| 2026-09-11 | `a5e594dc` | G | feat(danmaku): 弹幕与聊天区支持 B 站表情包，OSD 统计面板收敛为单页 |
| 2026-09-11 | `49eef9c3` | G | feat(douyin): 抖音推荐流恢复真分页，列表到底给出明确提示 |
| 2026-09-11 | `e1f7a75c` | G | feat(list): 分页采信服务端 hasMore，收敛为单一触发路径并补齐失败重试入口 |
| 2026-09-10 | `fae186bf` | S | refactor(block): 构造follow_user_block的model 和 crud |
| 2026-09-04 | `4db38b22` | S | chore: 逐步实现huya-js 流程完整化 |
| 2026-09-01 | `0c4fbf83` | S | fix(core): increase huya-sc fetch limit from 10 to 50 |
| 2026-08-23 | `e665a7b7` | S | refactor(core): huya弹幕数据模型业务逻辑更符合流程 |
| 2026-08-17 | `7453d626` | S | fix: huya super chat logic |
| 2026-08-17 | `72e00adb` | S | feat(core): support huya super chat (test) |
| 2026-08-04 | `9875d820` | S | fix: 虎牙弹幕缺失问题 #164 #84 |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time |

## 4. 当前状态

- future HEAD `52466f96`；core 最新提交 `63197f69`。
- 66 条中 fork（G）35 条、上游（S）31 条；Rust 迁移完成，Dart 协议实现已删除。
- 测试基线：2026-10-18 为 935 通过 / 0 失败；当前 31 个集成测试文件（新增虎牙表情/句柄用例后未重测总数）。
