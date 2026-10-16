# B站逐方法映射表（Dart core → 目标 Rust）

> 用途：把 B站每条能力钉到「迁移源（Dart core）→ 实现参考（DTV）→ 目标 Rust 模块/函数」，并标注复用度，供实现者逐条照做、供评审逐条核对。
> 源：`simple_live_core/lib/src/platforms/bilibili/*`、`lib/src/interface/*`、`lib/src/common/*`、`lib/src/model/*`
> 参考：`C:\DTV\src-tauri\src\platforms\bilibili\*`、`C:\DTV\src-tauri\src\platforms\common\*`
> 目标：`simple_live_app/rust/crates/slive-core/src/**`、桥 `simple_live_app/rust/src/api/slive/**`（见 `10-architecture.md §1.3`）
> 复用度图例：**直接移植**（算法/协议等价，改动限于接口适配）｜**需改写**（语义/签名/策略不同，须按 Dart core 契约重写）｜**需新写**（DTV 与上游均无，须自建）
>
> **重要口径（总监修正 + PM §4）**：**DTV 不是「平台实现主参考」**。DTV 缺 core 独有的 **9 项**能力（见 §7），这 9 项**必须从 Dart core 重实现**；DTV 仅作**局部增强参考**（`d1--cn` 优先 / HLS 重试），**不得替换既有语义**（否则违反 AC-30/AC-32）。

---

## 1. 公共基础层（common）

| 能力 / 编号 | Dart（file:line） | DTV（file:line） | 目标 Rust（module::fn） | 复用度 |
|---|---|---|---|---|
| HTTP 客户端（单例 + 统一错误 + 瞬断重试） | `common/http_client.dart:6-197`（Dio 单例、20s 超时、`CoreError`） | `common/http_client.rs:16-344`（`reqwest`、`http1_only`、`timeout45s`、瞬断重试 `:156-174`） | `slive-core::http::HttpClient`（共享 Client，rustls，见 ADR-003/005） | 需改写 |
| WS 封装（心跳/重连/backupUrl） | `common/web_socket_util.dart:11-164`（`5s×5` 重连、心跳定时器） | `bilibili/websocket.rs:88-119,230-264`（`maybe_send_heartbeat`/`reconnect`，`2 次` 重连） | `slive-core::ws::session::WsSession`（心跳 60s、`5s×5` 重连，对齐 Dart） | 需改写 |
| WS 帧头编解码 | `bilibili_danmaku.dart:119-145`（`encodeData`）、`:241-261`（`readInt`） | `bilibili/websocket.rs:337-356`（`make_packet`）、`:358-393`（`get_msg_header`） | `slive-core::ws::frame::{encode_packet, parse_header}` | 直接移植 |
| 解压（zlib/brotli） | `bilibili_danmaku.dart:168-172`（`zlib.decode`/`brotli.decode`） | `bilibili/websocket.rs:395-402`（仅 brotli） | `slive-core::ws::frame::decompress`（zlib `flate2` + brotli `brotli`，双分支） | 需改写（DTV 缺 zlib 分支，须补 F-13 的 ver2） |
| 二进制读写（大端） | `common/binary_writer.dart:3-149` | （无独立文件；DTV 手工字节序） | `slive-core::ws::frame`（`u32::from_be_bytes`/`to_be_bytes`） | 需改写（Rust 原生替换） |
| 统一错误 | `common/core_error.dart:1-41` | （无；DTV 用 `Result<_,String>`） | `slive-core::error::SliveError`（thiserror） | 需新写 |
| 日志 | `common/core_log.dart` | `println!/eprintln!` 混杂 | `log`/`tracing`（统一）；**禁止**记录 cookie/credential | 需改写 |
| cookie 解析 | `common/parse_cookie.dart:4-12` | `bilibili/search.rs:50-91`（`parse_cookie_pairs`/`find_cookie`/`upsert_cookie`/`build_cookie_header`） | `slive-core::platforms::bilibili::cookie`（私用） | 直接移植 |
| 安全类型转换 `asT<T>` | `common/common_asT.dart:1-6` | `serde_json::Value` 取值 + `unwrap_or` | `serde_json` + `Option`（无需对应函数） | 需改写 |
| 二维码状态枚举 | `common/qr_status.dart:1-7` | （无） | `slive-core::models::QrStatus` | 需新写 |

---

## 2. 列表 / 搜索 / 详情 / 取流（F-01 ~ F-10）

