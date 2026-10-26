# Rust Core 落地第一步 · 测试与夹具基线（40 条 AC 可机械验证）

> 版本锚点：`dart_simple_live` fork future @ `4dcdb4fe` · worktree 分支 `feat/core-rust` · `2026-10-16`
> 契约依据：`13-spec.md`（顶层契约 + 裁决 J-1~J-10）· `11-scope-and-acceptance.md §3（AC-01~AC-40）§3.5 §5 DoD` · `10-architecture.md §3/§4/§8.4` · `decisions/ADR-011`
> 知识库依据：`references/01-standards/{test-discipline,test-integrity-anti-gaming,verifier-critic-pattern,generated-code-failure-modes,production-readiness-scorecard}.md`
> 配套夹具草案：`docs/rust-core/fixtures-draft/`（本文件 §2/§3 描述其落地形态）
> 角色声明：本文由 **QA（严过关）独立编写**，测试用例从 **Spec / AC / Dart core 解析代码** 反推，**不参考实现者内部设计**（`test-discipline.md §4`「测试作者 ≠ 代码作者」）。

---

## 0. 本基线怎么用（一句话）

- 目标：把 40 条 AC 变成「**夹具输入 → 期望输出**」或「**真实命令输出**」，机器可判定、抗 flaky、实现者改不动。
- 本基线交付：**测试计划（本文）+ 夹具草案（`fixtures-draft/`）**。实现者在 Phase 3 落地时，把草案迁到 `crates/slive-core/tests/` 并补齐真实抓包。
- 与架构分工：架构 §8.4 给「夹具方案」，本文给「**逐 AC 用例映射 + 断言形式 + 缺口清单 + 独立验证步骤**」。

---

## 1. AC → 用例映射表（AC-01 ~ AC-40）

命名约定：用例名 = `ac{编号}_{能力}_{关键断言}`。夹具路径以**落地目标** `crates/slive-core/tests/fixtures/bilibili/` 为准（草案同名文件在 `docs/rust-core/fixtures-draft/`）。
断言形式：`离线夹具` = MockTransport / WS 帧注入；`golden` = 固定输入→固定期望的确定性断言；`脚本` / `git` / `命令` = 非夹具判定，由 QA 独立执行。
「夹具就绪」图例：**[就绪]** = 草案已可直接消费；**[合成]** = 规格+最小合成样本，待真实抓包替换；**[待建]** = 依赖实现产物（代码 / 绑定层 / App），Phase 4 才能判定。

### 1.1 核心成功流（AC-01 ~ AC-21）

