# ADR-015: 斗鱼弹幕统一走明文 TCP（`danmuproxy.douyu.com:8601`）

## Status

Accepted (2026-10-25)，**Supersedes ADR-013**（WSS 的 TLS 平台分层）。

## Background

ADR-013 把 WSS 的 TLS 后端按平台分层：桌面 `native-tls`、移动 `rustls`，并把
「Android 斗鱼弹幕是否可用」登记为 OPEN 项。

2026-10-25 真机复现（Android 1.8.15，**未配置斗鱼 cookie**）：

- App 聊天区只有「开始连接弹幕服务器」+「与服务器断开连接，正在尝试重连(1..5)」，
  失败点在连接阶段，与登录态无关；
- 手机**系统 TLS** 访问 `https://danmuproxy.douyu.com:8506/` 正常（curl 收到 `101`）；
- `rustls`（reqwest 0.12 直连主机侧）仍在握手阶段被服务端拒绝：
  `AlertReceived(HandshakeFailure)`；
- `danmuproxy.douyu.com:8601`（明文 TCP）在手机与桌面都能收到 `loginres`，
  桌面还能收到真实 `chatmsg`；帧格式与 WSS 完全一致。

结论：斗鱼弹幕代理只放行系统 TLS 栈，rustls 指纹风控在 Android/iOS 同样生效；
cookie 与此无关（TLS 握手先于任何业务头）。

## Decision

斗鱼弹幕在三端统一使用**明文 TCP** `tcp://danmuproxy.douyu.com:8601/`：

- `DouyuDanmakuArgs::connect_url()` 返回 `tcp://...`（不再返回 `wss://...`）；
- 新增 `slive_core::ws::tcp`：`TcpFrameSource` 按「4 字节小端全长（= 帧长 - 4）」切帧，
  处理半帧/粘包，单帧上限 1 MiB；`tcp::factory(url)` 供 FRB 桥与 `slive-cli` 复用；
- 删除斗鱼 WS 握手头（`connect_headers`）——TCP 不需要 UA / Origin / 子协议；
- 其余平台的 WSS 不受影响，仍按 ADR-013 的平台分层（桌面 `native-tls` / 移动 `rustls`）。

## Consequences

**正面**

- 三端斗鱼弹幕行为一致，彻底绕开 TLS ClientHello 指纹风控；
- 零 OpenSSL/NDK 构建成本，APK 体积与构建链路不变；
- 复用既有 STT 编解码、45s 心跳、`5s×5` 重连与会话主循环，无协议分叉。

**负面 / 已知限制**

- 斗鱼弹幕链路为明文（内容为公开弹幕；该 TCP 通道不承载账号凭证）；
- 依赖 8601 端口可用性（实测 8601/8602 均可用，8602 可作后备）；
- 桌面端不再使用 WSS，失去传输加密（接受：与移动端一致性优先）。

## Related ADRs

- **Supersedes**: ADR-013（全部）
- ADR-003（HTTP 仍为 rustls，不变）
- ADR-004（弹幕流推送链路不变，仅传输层变化）
