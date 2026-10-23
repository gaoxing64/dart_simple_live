# simple_live_tv_app 修改历史（Git 完整复现）

> 锚点：future `52466f96`（2026-10-21）｜`git log future -- simple_live_tv_app` 全量 **9** 条
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/update-history.md)

> 作者列：G = gaoxing64（fork），S = SlotSun（上游）。

## 1. 复现命令

```bash
git log --date=short --pretty=format:'%h %ad %an %s' future -- simple_live_tv_app
git show --stat <hash> -- simple_live_tv_app
git log --all --date=short --pretty=format:'%h %ad %s' -- simple_live_tv_app | wc -l
```

历史已重写：future 根提交 `543910ba`；旧线在 `backup-future-*` / `origin/future`。

## 2. 全量时间线（9 条，新→旧）

| 日期 | 提交 | 作者 | 内容 |
| --- | --- | --- | --- |
| 2026-10-20 | `63197f69` | G | fix(account): 校验失败不再抹凭证，修复升级用户每次启动误报账号失效 |
| 2026-10-18 | `f72bb417` | G | refactor(core)!: 删除 Dart 协议实现，console 由 slive-cli 取代 |
| 2026-10-17 | `2465f9a3` | G | feat(tv): TV app 切换 Rust core（sites 直连绑定层 + RustLib.init） |
| 2026-10-14 | `ac7d8199` | G | docs(tv): 新增 simple_live_tv_app 知识库（5 份） |
| 2026-10-14 | `bafc703b` | S | ci: prebuild tv_app v1.5.1 with flutter v3.35.7 after |
| 2026-10-13 | `6da36e04` | S | feat(tv): 支持斗鱼扫码登录 |
| 2026-10-03 | `b0d408e6` | S | refactor: gen application settings by utils |
| 2026-10-03 | `062d5a83` | S | refactor: 调整项目结构 |
| 2026-07-30 | `543910ba` | S | feat(follow): add follow_user.last_watch_time |

## 3. 上游大版本（旧线摘要）

| 时间 | 节点 |
| --- | --- |
| 2026-08 | 上游 TV 1.6.6 / Flutter 3.47.1（与 future 的 1.5.1/3.35.7 非同一版本线） |
| 2026-01 ~ 02 | Flutter 3.38.6；虎牙房间搜索修复 |
| 2025-10 ~ 12 | Android TV 构建/发版完善；media_kit + canvas_danmaku；去 flutter_qjs |
| 2024-05 ~ 2025-04 | Banner、远程同步、自动更新关注、AGP 适配 |
| 2023-09 ~ 2024-03 | TV 项目初始化 → 首页/播放/双击返回 |

## 4. 当前状态

- 分支 future，HEAD `52466f96`；TV 自 2026-10-17（`2465f9a3`）起走 Rust FFI。
- 版本 `1.5.1+10501`，Flutter `3.35.7`。
- 9 条中 fork 4 条（Rust 切换、Dart 删除、账号、知识库），其余 5 条为上游/导入。
