# Rust Core 落地第一步 · 迁移范围与验收标准（Spec 契约）

> 版本锚点：`dart_simple_live` fork future @ `4dcdb4fe`（2026-10-16）· worktree 分支 `feat/core-rust`
> 交付边界（用户已确认）：**crate 骨架 + B站（bilibili）端到端**
> 桥接版本（D6）：`flutter_rust_bridge = 2.13.0`（仓库既有 `simple_live_app/rust/` 口径；上游 slive_core 为 2.12.0，**不采用**）
> 依据：`docs/rust-core/00-briefing.md`（D1–D6）· `references/01-standards/spec-as-contract.md` · `references/01-standards/test-integrity-anti-gaming.md`
> 关联文档：`simple_live_core/doc/{architecture,test-suite,update-history}.md`
> 本文是 Spec 与 QA 的**唯一验收依据**。实现与本文冲突时：**先改本文，再改代码**（活规格）。

---

## 0. 本任务性质声明（防止误读）

这是**内部架构迁移**，不是新产品：UI 与用户可见交互**零变化**。因此本文不含传统产品 PRD 的用户故事/竞品定价/增长埋点，而聚焦三件事：

1. **功能对照清单（方法级）**——把 Dart core 现有 B站能力逐条钉到输入/输出/边界行为；
2. **范围锁定（做什么 / 明确不做什么）**；
3. **可机器验证的验收标准（EARS）**——每条断言给出「输入 → 期望输出」与证据形式。

> 行业知识库引用：本迁移无 UI/内容形态变更，`references/industries/content-platform.md` 仅两条对本任务有效——**禁止 emoji 作功能图标**（本轮无新增 UI，若后续涉及则统一 SVG 图标库，由架构师选型锁定）、**空状态须显式设计**（映射为本文的「未开播 / 房间不存在 / 空列表 / 分页到底」边界断言）。

---

## 1. B站功能对照清单（方法级）

来源：`simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart`（636 行）、`bilibili_danmaku.dart`（262 行）、`bilibili_emoticon.dart`（300 行）、`model/bilibili_user_info.dart`、`lib/src/interface/{live_site,live_danmaku}.dart`。

「边界行为」列是验收断言的设计依据；F-01 起的编号供 §2/§3 引用。

### 1.1 列表 / 搜索 / 详情 / 取流（HTTP）

| 编号 | 能力 | 输入 | 输出 | 边界行为 |
|------|------|------|------|----------|
| F-01 | 获取分类 A | `need_entrance=1, parent_id=0`；`getHeader()`（无 cookie 时用 buvid3/4） | `List<LiveCategory>`，含 `children: LiveSubCategory(id,name,parentId,pic)`；子类 `pic` 追加 `@100w.png` | 无 cookie 仍可请求（带 buvid）；`data` 缺失/空 → 空列表而非异常；网络失败 → `CoreError` |
| F-02 | 分类下房间 | `category.parentId/id`、`page`（默认 1）；`getAccessId()` 拼 `w_webid`；`getWbiSign()` 签名；`pageSize` **仅签名占位，接口固定 30 条/页，忽略** | `LiveCategoryResult(hasMore, items<LiveRoomItem>)`；`cover` 追加 `@400w.jpg` | `hasMore = data.has_more==1`；空 `list` → 空 items + `hasMore=false`；分页到底 → `has_more=0`；风控 `code!=0` → 抛错不放空 |
| F-03 | 推荐房间 | `sort=online`、`page`、`page_size=pageSize??30`；wbi 签名 | `LiveCategoryResult`；`cover` 追加 `@400w.jpg` | `hasMore = data.list 非空`（**本页非空判据**，非服务端字段）；空页 → `hasMore=false` |
| F-04 | 搜索房间 | `keyword`、`page`；`search_type=live&cover_type=user_cover` | `LiveSearchRoomResult(hasMore, items)`；title 去除 `<em>` 标签（正则 `<.*?em.*?>`）；`cover` 前缀补 `https:` 再追加 `@400w.jpg` | `hasMore = items.length>=40`（满页判据）；`result.live_room` 缺失 → 空列表；搜索被风控/空串 → 抛错 |
| F-05 | 搜索主播 | `keyword`、`page`；`search_type=live_user` | `LiveSearchAnchorResult(hasMore, items)`；`avatar` 前缀补 `https:` 追加 `@400w.jpg`；`userName` 去 `<em>` | `hasMore = items.length>=40`；`is_live` 原样透传为 `liveStatus` |
| F-06 | 房间详情 | `roomId`；先 `getRoomInfo`（`getInfoByRoom` + wbi）取 `realRoomId`，再 `getDanmuInfo`（wbi） | `LiveRoomDetail`：`roomId=realRoomId`、`title`、`cover`、`userName`、`userAvatar(+@100w.jpg)`、`online`、`status=(live_status==1)`、`introduction=description`、`notice=""`、`url=https://live.bilibili.com/{原roomId}`、`danmakuData=BiliBiliDanmakuArgs` | `host_list` 空 → 兜底 `broadcastlv.chat.bilibili.com`；`token` 取 `data.token`；未开播 → `status=false` 但仍返回详情与弹幕参数；房间不存在 → `getInfoByRoom` `code!=0`/`data=null` → 抛 `CoreError`，不得空指针 |
| F-07 | 清晰度列表 | `roomId`；`protocol=0,1&format=0,1,2&codec=0,1&platform=web` | `List<LivePlayQuality(quality,data=qn)>`：由 `g_qn_desc`(qn→desc) 映射 `stream[0].format[0].codec[0].accept_qn` | `accept_qn` 缺失/qn 未在映射 → 描述回落 `"未知清晰度"`；未开播 → 空列表而非异常 |
| F-08 | 播放地址 | `detail.roomId`、`quality.data(qn)`；`protocol=0,1&format=0,2&codec=0` | `LivePlayUrl(urls, headers{referer,user-agent})`；URL = `host+base_url+extra` | **mcdn 线路后置**（`urls.sort`：含 `mcdn` 排后）；无可用流 → 空 `urls`；`headers` 固定常量 |
| F-09 | 直播状态 | `roomId`；`room/v1/Room/get_info` | `bool = (data.live_status==1)` | `data` 缺失 → `false`；网络失败 → `CoreError` |
| F-10 | 房间 SC（HTTP 列表） | `roomId`；`av/v1/SuperChat/getMessageList` | `List<LiveSuperChatMessage>`：含 price/起止时间(ms→DateTime)/背景色/face(+@200w.jpg)/userName | `data.list` 为 null → 空列表；字段缺失用默认，不抛错 |

