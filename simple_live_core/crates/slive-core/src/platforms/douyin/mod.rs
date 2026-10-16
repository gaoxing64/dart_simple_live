//! 抖音(douyin)平台模块（IP-6）。
//!
//! 行为基准唯一：`simple_live_core/lib/src/platforms/douyin/`（`douyin_site.dart`
//! 1300 行 / `douyin_danmaku.dart` 239 / `abogus.dart` 732 / `xbogus.dart` 133）。
//! 模块划分沿用 B站范式（`site.rs` 仅编排 + 按能力拆文件），依赖只向下：
//! `platforms::douyin` -> `models` / `http` / `ws` / `error`，**不依赖 FRB**。
//!
//! 与 B站的三处关键差异（勿照抄 B站实现）：
//! 1. 请求 URL 需 **a_bogus 签名**（`signature` 子模块），B站是 wbi；
//! 2. 弹幕是 **protobuf over WS**（`PushFrame`），B站是 16 字节定长头 + op 码；
//! 3. 房间详情有**三段降级链路**（`web/enter` → `reflow/info` → 页面 HTML），
//!    B站只有两步；连麦房间 `web/enter` 会返回「降级骨架」，缺这一步进不去房。

pub mod account;
pub mod categories;
pub mod danmaku;
pub mod detail;
pub mod header;
pub mod play;
pub mod rooms;
pub mod search;
pub mod signature;
pub mod signing;
pub mod site;
pub mod status;
pub mod util;

pub use site::DouyinSite;