| AC | 优先级 | 用例名 | 夹具 | 断言形式 | 夹具就绪 |
|----|--------|--------|------|----------|----------|
| AC-01 | P0 | `ac01_get_categories_and_pic_suffix` | `http/room_v1_Area_getList.json` (+空 data 变体) | 条数 + 每 child `pic` 以 `@100w.png` 结尾；空/缺 data → 空列表 | [合成] |
| AC-02 | P0 | `ac02_category_rooms_has_more_and_cover` | `http/xlive_web-interface_v1_second_getList.json` (+空页变体) | `has_more==1`→true 且 `cover` 以 `@400w.jpg` 结尾；`has_more` 缺省为 0；空 `list`→`items=[]`+`hasMore=false` | [合成] |
| AC-03 | P0 | `ac03_recommend_has_more_from_nonempty_page` | `http/..._second_getListByArea.json` (+空页变体) | `list` 非空→true、空→false；**不读任何服务端分页字段** | [合成] |
| AC-04 | P0 | `ac04_search_rooms_strip_em_prefix_cover` | `http/..._search_type_live.json` (+满 40 条变体) | title 无 `<em>`；`cover` = `https://…@400w.jpg`；`hasMore = items.len()>=40` | [合成] |
| AC-05 | P1 | `ac05_search_anchors_avatar_and_uname` | `http/..._search_type_live_user.json` | `avatar` 补 `https:`+`@400w.jpg`；`uname` 去 `<em>`；`liveStatus` 透传；`hasMore` 判据同 AC-04 | [合成]（`is_live` 类型待核实） |
| AC-06 | P0 | `ac06_room_detail_fields_and_danmaku_args` | `http/getInfoByRoom.json` + `http/getDanmuInfo.json` | `roomId=realRoomId`；`status`；`url=https://live.bilibili.com/{请求roomId}`；`danmaku_data`(JSON) 含 `schema_version/room_id/uid/token/server_host/buvid/cookie` | [合成] |
| AC-07 | P0 | `ac07_play_qualities_map_and_unknown` | `http/getRoomPlayInfo.json` | `g_qn_desc` 映射 `accept_qn`；无描述 qn → `"未知清晰度"`；`data` = qn 十进制字符串 | [合成] |
| AC-08 | P0 | `ac08_play_urls_mcdn_last_and_headers` | `http/getRoomPlayInfo.json`（含 mcdn/非 mcdn 线路） | URL = `host+base_url+extra`；含 `mcdn` 的排**最后**；`headers` 含固定 referer/user-agent | [合成] |
| AC-09 | P0 | `ac09_live_status_bool` | `http/room_v1_Room_get_info.json` (+`live_status=0`/缺 data) | `data.live_status==1` → true；缺 data → false | [合成] |
| AC-10 | P1 | `ac10_super_chat_time_ms_and_face` | `http/av_v1_SuperChat_getMessageList.json` | 秒→毫秒（`*1000`）；`face` 以 `@200w.jpg` 结尾；`data.list` null → 空列表 | [合成] |
| AC-11 | P0 | `ac11_join_packet_byte_golden` | `golden/golden-join-packet.json` | `encode_packet(json, 7)` **逐字节** == golden（len/hdrlen=16/protover=0/op=7/seq=1 + body） | **[就绪]**（推导型 golden） |
| AC-12 | P0 | `ac12_op3_online_frame` | `ws/frame-op3-online.bin` | `type=online`、`data==Online(12345)`、`color=white`（big-endian int32） | **[就绪]**（合成帧） |
| AC-13 | P0 | `ac13_op5_multi_protocol_decode` | `ws/frame-op5-ver0-chat.bin`、`frame-op5-ver2-zlib.bin`（ver3 待生成） | 三协议分别 JSON/zlib/brotli 解压 + `[\x00-\x1f]+` 切分；断言产出**条数** | [就绪/合成]（ver3 待补） |
| AC-14 | P0 | `ac14_danmu_msg_chat_color_emoticons` | `ws/frame-op5-ver0-chat.bin` + `emoticon/emoticon-cases.json` | `type=chat`；`color=numberToColor(info[0][3])`（0→白）；挂载表情解析结果 | [就绪] |
| AC-15 | P0 | `ac15_super_chat_ws_and_null_silent` | `ws/frame-op5-ver0-superchat.bin` (+`data=null` 变体) | `type=superChat`、`data==SuperChat(...)`；`data=null` → 静默返回（无产出、不抛） | [就绪] |
| AC-16 | P0 | `ac16_emoticons_contract` | `emoticon/emoticon-cases.json`（37 条断言组） | 逐条镜像 Dart 31 契约：去重/上限 8（入口截断）/url 升 https/异常→None | **[就绪]** |
| AC-17 | P0 | `ac17_set_site_attrs_three_cases` | 无外部夹具（入参构造） | ①`{"cookie":X}`→站点 cookie==X（**非**整串 JSON）；②非法 JSON→`CoreError::InvalidInput`；③缺 `cookie` 键→保留旧值 | **[就绪]**（无需网络） |
| AC-18 | P1 | `ac18_qr_generate` | `http/passport_qrcode_generate.json` (+`code!=0`) | `key/url` 返回；`code!=0` → 抛错（不返回空码） | [合成] |
| AC-19 | P0 | `ac19_qr_poll_status_map` | `http/passport_qrcode_poll.json`（4 类 code + `set-cookie` 头） | 0→`scanned`+credential(JSON `{"cookie":…}`)；86038→`expired`；86090→`scanned`；其余→`unscanned` | [合成] |
| AC-20 | P0 | `ac20_account_info_and_uid_backfill` | `http/x_member_web_account.json` | `isValid=true` 且 **站点 `userId` 被回填 == mid**（副作用）；`code!=0`/`mid=null` → `isValid=false` **不抛** | [合成] |
| AC-21 | P0 | `ac21_header_buvid_and_wbi_golden` | `http/x_frontend_finger_spi.json` + `http/x_web-interface_nav.json` + `http/live.bilibili.com_lol.json` + `golden/golden-wbi.json` | 无 cookie→注入 `buvid3/buvid4`；有 cookie 缺 buvid3→追加；固定 `img_key/sub_key/wts` → 固定 `w_rid` | **[就绪/合成]** |

### 1.2 错误 / 边界（AC-22 ~ AC-29）

| AC | 优先级 | 用例名 | 夹具 | 断言形式 | 夹具就绪 |
|----|--------|--------|------|----------|----------|
| AC-22 | P0 | `ac22_not_live_returns_detail_and_host_fallback` | `http/getInfoByRoom.json` 未开播变体 | `status=false` 不抛；仍返回可用弹幕参数；`host_list` 空→`broadcastlv.chat.bilibili.com` | [合成] |
| AC-23 | P0 | `ac23_room_not_found_typed_error` | `http/getInfoByRoom.json`（`data=null` / `code!=0`） | 抛 `CoreError`；**不 panic / 不空指针** | [合成] |
| AC-24 | P0 | `ac24_account_invalid_no_throw` | `http/x_member_web_account.json` `code!=0` 变体 | `isValid=false` 空 `AccountInfo`；**不抛** | [合成] |
| AC-25 | P0 | `ac25_risk_control_error_no_retry` | `http/*.json`（`code=-352`） | 抛带服务端 message 的 `CoreError`；**不静默返回空**；**请求次数 == 1**（无重试） | [合成]（+计数型 Mock） |
| AC-26 | P0 | `ac26_http_error_map_and_ws_reconnect` | MockTransport 错误注入 + WS 帧序列 mock | HTTP 失败→`CoreError`；WS 断线 **5s×5** 后触发 `onClose`；收到消息后重连计数归零（**不依赖墙钟**） | [待建]（需时钟注入） |
| AC-27 | P0 | `ac27_empty_page_returns_empty_no_throw` | F-01~F-05 空页参数化夹具 | `items=[]` 且 `hasMore=false`；**不抛** | [合成] |
| AC-28 | P0 | `ac28_dirty_frame_logs_only` | `ws/frame-op5-dirty-length.bin`（+长度不足/解压失败/非法 JSON） | 只记日志、**不断连**、**不调回调**；连接状态未变 | [就绪/合成] |
| AC-29 | P1 | `ac29_unknown_quality_no_throw` | `http/getRoomPlayInfo.json`（`accept_qn` 空 / qn 无描述） | 空列表 **或** `"未知清晰度"`；**不抛** | [合成] |

