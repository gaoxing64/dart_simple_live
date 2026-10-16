# Spike 报告：FRB 跨 crate `#[frb(mirror)]` 可行性（ADR-007 关键路径）

> 分支 `feat/core-rust` · worktree `core-rust` · 2026-10-16
> 目的：验证 ADR-007 的**主路径**（模型定义在纯核心 crate `slive-core`、桥 crate 用 `#[frb(mirror)]` 暴露）在 FRB 2.13.0 下是否可行；不通则验证 `From` 回退路径。
> 结论依据文件：`docs/rust-core/10-architecture.md §1.3 / §3`、`docs/decisions/ADR-007`、`ADR-002`

---

## 0. 结论

**`verdict: 通（PASS）`** —— 跨 crate `#[frb(mirror)]` 在 FRB 2.13.0 下**可用**：
- `slive-core` 中**无任何 `#[frb]` 标注**的模型 `LiveRoomItem`，经桥 crate 镜像后，生成了**真正的 Dart 数据类**（非 opaque）。
- 桥 crate 的 `#[frb(opaque)]` 句柄 `LiveBilibiliSite` 正常生成，且其方法能**返回镜像类型**（`Future<LiveRoomItem> sampleRoomItem()`）。
- **采用路径：mirror（主路径）**，不启用 `From` 回退。
- **不阻塞贝洛奇开工**（解锁条件见 §6）。

---

## 1. 现状核验（`simple_live_app/rust/`）

| 项 | 现状 | 结论 |
|---|---|---|
| `rust/Cargo.toml` | 单包 `rust_lib_simple_live_app`（`crate-type=["cdylib","staticlib"]`，dep `flutter_rust_bridge="=2.13.0"`） | 可直接升级为 workspace 根 |
| `rust/Cargo.lock` | 存在（FRB 2.13.0 已解析） | 可增量更新 |
| `flutter_rust_bridge.yaml` | `rust_input: crate::api` / `rust_root: rust/` / `dart_output: lib/src/rust` | **无需改动**（`api/slive/**` 自动被扫描） |
| `rust_builder/`（cargokit） | `cargokit { manifestDir="../../rust"; libname="rust_lib_simple_live_app" }`（android/ios/macos/linux/windows 同口径） | **无需改动**（manifest 路径与 libname 均不变） |

## 2. 最小 workspace（已验证）

```toml
# simple_live_app/rust/Cargo.toml（在既有 [package] 基础上追加）
[dependencies]
slive-core = { path = "crates/slive-core" }   # 新增

[workspace]
members = ["crates/slive-core"]               # 新增；根包自动为成员
```

- 新增纯核心 crate：`rust/crates/slive-core/`（`crate-type=["rlib"]`，**零依赖**，无 FRB）。
- 桥 crate 新增 FRB 门面：`rust/src/api/slive/{mod.rs,models.rs,site.rs}`；`rust/src/api/mod.rs` 追加 `pub mod slive;`。

**cargo metadata 证据**（工作区成员解析正确）：
```
{"name":"slive-core"        / "rust_lib_simple_live_app"   # 两个成员
```
**构建产物证据**（cargokit 期望的 cdylib 正常产出）：
```
target/debug/rust_lib_simple_live_app.dll   (4,646,400 bytes)
```

## 3. `#[frb(mirror)]` 跨 crate 验证

镜像写法（FRB 2 官方 external-types 文档口径）：
```rust
// rust/src/api/slive/models.rs
pub use slive_core::models::LiveRoomItem;                 // ① 必须公开再导出

#[flutter_rust_bridge::frb(mirror(LiveRoomItem))]          // ② 占位类型 + 同名字段
pub struct _LiveRoomItem {
    pub room_id: String,
    pub title: String,
    pub cover: String,
    pub user_name: String,
    pub online: i32,
}
```
```rust
// rust/src/api/slive/site.rs
#[frb(opaque)]
pub struct LiveBilibiliSite { inner: slive_core::platforms::bilibili::BilibiliSite }
impl LiveBilibiliSite {
    #[frb(sync)] pub fn new() -> Self { .. }
    #[frb(sync)] pub fn id(&self) -> String { .. }
    #[frb(sync)] pub fn name(&self) -> String { .. }
    pub fn sample_room_item(&self) -> LiveRoomItem { self.inner.sample_room_item() }  // 返回镜像类型
}
```

**生成结果（`flutter_rust_bridge_codegen generate` 后）**

镜像生效——`lib/src/rust/api/slive/models.dart`（**真实数据类，非 opaque**）：
```dart
class LiveRoomItem {
  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final int online;
  const LiveRoomItem({required this.roomId, required this.title, required this.cover,
                      required this.userName, required this.online});
  // == / hashCode 已生成
}
```

