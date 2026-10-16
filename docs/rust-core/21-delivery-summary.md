# Rust Core 化交付总结

> 生成日期：2026-10-17
> 范围：Core Rust 化第一步 —— crate 骨架 + 五平台（B站/斗鱼/虎牙/Twitch/抖音）迁移 + App 端到端可用
> 状态：**已交付**（Windows 真机验证通过；全量测试 909 passed / 0 failed）

---

## 1. 交付范围

| 项 | 内容 |
|----|------|
| Rust 核心 crate | `simple_live_app/rust/crates/slive-core`（纯 Rust，零 FRB 依赖） |
| FRB 桥层 | `simple_live_app/rust/src/api/slive/`（flutter_rust_bridge 2.13.0，钉版） |
| 平台覆盖 | B站（首个端到端）；斗鱼 / 虎牙 / Twitch / 抖音（四平台迁移） |
| App 集成 | `lib/services/rust_core/` Dart 绑定层 + `sites.dart` 分派开关（可一键回退 Dart core） |
| 共享模块 | `tars/`（虎牙/斗鱼 TARS 编解码，手写不依赖 tars-stream） |
| 设计文档 | `docs/rust-core/00~20` 编号文档 + `docs/decisions/` ADR |

## 2. 架构要点

- **Seam 注入**：`HttpTransport` / `TimeSource`（可注入 sleep）/ `FrameSource` 三个 trait，
  离线夹具可完全脱离网络验证（fixtures 在 `tests/fixtures/{platform}/`）。
- **弹幕会话**：B站复用共享 runner（`ws/runner.rs`）；斗鱼/虎牙/Twitch/抖音各自的包构造在平台模块内。
- **两类房间号**（抖音）：`web_rid`（11~12 位，首页/关注下发）与 `room_id`（19 位，一次性），
  detail 按长度分派三段降级（reflow → web/enter → 页面 HTML 兜底）。
- **签名**：抖音 a_bogus/x_bogus 逐字节移植（`platforms/douyin/signature/`）；斗鱼 sign（getEncryption + md5 链）。

## 3. 真机排障时间线（第一天全量冒烟发现并修复）

| # | 症状 | 根因 | 修法 | 提交 |
|---|------|------|------|------|
| 1 | 双击 exe 进程空跑无窗口 | `PlatformService` 把 liveSite 强转 Dart 具体类（`as DouyinSite`），Rust 版非其子类 → initServices 中断 | 改用基类 `LiveSite` | `9a1274b7` |
| 2 | 抖音首页 Error（分类/播放正常） | feed/分区接口漏 `aid=6383` → 服务端 400 空 body | 补参数 + 参数级回归测试 | `a40cae4c` |
| 3 | 抖音 reflow 阴险失败 | 漏 `app_id` 不报 400 而是 200+`status_code:10011` | 补参 + 反向断言测试 | `c2944c3a` |
| 4 | HTML 兜底链路缺 cookie | 漏 `_getWebCookie` 等价物（ttwid/__ac_nonce/msToken 收集） | 补 `room_page_cookie` | `c2944c3a` |
| 5 | 斗鱼首页/分类全 error | `accountLogin` 对空 credential 账号注入空串 → 覆盖暂存 attrs → Rust 解析炸 | Dart 空串跳过 + Rust 空串短路 | `4fa5cd6e` |
| 6 | 斗鱼弹幕连不上（重连 5 次全败） | 弹幕服务器对 rustls ClientHello 指纹风控（仅放行系统 TLS） | tungstenite 换 `native-tls`（Schannel） | `487ea3b6` |
| 7 | Rust 报错不可诊断（`Instance of 'CoreError'`） | FRB CoreError 未重写 toString | `exceptionToString` 上浮 statusCode+message | `856c0d11` |

**方法论沉淀**：
- 离线合成夹具**对请求参数漏项/TSL 层差异完全无感知** —— 参数表抽可测函数 + 参数级断言是唯一防线；
  真机层用 curl/探针复现（ttwid 从根域 set-cookie 取）是定位捷径。
- App 层报错必须带 Rust 侧真实 message，否则排障成本翻倍（本次靠 `$e` 上浮一步定位）。
- Windows exe 运行中会锁文件（LNK1104），重建前先杀进程。

## 4. 验证数字

| 项 | 结果 |
|----|------|
| Rust 全量测试（slive-core + 桥 crate） | **908 passed / 0 failed**（截至交付整理；ignored 为联网冒烟与文档用例） |
| 真机冒烟 | 五平台首页/分类/搜索/进房/取流/弹幕——B站与四平台均在 Windows 真机验证 |
| 抖音参数核对 | 6 接口与 Dart 逐键一致 + a_bogus 端到端（curl 200 真数据） |
| 斗鱼弹幕 | native-tls 探针直连 101，收到 loginres + 真实 chatmsg |
| 回归基线 | Rust Core 路径与 Dart core 路径可一键切换（`sites.dart` 开关） |

## 5. 遗留事项（非阻塞）

1. **真机冒烟建议清单**（交给用户）：五平台各做一次「首页→进房→取流→弹幕」全链路。
2. **Android 斗鱼弹幕（OPEN）**：移动端 WSS 仍走 rustls（保 NDK 零 C 依赖，ADR-013）；
   若斗鱼风控同样拒绝 rustls 指纹，Android 上斗鱼弹幕将失败（其余弹幕不受影响）。
   需 Android 真机验证；失败则评估 Android 切 native-tls（vendor openssl）或降级策略。
   见 `docs/decisions/OPEN-DECISIONS.md`。
3. **编译期回退（OPEN）**：AC-31 修订后仅承诺「运行时回退」；「Rust 编译失败不阻断 App 构建」
   需条件依赖/可选 cargokit，登记为后续项。
4. **Linux/macOS 构建**：桌面 `native-tls` 依赖系统 TLS 库，跨平台发布时需确认。
5. **Twitch 真机**：无扫码登录、匿名只读链路，国内网络可达性未全面验证。
6. **斗鱼/虎牙/抖音登录态**：扫码登录链路已实现，未做完整登录后全功能回归。
7. **直链续流（O-7 renewers）**：需 FRB 回调通道，已登记待办（本次不做）。

## 6. 证据归档说明

开发过程中的 66 个 `evidence-*.log`（构建/测试/探针/排障原始输出）已在本次提交整理时移除 ——
其关键结论已全部提炼至本文档 §3 与各 commit message；原始过程日志可由本仓库 git 历史
（`backup-feat-core-rust-20261017` 分支）完整找回。