### 1.3 回归约束（AC-30 ~ AC-34）

| AC | 优先级 | 判定名 | 判定方式 | 就绪 |
|----|--------|--------|----------|------|
| AC-30 | P0 | 其余 4 平台零新增失败 | `flutter test`（`simple_live_core` + App）失败名单与迁移前**逐条比对**；`git diff` 确认 4 平台源码未动 | [待建]（需实现+基线） |
| AC-31 | P0 | 开关切 Dart 仍可用 | 开关切换路径走查 + 冒烟；关闭 Rust 路径不影响构建（`kUseRustBilibili=false`） | [待建] |
| AC-32 | P0 | UI 零变化 | `git diff --stat` 仅含 `slive-core` Rust 侧 + `simple_live_core` + 绑定层 + `sites.dart` 1 行；**无 UI 文件改动** | [待建] |
| AC-33 | P0 | 门禁（行数/依赖/emoji/占位） | 脚本：①`≤300 行/文件`；②`cargo tree` 依赖只向下；③emoji 正则扫描；④`todo!()/unimplemented!()/Lorem` 扫描 | [待建]（脚本见 §5） |
| AC-34 | P1 | Dart B站三文件保留 | `git` 审查：`bilibili_{site,danmaku,emoticon}.dart` 未删（窗口未结束，J-9） | [待建] |

### 1.4 反作弊与绑定层（AC-35 ~ AC-40）

| AC | 优先级 | 落地方式 | 判定方式 | 就绪 |
|----|--------|----------|----------|------|
| AC-35 | P0 | 确定性 golden 把关核心验收 | join 包逐字节 / wbi 固定 `w_rid` / 脏帧解码结果，**固定输入→固定期望**，不由被测代码自证 | **[就绪]**（golden 已产出） |
| AC-36 | P0 | held-out 留出集 | `tests/fixtures/bilibili/heldout/` 实现者不可见；`cargo test --features heldout` 单独判定 | [待建]（策略见 §3） |
| AC-37 | P0 | 实现 diff / 测试 diff 分离 | 两次独立 `git diff`（`-- src` vs `-- tests` `fixtures` `*.toml`）分别评审；见 §4.3 | **[就绪]**（流程，§4.3 给命令） |
| AC-38 | P0 | 真实命令输出落盘 | `cargo test/clippy` + FRB codegen + `flutter test` 输出落 `docs/rust-core/evidence-*.log` | [待建] |
| AC-39 | P0 | 绑定层零协议逻辑 + 结构约束 | ①`cargo tree -p <bridge>` **不得**含 `reqwest`/`tokio-tungstenite`/`md-5`/`wbi`；②绑定层文件 grep 无 `http`/`wss`/`md5`/`wbi`/`jsonDecode`/`Url(`/`Retry`；③人工审查仅类型翻译 | [待建]（§4.4 给判定式） |
| AC-40 | P0 | 凭证/日志不泄露明文 | 注入/校验后捕获日志（含 debug），断言**不含** `SESSDATA`/`cookie=` 明文子串 | [待建] |

---

## 2. 可见夹具清单（与架构 §8.4 对齐）

三类夹具，统一目标路径 `crates/slive-core/tests/fixtures/bilibili/`。草案已产出在 `docs/rust-core/fixtures-draft/`（见 `FIXTURE_INDEX.md`）。

### 2.1 类别一：HTTP 响应 `.json`（F-01~F-10、F-17~F-21）

