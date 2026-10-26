# 四平台测试与夹具基线（斗鱼 / 虎牙 / Twitch / 抖音）

> 作者：**QA（严过关）** ｜ 日期：2026-10-16 ｜ 工作目录：`C:/Users/admin/WorkBuddy/Worktrees/dart_simple_live/core-rust`
> 契约依据：`13-spec.md`（顶层契约 + §13 变更记录「启动其余平台迁移」）· `15-test-plan.md`（B站测试策略与反作弊门）· B站夹具范式 `crates/slive-core/tests/fixtures/bilibili/`
> 角色声明：夹具与用例由 QA **独立编写**，期望值从 **Dart core 解析代码**反推（`simple_live_core/lib/src/platforms/{douyu,huya,twitch,douyin}/`），**不参考任何 Rust 实现**（`test-discipline.md §4`「测试作者 ≠ 代码作者」）。

---

## 0. 一句话说明本目录解决什么问题

B站已有86 项离线测试 + 真实房间端到端验证。四路实现 agent（IP-3 斗鱼 / IP-4 虎牙 / IP-5 Twitch / IP-6 抖音）并行推进，**若不给可机械验证的输入，产出无法判定**。本文与配套夹具把「行为基准」从 Dart 源码固化成**可执行断言**：

- 字段名/ 结构：每份夹具的 `field_sources` 写明 **Dart 解析行号**，实现者照着对即可，不靠猜；
- 行为口径：既有 quirks（错位、回退、忽略分支）逐条钉死，**照搬而非"顺手修正"**；
- 反特判：脏帧、畸形条目、边界档位各自独立成例，专门击穿「对样本特判」的实现。

---

## 1. 产出清单

### 1.1 夹具（`crates/slive-core/tests/fixtures/<平台>/`）

| 层 | 斗鱼 | 虎牙 | Twitch | 抖音 | 合计 |
|----|------|------|--------|------|------|
| `http/http-samples.json` | 11 端点 / 30 变体 | 6 / 16 | 3 / 10 | 6 / 24 | **26 端点 / 80 变体** |
| `ws/*.bin` + `.expected.json` | 7 服务端 + 3 客户端 | 7 + 2 | 8 + 5 | 6 + 2 | **28 服务端 + 12 客户端** |
| `golden/*.json` | `golden-sign.json`（4 向量） | `golden-anticode.json`（3 向量） | `golden-quality-name.json`（11 档） | `golden-signature-params.json`、`golden-request-url.json` | **5 文件** |

> 全部标 `synthetic: true` + `needs_realtime_validation: true`（golden 除外：算法确定性，标 `false`）。
> 每份 `_meta` 必含：`synthetic` / `derivation` / `target_ac` / `target_rust_fn` / `needs_realtime_validation`。

### 1.2 测试（`crates/slive-core/tests/ac_<平台>_fixtures.rs`）

每平台 2 个文件（夹具契约 / golden+HTTP quirks），共用 `tests/fxcommon/mod.rs`：

| 文件 | 行数 | 可立即运行 | `#[ignore]` 待接入 | 依赖平台 API？ |
|------|------|-----------|------------------|--------------|
| `tests/fxcommon/mod.rs` | 227 | —（共享辅助：夹具 IO / 元数据校验 / 独立 MD5） | — | 否 |
| `tests/fxcommon/tars.rs` | 123 | —（虎牙 TARS 跳值，独立成文件以守门禁） | — | 否 |
| `tests/ac_douyu_fixtures.rs` | 243 | 13 | 4 | **否** |
| `tests/ac_douyu_golden.rs` | 300 | 14 | 0 | **否** |
| `tests/ac_huya_fixtures.rs` | 290 | 9 | 4 | **否** |
| `tests/ac_huya_golden.rs` | 241 | 12 | 0 | **否** |
| `tests/ac_twitch_fixtures.rs` | 299 | 14 | 4 | **否** |
| `tests/ac_twitch_golden.rs` | 229 | 12 | 0 | **否** |
| `tests/ac_douyin_fixtures.rs` | 298 | 12 | 4 | **否** |
| `tests/ac_douyin_golden.rs` | 298 | 14 | 0 | **否** |
| **合计** | — | **101 通过** | **16** | — |

> 全部文件 ≤ 300 行（`13-spec.md §9` 门禁）。实测 `cargo test`：**101 passed / 0 failed / 16~29 ignored，rc=0**
> （ignored 数随各 agent 接入进度变化；heldout 机制已启用，见 §6.4）。

**关键设计**：可运行的用例**只依赖夹具 + 字节布局 + `MockTransport`**，**不 import任何平台函数**。这样 IP-x agent 正在改`site.rs` / `danmaku` 的内部签名时，本文件不会连带编译失败——避免了「测试与实现同时改、互相阻塞」。

---

## 2. 夹具正确性：QA 已做的独立回验

> 依据 `verifier-critic-pattern.md`：期望值不能由被测代码自证。以下回验全部用**独立复刻的 Dart 算法**在 Python 侧重算，不借用 Rust 实现。

