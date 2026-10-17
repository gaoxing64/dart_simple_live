# simple_live_core 测试案例库（面向 AI 的文字版）

> 版本锚点：`simple_live_core` v1.1.0 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)

## 1. 怎么跑

```bash
cd simple_live_core
fvm flutter test                                   # 全部（含联网冒烟，耗时 >60s）
fvm flutter test test/douyin_recommend_fanout_test.dart   # 单个文件
fvm flutter test --plain-name "首屏"              # 按用例名过滤
```

- 工程用 FVM 管理 Flutter（本目录 `.fvmrc` 锁 `3.38.4`；注意与 `simple_live_app` 的 `3.47.6` 不同）。
- **离线用例**（adapter 注入，无网络）与**联网冒烟**（真实请求，含 30s 弹幕窗口）混在同一目录；CI/本地批量跑时建议先跑离线集。
- 所有离线用例都通过替换 `HttpClient.instance.dio.httpClientAdapter` 注入合成响应，并在 `tearDown` 还原（模式见 `douyin_recommend_fanout_test.dart` 的 `_install()`）。

## 2. 现有测试资产

| 文件 | 用例数 | 类型 | 守护的行为 |
| --- | --- | --- | --- |
| `test/simple_live_core_test.dart` | 10 | 联网 | 5 平台冒烟：推荐/分类/搜索/详情/清晰度/播放地址/弹幕 30s（twitch 跳过列表类；虎牙另有专项 group） |
| `test/douyin_recommend_fanout_test.dart` | 20 | 离线 | 抖音推荐：首屏扇出并发性与上限、切片去重/失败隔离、分区轮转真分页、游标重置 |
| `test/douyin_category_paging_test.dart` | 11 | 离线 | 抖音分类：offset/count 推进、满页判据、异常响应降级、脏数据单条跳过、与推荐共用 offset 约定 |
| `test/douyin_linkmic_room_test.dart` | 6 | 离线 | 抖音连麦：reflow 优先、降级房间不抛空指针、双路失败抛 CoreError、画质回退 |
| `test/douyu_recommend_paging_test.dart` | 4 | 离线 | 斗鱼推荐：`pgcnt=0` 时非空页仍判「还有更多」、空页到底、广告位过滤、缺字段降级 |
| `test/douyu_play_url_renew_test.dart` | 2 | 离线 | 斗鱼续流契约（2026-10-16 新增）：每条 flv 线路都带 `LivePlayUrlRenewer`、调用它会重新请求取流接口且 `expire=0` 兜底与首取一致、非 flv 线路不给回调 |
| `test/bilibili_emoticon_test.dart` | 31 | 离线 | B 站表情：两种下发入口、占位符形态判据、去重、上限 8、https 归一、异常载荷返回 null |

> **Rust core 补充（2026-10-17）**：抖音会员/守护表情（`WebcastEmojiChatMessage`）与普通聊天的
> 214 项标准 `[码]`（`[微笑]`/`[呲牙]`/`[互粉]` 等）均已在 Rust core 解码：
> `danmaku/emoticon.rs` 3 条 lib 单测、`danmaku/decode.rs` 6 条 lib 单测、
> `tests/ac_douyin_danmaku.rs` 2 条集成用例；Dart core / console 尚未实现。
> 标准表情图片为签名 CDN 地址，有效期至 2036-10，过期后需重新抓表。
| `test/douyu_enc.json` / `douyu_sc.json` | — | 样本 | 斗鱼签名/SC 抓包样本；**当前无用例引用**，可作解码测试素材 |

> **2026-10-12 同步（`abca65f8`）后未新增任何测试文件**：账号体系下沉 core 只带来源码与模型（`account_info.dart` 等），core 侧未跑测试、App 侧仅做适配。账号接口用例全部为【待补】（见 §4.7）。
> **2026-10-14 同步（`5ae375f1`）同样没有 core 测试变动**：`git diff --stat 8fd14a9f..HEAD -- simple_live_core/test` 输出为空；`grep -rn "setSiteAttrs" simple_live_core/test` 无命中，因此本轮改的 B 站凭证 JSON 解析目前**零覆盖**。
> **2026-10-16 斗鱼续流新增 `douyu_play_url_renew_test.dart`（2 条离线用例）**：配套 App 侧 `stream_relay/` 的 15 条，并补上 §4.5 TC-I08。同机 core 全量实测 82 执行 / 79 通过 / 3 失败（3 条均为 `huya tests` 联网用例：房间未开播，与既有口径一致）。

## 3. 覆盖矩阵