| 夹具（草案） | 服务 AC | 来源 | 形态 |
|--------------|---------|------|------|
| `http/room_v1_Area_getList.json` | AC-01, AC-27 | 合成 | `data[]` 分类树，子类 `pic` 相对路径 |
| `http/xlive_web-interface_v1_second_getList.json` | AC-02, AC-27 | 合成 | `has_more` + `list`（含 `@400w` cover） |
| `http/xlive_web-interface_v1_second_getListByArea.json` | AC-03, AC-27 | 合成 | `list` 空/非空两态 |
| `http/..._search_type_live.json` | AC-04, AC-27 | 合成 | `<em>` title + `//` cover |
| `http/..._search_type_live_user.json` | AC-05, AC-27 | 合成 | `<em>` uname + `uface` |
| `http/getInfoByRoom.json` + `http/getDanmuInfo.json` | AC-06, AC-22, AC-23 | 合成 | 两步响应 + 未开播/不存在变体 |
| `http/getRoomPlayInfo.json` | AC-07, AC-08, AC-29 | 合成 | `g_qn_desc`+`accept_qn`+`url_info`（含 `mcdn`） |
| `http/room_v1_Room_get_info.json` | AC-09 | 合成 | `data.live_status` |
| `http/av_v1_SuperChat_getMessageList.json` | AC-10, AC-27 | 合成 | `list[]` 含秒时间戳 |
| `http/passport_qrcode_generate.json` | AC-18 | 合成 | `qrcode_key`/`url` |
| `http/passport_qrcode_poll.json` | AC-19 | 合成 | 4 类 `code` + `set-cookie` 头 |
| `http/x_member_web_account.json` | AC-20, AC-24 | 合成 | `mid/uname/userid/face` |
| `http/x_frontend_finger_spi.json` | AC-21 | 合成 | `b_3`/`b_4` |
| `http/x_web-interface_nav.json` | AC-21 | 合成 | `wbi_img.img_url/sub_url` |
| `http/live.bilibili.com_lol.json`(text) | AC-21 | 合成 | HTML 含 `"access_id":"…"` |
| `http/*_code-352.json` | AC-25 | 合成 | 风控错误码 + message |

> ⚠️ **全部标记 `synthetic: true`**：只含 Dart 解析代码真正读取的字段（字段→行号见 `http/http-samples.json` 的 `field_sources`）。**真实响应形态（嵌套层级 / 额外字段 / 类型 / `is_live` 等）必须联网抓包替换后方可定稿**——禁止把合成样本当真实抓包（见 §6 纪律）。

### 2.2 类别二：WS 帧 `.bin`（F-11~F-16）

| 夹具（草案） | 服务 AC | 形态 | 期望产出 |
|--------------|---------|------|----------|
| `ws/frame-op3-online.bin` | AC-12 | 16B 头 + int32 人气 | `online`，人气 12345 |
| `ws/frame-op5-ver0-chat.bin` | AC-13, AC-14 | 头(protover=0) + DANMU_MSG JSON | `chat`（含颜色/表情） |
| `ws/frame-op5-ver2-zlib.bin` | AC-13 | 头(protover=2) + zlib(JSON) | 解压后 `chat` |
| `ws/frame-op5-ver0-superchat.bin` | AC-15 | 头 + SUPER_CHAT_MESSAGE JSON | `superChat` |
| `ws/frame-op5-dirty-length.bin` | AC-28 | 声明长度与真实字节不符 | 无产出、不抛 |

> 帧头格式来自 `bilibili_danmaku.dart:119-145,147-184,241-261`（**已被 Dart 源码验证**）；ver3(brotli) 帧待实现期用 `brotli` crate 生成或抓包补入。负载内容为合成，标 `synthetic: true`。

### 2.3 类别三：确定性 golden（F-22 wbi / join 包 / 脏帧结果）

| 夹具（草案） | 服务 AC | 形态 | 来源 |
|--------------|---------|------|------|
| `golden/golden-join-packet.json` | AC-11 | 固定 args → 固定 join/心跳字节（hex + 字节数组） | 由 `encodeData` 逻辑推导 |
| `golden/golden-wbi.json` | AC-21 | 固定 `img_key/sub_key/wts` → 固定 `mixin_key`/`w_rid` | 由 `getMixinKey`/`getWbiSign` 逻辑推导 |
| 内联常量断言（不落盘） | AC-11, AC-21, AC-28 | Rust `assert_eq!` | 同源 |

> golden **不落被测代码的产出**，而是由**已验证的 Dart 算法**独立推导 → 满足 AC-35「实现者改不动、不自证」。

### 2.4 夹具→AC 覆盖矩阵（汇总）

| AC 组 | 夹具类别 | 覆盖 |
|-------|----------|------|
| AC-01~AC-10 | HTTP `.json` | 15 端点（含变体） |
| AC-11~AC-16 | WS `.bin` + golden + emoticon | 5 帧 + 2 golden + 37 表情断言组 |
| AC-17~AC-21 | HTTP + golden | 账号/二维码/wbi |
| AC-22~AC-29 | HTTP/WS 变体 + 计数型 Mock | 错误/边界 |
| AC-35~AC-38 | golden + held-out + diff 流程 | 反作弊 |

---

## 3. held-out 留出集策略（AC-36）

### 3.1 目录与构建开关

- 目录：`crates/slive-core/tests/fixtures/bilibili/heldout/`（数据）+ `crates/slive-core/tests/heldout.rs`（用例）。
- 开关：`crates/slive-core/Cargo.toml` 声明 `[features] heldout = []`；heldout 用例全部 `#[cfg(feature = "heldout")]`。
- 判定命令（独立于默认测试）：`cargo test -p slive-core --features heldout`；**held-out 失败即本轮不通过**（不因实现者看不到而豁免）。

