# simple_live_app 修改历史（Git 复现版）

> 版本锚点：`simple_live_app` v1.8.15+10815 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)

## 1. 数据源与复现方法

本文全部结论可由仓库自身复现（只读命令，不含构建/测试）：

```bash
# ① future 分支（权威历史）：app 相关提交
git log --date=short --pretty=format:"%h|%ad|%an|%s" future -- simple_live_app

# ② 全部 refs（含历史重写前的旧线）：app 相关提交
git log --all --date=short --pretty=format:"%h|%ad|%an|%s" -- simple_live_app

# ③ 单条提交的改动面 / 子系统追溯
git show --stat <hash> -- simple_live_app
git log --oneline future -- simple_live_app/lib/modules/live_room/player

# ④ 重写前/后等价提交互查（按 subject）
git log --all --grep="<提交信息关键词>" --oneline

# ⑤ 判断某个 hash 是否在 future 上（区分新/旧线）
git merge-base --is-ancestor <hash> future   # 退出码 0 = 在 future 上
```

**两个必须知道的前提**：

1. **本仓库历史经过重写**。`future` 分支的根提交是 `543910ba`（2026-07-30，全树导入型），
   因此 `future` 上 app 相关提交共 **193 条**（锚点 `5ae375f1`，`git log --oneline future -- simple_live_app | wc -l`）；
   而全 refs 中 app 相关提交共 **1333 条**
   （含大量 merge 与旧线重复）。重写前的旧线保存在 `backup-future-20260925`、
   `backup-future-20261009`、`origin/future`、`future-rewrite`、`feat/multiplay-all-ends`
   等分支中。新旧线同一批工作的 hash 不同，可按 subject `--grep` 配对（见 §6）。
2. **`master` 是单提交的孤儿分支**（用于 fork-sync CI），不承载 app 历史。

作者口径：`SlotSun` = 上游 dart_simple_live 的提交身份（其 app 侧提交多为 release /
flutter 升级 / 业务重构）；`gaoxing64` = 本 fork；另有少量社区提交（`Slot`、
`pugaizai`、`xiaoyaocz` 等）。

## 2. 权威时间线（future 分支，193 条）

193 条按单一流水账阅读价值低，本节先按**功能线**聚类，再在 §2.2 给出全量清单
（截至 2026-10-11；2026-10-12 的上游同步批见 §2.3，同日的关注多归属功能线见 §2.4，
2026-10-14 的上游同步批见 §2.5）。

### 2.1 主线时间线（按功能线聚类）

| 时间窗 | 功能线 | 代表提交 | 内容 |
| --- | --- | --- | --- |
| 07-30 ~ 08-09 | 关注/潜伏期上游 + 播放器动作栏收尾 | `543910ba` `93bea52d` `de601e3c` `73e5898d` | 上游 follow 潜伏期与 last_watch_time；移除全屏冗余全屏按钮、清晰度弹窗复制直链、直链按钮图标化 |
| 08-21 ~ 09-03 | 上游基建：flutter 3.44→3.47 与 material_ui 迁移 | `9bdc5f10` `a0985b3a` `3fff9ef4` `1e3566a3` | Flutter/Material 版本爬升、迁移 material_ui 与 easy_refresh、弃用 API 清理 |
| 08-29 ~ 08-31 | UI 清理/主题/悬浮导航 | `82e61c8d` `d1978333` `8af872e6` | Windows 标题栏跟随主题；首页顶/底栏随滑动收起；新增悬浮玻璃导航栏 |
| 09-09 ~ 09-11 | 分页与列表加载（fork 主线） | `4e3c35a1` `e1f7a75c` `49eef9c3` `fb97e0ec` | 滚动通知自动补页 + 骨架；采信服务端 hasMore；抖音推荐真分页；隐藏列表停 ticker |
| 09-09 ~ 09-11 | OSD 统计浮层自绘 | `7865964d` `7347f515` | mpv 内置 OSD → Flutter 自绘响应式；后补「自绘/mpv 内置」可切 |
| 09-11 ~ 09-30 | B 站表情渲染与聊天区 | `a5e594dc` `aed42c1e` `5d8f0b38` `24b68f30` | 弹幕/聊天区表情包；渲染尺寸口径与开关；大表情占两个轨道、聊天区上限 150 |
| 09-18 ~ 09-25 | 关注页（分组/搜索/标签） | `b95865ac` `e17b9239` `f8822089` `453a01fd` | 分组视图 + 三页 ViewPager；搜索改顶栏原位展开；一键展开折叠；搜索胶囊对齐搜索页 |
| 09-19 ~ 09-21 | 桌面交互与窗口 | `c9d6f183` `afc6d8c4` `b5f9e9bd` `e53c0825` | 统一弹出菜单规格；滑动收起改纯绘制；最小窗口宽 436；底栏换 liquid_glass_easy |
| 09-20 ~ 09-27 | 小窗/全屏与会话 | `d45cad06` `01c8ab61` `dec20731` | 小窗锁定纵横比；全屏/小窗进出后最小宽度失效；音量均衡 loudnorm 与最大音量 |
| 10-01 | 多开（multi_play）地基 | `d5f32f7d` `f65912ab` `de408209` `8f7b941e` `48011b93` | 会话层与共享状态；棋盘视图 + 格子控件；关注页批量开多开；返回键与性能收口 |
| 10-03 | OSD 统一 + 每路独立音量（spec 落地） | `77eb7864` `247b8d80` `34f43593` `05f2521c` `b153e010` `ca13b5aa` | 音量纯函数、动作 resolver、桌面 renderer、音量三态控件、按格画面尺寸 |
| 10-03 | 桌面 OSD 形态收敛 | `b7188916` `636116d7` `9936e941` `b4a97364` | 右上角那一簇回归；底栏右簇贴右；清单类弹层按宿主分 |
| 10-04 | 多开落到移动端 | `1826c57b` `fcb43a82` | 触屏判据与竖屏视频区高度；竖屏 1×2、横屏全屏 2×2 |
| 10-06 | 悬浮底栏重构 | `e250ceb6` | 悬浮底栏换成 FlClash lens 底栏，移除 Liquid Glass |
| 10-09 | 后台播放与系统媒体控制 | `efa33716` `cd89ecdc` `5692db16` `cbb474ee` `e374b4df` | 依赖钉版；audio_service handler 与音频会话；直播间挂系统媒体控制；开关互斥；Android 原生接线 |
| 10-11 | 快捷键 + 多开动作式 + 音量浮层 | `12ab0c42` `afd18194` `5e5f1009` `c71da474` | 直播间快捷键可改键；多开「模式→动作」；音量浮层静音双向；全屏退出恢复窗口 |
| 10-12 | 关注多分组归属 + 一键按平台智能分组（fork 主线） | `7c895e6d` `5890641e` `6c7632e2` `53b70b83` `a225e3b4` `0442f4ac` `3c8a34c4` `6cf66e3f` `3267a04e` `3b86b496` `8fd14a9f` | 归属真源换成 `FollowUserTag.userId` 成员表；groupedView 按 userId 分桶；写路径翻转；备份 `tags` 数组 + WebDAV 按分组名并集；SmartGroupService 与两处入口；删 `FollowUser.tag` 冷字段（全批见 §2.4） |
| 10-12 | 上游同步 dev(v1.8.15) | `abca65f8` | 账号登录迁 core、`dart format`、fvm 3.47.6（详见 §2.3） |
| 10-14 | 上游同步 dev（5 提交） | `5ae375f1` | B 站 cookie 按 JSON 取 + `getAccountInfo` 回填 `userId`；app 侧仅 `accountLogout` 清 `userName`（详见 §2.5） |
| 全期 | 同步（WebDAV） | `03d66eb7` `7ba585ee` `abdffe71` `139ea90a` | 同步项可选、cookie 双向同步优先本地、单例模式去重 |
| 全期 | Rust 桥 | （无专属提交，仅 `1e3566a3`/`9bdc5f10`/`543910ba` 顺带触及 `rust/`） | 无独立 Rust 变更 |

### 2.2 全量提交清单（future，169 条截至 2026-10-11，新→旧；10-12 同步批见 §2.3，10-12 关注多归属线见 §2.4，10-14 同步批见 §2.5）

