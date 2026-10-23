# simple_live_core 工作流程图

> 锚点：future `52466f96`（2026-10-21）｜范围：`crates/slive-core` + `src/api/slive` + `lib/src/bridge` + `crates/slive-cli`
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/workflow-diagram.md)｜[TV](../../simple_live_tv_app/doc/workflow-diagram.md)

## 1. 两个入口，同一核心

```
App / TV → Rust*Site（Dart 绑定层）→ FRB 2.13 → src/api/slive → crates/slive-core
CLI slive ─────────────────────────────────────→ crates/slive-core（绕开 FRB）
```

- Dart 侧只做模型翻译与回调：`lib/src/bridge/rust_*_site.dart`。
- 核心零 FRB 依赖，可被其他 Rust 前端复用。

## 2. 播放链

```
get_room_detail(roomId)
  → 平台详情（JSON / HTML 正则 / 三级兜底）
  → LiveRoomDetail{status, data, danmaku_data}
get_play_qualities(detail)
  → 清晰度列表（部分平台本地组装，不发请求）
get_play_urls(detail, quality)
  → 真实线路 + headers（bilibili/douyu/huya 需请求）
  → 播放器按 urls 顺序尝试，headers 必须透传
```

| 阶段 | 特例 |
| --- | --- |
| detail | 虎牙抓 HTML 正则；抖音按 roomId 位数分流 `reflow/info` / `web/enter`，连麦房间补查 |
| qualities | 抖音解析 `live_core_sdk_data`，缺失回退 `flv_pull_url`/`hls_pull_url_map`；虎牙本地组装 |
| urls | 抖音直接用详情阶段地址；虎牙逐线路 tars + antiCode；B站 mcdn 排最后；斗鱼海外 `expire=0` |

斗鱼续流不在 core：App 按「房间+清晰度+线路」登记上下文，中转到期自行重取。

## 3. 弹幕链（每实例一个句柄）

```
site.getDanmaku() → XxxDanmakuConnection
  → start(argsJson, StreamSink)
  → from_json
  → 本句柄 stop_rx（watch；无全局单例）
  → 独立线程 + 自建 tokio runtime（FRB FFI 线程无 reactor）
  → run_session: connect → Ready → join → 收帧/解码 → 心跳
  → stop() 或句柄释放 → Closed("已手动停止")
```

状态机：`Connecting → Ready → Reconnecting（5s×5）→ Closed`；收到消息后重连计数归零；解码异常只记日志不断连。

证据：`crates/slive-core/src/ws/`、各平台 `danmaku/session.rs`。

## 4. 分页契约（hasMore）

```
get_category_rooms / get_recommend_rooms(page, pageSize?)
  → 平台是否支持 pageSize？否 → 用默认单页
  → hasMore：服务端字段有效则采信；失效则退化
  → LiveCategoryResult{has_more, items}
```

| 平台 | 判据 |
| --- | --- |
| bilibili 分类 | `has_more == 1`（单页固定 30） |
| bilibili 推荐 | 本页非空（唯一真正使用 pageSize） |
| douyu 分类 | `page < pgcnt` |
| douyu 推荐 | 本页非空（实测 pgcnt 恒 0） |
| huya | `page < totalPage` |
| douyin 分类 | 本页条数 ≥ count（满页，count=15） |
| douyin 推荐首屏 | 恒 `has_more=true`（feed 池 45~65） |
| douyin 推荐第 2 页起 | 7 分区轮转，本页非空；一圈全空才到底 |
| twitch | 无分页 |

## 5. 平台专属（一行版）

- **bilibili**：buvid3/4 + wbi（mixinKey 重排 + md5）；WSS 16 字节包头，ver 0/1/2/3；60s 心跳。
- **douyu**：`getEncryption` + md5 链（5min 缓存）；STT 文本帧；只受理 `fans=='1'`；45s 心跳。
- **huya**：HTML 正则 + tars `getCdnTokenInfoEx` + antiCode；TARS 弹幕；SC 走 WS 信号 + HTTP 拉取；60s 心跳。
- **douyin**：abogus / x_bogus（SM3+RC4）；protobuf 弹幕 + gzip + needAck；10s 心跳。
- **twitch**：GQL + m3u8；IRC 匿名 `justinfan`；40s 心跳；不支持项显式报错。

## 6. 失败与兜底

| 位置 | 行为 |
| --- | --- |
| HTTP | `SliveError` → `CoreError`（Network/Decode/Api/InvalidInput/Websocket） |
| 虎牙取流 | 单线路失败跳过，其余继续 |
| 抖音详情 | 三级兜底；全失败抛可读错误 |
| 抖音列表 | 脏条目跳过；整页失败才上抛 |
| 弹幕 | 脏帧只记日志 |

## 7. 消费方契约

1. `pageSize` 是期望值，只有 B站推荐真正使用。
2. `detail.data` / `danmaku_data` 是平台私有 JSON，不跨平台复用。
3. `get_play_urls` 多线路按序尝试，`headers` 必须透传。
4. 弹幕 `start(danmakuData)` 后等 `onReady`；`stop()` 后实例不可复用。
5. 未开播仍可挂弹幕。
6. 账号：`getQRCode → getQRPollResult → getAccountInfo → setSiteAttrs(String JSON)`。

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| Rust 核心/FRB 接管 | `73e80b1e`、`f72bb417` |
| 每实例弹幕连接句柄 | `3f0ac946`、`eecc060f` |
| 分页 hasMore | `e1f7a75c`、`49eef9c3` |
| 斗鱼续流 | `77eebd63`、`594023ae` |
| 账号迁 core | `e3a090ad` … `aa5f8073` |
| 弹幕表情 | `a5e594dc`、`3d237b0e`、`30bf6aae`、`953f78b7` |