| 平台 | 回验内容 | 方法 | 结果 |
|------|---------|------|------|
| 斗鱼 | 10 个 WS 帧的 12 字节小端包头 | 复刻 `deserializeDouyu`（`douyu_danmaku.dart:175-193`）逐帧解码 | ✅ `fullMsgLength == fullMsgLength2`、包头689、`bodyLength` 自洽、帧尾 0 |
| 虎牙 | 9 个 TARS 帧全字段 |复刻 `TarsInputStream` **含 `skipToTag` 语义**（`tars_input_stream.dart:139-160`） | ✅ cmdType/uri/nickName/content/fontColor/在线人数全部解出且与 `expected` 一致 |
| 虎牙 | 5 份房间页 HTML（含 4 变体） | 跑 Dart 的 `ROOM_DATA_REGEX` + `STREAM_REGEX` 再 `json.loads` | ✅ status/线路数/清晰度列表全部命中；缺 `TT_ROOM_DATA` 变体如期不中 |
| Twitch | 8 个 IRC 帧 | 跑 Dart 的三条正则 + `numberToColor` | ✅ 含「缺 color/缺 display-name 必须无产出」 |
| Twitch | 5 份 m3u8（含 4 变体） | 跑 Dart 的 `BANDWIDTH` 下标配对 + 阈值表 | ✅ 含「BANDWIDTH 少于 URL数」的错位边界 |
| 抖音 | 8 个 protobuf 帧 | 独立 protobuf 解码器 + gzip 解压 | ✅ PushFrame 字段、`needAck`、消息条数与顺序全部一致；两条脏帧分别在 gzip 层 / protobuf 层失败 |
| 抖音 | 5 份清晰度样本 | 复刻 `getPlayQualities` 的两条解析分支（`douyin_site.dart:949-1080`） | ✅ 含分支② 的错位行为（见 §4.2） |
| 斗鱼 | 4 个签名向量 | 用例内**独立 MD5**（RFC 1321）重算 `secret`/`auth` | ✅ 与golden 一致（防「跑实现写回期望」） |
| 虎牙 | 3 个 anticode 向量 | 复刻 `buildAntiCode`（含 `rotl64`、base64(fm) 前缀） | ✅ wap / pc / 无-fm 三分支 |

**回验中发现并修正的问题**（记录在此供追溯）：

1. 虎牙 `WSMsgItem` 作为 LIST 元素时**必须**有 `STRUCT_BEGIN/END` 包裹（Dart `writeList` → `writeTarsStruct`），初版漏了 → 已修正；
2. 虎牙房间页 HTML 初版用了 `window.stream = {...}`，**不匹配** Dart 的 `stream:` 正则且 JSON 跨行 → 已改为单行 + `换行 + }` 收尾；
3. 抖音清晰度分支② 的期望值初版凭直觉写，实测算法后发现**真实行为是「原画被丢弃、标清拿到原画地址」** → 已按实测改正并标注为「既有错位行为，不得顺手修正」。

---

## 3. 每平台的字段速查（给四路实现 agent）

### 3.1 斗鱼（IP-3）

**HTTP 端点 → Dart 解析行号**

| 能力 | 端点 | Dart | 关键字段 |
|------|------|------|---------|
| 分类 | `m.douyu.com/api/cate/list` | `douyu_site.dart:28-56` | `data.cate1Info[].cate1Id/cate1Name`、`data.cate2Info[].{cate1Id,cate2Id,cate2Name,icon}`；**按 cate1Id 数值升序排序**（:53） |
| 分类下房间 | `www.douyu.com/gapi/rkc/directory/mixList/2_{cateId}/{page}` | `:59-84` | `data.rl[].{type,rid,rn,nn,rs16,ol}`；`type != 1` 跳过；`hasMore = page < data.pgcnt`（**pgcnt 有效**） |
| 推荐 | `www.douyu.com/japi/weblist/apinc/allpage/6/{page}` | `:177-216` | 同上字段；**`hasMore = items.isNotEmpty`**（**pgcnt 恒 0，不可用**） |
| 详情/状态 | `www.douyu.com/betard/{roomId}` | `:219-237`、`:337-340` | `room.{room_id,room_name,room_pic,owner_name,owner_avatar,show_details,show_status,videoLoop,room_biz_all.hot}`；`status = show_status==1 && videoLoop!=1 && !room_name.startsWith("【回放】")`；`danmakuData = room_id` |
| 清晰度/取流 | `www.douyu.com/lapi/live/getH5PlayV1/{roomId}` (POST) | `:87-119`、`:164-174` | `data.cdnsWithName[].cdn`（**scdn\* 排最后**）、`data.multirates[].{name,rate}`、`data.{rtmp_url,rtmp_live}` |
| 搜索房间 | `www.douyu.com/japi/search/api/searchShow` | `:240-272` | `error != 0` 抛错；`data.relateShow[].{rid,roomName,roomSrc,nickName,hot}`；hot `12.3万` → ×10000，解析失败 → **-999** |
| 搜索主播 | `www.douyu.com/japi/search/api/searchUser` | `:302-334` | `data.relateUser[].anchorInfo.{rid,avatar,nickName,isLive,roomType}`；**`liveStatus = isLive==1 && roomType==0`** |
| 签名材料 | `www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption` | `douyu_utils.dart:109-126` | `data.{rand_str,enc_time,is_special,key,enc_data}` |
| 二维码 | `passport.douyu.com/scan/generateCode` | `:413-428` | `error != 0` 抛 `data`；`data.{code,url}`；`expireAt = now+300` |
| 扫码轮询 | `passport.douyu.com/japi/scan/auth` | `:431-473` | `error`: `-2`unscanned / `1` scanned / `-1` expired / `0` 已确认；`0` 时需 `set-cookie` 的 `LTP0` |

**弹幕（STT 文本协议）**