### 1.2 弹幕长连接（WebSocket）

| 编号 | 能力 | 输入 | 输出 | 边界行为 |
|------|------|------|------|----------|
| F-11 | 弹幕握手/连接 | `BiliBiliDanmakuArgs{roomId,token,buvid,serverHost,uid,cookie}`；`start(args)` | 连接 `wss://{serverHost}/sub`；`onReady` 后发 join 包（`encodeData(json,7)`：len+16 头、protover=3、platform=web、type=2、key=token、uid、roomid、buvid）；心跳 60s（`encodeData("",2)`） | cookie 空 → 握手不带 cookie 头；断线 → 5s×5 次重连（`WebScoketUtils`），超过 → `onClose("重连超过最大次数…")`；`stop()` 置空回调并关闭 |
| F-12 | 弹幕解码（人气） | op=3 帧 | 产出 `LiveMessage(type=online, data=int32 人气, color=white)` | body 不足 4 字节 → 只记日志不崩 |
| F-13 | 弹幕解码（消息，多协议） | op=5 帧；protover 0=JSON / 2=zlib / 3=brotli | 解压后按 `[\x00-\x1f]+` 切分，保留以 `{` 开头且长度>2 的片段逐条 `parseMessage` | 解压/解码失败 → 只记日志、不断连接、不抛到回调；`allowMalformed` 容忍脏字节 |
| F-14 | 解析聊天弹幕 | `DANMU_MSG` | `LiveMessage(type=chat)`：`message=info[1]`、`userName=info[2][1]`（info[2] 非空）、`color=numberToColor(info[0][3])`（0→白）、`emoticons=parseBilibiliEmoticons(...)` | `info` 非 List / 空 → 跳过；异常载荷 → 只记日志 |
| F-15 | 解析醒目留言（WS 下行） | `SUPER_CHAT_MESSAGE` | `LiveMessage(type=superChat, data=LiveSuperChatMessage)` | `data=null` → 直接返回；字段缺失 → 记日志 |
| F-16 | 弹幕表情包解析 | `info` + `message` | `List<LiveMessageEmoticon>?`：处理两入口（`info[0][13]` 单表情 / `info[0][15].extra.emots` 混排）；`large`/`emoticonUnique`/宽高；url 归一 https | 上限 8（**入口截断**）；两入口同图去重；裸名长度>12 / 含空白 / 含方括号 → 不整串替换；异常载荷 → `null`（不抛） |

### 1.3 账号体系（Cookie / 二维码 / 账号信息）

