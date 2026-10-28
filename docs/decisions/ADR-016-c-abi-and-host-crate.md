# ADR-016：宿主层拆分与通用 C ABI

- 状态：已接受
- 日期：2026-10-27
- 关联：ADR-001（纯核心边界）、ADR-008（绑定层只翻译）、ADR-013/ADR-015（TLS 与斗鱼 TCP）

## 背景

协议实现已 100% 在 `crates/slive-core`，但核心只能被 Dart 消费，原因不是协议耦合，而是缺少可复用的对外形态：

1. 没有统一门面 —— 五个 `*Site` 各自独立，CLI 与 FRB 桥各搓一遍适配层；
2. 传输层重复两份 —— `src/api/slive/danmaku.rs` 与 `crates/slive-cli/src/ws.rs` 逐行同构；
3. `DanmakuMask`（去重/合并算法）落在 FRB 桥层，非 Dart 宿主直接丢失；
4. 包强依赖 Flutter SDK（仅为 `debugPrint`）；
5. `ws/tcp.rs` 是真实 TCP 连接，却在「纯核心」里 —— ADR-001 名不副实。

目标：让 Rust / C#（WinUI 3）/ C++（Qt / MyGUI）复用同一核心，同时 Dart 侧零回归。

## 决策

### 1. 三层拆分

| crate | 职责 | 依赖方向 |
|---|---|---|
| `slive-core` | 协议、模型、`LiveSite` 门面、`DanmakuMask`、纯逻辑 | 无连接、无 FRB、无 Dart |
| `slive-host` | 真实 WS/TCP 连接、五平台会话装配、runtime 辅助、stderr logger | → slive-core |
| `slive-ffi` | C ABI、cbindgen 头、全局 runtime、dispatcher 线程 | → slive-core, slive-host |
| 根 crate | FRB 桥（Dart 入口） | → slive-core, slive-host |

`ws/tcp.rs` 迁入 `slive-host`，使 ADR-001 从「名义为真」变为「实际为真」。

### 2. `LiveSite` 门面

```rust
#[async_trait]
pub trait LiveSite: Send + Sync { /* 16 个共享方法 */ }

#[repr(i32)]
pub enum Platform { Bilibili = 0, Douyu = 1, Huya = 2, Douyin = 3, Twitch = 4 }

pub fn create_site(platform: Platform) -> Box<dyn LiveSite>;
```

平台特有方法（`huya::get_sub_categories`、`douyu::refresh_cookie`）**不进 trait** —— 保持对象安全与工厂返回类型稳定。

`impl_live_site!` 宏为五个 `*Site` 生成纯转发实现（零协议逻辑，ADR-008）。
宏必须用**路径导入**（`pub(crate) use impl_live_site;`），不能用 `#[macro_use]` —— 后者的可见性依赖模块声明顺序。

### 3. `DanmakuMask` 下沉

算法从 `src/api/danmaku_mask.rs` 迁到 `slive-core/src/danmaku/mask.rs`（剥离 4 处 `#[frb]`）。
桥层保留 **newtype 包装**而非 `pub use`：re-export 会丢掉 `#[frb(opaque)]`，将来重跑 codegen 会静默删类型。

### 4. C ABI 设计

| 决策 | 理由 |
|---|---|
| 句柄是 `u64` 而非裸指针 | 悬垂使用返回 `INVALID_HANDLE`，不是 UB；`free` 幂等 |
| 回调在**专用 dispatcher 线程**串行触发 | 宿主不必处理多线程回调；WinUI3/Qt 只需 marshal 一次 |
| `catch_unwind` **两处都要** | extern fn 体（unwinding 跨 FFI 是 UB）+ 任务 future（`JoinHandle` 会吞 panic，导致宿主 promise 永不完成） |
| `panic = "abort"` 编译期报错 | 否则所有守卫失效 |
| 字符串是 `{ptr,len}` 而非 NUL 结尾 | 日志可能含 `\0`；输入严格 UTF-8 校验，不做 lossy |
| 单一 `slive_site_call(method, args_json)` | 16 方法 × 同步/异步 = 80+ 符号，漂移面太大；且「同步网络调用」会诱使宿主在 UI 线程 `block_on` |
| 异步返回 `0` = 已受理（**恰好一次** completion） | C#/C++ 需要该保证来释放 promise |
| JSON envelope 带 `schema_version` | 宿主可做版本判断 |

不引入 `uniffi`（C++ 支持弱）或 `cxx`（不解决 C#）。
`cbindgen` **不作依赖**（不在 `Cargo.lock`）：头文件手写并入库，用 `include_str!` 做常量一致性测试。

### 5. 日志

核心 crate 用 `log::` 宏但**从不自行安装 logger** —— 由宿主决定输出。
- CLI / 桥层：`slive_host::logging::ensure_stderr_logger()`（保持原 `[前缀]` 格式，可观测性不退化）；
- C ABI：转发到宿主 `on_log` 回调。