| 能力 | bilibili | douyu | huya | douyin | twitch |
| --- | --- | --- | --- | --- | --- |
| 列表分页（离线回归） | 无 | ✅ | 无 | ✅✅ | 不支持 |
| 详情/清晰度/取流（离线） | 无 | 无 | 无 | ✅（连麦） | 无 |
| 弹幕解码（离线） | 无 | 无 | 无 | ✅（Rust core） | 无 |
| 表情包解析（离线） | ✅ | 不支持 | 无 | ✅（Rust core） | 不支持 |
| 账号接口（离线） | 无 | 无 | 无（桩） | 无 | 无（桩） |
| 凭证注入 `setSiteAttrs`（离线） | 无 | 无 | 无 | 无 | 无（桩） |
| 联网冒烟 | ✅ | ✅ | ✅ | ✅ | 部分 |

缺口集中在：**弹幕解码层**（四套协议全无离线用例，见 backlog P1-4）、**bilibili/douyu/huya 的取流链路**、**2026-10-12 新增的账号接口**（全平台离线用例为 0，见 §4.7），以及 **B 站凭证 JSON 解析**（`setSiteAttrs` 取 `{"cookie": ...}` 键 + `getAccountInfo` 回填 `userId`，`bilibili_site.dart:553-558`、`:613-635`）——现有测试里只有两个抖音用例把 `headers['cookie']` 当 fixture 直接赋值（`douyin_category_paging_test.dart:127`、`douyin_recommend_fanout_test.dart:188`），并未经过 `setSiteAttrs`，不构成覆盖。

## 4. 文字版测试案例库

约定：`[已有]` = 现有用例已覆盖（给出来源）；`[待补]` = 建议新增（给出实现要点）。用例描述已足够 AI 直接转写为 `test()`。

### 4.1 分页契约（跨平台，最高优先级）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-P01 | 斗鱼推荐第 1 页返回 40 条、`pgcnt=0` | `hasMore == true`（不能采信 pgcnt） | [已有] douyu_recommend_paging_test.dart |
| TC-P02 | 斗鱼推荐返回空 `rl` | `items` 空、`hasMore == false`、不抛异常 | [已有] 同上 |
| TC-P03 | 斗鱼推荐响应缺 `rl` 键 | 按空页处理，不抛异常 | [已有] 同上 |
| TC-P04 | 斗鱼推荐含 `type != 1` 的广告位 | 过滤广告后仍 `hasMore == true` | [已有] 同上 |
| TC-P05 | 抖音分类第 1/2 页 | 请求参数 `partition=101`、`partition_type=4`、`offset=0/15`、`count=15` | [已有] douyin_category_paging_test.dart |
| TC-P06 | 抖音分类返回 3 条（不满 15） | `hasMore == false`（判据是「满页」不是「非空」） | [已有] 同上 |
| TC-P07 | 抖音分类响应 `data: null` 或 `data: []` | 降级为空页，不抛 TypeError | [已有] 同上 |
| TC-P08 | 抖音分类含 null / 缺 `room` 的脏条目 | 只跳过脏条目（items 减 4），`hasMore` 看原始条数仍 true | [已有] 同上 |
| TC-P09 | 抖音推荐首屏 `pageSize=30` | 扇出 `kMinFeedFanout=4` 路、**并发**（maxInFlight==4）、声明 `hasMore=true`、不碰分区接口 | [已有] douyin_recommend_fanout_test.dart |
| TC-P10 | 抖音推荐首屏 `pageSize=500` | 扇出封顶 `kMaxFeedFanout=6` | [已有] 同上 |
| TC-P11 | 抖音推荐首屏切片参数 | 每路 count 互不相同（避免服务端返回同一批） | [已有] 同上 |
| TC-P12 | 抖音推荐首屏个别切片失败 | 其余切片正常返回、`hasMore` 仍 true | [已有] 同上 |
| TC-P13 | 抖音推荐首屏全部切片失败 | 抛 `CoreError`（不静默返回空） | [已有] 同上 |
| TC-P14 | 抖音推荐首屏全部为空 / 一路失败其余为空 | 空页处理（`hasMore=false`），不抛错 | [已有] 同上 |
| TC-P15 | 抖音推荐第 2/3 页 | 走 `partition/detail/room/v2`，slot0→slot1，`offset=0`、`count=20` | [已有] 同上 |
| TC-P16 | 抖音推荐第 `2+slots` 页 | 回到第 1 个分区、`offset=20`（页号→(分区,offset) 是纯函数） | [已有] 同上 |
| TC-P17 | 某分区翻空 | 顺延到下一分区而不是判到底 | [已有] 同上 |
| TC-P18 | 一圈分区全空 | `hasMore=false`，且恰好请求了 `kRecommendPartitions.length` 次 | [已有] 同上 |
| TC-P19 | 顺延后的下一页 | 不与上一页内容重复（同一 (分区,offset) 只消费一次） | [已有] 同上 |
| TC-P20 | 第 1 页刷新后 | 续接游标重置：第 2 页重新从第 1 个分区开始 | [已有] 同上 |
| TC-P21 | bilibili 推荐 `pageSize=60` | 请求里出现 `page_size=60`（唯一真正使用 pageSize 的平台） | [待补] |
| TC-P22 | 任何平台返回空列表 | `items` 空 + `hasMore=false`，且**不抛异常**（统一契约） | [待补] 各平台参数化 |

