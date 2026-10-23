# simple_live_app 待办与优化清单

> 锚点：future `52466f96`（2026-10-21）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/backlog.md)｜播放：[media-kit](../../media-kit/doc/backlog.md)

## P0 — 用户可见的正确性

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | 音量均衡依赖定制 libmpv；内核缺 `loudnorm` 时整条音轨被禁（静音） | `modules/live_room/player/player_controller.dart`（`volumeNormalizeAF`/自愈） | 发版前四平台 ABI 符号扫描；保持运行时自愈 |
| P0-2 | Android 12+ 暂停后从通知按播放＝后台重启前台服务，可能抛异常 | `services/playback/live_playback_audio_handler.dart`、`live_audio_session.dart` | 真机单变量 A/B：`androidStopForegroundOnPause=false` + `androidNotificationOngoing=false` |
| P0-3 | 长后台后通知「停止」可能连带回收 Flutter 引擎 | audio_service `disposeFlutterEngine` 守卫 | 真机专项：后台久置→通知停止→重开不黑屏 |
| P0-4 | 后台通知封面不带 referer/UA，防盗链平台退化成文字 | `live_playback_audio_handler` 的 `artUri` | 先落本地文件再交给 `MediaItem.artUri` |
| P0-5 | 弹幕表情始终渲染，无开关；旧键 `kDanmuEmoticonEnable` 无读取方 | `live_room_page.dart`、`local_storage_service.dart` | 采纳上游开关或正式登记为取舍 |

## P1 — 平台/设备脆弱点

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | iOS 后台/音频会话未在本机验证 | `services/playback/live_audio_session.dart` | 上 Mac 补手测：锁屏、耳机键、中断、拔耳机 |
| P1-2 | 多开时通知只代表主格，四路各自出声 | `live_playback_target.dart`、`live_room_controller.dart` | 二期在聚焦切换处 attach/detach |
| P1-3 | Android 跳过 mpv 前向缓存配置 | `player_controller.dart`（`!Platform.isAndroid`） | 跟踪上游修复后放开 |
| P1-4 | 播放器释放时序依赖 media-kit #1443 | `player_controller.dart` dispose TODO | 升级时连同 libs 滤镜钉版一起核对 |
| P1-5 | Wayland 下置顶/几何提示 no-op | `services/window_service.dart` | 记录平台边界 |
| P1-6 | 4 路上限 + 每路缓冲内存；四路性能 spike 未跑 | `multi_play_layout.dart`、`lib/spike/multi_player_spike.dart` | 跑 spike；评估移动端默认路数 |
| P1-7 | 本机测试有存量失败（最近记录 15 条/6 文件） | 见 test-suite §7 | 桌面/真机复跑，分流「缺插件」与「真断言坏」 |

## P2 — 结构/技术债

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | 设置项未抽象 struct | `app_settings_controller.dart` TODO | 批量生成 UI/配置 |
| P2-2 | WebDAV 遗留：启动自动同步、version.json、历史删除保护 | `remote_sync/webdav/**` | 按同步批次补 |
| P2-3 | 直播间 uid 匹配临时实现 | `live_room_controller.dart` TODO | 精细化去重 |
| P2-4 | player_controller 遗留 TODO（动画/关弹窗/锁定） | `player_controller.dart` | 随手清理 |
| P2-5 | 弹幕字号跟随窗口缩放为临时实现 | `player_controls.dart` | 归入弹幕设置重构 |
| P2-6 | 关注页遗留：信息编辑占位、筛选条件设置 | `follow_user/**` | 产品确定后补 |
| P2-7 | 弹幕轨道等高网格，大表情改尺寸后重叠 | `player_controller.dart` | 库层或后置重排 |
| P2-8 | 迁移逻辑临时物 | `migration_service.dart` | 表驱动迁移 |
| P2-9 | OSD 明确不做项（容器统一、4 路上限、拖拽换位/换台等） | 设计稿结论 | 保持记录，勿重开 |
| P2-10 | `_appendDistinct` 每页重建 seen，跨页 O(n²) | `base_controller.dart` | 规模变大再提升为控制器状态 |
| P2-11 | 搜索页未接通 hasMore | `search_list_controller.dart` | 单独实测四平台语义 |
| P2-12 | `analysis_options.yaml` 未排除 `rust_builder/` | `analysis_options.yaml` | 加 exclude 降噪 |
| P2-13 | `followStyleNotGrid` 无读取方 | `app_settings_controller.dart` | 保留存储键，注释说明 |

## 已决策取舍

- 弹幕表情始终渲染（待复核 P0-5）。
- 通知不画进度条/不推 duration。
- 通知「停止」= 暂停 + 撤通知，不是 `player.stop()`。
- 副格永不挂后台通知。
- OSD 容器按宿主分：全屏/小窗/格子右侧面板，窗口化底部抽屉。
- 关注拖拽/勾选只「加入」不「移动」；批量写后由调用方统一排序。
- 降级旧版 App 看不到分组归属，但成员表仍在；降级期间不要清理/重建分组。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P0-1 音量均衡依赖定制 libmpv | `c3c6afc4`、`38e1106d`、`57ea33e5` |
| P0-5 表情开关 | 上游 `6da36e04` 引入开关，本 fork 未采用 |
| P1-6 多开性能 | `fcb43a82`（移动端多开）、`afd18194`（动作化） |
| P1-4 播放器释放时序 | media-kit fork `23ec6b9c` |
| P2-13 `followStyleNotGrid` 无读取方 | `1c0d02f5`（三栏后二选一消失） |
