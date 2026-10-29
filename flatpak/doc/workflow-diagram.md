# flatpak 工作流程图

> 锚点：父仓 future `16454863`（2026-10-29）｜范围：`flatpak/flatpak-manifest.yaml` + 四个工作流中的 flatpak job + 桌面元数据
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[repo-infra 发布链](../../doc/repo-infra/workflow-diagram.md)｜被分发：[simple_live_app](../../simple_live_app/doc/workflow-diagram.md)

## 1. 一次构建的主链

```
CI 触发（release tag v* / dev push / future push / PR）
  → apt 装 flatpak + flatpak-builder；flatpak remote-add --user flathub
     git config --global protocol.file.allow always     # dir source 需要
  → flatpak-builder build-dir flatpak/flatpak-manifest.yaml \
        --arch=x86_64|aarch64 --repo=<arch> --force-clean --user \
        --install-deps-from=flathub --ccache --disable-rofiles-fuse
         │
         ├─ module 1：rustup（simple）
         │     ./rustup-init -y --profile minimal --no-modify-path
         │     CARGO_HOME=RUSTUP_HOME=/var/lib/rustup
         │     build-args: --share=network
         │
         └─ module 2：Slive（simple）
               先装 sources：
                 - type: dir, path: "../"                 # 整个仓库
                 - type: git, flutter 3.47.8（commit 737ba8f…）→ dest: flutter
               env：BUNDLE_PATH（按 arch）、PUB_CACHE、append-path 加 rustup/llvm21/flutter
               build-commands：
                 cd simple_live_app && flutter build linux --release
                 cp -av ${BUNDLE_PATH}/* ${FLATPAK_DEST}/bin
                 install metainfo.xml / logo.png(512) / .desktop
  → flatpak build-bundle <repo> "Slive_V…_linux-<arch>_flatpak_(zh-cn)_release_<n>_(Build<ts>).flatpak" io.github.SlotSun.Slive
  → upload-artifact（dev/future/pr）或 Upload Release（release）
```

证据：`flatpak/flatpak-manifest.yaml`；`.github/workflows/publish_app_release.yml:437-550`；`publish_app_dev.yaml:383-441`；`publish_app_future.yaml:382-440`；`pr.yaml:169-205`（PR 只构建、不 bundle、不上传）。

## 2. 沙箱与权限

```
finish-args:
  --share=ipc
  --socket=fallback-x11 / --socket=wayland      # 桌面显示
  --socket=pulseaudio                            # 音频
  --share=network                                # 直播流 + WebDAV + 更新检查
  --device=dri                                   # GPU 硬解（libmpv → EGL/GL）
  --talk-name=org.freedesktop.ScreenSaver        # 屏幕常亮（screen_awake_service）
  --system-talk-name=org.freedesktop.NetworkManager.IP4Config   # 局域网同步取本机 IP
```

`cleanup` 掉 `*.a/*.la/include/lib/cmake/lib/pkgconfig/man/share/man/share/doc/share/gtk-doc`，只留运行期需要的文件。

## 3. 两条版本钉线

```
flatpak-manifest.yaml:  flutter tag 3.47.8 / commit 737ba8f885dc774b53b442759999a312c9461e4e
                        ↕ 必须同步
simple_live_app/pubspec.yaml:  environment.flutter: 3.47.8

flatpak-manifest.yaml:  rustup-init 的 sha256（x86_64 / aarch64 各一份）
                        ↕ 独立于 Flutter，需单独刷新
```

`main.dart` 侧无任何 Flatpak 分支，应用代码对沙箱无感知。

## 4. 元数据装配

```
simple_live_app/assets/
  io.github.SlotSun.Slive.metainfo.xml  → /share/metainfo/            （AppStream，含 releases）
  io.github.SlotSun.Slive.desktop       → /share/applications/
  images/logo.png（512×512）            → /share/icons/hicolor/512x512/apps/io.github.SlotSun.Slive.png
```

`metainfo.xml` 的 `<releases>` 由 `scripts/update_version.dart` 从 `CHANGELOG.md` 重写（见 [repo-infra](../../doc/repo-infra/workflow-diagram.md) §5）。

## 5. 产物去向

| 工作流 | 是否 bundle | 去向 |
| --- | --- | --- |
| `publish_app_release.yml` | 是 | GitHub Release（`Slive_*.flatpak`） |
| `publish_app_dev.yaml` | 是 | Actions Artifacts（`linux-flatpak-<arch>`） |
| `publish_app_future.yaml` | 是 | Actions Artifacts |
| `pr.yaml` | **否**（只跑到 `flatpak-builder`） | 无 |

矩阵：`ubuntu-24.04` → `x86_64`，`ubuntu-24.04-arm` → `aarch64`。

## 6. 失败与兜底

| 失败点 | 表现 | 兜底 |
| --- | --- | --- |
| Flutter tag 与 pubspec 不一致 | 编译报 SDK 版本不满足 / 行为差异 | 无自动校验，靠人工（backlog P0-2） |
| `dir` source + 嵌套 git | `protocol.file.allow` 未设时报 `transport 'file' not allowed` | CI 里已 `git config --global protocol.file.allow always` |
| rofiles-fuse 不可用（容器/ARM runner） | 构建直接失败 | `--disable-rofiles-fuse` |
| 构建期需要拉依赖 | rustup/pub/flutter 均需网络 | `build-args: --share=network` |
| 产物名 glob 不匹配 | Release 附件为空（历史事故） | 上传 glob 与命名规范同批改（`24edf9f7`） |
| 本地构建把 75G 工作区塞进沙箱 | 极慢或磁盘爆 | 见 backlog P1-1（应加 `skip:`） |

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| 清单初版 | `543910ba` |
| Flutter 3.47.0 / 3.47.1 / 3.47.2 / 3.47.4 / 3.47.6 / 3.47.8 逐次跟进 | `542acd47`、`8b40850f`、`cb2f3a9f`、`ee085b69`、`6847a151`、`ddb0cc3e` |
| Flutter 3.44.8 | `9bdc5f10` |
| 斗鱼 cookie 相关（同步改清单） | `b492f965` |
