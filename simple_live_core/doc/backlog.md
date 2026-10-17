# simple_live_core 待办与优化清单（backlog）

> 版本锚点：`simple_live_core` v1.1.0 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)

## 0. 使用说明

- 每条含：**现象 → 证据（file:line / commit）→ 建议动作 → 影响面**。
- 优先级：`P0` 用户可见的正确性风险；`P1` 平台侧随时可能爆的脆弱点；`P2` 结构/技术债/功能缺口。
- 「证据」行号基于锚点提交；若与当前代码不符，先 `git log -L` 核对再动手。
- 第 5 节记录**已决策不修**的取舍，避免反复讨论。

## 1. P0 — 正确性风险

### P0-1 抖音播放地址没有刷新路径

- 现象：`DouyinSite.getPlayUrls` 不发请求，直接回传 `getPlayQualities` 阶段组装好的地址（`douyin_site.dart:1109` 附近）。抖音地址由详情阶段的 `stream_url` 决定，长时间挂机/断流重连后没有重新取流入口。
- 证据：`douyin_site.dart` `getPlayUrls` 方法体（对比 bilibili/douyu/huya 均实时请求）。
- 建议：为抖音补一个「地址过期重取」路径（重跑 `reflow/info` 或 web/enter），或在 App 层断流重试时强制重查详情。
- 影响：直播间长时播放、网络切换后的恢复能力。

### P0-2 B 站 wbi 密钥永久缓存

- 现象：`BiliBiliSite.kImgKey/kSubKey` 是静态字段，一旦取到就**永不失效**（`bilibili_site.dart:439-440`、`getWbiKeys` :507-526）。服务端轮换 `img_key/sub_key` 后，所有 wbi 签名接口（分区、推荐、详情、弹幕信息）会持续失败直到 App 重启。
- 建议：签名失败（HTTP 4xx/业务错误码）时清缓存并重试一次；或给 key 加 TTL。
- 影响：B 站全部列表/详情链路。

### P0-3 mcdn 排序比较函数不满足排序契约

- 现象：`urls.sort` 的比较器只返回 `1/-1`，两个都含 `mcdn` 时 `cmp(a,b)==cmp(b,a)==1`，违反反对称性；Dart 的排序在非法比较器下结果未定义（可能顺序错乱，mcdn 线路未必真的后置）。
- 证据：`bilibili_site.dart:191-198`。
- 建议：改成 `_Rank(a).compareTo(_Rank(b))` 形式（含 `return 0` 分支），或先过滤分组再拼接。
- 影响：B 站取流成功率（mcdn 线路不稳定性是历史问题）。

## 2. P1 — 平台脆弱点（反爬/协议随时变）

### P1-1 虎牙弹幕 WS 使用临时 cookie/guid

- 现象：上游注释自认「reg temp」（`huya_danmaku.dart:46-47`；`e665a7b7` :223-224 记录「websocket maybe need cookie check, reg temp instead」）。
- 建议：接入匿名登录（`HuyaSite.getAnonymousUid` 已存在）替换硬编码 cookie/guid。
- 影响：虎牙弹幕整体可用性。

### P1-2 抖音 abogus 是风控对抗，参数随时可能失效

- 现象：固定 `aid=6383`、UA 指纹、路径白名单、双 base64 字母表（`abogus.dart:496-521`）；另有外部签名服务方案（`getAbogusUrl` → `dy.nsapps.cn`，`douyin_site.dart:1239-1257`）**未启用**。
- 建议：给签名失败加统一埋点/降级提示；评估启用自部署签名服务（注释中「请自行部署后使用」）。
- 影响：抖音分区/推荐/web-enter 全部 HTTP 链路。

### P1-3 虎牙 VIP 房间名单硬编码

- 现象：`huya/common/huya_vip_room_id.dart` 维护 100+ 房间号；4K 档位对这些房间直接 `continue` 跳过（`huya_site.dart:151-155`），HDR 档位无条件跳过（:326-334）。
- 建议：把「跳过」升级为「对用户可见的档位说明」，并给名单加更新来源/日期戳；或改用接口判定（上游 `isVipRoom` 已有雏形）。
- 影响：虎牙高画质用户预期（4K 用户看不到入口）。

### P1-4 弹幕解码层没有离线回归