| 编号 | 能力 | Dart（file:line） | DTV（file:line） | 目标 Rust（module::fn） | 复用度 |
|---|---|---|---|---|---|
| F-01 | 分类 A 列表 | `bilibili_site.dart:51-80`（`Area/getList`，子类 `pic` 追加 `@100w.png`） | **无**（DTV 只有 area→rooms，无分类表） | `platforms::bilibili::categories::get_categories` | 需新写 |
| F-02 | 分类下房间 | `bilibili_site.dart:82-114`（`second/getList` + `getAccessId`(w_webid) + `getWbiSign`；`cover +@400w.jpg`；`has_more==1`） | `live_list.rs:6-134`（`second/getList`，但用**固定 secret** 签名 + `w_webid`、`web_location=444.253`） | `platforms::bilibili::rooms::get_category_rooms` | 需改写（签名口径不同：Dart 用 wbi；DTV 用固定 secret） |
| F-03 | 推荐房间 | `bilibili_site.dart:195-222`（`second/getListByArea`，`sort=online`，真用 `page_size`；`hasMore=本页非空`） | **无** | `platforms::bilibili::rooms::get_recommend_rooms` | 需新写 |
| F-04 | 搜索房间 | `bilibili_site.dart:273-304`（`search/type?search_type=live`；去 `<em>`；`cover` 补 `https:`；`hasMore=items>=40`） | `search.rs:140-261`（`search_bilibili_rooms`，`strip_em_tags`:26、`normalize_image`:30、`ensure_buvid`:93） | `platforms::bilibili::search::search_rooms` | 直接移植（协议等价；按 Dart 需求补 `hasMore` 判据） |
| F-05 | 搜索主播 | `bilibili_site.dart:307-337`（`search_type=live_user`；`avatar` 补 `https:`+`@400w.jpg`） | **无**（DTV 只走 `search_type=live`） | `platforms::bilibili::search::search_anchors` | 需新写（可复用 F-04 的清洗/补全工具函数） |

> **注意 · F-05 `is_live` 类型风险（QA advisory G-4）**：`bilibili_site.dart:332` 把 `item["is_live"]` **裸赋给 `bool` 字段**（`live_anchor_item.dart:14`）—— 服务端若返回 **int**（B站部分接口返 `0/1`），Dart 现状即抛 `TypeError`（既有隐性缺陷）。Rust 侧**必须显式容错**：接受 int / bool / 字符串 并**归一化为 `bool`**（`0`/`false`/`"0"` → `false`，其余 `true`），**不得照抄 Dart 的裸赋值**。已纳入 AC-05 的边界断言范围。
| F-06 | 房间详情 | `bilibili_site.dart:225-270`（`getInfoByRoom`(wbi)→`realRoomId`；`getDanmuInfo`(wbi)→`host_list/token`；组 `BiliBiliDanmakuArgs`） | `streamer_info.rs:102-202`（`fetch_bilibili_streamer_info`，wbi `getInfoByRoom`）+ `auth.rs:149-191`（`init_host_server`→`getDanmuInfo`）+ `auth.rs:198-253`（组 `AuthMessage`） | `platforms::bilibili::detail::get_room_detail` | 需改写（DTV 拆两次命令且返回 `LiveStreamInfo`；须按 Dart 契约组装 `LiveRoomDetail + danmaku_data`） |
| F-07 | 清晰度列表 | `bilibili_site.dart:117-143`（`getRoomPlayInfo`；`g_qn_desc`→`accept_qn` 映射） | `stream_url.rs:74-169`（`request_playinfo` + `qn_map` + `accept_qn` 解析） | `platforms::bilibili::play::get_play_qualities` | 直接移植（映射算法等价） |
| F-08 | 播放地址 | `bilibili_site.dart:146-192`（`protocol=0,1&format=0,2&codec=0`；`host+base_url+extra`；**mcdn 后置**） | `stream_url.rs:272-346`（`parse_stream_variants`，flv/hls 变体）+ `:348-458`（HLS 校验/重试/`d1--cn` 优先） | `platforms::bilibili::play::get_play_urls` | 需改写（DTV 策略为「`d1--cn` 优先 + HLS 重试」；本轮**必须**保留 Dart core 的「mcdn 后置」语义，DTV 的容错仅作增强参考） |
| F-09 | 直播状态 | `bilibili_site.dart:340-349`（`room/v1/Room/get_info`，`live_status==1`） | `stream_url.rs:236-251`（`room_init`，`live_status`） | `platforms::bilibili::status::get_live_status` | 需改写（端点不同：`Room/get_info` vs `room_init`；按 Dart 契约取 `Room/get_info`） |
| F-10 | SC（HTTP 列表） | `bilibili_site.dart:352-379`（`av/v1/SuperChat/getMessageList`；秒→毫秒；`face +@200w.jpg`） | **无** | `platforms::bilibili::super_chat::get_super_chat_messages` | 需新写 |

