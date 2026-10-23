# simple_live_core 测试案例库（面向 AI）

> 锚点：future `52466f96`（2026-10-21）｜Rust 测试，离线优先
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 下游：[App](../../simple_live_app/doc/test-suite.md)｜[TV](../../simple_live_tv_app/doc/test-suite.md)

## 1. 怎么跑

```bash
cd simple_live_core
cargo test                                  # 全部（离线）
cargo test -p slive-core                    # 核心
cargo test -p slive-cli                     # CLI URL 解析
cargo test -p slive-core --test ac_douyin_signature
cargo test -p slive-core --features heldout # held-out 留出集
cargo clippy --all-targets
```

- HTTP/WS 通过 `with_deps(假传输, 假 TimeSource)` / `ConnectFactory` 注入，无需联网。
- 夹具：`crates/slive-core/tests/fixtures/{platform}/`（含 `bytes_hex`）。
- 联网冒烟：`cargo run -p slive-cli -- info <url>`。

## 2. 现有资产

- **31 个集成文件**：`ac_douyin_*`（7）、`ac_douyu_*`（5）、`ac_huya_*`（6）、`ac_twitch_*`（5）、`ac_tars_*`（2）、B站/账号/属性/表情等（5）、`ac21_wbi_golden`。
- **lib 内联单测**：签名、帧编解码、模型转换、分页纯函数、错误映射。
- **基线（2026-10-18 实测）**：935 通过 / 0 失败（lib 496 + 集成 439）；此后新增虎牙表情与句柄用例，当前文件数 31。
- 历史红灯：Twitch `.bin` 被 CRLF 污染，已由 `7b6341d5` 修复。

## 3. AI 用例库

### 3.1 分页

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-P01 | 斗鱼推荐 | 40 条、pgcnt=0 | `has_more=true` |
| TC-P02 | 斗鱼推荐 | 空载荷 | items 空、`has_more=false`、不报错 |
| TC-P05 | 抖音分类 | 第 1/2 页 | partition/offset/count 正确 |
| TC-P06 | 抖音分类 | 返回 3 条（<15） | `has_more=false` |
| TC-P09 | 抖音推荐首屏 | page_size=30 | 扇出 ≥4、并发、`has_more=true` |
| TC-P15 | 抖音推荐 | 第 2/3 页 | 分区轮转、offset/count 正确 |
| TC-P17 | 抖音推荐 | 某分区翻空 | 顺延下一分区 |
| TC-P18 | 抖音推荐 | 一圈全空 | `has_more=false` |
| TC-P22 | 任意平台 | 空列表 | items 空 + `has_more=false` |

### 3.2 详情/取流

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-D01 | 抖音 19 位 roomId | 取详情 | 只走 `reflow/info` |
| TC-D04 | 抖音 web-enter 在播缺 stream | 取详情 | 补查 reflow 恢复 |
| TC-D05 | 抖音仅 `flv_pull_url` | 取清晰度 | 回退拼 3 档 |
| TC-D09 | 虎牙单线路失败 | 取流 | 跳过该线路，其余成功 |
| TC-D10 | B站 mcdn | 取流 | mcdn 排最后 |

### 3.3 弹幕

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-M01 | B站帧 | 解析包头 op=3 | `Online(int32)` |
| TC-M02 | B站 protobuf | ver 0/2/3 | JSON/zlib/brotli 均可解 |
| TC-M03 | 斗鱼 STT | `fans!=1` | 丢弃 |
| TC-M05 | 虎牙 TARS | type=7/22 | chat/online/SC 正确 |
| TC-M07 | 抖音 | PushFrame→gzip | needAck 回执；三类消息 |
| TC-M08 | Twitch IRC | PING | 回 PONG；PRIVMSG 解析 |
| TC-M10 | 多开 | 停 A / 释放句柄 B | 互不影响；释放即 Closed，不重连 |

### 3.4 表情/账号/接口

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-E01 | B站 extra.emots | 解析 | 只保留消息中出现的占位符 |
| TC-E06 | 单条 >8 表情 | 解析 | 截断为 8 |
| TC-E12 | 虎牙大表情 | 动态包 | `large=true`；失败回退静态 97 项 |
| TC-A04 | B站扫码 | 86038/86090/0 | expired/scanned/确认并产出 `{"cookie"}` |
| TC-A05 | 斗鱼扫码 | -2/1/-1/0 | unscanned/scanned/expired/确认 |
| TC-I02 | 四平台 set_site_attrs | JSON 注入 | 按键注入；缺键保留旧值 |
| TC-I05 | 断线 | 5s×5 | 5 次后 Closed；收到消息归零 |

### 3.5 联网冒烟（发版前）

| ID | 步骤 | 期望 |
| --- | --- | --- |
| TC-N01 | `slive info <真实房间>` | 详情 + 清晰度 + 直链 + headers |
| TC-N02 | `slive danmaku <在播房间>` | `[已连接]` 并持续输出 |
| TC-N03 | 闭播房间 | `info` 显示未开播；`danmaku` 报无法获取 |

## 4. 约定

1. 离线优先；联网用例标 `#[ignore]` 或手工。
2. 时间可注入，禁止 `sleep`。
3. 二进制夹具必须带 `bytes_hex` 与长度（`ac_*_fixtures` 校验）。
4. 不支持的平台能力断言具体错误类型与文案，不断言「返回空」。
5. 集成文件 `tests/ac_<平台>_<域>.rs`；lib 单测放模块 `#[cfg(test)]`。
6. 契约变更时在用例名/注释引用本文 ID。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-M10 多开互不停止 | `3f0ac946`、`eecc060f` |
| TC-E12 虎牙大表情 | `953f78b7` |
| TC-P05~P18 抖音分页 | `49eef9c3` |
| 夹具一致性 | `7b6341d5` |