### 4.2 抖音详情与取流

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-D01 | 19 位 roomId | 只请求 `reflow/info`，**不再**走 `web/enter`；画质按档位从高到低 | [已有] douyin_linkmic_room_test.dart |
| TC-D02 | 降级房间（`status=4` 无 stream_url） | `status=false`、`data` 是 Map、画质为空列表、不抛 `NoSuchMethodError` | [已有] 同上 |
| TC-D03 | `web/enter` 与网页兜底都失败 | 抛 `CoreError`（不是空指针） | [已有] 同上 |
| TC-D04 | `web/enter` 报在播但缺 stream_url | 用返回的 roomId 补查 `reflow/info`，恢复真实状态与画质 | [已有] 同上 |
| TC-D05 | 只有 `flv_pull_url`/`hls_pull_url_map`（无 live_core_sdk_data） | 回退拼出 3 档画质 | [已有] 同上 |
| TC-D06 | `detail.data` 为 null / 空 Map / 非 Map | `getPlayQualities` 返回空列表，不抛异常 | [已有] 同上 |
| TC-D07 | 搜索被风控（响应空串/`blocked`） | 抛带中文提示的异常 | [已有，仅联网路径] 建议改离线 |
| TC-D08 | `searchAnchors` | 抛「暂不支持」异常（契约固定） | [待补] 离线断言异常类型与文案 |

### 4.3 弹幕解码（离线，缺口最大，建议优先补）

实现要点：用真实抓包样本构造输入字节流，直接调用各平台解码方法，断言产出的 `LiveMessage`。

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-M01 | bilibili 包头解析 | 16 字节头（包长/头长/协议版本/操作码）解析正确；op=3 产出 `online`（int32 人气） | [待补] |
| TC-M02 | bilibili 协议版本 | 0=JSON / 2=zlib / 3=brotli 三路解压后都能切分出多条 JSON；`allowMalformed` 不炸 | [待补] |
| TC-M03 | douyu STT 反序列化 | `type@=chatmsg/...@=/` 风格文本 → map；`fans!=1` 的弹幕被丢弃（记录为已知取舍） | [待补] |
| TC-M04 | douyu 帧重组 | 包长重复两次 + 类型 689 的帧头/尾正确切帧，粘包不丢消息 | [待补] |
| TC-M05 | huya tars 解码 | type=7（uri 1400→chat / 8006→online）与 type=22（vMsgItem 遍历） | [待补] |
| TC-M06 | huya SC 触发 | content 命中 `(来自.+?上头条)` → 调用 SC 拉取；uri 2001314 分支 | [待补] |
| TC-M07 | douyin protobuf | `PushFrame → gzip → Response` 两级解析；`needAck` 时回发 Ack；`WebcastChatMessage`（含标准 `[码]` 表情）/`WebcastRoomUserSeqMessage`/`WebcastEmojiChatMessage` 产出对应类型（表情走 `emoticons`） | [已有 Rust core] |
| TC-M08 | twitch IRC | `PING` 回 `PONG`；PRIVMSG+display-name+color 三正则齐备才产出 chat，颜色 hex 转换正确 | [待补] |
| TC-M09 | 任意平台解码异常 | 只记日志、不打断连接、不抛出到回调 | [待补] |

### 4.4 B 站表情包解析（已覆盖 31 条，摘要为契约）

