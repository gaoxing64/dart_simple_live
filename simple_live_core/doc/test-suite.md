# simple_live_core 测试案例库（面向 AI 的文字版）

> 版本锚点：future `4795b165` + 2026-10-18 Dart core 清理
> 测试体系已全部落在 **Rust**：`cargo test`（无 Flutter 工具链依赖）。Dart 侧不再有测试文件。
> 配套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)

## 1. 怎么跑

```bash
cd simple_live_core

cargo test                          # 全量（slive-core + CLI；离线，约 30s）
cargo test -p slive-core            # 仅核心（918 用例）
cargo test -p slive-cli             # 仅 CLI（3 条 URL 解析）
cargo test -p slive-core --test ac_douyin_signature      # 单文件
cargo test -p slive-core golden_irc                     # 按用例名过滤
cargo test -p slive-core --features heldout             # 含 held-out 留出集（ADR-011）
cargo clippy --all-targets                              # 静态检查
```

- **全部离线**：HTTP 与 WS 均通过注入的假传输 / 假时钟驱动，不需要网络。
- 夹具在 `crates/slive-core/tests/fixtures/{platform}/`（真实抓包 + `bytes_hex`）。
- 联网验证用 CLI 直接跑真实房间：`cargo run -p slive-cli -- info <url>`。

### 1.1 当前基线（2026-10-18 实测）

| 范围 | 用例 | 通过 | 失败 |
| --- | --- | --- | --- |
| lib 单测 | 496 | 496 | 0 |
| 集成测试（30 个 `ac_*.rs`） | 439 | 439 | 0 |
| **合计** | **935** | **935** | **0** |

> 2026-10-18 虎牙大表情动态拉取新增 10 条 lib 单测 + 4 条集成用例
> （TARS 编解码 / 表合并 / 房间包覆盖 / 长中文码扫描 / TUP 成功、失败、超时 / 会话接线）；
> 全量复测 935 通过 / 0 失败，另 1 条 heldout 忽略。

> 2026-10-18 修复了此前恒红的 Twitch 8 条：`.gitattributes` 的 `* text=auto` 把 `.bin` 当文本，
> Windows checkout 转成 CRLF（7 条），且 `irc-crlf-boundary.bin` 在历史提交时丢了 `0d`（第 8 条）。
> 修法：加 `*.bin binary`、删除夹具重新 checkout、按 `bytes_hex` 重建该 bin。详见 backlog §5。

## 2. 现有测试资产

### 2.1 按平台

| 文件 | 用例 | 守护的行为 |
| --- | --- | --- |
| `tests/ac_douyin_signature.rs` | 14 | abogus / x_bogus / sm3 签名与公开用例向量 |
| `tests/ac_douyin_golden.rs` | 17 | 请求 URL、签名参数 golden（含顺序） |
| `tests/ac_douyin_detail_play.rs` | 18 | 详情三级兜底（reflow / web-enter / html）、清晰度、取流分支 |
| `tests/ac_douyin_lists.rs` | 15 | 分类与推荐分页（扇出、分区轮转、满页判据） |
| `tests/ac_douyin_danmaku.rs` | 15 | protobuf 解码、会员表情、needAck 回执、心跳 10s |
| `tests/ac_douyin_search_account.rs` | 20 | 搜索参数与风控、账号信息 |
| `tests/ac_douyin_fixtures.rs` | 12 | 夹具 ↔ 解析一致性 |
| `tests/ac_douyu_account.rs` | 25 | did 获取、扫码、`refreshCookie`、凭证注入 |
| `tests/ac_douyu_danmaku.rs` | 10 | STT 帧、join 序列、只受理粉丝发言 |
| `tests/ac_douyu_golden.rs` | 13 | 签名链 golden、请求体形状 |
| `tests/ac_douyu_http.rs` | 14 | 分类/推荐/详情请求与降级 |
| `tests/ac_douyu_fixtures.rs` | 9 | 夹具一致性 |
| `tests/ac_huya_danmaku.rs` | 15 | TARS 帧、组注册、SC 信号、心跳 |
| `tests/ac_huya_internals.rs` | 23 | antiCode、vip_room_id、tup 编解码内部件 |
| `tests/ac_huya_golden.rs` | 12 | 取流 URL golden（wsSecret/wsTime/seqid/uuid） |
| `tests/ac_huya_http.rs` | 22 | HTML 正则解析、列表分页、线路容错 |
| `tests/ac_huya_fixtures.rs` | 12 | 夹具一致性 |
| `tests/ac21_wbi_golden.rs` | 2 | B站 wbi 签名 golden |
| `tests/ac_account.rs` | 9 | B站扫码/校验/凭证注入（含 `user_id` 回填副作用） |
| `tests/ac_attrs_golden.rs` | 3 | `set_site_attrs` 各平台键契约 |
| `tests/ac_http_list.rs` / `ac_http_detail_play.rs` | 10 + 12 | B站列表/详情/取流请求形状 |
| `tests/ac_emoticon.rs` | 7 | B站表情包解析（两入口、去重、上限 8、https 归一） |
| `tests/ac_twitch_danmaku.rs` | 29 | IRC 解析、PING→PONG、40s 心跳、5 次重连 |
| `tests/ac_twitch_golden.rs` / `ac_twitch_quality_golden.rs` | 12 + 5 | GQL golden、清晰度映射 |
| `tests/ac_twitch_http.rs` | 23 | 详情 GQL、m3u8、不支持能力报错口径 |
| `tests/ac_twitch_fixtures.rs` | 14 | 夹具 ↔ `bytes_hex` 一致性 |
| `tests/ac_tars_codec.rs` / `ac_tars_wire.rs` | 30 + 10 | 手写 TARS 编解码与线格式 |
| `crates/slive-cli/src/url.rs`（`#[cfg(test)]`） | 3 | 五平台 URL 解析、query/fragment 剥离、非法输入 |