- 包头 12 字节小端：`fullMsgLength(i32)` / `fullMsgLength2(i32)` / `packType(i16)=689` / `encrypted(u8)=0` / `reserved(u8)=0`，body 后跟 1 字节 `0`；**总长 = 12 + n + 1**（`douyu_danmaku.dart:152-193`）。
- STT 语法：`//` → 数组；`k@=v` 以 `/` 分隔 → 对象；`@S` → `/`、`@A` → `@`（`:196-228`）。
- 消息类型：`chatmsg`（**仅 `if=='1'` 才产出**）、`comm_chatmsg`（SC，`cprice/100`）、`voice_trlt`（高能弹幕2，**秒×1000**）、`uenter`（**忽略**）。
- 客户端帧：`loginreq` / `joingroup` / `mrkl`（心跳，45s）。

**Rust 侧落点**：`platforms::douyu::sign::build_sign`、`platforms::douyu::danmaku::{decode,stt,parse}`；POST 走该模块自建的 `DouyuPost` seam（不改造共享 `HttpTransport`）。

### 3.2 虎牙（IP-4）

| 能力 | 端点 | Dart | 关键字段 |
|------|------|------|---------|
| 子分类 | `live.cdn.huya.com/liveconfig/game/bussLive?bussType=` | `huya_site.dart:64-96` | `data[].gid` **四种类型**（`{value:"a,b"}` / double / int / 其他）+ `gameFullName`；`pic` = `https://huyaimg.msstatic.com/cdnimage/game/{gid}-MS.jpg`（**由 gid 拼接**） |
| 分类下房间 / 推荐 | `www.huya.com/cache.php?m=LiveList` | `:103-130`、`:196-223` | **响应是 JSON 字符串**（被 `json.decode` 两次）；`data.datas[].{profileRoom,roomName,introduction,screenshot,nick,totalCount}`；封面不含 `?` 时追加 `?x-oss-process=style/w338_h190&`；`hasMore = page < totalPage` |
| 搜索房间 | `search.cdn.huya.com/?m=Search&do=getSearchContent&v=4` | `:412-451` | **`response["3"].docs[]`**；`roomId = "yy/{yyid}"`（**带前缀**） |
| 搜索主播 |同上 `v=1` | `:454-482` | **`response["1"].docs[]`**；`docs[].gameLiveOn` → `liveStatus` |
| 详情/状态 | `www.huya.com/{roomId}`（**HTML**） | `:226-342`、`:485-505` | 正则 `var TT_ROOM_DATA = {...};` 取 `state`/`isReplay`；正则 `stream: {...}` 取 `gameLiveInfo` / `gameStreamInfoList` / `vMultiStreamInfo` |
| 匿名 uid | `udblgn.huya.com/web/anonymousLogin` | `:508-517` | `data.uid` |

**⚠️ 详情链路的三个易错点**

1. `STREAM_REGEX` 要求 JSON **单行**（`huya_site.dart:241` 取`.split('\n')[0]`），跨行会导致只解出半截 JSON；
2. `HDR` 清晰度被跳过（`:308`）、`4K` 被跳过（`:149`）；
3. **未开播时 `danmakuData` 必须是 `{ayyuid:0, topSid:0, subSid:0}` 而不是 null**（`:325-333`注释：App 的 live-controller 无条件用它启动弹幕）。

**弹幕（TARS）**

- 外层 `WebSocketCommand`（tag：cmdType 0 / data 1 / requestId 2 / traceId 3 / encryptType 4 / time 5 / md5 6）。
- `cmdType`（`huya/model/huya_damaku_model.dart` 的 `EWebSocketCommandType`）：`7`=MsgPushReq、`16`=RegisterGroupReq、`20`=HeartBeatReq、`22`=MsgPushReq_V2。
- `cmdType=7` → `HYPushMessage{pushType 0, uri 1, msg 2, protocolType 3}`：`uri==1400` → `HYMessage`（聊天）；`uri==8006` → 裸 int（在线人数）。
- `cmdType=22` → `WSPushMessageV2{sGroupId 0, vMsgItem 1}`：**只匹配 `iUri==2001314` 触发 SC 拉取，本帧不产出消息**。
- 颜色：`bulletFormat.fontColor <= 0` → 回退白色（`:234`）。
- joinRoom **只发 join group**（`liveInfo`/`doLaunch`/`enterChannel` 已被注释，`:185-187`）；心跳 60s。

**Rust 侧落点**：`platforms::huya::danmaku::*`，TARS 复用 `slive_core::tars`（共享基础层，`platforms/* -> crate::tars -> crate::error`）。

### 3.3 Twitch（IP-5）

| 能力 | 端点 | Dart | 关键字段 |
|------|------|------|---------|
| 详情/状态 | `gql.twitch.tv/gql`（**POST 数组**） | `twitch_site.dart:207-279` + `twitch_models.dart` | 一次请求两个 persisted query：`[0]=ChannelShell`（`userOrError`）、`[1]=StreamMetadata`（`user`）；**按下标取，顺序不能错** |
| 清晰度 | `usher.ttvnw.net/api/channel/hls/{roomId}.m3u8` | `:135-176` | `BANDWIDTH=(\d+)` **按出现顺序**与 URL 行**按下标配对**；降序排序；`_getQualityName`阈值表 |
| 取流 | — | `:191-199` | 直接用清晰度的 `data`（就是 URL 本身） |