| 编号 | 能力 | 输入 | 输出 | 边界行为 |
|------|------|------|------|----------|
| F-17 | 注入凭证 | `setSiteAttrs(String)`：JSON `{"cookie":"..."}` | 写站点 `cookie` 字段 | 非 JSON / 缺 `cookie` 键 → 现状抛 `FormatException` 或静默保留旧值（**须在 AC 中钉死期望**，见 RISK-06） |
| F-18 | 生成登录二维码 | `passport .../qrcode/generate` | `QRCode(key=qrcode_key, url)` | `code!=0` → 抛 `message`；网络失败 → `CoreError` |
| F-19 | 轮询扫码状态 | `qrcode_key` | `QRPollResult(status, credential)`：code 0→`scanned`+credential（汇总 `set-cookie` 为 JSON `{"cookie":...}`）；86038→`expired`；86090→`scanned` | 其他 code → 保持 `unscanned`；`set-cookie` 空 → 不产 credential；接口 `code!=0` → 抛 `message` |
| F-20 | 获取账号信息 | `credential`(JSON 头) | `AccountInfo(name,avatar,uid,credential,isValid)`；成功时**副作用**：站点 `userId=info.mid`（供 F-06 弹幕 uid 配对） | `code!=0` → `isValid=false` 不抛；异常 → 捕获，`isValid=false`；`mid` 为 null → `!` 抛错被同段 catch 吞掉 → 空 `AccountInfo` |
| F-21 | 公共请求头 / 指纹 | — | `getHeader()`：无 cookie → `cookie=buvid3=..;buvid4=..`；有 cookie 且不含 buvid3 → 追加；`getBuvid()` 取 `x/frontend/finger/spi` | 指纹接口失败 → 返回空 buvid（不阻断） |

> F-22（辅助/内部）：wbi 签名链路 `getWbiKeys`(`x/web-interface/nav`) → `getMixinKey`(64 位重排表取前 32) → `getWbiSign`(wts + 排序 + 过滤 `!'()*` + md5)；`getAccessId`(从 `live.bilibili.com/lol` 正则 `"access_id":"..."`)，均带进程内缓存（`kImgKey/kSubKey/accessId`）。

---

## 2. 本轮迁移范围（锁定）

### 2.1 本轮做（IN）

| 项 | 内容 | 依据 |
|----|------|------|
| I-1 crate 骨架 | `common`（http/ws/log/error/binary/二进制工具）+ `model`（跨平台强类型）+ `interface`（Site/Danmaku 抽象）三层，依赖只向下 | D3 |
| I-2 B站全部方法 | F-01 ~ F-21 全部（方法级覆盖，行为与 Dart core 对齐） | D1/D3 |
| I-3 FRB 绑定 | `flutter_rust_bridge` 2.13.0，Dart 直连 FRB API（不保留 Dart 薄壳） | D2/D6 |
| I-4 单测 | 离线 fixture 用例为主（覆盖 F-01~F-21 + 边界），联网冒烟仅作「协议是否还活着」 | D3 + test-integrity |
| I-5 可回退开关 | B站路径可在「Rust Core / Dart core」间切换，默认安全、可一键回退 | 门禁 §7-1 |

### 2.2 本轮明确不做（OUT，逐条给原因）

| 项 | 不做原因 |
|----|----------|
| O-1 其余 4 平台（douyu / huya / douyin / twitch） | D2 明确「bilibili 以外的平台暂留 Dart」；本轮只验证「骨架 + 单平台端到端」的可复制路径，不摊薄范围 |
| O-2 JS Plugin（上游路线图第二步） | 上游 issue #155 路线图排序；本轮是第一步，且 core 已在 `architecture.md §3.5` 剥除 `flutter_qjs`，无 JS 依赖需求 |
| O-3 枪弹分离 | 路线图第三步，依赖前两步就位 |
| O-4 Plugin 分发 | 路线图第四步，依赖前两步就位 |
| O-5 任何 UI / 用户可见交互改动 | 本任务性质是内部迁移，UI 零变化（见 §0）；改 UI 会破坏「回归约束」的可判定性 |
| O-6 B站弹幕**发送** | Dart core 的 `LiveDanmaku` 无发送接口（`live_danmaku.dart:5-25` 仅回调/心跳/start/stop）；不新增能力 |
| O-7 直链续流 `renewers`（B站） | 该机制仅斗鱼需要（`live_play_url.dart:8-22`）；B站无此语义，随 O-1 一并排除 |
| O-8 抖音 protobuf / 虎牙 TARS 的 Rust 重生成 | 属 O-1 范围（对应平台迁移时再做） |

---

## 3. 验收标准（锁定 · QA 唯一依据）