| hash | 日期 | 主题 |
| --- | --- | --- |
| `3714eec1` | 2026-10-11 | merge: 多开改为动作式加入 + 音量浮层修复，并入 future |
| `afd18194` | 2026-10-11 | feat(multiplay): 多开从「模式」改成「动作」，关注行图标对齐 |
| `5e5f1009` | 2026-10-11 | fix(player): 音量浮层静音双向、拖动滑条也浮出读数 |
| `c71da474` | 2026-10-11 | fix(player): restore window after fullscreen exit |
| `12ab0c42` | 2026-10-11 | feat(live_room): 直播间播放器快捷键，可改键 / 禁用 / 恢复默认 |
| `1c97d00b` | 2026-10-09 | merge: 同步上游 dev(v1.8.14) 到 future |
| `e374b4df` | 2026-10-09 | feat(android): 媒体前台服务、通知与耳机键的原生接线 |
| `5692db16` | 2026-10-09 | feat(live_room): 直播间那一路挂到系统媒体控制上 |
| `cd89ecdc` | 2026-10-09 | feat(playback): audio_service handler 与音频会话 |
| `cbb474ee` | 2026-10-09 | feat(settings):「后台播放」开关，与「进入后台自动暂停」双向互斥 |
| `efa33716` | 2026-10-09 | build(deps): 引入 audio_service 0.18.19 与 audio_session 0.2.4 |
| `0f2481f6` | 2026-10-09 | fix(multiplay): 补上只有引用、没有定义的两个「默认路数」符号 |
| `029913c1` | 2026-10-08 | chore: update flutter 3.47.6 |
| `e250ceb6` | 2026-10-06 | feat(navbar): 悬浮底栏换成 FlClash lens 底栏，移除 Liquid Glass |
| `fcb43a82` | 2026-10-04 | feat(multiplay): 多开播放落到移动端——竖屏 1×2、横屏全屏 2×2 |
| `1826c57b` | 2026-10-04 | feat(multiplay): 移动端适配的地基——触屏判据与竖屏视频区高度 |
| `19282de1` | 2026-10-04 | style(player): 音量浮层四宿主统一，样式与锚点回到原版那条 |
| `b4a97364` | 2026-10-04 | refactor(player): 弹层容器回到按宿主分 |
| `636116d7` | 2026-10-03 | fix(player): 桌面底栏右簇回到贴右 |
| `b7188916` | 2026-10-03 | fix(player): 桌面 OSD 恢复右上角那一簇，换台按宿主分形态 |
| `b0d408e6` | 2026-10-03 | refactor: gen application settings by utils（上游） |
| `88ee03b5` | 2026-10-03 | fix: 完善斗鱼 cookie 管理（上游） |
| `d5b98eae` | 2026-10-03 | fix(player): 弹幕设置注释改口 |
| `4a756974` | 2026-10-03 | fix(player): 弹幕设置的屏蔽入口按 surface 区分 |
| `d1b02d45` | 2026-10-03 | fix(player): 桌面弹幕设置补回屏蔽入口 |
| `e6f33ad1` | 2026-10-03 | test(player): 条带音量颗需要设置替身 |
| `afe4d581` | 2026-10-03 | refactor(player): 多路可选谓词收敛为 controller getter |
| `f90f4f49` | 2026-10-03 | fix(player): 总音量拖到 0 时音量图标显示 volume_off |
| `e626e15b` | 2026-10-03 | fix(liveroom): 压低开关关掉时不渲染比例那行 |
| `47f4b5e2` | 2026-10-03 | fix(multiplay): 画面尺寸按格覆盖随会话收口 |
| `9936e941` | 2026-10-03 | fix(player): 桌面清单类弹层统一成右侧抽屉（spec §3） |
| `ec237ba2` | 2026-10-03 | fix(player): 桌面条带图标回归项目图标族 |
| `1e9c3222` | 2026-10-03 | fix(player): 条带文字按钮可收缩 |
| `743ee9df` | 2026-10-03 | fix(player): 窗口化桌面条带补回渐变遮罩带 |
| `7dae6796` | 2026-10-03 | fix(player): 换台锚定件恒平铺 |
| `1087e0b7` | 2026-10-03 | feat(liveroom): 页级「更多」与视频区条带共用同一份动作清单 |
| `72a798bd` | 2026-10-03 | fix(multiplay): 格子胶囊改紧凑密度，进全屏先聚焦那一路 |
| `641e3049` | 2026-10-03 | fix(multiplay): 格子胶囊用紧凑密度，240 宽不再溢出 |
| `cbd18386` | 2026-10-03 | feat(multiplay): 格子胶囊改由动作 resolver 驱动 |
| `5f612671` | 2026-10-03 | fix(player): 清掉移动分支里永不显示的桌面控件 |
| `05f2521c` | 2026-10-03 | feat(player): 桌面条带改由动作 resolver 驱动 |
| `34f43593` | 2026-10-03 | feat(player): 桌面条带 renderer（PlayerActionBar + 单项 builder） |
| `2a887c12` | 2026-10-03 | fix(multiplay): 画面尺寸的标题与生效范围同谓词 |
| `ca13b5aa` | 2026-10-03 | feat(multiplay): 画面尺寸可按格独立 |
| `9d069bb0` | 2026-10-03 | fix(player): 音量滑条改走 overlay 锚定 |
| `b153e010` | 2026-10-03 | feat(player): 音量三态控件（点击静音/悬停滑条/滚轮微调） |
| `b82791e6` | 2026-10-03 | fix(player): 窗口级动作的状态判断改走页面主格 |
| `95a9861a` | 2026-10-03 | feat(player): 动作执行层与 ⋮ 抽屉、选台锚定浮层 |
| `a202bd3f` | 2026-10-03 | fix(player): 进小窗前退全屏的事件不再污染小窗偏好 |
| `8bc3918b` | 2026-10-03 | fix(player): 小窗还原点改为离开窗口态时采集 |
| `86f82c89` | 2026-10-03 | refactor(multiplay): 压低改为可选后同步相关注释 |
| `57246d95` | 2026-10-03 | feat(multiplay): 非聚焦压低改为默认关的可选行为 |
| `f563ad5a` | 2026-10-03 | refactor(player): 动作清单的 tier 收成单一真相源 |
| `247b8d80` | 2026-10-03 | feat(player): 播放覆盖层动作清单抽成纯 resolver |
| `77eb7864` | 2026-10-03 | feat(multiplay): 音量决策抽成纯函数，压低改为可叠乘因子 |
| `b1df5968` | 2026-10-03 | fix: SC 时间戳对不齐，改由价格&用户名&消息判断去重（上游） |
| `062d5a83` | 2026-10-03 | refactor: 调整项目结构（上游） |
| `5ccd7685` | 2026-10-01 | fix: 保证 SC 列表唯一性（上游） |
| `48011b93` | 2026-10-01 | fix(multiplay): 按 review 收口性能与守卫 |
| `8f7b941e` | 2026-10-01 | fix(multiplay): 返回键改用 maybePop、折叠不再藏起聚焦格 |
| `c08d7914` | 2026-10-01 | chore(tools): 多开性能探针（一次性脚本） |
| `de408209` | 2026-10-01 | feat(multiplay): 关注页批量开多开、卡面可勾选 |
| `f65912ab` | 2026-10-01 | feat(multiplay): 多开棋盘视图与格子控件 |
| `d5f32f7d` | 2026-10-01 | feat(multiplay): 多开播放的共享状态排雷与会话层 |
| `7347f515` | 2026-10-01 | feat(player): Stats 覆盖层可切自绘浮层 / mpv 内置 OSD |
| `ac31401a` | 2026-10-01 | chore(deps): media_kit ref 升到 23ec6b9c |
| `206440f2` | 2026-10-01 | fix(history): 观看时长改为按房间各记一份 |
| `139ea90a` | 2026-09-30 | fix(webdav): 修正单例模式下 webdav 反复拉取（上游） |
| `24b68f30` | 2026-09-30 | fix(danmaku): 大表情最多占两个轨道，聊天区上限降到 150 |
| `5d8f0b38` | 2026-09-30 | fix(danmaku): 表情渲染的尺寸口径、开关与交互健壮性 |
| `aed42c1e` | 2026-09-29 | feat(danmaku): 弹幕与聊天区支持 B 站表情包 |
| `c10c0b8a` | 2026-09-28 | fix(settings): 修复 Android 上「保存日志文件」静默失败 |
| `6b63503c` | 2026-09-28 | fix(android): 修复硬解与视频输出初始化失败导致的黑屏 |
| `01c8ab61` | 2026-09-27 | fix(window): 全屏/小窗进出后最小宽度限制失效 |
| `dec20731` | 2026-09-27 | feat(volume): 音量均衡（loudnorm）与最大音量设置 |
| `abdffe71` | 2026-09-26 | fix(webdav): 修正 cookie 双向同步逻辑（上游） |
| `099d9c26` | 2026-09-25 | release v1.8.14（上游） |
| `c04903cb` | 2026-09-25 | fix(douyu): 参数不能正确保存导致 cookie 失效（上游） |
| `453a01fd` | 2026-09-25 | feat(follow): 搜索胶囊改用搜索页样式 |
| `7c7f3591` | 2026-09-25 | fix(bars): 列表滚不动时滚轮也能驱动顶/底栏 |
| `be48430d` | 2026-09-25 | feat(follow): 选择态入口与分组弹窗标题改为「编辑」 |
| `f8822089` | 2026-09-25 | feat(follow): 顶栏加一键展开/折叠全部分组 |
| `24333bf3` | 2026-09-25 | feat(player): 小窗底部按钮重排，退出按钮改 PIP 图标 |
| `8d9924a7` | 2026-09-25 | fix(player): 小窗双击退出不再残留置顶与纵横比锁定 |
| `0dbb3bd6` | 2026-09-24 | release v1.8.13（上游） |
| `7ba585ee` | 2026-09-24 | fix: 完善 douyu cookie 管理（上游） |
| `90259092` | 2026-09-24 | fix: Windows 下屏幕亮度重置问题 #180（上游） |
| `249ff1b9` | 2026-09-24 | fix(douyu): 额外配置实现 cookie 不过期（上游） |
| `34c39a31` | 2026-09-24 | merge: 合并上游 dev (v1.8.12) 到 future |
| `e17b9239` | 2026-09-24 | feat(follow): 搜索改顶栏图标原位展开 |
| `b95865ac` | 2026-09-23 | feat(follow): 关注页分组视图 + 三页 ViewPager |
| `9199926c` | 2026-09-22 | refactor: 优化部分代码逻辑（上游） |
| `192e22e6` | 2026-09-22 | fix(follow): 统一 follow 业务逻辑 #178（上游） |
| `b492f965` | 2026-09-22 | fix(douyu): 游客模式直播流只能存活 5min（上游） |
| `e53c0825` | 2026-09-21 | feat(glass): 底栏改用 liquid_glass_easy |
| `b5f9e9bd` | 2026-09-21 | fix(window): 修改桌面端最小窗口宽度为 436 |
| `2683e75e` | 2026-09-21 | chore: flutter 3.47.5（上游） |
| `0d26f8d3` | 2026-09-21 | feat: 支持根目录 data_hive_ce 作为项目数据启动目录 #174（上游） |
| `d45cad06` | 2026-09-20 | feat(player): 桌面端小窗播放锁定画面纵横比 |
| `dfa24b29` | 2026-09-19 | fix(player): 修复退出全屏后底部避让失效、导航条压住刷新键 |
| `afc6d8c4` | 2026-09-19 | perf(bars): 滑动收起改为纯绘制，消除每帧重排 |
| `8282b193` | 2026-09-19 | test(follow): 补关注页滑动收起顶栏回归测试 |
| `c9d6f183` | 2026-09-19 | feat(ui): 统一弹出菜单规格，补齐 Tab 跳切动画与滑动收起顶栏 |
| `85d9864e` | 2026-09-18 | release v1.8.12（上游） |
| `334af082` | 2026-09-18 | fix: 全屏播放状态下按钮越界 #173（上游） |
| `a38cbc75` | 2026-09-18 | Merge branch 'dev' into future (upstream v1.8.11) |
| `d9f03181` | 2026-09-18 | chore: fvm 版本对齐 pubspec（3.47.2 → 3.47.4） |
| `378be06b` | 2026-09-18 | release v1.8.11（上游） |
| `88f383cf` | 2026-09-18 | fix(window): 空安全导致的 bug（上游） |
| `899212ba` | 2026-09-18 | Merge branch 'dev' into future |
| `ee085b69` | 2026-09-17 | chore: flutter version 3.47.4（上游） |
| `d4b07a47` | 2026-09-17 | feat: 允许用户通过参数启动应用修改数据目录（上游） |
| `63c1eb8d` | 2026-09-16 | fix: 修复分页、播放器与桌面交互的遗留问题 |
| `c7285bb9` | 2026-09-16 | perf: 优化 ui（上游） |
| `3a8a5efc` | 2026-09-16 | fix(window): 修正启动时最大化功能，防白屏（上游） |
| `cd128383` | 2026-09-16 | refactor: 更清晰垂直的 window 业务逻辑 #134（上游） |
| `b5aaa1bd` | 2026-09-15 | feat: pc 端小窗模式 尺寸/位置 记忆 #171（上游） |
| `d97a033c` | 2026-09-14 | fix: 修正移动端退出全屏逻辑导致的错误（上游） |
| `9b0d4308` | 2026-09-14 | feat: 完善弹幕随屏幕大小放缩功能 #172（上游） |
| `3091f464` | 2026-09-13 | feat: 弹幕字体大小随窗口大小缩放 #172（上游） |
| `e319fd81` | 2026-09-13 | style: dart format /lib（上游） |
| `6f2437f2` | 2026-09-13 | style: follow.watchDuration 字段弃用调整（上游） |
| `a1d31be3` | 2026-09-13 | style: 部分代码复用抽离（上游） |
| `9dfb644e` | 2026-09-12 | fix(windows): 关闭亮度 auto reset 提前到窗口初始化之前 |
| `48aedc9a` | 2026-09-12 | fix: 修正分页、表情与桌面交互的遗留问题 |
| `37ea5361` | 2026-09-11 | fix(windows): 修复拖动窗口边框严重滞后于鼠标 |
| `fb97e0ec` | 2026-09-11 | fix(list): 隐藏的列表状态层停掉 ticker |
| `e79ff0a9` | 2026-09-11 | feat(desktop): 桌面端鼠标交互对齐移动端 |
| `a5e594dc` | 2026-09-11 | feat(danmaku): 弹幕与聊天区支持 B 站表情包，OSD 统计面板收敛为单页 |
| `49eef9c3` | 2026-09-11 | feat(douyin): 抖音推荐流恢复真分页，列表到底给出明确提示 |
| `3e536ca8` | 2026-09-11 | refactor(block): 房间专属关键词和用户名屏蔽（上游） |
| `a10fcb9f` | 2026-09-11 | refactor(block): 实现 live 界面直选屏蔽功能（上游） |
| `e1f7a75c` | 2026-09-11 | feat(list): 分页采信服务端 hasMore，收敛为单一触发路径 |
| `08aace49` | 2026-09-11 | refactor(block): 实现 live_controller 弹幕屏蔽逻辑（上游） |
| `abd56489` | 2026-09-10 | refactor(block): 实现 follow_block 的 WebDAV 同步（上游） |
| `fae186bf` | 2026-09-10 | refactor(block): 构造 follow_user_block 的 model 和 crud（上游） |
| `4e3c35a1` | 2026-09-10 | feat(list): 分页列表改用滚动通知自动加载下一页并补齐加载骨架 |
| `c1f5ae82` | 2026-09-09 | fix(player): 调整直播缓存策略并新增 mpv 属性回读日志 |
| `7865964d` | 2026-09-09 | feat(player): 播放器 OSD 统计浮层改为 Flutter 自绘 |
| `8af872e6` | 2026-08-31 | feat(nav): 新增悬浮玻璃导航栏并整合为悬浮胶囊 |
| `82e61c8d` | 2026-08-29 | fix(windows): Windows 标题栏跟随应用内主题与系统深浅色 |
| `d1978333` | 2026-08-31 | feat(home): 首页顶/底栏随列表滑动收起 |
| `192f77ea` | 2026-08-31 | fix(player): 全屏弹窗无响应与退出直播间崩溃 |
| `73e5898d` | 2026-08-09 | feat(player): 复制直链按钮改为图标按钮 |
| `de601e3c` | 2026-08-09 | feat(player): 清晰度选择弹窗支持复制线路直链 |
| `93bea52d` | 2026-08-09 | fix(player): 移除全屏模式下冗余的全屏按钮 |
| `03d66eb7` | 2026-09-08 | perf(webdav): 补充同步项的可选择功能（上游） |
| `48fa02cb` | 2026-09-06 | feat: 允许禁用「滑动调节亮度/音量」#167（上游） |
| `1fac4d68` | 2026-09-04 | fix(ci): lock version of auto_orientation_v2（上游） |
| `0c1c4d46` | 2026-09-03 | style: migrate deprecated API usages（上游） |
| `1773c426` | 2026-09-03 | chore: migrate easy_refresh（上游） |
| `1e3566a3` | 2026-09-03 | chore: upgrade plugins（上游） |
| `3fff9ef4` | 2026-09-02 | fix: 迁移 material_ui 中的弹窗 bug #169（上游） |
| `0c4fbf83` | 2026-09-01 | fix(core): increase huya-sc fetch limit 10→50（上游） |
| `51ebd945` | 2026-08-31 | chore: SC 排列方式调整为最新消息在最上方（上游） |
| `c7a587d3` | 2026-08-30 | fix(ci): temp use getx_material_ui base on 4.7.3（上游） |
| `a0985b3a` | 2026-08-30 | chore: migrate to material_ui（上游） |
| `cb2f3a9f` | 2026-08-29 | chore: upgrade flutter to 3.47.2（上游） |
| `8b40850f` | 2026-08-21 | chore: upgrade flutter to 3.47.1（上游） |
| `72e00adb` | 2026-08-17 | feat(core): support huya super chat (test)（上游） |
| `542acd47` | 2026-08-16 | chore: upgrade flutter to 3.47.0（上游） |
| `251b012d` | 2026-08-04 | fix(ios): iOS Deployment Target 15.0（上游） |
| `9bdc5f10` | 2026-08-01 | chore: bump flutter v3.44.8（上游） |
| `78c2d7eb` | 2026-08-01 | chore: update plugins for flutter v3.44.x（上游） |
| `02ef8c83` | 2026-07-31 | chore: sync media_kit version（上游） |
| `44f50480` | 2026-07-30 | feat(follow): init follow.lastWatchTime on first launch（上游） |
| `8b394ab1` | 2026-07-30 | feat(follow): logic of dormant（上游） |
| `5d84e5ef` | 2026-07-30 | feat(follow): add dormancy_threshold.setting（上游） |
| `543910ba` | 2026-07-30 | feat(follow): add follow_user.last_watch_time（根提交） |

