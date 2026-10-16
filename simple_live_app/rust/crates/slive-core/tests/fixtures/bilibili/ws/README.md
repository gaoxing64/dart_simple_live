# WS 帧夹具（F-11~F-16 / AC-11~AC-16 / AC-28）

## 帧格式（已被 Dart 源码核实）

16 字节头（大端）：

| 偏移 | 长度 | 字段 | 值 |
|------|------|------|-----|
| 0 | 4 | 包总长（含头） | `16 + body.len()` |
| 4 | 2 | 头长 | `16`（固定） |
| 6 | 2 | 协议版本 protover | `0`=JSON / `2`=zlib / `3`=brotli |
| 8 | 4 | 操作码 op | `3`=人气 / `5`=通知 / `7`=加入 / `2`=心跳 |
| 12 | 4 | 序列 seq | `1` |

来源：`bilibili_danmaku.dart:119-145`（`encodeData`）、`:147-184`（`decodeMessage`）、`:241-261`（`readInt`）。

## 文件

| 文件 | op / protover | 服务 AC | 期望（见同名 `.expected.json`） |
|------|---------------|---------|--------------------------------|
| `frame-op3-online.bin` | 3 / 0 | AC-12 | `online`，人气 12345（`00 00 30 39`） |
| `frame-op5-ver0-chat.bin` | 5 / 0 | AC-13, AC-14 | `chat`（`tester` / `hello world` / 白色） |
| `frame-op5-ver2-zlib.bin` | 5 / 2 | AC-13 | zlib 解压后同上 |
| `frame-op5-ver0-superchat.bin` | 5 / 0 | AC-15 | `superChat` + `LiveSuperChatMessage` |
| `frame-op5-dirty-length.bin` | 5 / 0 | AC-28 | **无产出、不断连、不抛**（声明长度 999 ≠ 真实 18 字节） |

## 解码规则（Dart `decodeMessage`，Rust 须对齐）

- `op=3`：`body` 前 4 字节 big-endian int32 = 人气；body 不足 4 字节 → 只记日志、不崩。
- `op=5`：按 `protover` 解压（0 直读 / 2 `zlib.decode` / 3 `brotli.decode`）；`utf8.decode(allowMalformed)` 容忍脏字节；按 `[\x00-\x1f]+` 切分；保留以 `{` 开头且长度 > 2 的片段逐条 `parseMessage`。
- 解压/解码失败 → 只记日志、不断连、不抛（AC-28）。

## 待补

- `frame-op5-ver3-brotli.bin`（AC-13）：实现期用 `slive-core` 的 `brotli` crate 生成（与解码对称），或抓包补齐（架构 §8.4(e)）。

## ⚠️ 合成声明

帧**头结构**来自 Dart 源码（A 级核实）；帧**负载内容**（DANMU_MSG / SUPER_CHAT_MESSAGE JSON）为**合成**，字段取自 Dart 解析代码（`bilibili_danmaku.dart:186-235`：`cmd`/`info[1]`/`info[0][3]`/`info[2][1]`/`data.{price,start_time,end_time,user_info.face,user_info.uname,...}`）。真实弹幕载荷形态待抓包替换。