规则：EARS 句式（当/如果/在…状态/在…配置下 + 系统 + 必须/应该 + 行为）。编号 AC-01 起。**每条必须可机器验证**（夹具输入 → 期望输出；或构建/命令真实输出）。优先级 P0 = 阻断合并；P1 = 可延后但须登记。

### 3.1 核心成功流（每类请求一条）

| 编号 | 优先级 | 验收标准（EARS） | 验证方式（机器可验证） |
|------|--------|------------------|------------------------|
| AC-01 | P0 | 当调用分类接口时，系统**必须**返回 `LiveCategory` 列表，子类 `pic` 以 `@100w.png` 结尾。 | 离线夹具（`Area/getList` 合成响应）断言条数与 `pic` 后缀 |
| AC-02 | P0 | 当调用分类下房间接口时，系统**必须**按 `has_more==1` 决定 `hasMore`，且每条 `cover` 以 `@400w.jpg` 结尾。 | 离线夹具断言 `hasMore` 与 cover 后缀；`has_more` 缺省为 0 |
| AC-03 | P0 | 当调用推荐接口且响应 `list` 非空时，系统**必须**返回 `hasMore=true`（**不**采信任何服务端分页字段）。 | 离线夹具：`list` 非空 → true；空 → false |
| AC-04 | P0 | 当搜索房间时，系统**必须**剔除 title 中 `<em>` 标签、为 `cover` 补 `https:` 前缀，并以 `items.length>=40` 判定 `hasMore`。 | 离线夹具含 `<em>` 的 title 与相对 cover；断言清洗结果 |
| AC-05 | P1 | 当搜索主播时，系统**必须**为 `avatar` 补 `https:` 前缀、去 `<em>`，`hasMore` 判据同 AC-04。 | 离线夹具断言 avatar/uname |
| AC-06 | P0 | 当请求房间详情时，系统**必须**返回 `roomId=真实房间号`、`status=(live_status==1)`、`url=https://live.bilibili.com/{请求房间号}`，且 `danmakuData` 携带 `roomId/token/serverHost/uid/buvid/cookie`。 | 离线夹具两步响应（getInfoByRoom + getDanmuInfo）；断言字段与 `serverHost` |
| AC-07 | P0 | 当请求清晰度列表时，系统**必须**由 `g_qn_desc` 映射 `accept_qn` 产出清晰度项；无法映射的 qn 描述**必须**为 `"未知清晰度"`。 | 离线夹具构造映射缺失项 |
| AC-08 | P0 | 当请求播放地址时，系统**必须**拼出 `host+base_url+extra`，且**含 `mcdn` 的 URL 必须排在最后**；`headers` **必须**含固定 referer/user-agent。 | 离线夹具含 mcdn 与非 mcdn 线路；断言排序与 headers |
| AC-09 | P0 | 当查询直播状态时，系统**必须**返回 `data.live_status==1` 的布尔值。 | 离线夹具 live_status∈{0,1} |
| AC-10 | P1 | 当请求 SC 列表时，系统**必须**把 `start_time/end_time`（秒）转为毫秒时间、`face` 以 `@200w.jpg` 结尾。 | 离线夹具断言时间与 face |
| AC-11 | P0 | 当 `start` 建立弹幕连接后，系统**必须**发送字节序正确的 join 包（长度前缀/头长 16/protover 3/op 7/seq 1 + JSON body）。 | 离线：对 `encodeData(json,7)` 做逐字节 golden 断言 |
| AC-12 | P0 | 当收到 op=3 帧时，系统**必须**产出 `type=online` 的 `LiveMessage`，`data` 为 big-endian int32 人气值。 | 离线：构造 4 字节 body（如 `00 00 30 39`）断言人气值 |
| AC-13 | P0 | 当收到 op=5 帧且 protover 为 0/2/3 时，系统**必须**分别按 JSON/zlib/brotli 解压并切分出多条 JSON 逐条解析。 | 离线：三路真帧 fixture；断言条数 |
| AC-14 | P0 | 当解析 `DANMU_MSG` 时，系统**必须**产出 `type=chat`，`color` 按 `numberToColor(info[0][3])`（0→白），并挂载表情包解析结果。 | 离线夹具（含彩色与表情载荷） |
| AC-15 | P0 | 当解析 `SUPER_CHAT_MESSAGE` 时，系统**必须**产出 `type=superChat` 且 `data` 为 `LiveSuperChatMessage`；`data=null` 时**必须**静默返回。 | 离线夹具两种 case |
| AC-16 | P0 | 当解析弹幕表情时，系统**必须**：两入口同图去重、单条上限 8（入口截断）、url 统一升 https、异常载荷返回 `null`。 | 离线：对齐 `bilibili_emoticon_test.dart` 的 31 条契约（迁移为 Rust 用例） |
| AC-17 | P0 | 当 `setSiteAttrs` 收到 `{"cookie":"..."}` 时，系统**必须**把 `cookie` 值写入站点字段（**非**整串 JSON）；**如果**入参为非法 JSON，系统**必须**抛出类型化错误（`CoreError::InvalidInput`）；**如果** JSON 合法但缺 `cookie` 键，系统**必须**保留旧值不变。 | 离线：注入后断言后续请求 Cookie 头不含 `{"cookie"` 字面量；非法 JSON → 断言抛错类型；缺键 → 断言站点字段旧值不变（凭证日志明文约束见 AC-40） |
| AC-18 | P1 | 当生成二维码时，系统**必须**返回 `key/url`；`code!=0` 时**必须**抛错（不返回空码）。 | 离线夹具 code=0 / code!=0 |
| AC-19 | P0 | 当轮询扫码时，系统**必须**按 code 映射状态：0→`scanned`+credential（JSON `{"cookie":...}`）、86038→`expired`、86090→`scanned`，其余→`unscanned`。 | 离线夹具覆盖四类 code |
| AC-20 | P0 | 当账号校验成功时，系统**必须**返回 `isValid=true` 且回填 `userId=mid`（副作用）；`mid` 为 null 或 `code!=0` 时**必须**返回 `isValid=false`，**不得**抛错。 | 离线夹具 + 断言站点 `userId` 字段变化 |
| AC-21 | P0 | 当构造请求头时，系统**必须**在无 cookie 时注入 `buvid3/buvid4`，有 cookie 且缺 buvid3 时**必须**追加；wbi 签名**必须**对固定 `img_key/sub_key/wts` 产出确定的 `w_rid`。 | 离线：固定入参 → 固定 `w_rid`（确定性 golden） |