---

## 3. 弹幕长连接（F-11 ~ F-16）

| 编号 | 能力 | Dart（file:line） | DTV（file:line） | 目标 Rust（module::fn） | 复用度 |
|---|---|---|---|---|---|
| F-11 | 握手/连接/心跳 | `bilibili_danmaku.dart:58-117`（`start`/`joinRoom`/`heartbeat`/`stop`；心跳 60s；join=protover3/type2/key/uid/roomid/buvid） | `websocket.rs:44-95`（`BiliLiveClient`/`send_auth`/`send_heart_beat`，心跳 30s）+ `auth.rs:198-253`（鉴权包） | `platforms::bilibili::danmaku::session::connect` | 需改写（心跳 30s→60s；`AuthMessage` 字段对齐 Dart：uid/roomid/protover3/platform web/type2/key/buvid） |
| F-12 | 解码：人气（op=3） | `bilibili_danmaku.dart:155-166`（big-endian int32 人气） | `websocket.rs:156-166`（解析 op=3 但**仅 debug 打印**，不产出） | `platforms::bilibili::danmaku::parse::parse_popularity` | 需改写（DTV 丢弃，Dart 产出 `LiveMessage{type=online}`） |
| F-13 | 解码：消息（op=5，protover 0/2/3） | `bilibili_danmaku.dart:147-184`（JSON/zlib/brotli；按 `[\x00-\x1f]+` 切分） | `websocket.rs:122-228`（`parse_ws_message`/`parse_business_message`；**仅 ver0/ver3**） | `platforms::bilibili::danmaku::protocol::decode` | 需改写（补 ver2 zlib；切分规则按 Dart） |
| F-14 | 解析聊天弹幕（DANMU_MSG） | `bilibili_danmaku.dart:186-208`（`info[1]`/`info[2][1]`/`info[0][3]` 颜色） | `websocket.rs:404-425`（`handle`，仅取 user/text；**无颜色/表情**） | `platforms::bilibili::danmaku::parse::parse_danmu_msg` | 需改写（补颜色 `numberToColor`、表情挂载） |
| F-15 | 解析醒目留言（WS） | `bilibili_danmaku.dart:209-235`（`SUPER_CHAT_MESSAGE`→`LiveSuperChatMessage`） | **无** | `platforms::bilibili::danmaku::parse::parse_super_chat` | 需新写 |
| F-16 | 弹幕表情包解析 | `bilibili_emoticon.dart:1-300`（两入口：`info[0][13]` 单表情 / `info[0][15].extra.emots`；上限 8；同图去重；裸名规则；url 归一 https） | **无**（上游亦无） | `platforms::bilibili::danmaku::emoticon::parse_bilibili_emoticons` | 需新写（fork 独有 31 契约用例，须逐条迁成 Rust 单测） |

---

## 4. 账号体系（F-17 ~ F-21）

