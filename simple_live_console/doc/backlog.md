# simple_live_console 待办与优化清单（backlog）

> 版本锚点：`simple_live_console` v1.0.0 · future 分支 `3714eec1`（2026-10-11）
> 复核：截至 `5ae375f1`（2026-10-14）`simple_live_console` 源码无变化，本文件 console 侧证据仍然有效；core 侧行号已按 HEAD 复核（见 P1-3）。
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/backlog.md)

## 0. 使用说明

- 每条含：**现象 → 证据（file:line）→ 建议动作 → 影响面**。
- 优先级：`P0` 用户可见的正确性 / 崩溃风险；`P1` 可用性与契约缺口；`P2` 结构 / 技术债。
- 行号基于锚点提交 `3714eec1` 的 `bin/simple_live_console.dart`（120 行，`5ae375f1` 起未变）；跨包（core）证据的行号一律按 `5ae375f1` 核对。改动前先 `git log -L` 核对。
- 第 5 节记录**已决策不修**的取舍，避免反复讨论。

## 1. P0 — 正确性与崩溃风险

### P0-1 清晰度序号无上界校验 → `RangeError`

- 现象：用户输入大于清晰度条数的序号时，`quality[index - 1]` 越界抛 `RangeError`，进程带 Dart 栈退出。`:62` 只用 `int.tryParse` 转了类型，`index > 0`（`:63`）只校验下界，**没有 `index <= quality.length` 校验**。
- 证据：`bin/simple_live_console.dart:62-65`。
- 建议：`if (index < 1 || index > quality.length)` 时打印可读提示并重新询问 / 退出。
- 影响：`-i` 的常规误操作即触发，用户可见。

### P0-2 全流程无错误边界，异常直接暴露

- 现象：`main` / `printInfo` / `printDanmaku` / `parseUrl` 均无 `try/catch`。网络失败（core 抛 `CoreError`）、未知域名（`:119` `throw Exception("链接解析失败")`）都会以原始 Dart 异常打破用户界面。
- 证据：`bin/simple_live_console.dart:41-119`（全文件无 `try` / `on Exception` / `catch`）。
- 建议：在 `main` 外层或各指令入口包一层捕获，把 `CoreError.message` / 解析失败转成一行中文提示 + 非零退出码。
- 影响：可用性；同时决定脚本化时的退出码是否稳定（见 [test-suite TC-CLI-3.x](./test-suite.md)）。

## 2. P1 — 可用性与契约缺口

### P1-1 无子命令 / 帮助体系，`-h` 单独输入不可用

- 现象：指令靠 `arguments[0]` 手写分流（`:12,24-33`）；`printHelp` 只有两行（`:37-38`），无版本号、无选项说明。且 `-h` 只有 1 个参数时先被 `arguments.length < 2`（`:13-17`）拦截，打印「错误的参数」而不是帮助。
- 证据：`bin/simple_live_console.dart:12-17,24-33,36-39`。
- 建议：引入 `package:args`（`pubspec.lock:20-27` 显示已作为传递依赖存在）或至少把 `-h/--help` 提前到 length 校验之前，并补 `--version`。
- 影响：新用户上手；脚本调用的一致性。

### P1-2 平台覆盖与房间号解析脆弱

- 现象：`parseUrl` 只识别 4 个域名子串（`:101,106,110,114`），Twitch 无分支；域名正则用字符类 `[\d|\w]`（`:103,107,111,117`），本意是「数字或词字符」，实际把字面量 `|` 也纳入匹配。
- 证据：`bin/simple_live_console.dart:100-119`（4 个 `if url.contains`）+ `:103` 等正则。
- 建议：字符类改为 `[\d\w]` 或 `\w`；补 Twitch 分支（core 已导出 `TwitchSite`，见 `simple_live_core/lib/simple_live_core.dart:9`）；无法识别时给可读提示而非 `throw`。
- 影响：覆盖面（当前落后于 core 的 5 平台）与解析健壮性。

### P1-3 cookie / UA 不可注入

- 现象：console 从不调用 `setSiteAttrs`。斗鱼 / 抖音 / B站的 cookie、虎牙的 UA 均无法通过 CLI 传入，只能吃 core 内置的匿名态。
- 证据：core 接口 `simple_live_core/lib/src/interface/live_site.dart:103`（`void setSiteAttrs(String data)`，`:100-102` 注释「`data` string2json来适配不同平台的credentials」）；console 全文件无该调用。
- **core 侧凭证口径已统一（2026-10-14）**：各实现均为「收 JSON 串 → `jsonDecode` → 按键取值」——B站 `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart:553`（取 `cookie`；本次合并 `5ae375f1` 才与其余平台对齐，dev 侧提交 `57d8f86d`）、抖音 `simple_live_core/lib/src/platforms/douyin/douyin_site.dart:1233`（`cookie` / `hlsFirst`）、斗鱼 `simple_live_core/lib/src/platforms/douyu/douyu_site.dart:344`（`cookie` / `dy_did` / `LTP0`）；虎牙只认 `ua`（`simple_live_core/lib/src/platforms/huya/huya_site.dart:559`），Twitch 未实现（`simple_live_core/lib/src/platforms/twitch/twitch_site.dart:298` 抛 `UnimplementedError`）。
- 建议：新增形如 `-c <cookie>` / 读环境变量的选项，转成 `setSiteAttrs(jsonEncode({'cookie': ...}))`——入参是 **JSON 串**而非 `Map`（锚点 `3714eec1` 处签名还是 `Map<String, dynamic>`，dev 的 `e3a090ad` 改为 `String`，经 merge `abca65f8` 进入 future）。
- 影响：需要登录才能取到的高清 / 完整链路在 CLI 侧不可用。

