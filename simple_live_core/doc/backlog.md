# simple_live_core 待办与优化清单（backlog）

> 版本锚点：future `4795b165` + 2026-10-18 Dart core 清理（本版已剔除全部 Dart 实现相关条目）
> 配套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)

## 0. 使用说明

- 每条含：**现象 → 证据（file:line）→ 建议动作 → 影响面**。
- 优先级：`P0` 明确的错误或门禁红灯；`P1` 平台侧随时可能爆的脆弱点；`P2` 结构/技术债/功能缺口。
- 第 5 节记录**已决策不修**的取舍与本次已解决项，避免反复讨论。

## 1. P0 — 明确的错误 / 门禁红灯

> 当前无 P0 项（原 P0-1 夹具 CRLF 已于 2026-10-18 修复，见 §5）。

### P0-2 抖音播放地址没有刷新路径

- 现象：`get_play_urls` 不发起请求，直接回传 `get_play_qualities` 阶段组装好的地址（`platforms/douyin/site.rs` → `play::fetch_urls(self, &quality)`，只收 quality）。
- 建议：补「地址过期重取」入口（重跑 `reflow/info` 或 `web/enter`），或在 App 断流重试时强制重查详情。
- 影响：长时间挂机 / 网络切换后的恢复能力。

### P0-3 B站 wbi 密钥缓存无失效策略

- 现象：站点句柄里的 `wbi_keys` 一旦取到就长期复用（`set_wbi_keys` / `wbi_keys_cached`）。服务端轮换后，全部 wbi 签名接口持续失败直到进程重启。
- 建议：签名失败（业务错误码）时清缓存并重试一次，或给 key 加 TTL。
- 影响：B站列表 / 详情 / 弹幕信息全部链路。

## 2. P1 — 平台脆弱点

### P1-1 虎牙弹幕使用匿名固定 guid / cookie

- 现象：`platforms/huya/danmaku/tars_cdn.rs` 里 `s_guid` / `s_cookie` 是匿名固定串（与登录态无关）。
- 建议：接入匿名登录（`HuyaSite` 已有匿名 uid 基础）替换硬编码值。
- 影响：虎牙弹幕整体可用性。

### P1-2 虎牙详情依赖网页 HTML 正则

- 现象：`detail_parse.rs` 用正则从 `www.huya.com/{roomId}` 抠 `TT_ROOM_DATA` / `stream` JSON。
- 建议：优先找稳定的 JSON 接口替代；短期给正则加「解析失败」告警，便于快速定位改版。
- 影响：虎牙详情 / 清晰度 / 取流全链路。

### P1-3 抖音 abogus / x_bogus 是风控对抗

- 现象：固定 `aid=6383`、UA 指纹、路径白名单、双 base64 字母表（`platforms/douyin/signature/`）。
- 建议：签名失败加统一埋点与用户可读提示；评估自部署签名服务方案。
- 影响：抖音分区 / 推荐 / web-enter / 弹幕握手。

### P1-4 虎牙 VIP 房间名单硬编码

- 现象：`platforms/huya/vip_room_id.rs` 维护 100+ 房间号；4K 档位对这些房间直接跳过，HDR 档位无条件跳过。
- 建议：把「跳过」升级为对用户可见的档位说明，并给名单加更新来源/日期戳。
- 影响：虎牙高画质用户预期。

### P1-5 斗鱼游客 / 海外链路依赖临时规则

- 现象：游客流只能存活 5min；海外 `@expire=300 & fcdn=ws` 追加 `&expire=0`（`platforms/douyu/play.rs`，上游标注 temp）；cookie 续期依赖 `safeAuth` + JWT exp。
- 现状：App 侧已用 `StreamRenewContext` + 本地中转做 FLV tag 级接续，断流不再要求用户配 cookie。
- 建议：跟踪 `expire=0` 的正式方案；续流落地后可择机验证删除该兼容分支。
- 影响：斗鱼非登录 / 海外场景稳定性。

### P1-6 CLI 没有自动化的端到端回归