### 2.2 lib 内联单测（486 条）

分布在 `crates/slive-core/src/**` 的 `#[cfg(test)] mod tests`：签名算法、帧编解码、模型转换、分页纯函数、错误映射等。数量按平台：抖音 180 / 虎牙 93 / 斗鱼 80 / Twitch 50 / B站 20 / 基础设施（tars+ws）60。

## 3. 覆盖矩阵

| 能力 | bilibili | douyu | huya | douyin | twitch |
| --- | --- | --- | --- | --- | --- |
| 列表分页 | ✅ | ✅ | ✅ | ✅ | 不支持 |
| 详情 / 清晰度 / 取流 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 弹幕解码 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 表情解析 | ✅ | 不支持 | ✅ | ✅ | 不支持 |
| 账号接口 | ✅ | ✅ | 桩 | ✅/桩 | 桩 |
| 凭证注入 `set_site_attrs` | ✅ | ✅ | ✅ | ✅ | 桩 |
| 签名 golden | ✅ | ✅ | ✅ | ✅ | 无签名 |
| 离线夹具 | ✅ | ✅ | ✅ | ✅ | ✅ |

## 4. 文字版测试案例库

约定：`[已有]` = 现有用例已覆盖（给出来源）；`[待补]` = 建议新增（给出实现要点）。

### 4.1 分页契约（跨平台）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-P01 | 斗鱼推荐第 1 页 40 条、`pgcnt=0` | `has_more == true`（不能采信 pgcnt） | [已有] `ac_douyu_golden` / lib 单测 |
| TC-P02 | 斗鱼推荐空载荷 | `items` 空、`has_more == false`、不报错 | [已有] |
| TC-P03 | 斗鱼推荐响应缺字段 | 按空页处理，不报错 | [已有] |
| TC-P05 | 抖音分类第 1/2 页 | `partition=101`、`partition_type=4`、`offset=0/15`、`count=15` | [已有] `ac_douyin_lists` |
| TC-P06 | 抖音分类返回 3 条（不满 15） | `has_more == false`（判据是满页不是非空） | [已有] |
| TC-P07 | 抖音分类 `data: null` / `[]` | 降级空页，不 panic | [已有] |
| TC-P08 | 抖音分类含 null / 缺 `room` 的脏条目 | 只跳过脏条目，`has_more` 看原始条数 | [已有] |
| TC-P09 | 抖音推荐首屏 `page_size=30` | 扇出 ≥4 路、并发、声明 `has_more=true`、不碰分区 | [已有] |
| TC-P10 | 抖音推荐首屏 `page_size=500` | 扇出封顶 6 | [已有] |
| TC-P11 | 抖音推荐首屏切片参数 | 每路 count 互不相同 | [已有] |
| TC-P12 | 首屏个别切片失败 | 其余正常、`has_more` 仍 true | [已有] |
| TC-P13 | 首屏全部切片失败 | 返回错误（不静默空） | [已有] |
| TC-P15 | 推荐第 2/3 页 | 走 `partition/detail/room/v2`，slot0→slot1，`offset=0`、`count=20` | [已有] |
| TC-P16 | 第 `2+slots` 页 | 回到第 1 个分区、`offset=20` | [已有] |
| TC-P17 | 某分区翻空 | 顺延下一分区，而不是判到底 | [已有] |
| TC-P18 | 一圈分区全空 | `has_more=false`，恰好请求分区数那么多次 | [已有] |
| TC-P21 | bilibili 推荐 `page_size=60` | 请求里出现 `page_size=60` | [已有] `ac_http_list` |
| TC-P22 | 任何平台空列表 | `items` 空 + `has_more=false`，不报错 | [已有] |

