# flatpak 架构与选型对照

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：Flatpak 分发（清单 + 沙箱 + 元数据 + CI job）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[repo-infra](../../doc/repo-infra/architecture.md)｜被分发：[simple_live_app](../../simple_live_app/doc/architecture.md)

## 1. 定位

Flatpak 是本项目在 Linux 上的**第二种分发形态**（除 `.deb` / `.zip` 之外），解决「发行版库版本不一致导致 libmpv 跑不起来」的问题：运行时、SDK、Rust 工具链、Flutter SDK 全部由清单钉住，产物是一个自包含 `.flatpak` bundle。清单只有一个文件（82 行），是四平台里**代码量最小、但外部依赖最重**的组件。

## 2. 清单结构

| 段 | 内容 |
| --- | --- |
| `app-id` | `io.github.SlotSun.Slive`（与 metainfo / desktop 文件名一致） |
| `runtime` / `sdk` | `org.freedesktop.Platform` / `org.freedesktop.Sdk` `25.08` |
| `sdk-extensions` | `org.freedesktop.Sdk.Extension.llvm21`（libmpv 构建链需要 clang 21 运行时） |
| `command` | `io.github.SlotSun.Slive` |
| `finish-args` | 8 条沙箱权限（见 workflow §2） |
| `cleanup` | 8 类构建期文件 |
| `modules[0]` | `rustup`：装 minimal profile 到 `/var/lib/rustup` |
| `modules[1]` | `Slive`：`flutter build linux --release` + 装元数据 |

## 3. 关键选型

| 选择 | 现状 | 理由 / 代价 |
| --- | --- | --- |
| 用 Flatpak 而非 AppImage | 官方 runtime + 沙箱 | 系统集成（桌面入口、图标、权限）标准化；代价是清单与 runtime 版本绑定 |
| `buildsystem: simple` | 手写 `build-commands`，不用 flutter 专用构建器 | 完全可控；代价是每次 Flutter 变更要人工核对命令 |
| Flutter 用 `type: git` 拉源码 | `tag: 3.47.8` + `commit: 737ba8f…` | 可复现；代价是**与 `pubspec.yaml` 的 `environment.flutter` 双写**，无自动校验 |
| 应用源码用 `type: dir` `path: "../"` | 直接把工作区目录树作为源 | 简单，不需要打包 tarball；代价是**把 build/、.git、21G/54G 构建产物一起拖进沙箱**（见 backlog P1-1） |
| rustup 单独一个 module | `rustup-init -y --profile minimal`，`CARGO_HOME=/var/lib/rustup` | 与 SDK 里可能自带的 rust 解耦；代价是构建期必须联网 |
| 关 rofiles-fuse | `--disable-rofiles-fuse` | ARM runner / 容器内无 fuse 权限；代价是失去只读校验（构建稍慢） |
| 产物形态 | `flatpak build-bundle` 出单文件 | 可直接分发、可 `flatpak install`；不分发到 Flathub 仓库 |
| 与 `.deb` 并存 | CI 同时产 deb 与 flatpak | 覆盖不同用户习惯；代价是两套 Linux 构建链都要维护 |

## 4. 沙箱权限与功能的映射

| 权限 | 支撑的功能 | 证据 |
| --- | --- | --- |
| `--share=network` | 五平台取流、弹幕、WebDAV、版本检查 | 全站网络请求 |
| `--device=dri` | libmpv 硬解与 GPU 渲染 | `player_controller.dart`（hwdec） |
| `--socket=pulseaudio` | 音频输出 | libmpv ao |
| `--socket=wayland` / `fallback-x11` | 窗口与输入 | `window_manager` |
| `--talk-name=org.freedesktop.ScreenSaver` | 屏幕常亮按路引用计数 | `services/screen_awake_service.dart` |
| `--system-talk-name=org.freedesktop.NetworkManager.IP4Config` | 局域网同步拿本机 IP | 清单注释「user settings synchronization」 |
| `--share=ipc` | 共享内存（渲染） | libmpv/GL |

**未申请**：`--filesystem` 任意路径（不读用户目录）、`--socket=session-bus`（MPRIS 用 Flatpak 默认允许的 `org.mpris.MediaPlayer2.<app-id>` 名）。因此「自定义数据目录（`data_hive_ce`）」在 Flatpak 下受沙箱限制，只能落在应用私有目录。

## 5. 元数据契约

| 文件 | 安装目标 | 生成方 |
| --- | --- | --- |
| `simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml` | `/share/metainfo/` | `scripts/update_version.dart` 重写 `<releases>`；其余手维护 |
| `simple_live_app/assets/io.github.SlotSun.Slive.desktop` | `/share/applications/` | 手维护（`Exec=io.github.SlotSun.Slive %U`） |
| `simple_live_app/assets/images/logo.png`（实测 512×512） | `/share/icons/hicolor/512x512/apps/io.github.SlotSun.Slive.png` | 手维护 |

三者文件名必须与 `app-id` 完全一致，否则桌面环境认不出应用。

## 6. 与 CI 的关系

Flatpak job 在 4 个工作流里各有一份（release / dev / future / pr），**代码几乎逐行重复**，仅「是否 bundle」「是否上传」不同。这也是 repo-infra backlog P1-1（dev/future 整文件重复）的一部分。

## 7. 风险

1. **Flutter 版本双写**：清单 `tag` 与 `pubspec.yaml` 各写一次，任一侧漏改即构建失败或行为不一致。
2. **`dir` source 全量拷贝**：本工作区 75G（`simple_live_app` 54G + `simple_live_core` 22G），本地跑 flatpak-builder 会极慢甚至爆盘；CI 是干净 checkout 所以没暴露。
3. **rustup sha256 手维护**：升级 rustup 需同时换两个架构的哈希。
4. **runtime 25.08 升级无回归**：runtime 大版本变更会改 glibc/llvm 行为，当前无冒烟用例。
5. **不上 Flathub**：用户需手动 `flatpak install ./xxx.flatpak`，且无自动更新通道。
6. **元数据 releases 只 1 条**（1.8.14），而 `CHANGELOG.md` 有 10+ 版本 —— 说明 `update_version.dart` 未在近期跑过，AppStream 版本历史不完整。

## 历史锚点

| 决策 | 提交 |
| --- | --- |
| 清单引入（含 rustup + Slive 双 module） | `543910ba` |
| Flutter 版本逐次跟进（3.44.8 → 3.47.8） | `9bdc5f10`、`542acd47`、`8b40850f`、`cb2f3a9f`、`ee085b69`、`6847a151`、`ddb0cc3e` |
| LLVM 21 SDK 扩展 | 清单 `sdk-extensions`（随 runtime 25.08） |