**字段名坑**：profileImage 的字段是 **`profileImageURL`**（大写 URL），不是 `profileImageUrl`。

**弹幕（IRC over WebSocket）**

- 三正则必须**同时**命中才产出（`:86-90`）：`PRIVMSG [^:]+:(.+)` / `display-name=([^;]+);` / `color=#([a-zA-Z0-9]{6});`。
- 帧内 `\n` 分隔，**逐行**处理、顺序产出。
- `PING` → 回 `PONG`（`:78-80`，注意是对**整帧** `replaceFirst`）。
- 心跳 40s（`PONG :tmi.twitch.tv`）；进房 `CAP REQ` / `PASS SCHMOOPIIE` / `NICK justinfanXXXX`（随机，不入golden）/ `USER` / `JOIN #room`。

**🔴 「不支持」清单（迁移必须保持不支持）**：`get_categories`/`get_category_rooms` 返回空；`get_recommend_rooms`/`search_rooms`/`search_anchors`/`get_account_info`/`get_qr_*`/`set_site_attrs` **抛错**。顺手实现会改变 App 行为、破坏 AC-30。

### 3.4 抖音（IP-6）

| 能力 | 端点 | Dart | 关键字段 |
|------|------|------|---------|
| 分类 | `live.douyin.com/`（HTML 正则） | `douyin_site.dart:60-107` | 正则 `categoryData...],`，解码 `renderDataJson["categoryData"]`；`id = "{partition.id_str},{partition.type}"` |
| 分类下房间 | `live.douyin.com/webcast/web/partition/detail/room/v2/` | `:110-234` | **双重嵌套** `data.data[]`；`[].room.{title,cover.url_list[0],owner.nickname,room_view_stats.display_value}`；`[].web_rid` 缺则**整条跳过**；`hasMore = rawCount >= count`（count 固定 15） |
| 推荐 | `live.douyin.com/webcast/feed/` | `:293-494` | **room 挂在 `item.data`**（分区接口挂 `item.room`）；固定 20 条/请求；首屏并发 fanout 4~6 路；按 roomId 去重 |
| 详情 | `live.douyin.com/webcast/room/web/enter/` | `:646-724` | `data[0].{id_str,status,title,cover,owner,room_view_stats,stream_url}` + 顶层 `user`；`status==2` 才在播；`stream_url` 为空 → **改查 reflow/info**（连麦房间） |
| 清晰度 | （`stream_url` 子结构） | `:949-1080` | 两条分支：`stream_data` 以 `{` 开头 → 按 `sdk_key` 取 `main.flv/main.hls`；否则按 `flvList[len-level]` 倒序索引 |
| 搜索 | `www.douyin.com/aweme/v1/web/live/search/` | `:1090-1170` | **`data[].lives.rawdata` 是字符串化的 JSON**（需二次 parse）；风控时响应是**纯文本 `blocked`** |
| 账号 | `live.douyin.com/webcast/user/me/` | `:1249-1284` | `data.{id_str,nickname,short_id,sign,birthday,gender,avatar_thumb.url_list[0]}` |
| 弹幕签名 | — | `douyin_danmaku.dart:210-238` | `sigParam` = 13 个参数**逗号连接**（键序见 golden）→ `md5` → `generateXBogus(md5, 1)` |

**两种 room_id**：`webRid`（11-12 位，固定，进房参数）vs `roomId`（19 位，每次开播变）。**`LiveRoomDetail.roomId` 存 webRid**；`getRoomDetail` 按 `length <= 16` 分流（`:502`）。

**弹幕（protobuf + gzip）**：`PushFrame{seqId 1, logId 2, payloadEncoding 6, payloadType 7, payload 8}` → `gzip` → `Response{messagesList 1, internalExt 5, needAck 9}` → `Message{method 1, payload 2}` → `WebcastChatMessage`（`user.nickName` + `content`，**颜色恒为白色**）/ `WebcastRoomUserSeqMessage`（`totalUser` 字段 7）。心跳与进房都是 `payloadType='hb'` 的空帧，10s。

---

## 4. 已钉死的「既有 quirks」（**照搬，不要顺手修**）

> 每条都对应 Dart 现状。迁移时"修正"它们会让 Rust 行为与 Dart 不一致 → 直接违反 AC-30「回归为零」。

### 4.1 清单

