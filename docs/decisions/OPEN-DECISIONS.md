# OPEN-DECISIONS（悬而未决登记册）

> 规范：只追加 + 就地关闭（OPEN → RESOLVED，补 Resolution 字段）。
> 每次 Phase 开始时把未决项复现到工作上下文最前面。

| Date | Source | Open Item | Related Constraints | Current Leaning | Blocked By | Resolves When | Status |
|------|--------|-----------|---------------------|-----------------|------------|---------------|--------|
| 2026-10-17 | 合并前评审 / ADR-013 | **Android 斗鱼弹幕可用性**：移动端 WSS 走 rustls（ADR-013 保 NDK 零 C 依赖），若斗鱼弹幕服务器对 rustls 指纹的风控同样生效，Android 上斗鱼弹幕将失败 | ADR-013 / ADR-003 动机（移动端零 OpenSSL） | 先验证再决策：若失败优先评估 Android 切 native-tls（vendor openssl，接受构建成本） | 等 Android 真机验证 | Android 真机冒烟后 | OPEN |
| 2026-10-17 | 合并前评审 / AC-31 修订 | **编译期回退**：AC-31 现仅承诺「运行时回退」；「Rust 编译失败不阻断 App 构建」需条件依赖 / 可选 cargokit | ADR-001（cargokit 硬依赖）/ AC-31 | 本轮不做；如需，走「条件依赖 + 构建开关」方案 | 等真实诉求（如无 Rust 工具链的 CI 环境） | 有条件构建需求时 | OPEN |

## 已关闭

（暂无）