| ID | 契约 | 状态 |
| --- | --- | --- |
| TC-E01 | `extra.emots`：只保留 message 中真正出现的占位符（面板几十个不下发） | [已有] |
| TC-E02 | 同一弹幕混排多个表情，顺序按 emots 下发顺序 | [已有] |
| TC-E03 | `info[0][13]` 单表情：message 是占位符→name 用它；是裸表情名（如「冲鸭」）→整串替换；夹带正文→name 为 null（渲染层追加） | [已有] |
| TC-E04 | 两个入口同图去重；同时存在时 `large` 判据必须一致（不能因 extra 先入队而画小） | [已有] |
| TC-E05 | 裸表情名长度上限 12 字、含空白/方括号的裸名一律丢弃（防子串替换吞正文） | [已有] |
| TC-E06 | 单条约 8 个上限在**入口**截断（不是解析后再丢） | [已有] |
| TC-E07 | 图片地址统一升 https；`//`、相对路径、`ftp://`、缺 url 全部丢弃 | [已有] |
| TC-E08 | 异常载荷（null/空数组/长度不足/非法 JSON）一律返回 null，不抛异常 | [已有] |
| TC-E09 | 大表情真实载荷（`info[0]` 只有 13/14 位、无 extra）能解析 | [已有] |
| TC-E10 | `LiveMessage.toString()` 里 emoticons 是对象数组（不是 JSON 字符串数组） | [已有] |

### 4.5 接口与基础设施契约

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-I01 | `LiveSite()` 基类默认行为 | 各方法返回空值/`false`/空 `LiveRoomDetail`，不抛异常 | [待补] |
| TC-I02 | 5 个平台 `setSiteAttrs(String)` 契约（v1.8.15 后） | 入参统一为 `String`，实现内一律 `jsonDecode` 后按键注入：bilibili 取 `cookie` 写入站点 `cookie` 字段（`bilibili_site.dart:553-558`，自 `5ae375f1` 起与其余平台一致）；douyu 取 `cookie`/`dy_did`/`LTP0`（`douyu_site.dart:344-356`）；huya 只取 `ua`（`huya_site.dart:559-564`）；douyin 取 `cookie`/`hlsFirst`（`douyin_site.dart:1233-1246`）；twitch 为 `UnimplementedError` 桩 | [待补] |
| TC-I03 | `HttpClient` 错误映射 | `badResponse` → `CoreError(statusCode)`；网络异常 → `CoreError("发送GET请求失败")`；`head` 特例不抛错 | [待补] |
| TC-I04 | `LiveRoomDetail.updateData/updateDanmakuData` | 返回新实例且只替换目标字段（`final` 语义） | [待补] |
| TC-I05 | `WebScoketUtils` 重连 | 断线 5s 重连、5 次后 `onClose`；收到消息后重连计数归零 | [待补]（需要 WS mock 或抽接口） |
| TC-I06 | 弹幕生命周期 | `onReady` → `onMessage`* → `onClose`；`stop()` 后回调置空、不再触发 | [待补] |
| TC-I07 | `LiveMessageColor.numberToColor` | 4/6/8 位 hex（含 0x？）转换正确；非 hex 回落白色 | [待补] |
| TC-I08 | `LivePlayUrl.renewers` 续流契约（2026-10-16） | douyu 为每条 flv 线路提供 `LivePlayUrlRenewer`，调用它=重新请求取流接口、`expire=0` 兜底与首取一致；非 flv 线路为 null；列表与 `urls` 等长（构造函数 assert） | [已有] douyu_play_url_renew_test.dart |

### 4.6 联网冒烟（夜间/发版前跑，勿进 PR 必跑集）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-N01 | 5 平台 `getRecommendRooms` | 非空、字段齐全（twitch 跳过） | [已有] simple_live_core_test.dart |
| TC-N02 | 5 平台 `getCategories` + 首个子类 `getCategoryRooms` | 非空、子类 id/parentId 齐全 | [已有] |
| TC-N03 | `searchRooms('LOL')` / `searchAnchors('联盟')` | 非空（抖音/虎牙/斗鱼/bilibili 各自动参） | [已有] |
| TC-N04 | 固定房间 `danking` 全链路 | 详情→清晰度→播放地址均非空 | [已有]（注意：依赖该主播在播） |
| TC-N05 | 弹幕 30s 窗口（虎牙房间 1995 专项） | `onReady` 触发、未关闭、至少 1 条消息 | [已有] |
| TC-N06 | 各平台「闭播房间」详情 | `status=false` 且不抛异常；弹幕参数有兜底 | [待补]（选固定闭播房间号） |

### 4.7 账号接口（v1.8.15 新增，全部【待补】）

