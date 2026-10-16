# Rust Core 落地 · 验收报告（Phase 4）

> 日期：2026-10-16 ｜ 分支：`feat/core-rust`（基线 `4dcdb4fe` = future）
> 结论：**DoD-1 ~ DoD-8 全部达成**，issue #155 第一步「Rust Core 落地（骨架 + B站端到端）」交付。
> **2026-10-17 补注**：本表为 **B站阶段**验收快照；此后已扩展至五平台 + 六轮真机修复
> （见 `21-delivery-summary.md`）。原 `evidence-*.log` 在交付整理时移除（66 个，结论保留于
> 本文与 21 文档）；「提交轨迹」更新为交付整理后的 4 笔结构化提交；DoD-5/6 表述按
> 2026-10-17 口径修订（运行时回退 / AC-39 传输依赖例外）。

## DoD 核对

| DoD | 结论 | 证据 |
|-----|------|------|
| **DoD-1 构建** | ✅ workspace `cargo build`/`clippy` 通过；FRB `=2.13.0`（codegen `Done!`，两侧精确钉版） | 构建日志（已归档，见 21 文档） |
| **DoD-2 离线测试** | ✅ **86 passed / 0 failed**（lib 42 + 集成 44），B站阶段口径（manual_e2e 2 例为联网冒烟，`#[ignore]` 单独判定）。**交付时全量 908 passed / 0 failed** | 21 文档 §4 |
| **DoD-3 端到端** | ✅ 真实 B站（房间 6）：详情 → 清晰度 5 项 → 取流 4 条 → **WS 弹幕 30s 窗口（Ready=1、消息≥1）**；错误流（不存在房间）→ 类型化错误 `19002000`，不 panic | 21 文档 §4（真机冒烟） |
| **DoD-4 回归为零** | ✅ App `flutter test` **+549 -15**，与 `16-app-regression-baseline.md §4` 基线**逐条一致**（15 条=存量红灯）；其余 4 平台代码零改动 | 21 文档 §4 |
| **DoD-5 可回退** | ✅ `sites.dart` 单点分派，五平台开关可切回 Dart core（**运行时回退**，2026-10-17 口径修订：编译期回退不在本轮，见 AC-31） | `sites.dart`、ADR-008 |
| **DoD-6 门禁** | ✅ 单文件 ≤300 行（Rust 最大 295/Dart 最大 209）；依赖只向下；**AC-39 协议逻辑扫描为空**（无 URL/签名/解析/重试；WS 传输依赖例外见 2026-10-17 口径修订）；无 emoji 图标、无 TODO 空壳 | 本文附录扫描 + 合并前评审（2026-10-17） |
| **DoD-7 证据留痕** | ✅ B站阶段 17 份 evidence 日志已入库后于交付整理时移除（结论见 21 文档 §3/§4）；wbi golden 由**独立实现交叉验证**（QA 算法推导 + Python 第三方实现双源，AC-35） | 本目录 + 21 文档 |
| **DoD-8 规格同步** | ✅ Spec 变更记录含实测锁定与差异修订（reqwest 0.12、freezed 3.x、stop API、pending 模式、nav 口径、首心跳）；**2026-10-17 增补**：ADR-013（WSS TLS 平台分层）、AC-31/AC-39 口径修订 | `13-spec.md §13`、`ADR-013` |

## 交付物清单

**Rust 核心**（`slive-core`，零 FRB 依赖，可被 Tauri 复用）：`http`（trait + rustls）/ `time`/`ws`（FrameSource + 会话主循环）/ `wbi` / `models`（20 类）/ `platforms/bilibili`（F-01~F-22 全能力）。

**FRB 桥**（`rust/src/api/slive/`）：opaque `LiveBilibiliSite`（15 方法 + 账号三接口）+ `startDanmaku(Stream)/stopDanmaku` + 模型 mirror；cargokit 零改动。

**Dart 绑定层**（`lib/services/rust_core/`，191+209 行）：`RustBilibiliSite implements LiveSite`（类型翻译 + 转发，**零协议逻辑**）+ `RustLiveDanmaku`（回调式 ↔ Stream 适配）；`sites.dart` 单点分派 + 开关（默认关）。

**测试与验收资产**：40 条 AC（EARS）+ 86 项离线测试 + DoD-3 联网冒烟 + held-out 机制（`--features heldout` 待真实数据回填）。

## 真实网络测试的价值（记录）

DoD-3 联网冒烟暴露了 3 个离线合成夹具无法覆盖的行为差异，均已修复并对齐 Dart core：
1. **nav 匿名响应 `code=-101`** 但 `data.wbi_img` 有效 → `getWbiKeys` 不做通用 code 检查；
2. **tungstenite 手动构造 Request 不补握手头** → 改用 `IntoClientRequest` 生成后追加业务头；
3. **join 后必须立即发首个心跳**，服务端才开始推送（纯"帧间检查"会与服务端互相等待）。

## 已知边界与后续

- manual_e2e 2 例为联网测试（`#[ignore]`，手动执行），不进常规套件 —— 与 `doc/test-suite.md` §5.1「目录离线优先」口径一致；
- held-out 留出集目录已建（`fixtures/bilibili/heldout/`），真实抓包数据回填后由 `cargo test --features heldout` 判定（实现者不可见）；
- `danmaku_mask` 的 2 个 dead_code 警告为存量（非本任务引入）；
- 仓库存量漂移（7 个 hive `.g.dart`、平台注册文件过期）已在验收外登记，待单独处理。

## 提交轨迹

B站阶段的开发提交（`ac8d6385` ... `5e7f4991`）在交付整理时已 squash 重组为结构化提交，
完整交付轨迹与真机排障时间线见 [`21-delivery-summary.md`](./21-delivery-summary.md)；
原始提交历史保留在 `backup-feat-core-rust-20261017` 分支。
