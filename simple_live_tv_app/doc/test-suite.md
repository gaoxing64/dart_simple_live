# simple_live_tv_app 测试案例库（面向 AI）

> 锚点：future `52466f96`（2026-10-21）｜TV 端几乎无自动化测试
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 上游：[simple_live_core](../../simple_live_core/doc/test-suite.md)

## 1. 怎么跑

```bash
cd simple_live_tv_app
fvm flutter test
fvm flutter analyze
```

- FVM 锁 Flutter `3.35.7`（与 app 的 3.47.6 不同）。
- `test/` 仅 1 个 `flutter create` 默认模板（断言计数器），实际无意义，应删除/重写。

## 2. 现有测试资产

| 文件 | 类型 | 状态 |
| --- | --- | --- |
| `test/widget_test.dart` | widget | 默认模板残留，断言 `0/1/Icons.add`，与真实 App 不符 |

## 3. AI 用例库（建议）

### 3.1 纯函数/模型（离线，优先）

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-TV-01 | 无 | `Utils.parseVersion('1.5.0')` | `10500` |
| TC-TV-02 | 无 | `Utils.onlineToString(123456)` | `12.3万` |
| TC-TV-03 | 无 | `Utils.isRegexFormat('/abc/')` | true；`'abc'` false |
| TC-TV-04 | 无 | `Utils.parseTime` 同日/同年/跨年 | `HH:mm` / `MM-dd HH:mm` / `yyyy-MM-dd HH:mm` |
| TC-TV-05 | Hive 初始化 | `FollowUser` 适配器写→读 | 字段一致 |
| TC-TV-06 | Hive 初始化 | `History` 适配器写→读 | 字段一致 |
| TC-TV-07 | Hive `account` 箱 | `Account` 写→读 | 只还原 5 字段；profile 字段丢失（P1-2 证据） |
| TC-TV-08 | 空库 | `MigrationService` 版本 <10501 | 创建 bilibili/douyu 空账号槽；写回版本 |

### 3.2 分页控制器

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-TV-10 | 测试子类 | 首页返回非空 | `currentPage++`、`canLoadMore=true` |
| TC-TV-11 | 同上 | 首页返回空 | `canLoadMore=false`、`pageEmpty=true` |
| TC-TV-12 | 同上 | 非首页返回空 | `canLoadMore=false`，不置 `pageEmpty` |
| TC-TV-13 | 同上 | `getData` 抛异常 | `pageError=true` |
| TC-TV-14 | 同上 | 断言现状 | `canLoadMore` 只由本页非空决定（P1-1 回归锚点） |

### 3.3 焦点/按键（widget + 手工）

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-TV-20 | pump `HighlightWidget` | 聚焦 | 放大 1.1、白底黑字、阴影 |
| TC-TV-21 | 同上 | `Enter/Space/Select` | 触发 `onTap` |
| TC-TV-22 | 同上 | 方向键 | 未覆写时 `ignored`，由默认 traversal 处理 |
| TC-TV-23 | 设置项 | 左右键 | 枚举值循环并落盘 |

## 4. 遥控器手工冒烟

1. 冷启动 → 首次协议页 → OK 进首页；横屏全屏。
2. 首页四向移动，焦点视觉正确。
3. 热门列表到底自动加载下一页。
4. 返回键：列表→首页；首页再返回不崩溃。
5. 搜索：直播间/主播切换、输入、进房。
6. 类目：左右切平台，OK 进子类。
7. 房间：OK 显隐控制条；Menu/→ 打开设置；左右改清晰度/线路/比例/弹幕；返回还原焦点。
8. 切台：↑/↓；← 关注弹窗切台。
9. 未开播：提示；录像：轮播提示。
10. 断网：列表错误态可刷新；房间不崩溃。
11. 同步：本机二维码；手机推送关注后首页刷新。
12. 扫码：设置→账号→B站/斗鱼→二维码→自动返回；失效 Toast。
13. 账号同步后仍显示「暂未登录」= 已知缺口（P1-2），不是崩溃。

## 5. 约定

- 离线优先；不写联网必跑用例。
- 不断言真实帧/耗时；只断言结构与状态。
- 文件名 `<域>_<主题>_test.dart`；用例名用中文行为描述。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-TV-07/08 账号与迁移 | `6da36e04`、`63197f69` |
| Rust 初始化 | `2465f9a3` |