### 6. Dart 去 Flutter 依赖

删除 `pubspec.yaml` 的 `flutter: sdk`；5 处 `debugPrint` → `CoreLog.error`。
`flutter_rust_bridge 2.13.0` 本身是纯 Dart 包，故本包变为纯 Dart 包（两个 App 仍以 `path:` 依赖它，合法）。

## 后果

**正面**
- 五个消费方共用一份核心与一份传输装配（原先三份）；
- 非 Dart 宿主获得完整能力（含 `DanmakuMask`）；
- `frb_generated.rs` 与 `lib/src/rust/` **字节不变** —— 无需重跑 codegen，两个 App 回归面接近零；
- `slive-core` 真正做到零连接、零 FRB、零 Dart。

**代价**
- 新增两个 crate（`slive-host`、`slive-ffi`）；
- C ABI 需要宿主自行把回调 marshal 到 UI 线程（已在 `slive.hpp` / `Slive.cs` 中给出钩子）；
- `slive-host` 承担 TLS 平台分层配置（桌面 `native-tls` / 移动 `rustls`），改动时须同步验证移动端构建。

## 取消与关闭

- `slive_request_cancel(id)`：在途请求登记表（`requests.rs`）持有 `watch` 发送端，任务侧 `tokio::select!` 抢先返回 `SLIVE_ERR_CANCELLED`，保证**恰好一次** completion；重复 ID → `SLIVE_ERR_BUSY`，已完成 → `SLIVE_ERR_NOT_FOUND`。
- `slive_shutdown`：取消全部在途请求 → 关闭 dispatcher 通道并 join 线程 → 在独立线程 drop runtime（避免在 runtime 上下文内 drop 触发 panic）。在回调线程内调用时只做取消并立即返回，不自我 join。
- `slive_init` 与 `dispatcher::start` 均为幂等：重复初始化不会起第二个回调线程。

## C++ / C# 封装

- `slive.hpp` 的 `Site::call` 把 promise 交给 `Runtime` 的在途表，由 `on_complete` fulfill —— future 保证会完成；`call_async` 在其上提供回调风格。
- 需先构造 `slive::Runtime`（`Site::call` 依赖它）；未构造时抛异常。
- 头文件由 `tests/cpp_header.rs` 用系统 C++ 编译器做 `-fsyntax-only` 验证（无编译器则跳过）。

## 审查修复（OCR 委托模式 + 自查）

按 OCR 规则集（Ownership/Lifetime、Unsafe 边界、Concurrency、Async 取消安全、FFI 边界）审查后修复：

| 缺陷 | 修复 |
|---|---|
| `dispatcher::stop()` 在 dispatcher 线程内会 join 自己 → **死锁** | 检测 `in_dispatcher_thread()`，回调内只关通道不 join |
| `dispatch_event` 持 `CALLBACKS` 锁调宿主回调 → 回调内调 `slive_init` 死锁 | 先克隆回调与 `user_data` 再释放锁 |
| `CALLBACKS` 用 `OnceLock` → 二次 `init` **静默沿用旧回调** | 改 `Mutex<Option<Callbacks>>`，允许更新 |
| `Callbacks` 的 `unsafe impl Sync` 含裸 `*mut c_void` | `user_data` 改 `AtomicPtr`，去掉 `unsafe impl` |
| `runtime.rs` 的 `init`/`shutdown` **锁顺序相反** → 死锁环 | runtime 与 handle 合并到同一把锁 |
| `with_mask` 在注册表锁内再取 mask 锁 → 两层锁嵌套 | `Entry::Mask(Arc<Mutex<..>>)`，先克隆 Arc 再取锁 |
| `from_slive_str` 安全契约未说明长度上界 | 补全 `# Safety`：非空、可读 ≥ len 字节、不得越界 |
| `free_slive_str` 未说明分配器兼容性 | 补全 `# Safety` + 头文件注明**不可用宿主 `free()`** |
| `slive_shutdown` 在回调内只取消请求、**不真正停止** | 统一走 `dispatcher::stop()`（已自保护）|

新增回归测试：`shutdown_from_inside_callback_does_not_deadlock`（离线触发，用 `set_site_attrs` 非法 JSON）。

## 验证

- `cargo test --workspace`：990 通过 / 0 失败（含 `slive-ffi` 的 13 单元 + 6 ABI 契约 + 5 头文件同步 + 4 取消/shutdown + 2 C/C++ 头编译）；
- `cargo clippy -p slive-core -p slive-host -p slive-ffi --all-targets`：0 告警；
- `git diff --stat src/frb_generated.rs lib/src/rust/`：空（零 codegen 漂移）；
- `dart analyze`（包内）：No issues found；
- 两个 App `flutter pub get --offline`：均成功解析。