opaque 句柄可用——`lib/src/rust/api/slive/site.dart`：
```dart
// Rust type: RustOpaqueMoi<...RustAutoOpaqueInner<LiveBilibiliSite>>
abstract class LiveBilibiliSite implements RustOpaqueInterface {
  static Future<LiveBilibiliSite> default_() => ...;
  String id();
  String name();
  factory LiveBilibiliSite() => ...;
  Future<LiveRoomItem> sampleRoomItem();   // ← 镜像类型跨 crate 流入 Dart
}
```

> 关键点：`slive-core` 侧模型**没有任何 `#[frb]` 标注**，也**没有手写 `From`**；桥层仅一次镜像声明，Dart 直接得到该类型 —— 即 ADR-007 主路径成立，且未引入上游 `45d401d8` 所清理的「多层转换」过度设计。

## 4. 真实命令与输出证据（可复现）

环境前置（本机实测）：
- Rust `rustc 1.98.0` / `cargo 1.98.0`；`rustfmt 1.9.0`。
- Flutter/Dart：`fvm` 已装 `3.47.6`（Dart 3.13.5，满足 FRB 2.13 的 Dart≥3.9.2）。
- 安装 codegen（**首次**，约 7min43s；并自动安装 `cargo-expand`，首次 generate 再花约 10min）：
  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.13.0
  ```

```
$ flutter_rust_bridge_codegen --version
flutter_rust_bridge_codegen 2.13.0

$ cd simple_live_app/rust && cargo build
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 9.47s
rc=0
warning: `rust_lib_simple_live_app` (lib) generated 1 warning   # 仅 danmaku_mask 预存在的 dead_code，与 slive 无关

$ cd simple_live_app && flutter_rust_bridge_codegen generate --no-dart-fix --no-auto-upgrade-dependency --no-deps-check
[INFO] .../fvm.rs:56 Installing Flutter version via FVM…
[INFO] .../cargo_expand/real.rs:115 Cargo expand is not installed. Automatically install and re-run.
Formatted 6 files (5 changed) in 0.03 seconds.
[WARN] .../polisher/mod.rs:126 Fail to execute_dart_format, but continue to run.
       (frb_generated.web.dart 含 `extension type`(Dart 3.3+)，格式化器解析失败；仅影响格式化，不影响内容)
Done!
rc=0

$ cargo build   # codegen 后再次构建（含新生成的 frb_generated.rs）
    Finished `dev` profile ... in 12.28s
rc=0

