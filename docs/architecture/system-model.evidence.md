# Slive 架构证据索引（当前状态）

> 采集日期：2026-10-28 · 复核 2026-10-29（基线 `2c1b4280`）· 基线分支：`future` · 视图：`system-context.dot`、`system-containers.dot`
> 置信度口径：high = 代码/依赖清单/ADR 直接可证；medium = 多处间接信号一致；low = 仅凭命名或目录推断。

## 1. 系统边界与角色

| 节点 | 说明 | 置信度 | 证据 |
| --- | --- | --- | --- |
| 观众 / 用户 | 移动端、桌面端、电视端使用者 | high | `README.md:26-33` |
| Slive 客户端家族 | 主 App、TV App、CLI 三个入口 | high | `README.md:66-71`、`simple_live_core/crates/slive-cli/src/main.rs` |
| 直播平台 | B站/斗鱼/虎牙/抖音/Twitch 的 HTTP API 与弹幕长连接 | high | `simple_live_core/crates/slive-core/src/platforms/mod.rs:10-17` |
| Firebase | Analytics + Crashlytics，仅 Android 初始化 | high | `simple_live_app/lib/main.dart:147-153` |
| WebDAV | 用户自建同步目标（关注、历史、设置、Cookie 等资源） | high | `simple_live_app/lib/modules/sync/remote_sync/webdav/resources/*` |
| 局域网设备 | UDP 23235 发现 + HTTP 23234 同步服务 | high | `simple_live_app/lib/services/sync_service.dart:25-26` |

## 2. 容器 / 组件

| 节点 | 职责 | 置信度 | 证据 |
| --- | --- | --- | --- |
| `simple_live_app` | 主 Flutter 客户端（Android/iOS/Windows/Linux/macOS），GetX 状态/路由，Hive CE 持久化 | high | `simple_live_app/pubspec.yaml:1-31`、`lib/main.dart:108-156` |
| `simple_live_tv_app` | Android TV 客户端，GetX + Hive 2 + media_kit | high | `simple_live_tv_app/pubspec.yaml:6-58` |
| 功能模块 | home/category/search/follow_user/live_room/settings/mine/sync | high | `simple_live_app/lib/modules/*` |
| 播放与后台音频 | media_kit fork（钉 commit）+ audio_service 0.18.19 + audio_session | high | `simple_live_app/pubspec.yaml:98-127` |
| StreamRelayService | 本地 HTTP 中转，斗鱼 300s 直链到期前续签并按 FLV tag 边界接续 | high | `simple_live_app/lib/services/stream_relay/stream_relay_service.dart:9-31` |
| `simple_live_core`（Dart） | `LiveSite`/`LiveDanmaku` 契约 + 跨平台模型 + 绑定层 + FRB 生成物 | high | `simple_live_core/lib/simple_live_core.dart:3-28`、`simple_live_core/pubspec.yaml:9-21` |
| 绑定层 `rust_*_site.dart` | 五平台 FRB 模型 ↔ Dart 模型 1:1 映射，零协议逻辑 | high | `simple_live_core/lib/src/bridge/*`、`docs/decisions/ADR-008` |
| 根 crate `rust_lib_simple_live_app` | FRB 门面（`src/api`）+ 生成物入库，构建产物供 App/TV 共用 | high | `simple_live_core/Cargo.toml:1-20`、`simple_live_core/flutter_rust_bridge.yaml` |
| `crates/slive-core` | 五平台协议、模型、DanmakuMask、心跳/重连策略；无连接、无 FRB | high | `simple_live_core/crates/slive-core/src/lib.rs:1-25`、`Cargo.toml` |
| `crates/slive-host` | 真实 WSS/明文 TCP 帧源、五平台弹幕会话装配、runtime 辅助 | high | `simple_live_core/crates/slive-host/src/lib.rs:1-11` |
| `crates/slive-ffi` | 通用 C ABI；句柄 u64、dispatcher 线程、JSON envelope；含 C++/C# 封装 | high | `docs/decisions/ADR-016-c-abi-and-host-crate.md:21-68`、`crates/slive-ffi/include/{slive.h,slive.hpp}`、`csharp/Slive.cs` |
| `crates/slive-cli` | `slive` 命令行，直连核心输出房间详情/播放直链/实时弹幕 | high | `README.md:69`、`crates/slive-cli/src/main.rs` |
| `rust_builder`（cargokit） | 五平台构建插件，包名保持 `rust_lib_simple_live_app` | high | `simple_live_core/Cargo.toml:2`、`simple_live_app/pubspec.yaml:46-47` |
| media-kit 子模块 + libmpv | 自定义 media_kit fork 与三套 libmpv 构建 | high | `simple_live_app/pubspec.yaml:98-159`、仓库根 `media-kit/`、`libmpv-*-build/` |
| 本地持久化 | App 用 Hive CE，TV 用 Hive 2 | high | `simple_live_app/pubspec.yaml:25-26`、`simple_live_tv_app/pubspec.yaml:24-25` |

