# simple_live_app 工作流程图

> 锚点：future `3359b76e`（2026-10-26）｜App v1.8.15+10815
> 五件套：[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜[test-suite.md](./test-suite.md)
> 上游：[simple_live_core](../../simple_live_core/doc/workflow-diagram.md)｜播放：[media-kit](../../media-kit/doc/workflow-diagram.md)

## 1. 启动

```
main(args)
  → 桌面便携模式? exe 同级 data_hive_ce : getApplicationSupportDirectory()
  → WidgetsFlutterBinding → RustLib.init → MediaKit.ensureInitialized
  → Hive.initFlutter(path)
  → initServices()
       Adapters → PackageInfo → LocalStorage → DB →
       AppSettings → AppStyle → FollowService → SmartGroupService →
       Migration → PlatformService → Sync/History/FollowBlock →
       [桌面] WindowService → [Android] Firebase → CoreLog 接管
  → initLivePlaybackAudioHandler()
  → WindowService.init()（桌面，runApp 前）
  → 透明状态栏 + edgeToEdge → runApp
```

证据：`lib/main.dart`。顺序是契约：窗口在 `runApp` 前、后台 handler 在服务就位后。

## 2. 列表与分页

```
IndexedPage(PageView 4 Tab)
  → HomeController（每平台一个带 tag 的 HomeListController）
  → CategoryListController → CategoryDetailController
  → AppSearchController → SearchListController（按平台）｜AggregateSearchController（聚合）
  → core: getRecommendRooms / getCategoryRooms / searchRooms|searchAnchors
```

`BasePageController.canLoadMore`：

```
本页空 → false
serverHasMore == false → false
连续重复页 ≥ 2 → false
否则 → true
```

- 唯一切页触发：`AutoLoadOnScroll.autoLoadIfNeeded`（无 footer）。
- 短列表用 `fillViewportIfNeeded` 主动补页。
- 跨页按 `itemKey` 去重。
- 搜索**两条路径都回写** `serverHasMore = result.hasMore`（按平台自 `7b31c568`；聚合按站各自记水位）。
  旧文档写「搜索页不写 serverHasMore」是错的，本轮已更正。

### 2b. 聚合搜索（设置开关，默认关）

```
AppSearchController.onInit → Get.put(AggregateSearchController, tag: aggregate-search)
胶囊「房间/主播」→ 模式只存 AggregateSearchController.searchMode 一份
  → doSearch / onSearchModeChanged
  → startSearch|updateSearchMode：先 _invalidateInflightLoad（旧查询当前轮结束即止损）
    → _awaitPendingLoad 串行 → _beginQuery（清 list/_seen/失败计数）
  → getData：对仍 hasMore 的站点并发 searchRooms|searchAnchors
    → 逐站 nextPage 游标 · _takeFreshItems 跨站去重(itemKey) · _interleave 按站交错
    → 单站异常隔离：failedPages 连续 3 次该源退役；本轮失败源名写进底部重试条文案
    → serverHasMore = 还有任意源未退役
```

- 抖音在「主播」模式被 `_supports` 排除（不支持搜主播），不算失败。
- 部分源失败但有结果时不整页报错，只置 `loadMoreFailed` ＋ `loadMoreFailedText` 点名来源。
- 空输入框切模式：用控制器自己记的 `_keyword`（上次真正搜过的词）在新模式下重搜，不是读输入框文本。

## 3. 进房/播放

```
AppNavigator.toLiveRoomDetail(site, roomId, together?)
  → LiveRoomController.onInit → loadData()
  → getRoomDetail → addHistory → getSuperChat / getPlayQualities
  → 选档（蜂窝另读 qualityLevelCellular）
  → getPlayUrls → playUrls/playHeaders
  → initializePlayer → player.open(Playlist)
  → getDanmaku().start(danmakuData)
  → 每 500ms(+tile*125ms) DanmakuMask.allowListBatch/mergeListBatch → canvas_danmaku
```

| 环节 | 要点 |
| --- | --- |
| 清晰度 | 2/1/0 = 最高/中/最低 |
| 线路 | `changePlayLine` → `player.jump` |
| 断流 | 原地重试 2 次 → 逐条换线 → 全断判定下播 |
| 头部 | `Media(url, httpHeaders: playHeaders)` |
| 缓存 | `buildLiveCacheProperties` 一次组表再逐条 `setProperty`；Android 关双重缓冲＝**空表**（留在内核默认值）；Twitch 预读 `kTwitchPlayerCacheSecs`(10) |
| 斗鱼 | 直链经本地 `StreamRelayService` 转发，到期按 FLV tag 接续 |
| 窗口 | 全屏/小窗/最大化；「谁先离开窗口态谁捕获还原点」 |

## 4. 多开

```
入口：路由 together / 关注行「加入」/ 关注点选 / 开关
  → addRoom → 已在会话? focus : 上限 4? 提示 : _createTile
  → attachHostSession + Get.put(tag: multi_tile_$id)
  → resolveMultiPlayLayout（纯函数）→ 网格
```

- 格子位置只跟加入顺序；焦点只改高亮与音量。
- 音量为纯函数：总音量 × 压低系数 × 本格系数。
- 副格不碰窗口/后台通知/自动关闭。
- 移出一律在网格点 ✕；关注行只负责「加入」。

## 5. 后台播放（仅主格，移动端）

```
player.stream.playing/buffering/completed
  → syncBackgroundPlayback（唯一入口）
  → LivePlaybackAudioHandler
  → LiveAudioSession（焦点/中断/耳机）
  → Android 通知+前台服务 / iOS 锁屏
远程指令 → playbackPlay/Pause/Stop → LivePlaybackTarget
退出/换台 → detach（摘通知）
```

- 与「进入后台自动暂停」互斥。
- handler 跑在主 isolate；桌面直接返回。
- 副格永不挂载。

## 6. 同步

```
局域网：UDP 23235 发现 + shelf HTTP 23234
  → /sync/follow /tag /history /blocked_word /account/account
WebDAV：资源注册 + 执行器（follow/block/history/settings/account）
SignalR 房间：建房/加房（QR）
  → DBService / accountBox → EventBus 刷新页面
```

关注列表按墓碑/时间合并；分组成员表按**组名并集**合并。

## 7. 账号

```
我的 → 平台配置 → 已登录? logout : 登录弹层
  → 扫码 / WebView / Cookie
  → PlatformService.accountLogin
  → core.getAccountInfo → DB accountBox → setSiteAttrs(JSON)
  → EventBus(kUpdateAccount)
```

B站是否登录现查 DB，不缓存 UI 布尔。

## 8. 关注页（三栏 + 分组胶囊）

```
三栏：导航（标签） | FollowSidebar | 内容
标签 = 过滤器（全部/直播中/未开播/自定义分组）
内容项：封面左上分组胶囊（首个 +N，未分组不显示）
搜索：顶栏原位展开；展开时收起刷新按钮
刷新：期间增量重排，整轮结束只排序一次
平台分类：改为设置开关（不再占据主页）
```

归属真源仍是 `FollowUserTag.userId` 成员表；「加入」不是「移动」。

## 9. 快捷键（默认）

`Space` 播放/暂停｜`F` 全屏｜`Esc` 关弹窗→退全屏/小窗→离开｜`D` 弹幕｜`P` 小窗｜`M` 静音｜`S` 截图｜`L` 锁条｜`R` 刷新｜`Q` 清晰度｜`G` 换台｜`↑↓` 音量｜`←→` 线路｜`1-4` 聚焦多开格。可改键，动作只派发到既有入口。

## 10. 通用约定

1. 所有 core 调用经 `Sites.allSites[siteId].liveSite`。
2. `EventBus` 订阅必须在 `onClose` 取消。
3. 一个直播间 = 一个 `LiveRoomController`；多开是 N 份带 tag 实例。
4. `hasMore` 只采信 core，不重算。

## 历史锚点

| 流程 | 关键提交 |
| --- | --- |
| Rust 桥/五平台直连 | `73e80b1e`、`f72bb417` |
| 列表分页/自动加载 | `e1f7a75c`、`4e3c35a1` |
| 进房/播放/多开 | `fcb43a82`、`afd18194`、`08fb5a74`、`49bfb83e`、`9a3f1313` |
| 后台播放 | `e374b4df`、`5692db16`、`cd89ecdc`、`cbb474ee` |
| 关注页三栏/胶囊/搜索 | `1c0d02f5`、`0d2f57e6`、`55928d21`、`b5718dd8`、`52466f96` |
| 屏幕常亮 | `900f8d50` |
| 账号 | `63197f69`（校验失败不抹凭证） |
| 弹幕表情 | `4287a2d8`、`953f78b7`（core 侧） |
| 聚合搜索（并发/交错/失败隔离/单一真值） | `446d613f`、`3624927b`、`8947bcdc` |
| 播放缓存组表与 Twitch 预读 | `0e99306a`、`c1dd7769` |
| 按平台搜索回写 serverHasMore（更正旧文档误记） | `7b31c568` |
| 聊天「最新」按钮与自动跟随共用 `resumeChatFollow` | `3359b76e` |