### 2.3 2026-10-12 同步上游 dev(v1.8.15)（merge `abca65f8`）

`future` 在 2026-10-12 把上游 `origin/dev`（`fork-parent/dev`，SlotSun，v1.8.15）并入，
合并提交 `abca65f8`（当时的分支 HEAD，现被 §2.4/§2.5 两批覆盖；父提交 `3714eec1` + `70b1d18f`）。
`git log --oneline 3714eec1..abca65f8` → **14 条**（13 条非合并 + 1 条合并）；
`-- simple_live_app` 命中 12 条（history simplification 略去 2 条）。
app 版本号随之 `1.8.14+10814` → **`1.8.15+10815`**（`pubspec.yaml:2`）。

13 条上游非合并提交按功能聚三类：

| 聚类 | 提交（hash · 日期） | 对 app 的影响 |
| --- | --- | --- |
| **账号登录迁 core**（10 条） | `e3a090ad`(10-10) `3a4ddb70`(10-10) `b5967198`(10-10) `c690e5f3`(10-10) `e88268c6`(10-10) `b3451ace`(10-11) `e3f67344`(10-11) `9abf40ff`(10-11) `aa5f8073`(10-11) `70b1d18f`(10-11) | 账号体系从 app 整体搬进 core：删 `services/bilibili_account_service.dart`；新增 `models/db/account.dart`（Hive typeId 8）与 `DBService.accountBox`；QR/Web 登录改走 core 的 `getQRCode`/`getQRPollResult`/`getAccountInfo`；`platform_service.dart` 改为 `accountList` 遍历 + `setSiteAttrs(jsonEncode(...))`；webdav 新增账号资源 |
| **格式统一** | `63a3055c`(10-11) | 全库 `dart format .`（app 侧文件同批重排；core 侧分类口径见 `simple_live_core/doc/update-history.md` §4） |
| **fvm 3.47.6** | `6847a151`(10-09) | `.fvmrc` 3.47.5 → 3.47.6（`pubspec.yaml:7` 同步） |
| **media_kit 版本同步** | `80e1a096`(10-09) | 上游把 media_kit 指向 `SlotSun/media-kit@b2bb9ff0…`；**本 fork 未采用**，见下方冲突口径 |

