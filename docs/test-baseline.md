# 测试基线

本文件记录 `future` 分支在引入 CI 时的测试现状，作为"修复进度"的对照基准。目标是把已知失败逐项清零后，再把 CI 的测试步骤改为阻断。

## 记录时间

2026-11-02，Flutter 3.47.8，`future` 分支。

## analyze

`flutter analyze --no-fatal-infos --no-fatal-warnings` 通过，0 个 error。存量 30 条 warning/info，属于待清理的技术债，不阻断合入。

## test

全量结果：667 通过、6 跳过、13 失败。

已知失败清单：

| 测试文件 | 用例 |
|----------|------|
| `test/widget_test.dart` | Counter increments smoke test（模板遗留用例，与当前首页无关） |
| `test/page_view_auto_load_test.dart` | 鼠标滚轮滚到底部自动加载 |
| `test/search_initial_site_test.dart` | 搜索页的初始平台（3 个）与端到端跟随首页（1 个） |

`search_initial_site_test.dart` 单独运行同样失败，说明不是并发隔离问题，是代码与测试预期已不一致。

## 修复约定

1. 新增或修改功能时，不得新增失败用例。
2. 修复上述用例后，在本文件删除对应行。
3. 清单清零后，把 `.github/workflows/ci.yml` 的 Test 步骤去掉 `continue-on-error`，改为阻断。
4. 模板遗留的 `widget_test.dart` 若确认无用，直接删除并在 PR 中说明。

## 格式

已按约定以独立的 `style: format` 提交统一存量格式（116 个文件），CI 的格式检查已改为阻断。

## 其他记录

- core 侧 Twitch 夹具用例（`ac_twitch_danmaku` 29 条 + `ac_twitch_fixtures` 14 条）于 2026-11-02 实测全绿，旧文档"8 条恒红"口径作废。
- 待办：Dart `Constant` 平台字符串与 Rust `Platform` 枚举 / `slive.h` C 宏的全量同步守护（现仅 douyin 有 `id_and_name_match_dart_constants`，C 宏有 `header_sync`）。
