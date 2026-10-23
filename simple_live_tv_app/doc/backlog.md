# simple_live_tv_app 待办与优化清单

> 锚点：future `52466f96`（2026-10-21）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/backlog.md)

## P0 — 正确性风险

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | `AppFocusNode()` 在 `build`/`itemBuilder` 内新建，重建可能丢焦点/跳焦 | `modules/home/home_page.dart`、`category/category_page.dart`、`settings/settings_page.dart` | 节点提升到 State/Controller/列表模型，构建期只复用 |
| P0-2 | 设置页 `allSites[item.siteId]!`，同步来未知 siteId 会让整个设置页崩溃 | `modules/settings/settings_page.dart`；`app/sites.dart` 仅 4 站 | 取不到时跳过并提示 |

## P1 — 契约/平台脆弱点

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | 分页只按「本页非空」判继续，忽略 core 的 `hasMore`；抖音等可能提前到底 | `app/controller/base_controller.dart` | `getData` 返回 `(items, hasMore)` 并采信 |
| P1-2 | 同步来的账号只 `updateAccount`，不 `accountLogin`；设置页显示「暂未登录」直到重启 | `services/sync_service.dart`、`platform_service.dart` | 同步后补一次登录刷新 |
| P1-3 | TV 用 pub 版 media_kit，手机端用自建 fork；编码/兼容模式可能不一致 | `pubspec.yaml` vs `simple_live_app/pubspec.yaml` | 明确是否需要对齐 |
| P1-4 | 账号凭证明文进日志与 `toString`，Hive 明文存储 | `services/sync_service.dart`、`models/db/account.dart` | 脱敏；只打 siteId |
| P1-5 | 历史箱名 `TVHostiry` 拼写错误，改名会丢历史 | `services/db_service.dart` | 保留 + 注释，或做迁移后再改 |
| P1-6 | 账号按 `id` 覆盖，跨端同 id 会覆盖本地槽位 | `db_service.dart`、`migration_service.dart` | 按 `siteId` 归并 |

## P2 — 结构/技术债

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | 大量手机端设置项在 TV 无消费点（聊天区/PIP/动态色/定时关闭等） | `app/controller/app_settings_controller.dart` | 删除/补 UI/注明保留 |
| P2-2 | `playerCompatMode` 存储默认 true、字段默认 false | `app_settings_controller.dart` | 统一常量 |
| P2-3 | 测试资产只有 flutter create 模板 | `test/widget_test.dart` | 见 test-suite 最小清单 |
| P2-4 | `account.g.dart` 无 build_runner 生成链 | `pubspec.yaml` | 补生成器或注明手维 |
| P2-5 | 迁移脚本版本/槽位硬编码；`PackageInfo` 取两次 | `services/migration_service.dart`、`main.dart` | 表驱动；去重 |
| P2-6 | 上游账号迁移残留死常量/死文件 | `routes/route_path.dart`、`app/common/asT.dart` | 清理 |
| P2-7 | 无多路同播；Windows 目标未登记/未验证 | `modules/live_room/`、`.metadata` | 产品决策 + 明确交付范围 |

## 已决策取舍

- 只支持 4 平台（无 twitch）。
- 无弹幕发送、无后台播放/PIP、同步只做接收端、无网页登录/多账号并存。
- 沿用手机端设置模型（代价是僵尸项）。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P0-1 焦点节点内联创建 | `6da36e04` 新增的两处账号项 |
| P1-2 同步账号不即时生效 | `6da36e04`（账号体系落地） |
| P1-4 凭证入日志 | `6da36e04` |
