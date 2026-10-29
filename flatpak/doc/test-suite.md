# flatpak 测试案例库（面向 AI）

> 锚点：父仓 future `16454863`（2026-10-29）｜无自动化测试；本库是清单与产物的核验清单
> 五件套：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)
> 上游：[repo-infra](../../doc/repo-infra/test-suite.md)

## 1. 怎么跑

```bash
# 前置（Debian/Ubuntu）
sudo apt-get install -y flatpak flatpak-builder
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
git config --global protocol.file.allow always     # dir source + 嵌套 git 必需

# 构建（x86_64；aarch64 换 --arch=aarch64 且需 ARM 机器）
cd <repo-root>
flatpak-builder build-dir flatpak/flatpak-manifest.yaml \
  --arch=x86_64 --repo=x86_64 --force-clean --user \
  --install-deps-from=flathub --ccache --disable-rofiles-fuse

# 打 bundle
flatpak build-bundle x86_64 Slive.flatpak io.github.SlotSun.Slive

# 安装与运行
flatpak install --user --bundle Slive.flatpak
flatpak run io.github.SlotSun.Slive
flatpak info --show-permissions io.github.SlotSun.Slive
```

> ⚠️ 本地构建会把 `path: "../"` 指向的整个工作区拷进沙箱。本机当前 `du -sh .` = 75G，**先按 backlog P0-1 加 `skip:` 再跑**，否则极慢/爆盘。

## 2. 现测基线（2026-10-29 静态核验）

| 项 | 结果 |
| --- | --- |
| 清单行数 | 82 |
| runtime / sdk | `org.freedesktop.Platform` / `org.freedesktop.Sdk` `25.08` |
| sdk-extension | `org.freedesktop.Sdk.Extension.llvm21` |
| Flutter 钉版 | `tag: 3.47.8`，`commit: 737ba8f885dc774b53b442759999a312c9461e4e` |
| 与 pubspec 一致性 | `environment.flutter: 3.47.8` → **一致** |
| rustup 哈希 | x86_64 / aarch64 各一条，已固定 |
| finish-args | 8 条 |
| 元数据路径 | metainfo / desktop / logo 三处均存在于 `simple_live_app/assets/`；logo 实测 512×512（与 hicolor/512x512 匹配） |
| metainfo releases | 1 条（1.8.14） |

## 3. AI 用例库

### 3.1 清单静态校验（无需构建）

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-F-01 | 无 | 解析 `app-id` | `io.github.SlotSun.Slive`，且与 metainfo `<id>`、desktop 文件名三者一致 |
| TC-F-02 | 无 | 读 `runtime-version` | 存在且为受支持的 freedesktop 版本（当前 25.08） |
| TC-F-03 | 无 | 读 `sdk-extensions` | 含 llvm21（libmpv 构建/运行需要 clang 运行时） |
| TC-F-04 | 无 | 比对清单 `flutter tag` 与 `simple_live_app/pubspec.yaml` 的 `environment.flutter` | **必须相等**（当前相等；不等即 FAIL，见 backlog P0-2） |
| TC-F-05 | 同上 | 比对清单里 flutter 的 `commit` 与 `tag` | commit 必须属于该 tag（防手写错哈希） |
| TC-F-06 | 无 | 检查 `finish-args` | 至少含 `--share=network`、`--device=dri`、`--socket=pulseaudio`、`--socket=wayland`、`--socket=fallback-x11` |
| TC-F-07 | 无 | 检查是否越权 | 不得出现 `--filesystem=host`、`--filesystem=home`、`--socket=system-bus` |
| TC-F-08 | 无 | 检查 `cleanup` | 含 `*.a`、`*.la`、`/include`、`/lib/pkgconfig`、`/share/doc` |
| TC-F-09 | 无 | 检查 `sources: dir` 是否带 `skip` | 应带（当前**未带** → FAIL，backlog P0-1） |
| TC-F-10 | 无 | 检查 `build-commands` 引用的路径 | `${FLATPAK_DEST}`、`${BUNDLE_PATH}` 均已定义（后者按 arch 在 `build-options.arch` 中给值） |
| TC-F-11 | 无 | 检查元数据安装目标 | metainfo→`/share/metainfo/`；desktop→`/share/applications/`；图标→`hicolor/512x512/apps/<app-id>.png` |