#### 冲突解决口径（本 fork 的取舍，均已核实）

- **media_kit / `dependency_overrides` 保留 gaoxing64 fork 钉版**：`pubspec.yaml:99-160` 六处
  仍指 `github.com/gaoxing64/media-kit@23ec6b9c…`（音量均衡 loudnorm 供应链依赖它），
  上游改用 `SlotSun/media-kit@b2bb9ff0…` 的改动被丢弃。
- **表情渲染门禁保留 fork 实现**：fork 无开关、始终渲染；上游 dev 的 `danmuEmoticonEnable`
  开关**未被采用**（`git grep danmuEmoticonEnable -- simple_live_app/lib` 无命中）。
- **多开批量入口保留 fork**：`LiveRoomRouteArgs.together`（`live_room_route_args.dart:22,29`）
  与 `LiveRoomController.together`（`live_room_controller.dart:67,74,325-328`）为本 fork 实现。
- **按格弹幕字号保留 fork**：`!isSecondaryTile` 分支（`live_room_controller.dart:308-315`），
  多开时让位给 MultiPlaySession 的按格缩放。
- **`room`（focus 格）控制器保留 fork 实现**（多开聚焦格语义）。
- **`app_navigation.dart` 适配改写**：旧 `BiliBiliAccountService` 已随迁移删除，`_biliBiliLogined()`
  改为 `DBService.instance.getAllAccounts()` 按 `siteId == Constant.kBiliBili && isActive` 判断
  （`app_navigation.dart:71-75`）；同时补回被合并丢掉的一组 imports。
- **6 个测试假件 `onInit` 签名修复**：`void onInit()` → `Future<void> onInit() async {}`
  （`AppSettingsController.onInit` 早已是 async，`app_settings_controller.dart:76`；HEAD 起这些
  测试文件因签名不匹配而**编译失败**，本次顺带修复）。涉及 `follow_test_harness.dart`、
  `desktop_scroll_behavior_test.dart`、`follow_user_sections_test.dart`、`home_site_id_test.dart`、
  `indexed_jump_transition_test.dart`、`page_view_auto_load_test.dart`。
- **`pubspec.lock`**：取 fork 版后由 `flutter pub get` 重建。

#### 适配与验证

- `git diff --stat 3714eec1 abca65f8 -- simple_live_app` → **53 个文件，+767/-885**（其中 `lib/` 37 个）。
- `flutter analyze`：app 代码**无 error**；仅 `rust_builder/cargokit/build_tool/**` 有 **43 个存量 error**
  （该目录未被合并触及，`analysis_options.yaml` 未排除它，见 backlog P2）。
- `flutter test`：**473 通过 / 18 失败**（共 491 条执行）。18 个失败分布在 6 个文件：
  `search_initial_site_test.dart`(9)、`follow_grouped_view_test.dart`(4)、`theme_mode_test.dart`(2)、
  `page_view_auto_load_test.dart`(1)、`viewpager_drag_test.dart`(1)、`widget_test.dart`(1)。失败性质：
  这些文件在 HEAD 时因上述 `onInit` 签名问题**根本无法编译**（用 worktree 在 HEAD 复现到 `loading [E]`
  编译错误）；修签名后暴露的失败含真实 `AppSettingsController.onInit` → `initDataPath()` →
  `getApplicationSupportDirectory()` 在 widget test 抛 `MissingPluginException`、`live_room_card.dart`
  1px overflow、关注页部分断言找不到控件。相关 app 代码合并没有改过，属**存量问题**
  （详见 backlog P1、test-suite.md）。
- 分支关系：`git rev-list --left-right --count origin/dev...future` → **`0 118`**。

### 2.4 2026-10-12 关注多分组归属 + 一键按平台智能分组（11 条，gaoxing64）

`git log --oneline abca65f8..8fd14a9f` → **11 条**，全部 2026-10-12、作者一律 `gaoxing64`；
其中 10 条触及 `simple_live_app`（`8fd14a9f` 只写 `specs/`）。
`git diff --stat abca65f8 8fd14a9f -- simple_live_app` → **26 个文件，+1797/-330**
（`lib/` 19 个 + `test/` 7 个）。

**权威设计文档**：`specs/2026-10-12-multi-membership-and-smart-grouping-plan.md`
（10 个 Task + 文末「附录：实施偏离记录」A1~A5/B1~B8/C），
`specs/2026-10-12-multi-membership-and-smart-grouping-pr.md`（用户可见变化、兼容性承诺、手工验收清单）。

按功能子聚类（Task 号取自计划文档）：