- 现象：bilibili 二进制包头+压缩、douyu STT、huya tars、douyin protobuf 四套解码逻辑目前只有联网冒烟（`test/simple_live_core_test.dart` 30s 真连），平台帧格式一改就只剩「线上炸」这一条发现路径。
- 建议：采集真实帧样本落盘，按 test-suite.md §4.3 的用例补齐离线解码测试（现有 adapter 注入范式可复用）。
- 影响：弹幕是所有平台的高频故障面。

### P1-5 斗鱼游客/海外链路依赖用户配置与临时 hack

- 现象：游客流只能存活 5min、需 cookie（`b492f965`）；海外 `expire=300 & fcdn=ws` 追加 `&expire=0`（`douyu_site.dart:134-136`，上游标注 temp）；cookie 续期依赖 `safeAuth` + JWT exp 判断（`douyu_utils.dart:49-90`）。
- **已改进（2026-10-16）**：游客断流不再要求用户配 cookie——`LivePlayUrl.renewers`（core）+ `StreamRelayService` 本地续流中转（app，`lib/services/stream_relay/`）在直链 300s 到期前重新取流并做 FLV tag 级接续（参考 DTV `ae4b425f`）。非 FLV 线路或中转登记失败的线路自动退回直连。
  - 补充实测（2026-10-16，游客态）：**「固定 300s 寿命」不是所有线路都成立**——`hw1a.douyucdn2.cn` 的直链 URL 自带 `expire=0`，连接 335s 未断。中继对此按「到期就续、没到期就不打扰」处理（预取挂 30s 用不上即放弃，退化为直通），真断时才同步补取。
  - 另一实测：真实流里约 1/s 存在与前一帧**同毫秒**的音频 tag，接续过滤用「相等也算未落后」（`FlvTimeline.isNotBehind`），否则会系统性丢帧。
- 建议：把「cookie 即将过期」提前到设置页提示（上游 `88ee03b5` 已在 App 侧加了提示，仓库内确认覆盖）；跟踪 `expire=0` 的正式方案（续流落地后它已退化为「首取+续流」共用的兼容路径，可择机验证删除）。
- 影响：斗鱼在非登录/海外场景的稳定性。

## 3. P2 — 结构 / 技术债 / 功能缺口

### P2-1 接口扩展方式容易再次破坏下游

- 现象：v1.1.0 给 `getCategoryRooms/getRecommendRooms` 加 `pageSize` 具名参数时，5 个内置实现全部要改（`CHANGELOG.md` 1.1.0 明示「破坏性」）。**2026-10-12 `abca65f8` 又一次验证**：上游把 `setSiteAttrs` 契约由 `Map<String, dynamic>` 改为 `String`，5 个平台实现签名必须同步改回，否则编译失败（`live_site.dart:103`）。
- 建议：新增能力优先用**可选具名参数给默认值**（`int? pageSize` 已是此形态，问题在实现方签名必须同步），或把可选能力拆成独立 mixin/扩展类；接口变更时同步跑 `simple_live_app`/`tv_app`/`console` 的编译。
- 影响：core 与三个消费工程的升级成本。

### P2-2 `dynamic` 通道无形状校验

- 现象：`detail.data` / `detail.danmakuData` / `quality.data` 全为 `dynamic`，跨平台误传只在运行时报错（抖音连麦崩溃即此类问题的极端形态，`63c1eb8d`）。
- 建议：给每个平台私有载荷加类型别名 + `assert`（debug 模式）或 `toString()` 诊断信息；在弹幕 `start()` 入口做一次类型检查并抛 `CoreError`。
- 影响：错误定位速度。

### P2-3 弹幕不支持 gift；表情包 B 站/虎牙 + 抖音会员/标准表情（Rust core）

- 证据：`live_message.dart:5-8`（gift 注释「暂时不支持」）、:37（emoticons 注释「目前仅 B 站」）；虎牙表情见 `8c9fc881`。抖音会员 / 守护表情由 Rust core 解析 `WebcastEmojiChatMessage`；普通聊天的 214 个标准 `[码]`（`[微笑]`/`[呲牙]`/`[互粉]` 等）由 `danmaku/emoticon.rs` 静态表映射（`crates/slive-core/src/platforms/douyin/danmaku/`）；Dart core 与 console 尚未迁移。标准表情的图片是签名 CDN 地址，有效期至 2036-10，过期后需重新抓表。
- 建议：明确产品取舍；若做 gift，需要各平台礼物模型 + App 侧展示协议（工作量大，先记录）。