### 3.2 内容类型（每条能力 ≥1 条、结构**不同于**可见集）

| 能力 | held-out 内容 | 与可见集的差异点 |
|------|---------------|------------------|
| F-01~F-05 | 真实抓包的分类/房间/搜索响应（不同房间、不同 null 组合） | 字段顺序 / 额外字段 / `<em>` 嵌套更深 |
| F-06 | 两个不同房间的 `getInfoByRoom`（一个未开播、一个在播） | `host_list` 数量 / `token` 长度不同 |
| F-07/F-08 | 另一房间的 `getRoomPlayInfo`（更多 qn、换线路） | `accept_qn` 集合不同 / mcdn 线路位置不同 |
| F-10~F-15 | 真实弹幕帧集（另一房间 30s / 含 ver3 brotli 帧） | 协议版本组合 / 混排表情数量不同 |
| F-16 | 另一房间的真实表情载荷（不同 `emoticon_unique` 前缀：`official_`/`upower_`） | 前缀分类不同 → 区分「只认 `room_0_1`」的特判 |
| F-17~F-21 | 另一份真实 `nav`/`account`/`poll` 响应 | `img_key/sub_key` 不同 → 区分「硬编码 w_rid」 |

### 3.3 实现者不可见的保障（关键）

1. **物理隔离**：heldout 用例与数据**由 QA 提交**，不进实现者的开发分支视图；实现阶段只在**可见夹具**目录下开发。
2. **构建隔离**：默认 `cargo test`/`cargo build` **不编译** heldout（feature 关闭）；实现者无法通过运行发现其内容。
3. **判定隔离**：heldout 只由 QA 在 Phase 4 用 `--features heldout` 运行；结果单独留证。
4. **反特判原理**：held-out 结构（不同房间 / 不同 `emoticon_unique` 前缀 / 不同 `img_key`）专门击穿「对可见样本特判 / 硬编码」的实现——特判式实现在这里必崩。

### 3.4 与实现者的交接流程

```text
QA 产出 heldout/（真实录制 + 用例）  ──┐
                                     │ 仅 QA 持有；不进实现者可见范围
实现者：按 fixtures-draft/ 的可见夹具开发，跑 `cargo test`（heldout 不编译）
                                     │
Phase 4：QA 运行 `cargo test --features heldout` → 单独判定 → 结果留证 + 回传总监
```

**本次（Phase 2）限制**：held-out 需**真实抓包**，当前无网络抓包（见 §6 G-1）。故本轮 held-out 目录**先落策略与占位**（`fixtures-draft/heldout/README.md`），真实数据待有网环境补齐；**不得**用合成数据冒充 held-out（否则失去反特判效力）。

---

## 4. 反作弊检查表（AC-35 ~ AC-38 落地）

> 依据 `test-integrity-anti-gaming.md`：判定原则 = **「通过」是靠改松验证还是改对代码**。本节把 4 条 AC 落成可执行判定。

### 4.1 AC-35 —— 确定性 golden（实现者改不动）

| golden | 输入 | 期望 | 为什么实现者改不动 |
|--------|------|------|--------------------|
| join 包 | 固定 `room_id/uid/token/buvid` | 固定字节（`golden-join-packet.json`） | 期望由 Dart `encodeData` 独立推导，非 Rust 产出 |
| wbi | 固定 `img_key/sub_key/wts` | 固定 `w_rid`（`golden-wbi.json`） | 期望由 Dart `getWbiSign` 独立推导 |
| 脏帧 | 固定损坏字节 | 无产出 + 不抛 | 期望来自 Spec 行为，非实现返回值 |

**落地规则**：golden 断言**禁止**写成「运行实现 → 把结果写回期望文件」。期望值**必须**来自 `fixtures-draft/` 的独立推导文件。

### 4.2 AC-25「不重试」——用**请求次数 == 1** 断言

- MockTransport 记录**每次请求**（URL + 参数 + 时间序）。
- 注入 `code=-352` 响应后：
  ```rust
  let err = site.get_categories().await.unwrap_err();
  assert!(matches!(err, CoreError::Api { code: -352, .. }));
  assert_eq!(mock.request_count("/room/v1/Area/getList"), 1, "风控错误不得自动重试");
  ```
- 同理：AC-25 的「不静默空列表」→ 断言返回 `Err` 而非 `Ok([])`。
- **反向用途**：此计数亦用于 NFR「请求数 ≤ Dart core 同路径」（断言请求 URL/参数**集合**一致，不依赖墙钟）。

### 4.3 AC-37 —— 实现 diff 与测试 diff **分离呈现**

```bash
# 实现 diff（评审 A：功能逻辑）
git diff -- 'simple_live_core/**/src/**' 'simple_live_app/lib/src/bridge/**'

# 测试/门禁 diff（评审 B：完整性差异）——单独看，逐项盘问
git diff -- '**/tests/**' '**/*.toml' 'Cargo.lock' '**/jest.config.*' '**/pytest.ini'
```

