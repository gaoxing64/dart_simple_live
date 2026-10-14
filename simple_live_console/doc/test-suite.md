# simple_live_console 测试案例库（面向 AI 的文字版）

> 版本锚点：`simple_live_console` v1.0.0 · future 分支 `3714eec1`（2026-10-11）
> 复核：截至 `5ae375f1`（2026-10-14）`simple_live_console` 源码无变化，本文件全部证据仍然有效。
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/test-suite.md)

## 1. 怎么跑

```bash
cd simple_live_console
fvm dart test                                   # 全部（当前只有 1 个空用例）
fvm dart test test/all_live_console_test.dart   # 单个文件
fvm dart test --plain-name "parseUrl"           # 按用例名过滤
```

- 工程用 FVM 管理工具链（`.fvmrc:2` 锁 `flutter 3.35.7`）。
- **注意**：唯一运行时依赖 `simple_live_core` 自身依赖 Flutter SDK（见 core `backlog.md` P2-10），因此普通 `dart test` 可能在依赖解析阶段失败；若失败改用 `fvm flutter test`（**待确认**，本任务未执行构建）。
- `pubspec.yaml:15` 已声明 `test: ^1.21.0`，`package:test` 可直接使用。

## 2. 现有测试资产

| 文件 | 用例数 | 类型 | 守护的行为 |
| --- | --- | --- | --- |
| `test/all_live_console_test.dart` | 1 | 单元（空） | **无**：用例体为 `test('calculate', () {});`，无断言、不 import 业务代码（`test/all_live_console_test.dart:4`） |

结论：测试形同虚设，任何参数解析 / `parseUrl` 改动都无护栏（对应 [backlog P2-2](./backlog.md)）。

## 3. 覆盖矩阵

| 能力域 | 现状 | 缺口 |
| --- | --- | --- |
| 参数解析（main 分流） | 无 | 全部：空参数 / 缺参 / 未知指令 / `-i` 与 `--i` |
| `parseUrl` 平台识别 | 无 | 4 平台 + 未知域名 + 房间号形态 |
| 错误处理与退出码 | 无 | 异常路径、越界序号 |
| 输出格式稳定性 | 无 | 文本字段顺序、直链格式 |
| 交互式取流（stdin 选档） | 无 | 需进程级 / 管道测试 |

## 4. 文字版测试案例库

约定：`[已有]` = 现有用例已覆盖（给出来源）；`[待补]` = 建议新增（给出实现要点）。`parseUrl` 是顶层公开函数，可直接 `import '../bin/simple_live_console.dart'` 后调用。

### 4.1 参数解析（main 分流）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-CLI-001 | 空参数 `[]` | 打印帮助、正常返回、不抛异常 | [已有，仅占位] `all_live_console_test.dart:4` 未覆盖 |
| TC-CLI-002 | 只有指令 `['-i']`（`length<2`） | 打印「错误的参数」+ 帮助 | [待补] |
| TC-CLI-003 | 未知指令 `['-x','url']` | 打印「未知指令:x」+ 帮助 | [待补] |
| TC-CLI-004 | `-i ""`（空 URL） | 打印「[URL]不能为空」+ 帮助 | [待补] |
| TC-CLI-005 | `-i` 与 `--i` 等价 | 两者都进入 `printInfo` 分支（`replaceAll('-','')`） | [待补] |
| TC-CLI-006 | 单独 `-h` | **当前**打印「错误的参数」+ 帮助（锁定现状；期望直接帮助，见 backlog P1-1） | [待补] |

### 4.2 `parseUrl` 平台 / 房间号形态

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-CLI-010 | `https://www.bilibili.com/6` | 返回 `BiliBiliSite`，id = `6` | [待补] |
| TC-CLI-011 | `https://www.huya.com/660000` | 返回 `HuyaSite`，id = `660000` | [待补] |
| TC-CLI-012 | `https://www.douyu.com/1126960` | 返回 `DouyuSite`，id = `1126960` | [待补] |
| TC-CLI-013 | `https://live.douyin.com/123456` | 返回 `DouyinSite`，id = `123456` | [待补] |
| TC-CLI-014 | 未知域名 `https://example.com/1` | 抛 `Exception("链接解析失败")` | [待补] |
| TC-CLI-015 | 纯数字房间号 `123456`（非 URL） | **当前**落入 `throw`（不支持纯数字输入，锁定现状） | [待补] |
| TC-CLI-016 | 带前缀 / 非数字 id（如 `.../yy123`） | 记录提取结果（正则 `[\d|\w]+` 的实际行为） | [待补] |
| TC-CLI-017 | 正则字符类含 `|` 的边界 | 锁定当前匹配行为（备忘：`[\d|\w]` 应写作 `[\d\w]`，见 backlog P1-2） | [待补] |

