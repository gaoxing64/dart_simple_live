# simple_live_app 修改历史（Git 完整复现）

> 锚点：future `3359b76e`（2026-10-26）｜`git log future -- simple_live_app` 全量 **278** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/update-history.md)｜播放：[media-kit](../../media-kit/doc/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游），其余为原值。
> 本表是路径过滤后的**全量时间线**（含上游同步、合并与文档提交），新→旧。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- simple_live_app
git log --merges --date=short --pretty=format:'%h %ad %s' future -- simple_live_app
git show --stat <hash> -- simple_live_app
git log --author=gaoxing64 --date=short --pretty=format:'%h %ad %s' future -- simple_live_app
git log --all --date=short --pretty=format:'%h %ad %s' -- simple_live_app   # 含重写前旧线
```

历史已重写：future 根提交 `543910ba`；旧线在 `backup-future-*` / `origin/future`。`master` 是孤儿分支。

## 2. 阶段归纳

| 阶段 | 日期范围 | 条数 | 主题 |
| --- | --- | --- | --- |
| 知识库重写 + 关注详情/弹幕合并/聚合搜索 | 2026-10-23 ~ 10-26 | 37 | 五件套按 Git 重写、主播详情页与观看热力图、重复弹幕合并、AGP 9、聚合搜索与播放器缓存键值表、聊天滑回底部自动跟随 |
| 关注页定稿 | 2026-10-20 ~ 10-21 | 10 | 三栏布局、标签过滤、分组胶囊、搜索展开收刷新、增量重排 |
| Rust 迁移 + 播放/多开修复 | 2026-10-16 ~ 10-19 | 19 | FRB 资产下沉、Dart 协议删除、斗鱼续流、小窗/手势/常亮 |
| 关注多归属/后台播放 | 2026-10-09 ~ 10-15 | 55 | 后台播放、多开动作、成员表、快捷键、上游同步 |
| 分页/表情/OSD | 2026-09-10 ~ 10-08 | 125 | hasMore、B站/抖音表情、OSD 统一、音量纯函数 |
| 导航/首页/基础 | 2026-07-30 ~ 09-09 | 32 | 胶囊导航、顶底栏收起、分页触发、播放器基础 |

## 3. 上游同步节点（路径日志中的 merge）

| 日期 | 提交 | 内容 |
| --- | --- | --- |
| 2026-10-17 | `7cb47723` | 同步 fork-parent/dev 4 提交（含虎牙 SC uri 修复） |
| 2026-10-14 | `5ae375f1` | 同步 dev（v1.8.15 之后 5 提交） |
| 2026-10-12 | `abca65f8` | 同步上游 v1.8.15 |
| 2026-10-11 | `3714eec1` | 多开改动作式加入 + 音量浮层并入 |
| 2026-10-09 | `1c97d00b` | 同步上游 v1.8.14 |
| 2026-09-24 | `34c39a31` | 同步上游 v1.8.12 |
| 2026-09-18 | `a38cbc75` | 合并 dev（v1.8.11） |
| 2026-09-18 | `899212ba` | 合并 dev |

## 4. 全量时间线（278 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-26 | `3359b76e` | G | fix(chat): 手动滑回底部并停手后自动恢复跟随最新 |
| 2026-10-26 | `65a83983` | G | docs(app): 知识库五件套跟到 c1dd7769 |
| 2026-10-26 | `c1dd7769` | G | refactor(player): 直播缓存属性改为可测的键值表 |
| 2026-10-26 | `36249272` | G | fix(search): 聚合搜索模式改单一真值并收紧失败与首屏反馈 |
| 2026-10-26 | `8947bcdc` | G | refactor(base): 列表底部重试条文案改为可覆写 |
| 2026-10-26 | `0e99306a` | G | fix(twitch): 提高预读避免直播反复缓冲 |
| 2026-10-26 | `446d613f` | G | feat(search): 新增多平台聚合搜索 |
| 2026-10-25 | `ddb0cc3e` | G | chore: 升级 Flutter 至 3.47.8 |
| 2026-10-25 | `49e4f621` | G | feat(follow): 热力图移动端首帧对齐当前日期 |
| 2026-10-25 | `dc4baac7` | G | fix(follow): 消除年份菜单当前项的满宽矩形高亮 |
| 2026-10-25 | `65ac73bb` | G | fix(follow): 观看热力图适配移动端布局 |
| 2026-10-25 | `2342c276` | G | feat(follow): 补齐直播中与中间页快速取关 |
| 2026-10-25 | `4609ceca` | G | feat(follow): 备注支持显示为昵称开关 |
| 2026-10-25 | `af6ce7f5` | G | fix(follow): 年份选择 hover 圆角与胶囊一致 |
| 2026-10-25 | `6b711db7` | G | style(follow): 统一标签展示并压紧中间页布局 |
| 2026-10-25 | `12ebf7d6` | G | style(follow): 移除中间页标签的文件夹图标 |
| 2026-10-25 | `3e2e8f77` | G | feat(follow): 分组标签迁至右键预览弹卡 |
| 2026-10-25 | `deeb019f` | G | fix(follow): 选择态展示全部主播分组标签 |
| 2026-10-25 | `1ce8c5da` | G | feat(live-room): 点击主播头像进入详情 |
| 2026-10-25 | `c2a4f588` | G | fix(follow): 搜索态侧键返回先收起搜索 |
| 2026-10-25 | `e376d7ab` | G | feat(follow): 关注卡片右键改为预览弹卡 |
| 2026-10-25 | `beaf6392` | G | feat(follow): 仅选中项展示分组标签 |
| 2026-10-25 | `848ab96b` | G | feat(follow): 新增主播详情页与观看统计 |
| 2026-10-25 | `f603d252` | G | feat(history): 按日记录直播间观看数据 |
| 2026-10-25 | `9ee01fb7` | G | feat(danmaku): 新增重复弹幕合并计数，去重支持合并/屏蔽双模式 |
| 2026-10-25 | `4538ec58` | G | feat(danmaku): 弹幕去重正式上线，摘除实验性标签并移除热身门槛 |
| 2026-10-25 | `0245b9dc` | G | feat(player): 键盘控制新增自定义键位开关 |
| 2026-10-25 | `384084f6` | G | fix(chat): 保留聊天页签状态避免切换卡顿 |
| 2026-10-24 | `d49ac49c` | G | build(android): 手机端升级到 AGP 9.0.1 + Gradle 9.1.0 |
| 2026-10-24 | `b2b93bfd` | G | feat(follow): 排序方式新增在线人数，移除用户名排序 |
| 2026-10-24 | `ee74d24f` | G | feat(live_room): 横屏聊天侧栏可拖拽调宽与收起 |
| 2026-10-24 | `e0b4299d` | G | fix(player): 窄屏非全屏时 OSD 不再遮挡画面 |
| 2026-10-24 | `db3dcae6` | G | refactor(settings): 直播间设置页签新增播放分组 |
| 2026-10-24 | `83e1d622` | G | refactor(settings): 精简直播间设置副标题 |
| 2026-10-23 | `7639b004` | G | fix(chat): 退出全屏后聊天区恢复滚动位置 |
| 2026-10-23 | `91e79575` | G | feat(chat): 聊天动画增加可关闭开关 |
| 2026-10-23 | `8d9f7fa1` | G | feat(chat): 聊天区增加入场动画与平滑滚底 |
| 2026-10-23 | `b47c9ed3` | G | docs(app): 按 Git 历史重写知识库五件套 || 2026-10-21 | `52466f96` | G | fix(follow): 搜索展开时收起刷新按钮 |
| 2026-10-21 | `b5718dd8` | G | fix(follow): 修复设置分组对话框空白 |
| 2026-10-21 | `55928d21` | G | feat(follow): 关注页标签栏自适应，内容项显示分组胶囊 |
| 2026-10-21 | `08fb5a74` | G | fix(multiplay): 外部设置面板的画面尺寸改为作用于聚焦格 |
| 2026-10-21 | `49bfb83e` | G | fix(player): 最大化/全屏进小窗后退出，窗口不再还原成越屏大窗 |
| 2026-10-21 | `9a3f1313` | G | fix(player): 桌面播放器摘掉移动端竖向手势，小窗整窗任意方向可拖 |
| 2026-10-20 | `1c0d02f5` | G | refactor(app): 关注页改三栏布局，平台分类改为设置开关 |
| 2026-10-20 | `0d2f57e6` | G | perf(app): 关注刷新期间增量重排，整轮结束只做一次排序 |
| 2026-10-20 | `c4837d78` | G | feat(app): 未开播关注卡面改用圆形头像占位 |
| 2026-10-20 | `63197f69` | G | fix(account): 校验失败不再抹凭证，修复升级用户每次启动误报账号失效 |
| 2026-10-19 | `900f8d50` | G | fix(app): 屏幕常亮改按路引用计数，修复多开与断线熄屏 |
| 2026-10-18 | `f72bb417` | G | refactor(core)!: 删除 Dart 协议实现，console 由 slive-cli 取代 |
| 2026-10-18 | `4795b165` | G | docs: 同步斗鱼续流「上下文驱动」契约与测试口径 |
| 2026-10-18 | `594023ae` | G | fix(app): 斗鱼续流改为上下文驱动，恢复到期自动续流 |
| 2026-10-18 | `7b31c568` | G | fix(app): 修复搜索结果重复 |
| 2026-10-17 | `4287a2d8` | G | fix(app): 抖音表情聊天按大表情尺寸渲染 |
| 2026-10-17 | `6dd27ec6` | G | docs: ADR-014 全面采用 Rust core，同步结构与路径文档 |
| 2026-10-17 | `73e80b1e` | G | refactor(core): FRB 资产与 Dart 绑定层迁入 simple_live_core，App 直连 Rust 去开关 |
| 2026-10-17 | `70c1c717` | G | refactor: Rust workspace 迁至 simple_live_core（ADR-001 预留路径落地） |
| 2026-10-17 | `278c4c4a` | G | fix(core): 虎牙 SC 上游对齐 —— URI_SUPER_CHAT 1314→1317 + 弃用文本触发路径 |
| 2026-10-17 | `7cb47723` | G | Merge fork-parent/dev: 同步上游 4 提交增量（含虎牙 SC 真实 uri 修复 97413c60） |
| 2026-10-17 | `97413c60` | S | fix(core): listen real uri to get list of huya-sc #157 |
| 2026-10-17 | `85fd039e` | G | fix: 评审修复 —— WSS TLS 落地平台分层 + 16 条失真骨架清理 + 绑定层日志规范 |
| 2026-10-17 | `50d9d832` | G | feat(app): 四平台 Dart 绑定层集成与真机体验修复（启动/取流/弹幕/错误可见性） |
| 2026-10-17 | `81730e6c` | G | feat(core): 斗鱼/虎牙/Twitch/抖音四平台迁移（TARS 共享模块 + 参数级夹具） |
| 2026-10-17 | `b6968bbb` | G | feat(core): slive-core 骨架与 B站全能力迁移（FRB 桥 + 弹幕会话 + wbi 签名） |
| 2026-10-16 | `4dcdb4fe` | G | docs(douyu): 续流中转落地后同步 core/app 文档 |
| 2026-10-16 | `77eebd63` | G | fix(douyu): 新增本地续流中转，修复未配置 cookie 时约 5 分钟断流 |
| 2026-10-16 | `e0da30e8` | S | style: 卡片模式-关注项ui的一些细微调整 |
| 2026-10-15 | `576ef965` | S | style: 紧凑模式-关注项ui的一些细微调整 |
| 2026-10-15 | `cbd9b8e7` | G | docs(app): test-suite 补齐过期行数，版本锚点改指测试态提交 |
| 2026-10-15 | `45fecf3a` | G | docs(app): 关注页分组筛选与模式切换的文档刷新 |
| 2026-10-15 | `eb8f91e8` | G | test(follow): 收紧卡片模式用例的溢出放行，只放行已知 1px 红灯 |
| 2026-10-15 | `bfddf81e` | G | feat(follow): 恢复关注页「模式切换」，平铺列表可选紧凑行/卡片网格 |
| 2026-10-15 | `e9bdee92` | G | test(follow): 回修分组用例 finder，组名改从卡片后代里找 |
| 2026-10-15 | `55974b69` | G | feat(follow): 「全部」视图加分组胶囊筛选，平铺态回归原版效率 |
| 2026-10-14 | `5610e152` | G | docs(app): test-suite 补多开窗口收口用例 |
| 2026-10-14 | `2195d86c` | G | test(multiplay): 去掉多余的 dart:ui import |
| 2026-10-14 | `b1beee59` | G | fix(multiplay): 全屏态下不收口窗口几何 |
| 2026-10-14 | `48ad7c12` | G | test(multiplay): 全屏态关格不摆窗口几何的回归 |
| 2026-10-14 | `f0362575` | S | refator: 优化代码，保持模块独立性 |
| 2026-10-14 | `785087e4` | G | feat(live_room): 锁定按钮 tooltip 内联 L 键帽 |
| 2026-10-14 | `d7742231` | G | feat(live_room): 桌面音量颗 tooltip 内联静音键帽（触屏不挂） |
| 2026-10-14 | `8184f893` | G | feat(live_room): 桌面播放器条带按钮 tooltip 内联当前快捷键键帽 |
| 2026-10-14 | `198a0407` | G | feat(live_room): player_tooltip —— 动作→快捷键映射与带键帽的 Tooltip 渲染器 |
| 2026-10-14 | `eff3ad1b` | G | fix(live_room): 中文输入法下用 Ctrl+字母 旁路触发快捷键 |
| 2026-10-14 | `ab733079` | G | docs(app): 已删文件引用改内联说明 |
| 2026-10-14 | `685d94b5` | G | docs(app): 新增 simple_live_app 知识库（5 份，锚点 abca65f8） |
| 2026-10-14 | `5ae375f1` | G | merge: 同步 dev(v1.8.15 之后 5 提交) 到 future |
| 2026-10-12 | `3b86b496` | G | feat(follow): 一键按平台智能分组 —— 确认弹窗 + 顶栏 ⋮ / 关注设置页两处入口 |
| 2026-10-12 | `3267a04e` | G | refactor(follow)!: 删除 FollowUser.tag 冷字段 —— FollowUserTag.userId 为归属唯一真源 |
| 2026-10-12 | `6cf66e3f` | G | feat(follow): UI 语义对齐多归属 —— 拖拽按成员表判同组、详情页多选分组、行副标题展示全部归属 |
| 2026-10-12 | `3c8a34c4` | G | fix(follow): 智能分组按 siteSort 优先 + 补全缺失平台，不再把它们误算成未知平台 |
| 2026-10-12 | `0442f4ac` | G | feat(follow): 备份与 WebDAV 兼容多分组 —— 导出 tags 数组，WebDAV 按分组名并集合并 |
| 2026-10-12 | `a225e3b4` | G | feat(follow): 翻转写路径 —— UI 操作改走多归属 API，FollowUser.tag 降级为主分组缓存 |
| 2026-10-12 | `53b70b83` | G | feat(follow): SmartGroupService —— 按平台一键智能分组（纯逻辑，可单测） |
| 2026-10-12 | `6c7632e2` | G | feat(follow): groupedView 按 userId 分桶 —— 一个关注出现在它的每个所属分组里 |
| 2026-10-12 | `5890641e` | G | feat(follow): FollowService 归属 API —— 加入 / 移出 / 查询分组成员 |
| 2026-10-12 | `7c895e6d` | G | feat(follow): 归属迁移 —— 把 FollowUser.tag 灌进 FollowUserTag.userId |
| 2026-10-12 | `57d8f86d` | S | fix(bili): 迁移到Account cookie 不生效 #https://github.com/SlotSun/dart_simple_live/issues/197#issuecomment-6118992744 |
| 2026-10-12 | `abca65f8` | G | merge: 同步上游 dev(v1.8.15) 到 future |
| 2026-10-11 | `70b1d18f` | S | feat(account): 完善平台账号各项同步迁移功能 |
| 2026-10-11 | `aa5f8073` | S | refactor(account): 完成平台账号数据同步迁移工作 |
| 2026-10-11 | `63a3055c` | S | style: dart format . |
| 2026-10-11 | `9abf40ff` | S | refactor(account): 完成bilibili_webLogin 功能迁移 |
| 2026-10-11 | `3714eec1` | G | merge: 多开改为动作式加入 + 音量浮层修复，并入 future |
| 2026-10-11 | `afd18194` | G | feat(multiplay): 多开从「模式」改成「动作」，关注行图标对齐 |
| 2026-10-11 | `5e5f1009` | G | fix(player): 音量浮层静音双向、拖动滑条也浮出读数 |
| 2026-10-11 | `c71da474` | G | fix(player): restore window after fullscreen exit |
| 2026-10-11 | `12ab0c42` | G | feat(live_room): 直播间播放器快捷键，可改键 / 禁用 / 恢复默认 |
| 2026-10-11 | `e3f67344` | S | refactor(account): 跑通QRcode全流程 |
| 2026-10-11 | `b3451ace` | S | fix(account): credential 数据拼装 |
| 2026-10-10 | `e88268c6` | S | refactor(account): 完成account 站点分流基础功能 |
| 2026-10-10 | `c690e5f3` | S | db: 构造 account 数据模型 |
| 2026-10-10 | `e3a090ad` | S | refactor(account): 逐步迁移账号登录从app到core，项目架构更清晰 |
| 2026-10-09 | `1c97d00b` | G | merge: 同步上游 dev(v1.8.14) 到 future |
| 2026-10-09 | `6847a151` | S | chore: sync fvm 3.47.6 |
| 2026-10-09 | `e374b4df` | G | feat(android): 媒体前台服务、通知与耳机键的原生接线 |
| 2026-10-09 | `5692db16` | G | feat(live_room): 直播间那一路挂到系统媒体控制上（切后台/锁屏继续出声） |
| 2026-10-09 | `cd89ecdc` | G | feat(playback): audio_service handler 与音频会话，投影到通知栏/锁屏/耳机键 |
| 2026-10-09 | `cbb474ee` | G | feat(settings): 「后台播放」开关，与「进入后台自动暂停」双向互斥 |
| 2026-10-09 | `efa33716` | G | build(deps): 引入 audio_service 0.18.19 与 audio_session 0.2.4 |
| 2026-10-09 | `0f2481f6` | G | fix(multiplay): 补上只有引用、没有定义的两个「默认路数」符号 |
| 2026-10-09 | `80e1a096` | S | chore: sync media_kit version |
| 2026-10-08 | `029913c1` | S | chore: update flutter 3.47.6 |
| 2026-10-06 | `e250ceb6` | G | feat(navbar): 悬浮底栏换成 FlClash lens 底栏，移除 Liquid Glass |
| 2026-10-04 | `fcb43a82` | G | feat(multiplay): 多开播放落到移动端——竖屏 1×2、横屏全屏 2×2 |
| 2026-10-04 | `1826c57b` | G | feat(multiplay): 移动端适配的地基——触屏判据与竖屏视频区高度 |
| 2026-10-04 | `19282de1` | G | style(player): 音量浮层四宿主统一，样式与锚点回到原版那条 |
| 2026-10-04 | `b4a97364` | G | refactor(player): 弹层容器回到按宿主分，桌面窗口化落底部抽屉 |
| 2026-10-03 | `636116d7` | G | fix(player): 桌面底栏右簇回到贴右，不再浮在条带中段 |
| 2026-10-03 | `b7188916` | G | fix(player): 桌面 OSD 恢复右上角那一簇，换台按宿主分形态 |
| 2026-10-03 | `b0d408e6` | S | refactor: gen application settings by utils |
| 2026-10-03 | `88ee03b5` | S | fix: 完善斗鱼cookie管理，提示用户续期cookie |
| 2026-10-03 | `d5b98eae` | G | fix(player): 弹幕设置注释改口，底部抽屉的宿主不含移动横屏全屏 |
| 2026-10-03 | `4a756974` | G | fix(player): 弹幕设置的屏蔽入口按 surface 区分，长按与换台并成一个浮层 |
| 2026-10-03 | `d1b02d45` | G | fix(player): 桌面弹幕设置补回屏蔽入口，解开弹层本体的循环引用 |
| 2026-10-03 | `e6f33ad1` | G | test(player): 条带音量颗需要设置替身；总音量为 0 的显示判定落用例 |
| 2026-10-03 | `afe4d581` | G | refactor(player): 多路可选谓词收敛为 controller getter |
| 2026-10-03 | `f90f4f49` | G | fix(player): 总音量拖到 0 时音量图标显示 volume_off（仅显示侧） |
| 2026-10-03 | `e626e15b` | G | fix(liveroom): 压低开关关掉时不渲染比例那行；页级菜单注释改为实际行为 |
| 2026-10-03 | `47f4b5e2` | G | fix(multiplay): 画面尺寸按格覆盖随会话收口，三处读者同一口径 |
| 2026-10-03 | `9936e941` | G | fix(player): 桌面清单类弹层统一成右侧抽屉（spec §3） |
| 2026-10-03 | `ec237ba2` | G | fix(player): 桌面条带图标回归项目图标族，清掉 trailing 与手抄样式 |
| 2026-10-03 | `1e9c3222` | G | fix(player): 条带文字按钮可收缩，窄窗口不再 RenderFlex 溢出 |
| 2026-10-03 | `743ee9df` | G | fix(player): 窗口化桌面条带补回渐变遮罩带 |
| 2026-10-03 | `7dae6796` | G | fix(player): 换台锚定件恒平铺，窄窗不再失去换台入口 |
| 2026-10-03 | `1087e0b7` | G | feat(liveroom): 页级「更多」与视频区条带共用同一份动作清单 |
| 2026-10-03 | `72a798bd` | G | fix(multiplay): 格子胶囊改紧凑密度，进全屏先聚焦那一路 |
| 2026-10-03 | `641e3049` | G | fix(multiplay): 格子胶囊用紧凑密度，240 宽不再溢出 |
| 2026-10-03 | `cbd18386` | G | feat(multiplay): 格子胶囊改由动作 resolver 驱动 |
| 2026-10-03 | `5f612671` | G | fix(player): 清掉移动分支里永不显示的桌面控件，修清晰度字族与空 ⋮ |
| 2026-10-03 | `05f2521c` | G | feat(player): 桌面条带改由动作 resolver 驱动 |
| 2026-10-03 | `34f43593` | G | feat(player): 桌面条带 renderer（PlayerActionBar + 单项 builder） |
| 2026-10-03 | `2a887c12` | G | fix(multiplay): 画面尺寸的标题与生效范围同谓词，横屏抽屉也清覆盖 |
| 2026-10-03 | `ca13b5aa` | G | feat(multiplay): 画面尺寸可按格独立（会话级覆盖，不落盘） |
| 2026-10-03 | `9d069bb0` | G | fix(player): 音量滑条改走 overlay 锚定，静音一律按本格系数 |
| 2026-10-03 | `b153e010` | G | feat(player): 音量三态控件（点击静音/悬停滑条/滚轮微调） |
| 2026-10-03 | `b82791e6` | G | fix(player): 窗口级动作的状态判断改走页面主格，动词统一为换台 |
| 2026-10-03 | `95a9861a` | G | feat(player): 动作执行层与 ⋮ 抽屉、选台锚定浮层 |
| 2026-10-03 | `a202bd3f` | G | fix(player): 进小窗前退全屏的事件不再污染小窗偏好 |
| 2026-10-03 | `8bc3918b` | G | fix(player): 小窗还原点改为离开窗口态时采集，支持从全屏直接进小窗 |
| 2026-10-03 | `86f82c89` | G | refactor(multiplay): 压低改为可选后同步相关注释 |
| 2026-10-03 | `57246d95` | G | feat(multiplay): 非聚焦压低改为默认关的可选行为 |
| 2026-10-03 | `f563ad5a` | G | refactor(player): 动作清单的 tier 收成单一真相源 |
| 2026-10-03 | `247b8d80` | G | feat(player): 播放覆盖层动作清单抽成纯 resolver |
| 2026-10-03 | `77eb7864` | G | feat(multiplay): 音量决策抽成纯函数，压低改为可叠乘因子 |
| 2026-10-03 | `b1df5968` | S | fix: SC时间戳对不齐，改由价格&用户名&消息判断去重 |
| 2026-10-03 | `062d5a83` | S | refactor: 调整项目结构 |
| 2026-10-01 | `5ccd7685` | S | fix: 保证SC列表唯一性 |
| 2026-10-01 | `48011b93` | G | fix(multiplay): 按 review 收口性能与守卫 |
| 2026-10-01 | `8f7b941e` | G | fix(multiplay): 返回键改用 maybePop、折叠不再藏起聚焦格 |
| 2026-10-01 | `c08d7914` | G | chore(tools): 多开性能探针（一次性脚本） |
| 2026-10-01 | `de408209` | G | feat(multiplay): 关注页批量开多开、卡面可勾选 |
| 2026-10-01 | `f65912ab` | G | feat(multiplay): 多开棋盘视图与格子控件 |
| 2026-10-01 | `d5f32f7d` | G | feat(multiplay): 多开播放的共享状态排雷与会话层 |
| 2026-10-01 | `7347f515` | G | feat(player): Stats 覆盖层可切自绘浮层 / mpv 内置 OSD |
| 2026-10-01 | `ac31401a` | G | chore(deps): media_kit ref 升到 23ec6b9c，并忽略 libmpv-darwin-build/ |
| 2026-10-01 | `206440f2` | G | fix(history): 观看时长改为按房间各记一份 |
| 2026-09-30 | `139ea90a` | S | fix(webdav): 修正单例模式下webdav反复拉取合并资源 |
| 2026-09-30 | `24b68f30` | G | fix(danmaku): 大表情最多占两个轨道，聊天区消息上限降到 150 |
| 2026-09-30 | `5d8f0b38` | G | fix(danmaku): 表情渲染的尺寸口径、开关与交互健壮性 |
| 2026-09-29 | `aed42c1e` | G | feat(danmaku): 弹幕与聊天区支持 B 站表情包 |
| 2026-09-28 | `c10c0b8a` | G | fix(settings): 修复 Android 上「保存日志文件」静默失败 |
| 2026-09-28 | `6b63503c` | G | fix(android): 修复硬解与视频输出初始化失败导致的黑屏 |
| 2026-09-27 | `01c8ab61` | G | fix(window): 全屏/小窗进出后最小宽度限制失效 |
| 2026-09-27 | `dec20731` | G | feat(volume): 音量均衡（loudnorm）与最大音量设置 |
| 2026-09-26 | `abdffe71` | S | fix(webdav): 修正cookie双向同步逻辑，优先使用本地有效数据 |
| 2026-09-25 | `099d9c26` | S | release v1.8.14 |
| 2026-09-25 | `c04903cb` | S | fix(douyu): 参数不能正确保存导致cookie失效问题 |
| 2026-09-25 | `453a01fd` | G | feat(follow): 搜索胶囊改用搜索页样式，修展开时的闪烁与位移 |
| 2026-09-25 | `7c7f3591` | G | fix(bars): 列表滚不动时滚轮也能驱动顶/底栏 |
| 2026-09-25 | `be48430d` | G | feat(follow): 选择态入口与分组弹窗标题改为「编辑」 |
| 2026-09-25 | `f8822089` | G | feat(follow): 顶栏加一键展开/折叠全部分组 |
| 2026-09-25 | `24333bf3` | G | feat(player): 小窗底部按钮重排，退出按钮改 PIP 图标 |
| 2026-09-25 | `8d9924a7` | G | fix(player): 小窗双击退出不再残留置顶与纵横比锁定 |
| 2026-09-24 | `0dbb3bd6` | S | release v1.8.13 |
| 2026-09-24 | `7ba585ee` | S | fix: 完善douyu cookie 管理，包括不限于 webdav 和 本地同步 |
| 2026-09-24 | `90259092` | S | fix: Windows下屏幕亮度重置问题  #180 |
| 2026-09-24 | `249ff1b9` | S | fix(douyu): 额外配置实现cookie不过期 |
| 2026-09-24 | `34c39a31` | G | merge: 合并上游 dev (v1.8.12) 到 future |
| 2026-09-24 | `e17b9239` | G | feat(follow): 搜索改顶栏图标原位展开 |
| 2026-09-23 | `b95865ac` | G | feat(follow): 关注页分组视图 + 三页 ViewPager |
| 2026-09-22 | `9199926c` | S | refactor: 优化部分代码逻辑 |
| 2026-09-22 | `192e22e6` | S | fix(follow):统一follow业务逻辑，tag数据随follow数据变动,保持一致性，规避数据混乱 #178 |
| 2026-09-22 | `b492f965` | S | fix(douyu): douyu 游客模式直播流只能存活5min,需要配置 cookie |
| 2026-09-21 | `e53c0825` | G | feat(glass): 底栏改用 liquid_glass_easy，默认值收敛到单一来源 |
| 2026-09-21 | `b5f9e9bd` | G | fix(window): 修改桌面端最小窗口宽度为 436 |
| 2026-09-21 | `2683e75e` | S | chore: flutter 3.47.5 |
| 2026-09-21 | `0d26f8d3` | S | feat: 支持根目录`data_hive_ce` 作为项目数据启动目录 #174 |
| 2026-09-20 | `d45cad06` | G | feat(player): 桌面端小窗播放锁定画面纵横比 |
| 2026-09-19 | `dfa24b29` | G | fix(player): 修复退出全屏后底部避让失效、导航条压住刷新键 |
| 2026-09-19 | `afc6d8c4` | G | perf(bars): 滑动收起改为纯绘制，消除同步模式的每帧重排 |
| 2026-09-19 | `8282b193` | G | test(follow): 补关注页滑动收起顶栏回归测试 |
| 2026-09-19 | `c9d6f183` | G | feat(ui): 统一弹出菜单规格，补齐 Tab 跳切动画与滑动收起顶栏 |
| 2026-09-18 | `85d9864e` | S | release v1.8.12 |
| 2026-09-18 | `334af082` | S | fix: 全屏播放状态下按钮越界 #173 |
| 2026-09-18 | `a38cbc75` | G | Merge branch 'dev' into future (upstream v1.8.11) |
| 2026-09-18 | `d9f03181` | G | chore: fvm 版本对齐 pubspec 要求（3.47.2 → 3.47.4） |
| 2026-09-18 | `378be06b` | S | release v1.8.11 |
| 2026-09-18 | `88f383cf` | S | fix(window): 空安全导致的bug |
| 2026-09-18 | `899212ba` | G | Merge branch 'dev' into future |
| 2026-09-16 | `63c1eb8d` | G | fix: 修复分页、播放器与桌面交互的遗留问题 |
| 2026-09-17 | `ee085b69` | S | chore: flutter version 3.47.4 |
| 2026-09-17 | `d4b07a47` | S | feat: 允许用户通过参数启动应用，可修改数据目录到应用文件夹 |
| 2026-09-16 | `c7285bb9` | S | perf: 优化ui |
| 2026-09-16 | `3a8a5efc` | S | fix(window): 修正启动时最大化功能，保证第一帧渲染防止白屏 |
| 2026-09-16 | `cd128383` | S | refactor: 更清晰垂直的window业务逻辑，允许用户记忆窗口最大化 #134 |
| 2026-09-15 | `b5aaa1bd` | S | feat: pc端小窗模式 尺寸/位置 记忆 #171 |
| 2026-09-14 | `d97a033c` | S | fix: 修正移动端退出全屏逻辑导致的错误 |
| 2026-09-14 | `9b0d4308` | S | feat: 完善弹幕随屏幕大小放缩功能，允许用户自定义放缩比率 #172 |
| 2026-09-13 | `3091f464` | S | feat: 弹幕字体大小随窗口大小缩放 #172 |
| 2026-09-13 | `e319fd81` | S | style: dart format /lib |
| 2026-09-13 | `6f2437f2` | S | style: follow.watchDuration 字段弃用的部分调整，未完全弃用 |
| 2026-09-13 | `a1d31be3` | S | style: 部分代码复用抽离 |
| 2026-09-12 | `9dfb644e` | G | fix(windows): 关闭亮度 auto reset 提前到窗口初始化之前 |
| 2026-09-12 | `48aedc9a` | G | fix: 修正分页、表情与桌面交互的遗留问题 |
| 2026-09-11 | `37ea5361` | G | fix(windows): 修复 Windows 端拖动窗口边框严重滞后于鼠标 |
| 2026-09-11 | `fb97e0ec` | G | fix(list): 隐藏的列表状态层停掉 ticker，空闲时不再持续出帧 |
| 2026-09-11 | `e79ff0a9` | G | feat(desktop): 桌面端鼠标交互对齐移动端（拖拽滚动 / 左右切页 / 右键菜单） |
| 2026-09-11 | `a5e594dc` | G | feat(danmaku): 弹幕与聊天区支持 B 站表情包，OSD 统计面板收敛为单页 |
| 2026-09-11 | `49eef9c3` | G | feat(douyin): 抖音推荐流恢复真分页，列表到底给出明确提示 |
| 2026-09-11 | `3e536ca8` | S | refactor(block): 实现基础的房间专属关键词和用户名屏蔽，提高弹幕过滤性能 |
| 2026-09-11 | `a10fcb9f` | S | refactor(block): 实现live界面直选屏蔽功能 |
| 2026-09-11 | `e1f7a75c` | G | feat(list): 分页采信服务端 hasMore，收敛为单一触发路径并补齐失败重试入口 |
| 2026-09-11 | `08aace49` | S | refactor(block): 实现live_controller 弹幕屏蔽逻辑 |
| 2026-09-10 | `abd56489` | S | refactor(block): 实现 follow_block的 WEBDav同步逻辑 |
| 2026-09-10 | `fae186bf` | S | refactor(block): 构造follow_user_block的model 和 crud |
| 2026-09-10 | `4e3c35a1` | G | feat(list): 分页列表改用滚动通知自动加载下一页并补齐加载骨架 |
| 2026-09-09 | `c1f5ae82` | G | fix(player): 调整直播缓存策略并新增 mpv 属性回读日志 |
| 2026-09-09 | `7865964d` | G | feat(player): 播放器 OSD 统计浮层改为 Flutter 自绘并支持多端响应式 |
| 2026-08-31 | `8af872e6` | G | feat(nav): 新增悬浮玻璃导航栏并整合为悬浮胶囊 |
| 2026-08-29 | `82e61c8d` | G | fix(windows): Windows 标题栏跟随应用内主题与系统深浅色 |
| 2026-08-31 | `d1978333` | G | feat(home): 首页顶/底栏随列表滑动收起，收起类型支持即时/同步 |
| 2026-08-31 | `192f77ea` | G | fix(player): 全屏弹窗无响应与退出直播间崩溃 |
| 2026-08-09 | `73e5898d` | G | feat(player): 复制直链按钮改为图标按钮 |
| 2026-08-09 | `de601e3c` | G | feat(player): 清晰度选择弹窗支持复制线路直链 |
| 2026-08-09 | `93bea52d` | G | fix(player): 移除全屏模式下冗余的全屏按钮 |
| 2026-09-08 | `03d66eb7` | S | perf(webdav): 补充同步项的可选择功能，标记一些工作在下个版本实现 |
| 2026-09-06 | `48fa02cb` | S | feat: 允许禁用“滑动调节亮度/音量 #167 |
| 2026-09-04 | `1fac4d68` | S | fix(ci): lock version of auto_orientation_v2 is v2.3.8 |
| 2026-09-03 | `0c1c4d46` | S | style: migrate deprecated API usages |
| 2026-09-03 | `1773c426` | S | chore: migrate easy_refresh |
| 2026-09-03 | `1e3566a3` | S | chore: upgrade plugins |
| 2026-09-02 | `3fff9ef4` | S | fix: 迁移material_ui 中的弹窗bug #169 |
| 2026-09-01 | `0c4fbf83` | S | fix(core): increase huya-sc fetch limit from 10 to 50 |
| 2026-08-31 | `51ebd945` | S | chore: SC排列方式调整为最新消息在最上方 |
| 2026-08-30 | `c7a587d3` | S | fix(ci): temp use getx_material_ui_version base on 4.7.3 |
| 2026-08-30 | `a0985b3a` | S | chore: migrate to material_ui |
| 2026-08-29 | `cb2f3a9f` | S | chore: upgrade flutter to 3.47.2 |
| 2026-08-21 | `8b40850f` | S | chore: upgrade flutter to 3.47.1 |
| 2026-08-17 | `72e00adb` | S | feat(core): support huya super chat (test) |
| 2026-08-16 | `542acd47` | S | chore: upgrade flutter to 3.47.0 |
| 2026-08-04 | `251b012d` | S | fix(ios): iOS Deployment Target 15.0 |
| 2026-08-01 | `9bdc5f10` | S | chore: bump flutter v3.44.8 |
| 2026-08-01 | `78c2d7eb` | S | chore: update plugins for flutter v3.44.x |
| 2026-07-31 | `02ef8c83` | S | chore: sync media_kit version |
| 2026-07-30 | `44f50480` | S | feat(follow): init follow.lastWatchTime on first launch of v10810 |
| 2026-07-30 | `8b394ab1` | S | feat(follow): logic of dormant |
| 2026-07-30 | `5d84e5ef` | S | feat(follow): add dormancy_threshold.setting of follow settings |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time |

## 5. 当前状态

- future HEAD `52466f96`；App 版本 `1.8.15+10815`，Flutter `3.47.6`。
- 路径提交 241 条：fork（G）162 条、上游（S）79 条；其中合并提交 8 条。
- 近期主线：关注页三栏/标签/胶囊、多开与窗口几何、屏幕常亮引用计数、Rust 迁移收尾。
- 测试：57 个 `*_test.dart`；最近完整记录 2026-10-14（522 执行 / 507 通过 / 15 失败），之后未重测。
