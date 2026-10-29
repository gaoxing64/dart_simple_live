# flatpak 待办与优化清单

> 锚点：父仓 future `16454863`（2026-10-29）
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[test-suite.md](./test-suite.md)
> 上游：[repo-infra](../../doc/repo-infra/backlog.md)

## P0 — 会直接让构建失败或产物不可用

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P0-1 | `type: dir path: "../"` 把整个工作区当源：本地实测 75G（`simple_live_app` 54G + `simple_live_core` 22G，含 `build/`、`target/`），本地构建会极慢或爆盘；CI 干净 checkout 掩盖了这个问题 | `flatpak-manifest.yaml` 的 `sources: - type: dir, path: "../"` | 加 `skip:` 列表（`build`、`target`、`.git`、`.fvm`、`node_modules`、`deliverables`），或改用 `type: git` + 子模块 |
| P0-2 | Flutter 版本双写：清单 `tag: 3.47.8` 与 `simple_live_app/pubspec.yaml` 的 `environment.flutter: 3.47.8` 各一份，任一侧漏改即构建失败或运行时行为不一致 | 清单第 79-82 行 vs `pubspec.yaml:7` | 加校验步骤（比对两处版本，不一致即 `exit 1`）；或由脚本从 pubspec 生成清单片段 |
| P0-3 | `rustup-init` 的两个架构 sha256 手维护，升级 rustup 时漏改会在下载校验阶段失败，且报错位置在日志深处 | 清单 `modules[0].sources` 两条 `sha256` | 记录 rustup 版本号与哈希的更新流程；最好同批更新并在 PR 描述里写明 |

## P1 — 可靠性与可维护性

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P1-1 | 4 个工作流各有一份几乎相同的 flatpak job（release 版 113 行，dev/future 58 行，pr 36 行），改一处要改四处 | `publish_app_release.yml:437`、`publish_app_dev.yaml:383`、`publish_app_future.yaml:382`、`pr.yaml:169` | 抽 composite action 或 `workflow_call`，参数化「是否 bundle / 是否上传 / 目标」 |
| P1-2 | 构建期依赖网络（rustup 下载、pub get、flutter 源码 tag），`--share=network` 已在 `build-args` 里；但离线/弱网环境无法构建，且构建结果不可完全复现 | 清单 `build-options.build-args`、`type: git` | 记录「构建需联网」为已知约束；如需可复现，改用 flatpak 的源缓存（`--rofiles-fuse` 已关，缓存不生效） |
| P1-3 | runtime 25.08 大版本升级无任何回归用例；llvm21 扩展与 libmpv 预编译二进制的 ABI 兼容性未验证 | 清单 `runtime-version: '25.08'`、`sdk-extensions: llvm21` | runtime 升级时手动跑 test-suite 的 TC-F-02/03 |
| P1-4 | `metainfo.xml` 的 `<releases>` 只有 1 条（1.8.14），与 `CHANGELOG.md` 的 10+ 版本不符；AppStream 版本历史不完整，软件中心显示过时 | `simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml:41-48` | 发版流程中加入 `dart run scripts/update_version.dart`（见 repo-infra P0-1） |
| P1-5 | 未提交 Flathub，无自动更新通道；用户需手动下载安装 | 无 flathub 相关配置 | 若要上架，需补 `flathub` 仓库清单、截图、appdata 审核项；否则在 README 注明手动更新 |
| P1-6 | 自定义数据目录（`data_hive_ce`，便携模式）在沙箱内不可用：未申请 `--filesystem` | 清单 `finish-args` 无 filesystem 权限；`main.dart` 便携模式逻辑 | 明确 Flatpak 版不支持便携模式，或在设置页按平台隐藏该选项 |

## P2 — 结构

| ID | 现象 | 证据 | 建议 |
| --- | --- | --- | --- |
| P2-1 | 清单内无注释说明「为什么需要 llvm21」「为什么 rustup 单独一个 module」 | 清单全文仅 2 处注释（`# user settings synchronization`） | 关键 module 与权限各加一行理由，降低后续维护成本 |
| P2-2 | `cleanup` 列表与 `sdk-extensions` 的交互未验证：删 `*.a`/`include` 可能影响运行期需要 | 清单 `cleanup` | 每次 runtime 升级后跑一次「装完能否起播」的冒烟 |
| P2-3 | `--disable-rofiles-fuse` 关闭了只读校验，构建期间源目录被写不会被发现 | 4 个工作流的 `flatpak-builder` 命令 | 在 x86_64 runner 上尝试开启，ARM 保留关闭；两者行为差异需记录 |
| P2-4 | 无 `.flatpakref`/`.flatpakrepo` 产出，用户拿到 bundle 后无法收到更新提示 | 仅 `build-bundle` | 如需，产 `flatpakrepo` 并托管在 Release |
| P2-5 | 产物命名与其他平台一致，但 Flatpak 惯例是 `app-id-version-arch.flatpak`；当前命名不符合 Flathub 习惯 | `Slive_V…_linux-x86_64_flatpak_(zh-cn)_release_…flatpak` | 内部保持一致即可，上架 Flathub 时另行处理 |

## 已决策取舍

- 保持 `buildsystem: simple` + 手写命令，不引入 flutter 专用构建器：可控性优先。
- 保持 `type: dir` 取源码：避免维护 tarball 发布流程（代价见 P0-1）。
- 不上 Flathub：避免审核与长期维护成本，接受用户手动更新。
- 申请 `--share=network` 而非按域名细粒度开放：直播平台域名多且会变，按域名白名单不现实。

## 历史锚点

| 条目 | 来源提交 |
| --- | --- |
| P0-2 Flutter 双写 | `ddb0cc3e`（最近一次双写同步） |
| P1-6 便携模式与沙箱 | `0d26f8d3`（便携模式引入，未考虑 Flatpak） |
| P1-4 metainfo 版本滞后 | `099d9c26` 后未再跑 `update_version.dart` |
