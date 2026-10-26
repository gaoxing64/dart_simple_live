# ocr 审查结论（主编审合并稿，供日志第 6 节使用）

两轮 ocr 运行（--from future --to merge/future-to-master-20261027）因 LLM 429 限流均为部分覆盖：
第一轮 58 条（45/73 文件组失败），第二轮 24 条（59/73 失败），两轮合并去重后的有效发现如下。
所有发现均集中于 master 独有保留内容，未发现 future 侧代码问题，无合并引入的回归。

## Critical

无。

## High（9 条）

安全（master 既有 CI 配置，合并后随保留内容进入 master 树）：
- .github/workflows/publish_app_arb8.yaml:16 [security] job 只需读权限却授予 write-all，配合未钉 SHA 的第三方
  action（timheuer/base64-to-file@v1.2、subosito/flutter-action@v2），一旦 action 被投毒可直接接管仓库。建议收敛为
  contents: read 并钉 commit SHA。
- 同文件 :27 [security] 签名密钥 KEYSTORE_BASE64 经第三方 action 落盘且只钉可变 tag v1.2，存在签名密钥泄漏面。

功能（master 遗留代码与 future 演进的语义层不兼容/真实 bug，合并前在 master 上已存在）：
- simple_live_console/bin/simple_live_console.dart [bug] console 依赖旧 core API（BiliBiliSite 等）与 SDK 约束
  >=2.19.1 <3.0.0，future 侧 core 子模块已改名 RustBilibiliSite 且要求 >=3.0.5 <4.0.0，console 在合并后的树上无法编译。
- simple_live_app/lib/services/bilibili_account_service.dart:58 [bug] 对 Sites.allSites 注入的 RustBilibiliSite
  强转为 Dart BiliBiliSite，必抛运行时错误；服务未注册、账号真源已迁 DBService+PlatformService，建议删除或迁移。
- simple_live_app/lib/services/douyin_account_service.dart:14 [bug] 同样强转 RustDouyinSite 抛异常，无调用方，建议删除。
- simple_live_app/rust/Cargo.toml:10 [bug] simple_live_app/rust 为 FRB 2.11.1 时代残留 crate，与运行库 2.13.0 不一致，
  RustLib.init(forceSameCodegenVersion) 会抛错，且与 simple_live_core 的桥 crate 同名会互相覆盖；建议删除该目录及
  lib/src/rust、flutter_rust_bridge.yaml 配套残留。
- simple_live_app/lib/src/rust/frb_generated.dart:70 [bug] 同上：app 内副本生成物 codegen 2.11.1 vs 运行库 2.13.0，
  init 即抛异常，且 core 侧已有同版本绑定，属迁移后遗留。
- simple_live_app/lib/src/rust/api/danmaku_mask.dart:22 [bug] 生成的绑定与调用方不一致（缺 mergeListBatch、
  adaptiveWindow 必填参数不匹配、controller 未 import），直接编译失败；正确实现在 simple_live_core 侧。
- simple_live_app/lib/modules/live_room/danmu/danmaku_mask.dart:48 [bug] _lastShiftMs 初值 0 未做首次对齐，
  epoch 毫秒输入下 while 循环约十亿次，isolate 卡死；Rust 侧有保护，Dart 侧缺失（该纯 Dart 实现当前未被调用，属第三份实现）。

## Medium（26 条，择要）

- qr_login_page.dart:36 [bug] QRStatus.expired 分支误写为 failed，二维码过期后无刷新入口，登录流程中断（两处）。
- qr_login_controller.dart:88 [security] B 站登录 Cookie 明文写日志，凭据泄露，应删除或脱敏。
- bilibili_account_service.dart:63 [bug] 登录态只写旧 KV 不写 DB Account，登出不清 credential，出现两套登录态与"登出后自动登录"。
- deleteAllCookies 清整个 WebView cookie 库，登出 B 站连带清掉抖音会话，跨账号副作用。
- danmaku_mask.dart/rust danmaku_mask.rs [bug] 频控分支不可达（maxFrequency 恒等于 1，设置项无效）；除零/死循环未完全防护；
  isolate 失败路径缺失致永久挂起。
- .github/workflows/fork-sync.yaml [bug] GITHUB_TOKEN 推送不触发下游构建工作流（若期望"同步即构建"需 PAT）；
  rebase+force-with-lease 无并发控制。
- .github/workflows/publish_app_arb8.yaml [bug] 缺 submodules: recursive、缺 Firebase 配置注入、无 timeout、
  upload-artifact 未设 if-no-files-found: error。
- rust_builder/android/AndroidManifest.xml [bug] package 属性与 AGP 9 冲突，include 即编译失败；build.gradle 硬编码
  AGP 7.3.0/compileSdk 33 与宿主(9.0.1/37)脱节。
- assets/update-linux-metainfo.dart [bug] 正则依赖固定缩进、失败静默；无幂等去重；version 未 XML 转义；与
  scripts/update_version.dart 功能重叠且行为相反，会互相覆盖。
- 旧包名 metainfo 副本（io.github.SlotSun.dart_simple_live.metainfo.xml + .desktop）：无任何构建引用，release 停在 1.8.4，
  screenshot/license 不合规，建议删除。
- lib/app/utils/{archive,document,duration_2_str_utils,string_normalizer}.dart：extensions/ 下已有同名实现的过期副本，
  无引用死代码，建议删除。

## Low（11 条）

死代码（_editDistance、lazy_static 冗余依赖、BOM/行尾）、SPDX 标识弃用（GPL-3.0）、toJson/fromJson 字段不对称
（id_str）、扫码轮询 Toast 刷屏、截图 URL 停在 v1.7.18 等，详见 ocr-review-report 存档。

## 覆盖缺口

两轮共 45+59 个文件组因 HTTP 429 限流失败（主要是 rust_builder/cargokit、rust 残留目录的多数文件组），
本次审查为部分覆盖；cargokit 构建工具链未审。合并放行不依赖缺口部分：缺口均为 master 既有第三方工具代码。

## 处置定性

以上均为 master 既有内容的预存问题（部分为 future 演进导致的语义过时），非本次合并引入的回归。
future 侧 0 删除、0 修改，master 独有内容完整保留。建议后续单独开 issue/分支处置：删除 rust 残留与死代码副本、
修复 workflow 权限与 danmaku_mask、迁移或删除账号服务与 console。
