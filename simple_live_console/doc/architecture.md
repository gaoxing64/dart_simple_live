# simple_live_console 架构与选型对照

> 版本锚点：`simple_live_console` v1.0.0 · future 分支 `3714eec1`（2026-10-11）
> 复核：截至 `5ae375f1`（2026-10-14）`simple_live_console` 源码无变化，本文件全部证据仍然有效。
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/architecture.md)

## 1. 工程布局

```
simple_live_console/
├── bin/simple_live_console.dart    # 唯一源码（120 行，全部逻辑）
├── test/all_live_console_test.dart # 占位测试（1 个空用例，line 4）
├── pubspec.yaml                    # 依赖声明（仅 path 依赖 core）
├── pubspec.lock                    # 依赖锁（含 test/analyzer 传递依赖）
├── analysis_options.yaml           # include: package:lints/recommended.yaml
├── README.md                       # 两条用法示例（-i / -d）
├── CHANGELOG.md                    # 仅 "1.0.0 - Initial version"
├── .fvmrc                          # flutter 3.35.7
├── .gitignore
├── .vscode/launch.json             # 默认调试参数：-d https://www.douyu.com/1126960
└── doc/                            # 本知识库（本次新增）
```

**没有 `lib/`**：这不是一个可被引用的 package，只是 script 目录 + 一个 `bin` 入口。

## 2. 单文件结构：函数职责表

全部逻辑在 `bin/simple_live_console.dart`，无内部分层（参数解析 / 业务 / 输出揉在一起）：

| 区域 | 行 | 职责 |
| --- | --- | --- |
| `main` | `:5-34` | 关闭 core 日志（`:6`）、解析 `arguments[0]`/`[1]`、分发到三条指令 |
| `printHelp` | `:36-39` | 打印两行用法说明 |
| `printInfo` | `:41-71` | 详情 → 清晰度列表 → `stdin` 交互选档 → 打印直链 |
| `printDanmaku` | `:73-98` | 详情 → `getDanmaku()` → 注册回调 → `start()` 常驻打印 |
| `parseUrl` | `:100-119` | URL → `[LiveSite 实例, roomId]`；按域名子串分流 4 平台 |

分层观察：**无接口层 / 无依赖注入 / 无错误边界**。`main` 直接 `await printInfo()`，异常一律上抛；输出直接用 `print`，没有输出格式化层（见 [backlog](./backlog.md)）。

## 3. 选型对照

### 3.1 命令行解析：手写 vs `package:args`

- **现状**：手写。`arguments.first` 取指令、`arguments[1]` 取 URL，`replaceAll("-","")` 归一化（`bin/simple_live_console.dart:12,18`）。
- **证据**：`pubspec.yaml:10-12` 只声明 `simple_live_core` 一个直接依赖；`args 2.7.0` 仅作为 `test` 的传递依赖出现在 `pubspec.lock:20-27`，源码未 `import 'package:args/args.dart'`。
- **对照 `package:args`**：可直接获得子命令（`-i`/`-d`）、长选项、自动 `--help`、参数校验与 usage 生成。
- **代价**：当前只有 `-i/-d` 两个短选项，无 `--json`、无版本号开关、`-h` 单独输入时被 `length<2` 拦截（`:13`），帮助信息硬编码两行（`:37-38`）。

### 3.2 输出格式：纯文本 vs 结构化

- **现状**：`print` 输出**中文纯文本**，字段用 `来源：/房间号：/线路1:` 等前缀（`:46-51,66-68`）。
- **对照 JSON**：脚本化消费需要 `--json` 之类的开关，把 `detail` / `quality` / `urls` 序列化为机器可读格式。
- **代价**：无法被 `jq` / 管道稳定解析；中文输出还依赖终端代码页（Windows 下需 UTF-8，见 [backlog P2-3](./backlog.md)）。

### 3.3 交互式 vs 批处理

- `-i` 在选定清晰度时阻塞等待 `stdin.readLineSync()`（`:60`），本质是一个**交互式**工具；批量场景下需要管道喂入序号。
- `-d` 用 `await Future(() {})`（`:97`）让进程常驻，没有退出信号 / 生命周期管理。

### 3.4 为什么独立成 CLI（与 app 的关系）

- `simple_live_app` / `simple_live_tv_app` 是 Flutter 图形端，承担 UI 与播放（media_kit）。
- `simple_live_console` 是**调试 / 脚本化**入口：验证 core 的取流链路是否可用、在无 GUI 环境（服务器 / CI / 排障）下拉直链或看弹幕。
- 它与 app **不共享任何 UI 代码**，唯一共享的是 `simple_live_core`；这保证了「core 改动后 console 能作为最小消费者的编译 / 冒烟探针」。

## 4. 依赖与边界

`pubspec.yaml` 全文（关键行）：

| 行 | 内容 | 说明 |
| --- | --- | --- |
| `:3` | `version: 1.0.0` | 版本锚点来源 |
| `:8` | `sdk: '>=2.19.1 <3.0.0'` | **SDK 上限仍锁 3.0.0**（见 backlog P2-1，待确认） |
| `:10-12` | `simple_live_core: {path: ../simple_live_core}` | 唯一运行时依赖（path） |
| `:14-16` | `lints: ^6.0.0` / `test: ^1.21.0` | 开发依赖 |

**边界约定**：

- console 只消费 `LiveSite` 的 5 个成员（`name` / `getRoomDetail` / `getPlayQualities` / `getPlayUrls` / `getDanmaku`），其余能力未使用（覆盖矩阵见 [workflow-diagram.md §4](./workflow-diagram.md)）。
- console **不解析** core 的 `dynamic` 私有载荷（`detail.data` / `danmakuData` / `quality.data`），而是原样回传，因此平台私有结构变化对 console 透明——这是它能长期不随 core 改动而改的原因。
- 反向依赖：core 不依赖 console；改动 core 的 `LiveSite` 签名（如 v1.1.0 的 `pageSize`）不影响 console（console 未调用列表接口）。2026-10-12（`abca65f8`）/2026-10-14（`5ae375f1`）两次上游同步同样未触及本目录；其间 `setSiteAttrs` 的入参由 `Map<String, dynamic>` 改为 JSON 串（`live_site.dart:103`），因 console 从未调用而不受影响。

## 5. 已知结构性问题（详见 backlog.md）

- 无参数校验层：`quality[index-1]` 越界即 `RangeError`（`:65`）。
- 无错误边界：网络 / 解析异常直接以 Dart 栈暴露给用户。
- 无输出格式开关、无 cookie/UA 注入（`setSiteAttrs` 未调用；core 侧现签名 `void setSiteAttrs(String data)`，`simple_live_core/lib/src/interface/live_site.dart:103`）。
- 测试为空壳（`test/all_live_console_test.dart:4`）。
- `pubspec.yaml:8` 的 SDK 上限与 `.fvmrc` 的 Flutter 3.35.7（Dart 3.x）存在潜在冲突。