### 3.2 关键错误流 / 边界

| 编号 | 优先级 | 验收标准（EARS） | 验证方式 |
|------|--------|------------------|----------|
| AC-22 | P0 | 如果房间未开播，系统**必须**返回 `status=false` 且不抛异常，并**仍**返回可用的弹幕参数（serverHost 兜底）。 | 离线夹具 live_status=0 |
| AC-23 | P0 | 如果房间不存在（`getInfoByRoom` `data=null` 或 `code!=0`），系统**必须**抛出类型化错误（`CoreError`），**不得**空指针/panic。 | 离线夹具；断言错误类型与消息 |
| AC-24 | P0 | 如果账号凭证无效（`member/web/account` `code!=0`），系统**必须**返回 `isValid=false` 的空 `AccountInfo` 且不抛错。 | 离线夹具 |
| AC-25 | P0 | 如果接口返回风控/业务错误码（`code!=0`，如 `-352`），系统**必须**抛出携带服务端 message 的类型化错误（`CoreError`），**不得**静默返回空列表，且**不得自动重试**。 | 离线夹具 code=-352；断言抛出错误类型/消息，且请求次数 == 1（无重试） |
| AC-26 | P0 | 如果 HTTP 请求失败，系统**必须**映射为 `CoreError`；如果 WS 断线，系统**必须**在 5s×5 次重连后触发 `onClose`，收到消息后重连计数归零。 | 离线：错误映射用例 + WS mock；不依赖墙钟/绝对时序 |
| AC-27 | P0 | 如果列表接口返回空页，系统**必须**返回 `items=[]` 且 `hasMore=false`，且**不得**抛异常。 | 离线：F-01~F-05 参数化空页 |
| AC-28 | P0 | 如果弹幕帧损坏（长度不足 / 解压失败 / 非法 JSON），系统**必须**只记日志、不断连接、不向回调抛出。 | 离线：脏帧夹具，断言回调未被调用且连接状态未变 |
| AC-29 | P1 | 如果 `accept_qn` 为空或 qn 无描述，系统**必须**返回空列表或 `"未知清晰度"`，不抛异常。 | 离线夹具 |

### 3.3 回归约束（迁移不得破坏既有行为）