| # | 平台 | quirk | Dart 依据 | 夹具 |
|---|------|-------|----------|------|
| Q1 | 斗鱼 | 推荐流 `pgcnt` 恒 0，必须用「非空即有更多」；**类目流的 pgcnt 反而有效** | `douyu_site.dart:199-215` / `:82` | `japi_weblist_apinc_allpage` + `gapi_rkc_directory_mixList` |
| Q2 | 斗鱼 | `room_biz_all.hot` 是 `12.3万` → `int.tryParse` 失败 → **online=0** | `:224` | `betard` variants |
| Q3 | 斗鱼 | `parseHotNum` 解析失败返回 **-999**（不是 0） | `:342-352` | `searchShow` variants |
| Q4 | 斗鱼 | `chatmsg` 仅 `if=='1'` 才产出（阴间弹幕过滤） | `:81` | `frame-chatmsg-fans0.bin` |
| Q5 | 虎牙 | `gid` 为 null 时 pic 拼成 `.../null-MS.jpg` | `huya_site.dart:83,90` | `bussLive` variants |
| Q6 | 虎牙 | `search_rooms` 的 `roomId` 带 `yy/` 前缀 | `:441` | `search_cdn_huya_com_rooms` |
| Q7 | Twitch | `title` 缺失时回落成**字符串 `"null"`**（不是空串） | `twitch_site.dart:229` | `gql_twitch_tv_room_shell` variants |
| Q8 | Twitch | `PING` 用**整帧** `replaceFirst`，混帧回包会带上后续 PRIVMSG 行 | `:79` | `irc-ping-privmsg-mixed.bin`（标 `pinned_dart_behavior`） |
| Q9 | 抖音 | 弹幕颜色**恒为白色**（注释「暂不知道怎么转换颜色」） | `douyin_danmaku.dart:158-162` | `frame-push-chat.bin` |
| Q10 | 抖音 | `display_value` 是 `1.2万` → `tryParse` 失败 → online=0 | `:232`、`:611`、`:707` | `partition` variants |
| Q11 | 抖音 | `sendAck` 里 `payloadType` 被连写两次，第二次（`internalExt`）覆盖第一次 | `:184-190` | `frame-push-multi-need-ack.bin` |
| Q12 | 抖音 | 清晰度分支② 存在**错位**：level=0 越界被丢弃、标清拿到原画地址 | `:1015-1021` | `stream_url_quality` variants（标 `dropped`） |

### 4.2 特别提示 Q12（最容易被"好心修坏"的一条）

`getPlayQualities` 在 `stream_data` 不是 JSON 串时走地址表分支，按 `flvList[flvList.length - level]` 取值。当地址表条数少于档位数（夹具中 2 条 vs 3 档）：

- `level=0` → 下标 2 越界 → urls 空 → **原画档被丢弃**（`:1028` 的 `if (urls.isNotEmpty)`）；
- `level=2`（标清）→ 下标 0 → **拿到原画的地址**。

这是 Dart 的既有行为。**线上是否真的会走到该分支取决于 `stream_data` 的真实形态（待抓包）**；若恒为 JSON 串则本分支属防御性覆盖。夹具已如实记录并标注。

---

## 5. 待抓包清单（真实录制指引）

> 纪律：`synthetic: true` 的夹具**不得**当真实抓包使用（`15-test-plan.md §6G-1`）。下表是解除标记的充要条件。

### 5.1 录制方法（按平台）

| 平台 | 工具 | 前置 |
|------|------|------|
| 斗鱼 | `mitmproxy` / Charles；或 Dart 侧注入 `HttpClientAdapter`（照 `douyu_play_url_renew_test.dart` 的 `_RoutingAdapter`） | 需 cookie（游客也可） |
| 虎牙 | `mitmproxy`；详情页直接 `curl` 存 HTML | 需 `HYSDK` UA 头 |
| Twitch | `mitmproxy`；persisted query 需真实 `client-id`（Dart 硬编码 `kimne78kx3ncx6brgo4mv6wki5h1ko`） | 无需 token |
| 抖音 | `mitmproxy` + 完整浏览器头 + `ttwid`（HEAD 请求换）+ A-Bogus / X-Bogus 签名 | 最难，见下|

### 5.2 待抓包项（按优先级）

| ID | 平台 | 抓什么 | 解除哪个标记 | 优先级 |
|----|------|--------|------------|--------|
| P-1 | 虎牙 | `www.huya.com/{roomId}` **真实 HTML** —— 重点核对 `var TT_ROOM_DATA =` 与 `stream:` **是否仍存在**、JSON 是否单行 | `www_huya_com_room_html` | **P0**（页面改版则整条链路失效） |
| P-2 | 抖音 | `stream_data` 真实形态（是否恒为 JSON 串） | `stream_url_quality` 分支② | **P0**（决定线上走哪条解析分支） |
| P-3 | 抖音 | `feed` 的 query 参数是否真的全部被忽略（count/offset/cursor） | `webcast_feed` | P0 |
| P-4 | Twitch | 两个 persisted query 的 `sha256Hash` 是否仍有效 | `gql_twitch_tv_room_shell` | P0（失效则整个详情链路挂） |
| P-5 | 虎牙 | `gameLiveOn` 的真实类型（bool vs 0/1） | `search_cdn_huya_com_anchors` | P1（Dart 直接赋 bool，类型错会抛） |
| P-6 | 虎牙 | `gid` 的真实形态（是否总是 `{value:"a,b,c"}`） | `bussLive` | P1 |
| P-7 | 斗鱼 | `betard` 房间不存在时的响应形态 | `betard` 错误流 | P1 |
| P-8 | 斗鱼 | `getEncryption` 的风控错误码集合 | `getEncryption` 错误流 | P1 |
| P-9 | 斗鱼 | `searchUser` 的 `isLive`/`roomType` 真实类型 | `searchUser` | P2 |
| P-10 | 抖音 | 风控响应形态（是否纯文本 `blocked`） | `aweme_v1_web_live_search` 错误流 | P1 |
| P-11 | Twitch | IRC帧的实际形态：tags 是否总带 `color`、是否多行/CRLF | 全部 `ws/*.bin` | P1 |
| P-12 | Twitch | m3u8 里 `BANDWIDTH` 与 URL 行的**相对顺序**是否稳定 | `usher_ttvnw_net_master_m3u8` | P1（顺序变了会整体错位） |
| P-13 | 抖音 | 连麦房间的降级骨架形态 | `web_enter` 降级变体 | P2 |
| P-14 | 四平台 | 各WS 帧的**真实**服务端字节（替换合成帧） | 全部 `ws/*.bin` | P2 |