| 编号 | 能力 | Dart（file:line） | DTV（file:line） | 目标 Rust（module::fn） | 复用度 |
|---|---|---|---|---|---|
| F-17 | 注入凭证 `setSiteAttrs` | `bilibili_site.dart:553-558`（JSON 取 `cookie`） | `state.rs:8-105`（仅存 `w_webid`）；`cookie.rs:1-172`（**webview 采集**，桌面专用） | `platforms::bilibili::account::set_site_attrs` | 需改写（DTV 走 webview，核心内不可用；按 Dart 契约 `jsonDecode` 取 `cookie`） |
| F-18 | 生成登录二维码 | `bilibili_site.dart:561-573`（`passport .../qrcode/generate`） | **无** | `platforms::bilibili::account::get_qr_code` | 需新写 |
| F-19 | 轮询扫码状态 | `bilibili_site.dart:576-610`（`qrcode/poll`；码 0/86038/86090 映射；汇总 `set-cookie` 为 JSON credential） | **无** | `platforms::bilibili::account::get_qr_poll_result` | 需新写 |
| F-20 | 获取账号信息 | `bilibili_site.dart:613-635`（`member/web/account`；成功回填 `userId=mid` 副作用） | `auth.rs:118-146`（`init_uid`，仅取 mid 供鉴权，**无回填**） | `platforms::bilibili::account::get_account_info` | 需改写（须实现 `user_id` 回填副作用，供 F-06 弹幕 uid） |
| F-21 | 公共请求头 / buvid 指纹 | `bilibili_site.dart:31-48`（`getHeader`）、`:389-414`（`getBuvid`，`x/frontend/finger/spi`） | `search.rs:93-138`（`ensure_buvid`）、`extractor.rs:142-214`(上游) | `platforms::bilibili::buvid::ensure_buvid` + `http::build_header` | 直接移植 |
| F-22 | wbi 签名链路 | `bilibili_site.dart:416-483`（mixin 表）、`:484-503`（`getWbiKeys`）、`:505-534`（`getWbiSign`）、`:536-550`（`getAccessId`） | `auth.rs:10-84`（表 + `get_mixin_key`/`get_url_encoded`/`encode_wbi`/`_encode_wbi`）、`streamer_info.rs:12-100`（`get_wbi_keys`/`build_wbi_sign`）、`state.rs:8-105`（`access_id`） | `platforms::bilibili::wbi::{get_wbi_keys, get_wbi_sign, get_access_id}` | 直接移植（算法等价；须泛化为「任意参数集」而非 DTV 仅 `room_id`） |
| F-23 | 用户信息模型 | `platforms/bilibili/model/bilibili_user_info.dart:5-56` | （内联 `serde_json::Value`） | `platforms::bilibili::account::BiliUserInfo`（私有） | 需改写 |

---

## 5. 面板/包线（桥层与 App）

| 目标 | 文件 | 说明 | 复用度 |
|---|---|---|---|
| FRB 门面（Site） | `simple_live_app/rust/src/api/slive/site.rs` | `#[frb(opaque)] LiveBilibiliSite`，转调 `slive-core::platforms::bilibili::site::BilibiliSite` | 需新写 |
| FRB 门面（弹幕） | `simple_live_app/rust/src/api/slive/danmaku.rs` | `StreamSink<LiveDanmuItem>` + `LiveDanmuConnection` | 需新写 |
| FRB 模型镜像 | `simple_live_app/rust/src/api/slive/models/*` | `#[frb(mirror(...))]`（见 ADR-007） | 需新写 |
| App 绑定层 | `simple_live_app/lib/src/bridge/rust_bilibili_{site,danmaku}.dart` | `implements LiveSite/LiveDanmaku`；模型/异常映射 | 需新写 |
| App 分派点 | `simple_live_app/lib/app/sites.dart:15` | 改 1 行（`createBilibiliSite()`） | 需改写 |

---

## 6. 覆盖度小结（与 `11-scope-and-acceptance.md §4` 对齐）

- **DTV 可直接移植**：F-04、F-07、F-21、F-22、WS 帧编解码、cookie 解析。
- **DTV 需改写**：F-02（签名口径）、F-06（组装契约）、F-08（须保留 mcdn 后置）、F-09（端点）、F-11（心跳 60s）、F-12/F-13/F-14（补人气/颜色/zlib）、F-17（去 webview）、F-20（回填副作用）。
- **仅 Dart core 有、必须新写**：F-01（分类 A）、F-03（推荐）、F-05（搜索主播）、F-10/F-15（SC）、F-16（表情包）、F-18/F-19（二维码登录）。
- **上游补充参考**（非依赖）：`w_webid`/buvid SPI/`wbi.rs`/`danmaku.rs` 的 zlib 分支；上游**缺** `mcdn` 排序与表情包/账号（见 ADR-009）。

> 每条目标函数的离线用例落点见 `11-scope-and-acceptance.md §3`（AC-01~AC-29）；单文件 ≤300 行拆分见 `10-architecture.md §1.3`。

---

## 7. DTV 无蓝本的 9 项（必须从 Dart core 重实现）

> 依据总监修正 + `11-scope-and-acceptance.md §4`。这 9 项 **DTV 源码内不存在或语义不符**，**禁止**以 DTV 为蓝本；须严格照 Dart core 契约实现，并逐条对应 AC。DTV 的局部强项（`d1--cn` 优先 / HLS 重试 / flv-hls 变体）**只可**用于 §2 中 F-08 的**增强参考**，不得替换 Dart core 的既有语义。