| 编号 | 优先级 | 验收标准（EARS） | 验证方式 |
|------|--------|------------------|----------|
| AC-30 | P0 | 当本轮迁移合入后，其余 4 平台（douyu/huya/douyin/twitch）**必须**继续走 Dart core 且行为不变。 | App 侧 Dart 测试回归名单逐条比对：**零新增失败**（对齐 `update-history.md §5.3` 的「失败名单逐条一致」口径） |
| AC-31 | P0 | 当 B站开关置于「Dart」时，App **必须**仍可正常使用 B站全部功能（可回退）。 | 开关切换后的路径走查 + 冒烟；关闭 Rust 路径不得影响构建 |
| AC-32 | P0 | 本轮**必须**不引入任何用户可见交互变化（页面/文案/布局/图标）。 | diff 审查：仅 `simple_live_core` Rust 侧 + `simple_live_app/rust` 与绑定层，无 UI 文件改动 |
| AC-33 | P0 | 迁移后源码**必须**满足门禁：单文件 ≤300 行、依赖只向下、无 emoji 作图标、无 TODO 空壳/占位实现。 | 脚本化统计（行数/lint）+ diff 人工核对 |
| AC-34 | P1 | 当 Dart core 的 B站代码被 Rust 取代时，Dart 侧**应该**保留至回退窗口结束（不提前删除）。 | git 审查：删除动作与回退窗口结束同批 |

### 3.4 证据与反作弊（对齐 test-integrity-anti-gaming）

| 编号 | 优先级 | 要求 |
|------|--------|------|
| AC-35 | P0 | 核心验收由**实现者改不动**的确定性校验把关：join 包逐字节 golden、wbi 固定入参→固定 `w_rid`、脏帧解码结果，均由固定输入→固定期望断言，不得由被测代码「自证」。 |
| AC-36 | P0 | 必须存在一组**留出（held-out）**弹幕/响应夹具，实现者不可见；仅用于最终判定，防「特判可见用例」。 |
| AC-37 | P0 | 实现 diff 与测试/门禁 diff **必须**分开呈现、分开评审（完整性差异）。任何删/弱断言、新增 `skip/ignore/xfail`、改阈值/基线**必须**单独说明并经复核；禁止以放宽测试换绿。 |
| AC-38 | P0 | 关键路径证据**必须**为真实命令输出（`cargo test` / `cargo clippy` / FRB 代码生成 / App 侧 `flutter test`），落盘日志；不接受「我觉得可以」。 |

### 3.5 绑定层与凭证安全（修订增补）

| 编号 | 优先级 | 验收标准（EARS） | 验证方式 |
|------|--------|------------------|----------|
| AC-39 | P0 | 在存在绑定层（`RustBilibiliSite` 或等价物）的配置下，该层**必须**只做**类型翻译与转发**，**不得**包含任何协议逻辑（URL 拼接 / 签名 / 解析 / 重试 / 编解码）。 | 该文件代码审查 + 断言其中无 HTTP/WS/签名调用（防止退化成被 D2 否决的「Dart 薄壳」） |
| AC-40 | P0 | 在凭证注入或账号校验后，系统**不得**在日志（含调试输出）中出现 `credential` / `cookie` 明文（对齐 §6 安全要求与 `bilibili_site.dart:598` 的教训）。 | 离线：注入/校验后捕获日志，断言不含 SESSDATA 等明文子串 |

---

## 4. 功能覆盖差异表（确认 Rust 侧不丢能力）

图例：`有` = 具备；`无` = 不具备；`部分` = 部分具备/等价替代。（原「待确认」三项已由架构师核实上游并回填，见 RISK-10。）