- 现象：`crates/slive-cli` 只有 3 条 URL 解析单测；`info` / `danmaku` 的真实链路只能手工跑。
- 建议：加一个 `#[ignore]` 的联网用例（固定房间 + 超时断言输出含「房间号：」），CI 里按需触发；或给 CLI 加 `--json` 便于脚本断言。
- 影响：CLI 是 Dart console 的替代品，缺回归意味着协议改版时它最先坏而无人知。

## 3. P2 — 结构 / 技术债 / 功能缺口

### P2-1 双份模型靠手写翻译维持

- 现象：Rust `models/*` 与 Dart `lib/src/model/*` 是同一套数据的两种声明，靠 `lib/src/bridge/rust_site_models.dart` 手写 1:1 翻译。新增字段要改三处（Rust 模型 → FRB codegen → Dart 模型 → 翻译函数）。
- 建议：字段变更时把「翻译函数」纳入 review checklist；中长期评估把 Dart 模型替换为 FRB 生成类型的 typedef。
- 影响：加字段的边际成本；漏翻译会在运行时空值/默认值。

### P2-2 FRB 版本锚定是隐形硬约束

- 现象：`Cargo.toml` 与 `pubspec.yaml` 都写 `=2.13.0`。版本漂移不会编译报错，而是运行时 `RustLib.init()` 抛异常。
- 建议：在 CI 加一条「两侧版本一致」的 grep 断言。
- 影响：升级 FRB 时最容易踩的坑。

### P2-3 账号能力在 huya / twitch 仍是桩

- 现象：huya 的 `get_qr_code` / `get_qr_poll_result` / `get_account_info`、twitch 的全部账号接口 + `set_site_attrs` 返回 `InvalidInput`（含「Dart core 亦未实现」后缀）。
- 建议：优先补 huya（已有匿名 uid 基础）；补齐前 App 侧按平台隐藏登录入口。
- 影响：这两个平台的账号功能不可用。

### P2-4 网络与重连策略固定

- 现象：HTTP 超时固定，无重试；WS 断线 5s × 5 次固定，无指数退避、无「网络恢复立即重连」。
- 建议：把重连次数/间隔提为可配置（`SessionTuning` 已具备结构），结合 App 前后台生命周期切换策略。
- 影响：弱网体验。

### P2-5 弹幕无节流 / 背压

- 现象：每条消息直接 `sink.add` / 回调，大房间刷屏由消费方自行处理。
- 建议：给会话加可选的批量/节流参数（默认关闭）。
- 影响：超人气房间的 UI 压力。

### P2-6 抖音弹幕颜色恒白

- 现象：`platforms/douyin/danmaku/decode.rs` 三处 `LiveMessageColor::white()`，未解析服务端颜色字段。
- 建议：采集样本逆写颜色语义后补齐。
- 影响：抖音弹幕渲染表现力（不影响功能）。

### P2-7 抖音推荐流容量与游标语义

- 现象：feed 首屏池仅 45~65 间、并发 6 路饱和；第 1 页会重置续接游标。
- 建议：若「下拉刷新后重复感强」，评估首屏扇出与游标重置策略；容量本身是服务端限制。
- 影响：推荐流观感。

### P2-8 CHANGELOG 断档

- 现象：`CHANGELOG.md` 只有 1.1.0 / 1.0.0 两条（历史随重写丢失）。
- 建议：以后每次接口变更都留条目；历史用 `doc/update-history.md` 代偿。
- 影响：版本可追溯性。

### P2-9 core 仍依赖 Flutter SDK

- 现象：`pubspec.yaml` 依赖 `flutter: sdk`（绑定层用 `foundation.debugPrint`）。这意味着 core 不能作为纯 Dart 包发布。
- 建议：把 `debugPrint` 换成 `dart:developer` 的 `log`，即可去掉 Flutter 依赖；但 App/TV 侧不受影响，属可选优化。
- 影响：`simple_live_core` 作为独立包复用的可能性。

### P2-10 礼物消息未支持