### 4.2 详情与取流

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-D01 | 抖音 19 位 roomId | 只请求 `reflow/info`，不走 `web/enter`；画质从高到低 | [已有] `ac_douyin_detail_play` |
| TC-D02 | 抖音降级房间（无 stream_url） | `status=false`、`data` 有值、画质空、不 panic | [已有] |
| TC-D03 | `web/enter` + 网页兜底都失败 | 返回 `SliveError::Api`（不是空指针） | [已有] |
| TC-D04 | `web/enter` 报在播但缺 stream | 用 roomId 补查 `reflow/info`，恢复真实状态 | [已有] |
| TC-D05 | 只有 `flv_pull_url` / `hls_pull_url_map` | 回退拼出 3 档画质 | [已有] |
| TC-D06 | `detail.data` 为 null / 非 Map | 返回空清晰度，不报错 | [已有] |
| TC-D07 | 抖音搜索被风控 | 返回带中文提示的错误 | [已有] `ac_douyin_search_account` |
| TC-D08 | twitch `search_anchors` | 返回 `Api{code:-1}`「暂不支持」 | [已有] `ac_twitch_http` |
| TC-D09 | 虎牙单线路取流失败 | 跳过该线路，其余成功 | [已有] `ac_huya_http` |
| TC-D10 | B站 mcdn 线路 | 含 `mcdn` 的排到最后 | [已有] `ac_http_detail_play` |

### 4.3 弹幕解码

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-M01 | B站包头解析 | 16 字节头正确；op=3 产出 `Online(int32)` | [已有] `ac_http_detail_play` / lib 单测 |
| TC-M02 | B站协议版本 0/2/3 | JSON / zlib / brotli 三路解压都能切出多条 | [已有] |
| TC-M03 | 斗鱼 STT 反序列化 | `type@=chatmsg/...@=/` → map；`fans != 1` 丢弃 | [已有] `ac_douyu_danmaku` |
| TC-M04 | 斗鱼帧重组 | 包长重复两次 + type 689 头尾正确切帧，粘包不丢消息 | [已有] |
| TC-M05 | 虎牙 tars 解码 | type=7（uri 1400→chat / 8006→online）、type=22（vMsgItem 遍历） | [已有] `ac_huya_danmaku` |
| TC-M06 | 虎牙 SC 触发 | content 命中上头条正则 → 走 `SuperChatFetcher` | [已有] |
| TC-M07 | 抖音 protobuf | `PushFrame → gzip → Response`；`needAck` 回 Ack；Chat/RoomUserSeq/Emoji 三类消息 | [已有] `ac_douyin_danmaku` |
| TC-M08 | Twitch IRC | `PING` → `PONG`；PRIVMSG + display-name + color 齐备才产出 chat | [已有] `ac_twitch_danmaku` |
| TC-M09 | 任意平台解码异常 | 只记日志、不断连、不抛出 | [已有] |
| TC-M10 | 多开互不停止 | 各句柄 stop 通道独立：停 A 不影响 B；句柄释放（发送端 drop）→ 本会话 `Closed("已手动停止")` 不重连 | [已有] lib 单测（`sender_drop_ends_session_without_reconnect` / `stop_channels_are_per_connection`） |

### 4.4 表情包

| ID | 契约 | 状态 |
| --- | --- | --- |
| TC-E01 | `extra.emots` 只保留 message 中真正出现的占位符 | [已有] `ac_emoticon` |
| TC-E02 | 多表情按下发顺序 | [已有] |
| TC-E03 | `info[0][13]` 单表情三种形态（占位符 / 裸名 / 夹正文） | [已有] |
| TC-E04 | 两入口同图去重，`large` 判据一致 | [已有] |
| TC-E05 | 裸表情名上限 12 字，含空白/方括号丢弃 | [已有] |
| TC-E06 | 单条 8 个上限在入口截断 | [已有] |
| TC-E07 | 图片地址统一 https；非法形态丢弃 | [已有] |
| TC-E08 | 异常载荷返回 None，不 panic | [已有] |
| TC-E11 | 抖音会员/守护表情 + 214 项标准 `[码]` 映射 | [已有] lib 单测 + `ac_douyin_danmaku` |
| TC-E12 | 虎牙大表情：按房间 `lPid` 拉 `getExpressionEmoticonPackage`；`steam.png → steam_3.png`；动态项 `large=true`；API 失败回退静态 97 项 | [已有] lib 单测（TARS/表合并/会话接线） |