| 能力 | Dart core B站（迁移源） | DTV B站（`C:\DTV`，2298 行） | 上游 slive_core B站（Dart 壳 `BilibiliSite` + Rust `platforms-parser`） |
|------|:---:|:---:|:---:|
| 分类 A 列表 | 有 F-01 | 无（仅 area→rooms，无分类表） | 有 `getCategories` |
| 分类下房间 | 有 F-02（wbi + `w_webid`） | 有 `fetch_bilibili_live_list`（固定 secret 签名 + `w_webid`） | 有 `getCategoryRooms` |
| 推荐房间 | 有 F-03（`sort=online`，真用 `page_size`） | 无 | 有 `getRecommendRooms`（**无 `pageSize`**） |
| 搜索房间 | 有 F-04 | 有 `search_bilibili_rooms` | 有 `searchRooms` |
| 搜索主播 | 有 F-05 | 无（只走 `search_type=live`） | 有 `searchAnchors` |
| 房间详情 | 有 F-06 | 有 `fetch_bilibili_streamer_info`（wbi） | 有 `getRoomDetail` |
| 清晰度列表 | 有 F-07 | 有（`qn_map`+`accept_qn`+`match_qn`） | 有 `getPlayQualities` |
| 播放地址 | 有 F-08（mcdn 后置） | 有（flv/hls 变体 + `d1--cn` 优先 + 重试） | 有 `getPlayUrls` |
| 直播状态 | 有 F-09（`Room/get_info`） | 有（`Room/room_init`） | 有 `getLiveStatus` |
| SC | 有 F-10（HTTP）+ F-15（WS） | 无 | 有 `getSuperChatMessages`（HTTP，**命名复数**） |
| 弹幕接收 | 有 F-11~F-15 | 有 `websocket.rs`（op5 ver3 解压；**无 zlib(ver2) 分支**；心跳 30s） | 有 `danmaku/*` |
| **表情包解析** | 有 F-16（fork 独有，31 用例） | 无 | 无（`LiveMessage` 无 `emoticons` 字段） |
| 账号-Cookie 注入 | 有 F-17 `setSiteAttrs(String)` | 部分（cookie 逐请求传参；`cookie.rs` 走 webview 采集） | 无（B站 Site 无账号接口） |
| 账号-二维码登录 | 有 F-18/F-19 | 无（用隐藏 webview 采集 cookie） | 无 |
| 账号-账号信息 | 有 F-20（+`userId` 回填副作用） | 部分（`init_uid` 走 `nav`） | 无 |
| 弹幕发送 | 无 | 无 | 无 |
| wbi 签名 | 有 F-22 | 有（`auth.rs` + 固定 secret 变体） | 有 `wbi.rs` |
| buvid3/4 指纹 | 有 F-21 | 部分（部分硬编码 `buvid3=i`） | 有（`nav` 内） |
| w_webid（分类/推荐） | 有 F-02 | 有 | 有（`access_id`） |
| mcdn 线路后置 | 有 F-08 | 无（改用 `d1--cn` 优先策略） | 无 |
| 多协议解压（JSON/zlib/brotli） | 有 F-13 | 部分（仅 ver3 brotli） | 有（zlib+brotli 双分支） |

**结论（给架构师的硬约束）：**（依 RISK-10 核实结果精确化）

1. **Dart core 有、DTV 与上游 B站均无（或形态不符）**，Rust 侧**必须从 Dart core 重实现**，二者均无法作蓝本：**表情包解析（F-16）**、**账号三接口（QR/Cookie/账号信息）+ `userId` 回填副作用（F-17~F-20）**、**mcdn 后置排序（F-08）**。
2. **DTV B站无、但上游有**——可参照上游形态，但**必须保证行为不丢**且与 Dart core 语义对齐：分类 A 列表、推荐房间、搜索主播、SC（HTTP）、**多协议解压（zlib+brotli 双分支）**、`w_webid`(access_id)、buvid SPI。
3. DTV 的强项（`d1--cn` 优先、HLS 重试、flv/hls 变体、线路容错）可作为 F-08 的**增强参考**，但不得替换 Dart core 的既有语义（否则违反 AC-30/AC-32）。

---

## 5. 迁移完成定义（DoD）

以下**每一条均为可判定**，全部满足方可判「本轮完成」：

- [ ] **DoD-1 构建**：Rust Core 工作区 `cargo build` 通过；FRB 代码生成成功且 `flutter_rust_bridge==2.13.0`（版本可查）。
- [ ] **DoD-2 离线测试**：B站 F-01~F-21 的离线 fixture 用例**全通过**，`skip/ignore/xfail = 0`；留出（held-out）用例集单独判定通过（AC-36）。
- [ ] **DoD-3 端到端**：选一固定房间（如 `6` 或 `danking`）走通「详情 → 清晰度 → 播放地址 → 弹幕 30s 窗口」，四步输出非空；覆盖一条错误流（未开播或房间不存在）。
- [ ] **DoD-4 回归为零**：App 侧 Dart 测试失败名单与迁移前**逐条一致**（零新增失败）；其余 4 平台能力不变（AC-30）。
- [ ] **DoD-5 可回退**：B站开关切至 Dart 后，旧路径仍可用、可构建（AC-31）。
- [ ] **DoD-6 门禁**：单文件 ≤300 行、依赖只向下、无 emoji 图标、无占位实现（AC-33）。
- [ ] **DoD-7 证据留痕**：实现 diff 与测试 diff 分离；`cargo test/clippy` + FRB 生成 + App 侧测试的真实输出落盘（AC-37/AC-38）。
- [ ] **DoD-8 规格同步**：实现与本文冲突处已**先改本文**（活规格）。

---

## 6. 非功能需求（迁移语境，非产品语境）