- 现象：`LiveMessageType::Gift` 存在但无平台产出。
- 建议：明确产品取舍；要做需要各平台礼物模型 + 渲染协议，工作量大。
- 影响：功能缺口（非缺陷）。

### P2-11 CLI 未进 CI、未做发布产物

- 现象：`.github/workflows` 里没有 `slive-cli` 的构建/上传 job；目前只能本地 `cargo build`。
- 建议：加一个 `cargo build -p slive-cli --release` 的 job（Windows/Linux/macOS 三平台），产物命名沿用既有 `{产品名}_V{版本}_{平台}_...` 规范。
- 影响：CLI 的可分发性（Dart console 时代曾发布过 `simple_live.exe`）。

## 4. 建议的推进批次

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 1 | P2-2（CI 版本断言）+ P1-6（CLI 回归） | 低成本护栏，防止隐形回归 |
| 2 | P0-2 / P0-3 | 用户可见的恢复能力，改动局部 |
| 3 | P1-1 ~ P1-5 | 平台对抗类，需真机/真号验证，建议成组做 |
| 4 | P2-1 / P2-9 / P2-11 | 结构性整理，配合下一次接口变更 |

## 5. 已决策的取舍与已解决项

| 取舍 / 项 | 原因 | 来源 |
| --- | --- | --- |
| **【已解决】** Twitch 夹具 8 条红灯 | `.gitattributes` 的 `* text=auto` 把 `.bin` 当文本：Windows checkout 转 CRLF（7 条），且 `irc-crlf-boundary.bin` 在历史提交时丢了 `0d`（第 8 条）。修法：加 `*.bin binary` + 删除夹具重新 checkout + 按 `bytes_hex` 重建那一个 bin。现 **918/918 全绿** | 2026-10-18 |
| 斗鱼弹幕只看 `fans=='1'` 的发言 | 斗鱼不返回人气值、部分房间有「阴间弹幕」；宁可少收不漏脏 | `platforms/douyu/danmaku/parse.rs` |
| 斗鱼推荐「本页非空即还有更多」 | 服务端 `pgcnt` 恒为 0，只能退化判据；App 侧跨页去重兜底 | `platforms/douyu/rooms.rs` |
| 抖音首屏 `has_more` 恒 true | feed 翻不动页，必须让 App 走到续接页 | `platforms/douyin/rooms.rs` |
| 虎牙闭播也给弹幕参数兜底 | App 会无条件 `start`，避免空安全崩溃 | `platforms/huya/detail_parse.rs` |
| TARS 手写而非用 `tars-stream` | 后者依赖 nightly `specialization`，stable 编不过 | `docs/rust-core/17-tars-module.md` |
| WSS TLS 分平台 | 斗鱼弹幕对 rustls ClientHello 指纹风控，仅桌面 native-tls 放行 | ADR-013 |
| **【已解决】** Dart core 平台实现 | 2026-10-18 删除 34 文件 / 15,286 行，含 proto 与 TARS | 本文件 P2-6 旧条目 |
| **【已解决】** `simple_live_console` | 由 `crates/slive-cli` 取代（直连 `slive-core`，不经 FRB），原 Dart console 整目录删除 | 2026-10-18 |
| **【已解决】** `assets/js/*.js` 保留决定 | JS 引擎方案早已废弃，Rust 侧 abogus/x_bogus 已完整实现，资产无引用，随清理删除 | 2026-10-18 |
| **【已解决】** B站 `setSiteAttrs` 桩 | 上游 `57d8f86d` 改为 JSON 取 `cookie` 键，Rust 侧 `set_site_attrs` 已实现 | `ac_attrs_golden` |
| **【已解决】** `_isVipRoom` 未使用字段 | Dart 实现已删除，Rust 侧 `vip_room_id.rs` 是显式名单 | 2026-10-18 |
| **【已解决】** douyin `_cookie` 方案分叉 | Dart 实现已删除，Rust 侧 `set_site_attrs` 直接写 header cookie | 2026-10-18 |