### 5.3 命名与落地规则

```text
# 录制产物落盘
crates/slive-core/tests/fixtures/<平台>/http/<真实名>.json      # 或并入 http-samples.json 的 samples
crates/slive-core/tests/fixtures/<平台>/ws/<真实名>.bin
crates/slive-core/tests/fixtures/<平台>/ws/<真实名>.expected.json

# 每份必须做的事：
#   1. _meta.synthetic: true  →  false
#   2. _meta.derivation: "真实抓包：<日期> <房间号> <工具>"
#   3. _meta.needs_realtime_validation: true  →  false
#   4. 保留原有合成样本（改名为 *.synthetic.json），别覆盖 —— 它们是「边界用例」的载体
```

---

## 6. held-out 留出集纪律（ADR-011，四平台沿用）

> ⚠️ **一处需要纠正的前提**：`15-test-plan.md §3` 与 `10-architecture.md §8.4` 都写了
> 「B站 heldout 已就位」，但 2026-10-16 实测：**`tests/fixtures/bilibili/` 下没有 `heldout/` 目录**
> （只有 http/ws/golden/emoticon 四个），且**全仓没有任何 `#[cfg(feature = "heldout")]` 门选用例**。
> 也就是说 **AC-36 的 held-out 机制此前从未真正运行过**，四平台是首个实际启用方。
> 本文§6.4 记录了机制的双向验证结论（用一个临时探针做的，验完已删）。

### 6.1 目录与开关

- 留出集数据：`crates/slive-core/tests/fixtures/<平台>/heldout/`（**当前为空**，仅有本节策略）；
- 开关：`crates/slive-core/Cargo.toml` 的 `[features] heldout = []`（**已由总监 2026-10-16 添加**），
  用例用 `#[cfg(feature = "heldout")]` 门选；
- 判定命令：`cargo test -p slive-core --features heldout`。

> 机制已双向验证（见 §6.4）。缺口 G-M3「feature 未声明」**已关闭**。

### 6.2 内容要求（反特判）

留出集必须满足「**结构不同于可见集**」，否则失去反特判效力：

| 平台 | 留出集应换成 |
|------|-------------|
| 斗鱼 | 另一个房间的 betard/列表；**不同的 enc_data/key**（区分硬编码 auth）；STT 字段顺序变体 |
| 虎牙 | 另一个房间页 HTML；**不同 fontColor 分布**；含 V2 帧的 `iUri` 全谱 |
| Twitch | 另一个频道的 GQL 响应；**不同 displayName/颜色**；无 `color` 标签的真实用户 |
| 抖音 | 另一个房间的 enter/feed；**不同 sdk_key 与 level 组合**；风控真实响应 |

### 6.3 纪律

1. **实现者不可见**：留出集由 QA 提交并在实现阶段不进入其开发视图；
2. **默认不编译**：`cargo test` / `cargo build` 不含 heldout；
3. **QA 独立运行**：`--features heldout` 由 QA 在 Phase 4 跑，结果单独留证；
4. **不得用合成数据冒充留出集** —— 必须真实抓包，否则特判式实现照样能过。

### 6.4 门选机制实测结论（已双向验证）

`[features] heldout = []` 已由总监添加进 `crates/slive-core/Cargo.toml`。QA 用一个**临时探针**
（两个互斥 `#[cfg]` 测试，验完即删、未入库）双向验证了机制确已生效：

| 命令 | 实际运行 |
|------|---------|
| `cargo test -p slive-core`（默认） | `probe_default_gate_should_run_without_feature ... ok`（1 passed）|
| `cargo test -p slive-core --features heldout` | `probe_heldout_gate_should_only_run_with_feature ... ok`（1 passed）|

结论：`#[cfg(feature = "heldout")]` 门选**按预期工作** —— 默认不编译、加 feature 才编译。
开启 feature 对既有夹具用例**无副作用**（8 个夹具文件仍 101 passed / 0 failed / rc=0）。

**留出集启用时的写法**（四平台照此）：

```rust
// tests/ac_<platform>_heldout.rs
#![cfg(feature = "heldout")]   // 或逐条 #[cfg(feature = "heldout")]

#[test]
fn ac<X>_heldout_<case>() { /* 只读 fixtures/<平台>/heldout/ 下的真实抓包 */ }
```

**当前状态**：四个 `fixtures/*/heldout/` 目录已建好但**为空**，`--features heldout` 编译通过、
无额外用例（符合预期）。待 §5.2 抓包回填后启用。

---

## 6A. 夹具修改纪律：只能改生成器，禁止手工编辑产物

> 本节由一次「实现路改了夹具、随后被生成器覆盖」的事件引出。

**规则**：`tests/fixtures/<平台>/**` 的 `.bin` / `.expected.json` / `golden/*.json` 全部由**生成器**产出，
**不允许手工编辑产物文件**。

| 角色 | 允许做的事 |
|------|-----------|
| QA（夹具 owner） | 改生成器 → 重新生成 → 提交产物 |
| 实现 agent（IP-3~6） | **只读**夹具；发现夹具有问题时**向 QA 提单**，不得自行改 |

**为什么**：产物里有多个互相引用的字段（`irc_text` / `bytes_hex` / `.bin` / `bytes_len` /
`expected.replies` 等），其中若干是**由 `.bin` 派生**的（见各帧的 `replies_derivation` /
`assert_hex_matches_bin`）。手工改一处会让其他字段失同步，而下次重新生成又会把手工修改覆盖掉
—— 造成「改了但没生效」的无效工，也让人误以为夹具有缺陷。

