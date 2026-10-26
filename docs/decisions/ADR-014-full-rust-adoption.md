# ADR-014: 全面采用 Rust core —— 开关移除 / 绑定层下沉 / TV 迁移

## Status
Accepted (2026-10-17) · **Implemented (2026-10-18)**

## Background
Rust Core 化前 13 个 ADR 落地后（骨架 + 五平台迁移 + 四平台绑定层集成），`Constant.kUseRust*`
五个运行时开关已全部翻 true（体验版默认 Rust 路径），真机链路验证通过。ADR-008 约定的「回退
窗口」到期，用户决策：**清理 Dart core、全面采用 Rust core**。

遗留三个硬耦合：① 主 App 的开关与二元分派；② 绑定层 + FRB 生成物 + cargokit 插件散在
`simple_live_app/`，TV app 与 console 无法共用；③ Dart core 五平台实现成为死代码，但
`simple_live_console`（纯 Dart CLI）与 `simple_live_tv_app` 仍直接实例化 Dart sites。

## Decision
1. **移除运行时开关**：删 `Constant.kUseRust*`（5 个）与 `sites.dart` 的三元分派，五平台
   直连 `Rust*Site()`；ADR-008 回退窗口标记关闭。
2. **绑定层下沉 `simple_live_core`**（git mv 保历史）：
   - `simple_live_app/lib/services/rust_core/**` → `simple_live_core/lib/src/bridge/**`；
   - `simple_live_app/lib/src/rust/**`（FRB 生成物）→ `simple_live_core/lib/src/rust/**`；
   - `simple_live_app/flutter_rust_bridge.yaml` → `simple_live_core/`（`rust_root: .`）；
   - `simple_live_app/rust_builder/`（cargokit）→ `simple_live_core/rust_builder/`。
   - 库出口：`simple_live_core.dart` 导出 5 个绑定层 + `RustLib` + `DanmakuMask`；
     **不导出** FRB `CoreError`（与 Dart core 同名，双导出致编译期歧义，实测
     `douyin_site.dart` 两处 import 撞名）——消费方深导入 + App 侧
     `implementation_imports: ignore`。
3. **TV app 切 Rust**：pubspec 增 `rust_lib_simple_live_app`（path 指向 core 的
   rust_builder）；`sites.dart` 四站点直连；`main.dart` 补 `await RustLib.init()`。
4. **Dart core 清理（受 console 保留制约，分两步）**：
   - 本轮：删 `lib/src/platforms/twitch/`（消费者归零）；`bilibili_emoticon.dart` 经核查被
     Dart 弹幕实现引用（console 路径）**保留**；common 工具全部仍在留平台引用，**保留**。
   - 下轮（console 迁移后）：剩余 4 平台 Dart 实现 + common + tars/proto + 相关 pubspec
     依赖（dio/protobuf/brotli/crypto/dart_sm/fixnum/tars_dart 等）+ Dart 测试一次性整删。
5. **console 暂留 Dart 路径**（用户决策，下轮处理）。注意其 SDK 约束（`<3.0.0`）与本包
   （`>=3.0.5`）已冲突，当前本就无法 `pub get`，属既存死代码；保留不增加新坏债。

## Implementation (2026-10-18)

决策 4 的「下轮」已执行，且 console 处理方式由用户重新决策为「先写 Rust CLI 再删」：

- 新增 `crates/slive-cli`（bin `slive`）：只依赖 `slive-core`，不经 FRB；`info` 输出详情/清晰度/直链，
  `danmaku` 持续打印弹幕。端到端已在 B站真实房间验证。
- 删除 `simple_live_console/`（整目录，125 行）：其 SDK 约束 `<3.0.0` 与 core 早已冲突，属死代码。
- 删除 `lib/src/platforms/**`（34 文件 / 15,286 行）、`lib/src/common/` 的 8 个 HTTP/WS 工具、
  `packages/tars_dart`（26 文件）、`test/*.dart`（9 个）、`assets/js`、`example/`。
- `lib/simple_live_core.dart` 去掉 8 条 export；`pubspec.yaml` 依赖收敛为
  `flutter` + `flutter_rust_bridge` + `freezed_annotation` + `logger`。
- 绑定层的 `_argsToJson` 兼容分支随 Dart args 类一并删除，`start(args)` 现在只接受
  `detail.danmakuData` 的 JSON 串（传其他类型抛 `ArgumentError`）。
- 验证：`core/app/tv` 三个包 `flutter analyze` 均 0 error；`cargo test -p slive-core` 918/910（8 条为
  Twitch 夹具 CRLF 既有红灯，非本次引入）。

## Consequences
**正面**
- 主 App / TV app 共用同一 crate、同一份 FRB 生成物、同一套绑定层——「一套 Rust core，多前端」形态成立。
- 主 App 代码路径去开关化，`sites.dart` 回归纯注册表。
- Dart core 死代码从「五平台全量」收缩到「console 所需子集」，下轮可整包删除。

**负面**
- `simple_live_core` 的 Dart 包自此依赖 Flutter（`flutter_rust_bridge` 运行库）——console
  （纯 Dart）的解体因此更依赖下轮迁移；已接受。
- TV app 钉 Flutter 3.35.7：Windows 本地构建受 VS 生成器环境限制（默认 VS2019，本机仅
  VS18），与本次改动无关，由 TV Android 构建 + CI 覆盖。

## Related ADRs
ADR-001（workspace 结构，含二次迁移记录）、ADR-002（FRB 版本与集成）、
ADR-008（分派与开关，回退窗口关闭）