## 3. 关键关系

| 从 → 到 | 关系 | 置信度 | 证据 |
| --- | --- | --- | --- |
| App/TV → `LiveSite` | 调用 | high | `simple_live_app/lib/app/sites.dart:10-48`、`simple_live_tv_app/lib/app/sites.dart:5-28` |
| `LiveSite` 实现 → 绑定层 | 实现 | high | 同上（`RustBilibiliSite()` 等直接构造，无运行时开关） |
| 绑定层 → FRB 生成物 | 调用 | high | `simple_live_core/lib/src/bridge/*`、`lib/src/rust/frb_generated.dart` |
| FRB Dart → 根 crate | FFI（dylib/静态库） | high | `simple_live_app/lib/main.dart:70`、`simple_live_core/Cargo.toml:6-8` |
| 根 crate → `slive-core` | 转发 + 会话装配 | high | `docs/decisions/ADR-016:26-31` |
| `slive-core` → 直播平台 | HTTPS(rustls) / WSS / 明文 TCP，双向 | high | `crates/slive-core/Cargo.toml:24-35`、`docs/decisions/ADR-015` |
| CLI → `slive-core` / `slive-host` | 直连（绕开 FRB） | high | `simple_live_core/doc/architecture.md:13-15` |
| `slive-ffi` → 核心/宿主 | 调用 / 组装 | high | `docs/decisions/ADR-016:21-31` |
| App → Firebase | 埋点/崩溃上报（仅 Android） | high | `simple_live_app/lib/main.dart:147-153` |
| App → WebDAV / 局域网 | 备份恢复 / 近场同步 | high | `webdav/resources/*`、`services/sync_service.dart` |

## 4. 技术栈清单

| 层 | 选型 | 证据 |
| --- | --- | --- |
| 客户端 UI | Flutter（App 钉 3.47.8；TV 钉 3.35.7）+ Material 3 + Remix Icon | `simple_live_app/pubspec.yaml:6-7`、`simple_live_tv_app/pubspec.yaml:6-8` |
| 状态/路由/国际化 | GetX（`get`，fork override 指向 SlotSun/get） | `simple_live_app/pubspec.yaml:23,129-133` |
| 持久化 | Hive CE（主 App）/ Hive 2（TV） | 同上 |
| 网络 | Dio（业务请求）+ reqwest(rustls)（核心协议） | `simple_live_app/pubspec.yaml:24`、`crates/slive-core/Cargo.toml:24-31` |
| 播放 | media_kit fork（钉 commit）+ libmpv；audio_service/audio_session 后台播放 | `simple_live_app/pubspec.yaml:96-127` |
| 跨语言桥 | flutter_rust_bridge **精确 2.13.0**（Rust 与 Dart 两侧同版本） | `simple_live_core/pubspec.yaml:16-18`、`simple_live_core/Cargo.toml:11` |
| Rust 核心 | tokio、serde、thiserror、prost、md-5、flate2/brotli、xxhash、chrono | `crates/slive-core/Cargo.toml` |
| C ABI | cbindgen 风格手写头文件（不入依赖）+ C++/C# 封装 | `docs/decisions/ADR-016:67-68` |
| 观测 | Firebase（Android）+ 自建日志（logger + CoreLog 回调桥接） | `main.dart:147-160` |

## 5. 未知与需验证项

1. **iOS/macOS 可用性**：README 标注“自测”，无 CI 证据（`README.md:29-32`）。置信度：低。
2. **Android TV 分发**：README 写明“请自行打包”，TV App 无发布产物（`README.md:33`）。置信度：高（缺产物是事实）。
3. **C ABI 宿主**：仓库内无 WinUI3/Qt 消费方，`slive.hpp`/`Slive.cs` 是能力封装而非已部署客户端（`docs/decisions/ADR-016`）。置信度：高（能力存在）/ 未知（实际使用）。
4. **文档时效性**：`docs/rust-core/10-architecture.md` 描述的是“B站先行”阶段；当前 5 平台均已 `Rust*Site()`（`sites.dart`）。以代码与 ADR-016 为准。
5. **Twitch 可见性**：已实现并注册，但 `Sites.supportSites` 过滤掉 Twitch（`simple_live_app/lib/app/sites.dart:51-56`）。属于产品开关而非架构缺失。
6. **SignalR 远端**：用于远端同步房间，服务端地址与部署方式不在仓库内（`services/signalr_service.dart`、`modules/sync/remote_sync/room/*`）。置信度：中。

## 6. 重新生成

```bash
cd docs/architecture
dot -Tsvg system-context.dot -o system-context.svg
dot -Tsvg system-containers.dot -o system-containers.svg
```

可在 Qoder Canvas 中直接打开 `.dot` 预览。若修改了包边界、crate 成员或外部依赖，请同步更新本文件与两张图。
