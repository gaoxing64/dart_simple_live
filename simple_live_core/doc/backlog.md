# simple_live_core 待办与优化清单

> 锚点：future `52466f96`（2026-10-21）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 下游：[App](../../simple_live_app/doc/backlog.md)｜[TV](../../simple_live_tv_app/doc/backlog.md)

## P0 — 正确性/恢复能力

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | 抖音 `get_play_urls` 只回传详情阶段地址，无过期重取入口 | `platforms/douyin/site.rs`、`play.rs` | 补地址过期重取，或消费方断流时强制重查详情 |
| P0-2 | B站 wbi key 缓存无失效策略，服务端轮换后持续签名失败 | `platforms/bilibili/wbi.rs`、site 句柄缓存 | 签名失败清缓存重试一次或加 TTL |

## P1 — 平台脆弱点

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | 虎牙弹幕用匿名固定 guid/cookie | `platforms/huya/danmaku/tars_cdn.rs` | 接匿名登录替换硬编码 |
| P1-2 | 虎牙详情依赖网页 HTML 正则 | `platforms/huya/detail_parse.rs` | 找稳定 JSON；至少加解析失败告警 |
| P1-3 | 抖音 abogus/x_bogus 是风控对抗 | `platforms/douyin/signature/` | 失败埋点 + 用户可读提示 |
| P1-4 | 虎牙 VIP 房间名单硬编码 100+ | `platforms/huya/vip_room_id.rs` | 跳过改成用户可见说明；加更新来源/日期 |
| P1-5 | 斗鱼游客流 5min、海外 `expire=0` 为临时规则 | `platforms/douyu/play.rs` | 跟踪正式方案；App 已用续流中转兜底 |
| P1-6 | CLI 只有 3 条 URL 解析单测，无端到端回归 | `crates/slive-cli/src/url.rs` | 加 `#[ignore]` 联网用例或 `--json` 脚本断言 |

## P2 — 结构/技术债

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | Rust/Dart 双份模型靠手写翻译 | `lib/src/bridge/rust_site_models.dart` | 字段变更纳入 review；评估 FRB 类型 typedef |
| P2-2 | FRB 版本锚定是隐形硬约束 | `Cargo.toml`、`pubspec.yaml` | CI 加两侧版本一致性断言 |
| P2-3 | 虎牙/Twitch 账号接口仍是桩 | `platforms/{huya,twitch}` | 先补虎牙；App 侧按平台隐藏入口 |
| P2-4 | 超时/重连策略固定（5s×5，无退避） | `ws/runner.rs`、`SessionTuning` | 提为可配置，结合前后台切换 |
| P2-5 | 弹幕无节流/背压 | 各 session `sink.add` | 可选批量/节流参数 |
| P2-6 | 抖音弹幕颜色恒白 | `platforms/douyin/danmaku/decode.rs` | 采集样本后补颜色解析 |
| P2-7 | 抖音推荐首屏池 45~65、游标会重置 | `platforms/douyin/rooms/mod.rs` | 评估扇出与游标策略 |
| P2-8 | CHANGELOG 断档 | `CHANGELOG.md` | 接口变更留条目 |
| P2-9 | core 仍依赖 Flutter SDK | `pubspec.yaml`、`foundation.debugPrint` | 改 `dart:developer` 可去依赖 |
| P2-10 | 礼物消息类型存在但无平台产出 | `models/message` | 明确产品取舍 |
| P2-11 | CLI 未进 CI、无发布产物 | `.github/workflows` | 加三平台 release job |

## 已决策取舍

- 斗鱼弹幕只收 `fans=='1'`：宁可少收不漏脏。
- 斗鱼推荐「本页非空即还有更多」：pgcnt 恒 0。
- 抖音首屏 `has_more` 恒 true：必须让 App 续接。
- TARS 手写、不用 `tars-stream`（nightly 依赖）。
- WSS TLS 分平台（桌面 native-tls / 移动 rustls，ADR-013）。
- 抖音详情/分页脏数据跳过而不整页失败。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P1-5 斗鱼临时规则 | `77eebd63`（App 侧续流中转） |
| P1-6 CLI 无回归 | `935db9e3`（CLI 引入） |
| P2-1/P2-2 双份模型/FRB 锚定 | `73e80b1e` |
| 抖音分页/推荐语义 | `49eef9c3` |