| 子聚类 | 提交（Task） | 内容 |
| --- | --- | --- |
| **归属真源立起来** | `7c895e6d`(T1) `5890641e`(T2) | 一次性把旧库 `FollowUser.tag` 灌进 `FollowUserTag.userId`（`migration_service.dart` +39、`db_service.dart` 新增 `replaceAllFollowTags:72`）；`FollowService` 补 `userTagNamesOf:127`/`userTagsOf:133`/`addUserToTag:148`/`removeUserFromTag:163`/`removeAllTagsFromUser:175` 五个归属 API，`FollowUserTag.contains:53`/`addMember:56` |
| **读侧翻转** | `6c7632e2`(T3) | `FollowUserController.groupedView` 改为先按成员表建 `userId → 分组 id[]` 桶再切（`follow_user_controller.dart:147-180`），一个关注出现在它的**每个**所属分组里 |
| **写侧翻转** | `a225e3b4`(T4) | 拖入 / 勾选批量移入 / 快速分组 sheet / 详情页保存一律改走归属 API（`reassignSelected`→`addUserToTag`，`follow_user_controller.dart:319`）；`FollowUser.tag` 降级为「主分组缓存」；批量结束后只 `liveListSort()` 一次 |
| **兼容层** | `0442f4ac`(T6) | 导出 JSON 同带 `tag`（旧版本只认它）与 `tags` 数组（`follow_service.dart:726-748`）；导入两键都认（`:750-775`）；WebDAV `FollowSyncResource.merge` 改为按**分组名并集**合并成员表、按存活关注 id 过滤幽灵、再用 `FractionalIndexing` 重发分组 id（`follow_sync_resource.dart:99-133`） |
| **UI 语义对齐** | `6cf66e3f`(T5) | 拖拽「同组」判据改看成员表（`follow_group_card.dart:72`、`follow_user_page.dart:833`）；详情页「所属分组」单选下拉→多选 chips（`follow_info_page.dart:107-124`）；行副标题展示全部分组名（`follow_user_item.dart:158-164`） |
| **删冷字段（breaking）** | `3267a04e`(T7) | 见 §3.22 |
| **智能分组（阶段二）** | `53b70b83`(T8) `3c8a34c4`(缺陷) `3b86b496`(T9) | 新增纯逻辑 `SmartGroupService`（`smart_group_service.dart:16`，`preview:20` 只算不改 / `execute:54` 落库 / `_orderedSiteIds:104`）；`3c8a34c4` 修「`siteSort` 不全时把缺失平台误算成未知平台」；`3b86b496` 加确认弹窗 `smart_group_preview_sheet.dart`（`showSmartGroupPreview:169`、顶层 `startSmartGrouping:199`）与两处入口：关注页顶栏 ⋮（`follow_user_page.dart:238-248` + `onSelected:279` → `controller.runSmartGrouping()`，`follow_user_controller.dart:490`）、关注设置页「分组管理」卡片（`follow_app_settings_page.dart:48-55`）；`main.dart:124` 注册服务 |
| **文档回写** | `8fd14a9f` | 计划文末补「实施偏离记录」，新增 PR 说明与手工验收清单；不动代码 |

> 测试基线随这批变化：`test/` 净 +3 个文件（`follow_membership_test.dart`、
> `smart_group_service_test.dart`、`follow_smart_group_ui_test.dart`）、静态声明 465→496，
> 全量 `flutter test` 由 473/18 变为 **507 通过 / 15 失败**（见 test-suite.md §2/§7）。

### 2.5 2026-10-14 同步上游 dev（merge `5ae375f1`）

`future` 在 2026-10-14 把 `origin/dev` 的 5 条提交并入；合并提交 `5ae375f1`
（父：`8fd14a9f` + `f8318694`），**无冲突**。
`git log --oneline 8fd14a9f..HEAD` → 6 条（5 上游 + 1 合并）；
`git rev-list --count --first-parent abca65f8..HEAD` → **12**（11 条关注线 + 本次合并），
`git rev-list --count abca65f8..HEAD` → **17**（含上游 5 条）。

| 上游提交 | 日期 | 内容 | 触及 |
| --- | --- | --- | --- |
| `57d8f86d` fix(bili): 迁移到 Account cookie 不生效 | 10-12 | core `BiliBiliSite.setSiteAttrs` 由 `cookie = data` 改为 `jsonDecode(data)` 后取 `map['cookie']`（`bilibili_site.dart:553-558`）——B 站与其他平台同走「`jsonEncode` 一个 map」的口径；app 侧 1 行（见下） | core + app |
| `03c4493a` fix(bili): 补充弹幕 cookie 需要配对的 uid | 10-12 | core `getAccountInfo` 校验成功后回填 `userId = info.mid!`（`bilibili_site.dart:613,622`，弹幕 `danmaku_arg` 需要配对 uid） | 仅 core |
| `6da36e04` feat(tv): 支持斗鱼扫码登录 | 10-13 | TV 端 | 不触及 app |
| `bafc703b` ci: prebuild tv_app v1.5.1 | 10-14 | CI 预构建 | 不触及 app |
| `f8318694` Update Crowdin configuration file | 10-14 | 翻译配置 | 不触及 app |

**app 侧唯一改动**（`git diff 8fd14a9f..HEAD -- simple_live_app` → 1 文件 1 行）：
`PlatformService.accountLogout`（`platform_service.dart:41-50`）里 `copyWith` 的
`siteId: ac.siteId` 换成 `userName: ''`（`platform_service.dart:44`）——退出登录时连账号名一起清掉，
不再只清 `credential` 而留下旧用户名显示。行为面与 `57d8f86d` 的 cookie 口径配套，本 fork 无取舍。

**验证**：合并后 `fvm flutter test --no-pub` **507 通过 / 15 失败**，与合并前（`8fd14a9f`）
逐条同名单（条数与失败用例名一致），**零回归**（红灯构成见 test-suite.md §7）。
分支关系：`git rev-list --left-right --count origin/dev...future` → **`0 130`**。

---

## 3. fork 自研提交详解（gaoxing64，22 条）

### 3.1 `e374b4df` feat(android): 媒体前台服务、通知与耳机键的原生接线（2026-10-09）

- **背景**：改前 `AndroidManifest.xml` 连一个 `<service>` 都没有——无前台服务、无
  `MediaSession`、无 `WAKE_LOCK`、无音频焦点；targetSdk 37 下进程随时被挂起/回收，
  别的 app 一出声就与我们混音。
- **改动**：manifest 补 `FOREGROUND_SERVICE(_MEDIA_PLAYBACK)`、`WAKE_LOCK`、
  `AudioService` 声明；`MainActivity.kt` 换 `AudioServiceActivity` 父类；
  新增通知图标 `res/drawable/ic_stat_slive.xml` 与 `res/raw/keep.xml`（钉住自定义图标，
  防 `shrinkResources` 误剥）；`proguard-rules.pro` 补规则。
- **涉及文件**：`android/app/src/main/AndroidManifest.xml`、`MainActivity.kt`、
  `res/drawable/ic_stat_slive.xml`、`res/raw/keep.xml`、`proguard-rules.pro`（+77/-4）。
- **测试**：无自动化，交真机验收（PiP 回归是换父类的唯一风险面：进出 `floating` 小窗、点通知回 app、进程被杀后从通知冷启动）。
- **影响/残留**：Android 12+ 后台起前台服务可能抛
  `ForegroundServiceStartNotAllowedException`（插件无 try/catch）；靠 handler 闸 +
  通知播放键 PendingIntent 缓解，真机待确认（详见 backlog P0-2）。

### 3.2 `5692db16` feat(live_room): 直播间那一路挂到系统媒体控制上（2026-10-09）

- **背景**：`audio_service` 只是投影面，出声的自始至终是 media_kit/libmpv；
  需要一个唯一入口把播放状态镜像到通知栏/锁屏/耳机键。
- **改动**：`LiveRoomController` 实现 `LivePlaybackTarget`，`syncBackgroundPlayback()`
  为幂等唯一入口（`attach`/`detach`），随 `player.stream.playing/buffering/completed`
  跳变；副格（`isSecondaryTile`）永不挂载——多开四路争一条通知只会互相顶掉。
- **涉及文件**：`live_room_controller.dart`（+167）、`live_room_page.dart`、
  `multi_play_tile.dart`、`player_controller.dart`（+183/-6）。
- **测试**：无；真机验收覆盖 Home/熄屏/锁屏/耳机键/拔耳机。
- **影响/残留**：多开时通知只代表页面主格那一路（二期跟随聚焦格）。

### 3.3 `cd89ecdc` feat(playback): audio_service handler 与音频会话（2026-10-09）

- **背景**：`services/` 绝不 import `modules/`，需要一个抽象切断依赖环；且
  `audio_service 0.18.19` 不管音频焦点、从不 `configure()` 会话（读包源码确认）。
- **改动**：新增 `LivePlaybackTarget`（抽象）、`LivePlaybackAudioHandler`
  （`BaseAudioHandler`，主 isolate）、`LiveAudioSession`（iOS 类别 `playback` /
  Android `requestAudioFocus`、中断/拔耳机）。handler 自写 `_publishIdle()`
  而非 `super.stop()`（后者只落 `processingState=idle`、不动 `playing`）。
- **涉及文件**：新增 `lib/services/playback/live_playback_target.dart`（50）、
  `live_playback_audio_handler.dart`（301）、`live_audio_session.dart`（120）；
  `main.dart` 挂 `AudioService.init`（+475）。
- **测试**：无自动化。
- **影响/残留**：语义决定（有意为之）——不发「上/下一首」、不发 seek/duration
  （不画进度条）、通知「停止」= 暂停+撤通知（不是 `player.stop()`）；理由与其余语义决定见 backlog §5「已决策的取舍」。

### 3.4 `cbb474ee` feat(settings):「后台播放」开关，与「进入后台自动暂停」双向互斥（2026-10-09）