### P1-4 输出不可机读

- 现象：全部用中文纯文本 `print`（`:46-51` 详情、`:56-58` 清晰度、`:66-68` 直链），无结构化输出开关，管道 / `jq` 无法稳定解析。
- 证据：`bin/simple_live_console.dart:46-51,66-68`。
- 建议：增加 `--json` 选项，把 `detail` / `quality` / `urls` 序列化输出。
- 影响：自动化脚本的可用性。

## 3. P2 — 结构 / 技术债

### P2-1 SDK 上限仍锁 `<3.0.0`

- 现象：`pubspec.yaml:8` 为 `sdk: '>=2.19.1 <3.0.0'`，而 `.fvmrc:2` 指定 `flutter 3.35.7`（Dart 3.x）。两者是否冲突需实机确认（本任务未执行构建）。
- 证据：`pubspec.yaml:8`、`.fvmrc:2`。
- 建议：确认后把上限改为 `<4.0.0`。
- 影响：工具链能否用 Flutter 3.x 跑 console（**待确认**）。

### P2-2 测试为空壳

- 现象：唯一测试是 `test('calculate', () {});`，无断言、无 import 业务代码。
- 证据：`test/all_live_console_test.dart:1-5`（尤其 `:4`）。
- 建议：按 [test-suite.md §4](./test-suite.md) 的 TC-CLI 用例补参数解析 / `parseUrl` 的离线单测。
- 影响：任何改动都无护栏。

### P2-3 Windows 下中文输出依赖控制台代码页

- 现象：源码用 `print` 输出中文（`:37-38,46-51` 等），全文件无 `stdout.encoding` / 代码页处理。
- 证据：`bin/simple_live_console.dart`（无 `stdout` 相关语句）。
- 建议：在 Windows 终端显式设 UTF-8（`stdout.encoding = utf8`）或文档说明需切 UTF-8 代码页。
- 影响：Windows 用户可能看到乱码（**待确认**，取决于终端）。

### P2-4 弹幕模式无退出机制 / 生命周期

- 现象：`printDanmaku` 用 `await Future(() {})`（`:97`）挂起进程，没有 `stop()`、没有信号处理，只能强杀。
- 证据：`bin/simple_live_console.dart:96-97`。
- 建议：`onClose` 后结束 / 监听 `ProcessSignal.sigint` 调用 `danmaku.stop()`。
- 影响：`-d` 只能 Ctrl+C 硬退。

### P2-5 变量遮蔽 `url`

- 现象：`printInfo(String url)`（`:41`）内部在 `:64` 又声明局部 `var url`，遮蔽了参数，可读性差且易埋 bug。
- 证据：`bin/simple_live_console.dart:41` 与 `:64`。
- 建议：重命名为 `playUrl`。
- 影响：维护性。

### P2-6 README 与实现漂移

- 现象：README 示例写 `simple_live.exe -i [URL]`，但实现是 Dart CLI（无打包产物）；也未提及 `-h`、也未说明 `-i` 需要交互输入序号。
- 证据：`README.md:8,14`；`bin/simple_live_console.dart:60`。
- 建议：改为 `dart run bin/simple_live_console.dart ...` 并补充交互说明。
- 影响：文档准确性。

## 4. 建议的推进批次

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 1 | P0-1 / P0-2 | 都是「用户一操作就能看见」的崩溃 / 异常，改动局部 |
| 2 | P2-2（补 `parseUrl` 与参数解析离线单测） | 先有护栏再动解析逻辑 |
| 3 | P1-1 / P1-4 | 引入 `args` + `--json`，可一并重构参数层 |
| 4 | P1-3 / P1-2 | cookie 注入与 Twitch 分支，依赖 core 能力 |
| 5 | 其余 P2 | 按需 |

## 5. 已决策的取舍（不修，记录原因）

| 取舍 | 原因 | 来源 |
| --- | --- | --- |
| 保持单文件、不拆分 `lib/` | console 定位是调试 / 脚本化最小消费者，拆分收益低于维护成本 | `architecture.md` §2 |
| 保持交互式取流（`stdin` 选档） | 与上游 2023 年起的形态一致，非 fork 目标 | `bin/simple_live_console.dart:60` |
| 不解析 core 的 `dynamic` 私有载荷 | 原样回传给 CLI 输出即可，避免与 core 内部结构耦合 | `architecture.md` §4 |