**发现夹具可疑时怎么提**：给出「文件名 + 你实际读到的内容 + 你认为应有的内容」，
QA 会用生成器复核。若确实是生成器缺陷，QA 修生成器并重新生成（而不是补丁产物）。

---

## 7. 解除 `#[ignore]` 的操作说明（给四路实现 agent）

各平台 `#[ignore]` 用例的断言写在**夹具 `.expected.json` / `http-samples.json` 里**，解除步骤：

1. 在你的 `ac_<平台>_*.rs` 里写实现断言，读取方式：
   ```rust
   let doc: serde_json::Value = serde_json::from_str(
       &std::fs::read_to_string(format!("{}/ws/frame-xxx.expected.json", fixtures_dir()))?
   )?;
   let expected = &doc["expected"];
   ```
2. 用 `MockTransport` / `MockDouyuPost` / `ScriptedFrameSource` 注入夹具；
3. 调用平台函数，产出与 `expected` 逐字段比对；
4. 确认通过后，**删除** `ac_<平台>_fixtures.rs` 里对应的 `#[ignore]` 用例（那只是骨架占位，真实断言由你的文件承载），或改为 `#[cfg(feature = "heldout")]`。

> ⚠️ **不要修改夹具来让实现通过**（`test-integrity-anti-gaming.md`）。若确信夹具与 Dart 行为不符，先提 QA 复核。

---

## 7A. 自检真实结论（不采信"应该能过"）

> 证据：`evidence-fixtures-test.log`、`evidence-fixtures-clippy.log`

| 命令 | 结果 |
|------|------|
| `cargo test -p slive-core --test ac_douyu_fixtures --test ac_douyu_golden --test ac_huya_fixtures --test ac_huya_golden --test ac_twitch_fixtures --test ac_twitch_golden --test ac_douyin_fixtures --test ac_douyin_golden` | **rc=0**；**101 passed / 0 failed / 16 ignored**（8 个文件全部 `ok`） |
| `cargo clippy -p slive-core --tests` | 我方9 个文件（`tests/fxcommon/**` + `tests/ac_{douyu,huya,twitch,douyin}_{fixtures,golden}.rs`）**零告警**；日志中的 22 条全部落在各 agent 的 `src/platforms/**`（`douyin/signature/*`、`huya/danmaku/*`、`huya/detail.rs` 等） |
| 单文件 ≤ 300 行 | ✅ 我方 10 个文件全部合规（最大 300 行） |
| 新增依赖 | ✅ 零新增（`Cargo.toml` 未改；MD5 在测试侧自实现） |
| 团队级 P0（emoji / 紫粉渐变 / 占位文案） | ✅ 无产出前端代码；测试注释与文档中无 emoji 图标、无占位 |

**全量 `cargo test -p slive-core` 当前无法作为我方结论**：其余测试目标（`ac_douyu_account.rs`、`ac_twitch_danmaku.rs`、`ac_huya_*`、`ac_douyin_detail_play.rs`）与 `slive-core` lib 的 `#[cfg(test)]` 单测正被 IP-3~IP-6 **并行改动**，处于中间态（报`cannot find 'twitch' in 'platforms'`、`cannot find module 'tables'` 等）。这是并行开发的预期状态，**非我方引入**；待各 agent 收尾后由 QA 重跑全量并按 §9G-M5 重新判定。

---

## 8. 回归护栏（对 App 侧基线的影响）

| 结论 | 说明 |
|------|------|
| **不影响 App 回归基线** | 本次改动**只新增** `crates/slive-core/tests/` 与 `docs/rust-core/` 下的文件；未触碰 `simple_live_app/`、`simple_live_core/lib/`、任何 `src/platforms/**` 实现文件 |
| App 侧基线仍为564/549/15 | 见 `16-app-regression-baseline.md`；本任务不产生新的 Dart 侧测试 |
| Core 侧 Dart 测试不变 | `simple_live_core/test/` 零改动 |
| 运行口径 | Rust 测试与 Dart 测试相互独立：`cargo test -p slive-core` 不涉及 Flutter；`flutter test` 需按`13-spec.md §9` 做代理隔离 |
| Flutter 侧新增断言 | 无。本任务纯夹具/测试/文档，**无UI 改动**（AC-32 不受影响） |

已按团队级 P0 规则自检：**无 emoji 图标**、**无紫粉渐变**、**无空洞占位文案**（本任务不产出前端代码，仍按 `15-test-plan.md §5.1 V10` 在 Phase 4 统一扫描）。

---

## 8A. 待裁决登记表（QA 裁决结果与待产品/总监拍板项）

> 本章登记夹具中「不能凭断言写死」的口径。纪律：**未裁决项不得伪装成已断言**；
> 已裁决项在夹具里写 `ruling`，在下面登记结论与理由。

### 8A.1 QA 已裁决

| ID | 议题 | 裁决 | 理由 |
|----|------|------|------|
| **Q-C** | Twitch 帧尾 `\r` 是否 trim 后进 message | **照搬 Dart，不 trim** | AC-30「行为零变化」是硬约束。`\r` 是否进入 message 属**行为差异**而非实现细节；迁移窗口内任何「顺手 trim」都让 Rust 与 Dart 产出不同，直接构成回归。若后续真机验证认为 `\r` 造成可见缺陷，按变更流程**单独**提「修正 Q-C」，不得在迁移中夹带。夹具 `ws/irc-crlf-boundary.expected.json` 的 `expected.ruling` 已写明。 |