### P2-4 网络与重连策略过于固定

- 现象：HTTP 超时固定 20s 无重试（`http_client.dart:17-21`）；WS 断线 5s×5 次固定（`web_socket_util.dart:149-163`），无指数退避、无「网络恢复立即重连」。
- 建议：至少把重连次数/间隔提为可配置；结合 App 的生命周期（后台/前台）切换重连策略。
- 影响：弱网体验。

### P2-5 弹幕无节流/背压

- 现象：`onMessage` 每条弹幕直接回调（大房间刷屏时由消费方自行处理）。
- 建议：给 `LiveDanmaku` 增加批量/节流回调选项（默认关闭，避免影响现有行为）。
- 影响：超人气房间的 UI 压力（App 侧已有消息上限，属于包内兜底）。

### P2-6 死代码与临时物清理

- `douyin_site.dart:851`（标注「死代码」）、:875（`_getUserUniqueId` unused）、`douyin_utils.dart:45`（`getTtwidWebid` 注释「no useful」）；
- 虎牙未启用的 WUP 流程：`buildLiveInfoData`/`buildDoLaunchData`/`buildEnterChanelData`（`huya_danmaku.dart:118-191` 注释状态）；
- `douyu_utils.dart:154` `todo: 获取 real_rid 暂未发现 fake_id`；
- `douyin.proto:166`（「后面的就不写了还有几十个属性」）、:563（字段名待定）；
- 抖音真原画（hvc1）代码被注释（`douyin_site.dart:1091-1103`，依赖 media_kit 支持）。
- 建议：逐条「删除 or 建 issue」二选一，避免临时代码沉淀成误导。

### P2-7 抖音弹幕颜色未知

- 现象：`douyin_danmaku.dart:163`「暂不知道具体怎么转换颜色」，颜色被注释、固定白。
- 建议：采集样本逆写颜色字段（结构已有 `LiveMessageColor`）。

### P2-8 抖音推荐流容量与游标语义

- 现象：feed 首屏池只有 45~65 间、并发 6 路饱和（`douyin_site.dart:279-282` 常量与注释）；第 1 页会重置续接游标 `_lastServedSlot`（有测试锁定行为）。
- 建议：若产品上「下拉刷新后推荐内容重复感强」，评估首屏扇出与游标重置策略；容量本身受服务端限制，属已知边界。
- 影响：推荐流观感。

### P2-9 CHANGELOG 断档

- 现象：`CHANGELOG.md` 只有 1.1.0 / 1.0.0 两条（历史随重写丢失）。
- 建议：以后每次 fork 侧接口变更都在此留条目；历史用 `doc/update-history.md` §6 代偿。

### P2-10 core 依赖 Flutter SDK

- 现象：`pubspec.yaml` 直接依赖 `flutter: sdk`（为 `web_socket_channel` 等生态），导致 core 不能作为纯 Dart 包使用/发布。
- 建议：评估把 WS 换成 `package:web_socket`（纯 Dart）等路线；短期保持现状，只在文档中明示。

### P2-11 账号接口在 huya / douyin / twitch 仍是 TODO 桩

- 现象：`abca65f8` 把账号能力下沉 core 后，只有 bilibili / douyu 完整实现；huya 的 `getQRCode/getQRPollResult/getAccountInfo`、douyin 的 `getQRCode/getQRPollResult`、twitch 的 `setSiteAttrs/getQRCode/getQRPollResult/getAccountInfo` 均为 `throw UnimplementedError()` 桩，调用即抛异常。
- 证据：`huya_site.dart:567-582`；`douyin_site.dart:1290-1299`（`getAccountInfo` 已实现于 `:1249`）；`twitch_site.dart:298-319`。
- 建议：按 architecture.md §3.7 的链路约定补齐；优先 huya（虎牙已有匿名 uid 基础）与 douyin（`getAccountInfo` 已就绪，只差扫码）；补齐前 App 侧需按平台隐藏登录入口或捕获异常。
- 影响：三端账号功能在这些平台不可用（登录即抛 `UnimplementedError`）。

