# simple_live_tv_app 工作流程图

> 锚点：future `52466f96`（2026-10-21）｜TV v1.5.1+10501
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/workflow-diagram.md)｜对照：[simple_live_app](../../simple_live_app/doc/workflow-diagram.md)

## 1. 启动

```
main()
  → WidgetsFlutterBinding.ensureInitialized()
  → RustLib.init()                    # FFI 必须最早，先于任何 Site 调用
  → MediaKit.ensureInitialized()
  → Hive.initFlutter()
  → initServices()
       CoreLog 接管 → 注册 Hive Adapter →
       LocalStorage → DB → AppSettings →
       MigrationService → Sync/FollowUser/PlatformService
  → 强制横屏 + 全屏 + 文字缩放 1.0
  → runApp → ScreenUtil(1920x1080)
  → firstRun ? /agreement : /home
```

证据：`lib/main.dart:28-43`、`:97-127`；`lib/app/sites.dart:5-34`（4 个 `Rust*Site`）。

## 2. 页面导航

```
/agreement → /home
/home → 热门 /hot_live｜类目 /category → /category/detail｜搜索 /search/*
      → 记录 /history｜同步 /sync｜设置 /settings｜关注 /follow
列表/关注/记录 → 房间 /room/detail
/settings → 账号项 → /qr_login/qr_login（B站/斗鱼共用）
```

路由：`lib/routes/app_pages.dart`、`route_path.dart`、`app_navigation.dart`。

## 3. 进房与播放

```
LiveRoomPage → LiveRoomController.loadData()
  → getRoomDetail(roomId)            # Rust 绑定层
  → addHistory()
  → getPlayQualities(detail) → 选档
  → getPlayUrls(detail, quality)
  → player.open(Media(url, headers))
  → getDanmaku().start(detail.danmakuData)
  → 弹幕：屏蔽词过滤 → canvas_danmaku
```

- 换台：`↑` 上一频道 / `↓` 下一频道；`resetRoom()` 重载。
- 容错：`mediaEnd/mediaError` 原地重试 2 次 → 顺序切线路 → 全失败置 `liveStatus=false`。
- 未开播有录像：轮播录像。

证据：`lib/modules/live_room/live_room_controller.dart`、`live_room_page.dart`。

## 4. 遥控器焦点（TV 核心）

```
HighlightWidget
  FocusTraversalOrder(NumericFocusOrder) + Focus(focusNode)
  Obx(isFoucsed) → 放大 1.1 + 白底黑字 + 阴影
  arrowRight/Left/Up/Down → 可选回调，否则 ignored（默认空间导航）
  enter/select/space → onTap
```

| 按键（房间内） | 行为 |
| --- | --- |
| OK / Enter / Space | 显示/隐藏控制条 |
| Menu / M / → | 播放设置（清晰度/线路/比例/弹幕） |
| ← | 我的关注弹窗切台 |
| ↑ / ↓ | 上一/下一频道 |
| 返回 | 2 秒内双击退出 |

证据：`lib/widgets/highlight_widget.dart`、`lib/widgets/settings_item_widget.dart`、`lib/modules/live_room/live_room_page.dart`、`player/player_controls.dart`。

## 5. 账号扫码（B站/斗鱼共用）

```
选中账号项 → QRLoginController(siteId)
  → getQRCode() → 渲染二维码
  → 每 3 秒 getQRPollResult(key)
  → credential(JSON) → PlatformService.accountLogin
  → getAccountInfo → DB 落盘 + setSiteAttrs
  → 返回设置页
```

虎牙/抖音未实现扫码（core 抛 `UnimplementedError`），设置页显示「无需登录」。

## 6. 数据同步（仅接收端）

```
手机 → UDP 发现(23235) → TV HTTP 服务(23234)
  → /sync/follow、/sync/history、/sync/blocked_word、/sync/account/account
  → DB/设置落盘 → EventBus 刷新页面
SignalR 房间同步：signalr_service.dart（当前 connect 被注释）
```

## 7. 失败兜底

| 场景 | 行为 |
| --- | --- |
| 取流失败 | 错误 Toast；不崩溃 |
| 未开播 | 显示「未开播」或录像轮播提示 |
| 列表空/断网 | 空态/错误态可刷新 |
| 同步 siteId 不认识 | 设置页 `allSites[id]!` 会抛异常（backlog P1-4） |

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| TV 切 Rust FFI | `2465f9a3`、`f72bb417` |
| 账号/扫码 | `6da36e04`、`63197f69` |
| 知识库 | `ac7d8199` |