- **背景**：两者同时开会互相顶掉，「后台播放」名存实亡；开关仅移动端显示。
- **改动**：`AppSettingsController` 两个 setter 强制互斥并各自落盘；
  UI 用 `SettingsSwitch` 的 `locked` + `lockedHint` 把被顶掉的一项锁上并说明原因；
  新增 `EventBus` 事件与存储键。
- **涉及文件**：`app_settings_controller.dart`（+44）、`event_bus.dart`、
  `modules/settings/play_settings_page.dart`（+46）、`local_storage_service.dart`（+99）。
- **测试**：无自动化，手测项为「开 A 时 B 被锁、开 B 会关掉 A 并落盘、重启后状态一致」。

### 3.5 `efa33716` build(deps): 引入 audio_service 0.18.19 与 audio_session 0.2.4（2026-10-09）

- 钉**精确版本**（不用 `^`），因为四条前提是逐条读包源码定下的（handler 跑主
  isolate、无 `requestAudioFocus`、`stop()` 不动 `playing`、
  `assert(!androidNotificationOngoing || androidStopForegroundOnPause)`）；
  bump 版本须重验四条。见 `simple_live_app/pubspec.yaml:115-128`。

### 3.6 `12ab0c42` feat(live_room): 直播间播放器快捷键，可改键/禁用/恢复默认（2026-10-11）

- **背景**：原快捷键硬编码（`docs/user.md` 列了默认键表），不可改键。
- **改动**：新增 `player_shortcuts.dart`（318，动作→键）、`shortcut_binding.dart`
  （449，绑定模型/冲突检测/持久化）、`shortcut_settings_page.dart`（211）、
  `shortcut_capture_dialog.dart`（333）；`Esc` 三级语义（关弹窗→退全屏/小窗→离开直播间）；
  `Tab` 与纯修饰键不可绑；两动作不可绑同键。
- **涉及文件**：上述 4 新增 + `live_room_page.dart`（+254）、`app_settings_controller.dart`
  （+83）、`main.dart`（+70）、`live_room_controller.dart`、`utils.dart`、
  `play_settings_page.dart`、`routes/*`、`local_storage_service.dart`（+2186/-97）。
- **测试**：`test/player_shortcuts_test.dart`（188）、`shortcut_binding_test.dart`（305）。

### 3.7 `afd18194` feat(multiplay): 多开从「模式」改成「动作」（2026-10-11）

- **背景**：多开原是一个全局「模式」，进入后整页布局切换；作者改为把它当成一个
  「动作」——在关注页/直播间当场把房间加进多开会话。
- **改动**：`multi_play_session.dart`/`multi_play_selection.dart` 调整；
  `live_room_page.dart` 大改（+291 行级）；新增 `multi_play_layout.dart`、
  `follow_user_item.dart` trailing 图标对齐。
- **涉及文件**：11 个（含 3 个测试），+504/-160。
- **测试**：`follow_user_item_trailing_test.dart`、`multi_play_layout_test.dart`、
  `multi_play_selection_test.dart`。

### 3.8 `5e5f1009` fix(player): 音量浮层静音双向、拖动滑条也浮出读数（2026-10-11）

- **背景**：音量浮层「静音」只有单向反馈；拖滑条时看不到数值。
- **改动**：`player_volume_action.dart` 修静音双向与拖动读数（+36）；
  新增 `test/player_volume_action_test.dart`（161）。
- 影响面小，是 10-03 OSD 统一设计的收尾。

### 3.9 `c71da474` fix(player): restore window after fullscreen exit（2026-10-11）

- **背景**：全屏退出后窗口未恢复到进全屏前的尺寸/位置（对齐 spec §7 的几何链）。
- **改动**：`main.dart`（+13）与 `player_controller.dart`（+42/-10）修正窗口几何；
  新增 `test/player_window_geometry_test.dart`（165）。

### 3.10 `e250ceb6` feat(navbar): 悬浮底栏换成 FlClash lens 底栏，移除 Liquid Glass（2026-10-06）

- **背景**：08-31 引入的悬浮玻璃导航栏（`floating_navigation_bar.dart`，855 行）
  在 09-21 改用 `liquid_glass_easy`；作者最终判定改为 FlClash 的 lens 底栏。
- **改动**：删除 `floating_navigation_bar.dart`（-1051）、`liquid_glass_nav_defaults.dart`
  （-193）与整套 glass_debug 调试页（-600）；新增 `navigation_dock.dart`（+1452）
  与 `test/navigation_dock_test.dart`（+487）；清理 pubspec 依赖与路由。
- **涉及文件**：18 个，+2017/-2551（净删约 500 行）。

### 3.11 `fcb43a82` feat(multiplay): 多开播放落到移动端（2026-10-04）

- **背景**：多开此前只服务桌面；移动端需要竖屏 1×2、横屏全屏 2×2。
- **改动**：`multi_play_grid.dart`/`multi_play_session.dart`/`live_room_page.dart`
  （+195）；`player_action_views.dart`（+139）与 `player_volume_action.dart` 加触屏适配。
- **涉及文件**：10 个，+468/-159；测试 `player_volume_action_test.dart`（+56）。
- 前一步 `1826c57b`（10-04）是先落**地基**：触屏判据与竖屏视频区高度。

### 3.12 `b95865ac` feat(follow): 关注页分组视图 + 三页 ViewPager（2026-09-23）

- **背景**：关注页原为单列表 + 顶部 tag；重构为「全部/直播中/未开播」三页 ViewPager
  并引入分组（tag）管理。
- **改动**：新增 `follow_tag_manager.dart`（241）、`widgets/follow_group_card.dart`（289）、
  `follow_member_row.dart`（254）、`follow_quick_group_sheet.dart`（233）；
  `follow_user_page.dart` 大改（837 行级）、`follow_user_controller.dart`（+318）、
  `services/follow_service.dart`、`page_grid_view.dart`。
- **涉及文件**：20 个（含 `collapsible_top_bar_follow_test.dart`）。
- **后续**：`e17b9239`（搜索顶栏原位展开）、`f8822089`（一键展开/折叠全部分组）、
  `be48430d`（编辑态）、`453a01fd`（搜索胶囊对齐搜索页）四轮打磨。

### 3.13 `e1f7a75c` feat(list): 分页采信服务端 hasMore（2026-09-11）

- **背景**：`LiveCategoryResult.hasMore` 各平台都算好了，但 App 层从未读取，
  `_doLoad` 只用「本页是否为空」判定（见 `page-loading-diagnosis.md` §三）。
- **改动**：`BasePageController` 新增 `serverHasMore`（默认 null 退回旧行为）与
  `itemKey`（去重键）；`canLoadMore = result.isNotEmpty && serverMore && !duplicated`；
  core 侧 `getRecommendRooms/getCategoryRooms` 新增可选 `int? pageSize`。
- **涉及文件**：app `base_controller.dart`、`home_list_controller.dart`、
  `category_detail_controller.dart` + core 5 平台 + 版本号 1.0.4→1.1.0。
- **测试**：`test/base_page_controller_paging_test.dart` 新增 6 条。
- **残留**：搜索页未接通（四平台 `hasMore` 语义不一致，见 `p1-paging-verification.md` §五）。

### 3.14 `49eef9c3` feat(douyin): 抖音推荐流恢复真分页（2026-09-11）

- **背景**：`webcast/feed/` 实测**不是分页接口**——count/offset/cursor 全被忽略、
  恒返回当前热门 Top 20（真实 ttwid 穷举验证，见 `p1-paging-verification.md` §二）。
- **改动**：首屏改**并发扇出**（`_recommendFanout()` = `ceil(pageSize/20)` 落在
  `[4,6]`），每路换个 `count` 参数（参数不同重叠更小），按 `roomId` 合并去重；
  容错：任一片失败不影响其余，全失败才抛 `CoreError`。
- **涉及文件**：core `douyin_site.dart`（新增 `kFeedSliceSize`/`kMinFeedFanout`/`kMaxFeedFanout`）。
- **测试**：`test/douyin_recommend_fanout_test.dart`（8 例）。
- **残留**：热门池只 ~45-65 间 → 首屏 `hasMore` 恒 true 交续接页；并发收益 6 路饱和。

### 3.15 `a5e594dc` → `aed42c1e` → `5d8f0b38` → `24b68f30` B 站表情包（2026-09-11 ~ 09-30）

- **背景**：B 站表情包弹幕在 message 里下发占位符文本（`[doge]`），图片另放在载荷
  里；`aed42c1e`（09-29）与 core 侧 `3d237b0e` 对齐真实载荷。
- **改动**：`a5e594dc` 落 app 侧渲染骨架 + OSD 统计面板收敛为单页；
  `5d8f0b38`（09-30）修渲染尺寸口径、开关与交互健壮性；
  `24b68f30`（09-30）大表情最多占两个轨道、聊天区消息上限降到 150。
