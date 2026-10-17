# simple_live_core 架构与选型对照

> 版本锚点：`simple_live_core` v1.1.0 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)

## 1. 模块全景

```
simple_live_core/
├── lib/simple_live_core.dart        # barrel 导出（5 个 Site + 5 个 Danmaku + 模型 + 账号模型/枚举）
├── lib/src/interface/
│   ├── live_site.dart               # LiveSite：全平台统一接口（具体类，默认空实现；含账号三接口）
│   └── live_danmaku.dart            # LiveDanmaku：弹幕长连接抽象接口
├── lib/src/common/
│   ├── http_client.dart             # Dio 单例（connect/receive/send=20s）
│   ├── custom_interceptor.dart      # 统一请求/响应/错误日志（带耗时）
│   ├── core_error.dart              # 统一错误类型（message + statusCode）
│   ├── core_log.dart                # 可插拔日志（onPrintLog 钩子，App 接管输出）
│   ├── web_socket_util.dart         # WS 封装：心跳、断线重连、backupUrl
│   ├── binary_writer.dart           # 大小端二进制读写（bilibili/douyu 分包）
│   ├── qr_status.dart               # 账号扫码状态枚举（loading/unscanned/scanned/expired/failed）
│   ├── common_asT.dart              # 安全类型转换 `asT<T>()`（账号模型解析用）
│   └── parse_cookie.dart / convert_helper.dart
├── lib/src/model/                   # 跨平台模型（见 §3.4）
│   ├── account_info.dart            # 账号信息（name/avatar/uid/credential/isValid）
│   └── account_qr_code.dart         # QRCode（key/url/expireAt）+ QRPollResult（status/credential/message）
├── lib/src/platforms/
│   ├── bilibili/ douyu/ huya/ douyin/ twitch/    # 每平台：site + danmaku (+ utils/signing + model/)
│   │   ├── bilibili/model/bilibili_user_info.dart   # 账号信息解析（新增）
│   │   ├── douyin/model/douyin_user_info.dart        # 账号信息解析（新增）
│   │   └── huya/model/huya_damaku_model.dart         # 虎牙弹幕模型
│   └── readme.md                    # “json to dart model”与三段式取流的口径说明
├── packages/tars_dart/              # 内置包：Tars/TUP 编解码（虎牙必需）
├── test/                            # 6 个测试文件（`ls test/*.dart`；离线回归 + 联网冒烟，见 test-suite.md）
└── example/simple_live_core_example.dart
```

依赖方向：`platforms → interface/model/common`，`interface → model`；`common` 不依赖 `platforms`。**没有任何反向依赖**，也没有对 `simple_live_app` 的依赖。

## 2. 分层

| 层 | 职责 | 变更频率 |
| --- | --- | --- |
| 接口层 | 定义契约与默认行为，决定下游兼容性 | 极低（改动即破坏性，见 §3.1） |
| 平台层 | 逆向平台协议：签名、分页、解码、特例兜底 | 高（平台改版驱动） |
| 模型层 | 跨平台数据结构；平台私有数据用 `dynamic` 通道携带 | 低 |
| 基础层 | HTTP/WS/日志/错误/二进制工具 | 低 |

## 3. 关键设计决策与对照

### 3.1 `LiveSite` 是具体类 + 默认空实现（而不是 `abstract class`）

- **现状**：`class LiveSite`，所有方法都有默认返回（空列表 / `false` / 空 `LiveRoomDetail`）；5 个平台 `implements LiveSite` 而不是 `extends`。
- **备选**：`abstract class` + 各平台 `extends`，编译器强制实现全部方法。
- **选择理由**：新增能力（如 `getSuperChatMessage`、`setSiteAttrs`）时，不必同时改 5 个平台；未实现的平台「静默不支持」而不是编译失败。`implements` 则保证平台层不会意外继承出错误的默认行为（必须显式覆写才生效）。
- **代价**：接口变更对「实现方」是破坏性的——v1.1.0 给 `getCategoryRooms/getRecommendRooms` 加 `pageSize` 具名参数时，5 个平台实现必须同步补参数（调用方不受影响）。这是历史遗留的显式取舍，参见 `simple_live_core/CHANGELOG.md` 1.1.0 条目。

### 3.2 回调式弹幕（`onMessage/onClose/onReady`）而不是 `Stream`

- **选择理由**：弹幕是「一条长连接 + 高频单向事件」，回调最直接；App 层可直接把回调桥接到自己的事件总线/状态管理，不需要在 core 里引入 `StreamController` 生命周期管理。
- **代价**：无法用 `Stream` 的操作符（节流、背压）；同一实例只能挂一个消费者（业务上够用，App 只有一个直播间消费弹幕）。
- **重连集中在基础层**：`WebScoketUtils` 负责心跳定时器、5s×5 次重连、`backupUrl` 切换；平台实现只提供 URL/headers/heartbeat 间隔和「鉴权包」逻辑。5 个平台心跳间隔：bilibili 60s / douyu 45s / huya 60s / douyin 10s / twitch 40s。

### 3.3 HTTP：Dio 单例 + 拦截器 + 统一错误

- **现状**：`HttpClient.instance`（懒加载单例）持有 `Dio`，挂 `CustomInterceptor`（记录耗时、按 `CoreLog.requestLogType` 分级打印）；所有失败收敛为 `CoreError`（带 `statusCode`），App 直接展示其 `message`。
- **对照**：用 `package:http` 或每平台自建 client → 会散落超时/日志/错误处理。集中单例让「注入 HttpClientAdapter 跑离线测试」也变成可能（见 test-suite.md），这是测试策略的地基。
- **代价**：全局单例不便于并行隔离/多账号；测试必须记得还原 adapter。

### 3.4 平台私有数据用 `dynamic` 双通道携带

- `LiveRoomDetail.data`：详情页中间态（虎牙 `HuyaUrlDataModel`、抖音 stream 数据、douyu 无）。
- `LiveRoomDetail.danmakuData`：弹幕连接参数（`BiliBiliDanmakuArgs` / `HuyaDanmakuArgs` / 抖音房间号字符串 / douyu 房间号）。
- `LivePlayQuality.data`：清晰度与地址的中间态（bilibili 用 `qn` 整数、douyu 用 `DouyuPlayData(rate, cdns)`、虎牙用 `{urls, bitRate}`）。
- **对照**：全强类型（泛型化 `LiveRoomDetail<T, D>`）会污染所有跨平台调用点；早期新平台曾走「json_to_dart model」（见 `lib/src/platforms/readme.md`）。
- **代价**：类型不安全，靠约定 + 各平台自己的 model 类兜底；跨平台误传会运行时报错。`updateData()/updateDanmakuData()` 是唯一的替换入口。

### 3.5 JS 引擎的剥离（重要历史选型）

上游早期用 `flutter_qjs`（内嵌 JS 引擎）执行平台侧脚本做签名/加密，后逐步「逆写」成纯 Dart：

| 时间 | 提交 | 内容 |
| --- | --- | --- |
| 2025-09 | `4802e965` / `38bdefb2` | 测试斗鱼/抖音本地签名 |
| 2026-03 | `dd44a80e` | 斗鱼逆写 JS，逐步剥离 `flutter_qjs` |
| 2026-06 | `0509f173`、`1c9d1714` | 抖音弹幕 xbogus 替换 JS 引擎；移除 JS 插件 |
| fork | 保留 `assets/js/*.js` 历史文件为参考 | — |

**收益**：去掉平台侧 JS 引擎依赖后，core 只依赖 Dart 生态（dio/crypto/dart_sm…），体积与启动成本下降，纯 Dart 可测（离线用例不再需要 JS 运行时）。**代价**：平台算法变更时需要人工跟踪逆写（如 abogus 的 SM3+RC4 实现）。

### 3.6 虎牙引入 `tars_dart`（内置包）

虎牙的拉流 token 与弹幕走腾讯 Tars/TUP 协议，Dart 生态没有可用实现，因此以 `path` 依赖内置 `packages/tars_dart`。这是一个「协议适配必须自己造」的案例：`BaseTarsHttp`（WUP over HTTP，取 `sFlvToken`）+ `TarsInputStream/OutputStream`（WS 弹幕帧解码）。

### 3.7 账号体系下沉到 core（上游 v1.8.15，`abca65f8`）

- **背景**：账号登录（扫码 / webLogin / cookie 校验）原本在 `simple_live_app` 侧实现，各端（app/tv_app/console）各自维护。上游 v1.8.15 把账号能力下沉到 core，统一入口。
- **接口新增**（`live_site.dart`）：`getQRCode()`（生成登录二维码，返回 `QRCode`）、`getQRPollResult({qrcodeKey})`（轮询扫码状态，返回 `QRPollResult`）、`getAccountInfo({credential})`（用凭证校验并换回 `AccountInfo`）。三者都在 `LiveSite` 上带默认空实现（`live_site.dart:107-121`），未实现的平台「静默不支持」。
- **`setSiteAttrs` 契约变化**：由 fork 早期的 `Map<String, dynamic>` 改为上游的 **`String`**（`live_site.dart:103`）。各平台用 `jsonDecode`（string2json）解析统一 credential：**bilibili 现在也按 JSON 取 `cookie` 键，与其他平台一致**（自 `5ae375f1`／上游 `57d8f86d`，`bilibili_site.dart:553-558`；此前是把整串当裸 cookie，和扫码流程产出的 JSON credential（`bilibili_site.dart:600`）配不上对）；douyu 读 `cookie`/`dy_did`/`LTP0`（`douyu_site.dart:344-356`）、douyin 读 `cookie`/`hlsFirst`（`douyin_site.dart:1233-1246`）、huya 只读 `ua`（`huya_site.dart:559-564`）。这是**对实现方的破坏性变更**（5 平台签名同步改回 String）。
- **数据模型**：新增 `AccountInfo`（`name/avatar/uid/credential/isValid`，`account_info.dart`）、`QRCode`+`QRPollResult`（`account_qr_code.dart`）、`QRStatus` 枚举（`qr_status.dart`）；平台侧用户信息模型 `BiliBiliUserInfoModel`、`DouyinUserInfoModel`（用 `asT<T>` 安全转换，`common_asT.dart`）。
- **链路约定**（`live_site.dart:115-118` 注释）：`login/init → getQRCode → 轮询 getQRPollResult(QRStatus) → getAccountInfo(credential) 校验 → isValid 则保存 → setSiteAttrs 注入`；因各 Site 是单例，注入后全局生效。
- **`getAccountInfo` 不止返回值**（`5ae375f1`，上游 `03c4493a`）：bilibili 校验成功时会把账号 uid 写进站点单例字段（`bilibili_site.dart:622` `userId = info.mid!`），`getRoomDetail` 再把它填进 `BiliBiliDanmakuArgs.uid`（`bilibili_site.dart:250-257`）；弹幕 WS 的 join 包带的就是 `"uid": args.uid`（`bilibili_danmaku.dart:91`），cookie 走握手头（`bilibili_danmaku.dart:63-67`），两者必须是同一个账号的一对。改动前 `userId` 在本文件无写入点，join 包恒为 0。core 没有弹幕发送接口（`live_danmaku.dart:5-25`），所以这条只影响握手，不影响下行解码。
- **实现分叉**：抖音 `setSiteAttrs` 采用上游的 `String` 契约，但实现保留 fork 的 `headers['cookie']` 语义，**未采用**上游的 `_cookie` 字段 + `_updateDouyinCookie()`（`douyin_site.dart:1233`）。详见 §6 与 backlog。
- **当前进度**：仅 bilibili / douyu 全实现；douyin 的 `getAccountInfo` 已实现，`getQRCode/getQRPollResult` 仍是 `UnimplementedError` 桩；huya 三接口、twitch 三接口 + `setSiteAttrs` 均为桩。

### 3.8 统一格式约定：`dart format`（上游 `63a3055c`）

- 上游随 v1.8.15 引入一次全库 `dart format .`（合并后 core 26 个文件被重排），并在 `analysis_options.yaml` 固化 `formatter: {trailing_commas: preserve, page_width: 120}`（`analysis_options.yaml:31-33`）。
- **影响**：随后任何 core 改动都应遵循该格式，避免制造无关 diff；本次合并中抖音 `douyin.pb*.dart` 因 format 产生的重排量最大（diff 噪声，非逻辑变更）。

## 4. 平台实现对照表（选型全景）

| 维度 | bilibili | douyu | huya | douyin | twitch |
| --- | --- | --- | --- | --- | --- |
| 详情获取 | JSON API | `betard/{roomId}` JSON | **网页 HTML 正则** | JSON（reflow/web-enter/网页三级） | gql |
| 列表分页 | 服务端 `has_more` / 本页非空 | 类目 `pgcnt` / 推荐本页非空 | `page < totalPage` | offset+count（满页判据） | 不支持 |
| 取流签名 | wbi（md5 + 重排表） | `getEncryption` + md5 链（5min 缓存） | tars `getCdnTokenInfoEx` + antiCode（md5/rotl64） | 无（本地组装） | 无 |
| 反爬（HTTP） | buvid3/4 + wbi | dy_did/acf_did + enc_data | 匿名 uid + 固定 cookie/guid（temp） | **abogus**（SM3+RC4，`aid=6383`） | 无需 |
| 弹幕传输 | WSS 自定义二进制 | WSS + 自制 STT 文本帧 | WSS + tars | WSS + protobuf(gzip) | WSS + IRC |
| 弹幕鉴权 | 16 字节包头 + token JSON | loginreq/joingroup | RegisterGroupReq(cmd16) | 长 query + **xbogus 签名** | 匿名 justinfan |
| 心跳 | 60s（JSON 包） | 45s（mrkl） | 60s（cmd20） | 10s（PushFrame hb）+ needAck 回执 | 40s（PONG） |
| 弹幕支持面 | chat/online/SC/**表情** | chat(仅粉丝)/SC（无 online） | chat/online/SC/**表情** | chat/online/**会员表情 + 标准表情** | 仅 chat |
| 表情包 | `parseBilibiliEmoticons`（fork 新增） | — | `huya_emoticon.dart`（103 个 `[xx]` 映射） | Rust core：`WebcastEmojiChatMessage`（会员/守护表情）+ 214 项标准 `[码]` 表 | — |
| SC 路径 | WS 下行解析 | WS 下行解析 | **WS 信号 + HTTP 拉取** | 不支持 | 不支持 |
| 搜索 | 房间+主播 | 房间+主播 | 房间（yyid） | 仅房间（主播接口抛异常） | 不支持 |
| 特殊兜底 | mcdn 线路后置 | cookie JWT 续期；海外 `expire=0`；flv 线路带**续流回调** `renewers` | 4K(HDR/VIP) 跳过；线路级容错 | 连麦房间 reflow 补查；脏数据单条跳过 | — |
| **账号能力**（v1.8.15） | 已实现：扫码 `getQRCode/getQRPollResult` + `getAccountInfo`（cookie 校验） | 已实现：did 获取 + 扫码 + `refreshCookie`（LTP0/cookie） | **TODO 桩**：三接口均 `UnimplementedError` | `getAccountInfo` 已实现；`getQRCode/getQRPollResult` 为 TODO 桩 | **TODO 桩**：三接口 + `setSiteAttrs` 均未实现 |

## 5. 依赖清单（`pubspec.yaml`）与用途

| 依赖 | 用途 | 不可替代性 |
| --- | --- | --- |
| `flutter` (sdk) | 仅因 `web_socket_channel` 等生态；**不是 UI 组件库** | 让 core 无法作为纯 Dart 包发布（见 backlog） |
| `dio` | HTTP（超时/拦截器/CancelToken） | 中 |
| `web_socket_channel` | 5 平台弹幕长连接 | 高 |
| `crypto` | md5（wbi/antiCode/douyu auth） | 高 |
| `dart_sm` | SM3（抖音 abogus） | 高 |
| `protobuf` | 抖音弹幕帧 | 高 |
| `brotli` | bilibili 协议压缩版本 3 | 高 |
| `html_unescape` | 斗鱼 rtmp_live 反转义 | 低 |
| `logger` | 日志输出（可被 `CoreLog.onPrintLog` 接管） | 低 |
| `fixnum` | protobuf/tars 的 64 位整数 | 高 |
| `tars_dart` (path) | 虎牙 Tars/TUP | 高（自研内置） |

## 6. fork 与上游的差异对照（future vs fork-parent/dev）

| 差异 | fork 实现 | 上游行为 | 兼容性 |
| --- | --- | --- | --- |
| `pageSize` 具名参数 | 新增（v1.1.0），bilibili 推荐流真正使用，其余忽略；`abca65f8` 同步时**再次作为冲突点保留 fork 版** | 无此参数（`origin/dev` 的 `live_site.dart` 无 `pageSize`） | **对实现方破坏性**（5 个内置实现已同步） |
| 分页判据 | 收敛为「服务端字段或退化判据」+ 回归测试（`e1f7a75c`） | 各自为政，douyu 推荐依赖失效的 `pgcnt` | 调用方无感 |
| B 站表情包 | `LiveMessage.emoticons` + `LiveMessageEmoticon`（含 `large`/`emoticonUnique`）+ 解析器 + 31 条离线用例（`grep -c 'test(' test/bilibili_emoticon_test.dart`） | 无 | 模型新增字段，向后兼容 |
| 抖音表情 | Rust core 解析 `WebcastEmojiChatMessage` → `LiveMessage.emoticons`（会员/守护表情）；`ChatMessage.content` 里的 214 个标准 `[码]` 由静态表映射成图片 | 无 | 模型复用，向后兼容 |
| 抖音推荐流 | feed 首屏扇出 + 分区轮转真分页（`49eef9c3`） | 一次 feed 请求、无真分页 | 调用方无感（语义更接近「无限滚动」） |
| 抖音连麦房间 | reflow 优先 + stream 缺失补查 + 全链路判空（`63c1eb8d`） | 空指针崩溃 | 调用方无感 |
| 斗鱼推荐分页 | 弃用 `pgcnt`，本页非空即还有更多（`e1f7a75c`） | `page < pgcnt`（恒 false，卡第一页） | 调用方无感 |
| 抖音 `setSiteAttrs` 实现 | `String` 契约 + `headers['cookie']` 语义（`douyin_site.dart:1233`）；无 `_cookie` 字段/`_updateDouyinCookie()` | 上游曾用 `_cookie` 字段 + `_updateDouyinCookie()` 维护 cookie 生命周期 | 语义分叉：若上游后续依赖 `_cookie` 字段（如 cookie 二次更新）需重新对齐（见 backlog） |
| 账号体系位置 | 随上游下沉至 core（`abca65f8`）；实现进度见 §4 | 同在 core，但仅 bilibili/douyu 完整 | — |

## 7. 已知取舍与风险（详见 backlog.md）

- `LiveSite` 默认空实现让「不支持」与「实现漏了」长得一样，调用方只能靠文档/测试区分。
- `dynamic` 通道的数据形状没有运行时校验，平台改版后错误会在消费方炸开。
- 虎牙依赖网页正则与硬编码 VIP 名单、弹幕 WS 使用 temp cookie/guid —— 平台反爬升级时最脆弱的一环。
- 斗鱼弹幕只受理粉丝发言（历史行为），可能漏消息但避免了「阴间弹幕」。
- 抖音 abogus 属于风控对抗，参数（aid、UA 指纹、白名单路径）随时可能失效；另有自部署签名服务方案（未启用，见 backlog）。
- 测试覆盖偏斜：分页与表情包有大量离线回归；网络协议层（WS 解码）只有联网冒烟。