### 4.3 错误处理与退出码

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-CLI-020 | 未捕获异常路径（如未知域名） | 进程以**非零**退出码结束、输出异常信息 | [待补]（需进程级测试） |
| TC-CLI-021 | 清晰度序号越界（如输入 `99`） | **当前**抛 `RangeError`（对应 backlog P0-1；修复后应变成可读提示） | [待补] |
| TC-CLI-022 | 网络失败（core 抛 `CoreError`） | 当前原始栈上抛；修复目标：一行中文提示 + 非零退出码 | [待补] |

### 4.4 输出格式稳定性

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-CLI-030 | 详情输出 | 字段前缀与顺序稳定：`来源/房间号/房间标题/直播用户/人气值/状态` | [待补] |
| TC-CLI-031 | 直链输出 | 每条为 `线路N:\r\n<url>`，N 从 1 递增 | [待补] |
| TC-CLI-032 | 未开播房间 | 只打印详情与「未开播」，不请求清晰度 | [待补] |

## 5. 命令级冒烟清单（可执行）

```bash
# 无参数 → 帮助
fvm dart run bin/simple_live_console.dart

# 单参数（length<2）→ 错误的参数 + 帮助
fvm dart run bin/simple_live_console.dart -i

# 未知指令
fvm dart run bin/simple_live_console.dart -x http://example.com

# 空 URL
fvm dart run bin/simple_live_console.dart -i ""

# 无法解析的链接（当前会抛 Exception）
fvm dart run bin/simple_live_console.dart -i http://example.com/1

# 交互式取直链（管道喂序号）
echo 1 | fvm dart run bin/simple_live_console.dart -i https://www.bilibili.com/6

# 弹幕（Ctrl+C 退出）
fvm dart run bin/simple_live_console.dart -d https://www.douyu.com/1126960
```

> 说明：`bin/simple_live_console.dart` 的异常都是未捕获的（无 `try/catch`），冒烟时以「是否输出可读提示 / 退出码」为判据。若 `dart run` 因 core 的 Flutter 依赖解析失败，改用 `fvm flutter pub run bin/simple_live_console.dart ...`（**待确认**）。

## 6. 写新测试的约定

1. **离线优先**：`parseUrl` 与参数分流是纯逻辑，**不要**写成联网用例；联网只会让 CI 不稳定。
2. **可测性前提**：`parseUrl` 已是顶层公开函数，可 `import '../bin/simple_live_console.dart'` 直接断言。参数分流目前写在 `main` 里，若要做到「无 stdout 副作用」的单测，建议把「`arguments` → 指令枚举」抽成一个纯函数（这也是 backlog P1-1 重构时的自然产物）。
3. **进程级用例**：退出码 / 交互式输入需 `Process.run` 起子进程断言，且应跳过网络依赖（用无法解析的 URL 触发本地分支）。
4. **锁定现状的用例**：对已知缺陷（`-h` 被拦、`[\d|\w]`、越界 `RangeError`）先写「当前行为」用例，并在 `reason:` 里引用 backlog ID，修复时同步翻转期望值。
5. **命名**：文件 `all_live_console_test.dart` 建议按域拆分（如 `parse_url_test.dart`）；用例名用中文描述行为，`reason:` 写明理由。

## 7. 与 backlog 的对应

- TC-CLI-021 ↔ **P0-1**（序号越界 RangeError）；
- TC-CLI-020 / TC-CLI-022 ↔ **P0-2**（无错误边界）；
- TC-CLI-002/003/004/006 ↔ **P1-1**（无子命令 / 帮助体系）；
- TC-CLI-010 ~ TC-CLI-017 ↔ **P1-2**（平台覆盖与 `parseUrl` 脆弱）；
- TC-CLI-030/031/032 ↔ **P1-4**（输出不可机读，先锁格式再加 `--json`）。