**必须逐项盘问的信号**（`test-integrity-anti-gaming.md §3`）：断言被删/放宽、新增 `skip`/`ignore`/`#[ignore]`/`.only`、改 golden/期望文件、调阈值、加 lint 豁免。任一项无理由 → 视为可疑，阻断。

### 4.4 AC-39 —— 绑定层边界（结构可判定）

```bash
# ① 结构约束：桥 crate 不得依赖协议相关 crate（编译期硬约束，J-7）
cargo tree -p rust_lib_simple_live_app | grep -E 'reqwest|tokio-tungstenite|md-5|brotli|flate2' && echo "FAIL: 桥含协议依赖" || echo "OK"

# ② 符号扫描：绑定层文件不得出现协议逻辑符号
grep -nE 'https?://|wss://|md5|wbi|jsonDecode|Uri\.parse|Url\(|Retry|reconnect' \
  simple_live_app/lib/src/bridge/rust_bilibili_*.dart && echo "FAIL: 绑定层含协议逻辑" || echo "OK"
```

### 4.5 AC-38 —— 真实命令输出落盘

```bash
cargo test -p slive-core -- --nocapture   > docs/rust-core/evidence-cargo-test.log 2>&1; echo "rc=$?"
cargo clippy -p slive-core -- -D warnings  > docs/rust-core/evidence-clippy.log    2>&1; echo "rc=$?"
flutter_rust_bridge_codegen --version     > docs/rust-core/evidence-frb-version.log 2>&1
cd ../simple_live_app && flutter analyze && flutter test > ../../docs/rust-core/evidence-app-test.log 2>&1
```

---

## 5. QA 独立验证步骤（不采信实现者自证）

> 依据 `verifier-critic-pattern.md`：检查者在**新上下文**、只看 **diff + 验收标准 + 契约** 做独立判定，输出 `pass/fail + blocking + advisory + evidence`。

### 5.1 必须由 QA 独立执行（不采信实现者）

| # | 验证 | 方法 | 对应 AC |
|---|------|------|---------|
| V1 | 跑全部离线用例（可见 + heldout） | `cargo test -p slive-core` + `--features heldout` | AC-01~AC-29、AC-36 |
| V2 | 逐字节 golden 复核 | 独立比对 `golden-*.json`，**不接受**实现自报 | AC-11、AC-21、AC-35 |
| V3 | 请求次数 == 1（无重试） | 独立读 Mock 计数 | AC-25 |
| V4 | **反作弊 5 类检测**（见 §5.2） | 脚本 + diff 审查 | AC-37、AC-35~AC-38 |
| V5 | 门禁脚本 | 行数 / 依赖方向 / emoji / 占位扫描 | AC-33 |
| V6 | 绑定层结构约束 + 符号扫描 | §4.4 两条命令 | AC-39 |
| V7 | 凭证日志明文断言 | 捕获日志查 `SESSDATA` | AC-40 |
| V8 | App 侧回归失败名单逐条比对 | 与迁移前基线对表 | AC-30 |
| V9 | UI diff 审查 | `git diff --stat` | AC-32 |
| V10 | emoji 图标 / 紫粉渐变 / 占位文案扫描 | 正则 | 团队级 P0 |

### 5.2 测试完整性反作弊门（P0 门禁，5 类检测）

对比**开发前后**测试 surface，命中**任一**即阻断（`test-integrity-anti-gaming.md`）：

```bash
# ① 测试文件删除
git diff --name-status <base>..HEAD -- '**/tests/**' | grep '^D'

# ② 断言数下降
git show <base>:crates/slive-core/tests 2>/dev/null | grep -rc 'assert' > /tmp/a_before.txt
grep -rc 'assert' crates/slive-core/tests > /tmp/a_after.txt; diff /tmp/a_before.txt /tmp/a_after.txt | grep '<'

# ③ 新增 skip/ignore/xfail/.only
git diff <base>..HEAD -- '**/tests/**' | grep '^+' | grep -Ei 'ignore|skip|xfail|\.only|#\[cfg\(not'

# ④ 硬编码断言（人工审查）：断言值是否来自实现返回值而非 Spec/夹具定义
# ⑤ 框架配置篡改
git diff <base>..HEAD -- '**/Cargo.toml' 'Cargo.lock' | grep -E '^\+.*(threshold|skip|ignore|exclude)'
```

**DoD-2 硬口径**：`cargo test` 输出中 `skip/ignore/xfail = 0`（含 `#[ignore]`）；本项目**禁止**以 `#[ignore]` 处理任何 B站用例（§6 纪律）。

### 5.3 验证者输入边界（只看这些，不看实现者叙事）

- ✅ 本次 diff（实现 diff / 测试 diff 分开）、AC-01~AC-40、契约（`13-spec.md`）、夹具与 golden、`cargo test` 真实输出。
- ❌ 实现者的「我觉得没问题」、探索弯路、临时废稿、「先这样」的免检理由。

**过度设计护栏**：只标三类阻断——①正确性缺陷 ②AC 未满足 ③契约/安全/数据完整性被破坏。风格偏好、镀金需求 → 归 `advisory`，不阻断。