- **涉及文件**：`lib/modules/live_room/danmaku/chat_emoticon_span.dart`、
  `danmaku_emoticon.dart`、`live_room_controller.dart`。
- **测试**：`test/chat_emoticon_span_test.dart`、`test/danmaku_emoticon_test.dart`。

### 3.16 `4e3c35a1` feat(list): 分页列表改用滚动通知自动加载并补骨架（2026-09-10）

- **背景**：「内容不满一屏时三项滚动指标无变化、通知不派发」导致停在前几行；
  加载策略从「等通知」改为「补到位」（`page-loading-diagnosis.md`）。
- **改动**：新增 `page_auto_load.dart`（`AutoLoadOnScroll` 改 Stateful +
  `addPostFrameCallback` 主动补页）、`skeleton.dart`、`system_ui_inset.dart`；
  `base_controller.dart` 分页状态机；两个 page_view 显式传 `scrollController`
  （修复 `EasyRefresh` 只监听不注入导致的 `hasClients` 恒 false 真 bug）。
- **涉及文件**：19 个，+1738/-66；测试 `page_view_auto_load_test.dart`（586）、
  `page_view_skeleton_test.dart`（353）、`system_ui_inset_test.dart`（132）、
  `net_image_size_test.dart`。

### 3.17 `8af872e6` feat(nav): 新增悬浮玻璃导航栏并整合为悬浮胶囊（2026-08-31）

- **改动**：新增 `widgets/floating_navigation_bar.dart`（855）、glass_debug 调试页；
  `main.dart`（+134）、`indexed_page.dart`、`appstyle_setting_page.dart`。
- **涉及文件**：16 个，+1603/-126；测试 `floating_navigation_bar_test.dart`（107）。
- **演进**：`e53c0825`（09-21，改用 `liquid_glass_easy`）→ `e250ceb6`（10-06，
  整体换成 FlClash lens，删除本提交产物）。

### 3.18 `d1978333` feat(home): 首页顶/底栏随列表滑动收起，收起类型支持即时/同步（2026-08-31）

- **改动**：顶/底栏随列表滑动收起，收起类型可配「即时/同步」；是后续
  `c9d6f183`（统一弹出菜单规格 + 滑动收起顶栏）、`afc6d8c4`（滑动收起改纯绘制、
  消除每帧重排）、`7c7f3591`（滚轮也能驱动顶/底栏）的起点。

### 3.19 `77eb7864` feat(multiplay): 音量决策抽成纯函数（2026-10-03）

- **背景**：音量规则被四处入口改（焦点、总音量滑条、该格滚轮、压低开关），内联在
  `LiveRoomController.resolveTargetVolume` 里无法测真值（spec §5）。
- **改动**：新增 `multi_play/multi_play_volume.dart` 的 `resolveTileVolume(...)`；
  焦点不再直接决定音量，压低只在开启时把 `duckRatio` 乘进去（默认关）。
- **测试**：`test/multi_play_volume_test.dart` 真值表（含「恒不超过总音量」与静音四态）。

### 3.20 `a225e3b4` feat(follow): 翻转写路径——UI 操作改走多归属 API（2026-10-12）

- **背景**：`5890641e` 立好归属 API、`6c7632e2` 翻好读侧之后，写侧仍一律走旧的
  `FollowService.setFollowTag(user, tag)`——一次只认一个分组，多归属写不进去。
  这批把「拖入分组 / 勾选批量移入 / 快速分组 sheet / 关注设置页分组」四个入口整体改道。
- **改动**：控制器侧新增/改写为按成员表操作（`follow_user_controller.dart` +69/−79；
  勾选批量移入 `reassignSelected` 现逐条 `FollowService.instance.addUserToTag(user, target.tag)`
  再收尾排一次序，`follow_user_controller.dart:307-327`）；服务侧 `follow_service.dart` +39/−86，
  `setFollowTag` 退化为「主分组缓存」的过渡壳（留在本批以保编译，`3267a04e` 才删）；
  `follow_app_settings_controller.dart`（+1/−6）跟着改道。**语义变化**：移入 = **加入**，
  原分组身份保留（不是「移动」）。
- **涉及文件**：5 个（lib 3 + test 2），+174/-171（`git show --stat a225e3b4`）。
- **测试**：`follow_grouped_view_test.dart` +29（多归属断言）、`follow_test_harness.dart` +36
  （假 `FollowService` 补成员表实现）。

### 3.21 `0442f4ac` feat(follow): 备份与 WebDAV 兼容多分组（2026-10-12）

- **背景**：分组归属一旦多值，两条对外契约立刻失效——① 导出的备份旧版本 app 要还能读；
  ② WebDAV 旧合并按分组覆盖，两台设备各加一个组会互相抹掉多归属。
- **改动**：`generateJson` 每条记录同带 `"tag"`（主分组，由 `userTagNamesOf(...).firstOrNull ?? '全部'`
  派生）与 `"tags"`（全量归属数组），`follow_service.dart:726-747`；`inputJson` 先认 `tags` 数组、
  没有则回退单个 `tag`，空串与哨兵 `'全部'` 跳过，缺组先建组，`follow_service.dart:750-774`。
  WebDAV 侧 `FollowSyncResource.merge` 改为**按分组名取成员并集**（不是覆盖）：本地与远端同名组
  合并 `userId` 集合，再按存活关注 id 过滤幽灵与墓碑，最后用 `FractionalIndexing.generateKeyBetween`
  顺序重发分组 id，`follow_sync_resource.dart:99-133`。
- **涉及文件**：3 个，+259/-14（`git show --stat 0442f4ac`）。
- **测试**：`follow_membership_test.dart` +226——`group('JSON 导出导入')`、
  `group('备份向后兼容')`（旧备份→新、新备份→旧、导出导入往返 3 条）、
  `group('WebDAV 合并')`（并集保住多归属、剔除幽灵与墓碑 2 条）。

### 3.22 `3267a04e` refactor(follow)!: 删除 FollowUser.tag 冷字段（2026-10-12，breaking）

- **背景**：`a225e3b4` 之后 `FollowUser.tag` 只剩「主分组缓存」一个身份，读侧已全部走成员表；
  留着它就有两份真源，任何写入顺序问题都会让两者漂移。提交带 `!`：Hive 字段布局变更。
- **改动**：`models/db/follow_user.dart` 删 `@HiveField(7) String tag`（`:50-53` 留注释说明
  旧记录 field 7 读取时被忽略、旧版本 app 读新记录回退 `'全部'`、成员表在 `tagBox` 里不受影响），
  同步重生成 `follow_user.g.dart`；`toJson`/`fromJson` 去掉 `tag` 键；收掉 `FollowService.setFollowTag`
  过渡壳与已无调用方的 `getTagOptionsWithAll()`；删
  `MigrationService.migrateTagMembership`（v1.8.16 的一次性回填已无源可读，
  原地留一句 `// 无需再回填（历史迁移见 git blame: migrateTagMembership）`，`migration_service.dart:160`）；
  详情页/控制器/行组件三处读归属改 `userTagNamesOf`。导出侧**刻意保留** `"tag"` 键（由真源派生），
  向后兼容不破（见 §3.21）。
- **涉及文件**：13 个，+94/-282（`git show --stat 3267a04e`；lib 7 + test 6）。
  两处收口规模：`follow_service.dart` +6/−53、`migration_service.dart` +4/−53。
- **测试**：`follow_membership_test.dart` +32/−97（缓存一致性用例随字段消失），
  `follow_user_sections_test.dart` 一条用例改名「按成员表分桶；不在任何成员表里的落未分组」
  （「孤儿 tag 名」概念已不存在，行为断言未变）；`viewpager_drag_test.dart` 随字段删除改种子数据。
- **影响/残留**：降级到旧版本 app 时**分组归属在旧版本看来丢失**（显式记入 PR 兼容性一节，
  不要在降级期间做「清理数据 / 重建分组」）；重新升级后归属自动回来。

## 4. 上游演化脉络（SlotSun，future 上的 app 侧上游提交）

上游在 v1.8.x 系列的 app 侧演进，按阶段归纳：