### P2-12 `huya_site.dart` 的 `_isVipRoom` 赋值后无人读取（unused_field）

- 现象：`_isVipRoom` 声明于 `huya_site.dart:37`、在 `:229` 被赋值，但全文件无读取点（`flutter analyze` 报 unused_field，存量 info/warning）。
- 证据：`grep _isVipRoom huya_site.dart` 仅命中声明与赋值两处（`:37`、`:229`）；为上游 v1.8.15 遗留。
- 建议：二选一——删除该字段，或让 4K/VIP 跳过逻辑真正改用它（现跳过逻辑走硬编码名单，见 P1-3），避免「看似有 VIP 判定实则未生效」的误导。
- 影响：无功能影响；属死代码/误导性代码。

### P2-13 douyin 未采用上游 `_updateDouyinCookie`（`_cookie` 字段）方案

- 现象：`abca65f8` 合并时抖音 `setSiteAttrs` 取上游 `String` 契约，但实现保留 fork 的 `headers['cookie']` 语义，**未引入**上游的 `_cookie` 字段与 `_updateDouyinCookie()`（合并结果里没有该方法，`douyin_site.dart:1233`）。
- 证据：`grep "_cookie|_updateDouyinCookie" douyin_site.dart` 无命中；对比 `git show origin/dev:simple_live_core/lib/src/platforms/douyin/douyin_site.dart` 存在 `String _cookie` 与 `void _updateDouyinCookie(String)`。
- 建议：跟踪上游是否在后续提交中让「cookie 二次更新」（如 web-enter 的 `set-cookie` 回写）依赖 `_cookie` 字段；一旦上游逻辑要求维护该内部状态，需重新对齐，否则会出现行为分叉。
- 影响：抖音 cookie 生命周期管理（当前 fork 侧仅 `headers['cookie']` 单点）。

## 4. 建议的推进批次

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 1 | P0-1 / P0-2 / P0-3 | 都是「用户能看见」且改动局部 |
| 2 | P1-4（补弹幕解码离线测试） | 先有护栏再动协议层，成本最低、收益最高 |
| 3 | P1-1 / P1-2 / P1-3 | 平台对抗类，需要真机/真号验证，建议成组做 |
| 4 | P2-1 / P2-2 / P2-6 | 结构性整理，配合下一次接口变更一起做 |
| 5 | 其余 P2 | 按产品优先级取舍 |

## 5. 已决策的取舍与已解决项（记录原因）

| 取舍 / 项 | 原因 | 来源 |
| --- | --- | --- |
| 斗鱼弹幕只看 `fans=='1'` 的发言 | 评论原文：斗鱼不返回人气值、部分直播间有「阴间弹幕」；宁可少收不漏脏 | `douyu_danmaku.dart:79-90` |
| 斗鱼推荐流「本页非空即还有更多」 | 服务端 `pgcnt` 恒为 0，只能退化判据；App 侧跨页去重兜底 | `e1f7a75c`、`douyu_site.dart:156-195` |
| 抖音首屏 `hasMore` 恒 true | feed 翻不动页，必须让 App 走到续接页；分区接口兜底 | `49eef9c3`、`douyin_recommend_fanout_test.dart` |
| 「无空白的表情名+正文」按整串替换 | B 站真实表情名含「哈哈哈」这类重复字，再收紧会误杀合法表情；代价是异常载荷下丢字 | `bilibili_emoticon_test.dart` 末组用例 |
| 虎牙未开播也给弹幕参数兜底 `HuyaDanmakuArgs(0,0,0)` | App 会无条件 `start`；避免空安全崩溃（`ed8e2880` 上游同类问题） | `huya_site.dart:344-354` |
| 保留 `assets/js/*.js` 历史文件 | 作为逆写算法的参考实现 | `architecture.md` §3.5 |
| **【已解决】** bilibili `setSiteAttrs` 曾是 TODO 桩 | 上游 v1.8.15（`abca65f8`，同批附 webLogin 迁移 `9abf40ff`）把它实现为「整串当裸 cookie」，与扫码产出的 JSON credential（`bilibili_site.dart:600`）配不上对；**2026-10-14 已解决**：上游 `57d8f86d` 改为 JSON 取 `cookie` 键，见 update-history.md §5 | `bilibili_site.dart:553-558` |