---

## 6. 当前不可验证项缺口清单（Phase 2 时点）

> 纪律：受限就**如实报告**并给替代路径，**不静默降级**、**不伪造**。

| ID | 缺口 | 影响 AC | 缺什么 | 替代路径 / 解除条件 |
|----|------|---------|--------|---------------------|
| G-1 | **无真实抓包** | AC-01~AC-10、AC-18~AC-21、AC-27、AC-29、AC-36 | 真实 B站 HTTP 响应（各端点） | ①实现期用 `#[ignore]` 一次性录制脚本 `tests/record_http.rs`（有网时手跑）；②**合成最小样本已产出**（字段对齐 Dart 解析代码），可先驱动实现；③真实抓包替换后**再跑一遍**校验合成样本 |
| G-2 | **ver3(brotli) 帧缺失** | AC-13 | brotli 压缩的真实/合成帧 | 实现期用 `slive-core` 的 `brotli` crate 生成 frame（与解码对称）；或抓包补齐 |
| G-3 | **WS 重连时序未可测** | AC-26 | 时钟/定时器注入接口（避免真等 25s、避免 flaky） | 要求 `ws::session` 的时间源抽象为可注入（`tokio::time::pause` 或 trait `Clock`）；**不得**用真实 sleep 断言 |
| G-4 | **账号 `is_live` 类型待核实** | AC-05 | `search_type=live_user` 真实 `is_live` 类型（bool/int） | 抓包核实；Dart `live_anchor_item.dart:14/20` 直接赋 `bool`，若服务端为 int 则 Dart 现状即抛错（**潜在既有缺陷**），实现者须以抓包为准 |
| G-5 | **danmaku_data 的 `schema_version`** | AC-06、AC-11 | Rust 侧新增字段（Dart 无，`bilibili_danmaku.dart:29-39`） | 已由架构 §3.3(b) 钉死为 `1`；断言 golden 覆盖 |
| G-6 | **绑定层/门禁/回退未可测** | AC-30~AC-34、AC-39、AC-40 | 实现产物（Rust 源码 / 绑定层 / `sites.dart` 改动） | Phase 4 判定；判定式已在 §1.3/§1.4/§4 给出 |
| G-7 | **App 侧回归基线未取** | AC-30、DoD-4 | 迁移**前** `flutter test` 失败名单快照 | **实现者动 App 之前**必须先由 QA 取基线（含 huya 联网 3 失败等既有口径，见 `test-suite.md §2`） |
| G-8 | **emoji/渐变/占位扫描目标** | 团队级 P0、AC-33 | 待扫描的前端产物 | 本轮无新增 UI（AC-32）；Rust 侧扫描目标为新增文件，Phase 4 执行 |
| G-9 | **fvm 3.47.6 未安装** | DoD-1、AC-30 | `.fvmrc` 钉 3.47.6，本机可能仅 3.47.5 | 实现期 `fvm install 3.47.6`；属构建前置（架构 R-02 已知） |

### 6.1 夹具就绪度（汇总）

| 就绪度 | 范围 |
|--------|------|
| **[就绪]** 可直接消费 | AC-16（37 表情断言组）、AC-11/AC-21（确定性 golden）、AC-12~AC-15/AC-28（WS 帧，除 ver3）、AC-17（无需夹具） |
| **[合成]** 规格+最小样本，待真实抓包替换 | AC-01~AC-10、AC-18~AC-20、AC-22~AC-25、AC-27、AC-29 的 HTTP 样本 |
| **[待建]** 依赖实现/环境 | AC-26（时钟注入）、AC-30~AC-34（实现产物）、AC-36（真实 held-out）、AC-38~AC-40 |

---

## 7. 纪律声明（违反 = 退回）

1. **不伪造**：凡未经核实的响应结构，一律标 `synthetic: true` + `verify_note`；字段必须能对上 Dart 解析代码行号，否则标「待核实」。
2. **不弱化断言换绿**：禁 `#[ignore]`/`skip`/放宽阈值/删断言（AC-37 门禁）；实测 **`skip/ignore/xfail = 0`**（DoD-2）。
3. **不自证**：核心验收由**独立推导的 golden** 把关（AC-35），测试作者 ≠ 代码作者。
4. **不静默降级**：网络/环境受限如实上报（§6），给替代路径。
5. **emoji 不作功能图标 / 无紫粉渐变 / 无空洞占位**（团队级 P0，Phase 4 扫描）。
6. **回归率非零不算完成**：AC-30 失败名单必须与迁移前**逐条一致**（零新增失败）。

---

## 7A. 多平台扩展（IP-3~IP-6：斗鱼 / 虎牙 / Twitch / 抖音）

> 本节由 QA 于 IP-3~IP-6 启动后追加。前六节是 **B站** 的测试基线；本节说明四平台的夹具基线与运行口径差异。
> 完整夹具索引、字段速查、待抓包清单、held-out 策略见 **`18-fixtures-multiplatform.md`**。

### 7A.1 夹具与用例位置