实现要点：账号链路多为 IO，优先用 adapter 注入合成响应；重点守护「credential 形态 / QRStatus 映射 / 桩行为」，不做真号联网。链路见 workflow-diagram.md §8。

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-A01 | `LiveSite()` 基类账号默认行为 | `getQRCode` 返回空 `QRCode(key:'',url:'')`、`getQRPollResult` 返回 `QRStatus.failed`、`getAccountInfo` 返回空 `AccountInfo`；均不抛异常 | [待补] |
| TC-A02 | huya / twitch 账号接口（桩） | 三接口（twitch 另含 `setSiteAttrs`）抛 `UnimplementedError`（断言现状） | [待补] |
| TC-A03 | douyin 扫码两接口（桩） | `getQRCode`/`getQRPollResult` 抛 `UnimplementedError`；`getAccountInfo` 另测（见 TC-A08） | [待补] |
| TC-A04 | bilibili `getQRPollResult` 状态映射 | 服务端 code 86038→`expired`、86090→`scanned`、0→`scanned` 且从 `set-cookie` 汇总出 credential（JSON `{"cookie": ...}`） | [待补] |
| TC-A05 | douyu `getQRPollResult` 状态映射 | error -2→`unscanned`、1→`scanned`、-1→`expired`、0→`scanned` 且 credential 为 `{dy_did, LTP0, cookie}` JSON | [待补] |
| TC-A06 | `QRStatus` 流转与「未扫码→已扫→过期/失败」 | 轮询按状态枚举推进；`QRPollResult.fromJson` 遇未知 status 回落 `failed`（`account_qr_code.dart:36-45`） | [待补] |
| TC-A07 | `setSiteAttrs` credential 非 JSON / 空值容错 | 空串或非法 JSON 不应导致后续请求崩溃（当前 bilibili/douyu/huya/douyin 四个实现都直接 `jsonDecode`，非 JSON 入参应会抛 `FormatException`——先断言现状，再决定是否加护栏；缺 `cookie` 键时 bilibili/douyu/douyin 静默保留旧值） | [待补] `bilibili_site.dart:554`、`douyu_site.dart:345`、`huya_site.dart:560`、`douyin_site.dart:1234` |
| TC-A08 | douyin `getAccountInfo` cookie 为空 | 直接返回空 `AccountInfo`（`isValid=false`），不发请求（`douyin_site.dart:1253`） | [待补] |
| TC-A09 | `getAccountInfo` 校验成功/失败契约 | 成功→`isValid=true` 且回填 name/avatar/uid/credential；失败→`isValid=false` 不抛（bilibili/douyu/douyin 各一）。**bilibili 另需断言副作用**：站点字段 `userId` 被回填为 `info.mid`（`bilibili_site.dart:622`），随后 `getRoomDetail` 产出的 `danmakuData.uid` 取的就是它（`bilibili_site.dart:252`）；`mid` 为 null 时 `!` 抛错被同段 `catch`（`bilibili_site.dart:631-633`）吞掉，只留下 `isValid=false` 的空 `AccountInfo` | [待补] |

## 5. 写新测试的约定

1. **离线优先**：任何能靠合成响应覆盖的逻辑，不要写成联网用例；联网用例只用于「协议是否还活着」。
2. **adapter 注入模板**：替换 `HttpClient.instance.dio.httpClientAdapter` → 断言 → `tearDown` 还原（`restore = () {}` 初始化，避免 LateInitializationError 掩盖真实失败）。
3. **参数从 path 解析**：抖音分区接口经 `buildRequestUrl` 签名后参数在 URL path 里（`queryParameters` 为空），断言要读 `Uri.parse(options.path).queryParameters`。
4. **避免 flaky**：不要断言墙钟耗时/绝对并发时序；用「并发计数」（maxInFlight）代替；不要依赖固定网络数据。
5. **命名**：文件 `<平台>_<域>_test.dart`；用例名用中文描述行为 + 括号里给关键条件；`reason:` 写明「为什么这个断言值得守护」。
6. **契约变更时**：先改测试的期望值并在 PR 说明里引用本文件 ID（如「TC-P06 判据由非空改为满页」），让行为变更有据可查。

## 6. 与 backlog 的对应

- 本文件 §4.3 的 TC-M01~M09 对应 backlog **P1-4**（弹幕解码无离线回归）；
- §4.5 的 TC-I02/I03/I05 对应 **P2-2/P2-4**（`dynamic` 通道、重连策略）；
- §4.7 的 TC-A02/A03/A07 对应 **P2-11 / P2-13**（账号接口桩、抖音 cookie 方案分叉）；
- TC-P21/P22 对应 **P0-2**（wbi 缓存失效场景可先写「失败后重试」的离线用例再动手修）；
- `test/douyu_enc.json`、`douyu_sc.json` 样本可直接用于补 TC-M03/M04 的输入数据。