$ dart format --output=none lib/src/rust/api/slive/models.dart lib/src/rust/api/slive/site.dart lib/src/rust/frb_generated.dart
Formatted 3 files (3 changed) in 0.02 seconds.   # = 均可被解析（rc=0）
```

## 5. 对架构文档的影响

| 章节 | 影响 |
|---|---|
| `10-architecture.md §1.3`（目录） | 落地路径确认：workspace 根 = `simple_live_app/rust`；纯核心 = `rust/crates/slive-core`；桥 = `rust/src/api/slive/**`。**cargokit 零改动**成立 |
| `10-architecture.md §3`（模型映射表） | **mirror 主路径确认**；§3.2 的「回退到 C（显式 From）」**不启用**，但仍保留为文档中的兜底方案（不删） |
| `10-architecture.md §2`（FRB 集成） | 补充前置：codegen 需 `cargo-expand`（自动装）；Dart 侧 `dart` 需在 PATH（供格式化） |
| `ADR-007` | Status 可从「mirror 可行性待验证」升级为「**已验证通过**」（本 spike 为依据） |

## 6. 阻塞判定（对贝洛奇开工）

**不阻塞。** 可立即开工，约定如下：
- 起手即按 **mirror** 建桥层模型（`api/slive/models/*`）；每新增 core 模型需在桥层加一条镜像声明（字段必须逐一对应，否则**编译报错** —— 这是安全护栏）。
- 首个 PR 需建立「mirror 往返一致性」用例（对齐 `10-architecture.md §3.3` 的断言要求），防镜像与源字段漂移。
- 其余按 `12-bilibili-mapping.md` 推进；`From` 回退方案无须启用。

## 7. 已知产物与注意事项（实现/CI 需知）

1. **cargo-expand 依赖**：codegen 首次运行会自动安装 `cargo-expand`（耗时数分钟）；CI 应预装或缓存。
2. **dart 格式化**：codegen 会调用 `dart format`。本机无全局 `dart`，故 **generate 前将 Flutter(Dart) 的 `dart` 加入 PATH**（如 `.../versions/3.47.6/bin/cache/dart-sdk/bin`）。否则 `frb_generated.web.dart`（含 `extension type`）会触发格式化告警（`continue`，不影响生成）。
3. **cargo-expand / codegen 版本**：均须与运行库 2.13.0 对齐（`flutter_rust_bridge_codegen 2.13.0`，已验证）。
4. **既有生成物的微小 cosmetic 差异**：`generate` 重排了 `lib/src/rust/api/danmaku_mask.dart`（2 行：`allowListBatch` 换行 + 去掉一个 `@override`）与 `frb_generated.{dart,io.dart,web.dart}`、`rust/src/frb_generated.rs`（新增 slive 的 wire 函数）。均属生成物、无逻辑变更；实现阶段随首次正式生成一并提交并复核。
5. **FVM 自动动作**：codegen 首次运行打印「Installing Flutter version via FVM…」（依据 `simple_live_app/.fvmrc=3.47.6`）。过程中 `simple_live_core/pubspec.lock` 曾一度出现版本漂移，复核后已恢复为与 HEAD 一致（当前 `git status` 无该文件）。**CI 需注意隔离，避免 pub get 误改锁文件**。
6. **未做**（超出 spike 范围/受限）：未在真机或 `flutter test` 层跑通 App 侧（任务限制不改 app 代码）；App 侧编译与端到端由后续实现 + QA 覆盖。

## 8. 交付物清单

- workspace 骨架（可构建）：`simple_live_app/rust/Cargo.toml`（+`[workspace]`）、`rust/crates/slive-core/{Cargo.toml,src/**}`、`rust/src/api/slive/{mod.rs,models.rs,site.rs}`、`rust/src/api/mod.rs`。
- 生成产物：`simple_live_app/lib/src/rust/api/slive/{models.dart,site.dart}` 及更新的 `frb_generated.*`。
- 本报告：`docs/rust-core/14-spike-frb-mirror.md`。
- 无临时文件残留（spike 内建文件即正式骨架起点）。

---

## 9. 追加轮：QA 硬前提的 3 个 seam 落地

> 依据 QA 测试计划（`docs/rust-core/15-test-plan.md`）：3 个 seam 不预留则大量 AC 无法离线验证。已在骨架中以**真实代码**落地（trait + 生产实现 + 测试替身 + 单测），非占位。

| seam | 定义位置 | 生产实现 | 测试替身 | 单测 |
|---|---|---|---|---|
| #1 HTTP 传输 | `slive-core::http::HttpTransport` | `http::ReqwestTransport`（reqwest 0.12 + rustls） | `testing::RecordingTransport`（记录请求次数/参数） | `recording_transport_records_calls`（断言 2 次调用 + URL） |
| #2 WS 事件源 + 时序 | `slive-core::ws::FrameSource` + `ws::WsSessionConfig` + `time::TimeSource` | `time::SystemClock`（真实 WS 帧源随 F-11） | `testing::ScriptedFrameSource` + `testing::FakeTime` | `scripted_frame_source_plays_script` / `bilibili_config_matches_dart_core`（`5s×5`） |
| #3 wbi `wts` 时间源 | `slive-core::wbi::wbi_sign(params, img_key, sub_key, wts)`（纯函数，`wts` 入参） | — | `testing::FakeTime` | `sign_is_deterministic_and_hex32` / `sign_varies_with_wts` |

**注入点**：`BilibiliSite::with_deps(http: Arc<dyn HttpTransport>, time: Arc<dyn TimeSource>)`（测试）/ `BilibiliSite::new()`（真实实现）。单测 `site_accepts_injected_seams` 证明注入生效。替身经 `--features testing` 暴露给集成测试。

**实测**（`cargo test -p slive-core`）：
```
running 11 tests
... (http/wbi/ws/testing/site 共 11)
test result: ok. 11 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
rc=0
```

**新增依赖**（`slive-core/Cargo.toml`，均已缓存）：`async-trait`、`thiserror`、`md-5`、`reqwest 0.12`（`default-features=false, features=["rustls-tls"]`）；dev：`tokio`。
> 版本说明：ADR-003 原记「reqwest 0.11（DTV 口径）」，实际取 **0.12**（0.11 偏旧；0.12 rustls 支持稳定且本机已缓存）。ADR-003 的「rustls/纯 Rust 后端」结论不变。

**未决（QA advisory G-4）**：`search_type=live_user` 的 `is_live` 类型待核实；Rust 侧**显式容错**（int/bool 归一化），**不照抄** Dart 的裸赋值 —— 已登记 `12-bilibili-mapping.md` F-05 注记 + `10-architecture.md §4.2`。

**对文档的影响**：`10-architecture.md` 新增 §1.5（seam 总表）与 §4.2（可测试性契约）；§1.3 crate 树补 `time.rs`/`http.rs`/`testing.rs`/`ws/mod.rs`。