| 平台 | 夹具 | 测试骨架 | 关联任务 |
|------|------|---------|---------|
| 斗鱼 | `crates/slive-core/tests/fixtures/douyu/{http,ws,golden}/` | `tests/ac_douyu_fixtures.rs` | IP-3 |
| 虎牙 | `.../huya/{http,ws,golden}/` | `tests/ac_huya_fixtures.rs` | IP-4 |
| Twitch | `.../twitch/{http,ws,golden}/` | `tests/ac_twitch_fixtures.rs` | IP-5 |
| 抖音 | `.../douyin/{http,ws,golden}/` | `tests/ac_douyin_fixtures.rs` | IP-6 |

分层与命名沿用 B站范式（`http/*.json` + `ws/*.bin`&`.expected.json` + `golden/*.json`），`_meta` 额外要求 `derivation` / `target_rust_fn` / `needs_realtime_validation`。

### 7A.2 运行口径（与 B站的关键差异）

| 维度 | B站 | 四平台 |
|------|------|--------|
| **离线用例是否 `#[ignore]`** | **禁止**（DoD-2 硬口径 `skip/ignore/xfail = 0`） | **允许且当前必需**：实现由IP-x并行填充，`ac_<平台>_fixtures.rs` 中「平台行为」用例一律 `#[ignore]`，标注解除条件；**夹具契约类用例不 ignore**（立即运行） |
| **用例是否依赖平台 API** | 依赖（`BilibiliSite::with_deps`） | **不依赖**：四平台骨架只读夹具 + 字节布局 + `MockTransport`，避免与 IP-x 的实现改动互相阻塞编译 |
| **golden 是否需抓包** | 部分（wbi 为推导型，join 包为推导型） | **全部为推导型**（`needs_realtime_validation: false`）：斗鱼 sign、虎牙 anticode、Twitch 阈值表、抖音 sigParam |
| **held-out** | 策略已定（§3），数据待抓包 | 同策略，**且`heldout` feature 尚未在 `Cargo.toml` 声明**（见 `18-...md §6.1` G-M3） |

> ⚠️ **DoD-2 的适用范围**：B站要求 `ignore = 0`；四平台在实现接入前必然存在 `#[ignore]` 骨架。Phase 4 验收时，四平台的判定口径为「**接入完成后 ignore 归零**」，而非沿用B站的全量 `ignore = 0`。此差异须经总监确认（登记于 `18-...md §9`）。

### 7A.3 「不支持」能力的迁移纪律（新增）

Twitch 与抖音在 Dart core 中有相当一部分能力**本就未实现**（`throw UnimplementedError` / 返回空列表 / 直接返回 `[]`）。

**迁移必须保持同样的"不支持"**：不得在Rust 侧「顺手实现」——那会改变 App 行为，直接违反 AC-30「回归为零」。

各平台的完整清单见 `18-fixtures-multiplatform.md §3.3`（Twitch）与该文件 §3.4（抖音），并已写入各平台 `http-samples.json` 的 `_meta.unsupported_by_dart`，由 `ac_<平台>_fixtures.rs::unsupported_capabilities_are_documented*` 守护。

### 7A.4 「既有 quirks」照搬纪律（新增）

四平台 Dart 实现中存在若干**看起来像bug、实为既有行为**的 quirks（如斗鱼推荐流 `pgcnt` 恒 0、抖音清晰度索引错位、Twitch 的 `title` 回落成字符串 `"null"`）。

**迁移一律照搬，不做"顺手修正"**。完整清单（Q1~Q12）与 Dart 行号见 `18-fixtures-multiplatform.md §4`；每条都有对应夹具锁定。这是 AC-30 的直接要求：行为零变化 > 代码看起来更合理。

### 7A.5 对 App 回归基线的影响

**零影响**。本扩展只新增 `crates/slive-core/tests/` 与 `docs/rust-core/` 下的文件，未触碰 `simple_live_app/`、`simple_live_core/lib/`、任何 `src/platforms/**` 实现文件，也未新增任何 Flutter 侧测试。

App 侧基线仍为 **564 执行 / 549 通过 / 15 存量失败**（`16-app-regression-baseline.md`）；Core 侧 Dart 测试不变。Rust 测试与 Dart 测试相互独立运行：`cargo test -p slive-core` 不涉及 Flutter；`flutter test` 仍须按 `13-spec.md §9` 做代理隔离。

---

## 8. 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-16 | 初始版本（Phase 2：测试与夹具基线） | 基于 `13-spec.md` + AC-01~AC-40 建立逐 AC 用例映射、三类夹具草案、held-out 策略、反作弊门、独立验证步骤与缺口清单 |
| 2026-10-16 | 追加 §7A「多平台扩展」：四平台夹具位置、运行口径差异、`#[ignore]` 适用范围、「不支持」能力与既有 quirks 两条新纪律、对 App 基线零影响的回归护栏 | `13-spec.md §13` 启动 IP-3~IP-6 平台迁移，需要在 B站基线之上补充多平台口径；详表见 `18-fixtures-multiplatform.md` |
