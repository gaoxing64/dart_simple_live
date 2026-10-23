# simple_live_app 测试案例库（面向 AI）

> 锚点：future `52466f96`（2026-10-21）｜57 个 `*_test.dart`，全部离线
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 上游：[simple_live_core](../../simple_live_core/doc/test-suite.md)

## 1. 怎么跑

```bash
cd simple_live_app
fvm flutter test
fvm flutter test test/multi_play_layout_test.dart
fvm flutter test --plain-name "排布选择"
fvm flutter test integration_test/simple_test.dart -d windows
```

- FVM 锁 Flutter `3.47.6`；`test/` 不联网、不拉真实播放器。
- widget test 无 Hive/path_provider：用 `test/follow_test_harness.dart` 的内存假件；假设置的 `onInit` 必须是 `Future<void>`。
- 不要跑 `dart format`。

## 2. 资产概览

| 主题 | 代表文件 | 覆盖 |
| --- | --- | --- |
| 多开 | `multi_play_{layout,selection,volume,identity}_test.dart` | 排布/焦点/音量/身份 |
| 播放器动作/OSD | `player_action_set_test.dart`、`player_osd_metrics_test.dart` | 动作集合、容器判据、断点 |
| 快捷键 | `player_shortcuts_test.dart`、`shortcut_binding_test.dart` | 默认键位/改键/冲突/编解码 |
| 窗口/PiP | `pip_aspect_test.dart`、`pip_aspect_qa_test.dart`、`player_window_geometry_test.dart` | 纵横比/还原点 |
| 分页列表 | `base_page_controller_paging_test.dart`、`page_view_auto_load_test.dart` | hasMore/去重/门闩/补页 |
| 弹幕表情 | `danmaku_emoticon_test.dart`、`chat_emoticon_span_test.dart` | 分段/图源/聊天 span |
| 关注 | `follow_*_test.dart` | 搜索/分段/分组/多归属/智能分组/顶栏 |
| 导航/设置/工具 | `navigation_dock_test.dart`、`settings_switch_locked_test.dart`、`tool_test.dart` | 导航/控件/纯函数 |

## 3. AI 用例库

### 3.1 多开

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-A-101 | 1–4 路布局 | rows×cols 正确 |
| TC-A-102 | 增删一路 | 既有格位置不跳变 |
| TC-A-103 | 窗口缩小 | 先丢非聚焦格，保聚焦 |
| TC-A-106 | 勾选含未开播 | 先剔除再判上限 |
| TC-A-107 | 勾选 >4 在播 | `tooMany`，不截断 |
| TC-A-108 | 删格 | 焦点前移/夹到末格 |
| TC-A-110 | 音量真值表 | 压低/系数/焦点组合正确，恒 ≤ 总音量 |
| TC-A-112 | 第 5 路 | 提示已满，不新增 |
| TC-A-113 | 副格 | 不 attach 后台通知 |

### 3.2 播放器/OSD/快捷键

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-A-201 | 窗口化 vs 全屏动作 | bar∪overflow 集合相等 |
| TC-A-203 | 窄窗口 | 动作不消失，只进 ⋮ |
| TC-A-205 | 小窗 | 平铺四件 + ⋮ |
| TC-A-213 | 打开 ⋮ | 全屏/小窗/格子右侧面板；窗口化底部抽屉 |
| TC-A-301 | 默认键逐键 | 与约定表一致 |
| TC-A-302 | 非法键 | 不吞（W/E/T/Tab 等） |
| TC-A-305 | 快捷键模型 | 编解码往返、坏数据回落、冲突判定 |
| TC-A-306 | 改键 | 新键生效、旧键失效 |
| TC-A-401 | 点音量图标 | 本路静音，不落盘 |
| TC-A-403 | 滚轮 ±5% | 浮层出现并 1.2s 消失 |

### 3.3 窗口/PiP

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-A-501 | client/outer/insets 换算 | 与样例一致 |
| TC-A-503 | 幂等 | F(F(x))==F(x) |
| TC-A-504 | 全屏↔小窗还原点 | 尺寸/位置正确 |
| TC-A-505 | scaleMode | fit/aspectRatio，按格覆盖优先 |
| TC-A-506 | 四条窗口路径（手测） | 退出后回到进全屏前尺寸 |
| TC-A-507 | 平滑滚轮边界 | 累加/贴边/delta=0 停惯性 |