| 类别 | 要求 | 优先级 | 机器可验证性 |
|------|------|--------|--------------|
| 性能 | 每类 B站请求不得引入**额外串行往返**（请求数 ≤ Dart core 同路径）；离线断言请求参数集合一致 | P1 | 断言拦截到的请求 URL/参数集合（不依赖墙钟，抗 flaky） |
| 兼容性 | `flutter_rust_bridge=2.13.0`；App 侧 Flutter `3.47.6`、core 侧 `.fvmrc` 现状；Rust edition 与 DTV 依赖兼容（reqwest/tokio/brotli） | P0 | 版本文件 + `cargo tree` 输出 |
| 可用性/可回退 | B站路径可开关；Rust 路径不可用时 Dart 路径仍可用，无单点 | P0 | 开关切换走查（DoD-5） |
| 安全 | credential/cookie **不得**写入日志（注意 `bilibili_site.dart:598` 曾 `CoreLog.i(cookieStr)`，Rust 侧**禁止**复刻该行为，见 AC-40）；仅 HTTPS | P0 | 日志断言 + 代码审查 |
| 可维护性 | 三层分层、单一职责、单文件 ≤300 行、依赖只向下 | P0 | 行数脚本 + lint |
| 国际化 | 不适用（无用户可见文案变化） | — | — |
| 埋点 | **不适用**：内部迁移、UI 零变化，不新增/修改任何埋点。上线后无「产品假设」需埋点验证 | — | 明确排除并说明理由（避免空洞占位） |

---

## 7. 风险与依赖（裁决状态）

> 状态：RESOLVED = 已裁决并锁定；执行待办 = 方案已定、实现期落地；OPEN = 仍待裁决。裁决结论已并入 §2/§3/§4。

| 编号 | 事项 | 裁决结论 / 状态 |
|------|------|-----------------|
| RISK-01 | 模型形态（`LiveMessage`） | **RESOLVED**：Rust `LiveMessage` **保留 `color` + `emoticons` + `data` 语义**（在 D4 基础上扩展，非纯对齐上游；否则丢 F-14/F-16）。 |
| RISK-02 | `data`/`danmakuData` 通道 | **RESOLVED**：`data` 采用**类型化枚举/强类型**表达桥接 FRB（非裸 JSON string）；`BiliBiliDanmakuArgs` 以强类型 struct 暴露。 |
| RISK-03 | 账号体系是否纳入 MVP | **RESOLVED**：**账号三接口（QR 登录 / Cookie 注入 / 账号信息）全部纳入本轮**（纯 HTTP，无 webview 依赖；覆盖 F-17~F-20）。 |
| RISK-04 | `pageSize` 参数 | **RESOLVED**：**保留** `pageSize`（B站推荐真用，保 fork 语义）。 |
| RISK-05 | SC 接口命名 | **RESOLVED**：**两全**——保留 fork 单数 `getSuperChatMessage`，同时提供上游复数 `getSuperChatMessages` 别名。 |
| RISK-06 | `setSiteAttrs` 容错 | **RESOLVED**：非法 JSON → 抛类型化错误（`CoreError::InvalidInput`）；缺 `cookie` 键 → 保留旧值（见 AC-17）。 |
| RISK-07 | 测试夹具来源 | **方案已定、执行待办**：架构师已在方案中给出夹具方案（真实响应/弹幕帧 + 可注入 adapter + 留出集），**实现期落地**。 |
| RISK-08 | 风控码（`-352` 等）处理 | **RESOLVED**：抛带服务端 message 的类型化错误，**不自动重试**（见 AC-25）。 |
| RISK-09 | Dart core B站代码去留 | **RESOLVED**：Dart B站代码**保留至回退窗口结束**再删（见 AC-31/AC-34）。 |
| RISK-10 | 上游 `platforms-parser` 覆盖度 | **RESOLVED**（架构师已核实）：上游**有** `w_webid`(access_id)、buvid SPI、**zlib+brotli 双分支**、SC(HTTP)；**无** mcdn 后置排序、表情包解析、账号三接口。§4 三项「待确认」已回填、结论已精确化。 |

---

## 附录 A：EARS 句式对照（本文件用法）

| 终止式 | 句式 | 本文件示例 |
|--------|------|-----------|
| Event-driven | 当 <触发>，系统必须 <响应> | AC-01 / AC-06 |
| State-driven | 在 <状态> 下，系统必须 <响应> | （本轮无独立状态依赖） |
| Unwanted behavior | 如果 <条件>，系统必须 <响应> | AC-22 ~ AC-29 |
| Optional feature | 在 <配置> 下，系统应该 <响应> | AC-34 |
| Ubiquitous | 系统必须 <响应> | AC-35 ~ AC-38 |
| Constraint（约束） | <约束对象> 必须 / 不得 <行为> | AC-39 / AC-40 |
