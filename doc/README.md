# Slive 组件知识库总索引

> 锚点：父仓 future `16454863`（2026-10-29）
> 每个组件一套「五件套」：**流程图** / **架构与选型对照** / **Git 完整修改历史** / **待办与优化** / **面向 AI 的测试案例库**
> 注意：`doc/` 是本知识库（给人与 AI 看的内部文档），`docs/` 是 VitePress 公开文档站，两者不是一回事。

## 1. 十个组件

| # | 组件 | 知识库位置 | 锚点 | 语言/形态 |
| --- | --- | --- | --- | --- |
| 1 | **simple_live_app** 手机/桌面客户端 | [`simple_live_app/doc/`](../simple_live_app/doc/workflow-diagram.md) | 父仓 `2c1b4280` | Flutter / GetX / Hive CE |
| 2 | **simple_live_tv_app** Android TV 客户端 | [`simple_live_tv_app/doc/`](../simple_live_tv_app/doc/workflow-diagram.md) | 子仓 `263a19e` / 父仓 `c767f931` | Flutter / GetX / Hive 2 |
| 3 | **simple_live_core** 协议核心与绑定层 | [`simple_live_core/doc/`](../simple_live_core/doc/workflow-diagram.md) | 父仓 `1748611b` / 子仓 `5326f2c` | Rust workspace + FRB 2.13 + Dart 契约 |
| 4 | **media-kit** 播放器 FFI 封装（fork） | [`media-kit/doc/`](../media-kit/doc/workflow-diagram.md) | `917d80ca` | Dart/Flutter 包 + libs 二进制 |
| 5 | **libmpv-win32-video-cmake** Windows libmpv 构建 | [`libmpv-win32-video-cmake/doc/`](../libmpv-win32-video-cmake/doc/workflow-diagram.md) | `8021dd5` | CMake + LLVM 自建工具链 |
| 6 | **libmpv-darwin-build** macOS/iOS libmpv 构建 | [`libmpv-darwin-build/doc/`](../libmpv-darwin-build/doc/workflow-diagram.md) | `42c6cce` | Nix / flakelight |
| 7 | **libmpv-android-video-build** Android libmpv 构建 | [`libmpv-android-video-build/doc/`](../libmpv-android-video-build/doc/workflow-diagram.md) | `acf64b0` | NDK + Gradle 壳 |
| 8 | **repo-infra** CI / 发布链 / 脚本 / 版本资产 | [`doc/repo-infra/`](./repo-infra/workflow-diagram.md) | 父仓 `16454863` | GitHub Actions + Python/Dart 脚本 |
| 9 | **docs-site** 公开文档站（VitePress + ADR 库） | [`doc/docs-site/`](./docs-site/workflow-diagram.md) | 父仓 `16454863` | VitePress 2 alpha + pnpm |
| 10 | **flatpak** Linux 分发 | [`flatpak/doc/`](../flatpak/doc/workflow-diagram.md) | 父仓 `16454863` | flatpak-builder 清单 |

## 2. 五件套对照

| 文件 | 回答什么问题 |
| --- | --- |
| `workflow-diagram.md` | 这个组件的**运行时/构建链路**怎么走？失败点在哪、兜底是什么？ |
| `architecture.md` | **分层与依赖**是什么？关键**选型**的理由与代价？和别的组件怎么衔接？ |
| `update-history.md` | 一条条**可复现的 Git 时间线**（附 `git log` 命令），谁在什么时候改了什么。 |
| `backlog.md` | 已知的**缺陷、优化、技术债**，带证据文件与建议动作，分 P0/P1/P2。 |
| `test-suite.md` | 面向 AI 的**文字版用例库**（前置/步骤/期望），含怎么跑、现测基线、缺口。 |

## 3. 依赖方向

```
              ┌──────────── repo-infra（CI / 发布 / 版本资产）
              │                 │
simple_live_app ──┐        docs-site（公开文档站）
simple_live_tv_app┼──→ simple_live_core ──→ 直播平台 API / WSS
              │   └──→ media-kit ──→ libmpv 二进制
              │                          ├─ libmpv-win32-video-cmake
              │                          ├─ libmpv-darwin-build
              │                          └─ libmpv-android-video-build
              └────────→ flatpak（Linux 分发，消费 App 的 Linux 产物）
```

## 4. 跨组件高频条目

| 主题 | 位置 |
| --- | --- |
| 音量均衡依赖自建 libmpv（缺 `loudnorm` 即静音） | app P0-1、media-kit P0-2、三个 libmpv P0-2 同类 |
| 三平台二进制能力需对齐（AV1 / loudnorm / stats.lua） | media-kit P1-5、android/darwin/win32 的「本轮了结」 |
| 版本号多源不一致（CHANGELOG / app_version.json / pubspec） | repo-infra P0-1、flatpak P1-4 |
| Flutter 版本双写（清单 vs pubspec） | flatpak P0-2、repo-infra P1-3 |
| CI 零测试（7 个工作流只构建） | repo-infra P0-3 |
| 子仓化后的哈希换算 | tv update-history §5、core update-history §4 |

## 5. 维护约定

1. **锚点是契约**：每份文档头部写「锚点：某提交」。功能提交后同步把相关内容跟到新锚点，而不是等攒一批。
2. **结论必须带证据**：文件路径 + 行号，或提交哈希。没有证据的判断写进「未知/需验证」，并标置信度（范式见 `docs/architecture/system-model.evidence.md`）。
3. **历史只追加**：`update-history.md` 不重写既有条目；口径变化写进「本轮了结」或注明「已解决」。
4. **待办要能动手**：每条给「现象 / 证据 / 建议」三列，避免只写「需要优化」。
5. **测试库要可执行**：给命令与期望值；没实跑过的用例在「已知缺口」里明说。

## 6. 相关但不在本索引内

| 路径 | 说明 |
| --- | --- |
| `docs/` | VitePress 公开站（指南 / 架构视图 / ADR / rust-core 阶段档案），另有 [docs-site KB](./docs-site/architecture.md) |
| `docs/rust-core/` | 2026-10 的 Rust 化阶段档案，属历史快照，结论以 ADR-014 / ADR-016 为准 |
| `deliverables/` | 不入库的本地交付物（截图、录屏、分析脚本） |