### 3.4 分页/列表

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-A-601 | `hasMore=false` | 一页即停 |
| TC-A-603 | 接口忽略翻页 | 连续两页零新增才停 |
| TC-A-605 | 空页 | `pageEmpty=true` 停止 |
| TC-A-606 | 非首页失败 | `loadMoreFailed`，失败页不自增 |
| TC-A-607 | 重试 | 重试同一页 `[1,2,2]`，成功清除重试条 |
| TC-A-608 | 别名回归 | 页面列表不与外部 List 共享引用 |
| TC-A-611 | 短列表补页失败 | 点击重试后重新请求 |
| TC-A-613 | 到底条 | 判据 `showEndBar` |

### 3.5 弹幕/关注/其他

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-A-701 | 表情分段 | 有 name 定位、无 name 追加 |
| TC-A-704 | 大表情高度 | 与库等高网格一致（已知重叠见 backlog P2-7） |
| TC-A-705 | 聊天 span | 分段正确 |
| TC-A-801 | 关注搜索 | 命中 remark/userName/title |
| TC-A-802 | 直播中/未开播分段 | `liveStatus==2` 归上段 |
| TC-A-810 | 成员表归属 | 加入不动其他组；移出只动该组；清空回未分组 |
| TC-A-811 | groupedView | 每个所属组都出现；幽灵 id 忽略；顺序继承 list |
| TC-A-812 | 备份双字段 | `tag` 兼容旧版，`tags` 全量；往返不丢 |
| TC-A-813 | WebDAV 合并 | 同名组按并集 |
| TC-A-815 | 智能分组 | preview 只算；execute 幂等；未知平台跳过 |
| TC-A-818 | 三栏/标签/胶囊（新增） | 标签过滤内容；胶囊显示首个+N；未分组不显示；搜索展开收起刷新；来源 `1c0d02f5`/`55928d21`/`52466f96` |
| TC-A-819 | 屏幕常亮引用计数（新增） | 多开/断线重连：每路各持一份，最后一个释放才熄屏；暂停/关房/直播终态释放；来源 `900f8d50` |
| TC-A-901 | 胶囊导航 | 点击/拖动透镜/几何 |
| TC-A-1001 | 时长文案 | 0 值空串；分/时档正确 |

## 4. 已知红灯（2026-10-14 记录，之后未重测）

`fvm flutter test --no-pub`：**507 通过 / 15 失败**，6 个文件：`search_initial_site_test`(9)、`theme_mode_test`(2)、`follow_grouped_view_test`(1)、`page_view_auto_load_test`(1)、`viewpager_drag_test`(1)、`widget_test`(1)。主因是真实 `AppSettingsController.onInit` 撞 `MissingPluginException` 与脚手架残留；属存量，不作为新回归。

## 5. 约定

1. 离线优先，网络注入 fake。
2. 纯函数直接 import 断言，不搭 widget。
3. 控制器测试继承真实类，只覆写 `getData`/`handleError`。
4. widget 测试用 harness；用 `tester.pump(Duration)`，不要 `pumpAndSettle`。
5. 命名 `<域>_<行为>_test.dart`；用例名中文描述行为。
6. 契约变更先在用例名引用本文 ID。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-A-101~111 多开 | `afd18194`、`fcb43a82`、`1826c57b` |
| TC-A-201~209 播放器动作/OSD | `b7188916`、`b4a97364`、`1826c57b` |
| TC-A-506 窗口还原/纵横比 | `d45cad06`、`49bfb83e`、`9a3f1313` |
| TC-A-601~608 分页 | `e1f7a75c`、`4e3c35a1` |
| TC-A-810~816 归属/备份/合并 | `3267a04e`、`a225e3b4`、`0442f4ac` |
| TC-A-818 三栏/标签/胶囊 | `1c0d02f5`、`55928d21`、`52466f96` |
| TC-A-819 常亮引用计数 | `900f8d50` |
