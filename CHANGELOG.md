# Changelog

All notable changes to this project will be documented in this file.

Format: Each version section starts with `## x.x.x`, followed by change lines starting with `-`.

---

## 1.9.1

- feat: 切台预取与 CDN 顺序缓存
- feat: 系统媒体控制（Windows SMTC / Linux MPRIS / Apple Now Playing）
- feat: 关注开播状态增量刷新，直播间继承进行中的刷新
- feat: 多播放格子加载态沿用播放器加载浮层
- feat: 直播间快捷键优化，Esc 统一返回
- feat: 核心解耦并新增 C ABI（ADR-016）
- fix: 修复抖音部分直播间反复缓冲
- fix: 修复 Android 端 mpv 内置 stats OSD 不可用
- fix: 修复 B 站登录入口悬空路由与缺失账号参数
- fix: 统一媒体控制与自动暂停的开关口径
- chore: media-kit 升级到 917d80ca（新 libmpv）

## 1.8.14

- fix: 进一步修正douyu断流问题
- tips: ios和macos用户请到action更新测试或者下载上游仓库版本

## 1.8.13

- feat: 支持自定义数据目录 (data_hive_ce) #174
- fix: douyu, 需要在配置douyu参数 说明 #182
- fix: 统一关注业务逻辑，修复tag数据混乱 #178
- fix: Windows屏幕亮度重置问题 #180
- 一些数据错误和潜在问题的修复
- 一些细节调整
- 关于linux的一系列修复 @pugaizai
- tips: ios和macos用户请到action更新测试或者下载上游仓库版本

## 1.8.12

- 基于v10811的热修版本：aur 以及 部分ui修复 #173
- feat: 允许按tag排序
- feat: 自由画面尺寸功能 #156
- feat: windows NVIDIA RTX VSR @ZhaiXB
- feat: 房间专属屏蔽词和屏蔽用户
- feat: PC端小窗记忆/开屏最大化
- feat: 弹幕随屏幕尺寸放缩
- feat: 允许禁用滑动调节亮度/音量
- feat: pc端参数启动应用
- fix: huya弹幕完整性
- 一些数据错误和潜在问题的修复
- 一些细节调整
- 关于linux的一系列修复 @pugaizai
- tips: ios和macos用户请到action更新测试或者下载上游仓库版本