| # | 能力（编号） | Dart core 源 | DTV 状态（证据） | 目标 Rust | 依据 AC |
|---|---|---|---|---|---|
| 1 | 分类 A 列表（F-01） | `bilibili_site.dart:51-80` | **无**（DTV 只有 area→rooms，无分类表） | `platforms::bilibili::categories::get_categories` | AC-01 |
| 2 | 推荐房间（F-03） | `bilibili_site.dart:195-222` | **无** | `platforms::bilibili::rooms::get_recommend_rooms` | AC-03 |
| 3 | 搜索主播（F-05） | `bilibili_site.dart:307-337` | **无**（DTV 只 `search_type=live`） | `platforms::bilibili::search::search_anchors` | AC-05 |
| 4 | SC（HTTP，F-10） | `bilibili_site.dart:352-379` | **无** | `platforms::bilibili::super_chat::get_super_chat_messages` | AC-10 |
| 5 | SC（WS 下行，F-15） | `bilibili_danmaku.dart:209-235` | **无** | `platforms::bilibili::danmaku::parse::parse_super_chat` | AC-15 |
| 6 | 表情包解析（F-16） | `bilibili_emoticon.dart:1-300` | **无**（上游亦无） | `platforms::bilibili::danmaku::emoticon::parse_bilibili_emoticons` | AC-16 |
| 7 | 账号三接口 + `userId` 回填（F-17~F-20） | `bilibili_site.dart:553-635` | **无/不可用**（`state.rs` 仅存 w_webid；`cookie.rs` 走 **webview**，核心层不可用） | `platforms::bilibili::account::{set_site_attrs,get_qr_code,get_qr_poll_result,get_account_info}` | AC-17~AC-20、AC-24 |
| 8 | zlib(ver2) 解压分支（F-13） | `bilibili_danmaku.dart:168-172` | **缺**（`websocket.rs:180-241` 仅 ver0/ver3） | `platforms::bilibili::danmaku::protocol::decode` | AC-13 |
| 9 | mcdn 线路后置排序（F-08） | `bilibili_site.dart:176-183`（`urls.sort`：含 mcdn 排后） | **缺**（DTV 改用 `d1--cn` 优先策略，`stream_url.rs:417-421`） | `platforms::bilibili::play::get_play_urls` | AC-08 |

> 另有 F-02（分类下房间）与 F-06（详情）虽 DTV 有部分实现，但**签名口径/组装契约不同**（DTV 用固定 secret 签名、返回 `LiveStreamInfo`），故在 §2 标为**需改写**，不得直接照搬。F-12/F-14（人气、弹幕颜色）DTV 丢弃或缺失，亦须按 Dart core 补齐。

---

## 8. RISK-10 上游覆盖度核实结果（回填 `11-scope-and-acceptance.md §4` 的「待确认」）

> 已读 `SlotSun/slive-core-api-rust`(`crates/platforms-parser`) HEAD 源码核实。

| 项 | 上游是否有 | 证据 |
|---|---|---|
| `w_webid`(access_id) | **有** | `extractor/platforms/bilibili/extractor.rs:103-133`（`get_access_id`，注释「Fetch and cache the `access_id` (w_webid) from `https://live.bilibili.com/lol`」）；`wbi.rs:318-389` 测试含 `w_webid=test_token` |
| zlib(ver2) 解压 | **有** | `extractor/platforms/bilibili/danmaku.rs:12-13,156-164,230-236`（`decompress_zlib`，`2 => …` 分支） |
| brotli(ver3) 解压 | **有** | 同上 `danmaku.rs:147-154,238-252` |
| buvid3/4 指纹 | **有** | `extractor.rs:134-214`（`ensure_buvid`，走 `x/frontend/finger/spi`） |
| SC（HTTP） | **有** | `extractor.rs:38,972-…`（`SUPER_CHAT_URL` + `get_super_chat_messages`） |
| **mcdn 后置排序** | **无** | 全仓 grep `mcdn` 无命中；`get_recommend_rooms` 用 `recommend_room_list`（`extractor.rs:730-744`），无 mcdn 排序逻辑 |
| **表情包解析** | **无** | 全仓 grep `emoticon` 无命中；`LiveMessage` 无 `emoticons` 字段 |
| **账号三接口（QR/Cookie/账号信息）** | **无** | B站 extractor 无 `qrcode`/`account` 相关（grep 无命中）；`slive_danmaku.dart` 亦无账号能力 |

**结论**：上游覆盖度好于 briefing 旧描述（w_webid/zlib 均有），但**仍缺 mcdn 排序、表情包、账号三接口**——这三项与 §7 的其余项一样，**须从 Dart core 重实现**。（另：上游含 Twitch `extractor.rs`/`danmaku.rs`，即 briefing「Twitch 无覆盖」的描述不准确——见 `10-architecture.md R-01`。）
