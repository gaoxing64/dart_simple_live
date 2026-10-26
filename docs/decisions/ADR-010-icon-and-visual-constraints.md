# ADR-010: 图标统一 Remix Icon，禁止 emoji 作功能图标

## Status
Accepted (2026-10-16)

## Background
团队级 P0 规则：禁止用 emoji 作功能图标；Spec 必须锁定一套 SVG 图标库，全项目统一不混用。本轮为内部架构迁移、UI 零变化（AC-32），但需为项目锁定唯一图标来源，防止后续 UI 变更引入混用。

现状证据：`simple_live_app/pubspec.yaml` 依赖 `remixicon: ^4.9.3`；`lib/app/sites.dart` 使用 `RemixIcons.bilibili_line / RemixIcons.tiktok_line / RemixIcons.twitch_line`（平台图标）与自定义字体图标 `LiveIcons.douyu / LiveIcons.huya`（`assets/iconfont/live_icons.ttf`）。

## Decision
- 全项目**唯一**图标集合：**Remix Icon**（`remixicon` 包，SVG 字体/图标集），用于所有通用/功能图标。
- 平台品牌图标维持既有专用字体 `LiveIcons`（`assets/iconfont/live_icons.ttf`）——属品牌资源，不算混用；新增品牌图标一律并入该字体，不引入第二个图标包。
- **禁止** emoji 作为功能图标；禁止紫→粉渐变配色方案。
- Rust Core 本轮**不产生任何图标/视觉资产**；该约束为后续 UI 变更的锁定口径。

## Consequences
**正面**
- 单一图标来源，避免风格不一与体积膨胀；符合 P0 门禁。
- 本轮无 UI 变更，零视觉回归风险。

**负面**
- 若未来设计需要 Remix 未覆盖的图标，须走「并入 `LiveIcons`」流程，而非临时新增图标包。

## Related ADRs
无（治理类约束）