### 3.2 构建与产物

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-F-20 | 环境就绪 | 跑 §1 的 `flatpak-builder` | 退出码 0；生成 `build-dir/` 与 `x86_64/` 仓库 |
| TC-F-21 | 构建成功 | `flatpak build-bundle` | 产出单个 `.flatpak` 文件，大小合理（数百 MB 级） |
| TC-F-22 | bundle 存在 | `flatpak install --user --bundle` | 安装成功，`flatpak list` 能看到 `io.github.SlotSun.Slive` |
| TC-F-23 | 已安装 | `flatpak run io.github.SlotSun.Slive` | 窗口打开，无 GL/EGL 报错（验证 `--device=dri` 与 llvm21 运行时） |
| TC-F-24 | 已安装 | `flatpak info --show-permissions` | 与清单 `finish-args` 逐条对应，无多余权限 |
| TC-F-25 | 应用内 | 进首页 → 选平台 → 打开直播间 | 取流成功、有画面有声音（验证 network/pulseaudio/dri 三者同时生效） |
| TC-F-26 | 应用内 | 开启「屏幕常亮」 | 不熄屏（验证 `ScreenSaver` talk-name） |
| TC-F-27 | 应用内 | 局域网同步页 | 能显示本机 IP 或被正确拒绝（验证 `NetworkManager.IP4Config`） |
| TC-F-28 | 应用内 | 检查「便携模式/自定义数据目录」 | Flatpak 下应不可用或明确提示（backlog P1-6） |
| TC-F-29 | 桌面环境 | 应用菜单搜索 Slive | 有图标（512×512）与名称，点击可启动 |

### 3.3 版本与元数据

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-F-30 | 无 | `appstreamcli validate simple_live_app/assets/io.github.SlotSun.Slive.metainfo.xml` | 无 error（warning 可接受） |
| TC-F-31 | 无 | 比对 metainfo `<releases>` 首条与 `assets/app_version.json` | 版本号一致（当前 1.8.14） |
| TC-F-32 | CHANGELOG 有新版本 | 跑 `dart run scripts/update_version.dart --version x.y.z` | metainfo 的 releases 覆盖 CHANGELOG 全部版本 |
| TC-F-33 | 构建产物 | `strings` 扫描 bundle 内 libmpv | 含 `loudnorm`、`aresample`（音量均衡依赖，见 libmpv KB） |

### 3.4 CI 行为

| ID | 前置 | 步骤 | 期望 |
| --- | --- | --- | --- |
| TC-F-40 | 读 release 工作流 | 检查 flatpak job 的 bundle 命名 | 以 `Slive_V` 开头（与上传 glob `Slive_*.flatpak` 匹配） |
| TC-F-41 | 读 pr.yaml | 检查是否 bundle | **不 bundle**（只构建验证） |
| TC-F-42 | 读 4 个工作流 | 检查 `flatpak-builder` 参数 | 均含 `--force-clean --user --install-deps-from=flathub --ccache --disable-rofiles-fuse` |
| TC-F-43 | 读 4 个工作流 | 检查矩阵 | `ubuntu-24.04 → x86_64`、`ubuntu-24.04-arm → aarch64` |

## 4. 建议补的自动化

| 优先级 | 用例 | 落地方式 |
| --- | --- | --- |
| P0 | TC-F-04/05 Flutter 双写一致性 | CI 里 10 行脚本：`yq` 取清单 tag vs `pubspec.yaml`，不等即失败 |
| P0 | TC-F-01 元数据三处同名 | `grep` 断言 app-id 在 3 个文件中一致 |
| P1 | TC-F-30 metainfo 校验 | `appstreamcli validate` 加入 CI（flatpak-builder 会自带 appstream 校验，需确认启用） |
| P1 | TC-F-20~23 构建冒烟 | 定时 workflow（每周）跑一次 x86_64 构建 + `flatpak run --command=… --version` 冒烟 |
| P2 | TC-F-24 权限漂移 | `flatpak info --show-permissions` 输出与基线 diff |

## 5. 已知缺口

- 本机无 flatpak/flatpak-builder，也没有 `dot`/Graphviz，本 KB 的构建类用例**均未实跑**，只做了静态核验。
- aarch64 产物无 ARM 机器可验证（与三个 libmpv KB 的同类缺口一致）。
- 无 AppStream 截图，软件中心展示为无图状态。

## 历史锚点

| 用例 | 守护的提交 |
| --- | --- |
| TC-F-04 Flutter 双写 | `ddb0cc3e`、`6847a151` |
| TC-F-40 产物命名 | `24edf9f7`（glob 回归） |
| TC-F-31/32 metainfo 版本 | `099d9c26` |
| TC-F-01 app-id 三处一致 | `543910ba` |