### 4.5 接口与基础设施契约

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-I02 | 四平台 `set_site_attrs(String)` | JSON 按键注入：bilibili 取 `cookie`、douyu 取 `cookie`/`dy_did`/`LTP0`、huya 取 `ua`、douyin 取 `cookie`/`hls_first`；缺键静默保留旧值 | [已有] `ac_attrs_golden` |
| TC-I03 | HTTP 错误映射 | 非 2xx / 网络失败 / 解码失败分别映射到 `Api` / `Network` / `Decode` | [已有] lib 单测 |
| TC-I05 | 会话重连 | 断线 5s 重连、5 次后 `Closed`；收到消息后计数归零 | [已有] 各平台 session 用例 |
| TC-I06 | 弹幕生命周期 | `Ready → Message* → Closed`；`stop()` 后回调不再触发 | [已有] |
| TC-I07 | `LiveMessageColor::number_to_color` | 4/6/8 位 hex 转换正确；非法回落白色 | [已有] lib 单测 |
| TC-I09 | CLI URL 解析 | 五平台识别、query/fragment 剥离、空/未知站点报错 | [已有] `slive-cli` 单测 |

### 4.6 联网冒烟（发版前跑）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-N01 | `slive info <各平台真实房间>` | 打印详情 + 清晰度 + 直链 + 请求头 | [手工] |
| TC-N02 | `slive danmaku <在播房间>` | `[已连接]`，持续输出 `用户：内容` | [手工] |
| TC-N03 | 闭播房间 | `状态：未开播`，`info` 正常退出；`danmaku` 报「无法获取弹幕」 | [手工] |

### 4.7 账号接口

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A04 | B站 `get_qr_poll_result` 状态映射 | 86038→expired、86090→scanned、0→scanned 且从 `set-cookie` 汇总 `{"cookie": ...}` | [已有] `ac_account` |
| TC-A05 | 斗鱼扫码状态映射 | -2→unscanned、1→scanned、-1→expired、0→确认并产出 `{dy_did,LTP0,cookie}` | [已有] `ac_douyu_account` |
| TC-A09 | `get_account_info` 校验成功/失败 | 成功回填 name/avatar/uid/credential 且 bilibili 回填 `user_id`；失败 `is_valid=false` 不报错 | [已有] |
| TC-A02 | huya / twitch 账号桩 | 返回 `InvalidInput`（含「Dart core 亦未实现」后缀） | [已有] `ac_attrs_golden` / `ac_twitch_http` |

## 5. 写新测试的约定

1. **离线优先**：能靠合成响应覆盖的逻辑不写联网用例。HTTP 走 `with_deps(假 HttpTransport, 假 TimeSource)`，WS 走注入的 `ConnectFactory`。
2. **时间可注入**：涉及心跳/重连/过期的用例一律用假时钟（`TimeSource` 立即返回），不要 `sleep`。
3. **夹具带 `bytes_hex`**：二进制夹具必须同时给 hex 与长度，`ac_*_fixtures` 会校验一致（Twitch 的 8 条红灯正是这条断言抓到的）。
4. **不静默兜底**：不支持的平台能力要断言**具体错误类型与文案**，不要断言「返回空」。
5. **命名**：集成文件 `tests/ac_<平台>_<域>.rs`；用例名用中文描述行为 + 括号给条件；lib 单测放模块内 `#[cfg(test)]`。
6. **契约变更时**：在用例名或注释里引用本文件 ID（如「TC-P06 判据由非空改为满页」）。

## 6. 与 backlog 的对应

- §4.6 的三条手工冒烟 → **P1-6**（CLI 端到端联网回归）；
- 夹具一致性由 `ac_*_fixtures` 强制（`bytes_hex` / `bytes_len` 与 `.bin` 必须逐字节相符），
  2026-10-18 正是这条断言抓到了 Git 行尾规范化对 `.bin` 的破坏；
- §4.7 的账号用例已补齐 Rust 侧，残留缺口是「扫码全链路真机验证」→ **P2-3**；
- 抖音签名用例的样本会随平台风控失效 → **P1-3**。