| 阶段 | 时间窗 | 关键提交 | 演进 |
| --- | --- | --- | --- |
| 关注功能铺垫 | 07-30 | `543910ba` `5d84e5ef` `8b394ab1` `44f50480` | follow 增加 `last_watch_time`、潜伏期（dormant）逻辑与阈值设置 |
| 工具链爬升 | 07-31 ~ 09-04 | `9bdc5f10` `cb2f3a9f` `ee085b69` `2683e75e` | Flutter 3.44.8→3.47.5、插件跟随、`auto_orientation_v2` 钉版 |
| 框架迁移 | 08-30 ~ 09-03 | `a0985b3a` `3fff9ef4` `1e3566a3` `1773c426` `0c1c4d46` | `getx_material_ui`→`material_ui`、easy_refresh 迁移、弃用 API 清理 |
| 窗口重构 | 09-14 ~ 09-18 | `b5aaa1bd` `cd128383` `3a8a5efc` `334af082` `88f383cf` | PC 小窗尺寸/位置记忆 #171、最大化记忆 #134、防白屏、全屏按钮越界 #173 |
| 弹幕缩放 | 09-13 ~ 09-14 | `3091f464` `9b0d4308` `d97a033c` | 弹幕字体随窗口缩放 #172、移动端退全屏修正 |
| 屏蔽功能 | 09-10 ~ 09-11 | `fae186bf` `abd56489` `3e536ca8` `a10fcb9f` `08aace49` | `follow_user_block` 模型/CRUD、WebDAV 同步、房间专属屏蔽词与用户名 |
| 数据目录 | 09-17 ~ 09-21 | `d4b07a47` `0d26f8d3` | 参数启动应用改数据目录、`data_hive_ce` 作为启动目录 #174 |
| 同步与 cookie | 09-24 ~ 09-30 | `7ba585ee` `abdffe71` `139ea90a` `249ff1b9` | douyu cookie 生命周期、WebDAV 双向同步优先本地、单例去重 |
| v1.8.11~14 | 09-18 ~ 09-25 | `378be06b` `85d9864e` `0dbb3bd6` `099d9c26` | 四次 release；#178 统一 follow 逻辑、#180 亮度重置 |
| SC 修复 | 09-30 ~ 10-03 | `5ccd7685` `b1df5968` `88ee03b5` `062d5a83` | SC 唯一性/时间戳去重、douyu cookie 提示、结构调整 |
| 账号迁 core | 10-10 ~ 10-11 | `e88268c6` `b3451ace` `e3f67344` `9abf40ff` `aa5f8073` `70b1d18f` | 账号体系从 app 整体搬进 core（经 §2.3 同步批进入 future） |
| B 站 cookie/uid | 10-12 | `57d8f86d` `03c4493a` | `setSiteAttrs` 改为 `jsonDecode` 后取 `cookie`；`getAccountInfo` 回填 `userId`（弹幕 `danmaku_arg` 需要配对 uid）；经 §2.5 同步批进入 future |

> 注：`029913c1`（10-08，flutter 3.47.6）与 `b0d408e6`（10-03，gen application
> settings by utils）曾是 future 上最晚的两条上游提交，之后 app 侧变更一度全为 fork 自研；
> 2026-10-12 的同步批（§2.3，13 条）重新引入上游「账号登录迁 core」等提交；
> 2026-10-14 的同步批（§2.5，上游 5 条）再引入 B 站 cookie/uid 修复，但 app 侧只落 1 行
> （`accountLogout` 清 `userName`），其余 4 条不触及 `simple_live_app`。

## 5. 各子系统提交热度

| 子系统（`simple_live_app/` 下） | future 条数 | 全部 refs 条数 | 关注点 |
| --- | --- | --- | --- |
| `lib/modules/live_room` | 104 | 555 | 最热：OSD 统一、音量、多开、后台播放接线 |
| `lib/modules/live_room/player` | 83 | 330 | 动作 resolver、条带 renderer、小窗几何链、快捷键 |
| `lib/modules/live_room/multi_play` | 24 | 36 | 棋盘视图、会话层、按格体积/尺寸 |
| `lib/services` | 70 | 274 | playback（后台播放）、follow_service、smart_group_service、sync_service |
| `lib/services/playback` | 1 | 1 | 仅 `cd89ecdc` 一条：audio_service 三文件 |
| `lib/modules/settings` | 32 | 128 | 播放设置、快捷键设置、互斥开关 |
| `lib/modules/follow_user` | 30 | 145 | 分组视图、搜索、标签、备注；**多归属 + 一键智能分组（§2.4）** |
| `lib/modules/sync` | 25 | 112 | WebDAV 同步项、cookie 双向、follow 成员表并集合并 |
| `lib/widgets` | 29 | 118 | 悬浮导航、page_view、骨架、follow card/行副标题 |
| `lib/app` | 46 | 306 | 设置控制器、base_controller、系统 UI inset |
| `test` | 67 | 124 | fork 贡献绝大部分：分页/自动加载/快捷键/音量/表情/关注归属与智能分组 |
| `android` | 4 | 69 | fork 仅 `e374b4df` 为功能改动，其余为上游/脚手架 |
| `rust` | 3 | 13 | **无专属提交**（仅 flutter/插件升级顺带触及） |

> 口径：future 条数按 `git log --oneline future -- <path> | wc`（本表在锚点 `5ae375f1` 重算）；
> 全部 refs 含 merge 与旧线，仅作量级参考。子路径相互重叠（`player` 属于 `live_room`），不可相加。

## 6. 历史重写：新旧提交对照

「重写前旧线」与「future 新线」是同一批工作的两套 hash。核对方法：按 subject
`--grep` 找到两条，再用 `git merge-base --is-ancestor <hash> future` 判定哪条在
future 上（在 = 新，不在 = 旧）。以下 8 对均已实测确证：

| 新（future，`ON_FUTURE`） | 旧（backup/origin，`NOT_FUTURE`） | 提交信息 |
| --- | --- | --- |
| `de601e3c` | `991ad96d` | feat(player): 清晰度选择弹窗支持复制线路直链 |
| `8af872e6` | `401f4fba` | feat(nav): 新增悬浮玻璃导航栏并整合为悬浮胶囊 |
| `a5e594dc` | `47cd644f` | feat(danmaku): …表情包，OSD 统计面板收敛为单页 |
| `e1f7a75c` | `03402670` | feat(list): 分页采信服务端 hasMore |
| `49eef9c3` | `05805539` | feat(douyin): 抖音推荐流恢复真分页 |
| `82e61c8d` | `da66a487` | fix(windows): Windows 标题栏跟随应用内主题 |
| `7865964d` | `81108f4e` | feat(player): 播放器 OSD 统计浮层改为 Flutter 自绘 |
| `d1978333` | `ab0319c8` | feat(home): 首页顶/底栏随列表滑动收起 |

另有两条「同工作、不同 subject」的复查型配对（`--grep` 逐条核对）：

| 新（future） | 旧（backup/origin） | 说明 |
| --- | --- | --- |
| `48aedc9a` | `35255ee6` | 旧线 subject 为「按 Open Code Review 复查结果修正分页、表情与桌面交互的遗留问题」 |
| `63c1eb8d` | `2575256b` | 旧线 subject 为「按 OCR 复查结果修复分页、播放器与桌面交互的遗留问题」 |

> 结论：**以 future 分支为准**；旧线仅用于找回重写前的上下文。注意
> `.workbuddy/artifacts/hash-mapping.md` 是**更早一次重写**时产出的对照表，其「新 hash」
> 列（如 `401f4fb`/`47cd644`）现已退化为旧线，与本表右列对应；该文件已过期，
> 使用前需按 `git merge-base --is-ancestor <hash> future` 重新判定。

## 7. 当前状态

- 版本：`simple_live_app/pubspec.yaml` = `1.8.15+10815`（`:2`）；根 `CHANGELOG.md` 最新条目仍是
  1.8.14（上游未把 1.8.15 写进 changelog，`grep '^## ' CHANGELOG.md`）。
- 分支：`future` HEAD = `5ae375f1`（2026-10-14，merge「同步 dev(v1.8.15 之后 5 提交) 到 future」）；
  领先 `origin/dev` **130** 个提交
  （`git rev-list --left-right --count origin/dev...future` → `0 130`）。
  `future` 上 app 相关提交 **193 条**。
- 最近两批 app 变更：`7c895e6d..8fd14a9f`（2026-10-12，关注多归属功能线 11 条，详见 §2.4）
  → `5ae375f1`（2026-10-14，同步 dev 5 条，详见 §2.5）。
- 已知红灯：`fvm flutter test --no-pub` 本机 **507 通过 / 15 失败**（全为存量，与 §2.4/§2.5
  两批改动无关；见 backlog P1-7、test-suite.md §7）。
- 后台播放的验收要点与已知限制、OSD 统一的设计口径，原先分别记在 `background-playback-notes.md`
  与 `specs/2026-10-03-osd-unify-and-independent-volume-design.md`。这两份**已不在工作区**
  （HEAD 里仍在，需要考古时用 `git show <HEAD>:<路径>`），其结论**已内联**到
  [backlog.md](./backlog.md) 的分级条目（P0-2/P0-3/P0-4、P2-9）与「已决策取舍」两处。
  关注多归属与一键智能分组的权威设计与验收清单：
  `specs/2026-10-12-multi-membership-and-smart-grouping-{plan,pr}.md`（§2.4）。