> ⚠️ Q-C **期望值仍未写死**（`expected.messages` 保持 `null`，标记 `PENDING_REAL_CAPTURE`）：
> 需先由真实抓包（待抓包 **P-11**）确认 Twitch 帧行尾究竟是 `\r\n` 还是 `\n`。
> 若真实帧为 `\n`，则 `\r` 分支线上根本走不到，本夹具仅作防御性覆盖。
> 这与其「行为口径已裁决」不矛盾——**口径已定，取值待观测**。

### 8A.2 待产品/总监拍板（非实现 bug，登记备查）

| ID | 议题 | 现状 | 影响 |
|----|------|------|------|
| **Q-A** | Twitch 只对**设置了昵称颜色**的用户下发 `color` 标签，而 Dart 要求 `color` / `display-name` / `PRIVMSG` **三标签同时命中**才产出消息（`twitch_danmaku.dart:86-90`） | **未设置颜色的用户，其聊天在 Dart 与 Rust 两侧都收不到** | 这是**产品口径问题，不是实现 bug**：两侧行为一致，迁移不构成回归（AC-30 不受影响）。但它是真实的功能缺口。 |
| | 建议后续动作 | 真机抓包统计「无 `color` 标签用户的消息占比」后，再决定是否提「修正 Q-A」变更 | 修正 = 放宽三正则条件，属行为变更，须走独立变更流程并评估 App 侧影响 |

> 夹具 `ws/irc-privmsg-no-color.bin` / `-no-display-name.bin` 已把这个行为**钉死为「无产出」**，
> 与 Dart 一致。它们既是回归守护，也是将来提 Q-A 变更时的**修改点清单**。

---

## 9. 已知缺口与风险（如实上报，不静默降级）

| ID | 缺口 | 影响 | 解除条件 |
|----|------|------|---------|
| G-M1 | **全部 HTTP 夹具为合成**（`synthetic: true`） | 四平台 HTTP 解析可能与真实形态有偏差 | §5.2 的 P-1~P-13 抓包 |
| G-M2 | **全部 WS 帧为合成** | 服务端可能下发未列出的字段/命令 | §5.2 的 P-14 抓包 |
| ~~G-M3~~ | ~~`heldout` feature 未在 Cargo.toml 声明~~ **已关闭**：总监已添加，机制经双向验证可用（§6.4） | — | 待真实抓包回填后启用 |
| G-M4 | Twitch 的「不支持」能力**无Rust 用例覆盖** | 实现可能顺手实现 →破坏 AC-30 | IP-5 接入后补「抛错」断言（本目录已列出清单） |
| G-M5 | WS 重连时序（5s×5）**未覆盖** | 依赖可注入时间源，四平台均未就绪 | 各平台提供 `Clock`/`TimeSource` 注入后补（B站同缺口，见 `15-test-plan.md §6 G-3`） |
| G-M6 | 抖音 `search_anchors` 等「不支持」能力无 Rust 断言 | 同 G-M4 | IP-6 接入后补 |

---

## 10. 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-16 | 初始版本：四平台夹具（26 端点 / 80 变体 / 40 帧 / 5 golden）+ 10 个测试文件 + 待抓包清单 + heldout 策略 | `13-spec.md §13` 启动其余平台迁移，需先建立可机械验证的输入基线 |
| 2026-10-16 | **自检修正（3 处夹具缺陷，由独立回验发现）**：① 虎牙 `WSMsgItem` 作为 LIST 元素漏了 `STRUCT_BEGIN/END`；② 虎牙房间页 HTML 用了 `window.stream = {...}`，不匹配 Dart 的 `stream:` 正则且 JSON 跨行（`split('\n')[0]` 只解半截）；③ 抖音清晰度分支② 的期望值凭直觉写，实测发现真实行为是「**原画被丢弃、标清拿到原画地址**」，已按实测改正并标为「既有错位行为，不得顺手修正」。另修正斗鱼 `betard` 基线样本 `online` 自相矛盾（`hot='12.3万'` 却写 123000）、斗鱼 STT 转义夹具未真正转义、斗鱼 `searchUser` 缺错误流变体 | QA 独立复刻 Dart 算法回验时暴露；夹具与自身 `note` 矛盾会让实现者照着错的期望写代码 |
| 2026-10-16 | 补§7A「自检真实结论」；`fxcommon` 拆出 `tars.rs` 以守单文件 ≤300 行 | 门禁自检；全量 `cargo test` 因各agent 并行改动暂不可用，需如实标注 |
| 2026-10-16 | 补§8A「待裁决登记表」：**Q-C 裁决（照搬 Dart 不 trim）**、**Q-A 登记（无 color 用户收不到消息，产品口径非 bug）**；为 `irc-ping-privmsg-mixed` 补 `replies_derivation`；**新增§6A「夹具只能改生成器、禁止手工编辑」纪律** | 总监转 IP-5 反馈的夹具一致性与两项裁决请求 |
| 2026-10-16 | **heldout feature 落地并双向验证（§6.1/§6.4）**；缺口 G-M3 关闭；**纠正「B站 heldout 已同款运行」的错误前提** —— 实测 B站无 heldout 目录、全仓无门选用例，AC-36 机制此前从未真正运行 | 总监添加 `[features] heldout = []` 后要求验证开关生效 |